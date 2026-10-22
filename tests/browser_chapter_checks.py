from browser_settings import install_debug_settings
"""Replay chapter two through the exported Web UI, using ordinary saved games.

Generate tests/chapter_web_fixtures.gd before export. JavaScript only writes the
initial save and reads subsequent saves; gameplay uses touch or mouse input. The
--smoke mode is a two-viewport release gate, not the full rendered regression.
"""
import argparse
import asyncio
import hashlib
import io
import json
import math
import os
import re
import shutil
from pathlib import Path

from PIL import Image, ImageChops, ImageStat
from playwright.async_api import async_playwright

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'verification/v0.14.0/chapter'
URL = os.environ.get('YIXING_TEST_URL', 'http://127.0.0.1:8765')
KEY = 'yixing.route_run.v0149'
ROUTE_FIELDS = ['chapter', 'current', 'pending', 'visited', 'done', 'prepared',
                'reward_debt', 'reward_blocked', 'pending_homework', 'homework_awarded',
                'treasure_id', 'treasure_claimed', 'treasure_choices']
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


def inspection_save(text):
    # Rendering alone updates these visual fields. Keep all gameplay fields,
    # including RNG, card IDs, delayed effects, wave/ghost state and undo budget.
    route = variant_json(text.split('\nroute=', 1)[1].split('\nbattle=', 1)[0])
    battle = variant_json(text.split('\nbattle=', 1)[1].rsplit('\nscreen=', 1)[0])
    battle.pop('initial_threat', None)
    for enemy in battle['enemies']:
        enemy.pop('visual', None)
    return {'route': route, 'battle': battle,
            'screen': re.search(r'^screen="(\w+)"', text, re.M).group(1),
            'undo_budget': re.findall(r'^normal_undos_remaining=(\d+)', text, re.M)}


def image_difference(before, after, box=None):
    a = Image.open(io.BytesIO(before)).convert('RGB')
    b = Image.open(io.BytesIO(after)).convert('RGB')
    assert a.size == b.size
    if box is not None:
        a, b = a.crop(box), b.crop(box)
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
            assert step['kind'] in {'tap', 'enter', 'combat', 'reload', 'inspect', 'close_inspect'}
            assert step['expected']['chapter'] in {1, 2}
    selected = [r for r in replays if not smoke or r['name'] in SMOKE_NAMES]
    assert len(selected) == (4 if smoke else len(expected)), 'Wrong selected chapter coverage'
    for replay in replays:
        uw, uh = replay['logical_size']
        previous = replay['initial']
        pending_inspection = None
        for step in replay['steps']:
            if step['kind'] in {'inspect', 'close_inspect'}:
                assert step['expected'] == previous, (replay['fixture'], 'Inspection changes expected gameplay')
                assert step['source'] == ('mouse' if int(replay['viewport'][0]) == 1280 else 'touch')
                x, y, width, height = step['popup']
                assert 0 <= x and 0 <= y and width > 0 and height > 0 and x+width <= uw and y+height <= uh
                assert step['title'] and step['lines'] and step['rows'] and step['font_size'] >= 12
                assert ''.join(row['text'] for row in step['rows']) == ''.join(step['lines']).replace('\n', '')
                for row in step['rows']:
                    assert 0 <= row['width'] <= width-28 and 0 <= row['top'] < row['bottom'] <= height
                if step['kind'] == 'inspect':
                    assert pending_inspection is None, 'Inspection missing release'
                    pending_inspection = step
                else:
                    assert pending_inspection is not None and step['popup'] == pending_inspection['popup']
                    pending_inspection = None
            else:
                assert pending_inspection is None, 'Gameplay continues with inspection still held'
            previous = step['expected']
        assert pending_inspection is None, 'Final inspection was not released'
        points = [replay['resume']] + [pos for step in replay['steps'] for pos in step['taps']]
        points += [step['target'] for step in replay['steps'] if 'target' in step]
        for point in points:
            assert len(point) == 2 and 0 <= point[0] < uw and 0 <= point[1] < uh, (
                replay['fixture'], 'Input coordinate outside logical viewport', point)
    if validate_only:
        print(json.dumps({'validated_fixtures': len(replays), 'selected_replays': len(selected),
                          'selected_state_assertions': sum(len(r['steps']) + 1 for r in selected),
                          'inspection_open_close_pairs': sum(step['kind'] == 'inspect' for r in selected for step in r['steps']),
                          'inspection_sources': sorted({step['source'] for r in selected for step in r['steps'] if 'source' in step}),
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
                page = await context.new_page();await install_debug_settings(page)
                errors = []
                page.on('pageerror', lambda error: errors.append(str(error)))
                page.on('console', lambda msg: errors.append(msg.text) if msg.type == 'error' and
                        ('SCRIPT ERROR' in msg.text or 'Parse Error' in msg.text) else None)
                stem = replay['name'] + '-' + str(w)
                screenshots = []
                panel_before = None
                inspection_before = None
                inspection_metrics = []
                cdp = await context.new_cdp_session(page)
                saved_steps = []

                async def tap(pos):
                    x, y = ox + pos[0] * scale, oy + pos[1] * scale
                    assert 0 <= x < w and 0 <= y < h, (stem, 'Tap outside viewport', pos, [x, y])
                    await page.touchscreen.tap(x, y)
                    await page.wait_for_timeout(160)

                async def resume():
                    await tap(replay['resume'])
                    await page.wait_for_timeout(350)

                async def saved_text():
                    return await page.evaluate('(key)=>localStorage.getItem(key)', KEY)

                async def snapshot():
                    return parse_save(await saved_text())

                def popup_box(rect, inset=4):
                    x, y, width, height = rect
                    return (math.floor(ox + (x+inset)*scale), math.floor(oy + (y+inset)*scale),
                            math.ceil(ox + (x+width-inset)*scale), math.ceil(oy + (y+height-inset)*scale))

                def check_popup(before, after, step):
                    box = popup_box(step['popup'])
                    difference = image_difference(before, after, box)
                    image = Image.open(io.BytesIO(after)).convert('RGB')
                    panel = image.crop(box)
                    paper = sum(max(abs(c-t) for c, t in zip(rgb, (252, 249, 241))) <= 6
                                for rgb in panel.getdata()) / (panel.width*panel.height)
                    assert difference > 7 and paper > .58, (stem, step['label'], 'Shared popup not visibly open', difference, paper, box)
                    # Inspect every actual wrapped row, not a whole-screen change
                    # caused by unrelated animation or the obsolete rules modal.
                    x, y, _, _ = step['popup']
                    ink_counts = []
                    for row in step['rows']:
                        if not row['text'].strip():
                            continue
                        band = image.crop(popup_box([x+14, y+row['top'], row['width'], row['bottom']-row['top']], 0))
                        ink = sum(r < 150 and g < 130 and b < 110 for r, g, b in band.getdata())
                        assert ink > max(2, len(row['text'])*scale*.4), (stem, step['label'], 'Popup row is missing or unreadable', row, ink)
                        ink_counts.append(ink)
                    return {'label': step['label'], 'popup': step['popup'], 'difference': round(difference, 3),
                            'paper_fraction': round(paper, 3), 'row_ink_pixels': ink_counts}

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
                        elif step['kind'] == 'inspect':
                            # Let entry/turn effects settle before taking a visual
                            # baseline. This does not weaken any saved-state check.
                            if number == 0 or replay['steps'][number-1]['kind'] != 'close_inspect':
                                await page.wait_for_timeout(2200)
                            panel_before = await page.screenshot()
                            inspection_before = inspection_save(await saved_text())
                            x, y = ox+step['target'][0]*scale, oy+step['target'][1]*scale
                            if step['source'] == 'mouse':
                                await page.mouse.move(x, y)
                            else:
                                await cdp.send('Input.dispatchTouchEvent', {'type': 'touchStart', 'touchPoints': [{'x': x, 'y': y, 'id': 4}]})
                            await page.wait_for_timeout(650)
                        elif step['kind'] == 'close_inspect':
                            assert panel_before is not None and inspection_before is not None
                            if step['source'] == 'mouse':
                                await page.mouse.move(ox+step['target'][0]*scale, oy+step['target'][1]*scale)
                            else:
                                await cdp.send('Input.dispatchTouchEvent', {'type': 'touchEnd', 'touchPoints': []})
                            # Wait through autosave and any accidental end-turn or
                            # card action, so a stale save cannot hide release leaks.
                            await page.wait_for_timeout(1600)
                        else:
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
                        if step['kind'] in {'inspect', 'close_inspect'}:
                            assert inspection_save(await saved_text()) == inspection_before, (stem, step['label'], 'Inspection changed cards, turn, RNG, effects or route')
                        if step['kind'] == 'inspect':
                            inspection_metrics.append(check_popup(panel_before, capture, step))
                        if step['kind'] == 'close_inspect':
                            difference = image_difference(panel_before, capture, popup_box(step['popup']))
                            assert difference < 5, (stem, step['label'], 'Shared popup did not close after release/exit', difference)
                            inspection_metrics[-1]['closed_difference'] = round(difference, 3)
                            panel_before = None;inspection_before = None
                    assert not errors, (stem, errors)
                    reports.append({'fixture': replay['fixture'], 'viewport': [w, h],
                                    'state_assertions': len(replay['steps']) + 1,
                                    'errors': errors, 'screenshots': screenshots, 'saved_steps': saved_steps,
                                    'inspection_metrics': inspection_metrics, 'final': await snapshot()})
                    print('PASS chapter', stem, len(replay['steps']) + 1, 'state checks', flush=True)
                except Exception:
                    await page.screenshot(path=str(output / f'{stem}-failure.png'))
                    raise
                finally:
                    await cdp.detach()
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
