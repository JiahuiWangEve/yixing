"""Treasure chapter choices and read-only HUD through ordinary exported Web UI.
Only production saved-game fixtures are installed; no runtime gameplay hooks.
"""
import argparse, asyncio, hashlib, io, json, os, shutil, time
from pathlib import Path
from PIL import Image
from playwright.async_api import async_playwright
from browser_chapter_checks import assert_rendered, image_difference, inspection_save
from browser_event_checks import variant_json
from browser_card_catalog_checks import scroll_plan, drag_points, drag_fractions
ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'verification/v0.15.0/treasure-ui'
URL = os.environ.get('YIXING_TEST_URL', 'http://127.0.0.1:8765')
KEY = 'yixing.route_run.v0149'

def state(text): return inspection_save(text)

def validate():
    data = json.loads((OUT / 'replays.json').read_text())
    assert data['web_save_key'] == KEY
    replays = data['replays']
    assert len(replays) == 12
    for r in replays:
        initial = state((OUT/'fixtures'/r['fixture']).read_text())
        assert initial['screen'] == 'treasure_choice'
        assert initial['route']['treasure_choices'] == r['choice_ids']
        assert len(set(r['choice_ids'])) == 3
        for i, entry in enumerate(r['claimed_fixtures']):
            expected = state((OUT/'fixtures'/entry['map_fixture']).read_text())
            assert expected['route']['chapter'] == 2 and expected['route']['treasure_id'] == r['choice_ids'][i]
            assert expected['route']['treasure_claimed'] and not expected['route']['treasure_choices']
            assert expected['battle']['collection'] == initial['battle']['collection']
            assert expected['battle']['lives'] == initial['battle']['lives']
    return replays

async def main(full=False, validate_only=False):
    replays = validate()
    if validate_only:
        print('PASS treasure Web descriptors: 12 layouts, 36 persisted claims'); return
    output = OUT/('browser-full' if full else 'browser-smoke'); output.mkdir(parents=True, exist_ok=True)
    reports=[]
    async with async_playwright() as p:
        executable=os.environ.get('CHROMIUM_PATH') or shutil.which('chromium')
        browser=await p.chromium.launch(**({'executable_path':executable} if executable else {}),headless=True,args=['--no-sandbox'])
        try:
            for r in replays:
                w,h=map(int,r['viewport'])
                if not full and w not in (1280,390): continue
                for slot in (range(3) if full else [0]):
                    entry=r['claimed_fixtures'][slot]; stem=f"{entry['id']}-{w}"
                    context=await browser.new_context(viewport={'width':w,'height':h},has_touch=w!=1280)
                    page=await context.new_page();cdp=await context.new_cdp_session(page);errors=[];shots=[]
                    page.on('pageerror',lambda error:errors.append(str(error)))
                    page.on('console',lambda msg:errors.append(msg.text) if msg.type=='error' and ('SCRIPT ERROR' in msg.text or 'Parse Error' in msg.text) else None)
                    uw,uh=r['logical_size'];scale=min(w/uw,h/uh);ox=(w-uw*scale)/2;oy=(h-uh*scale)/2
                    def xy(pos):return {'x':ox+pos[0]*scale,'y':oy+pos[1]*scale}
                    async def tap(pos):
                        pt=xy(pos)
                        if w==1280:await page.mouse.click(pt['x'],pt['y'])
                        else:await page.touchscreen.tap(pt['x'],pt['y'])
                    async def raw():return await page.evaluate('(key)=>localStorage.getItem(key)',KEY)
                    async def expect(expected,label):
                        deadline=time.monotonic()+10
                        while True:
                            actual=state(await raw())
                            if actual==expected:return
                            assert time.monotonic()<deadline,(stem,label,actual,expected)
                            await page.wait_for_timeout(80)
                    async def shot(label):
                        data=await page.screenshot(path=str(output/f'{stem}-{label}.png'));assert_rendered(data,[w,h])
                        shots.append({'label':label,'sha256':hashlib.sha256(data).hexdigest()});return data
                    async def boot():
                        await page.wait_for_function("!document.getElementById('status')",timeout=60000)
                        await page.wait_for_timeout(250)
                    async def resume():
                        await boot();await tap(r['resume']);await page.wait_for_timeout(250)
                    async def install(filename):
                        await page.evaluate('([key,text])=>localStorage.setItem(key,text)',[KEY,(OUT/'fixtures'/filename).read_text()])
                        await page.reload();await resume()
                    async def inspect(pos,label,rect):
                        before=await shot(label+'-before');saved=state(await raw());pt=xy(pos)
                        if w==1280:
                            await page.mouse.move(pt['x'],pt['y'])
                        else:
                            await cdp.send('Input.dispatchTouchEvent',{'type':'touchStart','touchPoints':[{**pt,'id':1}]})
                        x,y,rw,rh=rect
                        box=tuple(round(v) for v in [ox+(x+4)*scale,oy+(y+4)*scale,ox+(x+rw-4)*scale,oy+(y+rh-4)*scale])
                        deadline=time.monotonic()+4
                        while True:
                            await page.wait_for_timeout(100)
                            after=await page.screenshot()
                            patch=Image.open(io.BytesIO(after)).convert('RGB').crop(box)
                            pixels=list(patch.getdata())
                            paper=sum(max(abs(c-t) for c,t in zip(rgb,(252,249,241)))<=6 for rgb in pixels)/max(1,len(pixels))
                            ink=sum(max(rgb)<130 for rgb in pixels)
                            difference=image_difference(before,after,box)
                            if paper>.5 and ink>10 and difference>.5:break
                            assert time.monotonic()<deadline,(stem,label,'no readable paper-and-ink popup',paper,ink,difference)
                        after=await shot(label+'-open')
                        assert state(await raw())==saved,(stem,label,'inspection changed gameplay')
                        if w!=1280:await cdp.send('Input.dispatchTouchEvent',{'type':'touchEnd','touchPoints':[]})
                        else:await page.mouse.move(2,2)
                        await page.wait_for_timeout(100)
                        assert state(await raw())==saved
                    try:
                        fixture=(OUT/'fixtures'/r['fixture']).read_text();initial=state(fixture)
                        await page.add_init_script("if(!sessionStorage.getItem('treasure-seeded')){localStorage.setItem(%s,%s);sessionStorage.setItem('treasure-seeded','1');}"%(json.dumps(KEY),json.dumps(fixture)))
                        await page.goto(URL);await resume();await expect(initial,'pending choice restored');await shot('three-choices')
                        for key in ['1','2','3','4','5','6','7','Space','Enter','Escape']:await page.keyboard.press(key)
                        await expect(initial,'battle shortcuts cannot claim')
                        # A real canceled touch cannot commit a choice.
                        point=r['choice_taps'][0]
                        if w!=1280 and point:
                            pt=xy(point);await cdp.send('Input.dispatchTouchEvent',{'type':'touchStart','touchPoints':[{**pt,'id':1}]})
                            await cdp.send('Input.dispatchTouchEvent',{'type':'touchCancel','touchPoints':[]})
                            await expect(initial,'canceled touch does not claim')
                        desired=r['choice_scrolls'][slot]['scroll'];current=0
                        steps,current=scroll_plan(r['grid'],0,desired,r['scroll_limit'])
                        for delta in steps:
                            a,b=drag_points(r['grid'],delta);aa,bb=xy(a),xy(b)
                            if w==1280:
                                await page.mouse.move(aa['x'],aa['y']);await page.mouse.down()
                                await page.mouse.move(bb['x'],bb['y'],steps=1);await page.mouse.up()
                            else:
                                await cdp.send('Input.dispatchTouchEvent',{'type':'touchStart','touchPoints':[{**aa,'id':1}]})
                                for fraction in drag_fractions(delta):
                                    pt={k:aa[k]+(bb[k]-aa[k])*fraction for k in ('x','y')}
                                    await cdp.send('Input.dispatchTouchEvent',{'type':'touchMove','touchPoints':[{**pt,'id':1}]})
                                await cdp.send('Input.dispatchTouchEvent',{'type':'touchEnd','touchPoints':[]})
                            await expect(initial,'scroll never claims')
                        point=r['choice_scrolls'][slot]['tap'];point=[point[0],point[1]+desired-current]
                        await tap(point)
                        expected=state((OUT/'fixtures'/entry['map_fixture']).read_text())
                        await expect(expected,'one click claims exact treasure and chapter');await shot('claimed-map')
                        await page.reload();await resume();await expect(expected,'claimed reload cannot offer again')
                        await inspect(entry['map_icon'],'map-icon-rules',entry['map_popup'])
                        await install(entry['battle_fixture'])
                        battle=state((OUT/'fixtures'/entry['battle_fixture']).read_text())
                        await expect(battle,'battle restores trigger state');await shot('battle-icon')
                        await inspect(entry['battle_icon'],'battle-icon-rules',entry['battle_popup'])
                        assert not errors,errors
                        reports.append({'id':entry['id'],'viewport':[w,h],'screenshots':shots,'errors':errors})
                        print('PASS treasure Web',stem,'claim/reload/shortcut/cancel/scroll/map and battle inspection',flush=True)
                    except Exception:
                        await page.screenshot(path=str(output/f'{stem}-failure.png'));raise
                    finally:
                        await cdp.detach();await context.close()
        finally:await browser.close()
    (output/'results.json').write_text(json.dumps(reports,ensure_ascii=False,indent=2))
    print('TREASURE WEB RESULT',len(reports),'actual UI cases')
if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--full',action='store_true');parser.add_argument('--validate-only',action='store_true');args=parser.parse_args();asyncio.run(main(args.full,args.validate_only))
