"""Real exported Web regression, resumed only through ordinary Continue UI.

Generate native fixtures with rook_visual_capture.gd first. All gameplay uses
actual Space or touchscreen events; JS only loads the production save and reads
save/RAF evidence. No game API, hidden debug hook, or synthetic engine call.
"""
import asyncio
import base64
import hashlib
import io
import json
import math
import os
import shutil
from pathlib import Path

from PIL import Image, ImageDraw
from playwright.async_api import async_playwright

# These helpers are pure and do not write to the cannon suite's output paths.
from browser_cannon_checks import KEY, layout, parse_save, summary

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'verification/v0.12.0/rook/browser'
FIXTURES = OUT.parent / 'fixtures'
URL = os.environ.get('YIXING_TEST_URL', 'http://127.0.0.1:8765')
NAMES = ['distance_control', 'horse_complement', 'stale_near_general',
         'general_barrier', 'planned_formation', 'boss_hold_credit',
         'mixed_stress', 'general_evades_cannon']
VIEWPORTS = [(1280, 940), (390, 844)]
NOTES = [
    'Real Chromium Web export. Valid production saves resumed through Continue.',
    'Desktop uses mouse Continue and Space; mobile uses real touchscreen taps.',
    'Before/after saves must exactly match native results for each viewport.',
    'No injected gameplay API. Instrumentation only reads saves and RAF timing.',
    'Input-to-save includes animation lock and autosave, not just AI execution.',
    'Mobile is a 390x844 touch viewport on the CI CPU, not physical-device performance.',
    'Motion recording uses a separate replay and is excluded from performance samples.',
]


async def await_boot(page):
    await page.wait_for_function("!document.getElementById('status')", timeout=60000)
    await page.wait_for_timeout(800)


async def resume(page, geometry, mobile):
    if mobile:
        await page.touchscreen.tap(*geometry['resume'])
    else:
        await page.mouse.click(*geometry['resume'])
    await page.wait_for_timeout(350)


async def end_turn(page, geometry, mobile):
    if mobile:
        await page.touchscreen.tap(*geometry['end'])
    else:
        await page.keyboard.press('Space')


async def load_fixture(page, fixture, geometry, mobile):
    await page.add_init_script('localStorage.setItem(' + json.dumps(KEY) + ',' + json.dumps(fixture) + ');')
    await page.goto(URL)
    await await_boot(page)
    await resume(page, geometry, mobile)


async def snapshot(page):
    return await page.evaluate('(key) => localStorage.getItem(key)', KEY)


async def await_saved_turn(page):
    await page.wait_for_function(
        r'''/"turn": 2[,\n]/.test(localStorage.getItem('yixing.route_run.v0100')||'')''',
        timeout=20000)


async def instrument(page):
    await page.evaluate(r'''() => new Promise(resolve => {
      const trace = window.rookQaTrace = {start: performance.now(), inputAt: null,
        firstSaveAt: null, frames: [], last: null, baselineFrames: 0, running: true};
      const input = () => { if(trace.inputAt === null) trace.inputAt = performance.now(); };
      document.addEventListener('touchstart', input, {once:true, capture:true});
      document.addEventListener('keydown', input, {once:true, capture:true});
      function frame(now) {
        if(!trace.running) return;
        if(trace.last !== null && trace.inputAt !== null) trace.frames.push(now - trace.last);
        trace.last = now;
        if(trace.inputAt === null && ++trace.baselineFrames >= 2) resolve();
        const save = localStorage.getItem('yixing.route_run.v0100') || '';
        if(trace.inputAt !== null && trace.firstSaveAt === null && /"turn": 2[,\n]/.test(save)) trace.firstSaveAt=now;
        requestAnimationFrame(frame);
      }
      requestAnimationFrame(frame);
    })''')


async def trace_result(page):
    return await page.evaluate('''() => {
      const t = window.rookQaTrace; t.running=false;
      const sorted=[...t.frames].sort((a,b)=>a-b);
      return {input_to_saved_turn_ms: t.firstSaveAt !== null && t.inputAt !== null ? t.firstSaveAt-t.inputAt : null,
        max_raf_interval_ms: t.frames.length ? Math.max(...t.frames) : null,
        p95_raf_interval_ms: sorted.length ? sorted[Math.floor(sorted.length*.95)] : null,
        raf_samples: t.frames, baseline_frames: t.baselineFrames,
        input_event_recorded: t.inputAt !== null};
    }''')


def performance_checks(performance, name, width):
    assert performance['input_event_recorded'], (name, width, 'No real input event')
    assert performance['baseline_frames'] >= 2, (name, width, 'Missing pre-input baseline')
    assert len(performance['raf_samples']) >= 3, (name, width, 'Insufficient RAF samples')
    assert all(isinstance(x, (int, float)) and math.isfinite(x) and x >= 0
               for x in performance['raf_samples']), (name, width, 'Invalid RAF sample')
    latency = performance['input_to_saved_turn_ms']
    assert latency is not None and math.isfinite(latency) and 0 <= latency <= 8000, (
        name, width, 'Input-to-save exceeds existing 8-second gate', performance)
    maximum = performance['max_raf_interval_ms']
    assert maximum is not None and math.isfinite(maximum) and maximum <= 250, (
        name, width, 'RAF interval exceeds existing 250ms gate', performance)


async def movement_film(context, page, geometry, mobile, stem, expected):
    # Page init restores the same ordinary fixture, then Continue replays it.
    # A separate replay keeps screenshot transport out of performance samples.
    await page.reload()
    await await_boot(page)
    await resume(page, geometry, mobile)
    assert summary(parse_save(await snapshot(page))) == expected['before'], (stem, 'Replay before mismatch')
    cdp = await context.new_cdp_session(page)
    frames = []

    async def frame(params):
        frames.append(params)
        await cdp.send('Page.screencastFrameAck', {'sessionId': params['sessionId']})

    cdp.on('Page.screencastFrame', frame)
    await cdp.send('Page.startScreencast', {'format': 'jpeg', 'quality': 88, 'everyNthFrame': 1})
    try:
        await page.wait_for_timeout(80)
        await end_turn(page, geometry, mobile)
        await await_saved_turn(page)
        await page.wait_for_timeout(200)
    finally:
        await cdp.send('Page.stopScreencast')
        await cdp.detach()
    assert summary(parse_save(await snapshot(page))) == expected['after'], (stem, 'Replay after mismatch')
    assert len(frames) >= 4, (stem, 'Insufficient real animation frames', len(frames))
    film_dir = OUT / stem
    film_dir.mkdir(exist_ok=True)
    manifest = []
    sheets = []
    board_hashes = set()
    t0 = frames[0]['metadata']['timestamp']
    for i, captured in enumerate(frames):
        data = base64.b64decode(captured['data'])
        (film_dir / f'{i:03d}.jpg').write_bytes(data)
        elapsed = (captured['metadata']['timestamp'] - t0) * 1000
        board = Image.open(io.BytesIO(data)).crop(tuple(map(int, geometry['board'])))
        digest = hashlib.sha256(board.tobytes()).hexdigest()
        board_hashes.add(digest)
        manifest.append({'frame': i, 'elapsed_ms': elapsed, 'file': f'{i:03d}.jpg', 'board_sha256': digest})
        board.thumbnail((223, 247))
        tile = Image.new('RGB', (235, 280), '#ffffff')
        tile.paste(board, ((235 - board.width) // 2, 24))
        ImageDraw.Draw(tile).text((6, 5), f'{i:02d}: {elapsed:.0f}ms', fill='black')
        sheets.append(tile)
    # Every real frame is preserved; the contact sheet samples chronological order.
    selected = sheets if len(sheets) <= 24 else [sheets[round(i * (len(sheets) - 1) / 23)] for i in range(24)]
    sheet = Image.new('RGB', (6 * 235, ((len(selected) + 5) // 6) * 280), '#dddddd')
    for i, tile in enumerate(selected):
        sheet.paste(tile, ((i % 6) * 235, (i // 6) * 280))
    sheet.save(OUT / f'{stem}-contact.png')
    (film_dir / 'frames.json').write_text(json.dumps(manifest, indent=2) + '\n')
    assert len(board_hashes) >= 3, (stem, 'Animation recording contains only static board frames')
    return {'frame_count': len(frames), 'distinct_board_frames': len(board_hashes),
            'recorded_duration_ms': manifest[-1]['elapsed_ms'],
            'manifest': str((film_dir / 'frames.json').relative_to(ROOT)),
            'contact_sheet': str((OUT / f'{stem}-contact.png').relative_to(ROOT)),
            'native_movement': expected['movement']}


def write_report(reports):
    (OUT / 'browser-rook-report.json').write_text(json.dumps({'reports': reports, 'notes': NOTES}, indent=2) + '\n')


async def main():
    OUT.mkdir(parents=True, exist_ok=True)
    native = json.loads((OUT.parent / 'native-behavior.json').read_text())
    assert native['failures'] == 0 and native['checks'] > 0, 'Native semantic checks must pass first'
    expected = {(r['name'], r['viewport'][0]): r for r in native['scenarios']}
    assert set(expected) == {(name, width) for name in NAMES for width, _ in VIEWPORTS}, 'Native/browser scenario matrix differs'
    reports = []
    async with async_playwright() as p:
        executable = os.environ.get('CHROMIUM_PATH') or shutil.which('chromium')
        browser = await p.chromium.launch(**({'executable_path': executable} if executable else {}),
                                          headless=True, args=['--no-sandbox'])
        try:
            for width, height in VIEWPORTS:
                mobile = width != 1280
                context = await browser.new_context(viewport={'width': width, 'height': height}, has_touch=mobile)
                geometry = layout(width, height)
                try:
                    for name in NAMES:
                        page = await context.new_page()
                        errors = []
                        page.on('pageerror', lambda error: errors.append(str(error)))
                        page.on('console', lambda message: errors.append(message.text) if message.type == 'error' and
                                ('SCRIPT ERROR' in message.text or 'Parse Error' in message.text) else None)
                        fixture = (FIXTURES / f'{name}.cfg').read_text()
                        reference = expected[(name, width)]
                        assert summary(parse_save(fixture)) == reference['before'], (name, width, 'Fixture/native mismatch')
                        await load_fixture(page, fixture, geometry, mobile)
                        before = summary(parse_save(await snapshot(page)))
                        assert before == reference['before'], (name, width, 'before', before, reference['before'])
                        await page.screenshot(path=str(OUT / f'{name}-before-{width}.png'))
                        await instrument(page)
                        await end_turn(page, geometry, mobile)
                        await await_saved_turn(page)
                        await page.wait_for_timeout(200)
                        after = summary(parse_save(await snapshot(page)))
                        performance = await trace_result(page)
                        assert after == reference['after'], (name, width, 'after', after, reference['after'])
                        assert all(e['intent'] == [-1, -1] for e in after['pieces']), (name, width, 'Hidden intent')
                        assert all(e['moves'] <= 1 for e in after['pieces']), (name, width, 'Multiple movements')
                        await page.screenshot(path=str(OUT / f'{name}-after-{width}.png'))
                        report = {'scenario': name, 'viewport': [width, height],
                                  'input': 'touch end-turn' if mobile else 'Space',
                                  'before': before, 'after': after, 'performance': performance,
                                  'motion': None, 'errors': errors}
                        reports.append(report)
                        write_report(reports)
                        performance_checks(performance, name, width)
                        if os.environ.get('YIXING_FULL_REGRESSION') == '1':
                            report['motion'] = await movement_film(context, page, geometry, mobile,
                                                                 f'{name}-motion-{width}', reference)
                        write_report(reports)
                        assert not errors, (name, width, errors)
                        print(json.dumps({'scenario': name, 'viewport': [width, height],
                                          'max_raf_ms': performance['max_raf_interval_ms'],
                                          'input_to_save_ms': performance['input_to_saved_turn_ms'],
                                          'motion_frames': report['motion']['frame_count'] if report['motion'] else None, 'errors': errors}), flush=True)
                        await page.close()
                finally:
                    await context.close()
        finally:
            await browser.close()


if __name__ == '__main__':
    asyncio.run(main())
