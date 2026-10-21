"""Real touch grid selection on production saves; no game debug hooks."""
import argparse, asyncio, hashlib, json, os, shutil, time
from pathlib import Path
from playwright.async_api import async_playwright
from browser_event_checks import parse, boot, KEY
from browser_chapter_checks import assert_rendered
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'verification/v0.14.3/picker'
URL=os.environ.get('YIXING_TEST_URL','http://127.0.0.1:8765')
async def main(full=False):
    all_replays=json.loads((OUT/'replays.json').read_text())
    assert len(all_replays)==16
    widths={1280,390,360,844} if full else {1280,390}
    actions={'remove','upgrade','focus','homework'} if full else {'remove','upgrade'}
    replays=[r for r in all_replays if r['viewport'][0] in widths and r['action'] in actions]
    output=OUT/('browser-full' if full else 'browser-smoke');output.mkdir(parents=True,exist_ok=True)
    reports=[];started=time.monotonic()
    async with async_playwright() as p:
        exe=os.environ.get('CHROMIUM_PATH') or shutil.which('chromium')
        browser=await p.chromium.launch(**({'executable_path':exe} if exe else {}),headless=True,args=['--no-sandbox'])
        for replay in replays:
            w,h=replay['viewport'];uw,uh=replay['logical_size'];scale=min(w/uw,h/uh);ox=(w-uw*scale)/2;oy=(h-uh*scale)/2
            context=await browser.new_context(viewport={'width':int(w),'height':int(h)},has_touch=True)
            page=await context.new_page();cdp=await context.new_cdp_session(page);errors=[];screens=[]
            page.on('pageerror',lambda e:errors.append(str(e)))
            page.on('console',lambda m: errors.append(m.text) if m.type=='error' and ('SCRIPT ERROR' in m.text or 'Parse Error' in m.text) else None)
            def xy(pos): return {'x':ox+pos[0]*scale,'y':oy+pos[1]*scale}
            async def tap(pos):
                pt=xy(pos);await page.touchscreen.tap(pt['x'],pt['y']);await page.wait_for_timeout(140)
            async def snap(): return parse(await page.evaluate('(key)=>localStorage.getItem(key)',KEY))
            async def shot(label):
                path=output/f"{replay['name']}-{label}.png";data=await page.screenshot(path=str(path));assert_rendered(data,[w,h]);screens.append({'file':path.name,'sha256':hashlib.sha256(data).hexdigest()})
            async def drag(cancel=False):
                a,b=xy(replay['drag_from']),xy(replay['drag_to'])
                await cdp.send('Input.dispatchTouchEvent',{'type':'touchStart','touchPoints':[{**a,'id':1}]})
                for fraction in [.25,.5,.75,1]:
                    pt={key:a[key]+(b[key]-a[key])*fraction for key in ['x','y']}
                    await cdp.send('Input.dispatchTouchEvent',{'type':'touchMove','touchPoints':[{**pt,'id':1}]});await page.wait_for_timeout(20)
                await cdp.send('Input.dispatchTouchEvent',{'type':'touchCancel' if cancel else 'touchEnd','touchPoints':[]})
            try:
                fixture=(OUT/'fixtures'/replay['fixture']).read_text();initial=parse(fixture)
                await page.add_init_script('localStorage.setItem(%s,%s)'%(json.dumps(KEY),json.dumps(fixture)))
                await page.goto(URL);await boot(page);await tap(replay['resume']);await page.wait_for_timeout(350)
                assert await snap()==initial
                await tap(replay['open']);await shot('grid-top')
                await tap(replay['first']);await page.keyboard.press('Space');await shot('selected-first')
                await tap(replay['cancel']);assert await snap()==initial
                await tap(replay['open']);await drag(cancel=True);await tap(replay['confirm']);await page.wait_for_timeout(350)
                assert await snap()==initial,'canceled scroll committed action'
                await tap(replay['cancel']);await tap(replay['open'])
                for _ in range(replay['swipes']): await drag()
                await shot('scrolled-bottom')
                await tap(replay['confirm']);assert await snap()==initial,'scroll selected a card without tap'
                await tap(replay['last']);await shot('selected-last-copy')
                # Rotate/resize after selecting: the index must remain bound to the same copy.
                if full:
                    alternate=next(r for r in all_replays if r['action']==replay['action'] and r['viewport'][0]==(390 if w==844 else 844))
                    w,h=alternate['viewport'];uw,uh=alternate['logical_size'];scale=min(w/uw,h/uh);ox=(w-uw*scale)/2;oy=(h-uh*scale)/2
                    await page.set_viewport_size({'width':int(w),'height':int(h)});await page.wait_for_timeout(400);await shot('rotated-selected')
                    confirm=alternate['confirm']
                else: confirm=replay['confirm']
                await tap(confirm);await tap(confirm)
                deadline=time.monotonic()+8
                while True:
                    result=await snap()
                    if result['collection']==replay['after'] and result['pending_homework']==replay['homework'] and result['reward_debt']==replay['debt'] and result['screen']=='map': break
                    assert time.monotonic()<deadline,(replay['name'],result,replay['after']);await page.wait_for_timeout(80)
                await page.wait_for_timeout(1100);assert await snap()==result,'duplicate commit after rapid second tap'
                await shot('committed-exact-copy');assert not errors,errors
                reports.append({'fixture':replay['fixture'],'screenshots':screens,'errors':errors,'final':result})
                print('PASS picker',replay['name'],flush=True)
            except Exception:
                await page.screenshot(path=str(output/f"{replay['name']}-failure.png"));raise
            finally: await cdp.detach();await context.close()
        await browser.close()
    result={'replays':len(reports),'elapsed_seconds':round(time.monotonic()-started,2),'cases':reports}
    (output/'results.json').write_text(json.dumps(result,ensure_ascii=False,indent=2));print('PICKER WEB RESULT',len(reports),'replays')
if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--full',action='store_true');args=parser.parse_args();asyncio.run(main(args.full))
