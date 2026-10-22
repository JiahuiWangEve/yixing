"""Real exported-UI inspection, hold suppression, HP and precise attack preview.

Generate board_info_web_fixtures.gd in the integrated project. Browser JS only
seeds/reads ordinary production save text, never invokes runtime game methods.
Default 1280/390; --full adds 360/844. --validate-only does no browser work.
"""
import argparse, asyncio, io, json, os, re, shutil
from pathlib import Path
from PIL import Image, ImageChops, ImageStat
from playwright.async_api import async_playwright
from browser_settings import install_debug_settings
from browser_event_checks import KEY, boot, variant_json
from browser_chapter_checks import assert_rendered
ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'verification/v0.14.7/board-info'
URL = os.environ.get('YIXING_TEST_URL', 'http://127.0.0.1:8765')

def state(text):
    route = variant_json(text.split('\nroute=', 1)[1].split('\nbattle=', 1)[0])
    battle = variant_json(text.split('\nbattle=', 1)[1].rsplit('\nscreen=', 1)[0])
    # Pure rendering updates visual coordinates and the opening danger timer.
    # Everything gameplay-relevant, including RNG, queued bleed and ghosts, stays.
    battle.pop('initial_threat', None)
    battle.pop('notice', None)  # Selecting a card changes only this instructional copy.
    for enemy in battle['enemies']: enemy.pop('visual', None)
    return {'route': route, 'battle': battle, 'screen': re.search(r'^screen="(\w+)"', text, re.M).group(1)}

def crop(data, box):
    return Image.open(io.BytesIO(data)).convert('RGB').crop(box)

def panel_visible(before, after, box):
    a, b = crop(before, box), crop(after, box)
    diff = sum(ImageStat.Stat(ImageChops.difference(a, b)).mean) / 3
    paper = sum(max(abs(c - t) for c, t in zip(rgb, (252, 249, 241))) <= 6 for rgb in b.getdata()) / max(1, b.width * b.height)
    assert diff > 7 and paper > .58, ('Inspection panel not visibly rendered', diff, paper, box)
    return {'difference': round(diff, 3), 'paper_fraction': round(paper, 3)}

async def main(full=False, validate_only=False):
    replays = json.loads((OUT / 'replays.json').read_text())
    assert {int(r['viewport'][0]) for r in replays} == {1280, 390, 360, 844}
    for replay in replays:
        initial = state((OUT / 'fixtures' / replay['fixture']).read_text())
        expected = state((OUT / 'fixtures' / replay['after_fixture']).read_text())
        assert initial['battle']['encounter_state']['ghosts'], 'Missing authentic ghost'
        assert initial['battle']['pending_bleeds'], 'Missing actual bleed status'
        assert replay['preview']['affected'][0]['damage'] == 2
        assert expected['battle']['energy'] == initial['battle']['energy'] - 1
    chosen = replays if full else [r for r in replays if int(r['viewport'][0]) in {1280, 390}]
    if validate_only:
        print(json.dumps({'valid_fixtures': len(replays), 'selected_cases': len(chosen), 'rendered': False}));return
    output = OUT / ('browser-full' if full else 'browser-smoke');output.mkdir(parents=True, exist_ok=True)
    results = []
    async with async_playwright() as p:
        executable = os.environ.get('CHROMIUM_PATH') or shutil.which('chromium')
        browser = await p.chromium.launch(**({'executable_path': executable} if executable else {}), headless=True, args=['--no-sandbox'])
        for replay in chosen:
            w, h = replay['viewport'];uw, uh = replay['logical_size'];scale = min(w / uw, h / uh);ox = (w - uw * scale) / 2;oy = (h - uh * scale) / 2
            context = await browser.new_context(viewport={'width': int(w), 'height': int(h)}, has_touch=True)
            page = await context.new_page();await install_debug_settings(page);cdp = await context.new_cdp_session(page);errors = [];shots = [];panels = []
            page.on('pageerror', lambda e: errors.append(str(e)))
            page.on('console', lambda m: errors.append(m.text) if m.type == 'error' and ('SCRIPT ERROR' in m.text or 'Parse Error' in m.text) else None)
            def xy(pos): return {'x': ox + pos[0] * scale, 'y': oy + pos[1] * scale}
            def box(rect):
                x, y, rw, rh = rect
                return (round(ox + (x + 4) * scale), round(oy + (y + 4) * scale), round(ox + (x + rw - 4) * scale), round(oy + (y + rh - 4) * scale))
            async def tap(pos):
                pt = xy(pos)
                if replay['source'] == 'mouse': await page.mouse.click(pt['x'], pt['y'])
                else: await page.touchscreen.tap(pt['x'], pt['y'])
                await page.wait_for_timeout(160)
            async def saved(): return state(await page.evaluate('(key)=>localStorage.getItem(key)', KEY))
            async def shot(label):
                path = output / f"board-{int(w)}-{label}.png";data = await page.screenshot(path=str(path));assert_rendered(data, [int(w), int(h)]);shots.append(path.name);return data
            async def dismiss():
                if replay['source'] == 'mouse':
                    pt = xy(replay['blank']);await page.mouse.move(pt['x'], pt['y'])
                else: await cdp.send('Input.dispatchTouchEvent', {'type': 'touchEnd', 'touchPoints': []})
                await page.wait_for_timeout(180)
            async def inspect(target, label, expected=None):
                before = await page.screenshot();pt = xy(target['point'])
                if replay['source'] == 'mouse': await page.mouse.move(pt['x'], pt['y'])
                else: await cdp.send('Input.dispatchTouchEvent', {'type': 'touchStart', 'touchPoints': [{**pt, 'id': 1}]})
                await page.wait_for_timeout(650)
                after = await shot(label)
                panels.append(panel_visible(before, after, box(expected or target['popup'])))
                await dismiss();await page.wait_for_timeout(1100)
                assert await saved() == initial, ('Inspection/release mutated battle', int(w), label)
            try:
                fixture = (OUT / 'fixtures' / replay['fixture']).read_text();initial = state(fixture)
                await page.add_init_script('if(!sessionStorage.getItem("qa-board")){localStorage.setItem(%s,%s);sessionStorage.setItem("qa-board","1")}' % (json.dumps(KEY), json.dumps(fixture)))
                await page.goto(URL);await boot(page);await tap(replay['resume']);await page.wait_for_timeout(1200)
                assert await saved() == initial
                baseline = await shot('segmented-hp-and-ghost')
                # Verify the 9/9 HP bar is visibly red while the ordinary 1-HP
                # pawn has no corresponding bar. Logical locations come from engine.
                red_counts = []
                for name in ['full_hp', 'one_hp']:
                    x, y = replay[name];cell = replay['cell']
                    rect = [x - cell * .40, y + cell * .44, cell * .8, max(7, cell * .15)]
                    patch = crop(baseline, (round(ox + rect[0] * scale), round(oy + rect[1] * scale), round(ox + (rect[0] + rect[2]) * scale), round(oy + (rect[1] + rect[3]) * scale)))
                    red_counts.append(sum(r > 130 and r > g * 1.6 and r > b * 1.8 for r, g, b in patch.getdata()))
                assert red_counts[0] > max(4, 15 * scale) and red_counts[1] == 0, ('HP bars not visually differentiated', w, red_counts)
                for target_name in ['enemy', 'ghost', 'tag']:
                    await inspect(replay[target_name], target_name + '-inspection')
                await tap(replay['card']);await page.wait_for_timeout(200)
                await tap(replay['tag']['point'])  # A quick tag tap must not cancel the selected card.
                assert await saved() == initial
                await inspect(replay['enemy'], 'attack-preview-hold-no-commit', replay['attack_popup'])
                # The deliberate quick target tap is still normal gameplay.
                await tap(replay['enemy']['point']);await page.wait_for_timeout(1800)
                expected = state((OUT / 'fixtures' / replay['after_fixture']).read_text())
                actual = await saved()
                assert actual == expected, ('Preview differs from real attack or tag/hold canceled selection', w, actual, expected)
                await shot('actual-attack-matches-preview');assert not errors, errors
                results.append({'viewport': [w, h], 'source': replay['source'], 'panels': panels, 'hp_red_pixels': red_counts, 'screenshots': shots, 'errors': errors})
                print('PASS board-info', int(w), replay['source'], 'unchanged inspection saves; exact real attack', flush=True)
            except Exception:
                await page.screenshot(path=str(output / f'board-{int(w)}-failure.png'));raise
            finally:
                await cdp.detach();await context.close()
        await browser.close()
    (output / 'results.json').write_text(json.dumps(results, ensure_ascii=False, indent=2))
    print('BOARD INFO WEB RESULT', len(results), 'real UI cases')
if __name__ == '__main__':
    parser = argparse.ArgumentParser();parser.add_argument('--full', action='store_true');parser.add_argument('--validate-only', action='store_true');args = parser.parse_args();asyncio.run(main(args.full, args.validate_only))
