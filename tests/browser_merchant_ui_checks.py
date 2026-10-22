"""Two-step merchant UI through ordinary saves and real mouse/touch input.

The only JavaScript reads/writes the production localStorage save. No game hooks
or injected transactions are used; offline fixtures come from merchant_ui_checks.
"""
import argparse
import asyncio
import hashlib
import json
import os
import shutil
import time
from pathlib import Path

from playwright.async_api import async_playwright
from browser_chapter_checks import assert_rendered
from browser_event_checks import KEY, await_saved_state, boot, parse, variant_json
from browser_settings import install_debug_settings

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'verification/v0.14.11/merchant'
URL = os.environ.get('YIXING_TEST_URL', 'http://127.0.0.1:8765')


def stored_offers(text, node):
    route = variant_json(text.split('\nroute=', 1)[1].split('\nbattle=', 1)[0])
    return route['nodes'][node]['offers']


async def main(full=False):
    all_replays = json.loads((OUT / 'replays.json').read_text())
    full_matrix = {(empty, width) for empty in (False, True) for width in (1280, 390, 360, 844)}
    assert {(r['empty'], int(r['viewport'][0])) for r in all_replays} == full_matrix
    assert len(all_replays) == len(full_matrix), 'Incomplete or duplicate merchant fixture matrix'
    for replay in all_replays:
        fixture = (OUT / 'fixtures' / replay['fixture']).read_text()
        assert parse(fixture) == replay['initial'], replay['fixture']
        assert stored_offers(fixture, replay['node']) == replay['offers']
        assert len(replay['offers']) == len(set(replay['offers'])) == 3
        if not replay['empty']:
            before, after = replay['initial']['collection'], replay['expected']['collection']
            assert len(before) == len(after) == 20
            assert [i for i, (a, b) in enumerate(zip(before, after)) if a != b] == [replay['target_index']]
            assert before[replay['target_index']] == 'sword_plus'
            assert after[replay['target_index']] == replay['offers'][0]
    widths = {1280, 390, 360, 844} if full else {1280, 390}
    replays = [r for r in all_replays if int(r['viewport'][0]) in widths]
    output = OUT / ('browser-full' if full else 'browser-smoke')
    output.mkdir(parents=True, exist_ok=True)
    reports = []
    started = time.monotonic()
    async with async_playwright() as p:
        exe = os.environ.get('CHROMIUM_PATH') or shutil.which('chromium')
        browser = await p.chromium.launch(
            **({'executable_path': exe} if exe else {}),
            headless=True, args=['--no-sandbox'],
        )
        for replay in replays:
            w, h = replay['viewport']
            uw, uh = replay['logical_size']
            scale = min(w / uw, h / uh)
            ox, oy = (w - uw * scale) / 2, (h - uh * scale) / 2
            context = await browser.new_context(
                viewport={'width': int(w), 'height': int(h)}, has_touch=True,
            )
            page = await context.new_page()
            await install_debug_settings(page)
            cdp = await context.new_cdp_session(page)
            errors, screens = [], []
            assertions = 0
            page.on('pageerror', lambda e: errors.append(str(e)))
            page.on('console', lambda m: errors.append(m.text)
                    if m.type == 'error' and ('SCRIPT ERROR' in m.text or 'Parse Error' in m.text) else None)

            def xy(pos):
                return {'x': ox + pos[0] * scale, 'y': oy + pos[1] * scale}

            async def click(pos):
                pt = xy(pos)
                if w == 1280:
                    await page.mouse.click(pt['x'], pt['y'])
                else:
                    await page.touchscreen.tap(pt['x'], pt['y'])
                await page.wait_for_timeout(160)

            async def raw_save():
                return await page.evaluate('(key) => localStorage.getItem(key)', KEY)

            async def snapshot():
                return parse(await raw_save())

            async def expect(expected, label):
                nonlocal assertions
                actual = await await_saved_state(snapshot, expected)
                assert actual == expected, (replay['name'], label, actual, expected)
                assert stored_offers(await raw_save(), replay['node']) == replay['offers'], (label, 'offer reroll')
                assertions += 1

            async def shot(label):
                path = output / f"{replay['name']}-{label}.png"
                data = await page.screenshot(path=str(path))
                assert_rendered(data, [w, h])
                screens.append({'file': path.name, 'sha256': hashlib.sha256(data).hexdigest()})

            async def drag(start, end, cancel=False):
                a, b = xy(start), xy(end)
                await cdp.send('Input.dispatchTouchEvent', {
                    'type': 'touchStart', 'touchPoints': [{**a, 'id': 1}],
                })
                for fraction in (.25, .5, .75, 1):
                    pt = {key: a[key] + (b[key] - a[key]) * fraction for key in ('x', 'y')}
                    await cdp.send('Input.dispatchTouchEvent', {
                        'type': 'touchMove', 'touchPoints': [{**pt, 'id': 1}],
                    })
                    await page.wait_for_timeout(25)
                await cdp.send('Input.dispatchTouchEvent', {
                    'type': 'touchCancel' if cancel else 'touchEnd', 'touchPoints': [],
                })
                await page.wait_for_timeout(100)

            async def reload_resume():
                await page.reload()
                await boot(page)
                await click(replay['resume'])
                await page.wait_for_timeout(350)

            try:
                fixture = (OUT / 'fixtures' / replay['fixture']).read_text()
                # Seed exactly once per fresh tab. The session marker prevents
                # reload from replacing a committed result with its fixture.
                await page.add_init_script("""if (!sessionStorage.getItem('merchant-fixture-installed')) {
                    localStorage.setItem(%s, %s);
                    sessionStorage.setItem('merchant-fixture-installed', '1');
                }""" % (json.dumps(KEY), json.dumps(fixture)))
                await page.goto(URL)
                await boot(page)
                await click(replay['resume'])
                await page.wait_for_timeout(350)
                await expect(replay['initial'], 'ordinary save resumed')
                await shot('three-actual-offer-faces')
                for number in range(1, 8):
                    await page.keyboard.press(str(number))
                await page.keyboard.press('Space')
                await expect(replay['initial'], 'offer screen consumes battle shortcuts')
                await drag(replay['offer_drag_from'], replay['offer_drag_to'])
                await expect(replay['initial'], 'offer drag never exchanges')
                if replay['empty']:
                    for pos in replay['offer_points']:
                        await click(pos)
                    await page.keyboard.press('Enter')
                    await expect(replay['initial'], 'empty deck offers disabled')
                    await shot('empty-deck-disabled')
                    await click(replay['leave'])
                    await expect(replay['expected'], 'empty deck can leave')
                else:
                    # Each face opens its own incoming-card preview, then cancel
                    # returns the unchanged saved offers and physical old cards.
                    for index, pos in enumerate(replay['offer_points']):
                        await click(pos)
                        await expect(replay['initial'], f'offer {index + 1} preview only')
                        await shot(f'incoming-offer-{index + 1}')
                        await click(replay['first'])
                        for number in range(1, 8):
                            await page.keyboard.press(str(number))
                        await page.keyboard.press('Space')
                        await expect(replay['initial'], f'old card preview {index + 1} only')
                        await shot(f'old-to-new-preview-{index + 1}')
                        await click(replay['cancel'])
                        await expect(replay['initial'], f'cancel offer {index + 1} keeps fixed offers')
                    await reload_resume()
                    await expect(replay['initial'], 'reload cancels preview without reroll')
                    await shot('fixed-offers-after-cancel-reload')
                    await click(replay['offer_points'][0])
                    await drag(replay['drag_from'], replay['drag_to'], cancel=True)
                    await click(replay['confirm'])
                    await expect(replay['initial'], 'canceled touch scroll cannot commit')
                    await click(replay['cancel'])
                    await click(replay['offer_points'][0])
                    for _ in range(replay['swipes']):
                        await drag(replay['drag_from'], replay['drag_to'])
                    await shot('twenty-cards-scrolled-bottom')
                    await click(replay['confirm'])
                    await expect(replay['initial'], 'scroll release never selects an old card')
                    await click(replay['last'])
                    await expect(replay['initial'], 'last upgraded duplicate is preview only')
                    await shot('selected-last-upgraded-copy')
                    # Real rapid second click must not apply the exchange twice.
                    pt = xy(replay['confirm'])
                    if w == 1280:
                        await page.mouse.dblclick(pt['x'], pt['y'], delay=40)
                    else:
                        await page.touchscreen.tap(pt['x'], pt['y'])
                        await page.wait_for_timeout(40)
                        await page.touchscreen.tap(pt['x'], pt['y'])
                    await expect(replay['expected'], 'only the chosen physical index replaced once')
                    await page.wait_for_timeout(1100)
                    await expect(replay['expected'], 'duplicate confirmation remains harmless')
                    await shot('exact-copy-committed')
                await reload_resume()
                await expect(replay['expected'], 'completed result survives reload')
                await shot('saved-result-resumed')
                assert not errors, (replay['name'], errors)
                reports.append({
                    'fixture': replay['fixture'], 'viewport': [w, h],
                    'input': 'mouse + real touch scroll' if w == 1280 else 'real touch',
                    'state_assertions': assertions, 'screenshots': screens,
                    'errors': errors, 'final': await snapshot(),
                })
                print('PASS merchant', replay['name'], assertions, 'state checks', flush=True)
            except Exception:
                await page.screenshot(path=str(output / f"{replay['name']}-failure.png"))
                raise
            finally:
                await cdp.detach()
                await context.close()
        await browser.close()
    result = {
        'replays': len(reports),
        'state_assertions': sum(r['state_assertions'] for r in reports),
        'elapsed_seconds': round(time.monotonic() - started, 2),
        'cases': reports,
    }
    (output / 'results.json').write_text(json.dumps(result, ensure_ascii=False, indent=2))
    print('MERCHANT WEB RESULT', result['replays'], 'replays,', result['state_assertions'], 'state checks')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--full', action='store_true')
    args = parser.parse_args()
    asyncio.run(main(args.full))
