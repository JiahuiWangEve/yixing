"""Verify enemy collision excursions on the actual exported Web canvas.

Generate tests/enemy_impact_fixtures.gd first. Only ordinary production saves are
installed/read; gameplay is driven by Space and real touch events, with no game
object, runtime QA endpoint, or injected gameplay API. The compositor film must
show the attacker's own glyph leaving its square and returning. A line/flash or
an unchanged token cannot pass. Native tests separately cover settlement rules.

Run in the authorized CI browser. --validate-only performs no browser launch.
"""
import argparse
import asyncio
import base64
import hashlib
import io
import json
import math
import os
from pathlib import Path
import re
import shutil
import time

from PIL import Image, ImageChops, ImageDraw, ImageStat
from playwright.async_api import async_playwright

from browser_chapter_checks import assert_rendered, variant_json

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'verification/v0.15.5/enemy-impact'
URL = os.environ.get('YIXING_TEST_URL', 'http://127.0.0.1:8765')
KEY = 'yixing.route_run.v0149'
NAMES = {'cannon_hit', 'rook_hit', 'shield_block', 'lethal_hit'}
VIEWPORTS = {(1280, 940), (390, 844)}


def state(text):
    """Decode every saved field, retaining exact integer RNG and checkpoints."""
    assert text and text.startswith('[run]'), 'Missing production run save'
    fields = re.findall(r'^([A-Za-z_]\w*)=(.*?)(?=^[A-Za-z_]\w*=|\Z)',
                        text, re.M | re.S)
    result = {key: variant_json(value.strip()) for key, value in fields}
    assert {'version', 'normal_undos_remaining', 'route', 'battle', 'screen',
            'battle_start'} <= result.keys(), 'Incomplete production save envelope'
    # These are the only live render fields that change without player input.
    # Checkpoint fields are immutable, so even their visual data stays compared.
    result['battle'].pop('initial_threat', None)
    for enemy in result['battle']['enemies']:
        enemy.pop('visual', None)
    return result


def fixture(filename):
    return (OUT / 'fixtures' / filename).read_text()


def validate():
    manifest = json.loads((OUT / 'replays.json').read_text())
    assert manifest['schema'] == 1 and manifest['web_save_key'] == KEY
    replays = manifest['replays']
    assert len(replays) == 8 and {(r['name'], tuple(r['viewport'])) for r in replays} == {
        (name, size) for name in NAMES for size in VIEWPORTS}, 'Incomplete/duplicate collision matrix'
    for r in replays:
        before, after = state(fixture(r['initial'])), state(fixture(r['after']))
        a, b = before['battle'], after['battle']
        assert before['version'] == after['version'] == 6
        assert before['screen'] == after['screen'] == 'game'
        assert before['route'] == after['route'] and before['battle_start'] == after['battle_start']
        assert before['normal_undos_remaining'] == after['normal_undos_remaining']
        assert a['phase'] == 'play'
        assert [(e['uid'], e['kind'], e['pos']) for e in a['enemies']] == [
            (e['uid'], e['kind'], e['pos']) for e in b['enemies']], 'Fixture includes a logical enemy move'
        attacker = next(e for e in a['enemies'] if e['uid'] == r['attacker_uid'])
        assert attacker['kind'] == r['attacker_kind']
        assert all(e['cd'] >= 2 for e in a['enemies']), 'Fixture must isolate collision from movement'
        assert math.dist(r['source'], r['target']) >= 3 * r['cell_size'], 'Expected a clearly remote attacker'
        if r['name'] == 'shield_block':
            assert a['shield_charges'] == 1 and b['shield_charges'] == 0
            assert a['lives'] == b['lives'] and a['player'] == b['player']
            assert a['rng_state'] == b['rng_state']
        else:
            assert b['lives'] == a['lives'] - 1
            assert a['shield_charges'] == 0
        if r['name'] == 'lethal_hit':
            assert b['phase'] == 'dead' and b['lives'] == 0 and b['turn'] == a['turn']
            assert a['player'] == b['player'] and a['rng_state'] == b['rng_state']
        else:
            assert b['phase'] == 'play' and b['turn'] == a['turn'] + 1
            if r['name'] != 'shield_block':
                assert a['player'] != b['player'] and a['rng_state'] != b['rng_state']
        assert r['duration'] == .34 and r['impact_at'] == .14
        uw, uh = r['logical_size']
        for key in ('source', 'target', 'resume', 'end_turn'):
            x, y = r[key]
            assert 0 <= x < uw and 0 <= y < uh, (r['stem'], key)
        assert 0 < r['token_scale'] <= 1
        x, y, width, height = r['board_rect']
        assert 0 <= x < x + width <= uw and 0 <= y < y + height <= uh
    return replays


class Geometry:
    def __init__(self, replay):
        self.replay = replay
        w, h = replay['viewport']; uw, uh = replay['logical_size']
        self.scale = min(w / uw, h / uh)
        self.offset = ((w - uw * self.scale) / 2, (h - uh * self.scale) / 2)

    def point(self, value):
        return tuple(self.offset[i] + value[i] * self.scale for i in range(2))

    def box(self, value):
        x, y, w, h = value
        a, b = self.point((x, y)), self.point((x + w, y + h))
        return tuple(map(round, (*a, *b)))

    def board_present(self, image):
        # Sample the empty inner corner of the board, not an enemy or threat dot.
        x, y, _, _ = self.replay['board_rect']
        sample = image.crop(self.box((x + 6, y + 6, 7, 7)))
        pixels = list(sample.getdata())
        return sum(max(abs(p[i] - (210, 184, 140)[i]) for i in range(3)) <= 12
                   for p in pixels) / max(1, len(pixels)) > .75


class TokenTracker:
    """Match the real attacker's central glyph/paper pattern along its path.

    Unlike a dark-pixel or frame-difference test, this cannot confuse the new
    trail, the origin ring, or the red damage beam with a moving chess piece.
    Exclude the changing cooldown/HP badges and most of the circular border.
    """
    def __init__(self, baseline, replay, geometry):
        self.geometry = geometry
        self.source, target = geometry.point(replay['source']), geometry.point(replay['target'])
        distance = math.dist(self.source, target)
        self.direction = tuple((target[i] - self.source[i]) / distance for i in range(2))
        self.travel = distance - .34 * replay['cell_size'] * geometry.scale
        self.radius = max(7, round(14 * replay['token_scale'] * geometry.scale))
        self.template = baseline.crop(self.patch_box(self.source))
        pixels = list(self.template.getdata())
        assert sum(max(p) < 150 for p in pixels) >= max(10, len(pixels) * .06), 'Missing attacker glyph in baseline'
        assert sum(min(p) > 210 for p in pixels) >= len(pixels) * .25, 'Missing enemy paper face in baseline'

    def patch_box(self, center):
        x, y = map(round, center); r = self.radius
        return x - r, y - r, x + r + 1, y + r + 1

    def error(self, image, center):
        return sum(ImageStat.Stat(ImageChops.difference(
            self.template, image.crop(self.patch_box(center)))).mean) / 3

    def measure(self, data):
        image = Image.open(io.BytesIO(data)).convert('RGB')
        # Integer pixel candidates avoid accidentally skipping a narrow phone
        # glyph. A two-pixel coarse pass plus local refinement remains inexpensive.
        def candidate(distance):
            point = tuple(self.source[i] + self.direction[i] * distance for i in range(2))
            return self.error(image, point), distance, point
        best = min((candidate(float(d)) for d in range(0, math.ceil(self.travel) + 1, 2)), key=lambda x: x[0])
        best = min((candidate(d) for d in [best[1] + offset for offset in (-1, 0, 1)]
                    if 0 <= d <= self.travel), key=lambda x: x[0])
        error, distance, point = best
        home_error = self.error(image, self.source)
        return {'match_error': round(error, 3), 'home_error': round(home_error, 3),
                'progress': round(distance / self.travel, 4), 'center': list(point),
                'matched': error < 27, 'board_visible': self.geometry.board_present(image)}


def motion_evidence(metrics, lethal=False):
    usable = [(i, m) for i, m in enumerate(metrics) if m['matched'] and m['board_visible']]
    assert usable, 'No recognizable attacker in compositor frames'
    peak_index, peak = max(usable, key=lambda item: item[1]['progress'])
    assert peak['progress'] >= .50 and peak['home_error'] > 30, (
        'Attacker never visibly left its square toward the player', peak)
    outward = next(((i, m) for i, m in usable if i < peak_index and m['progress'] < .25), None)
    assert outward is not None, 'Missing pre-excursion origin frame'
    if lethal:
        # Death deliberately covers the board at the end of the same .34s
        # excursion. Do not demand a source frame hidden by the death overlay.
        ended = next(((i, m) for i, m in enumerate(metrics) if i > peak_index and not m['board_visible']), None)
        assert ended is not None, 'Lethal attack did not finish visibly at the death screen'
        return {'before': outward[0], 'approach': peak_index, 'death': ended[0]}
    returning = next(((i, m) for i, m in usable if i > peak_index and
                      .10 < m['progress'] < peak['progress'] * .80), None)
    assert returning is not None, ('Missing visible return leg', peak, metrics)
    restored = next(((i, m) for i, m in usable if i > returning[0] and
                     m['progress'] < .06 and m['home_error'] < 27), None)
    assert restored is not None, 'Attacker never returned visibly to its original square'
    return {'before': outward[0], 'approach': peak_index,
            'return': returning[0], 'restored': restored[0]}


def save_film(folder, frames, metrics, selected, geometry):
    folder.mkdir(parents=True, exist_ok=True)
    manifest = []
    start = frames[0][0] if frames else 0
    for number, (stamp, data) in enumerate(frames):
        filename = f'{number:03d}.jpg'; (folder / filename).write_bytes(data)
        manifest.append({'frame': number, 'elapsed_ms': round((stamp - start) * 1000, 3),
                         'file': filename, **metrics[number]})
    (folder / 'frames.json').write_text(json.dumps(manifest, indent=2))
    tiles = []
    # Keep complete original frames as well as a labeled, human-readable filmstrip.
    if not selected and frames:
        selected = {f'sample-{i}': round(i * (len(frames) - 1) / 5) for i in range(6)}
    for label, number in selected.items():
        im = Image.open(io.BytesIO(frames[number][1])).convert('RGB')
        im.save(folder.parent / f'{folder.name}-{label}.png')
        crop = im.crop(geometry.box(geometry.replay['board_rect']))
        crop.thumbnail((265, 290))
        tile = Image.new('RGB', (285, 330), 'white'); tile.paste(crop, ((285 - crop.width) // 2, 30))
        draw = ImageDraw.Draw(tile)
        draw.text((8, 7), f'{label}: frame {number}, {manifest[number]["elapsed_ms"]:.0f}ms', fill='black')
        tiles.append(tile)
    if tiles:
        sheet = Image.new('RGB', (285 * len(tiles), 330), '#ddd')
        for i, tile in enumerate(tiles): sheet.paste(tile, (i * 285, 0))
        sheet.save(folder.parent / f'{folder.name}-contact.png')
    return manifest


async def main(validate_only=False):
    replays = validate()
    if validate_only:
        print(json.dumps({'validated_replays': len(replays), 'viewports': sorted(VIEWPORTS),
                          'rendered': False, 'omitted_gameplay_fields': [],
                          'manifest_sha256': hashlib.sha256((OUT / 'replays.json').read_bytes()).hexdigest()}))
        return
    output = OUT / 'browser'; output.mkdir(parents=True, exist_ok=True)
    reports = []; started = time.monotonic()
    async with async_playwright() as p:
        executable = os.environ.get('CHROMIUM_PATH') or shutil.which('chromium')
        browser = await p.chromium.launch(**({'executable_path': executable} if executable else {}),
                                          headless=True, args=['--no-sandbox'])
        try:
            # Two contexts, eight reloads: retain the compiled Web runtime cache
            # without sharing scenario state or slowing the small release gate.
            for viewport in sorted(VIEWPORTS, reverse=True):
                w, h = viewport
                context = await browser.new_context(viewport={'width': w, 'height': h}, has_touch=True)
                page = await context.new_page(); cdp = await context.new_cdp_session(page)
                errors = []
                page.on('pageerror', lambda e: errors.append(str(e)))
                page.on('console', lambda m: errors.append(m.text) if m.type == 'error' and
                        ('SCRIPT ERROR' in m.text or 'Parse Error' in m.text) else None)
                try:
                    for replay in [r for r in replays if tuple(r['viewport']) == viewport]:
                        stem = replay['stem']; geometry = Geometry(replay)
                        before, after = state(fixture(replay['initial'])), state(fixture(replay['after']))
                        frames = []; metrics = []; selected = {}; ack_tasks = []; recording = False

                        async def raw():
                            return await page.evaluate('(key) => localStorage.getItem(key)', KEY)

                        async def tap(point):
                            x, y = geometry.point(point)
                            await page.touchscreen.tap(x, y)

                        async def expect(expected, label, stable=.12, timeout=10):
                            deadline = time.monotonic() + timeout; since = None
                            while True:
                                observed = state(await raw())
                                if observed == expected:
                                    since = since or time.monotonic()
                                    if time.monotonic() - since >= stable: return
                                else: since = None
                                assert time.monotonic() < deadline, (stem, label, observed, expected)
                                await asyncio.sleep(.04)

                        def receive_frame(event):
                            frames.append((event['metadata'].get('timestamp', 0), base64.b64decode(event['data'])))
                            ack_tasks.append(asyncio.create_task(cdp.send('Page.screencastFrameAck',
                                                                         {'sessionId': event['sessionId']})))
                        try:
                            # Seed once per navigation, not per reload init script:
                            # the subsequent proof reads saves written by the game.
                            if page.url == 'about:blank':
                                await page.add_init_script('if (!sessionStorage.getItem("impact-seeded")) {'
                                    'localStorage.setItem(%s,%s); sessionStorage.setItem("impact-seeded","1");}' %
                                    (json.dumps(KEY), json.dumps(fixture(replay['initial']))))
                                await page.goto(URL)
                            else:
                                await page.evaluate('([key,value]) => localStorage.setItem(key,value)',
                                                    [KEY, fixture(replay['initial'])])
                                await page.reload()
                            await page.wait_for_function("!document.getElementById('status')", timeout=60000)
                            await page.evaluate('() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)))')
                            await tap(replay['resume'])
                            deadline = time.monotonic() + 10
                            while True:
                                baseline_data = await page.screenshot()
                                baseline = Image.open(io.BytesIO(baseline_data)).convert('RGB')
                                if geometry.board_present(baseline): break
                                assert time.monotonic() < deadline, (stem, 'Continue did not show the board')
                                await asyncio.sleep(.04)
                            assert_rendered(baseline_data, viewport)
                            (output / f'{stem}-before.png').write_bytes(baseline_data)
                            await expect(before, 'ordinary Continue restores entire fixture')
                            tracker = TokenTracker(baseline, replay, geometry)
                            # DOM input observation only, never engine instrumentation.
                            await page.evaluate('''() => {
                                window.impactInputs = [];
                                for (const kind of ['keydown', 'touchend'])
                                  document.addEventListener(kind, e => window.impactInputs.push({
                                    kind, key: e.key || null, at: performance.now()}), {capture:true});
                            }''')
                            cdp.on('Page.screencastFrame', receive_frame)
                            await cdp.send('Page.startScreencast', {'format': 'jpeg', 'quality': 95, 'everyNthFrame': 1})
                            recording = True
                            deadline = time.monotonic() + 5
                            while len(frames) < 2:
                                assert time.monotonic() < deadline, (stem, 'No baseline compositor frames')
                                await asyncio.sleep(.015)
                            # The immediate second request must be rejected while
                            # the first attack excursion owns the input lock.
                            if w == 1280:
                                await page.keyboard.press('Space'); await page.keyboard.press('Space')
                            else:
                                await tap(replay['end_turn']); await tap(replay['end_turn'])
                            await expect(after, 'single turn only, exact HP/RNG/cards/route/checkpoint')
                            final_data = await page.screenshot(path=str(output / f'{stem}-settled.png'))
                            assert_rendered(final_data, viewport)
                            await cdp.send('Page.stopScreencast'); recording = False
                            await asyncio.gather(*ack_tasks)
                            cdp.remove_listener('Page.screencastFrame', receive_frame)
                            inputs = await page.evaluate('window.impactInputs')
                            assert len(inputs) == 2, (stem, 'Wrong input burst', inputs)
                            assert inputs[1]['at'] - inputs[0]['at'] < 200, (stem, 'Duplicate input was not delivered within the collision lock', inputs)
                            (output / f'{stem}-observed.cfg').write_text(await raw())
                            assert len(frames) >= 5, (stem, 'Too few actual compositor frames', len(frames))
                            metrics = [tracker.measure(data) for _, data in frames]
                            selected = motion_evidence(metrics, replay['name'] == 'lethal_hit')
                            if replay['name'] == 'lethal_hit':
                                assert not geometry.board_present(Image.open(io.BytesIO(final_data)).convert('RGB'))
                            else:
                                final_metric = tracker.measure(final_data)
                                assert final_metric['matched'] and final_metric['progress'] < .06, (stem, final_metric)
                            assert not errors, (stem, errors)
                            report = {'scenario': replay['name'], 'viewport': list(viewport),
                                      'frames': len(frames), 'selected_frames': selected,
                                      'inputs': inputs, 'exact_save_match': True,
                                      'before': before, 'after': state(await raw()), 'errors': errors.copy()}
                            reports.append(report)
                            (output / 'results.json').write_text(json.dumps({'reports': reports,
                                'elapsed_seconds': round(time.monotonic() - started, 2),
                                'notes': ['Actual exported Web, normal Continue and Space/touch, no gameplay hook.',
                                          'Every gameplay field and RNG compared; only live rendered position and initial threat timer omitted.',
                                          'Source glyph, outbound motion, return leg and restored square are required, not just a hit flash.',
                                          'Lethal cases require visible approach before the final death overlay.']},
                                ensure_ascii=False, indent=2))
                            print('PASS enemy impact Web', stem, len(frames), 'real frames', flush=True)
                        finally:
                            if recording: await cdp.send('Page.stopScreencast')
                            if ack_tasks: await asyncio.gather(*ack_tasks, return_exceptions=True)
                            cdp.remove_listener('Page.screencastFrame', receive_frame)
                            if frames:
                                if not metrics and 'tracker' in locals(): metrics = [tracker.measure(data) for _, data in frames]
                                if not metrics: metrics = [{} for _ in frames]
                                save_film(output / stem, frames, metrics, selected, geometry)
                finally:
                    await cdp.detach(); await context.close()
        finally:
            await browser.close()
    assert len(reports) == 8
    print(json.dumps({'replays': len(reports), 'real_frames': sum(r['frames'] for r in reports),
                      'elapsed_seconds': round(time.monotonic() - started, 2), 'errors': 0}))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--validate-only', action='store_true')
    args = parser.parse_args()
    asyncio.run(main(args.validate_only))
