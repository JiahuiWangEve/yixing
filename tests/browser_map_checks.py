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
   page=await context.new_page();await install_debug_settings(page); errors=[]; assertions=[]; keyboard_assertions=[]; map_assertions=[]
   page.on('pageerror',lambda e:errors.append(str(e)))
   page.on('console',lambda m: errors.append(m.text) if m.type=='error' and ('SCRIPT ERROR' in m.text or 'Parse Error' in m.text) else None)
   await page.goto(URL); await page.wait_for_timeout(4500)
   uw,uh=(1280,940) if w==1280 else ((960,540) if w>h else (480,max(660,480*h/w)))
   scale=min(w/uw,h/uh); ox=(w-uw*scale)/2; oy=(h-uh*scale)/2
   side=w==1280 or w>h
   mw=min(uw-28,1000); mx=(uw-mw)/2; my=90 if side and w!=1280 else 112; mh=uh-my-14
   ch,margin=(1240,42) if w==1280 else ((1160,28) if side else (mh*2.4,28))
   def content(i):return (mx+margin+XS[i]*(mw-margin*2),my+32+YS[i]*(ch-80))
   def focus(i):return max(0,min(ch-mh,content(i)[1]-my-mh*.73))
   def node(i,current=0):x,y=content(i);return (x,y-focus(current)-15)
   blank=(mx+8,my+mh*.85) # Inside the map, left of every landmark hitbox.
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
   async def shot(label):return await page.screenshot(path=str(OUT/f'{label}-{w}.png'))
   cdp=await context.new_cdp_session(page)
   def touch_point(pos,id=0):
    return {'x':ox+pos[0]*scale,'y':oy+pos[1]*scale,'id':id}
   async def touch(kind,points):
    await cdp.send('Input.dispatchTouchEvent',{'type':kind,'touchPoints':points})
   async def remains_map(current=-1):
    # A bad release can start a march before the save changes. Wait past its
    # full 0.85 s duration rather than passing against an unchanged old save.
    await page.wait_for_timeout(1100);await state('map',current,-1)
   async def drag_map(distance):
    start=(mx+mw*.48,my+mh*.28)
    await touch('touchStart',[touch_point(start)])
    # Cross the 12-logical-pixel gesture deadzone in the first event.
    # Ten-pixel initial moves can be coalesced differently by the Web input
    # frame, so symmetric physical paths need not have equal scroll deltas.
    for step in range(2,11):
     await touch('touchMove',[touch_point((start[0],start[1]+distance*step/10))])
     await page.wait_for_timeout(16)
    await touch('touchEnd',[])
    await page.wait_for_timeout(100)
   menu=(640,209) if w==1280 else ((265,169) if side else (240,max(150,uh*.25)+30))
   await tap(*menu); await tap(*menu,500)
   await state('map',-1,-1);await shot('map')
   if w==1280:
    # Real mouse hover opens information, but must not implicitly select.
    plain=await page.screenshot();nx,ny=node(0)
    await page.mouse.move(ox+nx*scale,oy+ny*scale);await page.wait_for_timeout(450)
    assert await shot('hover-info')!=plain,'Hover must show route information'
    await page.mouse.move(ox+uw*.5*scale,oy+80*scale);await page.wait_for_timeout(150)
    map_assertions.append('Mouse hover displays information without selecting')
   await tap(*node(0));await remains_map();await shot('selected')
   await tap(*blank);await page.keyboard.press('Enter');await remains_map();await shot('blank-cleared')
   await tap(*node(0));await remains_map()
   map_assertions.append('First click selects; blank map clears selection and Enter cannot depart')
   # Selecting another node replaces the old selection; unreachable nodes are
   # still inspectable but even repeated clicks must never start a journey.
   await tap(*node(1));await tap(*node(1));await remains_map()
   await tap(*node(0));await remains_map()
   map_assertions.append('Different node replaces selection; unreachable repeat cannot depart')
   for gesture in ['hold','cancel','multitouch-hold']:
    for already_selected in [False,True]:
     await tap(*blank)
     if already_selected:await tap(*node(0))
     before_gesture=await page.screenshot()
     await touch('touchStart',[touch_point(node(0))])
     if gesture=='hold':
      await page.wait_for_timeout(550)
      assert await shot('hold-selected' if already_selected else 'hold-info')!=before_gesture,'Touch hold must show route information'
     elif gesture=='multitouch-hold':
      # Secondary contact must not steal the primary long-hold capture.
      await touch('touchStart',[touch_point(node(0)),touch_point(blank,1)])
      await page.wait_for_timeout(550)
      assert await shot('multitouch-hold-selected' if already_selected else 'multitouch-hold-info')!=before_gesture,'Primary touch hold must still show information with a second finger present'
     await touch('touchCancel' if gesture=='cancel' else 'touchEnd',[])
     await remains_map()
     if not already_selected:
      # If the gesture secretly selected, this ordinary first click would depart.
      await tap(*node(0));await remains_map()
     map_assertions.append('%s on %s node does not select or depart'%(gesture,'selected' if already_selected else 'unselected'))
   await tap(*blank);await tap(*node(0));await remains_map()
   await page.wait_for_timeout(1200) # Selection is not a timed double-click window.
   await tap(*node(0),120);await tap(*node(0),1000)
   await state('game',-1,0);await shot('battle')
   map_assertions.append('Same selected node departs after a long delay; duplicate travel input suppressed')
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
   await drag_map(120);await remains_map(0)
   assert await page.screenshot()!=baseline, 'Touch drag must change map scroll position'
   await shot('touch-scrolled')
   await drag_map(-120);await remains_map(0)
   restored=await shot('touch-restored')
   assert restored==baseline, 'Equal opposite touch drag must restore the static map without a focus-current control'
   map_assertions.append('Drag scroll changes map and equal opposite drag restores it without selecting')
   frame_deltas=await page.evaluate("""() => new Promise(resolve => {let last=null, values=[]; function tick(now) {if(last!==null) values.push(now-last);last=now;if(values.length<60) requestAnimationFrame(tick);else resolve(values);}requestAnimationFrame(tick);})""")
   await cdp.detach()
   await tap(*node(1)); await tap(*node(1),350); await shot('march')
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
   reports.append({'viewport':[w,h],'errors':errors,'state_assertions':assertions,'keyboard_assertions':keyboard_assertions,'map_assertions':map_assertions,'map_performance':{'touch_scroll_checks':3,'idle_browser_raf_ms':frame_deltas},'note':'Actual Web export: centered map, first-click selection, delayed same-node departure, blank clearing, unreachable nodes, mouse hover and touch hold/cancel/multitouch safety, duplicate suppression, drag round-trip, battle reload, debug reward return, curved march, event reload/resolve, map refresh.'})
   await context.close()
  await browser.close()
 (OUT/'browser-flow.json').write_text(json.dumps(reports,indent=2))
 print(json.dumps(reports))
asyncio.run(main())
