from browser_settings import install_debug_settings
"""Capture visible old/new card and victory seal before reward UI on real Web."""
import asyncio, base64, io, json, os, shutil, time
from PIL import Image, ImageChops, ImageStat
from presentation_image_checks import seal_score
from playwright.async_api import async_playwright
from browser_event_checks import ROOT, KEY, parse, boot
OUT=ROOT/'verification/v0.14.3/presentation';URL=os.environ.get('YIXING_TEST_URL','http://127.0.0.1:8765')
def upgrade_frame(data, baseline, logical_size):
    """Require the expanded card outline and an occluded, then restored home button.

    Map paper deliberately shares the old-card fill. A fill sample alone is not
    card evidence, and the flip's unclassified sliver is not dismissal evidence.
    """
    im=Image.open(io.BytesIO(data)).convert('RGB')
    before=Image.open(io.BytesIO(baseline)).convert('RGB').resize(im.size)
    uw,uh=logical_size;scale=min(im.width/uw,im.height/uh)
    ox=(im.width-uw*scale)/2;oy=(im.height-uh*scale)/2
    def point(x,y):return round(ox+x*scale),round(oy+y*scale)
    x,y=point(uw/2+118,uh/2+90)
    rgb=ImageStat.Stat(im.crop((x-1,y-1,x+2,y+2))).mean
    # Horizontal edges span most of the 260x310 presentation face, so map
    # marks, a single paper pixel, and the narrow flipping face cannot qualify.
    edges=[]
    for dy in (-155,155):
        x0,y0=point(uw/2-110,uh/2+dy);x1,_=point(uw/2+110,uh/2+dy)
        radius=max(1,round(scale*2))
        outside=y0+(-1 if dy<0 else 1)*max(3,round(scale*7))
        edges.append(sum(sum(im.getpixel((x,outside)))/3-
                         min(sum(im.getpixel((x,yy)))/3 for yy in range(y0-radius,y0+radius+1))>12
                         for x in range(x0,x1))/max(1,x1-x0))
    # This header button exists unchanged on both route_choice and map. Compare
    # only its pre-action ink, not the visited counter or new deck button.
    x0,y0=point(20,16);x1,y1=point(125,52)
    ink=[(x,y) for y in range(y0,y1) for x in range(x0,x1) if max(before.getpixel((x,y)))<140]
    assert ink,'Missing pre-action home-button baseline ink'
    restored=sum(max(im.getpixel(pos))<170 for pos in ink)/len(ink)
    label=None
    if min(edges)>.65 and restored<.2:
        label=next((name for name,target in [('old-card',(252,249,241)),('upgraded-card',(229,223,210))]
                    if max(abs(rgb[i]-target[i]) for i in range(3))<8),None)
    return label,{'probe_rgb':rgb,'edge_coverage':edges,'header_ink_restored':restored}

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
                    baseline=await page.screenshot()
                    cdp=await context.new_cdp_session(page);frames=[];ack_tasks=[]
                    def receive_seal_frame(event):
                        frames.append(base64.b64decode(event['data']))
                        ack_tasks.append(asyncio.create_task(cdp.send('Page.screencastFrameAck',{'sessionId':event['sessionId']})))
                    cdp.on('Page.screencastFrame',receive_seal_frame)
                    await cdp.send('Page.startScreencast',{'format':'jpeg','quality':80,'maxWidth':640,'maxHeight':640,'everyNthFrame':1})
                    def red_pixels(data):return seal_score(data,baseline,(uw,uh))
                    assert red_pixels(baseline)==0,'Pre-action red general must not be recognized as a victory seal'
                    await tap(r['skip'])
                    cursor=0;seen_seal=False;finished=False;blocked_checked=False;deadline=time.monotonic()+20
                    while not finished and time.monotonic()<deadline:
                        while cursor<len(frames):
                            count=red_pixels(frames[cursor]);cursor+=1
                            if count>1000:
                                seen_seal=True
                                if not blocked_checked:
                                    settled=await state()
                                    await tap((920,405) if w==1280 else (240,442))
                                    assert await state()==settled,'Reward input leaked through visible victory seal'
                                    blocked_checked=True
                            elif seen_seal and count==0:finished=True
                        if not finished:await asyncio.sleep(.05)
                    await cdp.send('Page.stopScreencast');await asyncio.gather(*ack_tasks);await cdp.detach()
                    assert finished,('victory display did not visibly finish',w,len(frames))
                    s=await state();assert s['phase']=='reward'
                    (output/f"{r['name']}-victory-red-counts.json").write_text(json.dumps([red_pixels(frame) for frame in frames]))
                    assert frames,('no victory compositor frames',w)
                    data=max(frames,key=red_pixels);red=red_pixels(data)
                    assert red>1000,('victory seal not visible in any frame',w,red,len(frames))
                    Image.open(io.BytesIO(data)).save(output/f"{r['name']}-{mode}-seal-before-reward.png")
                    await shot('reward-after-seal');assert await state()==s
                    await page.reload();await boot(page);await tap(r['resume']);await page.wait_for_timeout(450);await shot('reload-no-second-seal');assert await state()==s
                else:
                    await tap(r['choose']);await page.wait_for_timeout(140)
                    baseline=await page.screenshot()
                    # Stream compositor frames before input. Sequential screenshots
                    # can themselves outlast this short animation on slow runners.
                    cdp=await context.new_cdp_session(page);frames=[];ack_tasks=[]
                    def receive_frame(event):
                        frames.append((event['metadata'].get('timestamp',0),base64.b64decode(event['data'])))
                        ack_tasks.append(asyncio.create_task(cdp.send('Page.screencastFrameAck',{'sessionId':event['sessionId']})))
                    cdp.on('Page.screencastFrame',receive_frame)
                    await cdp.send('Page.startScreencast',{'format':'jpeg','quality':80,'maxWidth':640,'maxHeight':640,'everyNthFrame':1})
                    selected={};frame_info=[]
                    await tap(r['confirm'])
                    cursor=0;finished=False;deadline=time.monotonic()+20
                    while not finished and time.monotonic()<deadline:
                        while cursor<len(frames):
                            number=cursor;stamp,data=frames[cursor];cursor+=1
                            label,evidence=upgrade_frame(data,baseline,(uw,uh))
                            frame_info.append({'frame':number,'timestamp':stamp,'phase':label,**evidence})
                            if label and (label not in selected or label == 'upgraded-card'):selected[label]=(number,stamp,data)
                            if 'upgraded-card' in selected and label is None and evidence['header_ink_restored']>.8:
                                finished=True
                                Image.open(io.BytesIO(data)).save(output/f"{r['name']}-{mode}-map-after-display.png")
                        if not finished:await asyncio.sleep(.05)
                    await cdp.send('Page.stopScreencast');await asyncio.gather(*ack_tasks);await cdp.detach()
                    assert (await state())['collection']==r['after']
                    (output/f"{r['name']}-upgrade-frames.json").write_text(json.dumps(frame_info,indent=2))
                    # Retain visual evidence even when a later assertion fails.
                    for label,(_,stamp,data) in selected.items():
                        Image.open(io.BytesIO(data)).save(output/f"{r['name']}-{mode}-{label}.png")
                    if frames:Image.open(io.BytesIO(frames[-1][1])).save(output/f"{r['name']}-{mode}-last-frame.png")
                    assert finished,('upgrade display did not visibly finish',w,frame_info)
                    assert set(selected)=={'old-card','upgraded-card'},('missing distinct visible card phases',w,frame_info)
                    assert selected['old-card'][0]<selected['upgraded-card'][0],frame_info
                    await tap(r['view']);await page.wait_for_timeout(150);await shot('read-only-deck');s=await state();assert s['collection']==r['after']
                    await page.keyboard.press('Enter');await page.keyboard.press('Space');await tap(r['back']);await page.wait_for_timeout(150);assert await state()==s
                    await page.reload();await boot(page);await tap(r['resume']);await page.wait_for_timeout(450);assert (await state())['collection']==r['after'];await shot('reload-no-reroll')
                assert not errors,errors;reports.append({'viewport':[w,h],'mode':mode,'errors':errors});await context.close();print('PASS presentation',mode,w,flush=True)
        await browser.close()
    (output/'results.json').write_text(json.dumps(reports,indent=2));print('PRESENTATION WEB RESULT',len(reports),'cases')
if __name__=='__main__':asyncio.run(main())
