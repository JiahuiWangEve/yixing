"""Small real-Web release gate; full semantic/UI regression runs after publication.

Uses only normal UI and persisted saves. Desktop mouse and portrait touch
exercise inspection -> deck -> single-tap travel -> victory -> reload ->
Continue -> single-tap legal next node. No fixture injection.
"""
import asyncio
import json
import os
import re
import shutil
from pathlib import Path
from playwright.async_api import async_playwright
from browser_map_checks import RouteGeometry, saved_route

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'verification/release-smoke'
URL = os.environ.get('YIXING_TEST_URL', 'http://127.0.0.1:8765')
KEY = 'yixing.route_run.v0149'

async def main():
    OUT.mkdir(parents=True, exist_ok=True)
    reports = []
    async with async_playwright() as p:
        executable = os.environ.get('CHROMIUM_PATH') or shutil.which('chromium')
        browser = await p.chromium.launch(**({'executable_path': executable} if executable else {}),
                                          headless=True, args=['--no-sandbox'])
        try:
            for w, h in [(1280, 940), (390, 844)]:
                context = await browser.new_context(viewport={'width': w, 'height': h}, has_touch=True)
                page = await context.new_page()
                errors = []
                page.on('pageerror', lambda error: errors.append(str(error)))
                page.on('console', lambda msg: errors.append(msg.text) if msg.type == 'error' and
                        ('SCRIPT ERROR' in msg.text or 'Parse Error' in msg.text) else None)
                desktop = w == 1280
                uw, uh = (1280, 940) if desktop else (480, max(660, 480*h/w))
                scale = min(w/uw, h/uh)
                ox, oy = (w-uw*scale)/2, (h-uh*scale)/2
                async def tap(x, y):
                    if desktop:
                        await page.mouse.click(ox+x*scale, oy+y*scale)
                    else:
                        await page.touchscreen.tap(ox+x*scale, oy+y*scale)
                    await page.wait_for_timeout(180)
                async def inspect(x, y):
                    px, py = ox+x*scale, oy+y*scale
                    if desktop:
                        await page.mouse.move(px, py)
                        await page.wait_for_timeout(350)
                    else:
                        session = await context.new_cdp_session(page)
                        await session.send('Input.dispatchTouchEvent', {'type':'touchStart',
                                           'touchPoints':[{'x':px, 'y':py}]})
                        await page.wait_for_timeout(450)
                        await session.send('Input.dispatchTouchEvent', {'type':'touchEnd', 'touchPoints':[]})
                        await session.detach()
                        await page.wait_for_timeout(180)
                async def boot():
                    await page.wait_for_function("!document.getElementById('status')", timeout=60000)
                    await page.wait_for_timeout(350)
                async def state(screen, current, pending):
                    await page.wait_for_function('''([key,screen,current,pending]) => {
                        const text=localStorage.getItem(key)||'';
                        return text.includes('screen="'+screen+'"') &&
                            new RegExp('"current":\\\\s*'+current+'[,}]').test(text) &&
                            new RegExp('"pending":\\\\s*'+pending+'[,}]').test(text);
                    }''', arg=[KEY, screen, current, pending], timeout=12000)
                try:
                    await page.goto(URL)
                    await boot()
                    # Enable through the real home toggle; no saved fixture injection.
                    await tap(*((640,497) if desktop else (240,max(150,uh*.25)+326)))
                    assert 'debug_mode=true' in (await page.evaluate("localStorage.getItem('yixing.settings.v1')") or '')
                    menu = (640, 209) if desktop else (240, max(150, uh*.25)+30)
                    await tap(*menu)
                    await tap(*menu)
                    await state('map', -1, -1)
                    route = saved_route(await page.evaluate('(key)=>localStorage.getItem(key)', KEY))
                    geometry = RouteGeometry(route, w, h)
                    assert route['nodes'][0]['kind'] == 'battle'
                    assert geometry.visible(0), 'Generated entrance must be visible'
                    saved_before = await page.evaluate('(key)=>localStorage.getItem(key)', KEY)
                    plain_map = await page.screenshot(path=str(OUT / f'map-before-inspection-{w}.png'))
                    await inspect(*geometry.node(0))
                    inspected_map = await page.screenshot(path=str(OUT / f'map-inspected-deck-entry-{w}.png'))
                    assert inspected_map != plain_map, 'Hover or held touch did not show map inspection'
                    assert await page.evaluate('(key)=>localStorage.getItem(key)', KEY) == saved_before
                    # Inspection never departs. The deck clears its frame/popup,
                    # and closing keeps only the previous map camera position.
                    await tap(uw-84, 34)
                    deck = await page.screenshot(path=str(OUT / f'map-readonly-deck-{w}.png'))
                    assert deck != inspected_map, 'Header deck entry did not open the read-only picker'
                    await page.keyboard.press('Enter')
                    assert await page.evaluate('(key)=>localStorage.getItem(key)', KEY) == saved_before
                    await tap(88, uh-40)
                    returned_map = await page.screenshot(path=str(OUT / f'map-returned-cleared-{w}.png'))
                    assert returned_map == plain_map, 'Closing the deck did not retain camera while clearing inspection'
                    assert await page.evaluate('(key)=>localStorage.getItem(key)', KEY) == saved_before
                    # One ordinary release departs from the unselected map.
                    await tap(*geometry.node(0))
                    await state('game', -1, 0)
                    await tap(*( (1098,102) if desktop else (410,84) ))
                    await page.wait_for_function("/\"phase\": \"reward\"/.test(localStorage.getItem('yixing.route_run.v0149')||'')", timeout=12000)
                    await page.wait_for_timeout(1150) # Victory seal is shown before reward input.
                    await tap(*( (920,405) if desktop else (240,442) ))
                    await state('map', 0, -1)
                    await page.reload()
                    await boot()
                    await tap(*( (640,425) if desktop else (240,max(150,uh*.25)+252) ))
                    await state('map', 0, -1)
                    # The saved snapshot survives reload even if Continue is broken.
                    # Prove the restored UI is live by entering an actual legal next
                    # node; generated first branches are not necessarily events.
                    restored = saved_route(await page.evaluate('(key)=>localStorage.getItem(key)', KEY))
                    assert restored['nodes'] == route['nodes'], 'Reload changed generated route'
                    assert restored['nodes'][0]['next'], 'Entrance has no legal continuation'
                    target = restored['nodes'][0]['next'][0]
                    geometry = RouteGeometry(restored, w, h)
                    assert geometry.visible(target), 'Next generated node must be visible'
                    await tap(*geometry.node(target))
                    kind = restored['nodes'][target]['kind']
                    next_screen = 'game' if kind in ['battle', 'elite', 'boss'] else 'route_choice'
                    await state(next_screen, 0, target)
                    assert not errors, errors
                    await page.screenshot(path=str(OUT / f'next-node-after-resume-{w}.png'))
                    reports.append({'viewport':[w,h], 'errors':errors, 'passed':True,
                                    'input':'mouse' if desktop else 'touch',
                                    'inspection_cleared_by_deck':True,
                                    'single_tap_departures':2,
                                    'resumed_next_node':target, 'resumed_next_kind':kind,
                                    'resumed_next_screen':next_screen})
                    print('PASS release smoke', w, h, flush=True)
                except Exception:
                    await page.screenshot(path=str(OUT / f'failure-{w}.png'))
                    raise
                finally:
                    await context.close()
        finally:
            await browser.close()
    (OUT / 'results.json').write_text(json.dumps(reports, indent=2))

if __name__ == '__main__':
    asyncio.run(main())
