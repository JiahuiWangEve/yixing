"""Replay chapter two through the exported Web UI, using ordinary saved games.

Generate tests/chapter_web_fixtures.gd before export. JavaScript only writes the
initial save and reads subsequent saves; gameplay uses touchscreen input. The
--smoke mode is a two-viewport release gate, not the full rendered regression.
"""
import argparse
import asyncio
import hashlib
import io
import json
import os
import re
import shutil
from pathlib import Path

from PIL import Image, ImageChops, ImageStat
from playwright.async_api import async_playwright

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'verification/v0.14.0/chapter'
URL = os.environ.get('YIXING_TEST_URL', 'http://127.0.0.1:8765')
KEY = 'yixing.route_run.v0100'
ROUTE_FIELDS = ['chapter', 'current', 'pending', 'visited', 'done', 'prepared',
                'reward_debt', 'reward_blocked', 'pending_homework', 'homework_awarded']
BATTLE_FIELDS = ['phase', 'turn', 'lives', 'energy', 'collection', 'deck', 'hand',
                 'discard', 'rewards', 'player', 'encounter_state']
SMOKE_NAMES = {'chapter_transition', 'final_boss'}
MATRIX = {
    'chapter_transition': {1280, 390},
    'final_boss': {1280, 390},
    'chapter_map': {390, 360, 844},
    'revival': {390, 360, 844},
    'reinforcement': {390, 360, 844},
    'general_guard': {390},
}


def variant_json(text):
    return json.loads(re.sub(r'\bVector2i?\(([^()]*)\)', r'[\1]', text).replace('&"', '"'))


def parse_save(text):
    assert isinstance(text, str) and '\nroute=' in text and '\nbattle=' in text, 'Missing save'
    route = variant_json(text.split('\nroute=', 1)[1].split('\nbattle=', 1)[0])
    battle = variant_json(text.split('\nbattle=', 1)[1].rsplit('\nscreen=', 1)[0])
    result = {'screen': re.search(r'^screen="(\w+)"', text, re.M).group(1)}
    result.update({key: route[key] for key in ROUTE_FIELDS})
    result.update({key: battle[key] for key in BATTLE_FIELDS})
    result['encounters'] = [node['encounter'] for node in route['nodes']]
    result['enemies'] = [{key: value for key, value in enemy.items() if key != 'visual'}
                         for enemy in battle['enemies']]
    return result


def image_difference(before, after):
    a = Image.open(io.BytesIO(before)).convert('RGB')
    b = Image.open(io.BytesIO(after)).convert('RGB')
    assert a.size == b.size
    return sum(ImageStat.Stat(ImageChops.difference(a, b)).mean) / 3


def assert_rendered(data, expected_size):
    image = Image.open(io.BytesIO(data)).convert('RGB')
    assert image.size == tuple(expected_size), ('Wrong screenshot size', image.size, expected_size)
    assert sum(ImageStat.Stat(image).stddev) > 30, 'Blank or effectively solid-color game canvas'


async def boot(page):
    await page.wait_for_function("!document.getElementById('status')", timeout=60000)
    await page.wait_for_timeout(350)


async def main(smoke=False, validate_only=False):
    output = OUT / ('smoke' if smoke else 'browser')
    output.mkdir(parents=True, exist_ok=True)
    replays = json.loads((OUT / 'replays.json').read_text())
    expected = {(name, width) for name, widths in MATRIX.items() for width in widths}
    actual = {(replay['name'], int(replay['viewport'][0])) for replay in replays}
    assert actual == expected and len(replays) == len(expected), 'Incomplete or duplicate chapter fixture matrix'
    # Validate all fixture envelopes even in the small gate. Generation and browser
    # must agree on the save schema; missing entries cannot silently shrink coverage.
    for replay in replays:
        fixture = OUT / 'fixtures' / replay['fixture']
        assert parse_save(fixture.read_text()) == replay['initial'], ('Fixture decode mismatch', fixture.name)
        for step in replay['steps']:
            assert step['kind'] in {'tap', 'enter', 'combat', 'reload', 'panel', 'close_panel'}
            assert step['expected']['chapter'] in {1, 2}
    selected = [r for r in replays if not smoke or r['name'] in SMOKE_NAMES]
    assert len(selected) == (4 if smoke else len(expected)), 'Wrong selected chapter coverage'
    for replay in replays:
        uw, uh = replay['logical_size']
        for point in [replay['resume']] + [pos for step in replay['steps'] for pos in step['taps']]:
            assert len(point) == 2 and 0 <= point[0] < uw and 0 <= point[1] < uh, (
                replay['fixture'], 'Input coordinate outside logical viewport', point)
    if validate_only:
        print(json.dumps({'validated_fixtures': len(replays), 'selected_replays': len(selected),
                          'selected_state_assertions': sum(len(r['steps']) + 1 for r in selected),
                          'rendered': False,
                          'manifest_sha256': hashlib.sha256((OUT / 'replays.json').read_bytes()).hexdigest()}))
        return
    reports = []
    async with async_playwright() as p:
        executable = os.environ.get('CHROMIUM_PATH') or shutil.which('chromium')
        browser = await p.chromium.launch(**({'executable_path': executable} if executable else {}),
                                          headless=True, args=['--no-sandbox'])
        try:
            for replay in selected:
                w, h = map(int, replay['viewport'])
                uw, uh = replay['logical_size']
                scale = min(w / uw, h / uh)
                ox, oy = (w - uw * scale) / 2, (h - uh * scale) / 2
                context = await browser.new_context(viewport={'width': w, 'height': h}, has_touch=True)
                page = await context.new_page()
                errors = []
                page.on('pageerror', lambda error: errors.append(str(error)))
                page.on('console', lambda msg: errors.append(msg.text) if msg.type == 'error' and
                        ('SCRIPT ERROR' in msg.text or 'Parse Error' in msg.text) else None)
                stem = replay['name'] + '-' + str(w)
                screenshots = []
                panel_before = None
                saved_steps = []

                async def tap(pos):
                    x, y = ox + pos[0] * scale, oy + pos[1] * scale
                    assert 0 <= x < w and 0 <= y < h, (stem, 'Tap outside viewport', pos, [x, y])
                    await page.touchscreen.tap(x, y)
                    await page.wait_for_timeout(160)

                async def resume():
                    await tap(replay['resume'])
                    await page.wait_for_timeout(350)

                async def snapshot():
                    return parse_save(await page.evaluate('(key)=>localStorage.getItem(key)', KEY))

                async def await_saved_state(expected, label):
                    # A successful UI transition can precede its synchronous save
                    # on a busy CI main thread. The previous fixed 1050 ms read
                    # caught the old map save even though its failure screenshot
                    # already showed the correctly entered chapter-two battle.
                    # Never resend input: wait for the complete original expected
                    # state, and retain the strict assertion on timeout.
                    loop = asyncio.get_running_loop()
                    started = loop.time()
                    deadline = started + 12
                    while True:
                        observed = await snapshot()
                        if observed == expected:
                            saved_steps.append({'label': label, 'save_wait_ms': round((loop.time() - started) * 1000, 1)})
                            return observed
                        assert loop.time() < deadline, (stem, label, observed, expected)
                        await page.wait_for_timeout(80)

                async def screenshot(label):
                    path = output / f'{stem}-{label}.png'
                    data = await page.screenshot(path=str(path))
                    assert_rendered(data, [w, h])
                    screenshots.append({'file': path.name, 'sha256': hashlib.sha256(data).hexdigest()})
                    return data

                try:
                    # Seed exactly once. Reload and Continue must preserve progress,
                    # unlike an init script which would reset the fixture on reload.
                    await page.goto(URL)
                    await boot(page)
                    await page.evaluate('([key,value])=>localStorage.setItem(key,value)',
                                        [KEY, (OUT / 'fixtures' / replay['fixture']).read_text()])
                    await page.reload()
                    await boot(page)
                    await resume()
                    await await_saved_state(replay['initial'], 'initial')
                    await screenshot('initial')
                    for number, step in enumerate(replay['steps']):
                        if step['kind'] == 'reload':
                            await page.reload()
                            await boot(page)
                            await resume()
                        else:
                            if step['kind'] == 'panel':
                                panel_before = await page.screenshot()
                            for pos in step['taps']:
                                await tap(pos)
                            # Preserve the existing animation/input-lock settle
                            # window. Save equality alone is not an animation or
                            # input-readiness signal, especially after Continue.
                            await page.wait_for_timeout(step.get('wait_ms', 1800 if step['kind'] == 'combat' else
                                                                  1050 if step['kind'] == 'enter' else 350))
                        observed = await await_saved_state(step['expected'], step['label'])
                        assert observed == step['expected'], (stem, number, step['label'], observed, step['expected'])
                        capture = await screenshot(str(number) + '-' + step['label'])
                        if step['kind'] == 'panel':
                            assert image_difference(panel_before, capture) > 5, (stem, 'Rules panel did not visibly open')
                        if step['kind'] == 'close_panel':
                            assert panel_before is not None
                            assert image_difference(panel_before, capture) < 5, (stem, 'Rules panel did not visibly close')
                    assert not errors, (stem, errors)
                    reports.append({'fixture': replay['fixture'], 'viewport': [w, h],
                                    'state_assertions': len(replay['steps']) + 1,
                                    'errors': errors, 'screenshots': screenshots, 'saved_steps': saved_steps, 'final': await snapshot()})
                    print('PASS chapter', stem, len(replay['steps']) + 1, 'state checks', flush=True)
                except Exception:
                    await page.screenshot(path=str(output / f'{stem}-failure.png'))
                    raise
                finally:
                    await context.close()
        finally:
            await browser.close()
    result = {'mode': 'smoke' if smoke else 'full', 'replays': len(reports),
              'state_assertions': sum(r['state_assertions'] for r in reports),
              'errors': sum(len(r['errors']) for r in reports), 'cases': reports}
    (output / 'results.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({key: value for key, value in result.items() if key != 'cases'}), flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--smoke', action='store_true', help='Only chapter transition and final win at desktop/touch sizes')
    parser.add_argument('--validate-only', action='store_true', help='Validate all saves, coverage, and coordinates without launching a browser')
    args = parser.parse_args()
    asyncio.run(main(args.smoke, args.validate_only))
