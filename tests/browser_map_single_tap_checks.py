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
from playwright.async_api import async_playwright, TimeoutError as PlaywrightTimeoutError
from browser_event_checks import KEY, variant_json, await_saved_state
from browser_settings import install_debug_settings
from browser_chapter_checks import assert_rendered

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'verification/v0.14.12/map-single-tap'
URL = os.environ.get('YIXING_TEST_URL', 'http://127.0.0.1:8765')


def state(text):
    assert text, 'Missing ordinary production snapshot'
    return {'screen': re.search(r'^screen="(\w+)"', text, re.M).group(1),
            'route': variant_json(text.split('\nroute=', 1)[1].split('\nbattle=', 1)[0])}


def difference(before, after, box, after_box=None):
    a = Image.open(io.BytesIO(before)).convert('RGB').crop(box)
    b = Image.open(io.BytesIO(after)).convert('RGB').crop(box if after_box is None else after_box)
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
                cdp = await context.new_cdp_session(page);errors = [];checks = [];shots = [];frame_timelines = [];blur_evidence = []
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
                async def painted():
                    # Advance through actual browser paint opportunities, rather
                    # than assuming a fixed wall-clock delay renders a frame.
                    await asyncio.wait_for(page.evaluate("() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)))"), 8)
                async def tap(pos):
                    point = xy(pos);await page.touchscreen.tap(point['x'], point['y']);await painted()
                async def snap(): return state(await page.evaluate('(key)=>localStorage.getItem(key)', KEY))
                async def shot(label):
                    path = output / f'map-{w}-{label}.png';data = await page.screenshot(path=str(path));assert_rendered(data, [w, h]);shots.append(path.name);return data
                async def no_departure(label):
                    # A bad release first starts an unsaved 0.85-second march.
                    # Observe past arrival rather than trusting the old snapshot.
                    await page.wait_for_timeout(1100)
                    assert await snap() == initial, (w, label, await snap(), initial)
                    checks.append(label)
                async def wait_visual(label, predicate, clip=None):
                    deadline = asyncio.get_running_loop().time() + 8
                    last = None;observations = [];matched = False
                    try:
                        while asyncio.get_running_loop().time() < deadline:
                            remaining = deadline - asyncio.get_running_loop().time()
                            last = await asyncio.wait_for(page.screenshot(**({'clip': clip} if clip else {})), remaining)
                            matched, metric = predicate(last)
                            observations.append({'time': asyncio.get_running_loop().time(), 'difference': metric})
                            if matched: return last
                            await asyncio.sleep(min(.04, max(0, deadline-asyncio.get_running_loop().time())))
                        raise AssertionError((w, label, 'Expected visual state did not arrive within eight seconds', observations))
                    finally:
                        if not matched:
                            if last is not None: (output / f'map-{w}-{label}-last.png').write_bytes(last)
                            (output / f'map-{w}-{label}-wait.json').write_text(json.dumps({'matched': matched, 'observations': observations}, indent=2))
                async def baseline_restored(baseline, label):
                    def matches(data):
                        metric = difference(baseline, data, (0, 0, w, h));return metric < .01, metric
                    actual = await wait_visual(label, matches)
                    path = output / f'map-{w}-{label}.png';path.write_bytes(actual);shots.append(path.name)
                    assert_rendered(actual, [w, h])
                async def changed_from(before, label):
                    def changed(data):
                        metric = difference(before, data, (0, 0, w, h));return metric > 1, metric
                    actual = await wait_visual(label, changed)
                    path = output / f'map-{w}-{label}.png';path.write_bytes(actual);shots.append(path.name)
                    assert_rendered(actual, [w, h]);return actual
                async def observe_first_frame(kind):
                    # Capture compositor output as it happens. A synchronous PNG
                    # screenshot can finish after the .3/.4-second dwell and
                    # falsely label an on-time tooltip as premature under load.
                    # The first changed compositor frame must show only framing;
                    # a later compositor frame must add the explanation.
                    frames = [];measurements = [];ready = asyncio.Event()
                    start_index = None;first_index = None;first_time = None;tooltip_time = None;success = False
                    async def captured(event):
                        # Preserve event order before awaiting the acknowledgement.
                        # Wake the observer only after the browser can send again.
                        frames.append((event['metadata'].get('timestamp'), base64.b64decode(event['data'])))
                        await cdp.send('Page.screencastFrameAck', {'sessionId': event['sessionId']})
                        ready.set()
                    async def next_capture(deadline):
                        remaining = deadline - asyncio.get_running_loop().time()
                        if remaining <= 0: return False
                        try: await asyncio.wait_for(ready.wait(), remaining)
                        except asyncio.TimeoutError: return False
                        return True
                    cdp.on('Page.screencastFrame', captured)
                    try:
                        await cdp.send('Page.startScreencast', {'format': 'png', 'maxWidth': w, 'maxHeight': h, 'everyNthFrame': 1})
                        deadline = asyncio.get_running_loop().time() + 5
                        while not frames:
                            if not await next_capture(deadline): break
                            ready.clear()
                        assert frames, 'No baseline compositor frame received'
                        before = frames[-1][1];start_index = len(frames)
                        assert Image.open(io.BytesIO(before)).size == (w, h), 'Unexpected compositor dimensions'
                        if kind == 'mouse':
                            point = xy(node);await page.mouse.move(point['x'], point['y'])
                        else: await dispatch('touchStart', [pt(node)])
                        # Completion is evidence-driven, not a fixed delay after
                        # input. Slow CI may deliver the later compositor event
                        # well after the production tooltip was drawn.
                        deadline = asyncio.get_running_loop().time() + 8
                        cursor = start_index;first = None;tooltip = None
                        while tooltip is None:
                            ready.clear()
                            while cursor < len(frames):
                                index = cursor;timestamp, data = frames[index];cursor += 1
                                frame_delta = difference(before, data, box(hit, 6))
                                popup_delta = difference(first if first is not None else before, data, box(replay[kind+'_popup']))
                                measurements.append({'index': index, 'timestamp': timestamp,
                                                     'frame_delta': frame_delta, 'popup_delta': popup_delta})
                                if frame_delta <= .15: continue
                                if first is None:
                                    first_index = index;first_time = timestamp;first = data
                                    path = output / f'map-{w}-{kind}-immediate-frame.png';path.write_bytes(first);shots.append(path.name)
                                    assert popup_delta < .01, (w, kind, 'First framed output already had a tooltip')
                                elif popup_delta > 1:
                                    tooltip_time = timestamp;tooltip = data;break
                            if tooltip is not None or not await next_capture(deadline): break
                        assert first is not None, (w, kind, 'No immediate framed compositor output')
                        assert tooltip is not None, (w, kind, 'No later tooltip compositor output')
                        assert tooltip_time is None or first_time is None or tooltip_time > first_time
                        path = output / f'map-{w}-{kind}-delayed-tooltip.png';path.write_bytes(tooltip);shots.append(path.name)
                        frame_timelines.append({'input': kind, 'first_frame_timestamp': first_time,
                                                'tooltip_timestamp': tooltip_time, 'captured_frames': len(frames)})
                        success = True
                        return tooltip
                    finally:
                        await cdp.send('Page.stopScreencast')
                        cdp.remove_listener('Page.screencastFrame', captured)
                        diagnostic = {'input': kind, 'passed': success, 'captured_frames': len(frames),
                                      'input_start_index': start_index, 'first_frame_index': first_index,
                                      'first_frame_timestamp': first_time, 'tooltip_timestamp': tooltip_time,
                                      'frames': [{'index': i, 'timestamp': timestamp, 'bytes': len(data)}
                                                 for i, (timestamp, data) in enumerate(frames)],
                                      'measurements': measurements}
                        if not success and frames:
                            # Retain early frames plus the final frame even if a
                            # stalled compositor never supplies the expected state.
                            indices = sorted(set(range(min(40, len(frames)))) | {len(frames)-1})
                            diagnostic['retained_frames'] = []
                            for index in indices:
                                path = output / f'map-{w}-{kind}-diagnostic-{index:03d}.png';path.write_bytes(frames[index][1])
                                diagnostic['retained_frames'].append(path.name)
                        (output / f'map-{w}-{kind}-compositor.json').write_text(json.dumps(diagnostic, indent=2))
                async def blur_window():
                    # Headless tabs are separate targets, not necessarily separate
                    # focused OS windows. Prove the DOM event was delivered before
                    # testing its cancellation guarantee. No game API is invoked.
                    before_focus = await page.evaluate("""() => {
                        window.__qaMapBlurEvents = [];
                        window.__qaMapBlurObserver = event => {
                            if (event.target === window) window.__qaMapBlurEvents.push({
                                type: event.type, trusted: event.isTrusted,
                                timestamp: event.timeStamp, target: 'window',
                                hasFocus: document.hasFocus(), visibility: document.visibilityState
                            });
                        };
                        window.addEventListener('blur', window.__qaMapBlurObserver, true);
                        return document.hasFocus();
                    }""")
                    try:
                        other = await context.new_page();await other.bring_to_front()
                        try: await page.wait_for_function('window.__qaMapBlurEvents.length > 0', timeout=1000)
                        except PlaywrightTimeoutError: pass
                        await other.close();await page.bring_to_front()
                        natural = await page.evaluate('window.__qaMapBlurEvents.slice()')
                        source = 'tab-switch' if natural else 'explicit-dom-event'
                        if not natural:
                            # Exercise the same registered DOM cancellation entry
                            # point when headless bring_to_front emits no blur.
                            await page.evaluate("window.dispatchEvent(new Event('blur'))")
                        evidence = {'source': source, 'coverage': 'Browser tab-switch blur' if natural else 'DOM blur-listener cancellation only', 'focus_before': before_focus,
                                    'focus_after': await page.evaluate('document.hasFocus()'),
                                    'tab_switch_events': natural,
                                    'delivered_events': await page.evaluate('window.__qaMapBlurEvents.slice()')}
                        blur_evidence.append(evidence)
                        (output / f'map-{w}-blur-events.json').write_text(json.dumps(evidence, indent=2))
                        print('MAP BLUR EVIDENCE', w, json.dumps(evidence), flush=True)
                        assert evidence['delivered_events'], 'Blur cancellation was not exercised: no window DOM event received'
                        assert all(event['type'] == 'blur' and event['target'] == 'window'
                                   for event in evidence['delivered_events'])
                    finally:
                        await page.evaluate("window.removeEventListener('blur', window.__qaMapBlurObserver, true)")
                async def hold():
                    # A real held touch is released only after its actual popup
                    # is rendered. Crop the expected panel to keep polling cheap.
                    left, top, right, bottom = box(replay['touch_popup'])
                    clip = {'x': left, 'y': top, 'width': right-left, 'height': bottom-top}
                    before = await page.screenshot(clip=clip)
                    await dispatch('touchStart', [pt(node)])
                    def visible(data):
                        metric = difference(before, data, (0, 0, right-left, bottom-top));return metric > 1, metric
                    await wait_visual('held-tooltip', visible, clip)
                async def seed_and_resume(first=False):
                    if first:
                        await page.add_init_script('if(!sessionStorage.getItem("qa-map-once")){localStorage.setItem(%s,%s);sessionStorage.setItem("qa-map-once","1")}' % (json.dumps(KEY), json.dumps(fixture)))
                        await page.goto(URL)
                    else:
                        await page.evaluate('([key,text])=>localStorage.setItem(key,text)', [KEY, fixture]);await page.reload()
                    await page.wait_for_function("!document.getElementById('status')", timeout=60000);await painted();await tap(replay['resume'])
                    assert await snap() == initial
                    point = xy(blank);await page.mouse.move(point['x'], point['y']);await painted()
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
                    # Use 20 logical pixels to cross the 12-pixel deadzone clearly:
                    # fractional Web viewport scaling can quantize an exact 12-pixel
                    # request below threshold. Native tests retain exact-12 coverage.
                    # Hitbox exit uses 4 pixels inside to 4 outside (8 total), safely
                    # below the deadzone even after CSS/device coordinate rounding.
                    for gesture in ['cancel', 'drag-threshold', 'drag-return', 'outside-hitbox', 'second-finger', 'blur']:
                        start = [hit[0] + hit[2] - 4, node[1]] if gesture == 'outside-hitbox' else node
                        await dispatch('touchStart', [pt(start)])
                        if gesture == 'cancel': await dispatch('touchCancel', [])
                        elif gesture == 'drag-threshold':
                            await dispatch('touchMove', [pt([node[0]+20, node[1]])]);await dispatch('touchEnd', [])
                        elif gesture == 'drag-return':
                            await dispatch('touchMove', [pt([node[0]+28, node[1]])]);await dispatch('touchMove', [pt(node)]);await dispatch('touchEnd', [])
                        elif gesture == 'outside-hitbox':
                            await dispatch('touchMove', [pt([start[0]+8, start[1]])]);await dispatch('touchEnd', [])
                        elif gesture == 'second-finger':
                            await dispatch('touchStart', [pt(node), pt(blank, 1)]);await dispatch('touchEnd', [])
                        else:
                            await blur_window();await dispatch('touchEnd', [])
                        await no_departure(gesture+' prevents travel')
                        await baseline_restored(baseline, gesture+'-cleared')
                    await tap(replay['unavailable']);await no_departure('Single nonlegal tap does not depart')
                    await tap(blank);await baseline_restored(baseline, 'nonlegal-cleared')
                    # Drag while a hold is visible cancels sticky state and its release.
                    await hold();await dispatch('touchMove', [pt([node[0]+20, node[1]])]);await dispatch('touchEnd', [])
                    await no_departure('Drag after hold does not depart');await baseline_restored(baseline, 'hold-drag-cleared')
                    # A visible node hold must hand off to a continuous vertical
                    # scroll, not cancel after its first changed camera position.
                    await hold()
                    await dispatch('touchMove', [pt([node[0], node[1]+24])]);await painted()
                    first_scroll = await shot('hold-vertical-first-step')
                    await dispatch('touchMove', [pt([node[0], node[1]+48])])
                    await changed_from(first_scroll, 'hold-vertical-second-step')
                    await dispatch('touchEnd', []);await no_departure('Vertical hold-drag continues across frames without departure')
                    # Restore through the actual opposite gesture; retain strict
                    # image equality and unchanged ordinary save as separate checks.
                    await dispatch('touchStart', [pt([node[0], node[1]+48])])
                    await dispatch('touchMove', [pt([node[0], node[1]+24])]);await painted()
                    await dispatch('touchMove', [pt(node)]);await painted()
                    await dispatch('touchEnd', []);await no_departure('Opposite vertical drag cannot select or depart')
                    await baseline_restored(baseline, 'hold-vertical-round-trip')
                    await hold();await dispatch('touchEnd', []);before_deck = await page.screenshot();await tap(replay['deck'])
                    deck = await changed_from(before_deck, 'deck-from-sticky');assert difference(baseline, deck, (0, 0, w, h)) > 1
                    await tap(replay['close_deck']);await baseline_restored(baseline, 'deck-close-no-residue')
                    await no_departure('Deck dismissal retains camera but clears inspection and capture')
                    await hold();await dispatch('touchEnd', []);before_home = await page.screenshot();await tap(replay['home'])
                    home = await changed_from(before_home, 'home-clears-sticky');assert difference(baseline, home, (0, 0, w, h)) > 1
                    await tap(replay['resume']);await baseline_restored(baseline, 'resume-clears-sticky')
                    await no_departure('Page change and resume clear sticky inspection')
                    # Holding cannot auto-enter, but the next distinct short tap must.
                    await hold();await dispatch('touchEnd', []);await no_departure('Final hold remains inspection only')
                    await tap(node)
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
                    results.append({'viewport': [w, h], 'checks': checks, 'screenshots': shots, 'frame_timelines': frame_timelines, 'blur_evidence': blur_evidence, 'errors': errors})
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
