"""Focused actual-Web map input gate using ordinary saved runs, never game hooks.

Generate map_single_tap_web_fixtures.gd first. Default desktop 1280 and touch390;
--full (or YIXING_FULL_REGRESSION=1) adds 360 and landscape844. --validate-only
validates every fixture without starting a browser. Exact dwell thresholds and
road-cache work counts are asserted by the paired headless regression.
"""
import argparse
import base64
import asyncio
import io
import json
import os
import re
import shutil
from pathlib import Path
from PIL import Image, ImageChops, ImageStat
from playwright.async_api import async_playwright
from browser_event_checks import KEY, boot, variant_json, await_saved_state
from browser_settings import install_debug_settings
from browser_chapter_checks import assert_rendered

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'verification/v0.14.12/map-single-tap'
URL = os.environ.get('YIXING_TEST_URL', 'http://127.0.0.1:8765')


def state(text):
    assert text, 'Missing ordinary production snapshot'
    return {'screen': re.search(r'^screen="(\w+)"', text, re.M).group(1),
            'route': variant_json(text.split('\nroute=', 1)[1].split('\nbattle=', 1)[0])}


def difference(before, after, box):
    a = Image.open(io.BytesIO(before)).convert('RGB').crop(box)
    b = Image.open(io.BytesIO(after)).convert('RGB').crop(box)
    return sum(ImageStat.Stat(ImageChops.difference(a, b)).mean) / 3


async def main(full=False, validate_only=False):
    replays = json.loads((OUT / 'replays.json').read_text())
    assert {tuple(r['viewport']) for r in replays} == {(1280, 940), (390, 844), (360, 640), (844, 390)}
    assert len(replays) == 4, 'Missing or duplicate viewport fixture'
    for replay in replays:
        initial = state((OUT / 'fixtures' / replay['fixture']).read_text())
        route = initial['route']
        assert initial['screen'] == 'map' and route['current'] == route['pending'] == -1
        assert route['visited'] == [] and route['nodes'][0]['kind'] == 'battle'
        assert replay['unavailable_id'] != 0
        assert len(replay['point']) == 2 and replay['hit'][2] >= 44 and replay['hit'][3] >= 44
    chosen = replays if full else [r for r in replays if r['viewport'][0] in {1280, 390}]
    if validate_only:
        print(json.dumps({'valid_fixtures': len(replays), 'selected_cases': len(chosen), 'rendered': False}));return
    output = OUT / ('browser-full' if full else 'browser-smoke');output.mkdir(parents=True, exist_ok=True)
    results = []
    async with async_playwright() as p:
        executable = os.environ.get('CHROMIUM_PATH') or shutil.which('chromium')
        browser = await p.chromium.launch(**({'executable_path': executable} if executable else {}), headless=True, args=['--no-sandbox'])
        try:
            for replay in chosen:
                w, h = map(int, replay['viewport']);uw, uh = replay['logical_size']
                scale = min(w / uw, h / uh);ox = (w - uw * scale) / 2;oy = (h - uh * scale) / 2
                context = await browser.new_context(viewport={'width': w, 'height': h}, has_touch=True)
                page = await context.new_page();await install_debug_settings(page)
                cdp = await context.new_cdp_session(page);errors = [];checks = [];shots = [];frame_timelines = []
                page.on('pageerror', lambda e: errors.append(str(e)))
                page.on('console', lambda m: errors.append(m.text) if m.type == 'error' and ('SCRIPT ERROR' in m.text or 'Parse Error' in m.text) else None)
                fixture = (OUT / 'fixtures' / replay['fixture']).read_text();initial = state(fixture)
                node = replay['point'];blank = replay['blank'];hit = replay['hit']
                def xy(pos): return {'x': ox + pos[0] * scale, 'y': oy + pos[1] * scale}
                def pt(pos, index=0): return {**xy(pos), 'id': index}
                def box(rect, grow=0):
                    x, y, rw, rh = rect
                    return (round(ox + (x-grow)*scale), round(oy + (y-grow)*scale), round(ox + (x+rw+grow)*scale), round(oy + (y+rh+grow)*scale))
                async def dispatch(kind, points): await cdp.send('Input.dispatchTouchEvent', {'type': kind, 'touchPoints': points})
                async def tap(pos, delay=120):
                    point = xy(pos);await page.touchscreen.tap(point['x'], point['y']);await page.wait_for_timeout(delay)
                async def snap(): return state(await page.evaluate('(key)=>localStorage.getItem(key)', KEY))
                async def shot(label):
                    path = output / f'map-{w}-{label}.png';data = await page.screenshot(path=str(path));assert_rendered(data, [w, h]);shots.append(path.name);return data
                async def no_departure(label):
                    # A bad release first starts an unsaved 0.85-second march.
                    # Observe past arrival rather than trusting the old snapshot.
                    await page.wait_for_timeout(1100)
                    assert await snap() == initial, (w, label, await snap(), initial)
                    checks.append(label)
                async def baseline_restored(baseline, label):
                    await page.wait_for_timeout(100)
                    actual = await shot(label)
                    assert difference(baseline, actual, (0, 0, w, h)) < .01, (w, label, 'Transient inspection not cleared')
                async def observe_first_frame(kind):
                    # Capture compositor output as it happens. A synchronous PNG
                    # screenshot can finish after the .3/.4-second dwell and
                    # falsely label an on-time tooltip as premature under load.
                    # The first changed compositor frame must show only framing;
                    # a later compositor frame must add the explanation.
                    frames = []
                    async def captured(event):
                        await cdp.send('Page.screencastFrameAck', {'sessionId': event['sessionId']})
                        frames.append((event['metadata'].get('timestamp'), base64.b64decode(event['data'])))
                    cdp.on('Page.screencastFrame', captured)
                    try:
                        await cdp.send('Page.startScreencast', {'format': 'png', 'maxWidth': w, 'maxHeight': h, 'everyNthFrame': 1})
                        deadline = asyncio.get_running_loop().time() + 5
                        while not frames and asyncio.get_running_loop().time() < deadline:
                            await asyncio.sleep(.02)
                        assert frames, 'No baseline compositor frame received'
                        before = frames[-1][1];start_index = len(frames)
                        assert Image.open(io.BytesIO(before)).size == (w, h), 'Unexpected compositor dimensions'
                        if kind == 'mouse':
                            point = xy(node);await page.mouse.move(point['x'], point['y'])
                        else: await dispatch('touchStart', [pt(node)])
                        await page.wait_for_timeout(650)
                        changed = [(timestamp, data) for timestamp, data in frames[start_index:]
                                   if difference(before, data, box(hit, 6)) > .15]
                        assert changed, (w, kind, 'No immediate framed compositor output')
                        first_time, first = changed[0]
                        assert difference(before, first, box(replay[kind+'_popup'])) < .01, (w, kind, 'First framed output already had a tooltip')
                        explained = [(timestamp, data) for timestamp, data in changed[1:]
                                     if difference(first, data, box(replay[kind+'_popup'])) > 1]
                        assert explained, (w, kind, 'No later tooltip compositor output')
                        tooltip_time, tooltip = explained[0]
                        assert tooltip_time is None or first_time is None or tooltip_time > first_time
                        for label, data in [('immediate-frame', first), ('delayed-tooltip', tooltip)]:
                            path = output / f'map-{w}-{kind}-{label}.png';path.write_bytes(data);shots.append(path.name)
                        frame_timelines.append({'input': kind, 'first_frame_timestamp': first_time,
                                                'tooltip_timestamp': tooltip_time, 'captured_frames': len(frames)})
                        return tooltip
                    finally:
                        await cdp.send('Page.stopScreencast')
                        cdp.remove_listener('Page.screencastFrame', captured)
                async def hold():
                    await dispatch('touchStart', [pt(node)])
                    await page.wait_for_timeout(500)
                async def seed_and_resume(first=False):
                    if first:
                        await page.add_init_script('if(!sessionStorage.getItem("qa-map-once")){localStorage.setItem(%s,%s);sessionStorage.setItem("qa-map-once","1")}' % (json.dumps(KEY), json.dumps(fixture)))
                        await page.goto(URL)
                    else:
                        await page.evaluate('([key,text])=>localStorage.setItem(key,text)', [KEY, fixture]);await page.reload()
                    await boot(page);await tap(replay['resume'], 250)
                    assert await snap() == initial
                    point = xy(blank);await page.mouse.move(point['x'], point['y']);await page.wait_for_timeout(100)
                try:
                    await seed_and_resume(first=True)
                    baseline = await shot('initial')
                    # Mouse and touch first-frame evidence comes from compositor
                    # events, not screenshots whose encoding can outlast a dwell.
                    await observe_first_frame('mouse')
                    assert await snap() == initial
                    point = xy(blank);await page.mouse.move(point['x'], point['y'])
                    await baseline_restored(baseline, 'mouse-exit-clears')
                    checks.append('Mouse immediate frame, delayed tooltip, exit clears without travel')
                    held = await observe_first_frame('touch')
                    await dispatch('touchEnd', []);await no_departure('Long-hold release does not depart')
                    sticky = await shot('touch-release-sticky')
                    assert difference(held, sticky, (0, 0, w, h)) < .01, 'Hold release lost tooltip or frame'
                    await tap(blank);await baseline_restored(baseline, 'blank-clears-sticky')
                    checks.append('Touch immediate frame, delayed tooltip, release sticky, blank clears')
                    # Every independent unsafe gesture must survive past arrival time.
                    for gesture in ['cancel', 'drag-threshold', 'drag-return', 'outside-hitbox', 'second-finger', 'blur']:
                        start = [hit[0] + hit[2] - 2, node[1]] if gesture == 'outside-hitbox' else node
                        await dispatch('touchStart', [pt(start)])
                        if gesture == 'cancel': await dispatch('touchCancel', [])
                        elif gesture == 'drag-threshold':
                            await dispatch('touchMove', [pt([node[0]+12, node[1]])]);await dispatch('touchEnd', [])
                        elif gesture == 'drag-return':
                            await dispatch('touchMove', [pt([node[0]+28, node[1]])]);await dispatch('touchMove', [pt(node)]);await dispatch('touchEnd', [])
                        elif gesture == 'outside-hitbox':
                            await dispatch('touchMove', [pt([start[0]+4, start[1]])]);await dispatch('touchEnd', [])
                        elif gesture == 'second-finger':
                            await dispatch('touchStart', [pt(node), pt(blank, 1)]);await dispatch('touchEnd', [])
                        else:
                            other = await context.new_page();await other.bring_to_front();await page.wait_for_timeout(100)
                            await other.close();await page.bring_to_front();await dispatch('touchEnd', [])
                        await no_departure(gesture+' prevents travel')
                        await baseline_restored(baseline, gesture+'-cleared')
                    await tap(replay['unavailable']);await no_departure('Single nonlegal tap does not depart')
                    await tap(blank);await baseline_restored(baseline, 'nonlegal-cleared')
                    # Drag while a hold is visible cancels sticky state and its release.
                    await hold();await dispatch('touchMove', [pt([node[0]+16, node[1]])]);await dispatch('touchEnd', [])
                    await no_departure('Drag after hold does not depart');await baseline_restored(baseline, 'hold-drag-cleared')
                    await hold();await dispatch('touchEnd', []);await tap(replay['deck'])
                    deck = await shot('deck-from-sticky');assert difference(baseline, deck, (0, 0, w, h)) > 1
                    await tap(replay['close_deck']);await baseline_restored(baseline, 'deck-close-no-residue')
                    await no_departure('Deck dismissal retains camera but clears inspection and capture')
                    await hold();await dispatch('touchEnd', []);await tap(replay['home'])
                    home = await shot('home-clears-sticky');assert difference(baseline, home, (0, 0, w, h)) > 1
                    await tap(replay['resume'], 300);await baseline_restored(baseline, 'resume-clears-sticky')
                    await no_departure('Page change and resume clear sticky inspection')
                    # Holding cannot auto-enter, but the next distinct short tap must.
                    await hold();await dispatch('touchEnd', []);await no_departure('Final hold remains inspection only')
                    await tap(node, 80)
                    async def entered():
                        value = await snap();return (value['screen'], value['route']['current'], value['route']['pending'])
                    assert await await_saved_state(entered, ('game', -1, 0)) == ('game', -1, 0), 'One distinct short touch after hold did not enter'
                    arrived = await snap();await page.wait_for_timeout(1100)
                    assert await snap() == arrived, 'Repeated arrival committed route twice'
                    await shot('single-touch-arrival');checks.append('Next distinct short touch enters once without a confirming tap')
                    # An independent fresh ordinary save proves mouse single-click entry.
                    await seed_and_resume()
                    point = xy(node);await page.mouse.click(point['x'], point['y'])
                    assert await await_saved_state(entered, ('game', -1, 0)) == ('game', -1, 0), 'One physical mouse click did not enter'
                    await shot('single-mouse-arrival');checks.append('One physical mouse click enters without prior selection')
                    assert not errors, errors
                    results.append({'viewport': [w, h], 'checks': checks, 'screenshots': shots, 'frame_timelines': frame_timelines, 'errors': errors})
                    print('PASS map single-tap', w, h, len(checks), 'real-UI checks', flush=True)
                except Exception:
                    await page.screenshot(path=str(output / f'map-{w}-failure.png'));raise
                finally:
                    await cdp.detach();await context.close()
        finally:
            await browser.close()
    (output / 'results.json').write_text(json.dumps(results, ensure_ascii=False, indent=2))
    print('MAP SINGLE TAP WEB RESULT', len(results), 'viewport cases')


if __name__ == '__main__':
    parser = argparse.ArgumentParser();parser.add_argument('--full', action='store_true');parser.add_argument('--validate-only', action='store_true');args = parser.parse_args()
    asyncio.run(main(args.full or os.environ.get('YIXING_FULL_REGRESSION') == '1', args.validate_only))
