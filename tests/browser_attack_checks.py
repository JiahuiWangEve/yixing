"""Attack range/gesture Web gate using normal input and production saved games.

Generate attack_ui_checks.gd first. JavaScript only installs/reads the ordinary
localStorage save envelope. No game references, debug hooks or test exports.
Basic: 3 scenarios x desktop/phone. --full: 8 scenarios x 4 viewports, plus full
catalog consumption detail and touch cancellation/multitouch/drag guards.
Run this only in the authorized real-Web CI browser, not a local GUI substitute.
"""
import argparse
import asyncio
import hashlib
import io
import json
import math
import os
from pathlib import Path
import shutil
import time

from PIL import Image
from playwright.async_api import async_playwright
from browser_chapter_checks import assert_rendered, inspection_save
from browser_card_catalog_checks import scroll_plan, drag_points, drag_fractions

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'verification/v0.15.1/attack-ui'
URL = os.environ.get('YIXING_TEST_URL', 'http://127.0.0.1:8765')
KEY = 'yixing.route_run.v0149'
CASES = {'sword_unique', 'sword_multiple', 'sweep', 'blood_unique',
         'blood_multiple', 'blood_break', 'airdrop', 'chain_bonus'}
SIZES = {(1280, 940), (390, 844), (360, 640), (844, 390)}


def state(text):
    # Only initial_threat and enemy.visual are visual-only. In particular keep
    # every RNG, HP, economy, hand-copy UID, delayed effect, route and undo field.
    return inspection_save(text)


def fixture_state(filename):
    return state((OUT / 'fixtures' / filename).read_text())


def validate():
    data = json.loads((OUT / 'replays.json').read_text())
    assert data['schema'] == 1 and data['web_save_key'] == KEY
    replays = data['replays']
    assert {(r['name'], tuple(r['viewport'])) for r in replays} == {
        (name, size) for name in CASES for size in SIZES}
    assert len(replays) == 32
    for r in replays:
        before, selected, after = [fixture_state(r[k]) for k in ('initial', 'selected', 'after')]
        assert before['screen'] == selected['screen'] == after['screen'] == 'game'
        assert before['route'] == selected['route'] == after['route']
        changed = {k for k in before['battle'] if before['battle'][k] != selected['battle'][k]}
        assert changed <= {'notice'}, (r['stem'], 'Selecting mutates gameplay', changed)
        assert before['battle']['hand'] == [r['card']] and after['battle']['hand'] == []
        assert after['battle']['turn'] == before['battle']['turn']
        assert after['battle']['energy'] < before['battle']['energy']
        assert all(enemy['hp'] > 0 for enemy in after['battle']['enemies'])
        if r['name'] in {'sword_multiple', 'blood_multiple', 'airdrop'}:
            assert fixture_state(r['after_upward']) == selected
            assert r['actions'] > 1
        else:
            assert r['actions'] == 1
        if r['name'] == 'sword_unique':
            passed = fixture_state(r['after_pass'])['battle']
            assert passed['energy'] == before['battle']['energy'] - 3
            assert passed['hand'] == ['breath'] and passed['discard'] == ['sword']
            assert passed['enemies'] == before['battle']['enemies']
            board = fixture_state(r['after_board'])
            assert board['route'] == after['route'] and board['screen'] == after['screen']
            assert {k for k in board['battle'] if board['battle'][k] != after['battle'][k]} <= {'notice'}
        if r['name'] == 'airdrop':
            assert not r['range']['squares'] and not r['range']['rings']
            assert after['battle']['player'] == [4, 3]
            assert after['battle']['lives'] == before['battle']['lives'] - 1
            assert after['battle']['airdrop_recovery_turn'] == 2
        else:
            assert r['range']['squares'] and r['range']['rings'] and r['range']['empty']
        if r['name'] in {'blood_unique', 'blood_multiple', 'blood_break', 'airdrop'}:
            assert r['face']['short'].startswith('命−1；')
            assert r['face']['detail'].startswith('命−1；')
        if r['name'] == 'blood_break':
            assert '消耗：一局战斗只能用一次。' in r['face']['detail']
            assert '消耗：一局战斗只能用一次。' in r['catalog']['detail']
        if r['name'] == 'chain_bonus':
            assert '本回合主动位移次数+1' in r['face']['short']
            assert '当前5' in r['face']['short']
            assert before['route']['chapter'] == 2 and before['route']['treasure_id'] == 'battle_tassel'
            assert before['battle']['treasure_battle']['tassel_ready']
            assert not after['battle']['treasure_battle']['tassel_ready']
            assert before['battle']['enemies'][1]['hp'] - after['battle']['enemies'][1]['hp'] == 5
        uw, uh = r['logical_size']
        for key in ('card_point', 'selected_point', 'upward', 'generic_board', 'target', 'invalid_target', 'pass', 'resume'):
            x, y = r[key]
            assert 0 <= x < uw and 0 <= y < uh, (r['stem'], key, r[key])
        assert r['face']['font_size'] >= 12 and r['face']['rows'] and r['face']['complete']
    return replays


def near(pixel, color, tolerance=8):
    return max(abs(a - b) for a, b in zip(pixel, color)) <= tolerance


def color_count(image, box, color, tolerance=8):
    pixels = list(image.crop(box).getdata())
    return sum(near(pixel, color, tolerance) for pixel in pixels), len(pixels)


def text_ink_metrics(image, box, paper, ink):
    """Measure antialiased text as the physical paper-to-ink mixture.

    Small Chinese glyphs at fractional Web scales need not contain any fully
    opaque ink pixel. Project onto the exact palette line instead of requiring
    an arbitrary near-black RGB cutoff. The 25% ink coverage floor rejects
    almost-paper noise, and residual <=8 excludes green/red UI decorations.
    """
    direction = [a - b for a, b in zip(ink, paper)]
    denominator = sum(c * c for c in direction)
    visible = 0; mass = 0.0; peak = 0.0
    for pixel in image.crop(box).getdata():
        alpha = sum((p - b) * d for p, b, d in zip(pixel, paper, direction)) / denominator
        residual = max(abs(p - (b + alpha * d)) for p, b, d in zip(pixel, paper, direction))
        if .25 <= alpha <= 1.08 and residual <= 8:
            visible += 1; mass += min(1., alpha); peak = max(peak, min(1., alpha))
    return {'visible_ink_pixels': visible, 'ink_coverage_mass': round(mass, 3),
            'peak_ink_coverage': round(peak, 3), 'pixel_box': list(box)}


def text_rows_evidence(image, rows, mapper, paper, ink, scale):
    result = []
    for row in rows:
        if not row['text'].strip(): continue
        measured = text_ink_metrics(image, mapper(row['rect']), paper, ink)
        chars = len(row['text'].strip())
        measured.update({'text': row['text'], 'font_size': row['font_size'],
                         'font_ascent': row['font_ascent'], 'font_descent': row['font_descent'],
                         'baseline': row['baseline'], 'text_advance': row['text_advance'],
                         'logical_rect': row['rect'], 'physical_transform': row['physical_transform']})
        measured['readable'] = (measured['visible_ink_pixels'] >= max(3, chars * scale * 1.2)
                                and measured['ink_coverage_mass'] >= max(2, chars * scale * .75))
        result.append(measured)
    return bool(result) and all(row['readable'] for row in result), result


def range_ring_metrics(image, centers, geometry, palette, mapper, sx, sy):
    """Exact attack annulus, excluding the independently green countdown HUD."""
    radius = geometry['cell_size'] * .49
    hud = geometry['ring_hud']; result = []
    for center in centers:
        pt = mapper(center); hits = total = excluded = 0
        for y in range(math.floor(pt['y'] - (radius + 3) * sy), math.ceil(pt['y'] + (radius + 3) * sy)):
            for x in range(math.floor(pt['x'] - (radius + 3) * sx), math.ceil(pt['x'] + (radius + 3) * sx)):
                dx, dy = (x + .5 - pt['x']) / sx, (y + .5 - pt['y']) / sy
                if abs(math.hypot(dx, dy) - radius) > max(1.4 / min(sx, sy), 1.8): continue
                bx, by = hud['badge_offset']; hx, hy, hw, hh = hud['hp_box']
                if (math.hypot(dx - bx, dy - by) <= hud['badge_radius'] + 2
                        or hx - 1 <= dx <= hx + hw + 1 and hy - 1 <= dy <= hy + hh + 1):
                    excluded += 1; continue
                total += 1
                if near(image.getpixel((x, y)), palette['legal'], 12): hits += 1
        result.append({'center': center, 'legal_ink_pixels': hits, 'annulus_pixels': total,
                       'excluded_hud_pixels': excluded, 'hud_geometry': hud})
    return result


async def main(full=False, validate_only=False):
    replays = validate()
    selected = [r for r in replays if full or (r['basic'] and r['viewport'][0] in (1280, 390))]
    assert len(selected) == (32 if full else 6)
    if validate_only:
        print(json.dumps({'validated_fixtures': len(replays), 'selected_replays': len(selected),
                          'viewports': sorted({tuple(r['viewport']) for r in selected}),
                          'rendered': False, 'gameplay_fields_omitted': [],
                          'manifest_sha256': hashlib.sha256((OUT / 'replays.json').read_bytes()).hexdigest()}))
        return
    output = OUT / ('browser-full' if full else 'browser-smoke')
    output.mkdir(parents=True, exist_ok=True)
    reports = []
    started = time.monotonic()
    async with async_playwright() as p:
        executable = os.environ.get('CHROMIUM_PATH') or shutil.which('chromium')
        browser = await p.chromium.launch(**({'executable_path': executable} if executable else {}),
                                          headless=True, args=['--no-sandbox'])
        try:
            # Reuse one actual Web context per viewport, but reload every fixture.
            # This keeps the basic gate bounded without runtime game instrumentation.
            for viewport in sorted({tuple(r['viewport']) for r in selected}):
                w, h = map(int, viewport)
                context = await browser.new_context(viewport={'width': w, 'height': h}, has_touch=True)
                page = await context.new_page()
                cdp = await context.new_cdp_session(page)
                errors = []
                page.on('pageerror', lambda e: errors.append(str(e)))
                page.on('console', lambda m: errors.append(m.text) if m.type == 'error'
                        and ('SCRIPT ERROR' in m.text or 'Parse Error' in m.text) else None)
                try:
                    for r in [r for r in selected if tuple(r['viewport']) == viewport]:
                        stem = r['stem']; screenshots = []; metrics = []; save_waits = []
                        uw, uh = r['logical_size']; scale = min(w / uw, h / uh)
                        ox, oy = (w - uw * scale) / 2, (h - uh * scale) / 2
                        desktop = w == 1280

                        def xy(pos): return {'x': ox + pos[0] * scale, 'y': oy + pos[1] * scale}
                        def box(rect, inset=0):
                            x, y, rw, rh = rect
                            return (math.floor(ox + (x + inset) * scale), math.floor(oy + (y + inset) * scale),
                                    math.ceil(ox + (x + rw - inset) * scale), math.ceil(oy + (y + rh - inset) * scale))
                        async def raw(): return await page.evaluate('(key) => localStorage.getItem(key)', KEY)
                        async def tap(pos):
                            pt = xy(pos)
                            if desktop:
                                await page.mouse.click(pt['x'], pt['y']); await page.mouse.move(2, 2)
                            else: await page.touchscreen.tap(pt['x'], pt['y'])
                        async def drag(a, b, back=False, cancel=False, force_touch=False):
                            first, end = xy(a), xy(b)
                            touch = force_touch or not desktop
                            if touch: await cdp.send('Input.dispatchTouchEvent', {'type': 'touchStart', 'touchPoints': [{**first, 'id': 1}]})
                            else: await page.mouse.move(first['x'], first['y']); await page.mouse.down()
                            for fraction in (.25, .5, .75, 1):
                                pt = {k: first[k] + (end[k] - first[k]) * fraction for k in ('x', 'y')}
                                if touch: await cdp.send('Input.dispatchTouchEvent', {'type': 'touchMove', 'touchPoints': [{**pt, 'id': 1}]})
                                else: await page.mouse.move(pt['x'], pt['y'])
                            if back:
                                if touch: await cdp.send('Input.dispatchTouchEvent', {'type': 'touchMove', 'touchPoints': [{**first, 'id': 1}]})
                                else: await page.mouse.move(first['x'], first['y'])
                            if touch: await cdp.send('Input.dispatchTouchEvent', {'type': 'touchCancel' if cancel else 'touchEnd', 'touchPoints': []})
                            else: await page.mouse.up(); await page.mouse.move(2, 2)
                        async def expect(expected, label, stable=0):
                            deadline = time.monotonic() + 10; since = None; begin = time.monotonic()
                            while True:
                                observed = state(await raw())
                                if observed == expected:
                                    since = since or time.monotonic()
                                    if time.monotonic() - since >= stable:
                                        save_waits.append({'label': label, 'ms': round((time.monotonic() - begin) * 1000)})
                                        return
                                else: since = None
                                assert time.monotonic() < deadline, (stem, label, observed, expected)
                                await page.wait_for_timeout(80)
                        async def shot(label):
                            filename = f'{stem}-{label}.png'
                            data = await page.screenshot(path=str(output / filename)); assert_rendered(data, [w, h])
                            screenshots.append({'file': filename, 'sha256': hashlib.sha256(data).hexdigest()})
                            return data
                        async def until_image(predicate, label, timeout=6):
                            deadline = time.monotonic() + timeout
                            while True:
                                data = await page.screenshot(); image = Image.open(io.BytesIO(data)).convert('RGB')
                                ok, result = predicate(image)
                                if ok: return data, result
                                if time.monotonic() >= deadline:
                                    # Save the exact failed predicate frame and its
                                    # geometry/palette proof, not just a later catch.
                                    safe_label = ''.join(ch if ch.isalnum() else '-' for ch in label).strip('-')
                                    (output / f'{stem}-{safe_label}-failed.png').write_bytes(data)
                                    (output / f'{stem}-{safe_label}-failed.json').write_text(
                                        json.dumps({'label': label, 'viewport': [w, h], 'logical_size': [uw, uh],
                                                    'scale': scale, 'offset': [ox, oy], 'evidence': result},
                                                   ensure_ascii=False, indent=2))
                                    raise AssertionError((stem, label, result))
                                await page.wait_for_timeout(80)
                        def board_visible(image):
                            x, y, _, _ = r['range']['board']
                            count, total = color_count(image, box([x + 10, y + 10, 8, 8]), r['range']['colors']['board'], 5)
                            return count / max(1, total) > .75, {'board_color_pixels': count, 'total': total}
                        async def install(filename, first=False):
                            text = (OUT / 'fixtures' / filename).read_text()
                            if first:
                                await page.add_init_script("if (!sessionStorage.getItem('attack-seeded')) { localStorage.setItem(%s,%s); sessionStorage.setItem('attack-seeded','1'); }" % (json.dumps(KEY), json.dumps(text)))
                                await page.goto(URL)
                            else:
                                await page.evaluate('([key,text]) => localStorage.setItem(key,text)', [KEY, text]); await page.reload()
                            await page.wait_for_function("!document.getElementById('status')", timeout=60000)
                            await tap(r['resume'])
                            await until_image(board_visible, 'ordinary Continue reaches board', 10)
                            await expect(fixture_state(filename), 'ordinary save resumes')
                        def ring_metrics(image, centers):
                            return range_ring_metrics(image, centers, r['range'], r['range']['colors'], xy, scale, scale)
                        def range_visible(image):
                            if not r['range']['rings']:
                                rings = ring_metrics(image, r['enemy_centers'])
                                return all(item['legal_ink_pixels'] <= 3 for item in rings), {'no_projected_airdrop_range': rings}
                            fills = []
                            for sample in r['range']['empty']:
                                x, y = sample['sample']
                                count, total = color_count(image, box([x - 1.5, y - 1.5, 3, 3]), r['range']['colors']['fill'], 5)
                                fills.append({'cell': sample['cell'], 'exact_fill_pixels': count, 'pixels': total})
                            rings = ring_metrics(image, [e['center'] for e in r['range']['rings']])
                            filled = sum(item['exact_fill_pixels'] >= max(1, item['pixels'] * .45) for item in fills)
                            strong = all(item['legal_ink_pixels'] >= max(8, item['annulus_pixels'] * .12) for item in rings)
                            return filled >= 1 and strong, {'empty_legal_squares': fills, 'strong_enemy_rings': rings, 'palette': r['range']['colors']}
                        def face_visible(image):
                            ok, rows = text_rows_evidence(image, r['face']['rows'], box,
                                                         r['range']['colors']['hand'], r['range']['colors']['ink'], scale)
                            blank = text_ink_metrics(image, box(r['face']['blank_control']),
                                                     r['range']['colors']['hand'], r['range']['colors']['ink'])
                            return ok and blank['visible_ink_pixels'] == 0, {'rows': rows, 'blank_paper_control': blank}
                        async def select_card():
                            await tap(r['card_point'])
                            await expect(fixture_state(r['selected']), 'selection changes notice only, never spends/plays')
                            _, result = await until_image(range_visible, 'exact legal-square and enemy-ring palette')
                            metrics.append(result)
                            if full:
                                _, face_result = await until_image(face_visible, 'normalized focused face rows')
                                metrics.append({'focused_face_rows': face_result})
                            await shot('selected-range-and-detail')
                        async def guard_inputs():
                            chosen = fixture_state(r['selected']); source = r['selected_point']
                            await drag(source, r['upward'], cancel=True, force_touch=True)
                            await expect(chosen, 'touchCancel does not play', stable=1.15)
                            await drag(source, r['upward'], back=True)
                            await expect(chosen, 'drag back to hand does not play', stable=1.15)
                            # A microdrag is a tap/selection toggle, never a play.
                            await drag(source, [source[0] + 3, source[1] - 3])
                            await expect(chosen, 'microdrag cannot spend or play', stable=1.15)
                            await tap(r['card_point']); await until_image(range_visible, 'restore selected range after microdrag')
                            a, b = xy(source), xy([source[0] + 25, source[1]])
                            await cdp.send('Input.dispatchTouchEvent', {'type': 'touchStart', 'touchPoints': [{**a, 'id': 1}]})
                            await cdp.send('Input.dispatchTouchEvent', {'type': 'touchStart', 'touchPoints': [{**a, 'id': 1}, {**b, 'id': 2}]})
                            await cdp.send('Input.dispatchTouchEvent', {'type': 'touchEnd', 'touchPoints': [{**b, 'id': 2}]})
                            await cdp.send('Input.dispatchTouchEvent', {'type': 'touchEnd', 'touchPoints': []})
                            await expect(chosen, 'multitouch cannot play', stable=1.15)
                            await drag(source, r['invalid_target'])
                            await expect(chosen, 'invalid explicit enemy aim never redirects to unique victim', stable=1.15)
                            await shot('guarded-release-still-selected')
                        async def catalog_detail():
                            c = r['catalog']
                            # Reload goes to the ordinary home screen. Open the
                            # shipped role-selection catalog, not a test-only modal.
                            await page.reload(); await page.wait_for_function("!document.getElementById('status')", timeout=60000)
                            await tap(c['start']); await tap(c['open']); await tap(c['tab'])
                            current = 0
                            moves, current = scroll_plan(c['grid'], current, c['scroll'], c['scroll_limit'])
                            for delta in moves:
                                a, b = drag_points(c['grid'], delta)
                                first, last = xy(a), xy(b)
                                await cdp.send('Input.dispatchTouchEvent', {'type': 'touchStart', 'touchPoints': [{**first, 'id': 1}]})
                                for fraction in drag_fractions(delta):
                                    pt = {k: first[k] + (last[k] - first[k]) * fraction for k in ('x', 'y')}
                                    await cdp.send('Input.dispatchTouchEvent', {'type': 'touchMove', 'touchPoints': [{**pt, 'id': 1}]})
                                await cdp.send('Input.dispatchTouchEvent', {'type': 'touchEnd', 'touchPoints': []})
                            await tap([c['tap'][0], c['tap'][1] + c['scroll'] - current])
                            async def inspect_catalog_rows(scroll, label):
                                def readable(image):
                                    rows = []
                                    gx, gy, gw, gh = c['grid']
                                    for row in c['rows']:
                                        x, y, rw, rh = row['rect']; y -= scroll
                                        if y < gy + 2 or y + rh > gy + gh - 2: continue
                                        rows.append({**row, 'rect': [x, y, rw, rh],
                                                     'baseline': [row['baseline'][0], row['baseline'][1] - scroll]})
                                    return text_rows_evidence(image, rows, box,
                                                              r['range']['colors']['surface'], r['range']['colors']['ink'], scale)
                                _, found = await until_image(readable, label); metrics.append({'catalog_rows': found})
                                await shot(label)
                            await inspect_catalog_rows(0, 'catalog-self-cost-top')
                            # Scroll only if the actual final rule extends past the clip.
                            # Card height includes intentional blank paper; scrolling to
                            # that bottom can move every rule above the viewport.
                            last_rule_bottom = max(row['rect'][1] + row['rect'][3] for row in c['rows'])
                            rule_scroll = min(c['detail_scroll_limit'], max(0, last_rule_bottom - (c['grid'][1] + c['grid'][3]) + 2))
                            moves, current = scroll_plan(c['grid'], 0, rule_scroll, c['detail_scroll_limit'], exact_end=rule_scroll == c['detail_scroll_limit'])
                            for delta in moves:
                                a, b = drag_points(c['grid'], delta)
                                # First motion exceeds the deadzone so none of
                                # the intended scroll distance is lost.
                                first, last = xy(a), xy(b)
                                await cdp.send('Input.dispatchTouchEvent', {'type': 'touchStart', 'touchPoints': [{**first, 'id': 1}]})
                                for fraction in drag_fractions(delta):
                                    pt = {k: first[k] + (last[k] - first[k]) * fraction for k in ('x', 'y')}
                                    await cdp.send('Input.dispatchTouchEvent', {'type': 'touchMove', 'touchPoints': [{**pt, 'id': 1}]})
                                await cdp.send('Input.dispatchTouchEvent', {'type': 'touchEnd', 'touchPoints': []})
                            await inspect_catalog_rows(current, 'catalog-complete-consumption-rule')
                            await expect(fixture_state(r['after']), 'catalog detail changes no run data', stable=1.15)

                        try:
                            await install(r['initial'], first=page.url == 'about:blank')
                            await shot('before-selection')
                            await select_card()
                            if r['name'] == 'sword_unique': await guard_inputs()
                            await drag(r['selected_point'], r['upward'])
                            if 'after_upward' in r:
                                await expect(fixture_state(r['after_upward']), 'ambiguous/airdrop upward release is inert', stable=1.15)
                                await shot('upward-no-auto-choice')
                                await drag(r['selected_point'], r['target'])
                            await expect(fixture_state(r['after']), 'release commits exact one attack')
                            # CDP cannot deliver touchEnd after the contact ended.
                            # Native attack_targeting_checks exercises duplicate
                            # release directly; Web verifies one physical release
                            # followed by stable, exactly-once persisted results.
                            await expect(fixture_state(r['after']), 'released attack remains committed exactly once', stable=1.15)
                            await shot('played-once')
                            if r['name'] == 'sword_unique':
                                await install(r['initial']); await drag(r['card_point'], r['generic_board'])
                                await expect(fixture_state(r['after_board']), 'generic board drop resolves unique victim')
                                await shot('generic-board-shortcut')
                                await install(r['initial']); await drag(r['card_point'], r['pass'])
                                await expect(fixture_state(r['after_pass']), 'discard is exactly three fee plus one draw, no attack')
                                await shot('discard-still-three-fee-draw')
                            if full and r['name'] == 'blood_break': await catalog_detail()
                            assert not errors, errors
                            reports.append({'name': stem, 'viewport': [w, h], 'screenshots': screenshots,
                                            'roi_evidence': metrics, 'save_waits': save_waits, 'errors': list(errors)})
                            print('PASS attack Web', stem, 'exact saves / range palette / pointer release', flush=True)
                        except Exception:
                            await page.screenshot(path=str(output / f'{stem}-failure.png')); raise
                finally:
                    await cdp.detach(); await context.close()
        finally: await browser.close()
    result = {'replays': len(reports), 'elapsed_seconds': round(time.monotonic() - started, 2), 'cases': reports}
    (output / 'results.json').write_text(json.dumps(result, ensure_ascii=False, indent=2))
    print('ATTACK WEB RESULT', len(reports), 'actual exported Web cases')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--full', action='store_true')
    parser.add_argument('--validate-only', action='store_true')
    args = parser.parse_args()
    asyncio.run(main(args.full, args.validate_only))
