"""Settings entry, old-control removal, and preference persistence in real Web UI.

Only ordinary clicks, touch, keys, and production localStorage are used. One
legacy preference envelope is restored to check migration. No runtime hooks or
claim of physical audio playback; CI supplies Chromium, which is not run locally.
"""
import argparse
import asyncio
import io
import json
import os
import re
import shutil
from pathlib import Path
from PIL import Image, ImageChops, ImageStat
from playwright.async_api import async_playwright
from browser_event_checks import boot, KEY
from browser_settings import SETTINGS_KEY

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'verification/sound-settings/browser'
URL = os.environ.get('YIXING_TEST_URL', 'http://127.0.0.1:8765')


async def main(smoke=False):
    OUT.mkdir(parents=True, exist_ok=True)
    reports = []
    async with async_playwright() as p:
        executable = os.environ.get('CHROMIUM_PATH') or shutil.which('chromium')
        browser = await p.chromium.launch(**({'executable_path': executable} if executable else {}),
                                          headless=True, args=['--no-sandbox'])
        try:
            for w, h in ([(1280, 940), (390, 844)] if smoke else [(1280, 940), (390, 844), (360, 640), (844, 390)]):
                context = await browser.new_context(viewport={'width': w, 'height': h}, has_touch=True)
                page = await context.new_page()
                errors, assertions = [], []
                page.on('pageerror', lambda error: errors.append(str(error)))
                page.on('console', lambda msg: errors.append(msg.text) if msg.type == 'error' and
                        ('SCRIPT ERROR' in msg.text or 'Parse Error' in msg.text) else None)
                desktop, landscape = w == 1280, w > h and w != 1280
                uw, uh = (1280, 940) if desktop else ((960, 540) if landscape else (480, max(660, 480*h/w)))
                scale = min(w/uw, h/uh)
                ox, oy = (w-uw*scale)/2, (h-uh*scale)/2
                old = (913, 20, 88, 40) if desktop else ((830, 12, 106, 64) if landscape else (220, 12, 88, 46))

                def menu(i, tutorial=False):
                    if landscape:
                        return 265+(i % 2)*430, 169+(i//2)*72
                    if desktop:
                        return 640, 209+i*72
                    return 240, (142+26+i*56) if tutorial else (max(150, uh*.25)+30+i*74)

                def box(rect):
                    x, y, width, height = rect
                    return tuple(round(v) for v in (ox+x*scale, oy+y*scale, ox+(x+width)*scale, oy+(y+height)*scale))

                async def tap(pos):
                    x, y = ox+pos[0]*scale, oy+pos[1]*scale
                    if desktop:
                        await page.mouse.click(x, y)
                    else:
                        await page.touchscreen.tap(x, y)
                    await page.wait_for_timeout(200)

                async def prefs():
                    return await page.evaluate('(key)=>localStorage.getItem(key)', SETTINGS_KEY)

                async def saved():
                    return await page.evaluate('(key)=>localStorage.getItem(key)', KEY)

                async def shot(label):
                    return await page.screenshot(path=str(OUT/f'{label}-{w}.png'))

                async def no_old_button(label):
                    before = await prefs()
                    await tap((old[0]+old[2]/2, old[1]+old[3]/2))
                    assert await prefs() == before, (label, 'former sound hitbox changed preferences')
                    picture = Image.open(io.BytesIO(await shot(label))).convert('RGB').crop(box(old))
                    # The removed button had a large, flat #e6d4b0 fill. Check its
                    # absence as well as the now-inert old click coordinates.
                    count = sum(1 for rgb in picture.getdata() if sum(abs(a-b) for a, b in zip(rgb, (230, 212, 176))) < 12)
                    assert count / (picture.width*picture.height) < .10, (label, 'old button fill remains')
                    assertions.append(label + ': former sound control absent and cannot toggle')

                def sound_row(png):
                    x, y = menu(0)
                    width, height = (440, 58) if desktop else ((390, 58) if landscape else (432, 60))
                    return Image.open(io.BytesIO(png)).convert('RGB').crop(box((x-width/2, y-height/2, width, height)))

                async def assert_preferences(muted, debug):
                    actual = await prefs() or ''
                    assert re.search(r'^audio_muted='+str(muted).lower()+r'$', actual, re.M), actual
                    assert re.search(r'^debug_mode='+str(debug).lower()+r'$', actual, re.M), actual

                async def wait_state(screen, phase=None):
                    await page.wait_for_function('''([key, screen, phase]) => {
                        const value = localStorage.getItem(key) || '';
                        return value.includes('screen="' + screen + '"') &&
                            (!phase || new RegExp('"phase":\\\\s*"' + phase + '"').test(value));
                    }''', arg=[KEY, screen, phase], timeout=12000)

                try:
                    await page.goto(URL)
                    await boot(page)
                    assert await prefs() is None
                    await no_old_button('home')
                    await tap(menu(2))
                    on = sound_row(await shot('settings-default-on'))
                    assert await prefs() is None, 'Entering settings must not toggle or write preferences'
                    await tap(menu(0))
                    await assert_preferences(True, False)
                    off = sound_row(await shot('settings-off'))
                    assert sum(ImageStat.Stat(ImageChops.difference(on, off)).mean) > .1, 'Sound row status did not update'
                    await tap(menu(1))
                    await tap(menu(2))
                    assert sum(ImageStat.Stat(ImageChops.difference(off, sound_row(await shot('settings-returned-off')))).mean) < 1
                    await page.keyboard.press('Space')
                    await page.keyboard.press('Control+z')
                    await page.keyboard.press('Enter')
                    await assert_preferences(True, False)
                    await page.keyboard.press('Escape')
                    await tap(menu(2))
                    await tap(menu(0))
                    await assert_preferences(False, False)
                    await page.reload()
                    await boot(page)
                    await tap(menu(2))
                    assert sum(ImageStat.Stat(ImageChops.difference(on, sound_row(await shot('settings-reloaded-on')))).mean) < 1
                    assertions.append('Settings opens without toggling; click toggles, Back/Escape return, enabled state reloads')

                    # Old releases stored debug_mode alone. Preserve that setting
                    # and default the new audio preference to enabled.
                    await page.evaluate('([key,value])=>localStorage.setItem(key,value)',
                                        [SETTINGS_KEY, '[settings]\n\ndebug_mode=true\n'])
                    await page.reload()
                    await boot(page)
                    await tap(menu(2))
                    assert sum(ImageStat.Stat(ImageChops.difference(on, sound_row(await shot('legacy-default-on')))).mean) < 1
                    await tap(menu(0))
                    await assert_preferences(True, True)
                    await page.reload()
                    await boot(page)
                    await tap(menu(2))
                    assert sum(ImageStat.Stat(ImageChops.difference(off, sound_row(await shot('settings-reloaded-off')))).mean) < 1
                    await tap(menu(1))
                    await tap(menu(4))
                    await assert_preferences(True, False)
                    await tap(menu(4))
                    await assert_preferences(True, True)
                    assertions.append('Legacy debug preference survives migration; muted state reloads; debug changes preserve sound')

                    # Basic release smoke remains desktop + touch portrait. The
                    # two other sizes above cover settings layout and persistence.
                    if desktop or w == 390:
                        await tap(menu(0))
                        await no_old_button('skill-selection')
                        await tap(menu(0))
                        await wait_state('map')
                        await no_old_button('map')
                        await tap((74, 34))
                        await tap(menu(2))
                        before = await saved()
                        for key in ['Space', 'Control+z', 'Enter']:
                            await page.keyboard.press(key)
                        await page.wait_for_timeout(1100)
                        assert await saved() == before, 'Settings keyboard leaked into saved expedition'
                        await page.keyboard.press('Escape')
                        await tap(menu(3))
                        await wait_state('map')
                        mw = min(uw-28, 1000)
                        mx, my, mh = (uw-mw)/2, 112, uh-126
                        ch, margin = (1240, 42) if desktop else (mh*2.4, 28)
                        nx, ny = mx+margin+.46*(mw-margin*2), my+32+.94*(ch-80)
                        scroll = max(0, min(ch-mh, ny-my-mh*.73))
                        await tap((nx, ny-scroll-15))
                        await tap((nx, ny-scroll-15))
                        await wait_state('game', 'play')
                        await page.wait_for_timeout(800)
                        await no_old_button('battle')
                        await tap((1098, 102) if desktop else (410, 84))
                        await wait_state('game', 'reward')
                        await page.wait_for_timeout(1200)
                        await no_old_button('reward')
                        await tap((80, 40) if desktop else (54, 35))
                        await tap(menu(1))
                        await no_old_button('tutorial-menu')
                        await tap(menu(0, tutorial=True))
                        await page.wait_for_timeout(800)
                        await no_old_button('tutorial')
                        await assert_preferences(True, True)
                        assertions.append('Settings blocks combat keys; original Continue index resumes; map/battle/reward/tutorial retain sound preference')
                    assert not errors, errors
                    reports.append({'viewport': [w, h], 'assertions': assertions, 'errors': errors})
                    print('PASS sound settings Web', w, h, flush=True)
                except Exception:
                    await shot('failure')
                    raise
                finally:
                    await context.close()
        finally:
            await browser.close()
    (OUT/'results.json').write_text(json.dumps(reports, ensure_ascii=False, indent=2)+'\n')


if __name__ == '__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--smoke',action='store_true')
    asyncio.run(main(parser.parse_args().smoke))
