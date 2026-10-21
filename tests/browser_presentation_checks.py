from browser_settings import install_debug_settings
"""Capture visible old/new card and victory seal before reward UI on real Web."""
import asyncio, base64, io, json, os, shutil, time
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
                context=await browser.new_context(viewport={'width':int(w),'height':int(h)},has_touch=True);page=await context.new_page();await install_debug_settings(page);errors=[]
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
                    await tap(r['choose']);await page.wait_for_timeout(140)
                    # Stream compositor frames before input. Sequential screenshots
                    # can themselves outlast this short animation on slow runners.
                    cdp=await context.new_cdp_session(page);frames=[];ack_tasks=[]
                    def receive_frame(event):
                        frames.append((event['metadata'].get('timestamp',0),base64.b64decode(event['data'])))
                        ack_tasks.append(asyncio.create_task(cdp.send('Page.screencastFrameAck',{'sessionId':event['sessionId']})))
                    cdp.on('Page.screencastFrame',receive_frame)
                    await cdp.send('Page.startScreencast',{'format':'png','everyNthFrame':1})
                    await tap(r['confirm']);await page.wait_for_timeout(2100)
                    await cdp.send('Page.stopScreencast');await asyncio.gather(*ack_tasks);await cdp.detach()
                    assert (await state())['collection']==r['after']
                    # Production card colors identify the two fully expanded
                    # faces, not a flipped sliver or the map after dismissal.
                    probe=(int(ox+(uw/2+65)*scale),int(oy+(uh/2+75)*scale))
                    selected={};frame_info=[]
                    for number,(stamp,data) in enumerate(frames):
                        im=Image.open(io.BytesIO(data)).convert('RGB')
                        x,y=probe;patch=im.crop((x-3,y-3,x+4,y+4));rgb=ImageStat.Stat(patch).mean
                        label=next((label for label,target in [('old-card',(242,229,204)),('upgraded-card',(234,213,172))] if max(abs(rgb[i]-target[i]) for i in range(3))<5),None)
                        frame_info.append({'frame':number,'timestamp':stamp,'probe_rgb':rgb,'phase':label})
                        if label and label not in selected:selected[label]=(number,stamp,data)
                    assert set(selected)=={'old-card','upgraded-card'},('missing distinct visible card phases',w,frame_info)
                    assert selected['old-card'][0]<selected['upgraded-card'][0],frame_info
                    for label,(_,stamp,data) in selected.items():
                        (output/f"{r['name']}-{mode}-{label}.png").write_bytes(data)
                    (output/f"{r['name']}-upgrade-frames.json").write_text(json.dumps(frame_info,indent=2))
                    await tap(r['view']);await page.wait_for_timeout(150);await shot('read-only-deck');s=await state();assert s['collection']==r['after']
                    await page.keyboard.press('Enter');await page.keyboard.press('Space');await tap(r['back']);await page.wait_for_timeout(150);assert await state()==s
                    await page.reload();await boot(page);await tap(r['resume']);await page.wait_for_timeout(450);assert (await state())['collection']==r['after'];await shot('reload-no-reroll')
                assert not errors,errors;reports.append({'viewport':[w,h],'mode':mode,'errors':errors});await context.close();print('PASS presentation',mode,w,flush=True)
        await browser.close()
    (output/'results.json').write_text(json.dumps(reports,indent=2));print('PRESENTATION WEB RESULT',len(reports),'cases')
if __name__=='__main__':asyncio.run(main())
