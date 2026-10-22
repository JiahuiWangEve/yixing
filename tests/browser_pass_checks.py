from browser_settings import install_debug_settings
"""Production-Web pass-card gate with held side-zone highlight evidence.

Default/--smoke runs desktop and portrait only; --full adds narrow portrait and
landscape. Seeds ordinary route saves once per fresh context. All gameplay uses
real browser touch events (including CDP touchCancel/multitouch), never runtime
debug hooks. Captures the highlighted zone while the first touch is still held.
"""
import argparse
import asyncio
import hashlib
import io
import json
import os
import shutil
import time

from PIL import Image
from playwright.async_api import async_playwright
from browser_chapter_checks import ROOT, URL, KEY, assert_rendered, boot, parse_save as chapter_save, variant_json

OUT = ROOT / 'verification/v0.14.5/pass'
MATRIX = {(1280, 940), (390, 844), (360, 780), (844, 390)}
EXTRA_BATTLE = ['airdrop_recovery_turn', 'basic_used', 'card_move_used', 'free_card_uid', 'hand_ids',
                'next_card_uid', 'active_displacements', 'shield_charges', 'pending_bleeds', 'reload_ready',
                'artillery_mode', 'deploy_draw_used', 'tuna_turns', 'tuna_active']


def parse_save(text):
    result = chapter_save(text)
    route = variant_json(text.split('\nroute=', 1)[1].split('\nbattle=', 1)[0])
    battle = variant_json(text.split('\nbattle=', 1)[1].rsplit('\nscreen=', 1)[0])
    result['victory_recorded'] = route['victory_recorded']
    result.update({key: battle[key] for key in EXTRA_BATTLE})
    return result


def validate():
    replays = json.loads((OUT / 'replays.json').read_text())
    assert len(replays) == len(MATRIX) and {tuple(r['viewport']) for r in replays} == MATRIX
    for replay in replays:
        assert parse_save((OUT / 'fixtures' / replay['fixture']).read_text()) == replay['initial'], replay['fixture']
        uw, uh = replay['logical_size'];points = [replay['resume']]
        previous = replay['initial'];labels = set()
        for step in replay['steps']:
            labels.add(step['label'])
            assert step['kind'] in {'action', 'blocked', 'reload'}
            assert step['wait_ms'] >= 100
            if step['kind'] == 'blocked':
                assert step['expected'] == previous, (replay['fixture'], step['label'], 'blocked action mutates state')
            for action in step['inputs']:
                assert action['action'] in {'tap', 'drag'}
                if action['action'] == 'drag':
                    assert action['mode'] in {'release', 'cancel', 'multitouch'}
                    assert action['highlight'] in {'allowed', 'blocked'}
                    points.extend(action[key] for key in ['from', 'preview', 'to', 'second'])
                else: points.append(action['point'])
            previous = step['expected']
        assert labels == {'cancel-held-drag-keeps-card', 'pass-consumable-draws-one-no-effect',
                          'insufficient-energy-no-change', 'zero-cost-pass-multitouch-once',
                          'free-card-pass-keeps-basic-quota', 'reload-preserves-free-card-removal',
                          'basic-move-still-available', 'unaffordable-generated-pass-no-change',
                          'next-turn-before-printed-zero-pass', 'next-turn-before-generated-pass'}
        for x, y in points: assert 0 <= x < uw and 0 <= y < uh, (replay['fixture'], 'out-of-bounds input', [x, y])
        final = replay['steps'][-1]['expected']
        assert final['free_card_uid'] == 0 and final['basic_used'] and final['energy'] == 0
        assert final['player'] == [5, 9] and final['hand'][:4] == ['spear', 'sword', 'spear', 'fatigue'] and len(final['hand']) == 5
        assert not final['discard'] and len(final['deck']) == 1 and final['hand'][-1] in ['airdrop', 'breath']
        assert final['lives'] == 3 and final['airdrop_recovery_turn'] == 0
        assert final['enemies'][0]['hp'] == replay['initial']['enemies'][0]['hp'], 'Pass should never damage enemies'
        assert final['turn'] == 3
    return replays


def border_color_count(data, box, target, thickness, tolerance=25):
    """Measure the production zone's outline, not merely a moving card's center."""
    image = Image.open(io.BytesIO(data)).convert('RGB')
    x0, y0, x1, y1 = box
    pixels = image.load();count = 0
    for y in range(max(0, y0), min(image.height, y1)):
        for x in range(max(0, x0), min(image.width, x1)):
            if min(x - x0, x1 - 1 - x, y - y0, y1 - 1 - y) > thickness: continue
            if max(abs(pixels[x, y][i] - target[i]) for i in range(3)) < tolerance: count += 1
    return count


async def main(full=False, validate_only=False):
    replays = validate()
    selected = replays if full else [r for r in replays if r['viewport'][0] in [1280, 390]]
    if validate_only:
        print(json.dumps({'validated_fixtures': len(replays), 'selected_replays': len(selected),
                          'state_assertions': sum(len(r['steps']) + 1 for r in selected), 'rendered': False,
                          'manifest_sha256': hashlib.sha256((OUT / 'replays.json').read_bytes()).hexdigest()}))
        return
    output = OUT / ('browser' if full else 'smoke');output.mkdir(parents=True, exist_ok=True)
    reports = [];started = time.monotonic()
    async with async_playwright() as p:
        executable = os.environ.get('CHROMIUM_PATH') or shutil.which('chromium')
        browser = await p.chromium.launch(**({'executable_path': executable} if executable else {}),
                                          headless=True, args=['--no-sandbox'])
        try:
            for replay in selected:
                w, h = map(int, replay['viewport']);uw, uh = replay['logical_size']
                scale = min(w / uw, h / uh);ox, oy = (w - uw * scale) / 2, (h - uh * scale) / 2
                context = await browser.new_context(viewport={'width': w, 'height': h}, has_touch=True)
                page = await context.new_page();await install_debug_settings(page);cdp = await context.new_cdp_session(page)
                errors = [];screenshots = [];highlights = [];events = [];overlays = []
                page.on('pageerror', lambda error: errors.append(str(error)))
                page.on('console', lambda msg: errors.append(msg.text) if msg.type == 'error' and
                        ('SCRIPT ERROR' in msg.text or 'Parse Error' in msg.text) else None)
                stem = replay['fixture'].removesuffix('.cfg')
                def screen_point(pos): return {'x': ox + pos[0] * scale, 'y': oy + pos[1] * scale}
                async def send_touch(kind, points):
                    events.append({'type': kind, 'points': len(points)})
                    await cdp.send('Input.dispatchTouchEvent', {'type': kind, 'touchPoints': points})
                async def tap(pos):
                    xy = screen_point(pos);await page.touchscreen.tap(xy['x'], xy['y'])
                async def snapshot(): return parse_save(await page.evaluate('(key)=>localStorage.getItem(key)', KEY))
                async def expect(expected, label):
                    deadline = time.monotonic() + 8
                    while True:
                        actual = await snapshot()
                        if actual == expected: return
                        assert time.monotonic() < deadline, (stem, label, actual, expected)
                        await page.wait_for_timeout(80)
                async def screenshot(label, **metadata):
                    path = output / f'{stem}-{label}.png';data = await page.screenshot(path=str(path))
                    assert_rendered(data, [w, h])
                    screenshots.append({'file': path.name, 'sha256': hashlib.sha256(data).hexdigest(), **metadata})
                    return data
                async def visible_zone(label):
                    data = await screenshot(label, selected_or_held=True)
                    zx, zy, zw, zh = replay['zone']
                    box = tuple(round(v) for v in [ox+zx*scale, oy+zy*scale, ox+(zx+zw)*scale, oy+(zy+zh)*scale])
                    count = border_color_count(data, box, (252,249,241), max(w,h), tolerance=6)
                    assert count > (box[2]-box[0])*(box[3]-box[1])*.15, (stem,label,'shared discard zone is not visible',count)
                    overlays.append({'label':label,'button_fill_pixels':count})
                async def resume():
                    await tap(replay['resume']);await page.wait_for_timeout(400)
                async def drag(action, label, expected_before):
                    a, preview, b = [screen_point(action[key]) for key in ['from', 'preview', 'to']]
                    await send_touch('touchStart', [{**a, 'id': 1}]);await page.wait_for_timeout(350)
                    await visible_zone(label + '-held-before-drag')
                    for fraction in [.25, .5, .75, 1]:
                        xy = {key: a[key] + (preview[key] - a[key]) * fraction for key in ['x', 'y']}
                        await send_touch('touchMove', [{**xy, 'id': 1}]);await page.wait_for_timeout(30)
                    await page.wait_for_timeout(80)
                    unhovered = await screenshot(label + '-zone-before-hover', touch_held=True, zone_hovered=False)
                    await send_touch('touchMove', [{**b, 'id': 1}]);await page.wait_for_timeout(120)
                    held = await screenshot(label + '-held-highlight-before-release', touch_held=True,
                                            zone_hovered=True, allowed=action['highlight'] == 'allowed')
                    # No release has happened when this screenshot and save check run.
                    assert events[-1]['type'] == 'touchMove'
                    assert await snapshot() == expected_before, (stem, label, 'Card committed before finger release')
                    zx, zy, zw, zh = replay['zone']
                    box = tuple(round(v) for v in [ox + zx * scale, oy + zy * scale,
                                                   ox + (zx + zw) * scale, oy + (zy + zh) * scale])
                    target = (56, 105, 95) if action['highlight'] == 'allowed' else (166, 56, 45)
                    thickness = max(4, round(6 * scale))
                    before_count = border_color_count(unhovered, box, target, thickness)
                    held_count = border_color_count(held, box, target, thickness)
                    assert held_count >= before_count + 12, (stem, label, 'No visible highlighted zone outline', before_count, held_count)
                    highlights.append({'label': label, 'allowed': action['highlight'] == 'allowed',
                                       'before_outline_pixels': before_count, 'held_outline_pixels': held_count,
                                       'captured_before_release': True})
                    if action['mode'] == 'multitouch':
                        second = {**screen_point(action['second']), 'id': 2}
                        await send_touch('touchStart', [{**b, 'id': 1}, second])
                        await send_touch('touchEnd', [{**b, 'id': 1}])
                        await page.wait_for_timeout(100)
                        assert await snapshot() == expected_before, (stem, label, 'Second finger prematurely commits first finger')
                    await send_touch('touchCancel' if action['mode'] == 'cancel' else 'touchEnd', [])
                try:
                    fixture = (OUT / 'fixtures' / replay['fixture']).read_text()
                    await page.add_init_script('''if (!sessionStorage.getItem('pass-qa-installed')) {
                        localStorage.setItem(%s, %s);sessionStorage.setItem('pass-qa-installed','1');
                    }''' % (json.dumps(KEY), json.dumps(fixture)))
                    await page.goto(URL);await boot(page);await resume()
                    await expect(replay['initial'], 'initial');await screenshot('initial')
                    previous = replay['initial']
                    for number, step in enumerate(replay['steps']):
                        label = str(number) + '-' + step['label']
                        if step['kind'] == 'reload':
                            await page.reload();await boot(page);await resume()
                        else:
                            for action in step['inputs']:
                                if action['action'] == 'tap':
                                    await tap(action['point'])
                                    if action.get('selected_zone'):
                                        await page.wait_for_timeout(100)
                                        await visible_zone(label + '-selected-before-commit')
                                        assert await snapshot() == previous, (stem,label,'selection committed before zone click')
                                else: await drag(action, label, previous)
                                await page.wait_for_timeout(100)
                            # For unchanged-state assertions, cross a complete
                            # production autosave boundary so stale localStorage
                            # cannot hide a late duplicate/canceled commit.
                            await page.wait_for_timeout(max(step['wait_ms'], 1150 if step['kind'] == 'blocked' else 0))
                        await expect(step['expected'], step['label']);await screenshot(label + '-settled')
                        previous = step['expected']
                    await page.wait_for_timeout(1150)
                    await expect(previous, 'no-delayed-duplicate-commit')
                    assert not errors, (stem, errors)
                    assert any(e['type'] == 'touchCancel' for e in events)
                    if w < 1000: assert any(e['points'] == 2 for e in events)
                    reports.append({'fixture': replay['fixture'], 'viewport': [w, h],
                                    'state_assertions': len(replay['steps']) + 2, 'errors': errors,
                                    'screenshots': screenshots, 'highlights': highlights, 'selection_and_hold_overlays': overlays,
                                    'touch_events': events, 'final': await snapshot()})
                    print('PASS pass-cards', stem, len(replay['steps']) + 2, 'state checks;',
                          len(highlights), 'held highlight checks', flush=True)
                except Exception:
                    await page.screenshot(path=str(output / f'{stem}-failure.png'));raise
                finally:
                    await cdp.detach();await context.close()
        finally:
            await browser.close()
    result = {'mode': 'full' if full else 'smoke', 'replays': len(reports),
              'state_assertions': sum(r['state_assertions'] for r in reports),
              'highlight_assertions': sum(len(r['highlights']) for r in reports),
              'errors': sum(len(r['errors']) for r in reports),
              'elapsed_seconds': round(time.monotonic() - started, 3), 'cases': reports}
    (output / 'results.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({key: value for key, value in result.items() if key != 'cases'}), flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--smoke', action='store_true', help='Quick desktop/portrait gate (default)')
    mode.add_argument('--full', action='store_true', help='Also test small portrait and mobile landscape')
    parser.add_argument('--validate-only', action='store_true', help='Validate all saves and replay coordinates without Chromium')
    args = parser.parse_args()
    asyncio.run(main(args.full, args.validate_only))
