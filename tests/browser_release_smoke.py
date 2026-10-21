"""Small real-Web release gate; full semantic/UI regression runs after publication.

Uses only normal UI and persisted saves. Desktop and touch portrait exercise new
run -> map -> battle -> victory -> map -> reload -> Continue. No fixture injection.
"""
import asyncio
import json
import os
import re
import shutil
from pathlib import Path
from playwright.async_api import async_playwright

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'verification/release-smoke'
URL = os.environ.get('YIXING_TEST_URL', 'http://127.0.0.1:8765')
KEY = 'yixing.route_run.v0100'

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
                    await page.touchscreen.tap(ox+x*scale, oy+y*scale)
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
                    mx,my,mw,mh,ch,margin = (24,116,850,800,1240,42) if desktop else (14,112,452,uh-282,(uh-282)*2.4,28)
                    nx = mx+margin+.46*(mw-margin*2)
                    ny = my+32+.94*(ch-80)
                    scroll = max(0, min(ch-mh, ny-my-mh*.73))
                    await tap(nx, ny-scroll-15)
                    await tap(*( (1075,868) if desktop else (uw-107,uh-48) ))
                    await state('game', -1, 0)
                    await tap(*( (1098,102) if desktop else (410,84) ))
                    await page.wait_for_function("/\"phase\": \"reward\"/.test(localStorage.getItem('yixing.route_run.v0100')||'')", timeout=12000)
                    await page.wait_for_timeout(1150) # Victory seal is shown before reward input.
                    await tap(*( (920,405) if desktop else (240,442) ))
                    await state('map', 0, -1)
                    await page.reload()
                    await boot()
                    await tap(*( (640,425) if desktop else (240,max(150,uh*.25)+252) ))
                    await state('map', 0, -1)
                    # The saved snapshot survives reload even if Continue is broken.
                    # Prove the restored UI is live by entering the next event.
                    await tap(mx+margin+.15*(mw-margin*2), my+32+.82*(ch-80)-scroll-15)
                    await tap(*((1075,868) if desktop else (uw-107,uh-48)))
                    await state('route_choice', 0, 1)
                    assert not errors, errors
                    await page.screenshot(path=str(OUT / f'event-after-resume-{w}.png'))
                    reports.append({'viewport':[w,h], 'errors':errors, 'passed':True})
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
