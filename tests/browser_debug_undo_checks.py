"""Real Web debug settings and whole-expedition undo, using only ordinary UI.

No fixture injection or runtime hooks: starts a new game, uses Space / Undo,
changes the home toggle, and reads production save/preference storage.
"""
import asyncio, io, json, os, re, shutil
from pathlib import Path
from PIL import Image, ImageChops, ImageStat
from playwright.async_api import async_playwright
from browser_map_checks import RouteGeometry, saved_route
from browser_event_checks import boot, parse, KEY
from browser_settings import SETTINGS_KEY
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'verification/v0.14.4/debug/browser'
URL=os.environ.get('YIXING_TEST_URL','http://127.0.0.1:8765')
async def main():
    OUT.mkdir(parents=True,exist_ok=True);reports=[]
    async with async_playwright() as p:
        exe=os.environ.get('CHROMIUM_PATH') or shutil.which('chromium')
        browser=await p.chromium.launch(**({'executable_path':exe} if exe else {}),headless=True,args=['--no-sandbox'])
        for w,h in [(1280,940),(390,844)]:
            context=await browser.new_context(viewport={'width':w,'height':h},has_touch=True)
            page=await context.new_page();errors=[];assertions=[]
            page.on('pageerror',lambda e:errors.append(str(e)))
            page.on('console',lambda m:errors.append(m.text) if m.type=='error' and ('SCRIPT ERROR' in m.text or 'Parse Error' in m.text) else None)
            desktop=w==1280;uw,uh=(1280,940) if desktop else (480,max(660,480*h/w))
            scale=min(w/uw,h/uh);ox=(w-uw*scale)/2;oy=(h-uh*scale)/2
            top=180 if desktop else max(150,uh*.25);step=72 if desktop else 74
            menu=lambda i:(640,top+29+i*step) if desktop else (240,top+30+i*step)
            skip=(1098,102) if desktop else (410,84)
            undo=(1130,40) if desktop else (394,35)
            home=(80,40) if desktop else (54,35)
            async def tap(pos):
                await page.touchscreen.tap(ox+pos[0]*scale,oy+pos[1]*scale);await page.wait_for_timeout(200)
            async def save():return await page.evaluate('(key)=>localStorage.getItem(key)',KEY)
            async def state():return parse(await save())
            async def budget():return int(re.search(r'^normal_undos_remaining=(\d+)',await save(),re.M).group(1))
            async def wait_turn(turn):
                await page.wait_for_function('([key,turn])=>new RegExp("\\\"turn\\\": "+turn+"[,\\n]").test(localStorage.getItem(key)||"")',arg=[KEY,turn],timeout=12000)
            async def shot(label):return await page.screenshot(path=str(OUT/f'{label}-{w}.png'))
            async def toggle_resume(enabled):
                await tap(home);await tap(menu(4))
                expected='debug_mode='+str(enabled).lower()
                assert expected in (await page.evaluate('(key)=>localStorage.getItem(key)',SETTINGS_KEY) or '')
                await tap(menu(3));await page.wait_for_timeout(400)
            try:
                await page.goto(URL);await boot(page)
                assert not await page.evaluate('(key)=>localStorage.getItem(key)',SETTINGS_KEY)
                await shot('home-default-off');await tap(menu(0));await tap(menu(0))
                route=saved_route(await save());geometry=RouteGeometry(route,w,h)
                assert route['current']==-1 and route['pending']==-1 and route['nodes'][0]['kind']=='battle'
                assert geometry.visible(0), 'Generated entrance must be visible'
                await tap(geometry.node(0));await tap(geometry.node(0))
                await wait_turn(1);assert await budget()==3
                off=await shot('battle-off-no-skip');await tap(skip);await page.wait_for_timeout(1100)
                assert (await state())['phase']=='play';assert await budget()==3
                assertions.append('OFF hides skip and its former hitbox is inert')
                for remaining in [2,1,0]:
                    await page.keyboard.press('Space');await wait_turn(2);await page.wait_for_timeout(500)
                    if remaining==1:await page.keyboard.press('Control+z')
                    else:await tap(undo)
                    await wait_turn(1);assert await budget()==remaining
                assertions.append('Three successful undos consume one global allowance each, including Ctrl+Z')
                await page.keyboard.press('Space');await wait_turn(2);await page.wait_for_timeout(500)
                await tap(undo);await page.keyboard.press('Control+z');await page.wait_for_timeout(1100)
                assert (await state())['turn']==2 and await budget()==0
                await shot('off-exhausted');await page.reload();await boot(page);await tap(menu(3));await page.wait_for_timeout(450)
                assert await budget()==0 and (await state())['turn']==2
                assertions.append('Exhaustion blocks button and keyboard; reload preserves zero')
                await toggle_resume(True);on=await shot('battle-on-skip')
                rect=(1040,80,1156,124) if desktop else (352,64,468,104)
                box=tuple(int((ox if i%2==0 else oy)+v*scale) for i,v in enumerate(rect))
                diff=ImageStat.Stat(ImageChops.difference(Image.open(io.BytesIO(off)).convert('RGB').crop(box),Image.open(io.BytesIO(on)).convert('RGB').crop(box))).mean
                assert sum(diff)>5,('skip visibility did not change',diff)
                for _ in range(5):
                    await page.keyboard.press('Space');await wait_turn(3);await page.wait_for_timeout(500)
                    await tap(undo);await wait_turn(2);assert await budget()==0
                assertions.append('ON allows five more undos without replenishing or charging normal quota')
                await page.reload();await boot(page)
                assert 'debug_mode=true' in await page.evaluate('(key)=>localStorage.getItem(key)',SETTINGS_KEY)
                await tap(menu(3));await page.wait_for_timeout(400);await toggle_resume(False)
                await page.keyboard.press('Space');await wait_turn(3);await page.wait_for_timeout(500);await tap(undo)
                await page.wait_for_timeout(1100);assert (await state())['turn']==3 and await budget()==0
                assertions.append('ON persists across reload; switching OFF never replenishes quota')
                await shot('off-again-zero');assert not errors,errors
                reports.append({'viewport':[w,h],'assertions':assertions,'errors':errors});print('PASS debug undo Web',w,flush=True)
            except Exception:
                await shot('failure');raise
            finally:await context.close()
        await browser.close()
    (OUT/'results.json').write_text(json.dumps(reports,indent=2))
if __name__=='__main__':asyncio.run(main())
