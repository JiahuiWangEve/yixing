"""Small real-Web airdrop gate: clicks, touch drag, recovery, and sacrifice loss.

Only ordinary saved games are seeded. Imported chapter helpers are read-only;
its fixture matrix and output paths are never changed. --validate-only launches
no browser. Fresh contexts install each fixture exactly once, so reload cannot
silently reset the tested recovery state.
"""
import argparse
import asyncio
import hashlib
import json
import os
import shutil
import time

from playwright.async_api import async_playwright
from browser_chapter_checks import ROOT, URL, KEY, assert_rendered, boot, parse_save as chapter_save, variant_json

OUT = ROOT / 'verification/v0.14.1/airdrop'
MATRIX = {('survive_recovery', 1280), ('survive_recovery', 390), ('one_life_general_kill', 390)}


def parse_save(text):
    result = chapter_save(text)
    route = variant_json(text.split('\nroute=', 1)[1].split('\nbattle=', 1)[0])
    battle = variant_json(text.split('\nbattle=', 1)[1].rsplit('\nscreen=', 1)[0])
    result['victory_recorded'] = route['victory_recorded']
    for key in ['airdrop_recovery_turn', 'basic_used', 'card_move_used']:
        result[key] = battle[key]
    result['recovery_active'] = battle['airdrop_recovery_turn'] > 0 and battle['turn'] == battle['airdrop_recovery_turn']
    return result


def validate():
    replays = json.loads((OUT / 'replays.json').read_text())
    assert len(replays) == len(MATRIX) and {(r['name'], int(r['viewport'][0])) for r in replays} == MATRIX
    actions = set()
    for replay in replays:
        assert parse_save((OUT / 'fixtures' / replay['fixture']).read_text()) == replay['initial'], replay['fixture']
        uw, uh = replay['logical_size']
        points = [replay['resume']]
        for step in replay['steps']:
            assert step['kind'] in {'action', 'blocked', 'reload'}
            assert isinstance(step['wait_ms'], int) and step['wait_ms'] >= 100
            for action in step['inputs']:
                actions.add(action['action'])
                assert action['action'] in {'tap', 'drag', 'key'}
                if action['action'] == 'key':
                    assert action['key'] == 'Space'
                else:
                    points.extend([action['from'], action['to']] if action['action'] == 'drag' else [action['point']])
        for x, y in points:
            assert 0 <= x < uw and 0 <= y < uh, (replay['fixture'], 'out-of-bounds input', [x, y])
        final = replay['steps'][-1]['expected']
        if replay['name'] == 'survive_recovery':
            assert final['turn'] == 3 and final['lives'] == 3 and not final['recovery_active']
            assert final['player'] == [5, 6] and 'airdrop' not in final['hand'] + final['deck'] + final['discard']
        else:
            assert final['phase'] == 'dead' and final['lives'] == 0 and not final['victory_recorded']
            assert not final['rewards'] and not any(e['kind'] == 'g' for e in final['enemies'])
    assert actions == {'tap', 'drag', 'key'}, 'Missing real input path'
    return replays


async def main(validate_only=False):
    replays = validate()
    if validate_only:
        print(json.dumps({'validated_fixtures': len(replays), 'state_assertions': sum(len(r['steps']) + 1 for r in replays),
                          'rendered': False, 'manifest_sha256': hashlib.sha256((OUT / 'replays.json').read_bytes()).hexdigest()}))
        return
    output = OUT / 'browser'
    output.mkdir(parents=True, exist_ok=True)
    reports = []
    started = time.monotonic()
    async with async_playwright() as p:
        executable = os.environ.get('CHROMIUM_PATH') or shutil.which('chromium')
        browser = await p.chromium.launch(**({'executable_path': executable} if executable else {}), headless=True, args=['--no-sandbox'])
        try:
            for replay in replays:
                w, h = map(int, replay['viewport']);uw, uh = replay['logical_size']
                scale = min(w / uw, h / uh);ox, oy = (w - uw * scale) / 2, (h - uh * scale) / 2
                context = await browser.new_context(viewport={'width': w, 'height': h}, has_touch=True)
                page = await context.new_page();cdp = await context.new_cdp_session(page)
                errors = [];screenshots = []
                page.on('pageerror', lambda e: errors.append(str(e)))
                page.on('console', lambda m: errors.append(m.text) if m.type == 'error' and ('SCRIPT ERROR' in m.text or 'Parse Error' in m.text) else None)
                stem = replay['fixture'].removesuffix('.cfg')
                def screen_point(pos): return {'x': ox + pos[0] * scale, 'y': oy + pos[1] * scale}
                async def tap(pos):
                    xy = screen_point(pos);await page.touchscreen.tap(xy['x'], xy['y'])
                async def drag(start, end):
                    a, b = screen_point(start), screen_point(end)
                    await cdp.send('Input.dispatchTouchEvent', {'type': 'touchStart', 'touchPoints': [{**a, 'id': 1}]})
                    for fraction in [.2, .4, .6, .8, 1]:
                        point = {key: a[key] + (b[key] - a[key]) * fraction for key in ['x', 'y']}
                        await cdp.send('Input.dispatchTouchEvent', {'type': 'touchMove', 'touchPoints': [{**point, 'id': 1}]})
                        await page.wait_for_timeout(35)
                    await cdp.send('Input.dispatchTouchEvent', {'type': 'touchEnd', 'touchPoints': []})
                async def snapshot(): return parse_save(await page.evaluate('(key)=>localStorage.getItem(key)', KEY))
                async def expect(expected, label):
                    deadline = time.monotonic() + 8
                    while True:
                        actual = await snapshot()
                        if actual == expected: return
                        assert time.monotonic() < deadline, (stem, label, actual, expected)
                        await page.wait_for_timeout(80)
                async def screenshot(label):
                    path = output / f'{stem}-{label}.png';data = await page.screenshot(path=str(path))
                    assert_rendered(data, [w, h]);screenshots.append({'file': path.name, 'sha256': hashlib.sha256(data).hexdigest()})
                async def resume():
                    await tap(replay['resume']);await page.wait_for_timeout(350)
                try:
                    # This one-time flag is scoped to the fresh browser context.
                    # The reload test keeps the current save, never the fixture.
                    fixture = (OUT / 'fixtures' / replay['fixture']).read_text()
                    await page.add_init_script('''if (!sessionStorage.getItem('airdrop-qa-installed')) {
                        localStorage.setItem(%s, %s);sessionStorage.setItem('airdrop-qa-installed','1');
                    }''' % (json.dumps(KEY), json.dumps(fixture)))
                    await page.goto(URL);await boot(page);await resume()
                    await expect(replay['initial'], 'initial');await screenshot('initial')
                    for number, step in enumerate(replay['steps']):
                        if step['kind'] == 'reload':
                            await page.reload();await boot(page);await resume()
                        else:
                            for action in step['inputs']:
                                if action['action'] == 'tap': await tap(action['point'])
                                elif action['action'] == 'drag': await drag(action['from'], action['to'])
                                else: await page.keyboard.press(action['key'])
                                await page.wait_for_timeout(100)
                            # Native driver records the real fx/input lock before
                            # clearing effects, plus a 100 ms presentation margin.
                            # Save equality alone cannot replace this boundary.
                            await page.wait_for_timeout(max(step['wait_ms'], 250 if step['kind'] == 'blocked' else 0))
                        await expect(step['expected'], step['label'])
                        await screenshot(str(number) + '-' + step['label'])
                    assert not errors, (stem, errors)
                    reports.append({'fixture': replay['fixture'], 'viewport': [w, h], 'state_assertions': len(replay['steps']) + 1,
                                    'errors': errors, 'screenshots': screenshots, 'final': await snapshot()})
                    print('PASS airdrop', stem, len(replay['steps']) + 1, 'state checks', flush=True)
                except Exception:
                    await page.screenshot(path=str(output / f'{stem}-failure.png'));raise
                finally:
                    await cdp.detach();await context.close()
        finally:
            await browser.close()
    result = {'replays': len(reports), 'state_assertions': sum(r['state_assertions'] for r in reports),
              'errors': sum(len(r['errors']) for r in reports), 'elapsed_seconds': round(time.monotonic() - started, 3), 'cases': reports}
    (output / 'results.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({k: v for k, v in result.items() if k != 'cases'}))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--validate-only', action='store_true', help='Validate saves, matrix, and UI inputs without launching Chromium')
    asyncio.run(main(parser.parse_args().validate_only))
