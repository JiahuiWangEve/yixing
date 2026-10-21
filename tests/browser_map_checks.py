from browser_settings import install_debug_settings
"""Real Web smoke test; native rendering checks are not a substitute for this.
Run a server over build/web on 8765 (or set YIXING_TEST_URL).
"""
import asyncio, json, os, re, shutil
from pathlib import Path
from playwright.async_api import async_playwright
from browser_event_checks import await_saved_state
ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'verification/v0.13.0/browser'
OUT.mkdir(parents=True, exist_ok=True)
URL = os.environ.get('YIXING_TEST_URL', 'http://127.0.0.1:8765')
XS = [.46,.15,.50,.85,.22,.76,.53,.13,.48,.86,.24,.73,.15,.49,.84,.79]
YS = [.94,.82,.79,.83,.69,.66,.56,.45,.43,.46,.33,.33,.20,.18,.21,.075]
async def main():
 reports=[]
 async with async_playwright() as p:
  executable = os.environ.get('CHROMIUM_PATH') or shutil.which('chromium')
  browser=await p.chromium.launch(**({'executable_path':executable} if executable else {}),headless=True,args=['--no-sandbox'])
  viewports = [(1280,940),(390,844),(844,390),(360,640)] if os.environ.get('YIXING_FULL_REGRESSION') == '1' else [(1280,940),(390,844)]
  for w,h in viewports:
   context=await browser.new_context(viewport={'width':w,'height':h},has_touch=True)
   page=await context.new_page();await install_debug_settings(page); errors=[]; assertions=[]; keyboard_assertions=[]
   page.on('pageerror',lambda e:errors.append(str(e)))
   page.on('console',lambda m: errors.append(m.text) if m.type=='error' and ('SCRIPT ERROR' in m.text or 'Parse Error' in m.text) else None)
   await page.goto(URL); await page.wait_for_timeout(4500)
   uw,uh=(1280,940) if w==1280 else ((960,540) if w>h else (480,max(660,480*h/w)))
   scale=min(w/uw,h/uh); ox=(w-uw*scale)/2; oy=(h-uh*scale)/2
   side=w==1280 or w>h
   mx,my,mw,mh,ch,margin=(24,116,850,800,1240,42) if w==1280 else ((14,90,626,436,1160,28) if side else (14,112,452,uh-282,(uh-282)*2.4,28))
   def content(i):return (mx+margin+XS[i]*(mw-margin*2),my+32+YS[i]*(ch-80))
   def focus(i):return max(0,min(ch-mh,content(i)[1]-my-mh*.73))
   def node(i,current=0):x,y=content(i);return (x,y-focus(current)-15)
   info_x=mx+mw+20; info_w=uw-(mx+mw)-44
   confirm=(info_x+info_w/2,my+mh-48) if side else (uw-107,uh-48)
   cancel=(info_x+info_w/2,my+mh-121) if side else (87,uh-48)
   async def tap(x,y,delay=180):
    await page.touchscreen.tap(ox+x*scale,oy+y*scale); await page.wait_for_timeout(delay)
   async def state(screen,current,pending):
    saved=None
    async def current_state():
     nonlocal saved
     saved=await page.evaluate("localStorage.getItem('yixing.route_run.v0100')")
     if not saved: return None
     return (re.search(r'^screen="(\w+)"',saved,re.M).group(1),int(re.search(r'"current": (-?\d+)',saved).group(1)),int(re.search(r'"pending": (-?\d+)',saved).group(1)))
    # Keep all original settle times and assert the same exact state tuple.
    # Only observe until an asynchronous map arrival's save has caught up.
    got=await await_saved_state(current_state,(screen,current,pending))
    if got != (screen,current,pending): await page.screenshot(path=str(OUT/f'failure-{w}.png'))
    assert saved, 'No synchronous Web snapshot'
    assert got==(screen,current,pending),(w,got,(screen,current,pending))
    assertions.append(list(got))
   async def shot(label):await page.screenshot(path=str(OUT/f'{label}-{w}.png'))
   menu=(640,209) if w==1280 else ((265,169) if side else (240,max(150,uh*.25)+30))
   await tap(*menu); await tap(*menu,500)
   await shot('map'); await tap(*node(0)); await state('map',-1,-1); await shot('preview')
   await tap(*cancel); await page.keyboard.press('Enter'); await page.wait_for_timeout(950)
   await state('map',-1,-1); await shot('cancel')
   await tap(*node(0)); await tap(*confirm,120); await tap(*confirm,1000)
   await state('game',-1,0); await shot('battle')
   if w == 1280:
    async def saved_turn():
     saved=await page.evaluate("localStorage.getItem('yixing.route_run.v0100')")
     return int(re.search(r'"turn": (\d+)',saved).group(1))
    before=await saved_turn()
    await page.keyboard.press('Enter'); await page.wait_for_timeout(1200)
    assert await saved_turn()==before, 'Enter must not end a battle turn'
    keyboard_assertions.append('Enter ignored in battle')
    await page.keyboard.down('Space'); await page.wait_for_timeout(1500)
    actual_turn=await await_saved_state(saved_turn,before+1)
    assert actual_turn==before+1, 'Space must end one battle turn'
    keyboard_assertions.append('Space ends one turn')
    await page.keyboard.down('Space'); await page.wait_for_timeout(1500)
    await page.keyboard.up('Space')
    assert await saved_turn()==before+1, 'Held Space repeat must not end another turn'
    keyboard_assertions.append('Held Space echo ignored')
    await shot('space-shortcut')
   await page.reload(); await page.wait_for_timeout(4500)
   resume=(640,425) if w==1280 else ((695,241) if side else (240,max(150,uh*.25)+252))
   await tap(*resume,500); await state('game',-1,0); await shot('resume')
   skip=(1098,102) if w==1280 else ((468,462) if side else (410,84))
   await tap(*skip,1200); await shot('reward')
   # v0.6.0 reward selector: third choice is Skip, not the older add-card footer.
   skip_reward=(920,405) if w==1280 else ((792,257) if side else (240,442))
   await tap(*skip_reward,500); await state('map',0,-1); await shot('returned')
   # Idle map frames must stay visually stable; touch drag must scroll without selecting.
   baseline=await page.screenshot()
   await page.wait_for_timeout(150)
   assert await page.screenshot()==baseline, 'Idle map should be visually stable'
   cdp=await context.new_cdp_session(page)
   dx=ox+(mx+mw*.48)*scale; dy=oy+(my+mh*.28)*scale
   await cdp.send('Input.dispatchTouchEvent',{'type':'touchStart','touchPoints':[{'x':dx,'y':dy}]})
   for step in range(1,13):
    await cdp.send('Input.dispatchTouchEvent',{'type':'touchMove','touchPoints':[{'x':dx,'y':dy+step*10*scale}]})
    await page.wait_for_timeout(16)
   await cdp.send('Input.dispatchTouchEvent',{'type':'touchEnd','touchPoints':[]})
   await page.wait_for_timeout(100)
   await state('map',0,-1)
   assert await page.screenshot()!=baseline, 'Touch drag must change map scroll position'
   await shot('touch-scrolled')
   center=cancel if side else (uw-107,uh-48)
   await tap(*center)
   assert await page.screenshot()==baseline, 'Focus-current restores exact static map after drag'
   frame_deltas=await page.evaluate("""() => new Promise(resolve => {let last=null, values=[]; function tick(now) {if(last!==null) values.push(now-last);last=now;if(values.length<60) requestAnimationFrame(tick);else resolve(values);}requestAnimationFrame(tick);})""")
   await cdp.detach()
   await tap(*node(1)); await tap(*confirm,350); await shot('march')
   await page.wait_for_timeout(700); await state('route_choice',0,1); await shot('event')
   await page.reload(); await page.wait_for_timeout(4500); await tap(*resume,500)
   await state('route_choice',0,1)
   saved=await page.evaluate("localStorage.getItem('yixing.route_run.v0100')")
   route=json.loads(saved.split('\nroute=',1)[1].split('\nbattle=',1)[0].replace('&\"','\"'))
   leave_index=3 if route['nodes'][1]['event_id']in ['merchant','manual'] else 2
   await tap(uw/2,199+leave_index*54,500); await state('map',1,-1)
   await shot('event-return'); await page.reload(); await page.wait_for_timeout(4500); await tap(*resume,500)
   await state('map',1,-1); await shot('map-resume')
   assert not errors,(w,errors)
   reports.append({'viewport':[w,h],'errors':errors,'state_assertions':assertions,'keyboard_assertions':keyboard_assertions,'map_performance':{'touch_scroll_checks':3,'idle_browser_raf_ms':frame_deltas},'note':'Actual Web export: touch preview/cancel/confirm, duplicate suppression, battle reload, debug reward return, curved march, event reload/resolve, map refresh.'})
   await context.close()
  await browser.close()
 (OUT/'browser-flow.json').write_text(json.dumps(reports,indent=2))
 print(json.dumps(reports))
asyncio.run(main())
