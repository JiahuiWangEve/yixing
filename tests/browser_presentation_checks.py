"""Capture visible old/new card and victory seal before reward UI on real Web."""
import asyncio, io, json, os, shutil, time
from PIL import Image, ImageChops, ImageStat
from playwright.async_api import async_playwright
from browser_event_checks import ROOT, KEY, parse, boot
OUT=ROOT/'verification/v0.14.3/presentation';URL=os.environ.get('YIXING_TEST_URL','http://127.0.0.1:8765')
async def main():
    output=OUT/'browser';output.mkdir(parents=True,exist_ok=True);reports=[]
    async with async_playwright() as p:
        exe=os.environ.get('CHROMIUM_PATH') or shutil.which('chromium')
        browser=await p.chromium.launch(**({'executable_path':exe} if exe else {}),headless=True,args=['--no-sandbox'])
        for r in json.loads((OUT/'replays.json').read_text()):
            w,h=r['viewport'];uw,uh=r['logical_size'];scale=min(w/uw,h/uh);ox=(w-uw*scale)/2;oy=(h-uh*scale)/2
            for mode in ['victory','upgrade']:
                context=await browser.new_context(viewport={'width':int(w),'height':int(h)},has_touch=True);page=await context.new_page();errors=[]
                page.on('pageerror',lambda e:errors.append(str(e)))
                async def tap(pos):await page.touchscreen.tap(ox+pos[0]*scale,oy+pos[1]*scale)
                async def state():return parse(await page.evaluate('(key)=>localStorage.getItem(key)',KEY))
                async def shot(label):return await page.screenshot(path=str(output/f"{r['name']}-{mode}-{label}.png"))
                fixture=(OUT/'fixtures'/f"{r['name']}-{mode}.cfg").read_text()
                await page.add_init_script('if(!sessionStorage.getItem("qa")){localStorage.setItem(%s,%s);sessionStorage.setItem("qa","1")}'%(json.dumps(KEY),json.dumps(fixture)))
                await page.goto(URL);await boot(page);await tap(r['resume']);await page.wait_for_timeout(400)
                if mode=='victory':
                    await tap(r['skip']);await page.wait_for_timeout(430);data=await shot('seal-before-reward')
                    s=await state();assert s['phase']=='reward'
                    im=Image.open(io.BytesIO(data)).convert('RGB');crop=im.crop((int(w*.25),int(h*.25),int(w*.75),int(h*.75)))
                    red=sum(1 for rr,g,b in crop.getdata() if rr>110 and rr>g*1.8 and rr>b*1.8)
                    assert red>150,('victory seal not visible',w,red)
                    await page.wait_for_timeout(800);await shot('reward-after-seal');assert await state()==s
                    await page.reload();await boot(page);await tap(r['resume']);await page.wait_for_timeout(450);await shot('reload-no-second-seal');assert await state()==s
                else:
                    await tap(r['choose']);await page.wait_for_timeout(140);await tap(r['confirm']);await page.wait_for_timeout(170)
                    old=await shot('old-card');assert (await state())['collection']==r['after']
                    await page.wait_for_timeout(650);new=await shot('upgraded-card')
                    diff=ImageStat.Stat(ImageChops.difference(Image.open(io.BytesIO(old)).convert('RGB'),Image.open(io.BytesIO(new)).convert('RGB'))).mean
                    assert sum(diff)>0.4,('old/new card unchanged',w,diff)
                    await page.wait_for_timeout(1200);await tap(r['view']);await page.wait_for_timeout(150);await shot('read-only-deck');s=await state();assert s['collection']==r['after']
                    await page.keyboard.press('Enter');await page.keyboard.press('Space');await tap(r['back']);await page.wait_for_timeout(150);assert await state()==s
                    await page.reload();await boot(page);await tap(r['resume']);await page.wait_for_timeout(450);assert (await state())['collection']==r['after'];await shot('reload-no-reroll')
                assert not errors,errors;reports.append({'viewport':[w,h],'mode':mode,'errors':errors});await context.close();print('PASS presentation',mode,w,flush=True)
        await browser.close()
    (output/'results.json').write_text(json.dumps(reports,indent=2));print('PRESENTATION WEB RESULT',len(reports),'cases')
if __name__=='__main__':asyncio.run(main())
