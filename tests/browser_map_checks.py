from browser_settings import install_debug_settings
"""Real Web smoke test; native rendering checks are not a substitute for this.
Run a server over build/web on 8765 (or set YIXING_TEST_URL).
"""
import asyncio, json, os, re, shutil
from pathlib import Path
from playwright.async_api import async_playwright
from browser_event_checks import await_saved_state, variant_json
ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'verification/v0.13.0/browser'
URL = os.environ.get('YIXING_TEST_URL', 'http://127.0.0.1:8765')
def saved_route(text):
 """Decode only the ordinary production save, never a runtime/debug hook."""
 assert text, 'No synchronous Web snapshot'
 route = variant_json(text.split('\nroute=', 1)[1].split('\nbattle=', 1)[0])
 assert route['nodes'] and all(node['id'] == i for i, node in enumerate(route['nodes']))
 for node in route['nodes']:
  assert all(isinstance(node[key], (int, float)) and not isinstance(node[key], bool)
             and 0 <= node[key] <= 1 for key in ('x', 'y')), node
 return route

class RouteGeometry:
 """Public map projection from route_map.gd, using persisted node coordinates.

 This intentionally models production map_rect/content_height/content_point and
 focus_current instead of assuming any seed's node count, kind, or lane position.
 Every browser entry below still clicks the normal exported canvas UI.
 """
 def __init__(self, route, width, height):
  self.route = route
  self.desktop = width == 1280
  self.landscape = width > height and not self.desktop
  self.uw, self.uh = ((1280, 940) if self.desktop else
                     ((960, 540) if self.landscape else (480, max(660, 480*height/width))))
  self.mw = min(self.uw - 28, 1000)
  self.mx = (self.uw - self.mw)/2
  self.my = 90 if self.landscape else 112
  self.mh = self.uh - self.my - 14
  self.ch = 1520 if self.desktop else (1440 if self.landscape else max(1440, self.mh*2.4))
  self.margin = 42 if self.desktop else 28

 def content(self, node_id):
  node = self.route['nodes'][node_id]
  return (self.mx + self.margin + node['x']*(self.mw - self.margin*2),
          self.my + 160 + node['y']*(self.ch - 220))

 def focus(self, current=None):
  if current is None: current = self.route['current']
  return max(0, min(self.ch - self.mh, self.content(max(0, current))[1] - self.my - self.mh*.73))

 def node(self, node_id, current=None):
  x, y = self.content(node_id)
  return x, y - self.focus(current) - 15

 def visible(self, node_id, current=None):
  x, y = self.node(node_id, current)
  return self.mx + 6 < x < self.mx + self.mw - 6 and self.my + 8 < y < self.my + self.mh - 8

 def blank(self, current=None):
  # Generated lanes can reach either map edge. Find a point outside every real
  # landmark hitbox rather than assuming a fixed empty strip exists on the left.
  width = 102 if self.desktop else (92 if self.landscape else 88)
  for xf in (.01, .99, .5, .25, .75):
   for yf in (.85, .65, .45, .25):
    point = self.mx + self.mw*xf, self.my + self.mh*yf
    hit = False
    for node in self.route['nodes']:
     x, y = self.content(node['id']); y -= self.focus(current)
     size = width*(1.2 if node['kind'] == 'boss' else 1)
     if x - size/2 - 6 <= point[0] <= x + size/2 + 6 and y - size + 7 <= point[1] <= y + 43:
      hit = True; break
    if not hit: return point
  raise AssertionError('No blank map point outside generated landmark hitboxes')


def event_path(route, start):
 """Find a real forward route to an event; don't assume node 1 is an event."""
 queue = [(start, [])]
 seen = {start}
 while queue:
  current, path = queue.pop(0)
  for target in route['nodes'][current]['next']:
   if target in seen: continue
   seen.add(target)
   next_path = path + [target]
   if route['nodes'][target]['kind'] == 'event': return next_path
   queue.append((target, next_path))
 raise AssertionError(('No reachable event in generated chapter', route['seed'], start))


def leave_point(node, width, height):
 # Merchant offers now have a fixed bottom leave button, not a text-option row.
 if node.get("event_id") == "merchant": return (width / 2, height - 40)
 return (width / 2, 199 + leave_index(node) * 54)

def leave_index(node):
 if node['kind'] == 'workshop': return 1
 if node['kind'] == 'camp' or node['event_id'] == 'herbalist': return 2
 if node['event_id'] == 'merchant': return len(node['offers'])
 assert node['event_id'] == 'manual', node
 return 3

async def main():
 OUT.mkdir(parents=True, exist_ok=True)
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
   async def tap(x,y,delay=180):
    await page.touchscreen.tap(ox+x*scale,oy+y*scale); await page.wait_for_timeout(delay)
   async def state(screen,current,pending):
    saved=None
    async def current_state():
     nonlocal saved
     saved=await page.evaluate("localStorage.getItem('yixing.route_run.v0149')")
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
   await state('map',-1,-1)
   # An event is not compulsory in every valid random chapter. Choose a run
   # containing one through New Run UI, never by rewriting/injecting a fixture.
   # Event round-trip coverage remains mandatory, not a conditional skip.
   skipped_seeds=[]
   for attempt in range(16):
    route=saved_route(await page.evaluate("localStorage.getItem('yixing.route_run.v0149')"))
    if any(n['kind']=='event' for n in route['nodes']): break
    skipped_seeds.append(route['seed'])
    if attempt<15:
     await tap(74,34);await tap(*menu);await tap(*menu,500)
     await state('map',-1,-1)
   path=event_path(route,0)
   await shot('map')
   geometry=RouteGeometry(route,w,h)
   node=geometry.node;blank=geometry.blank()
   assert route['nodes'][0]['kind']=='battle', 'Generated entrance must remain a battle'
   assert geometry.visible(0), 'Entrance must be visible after production auto-focus'
   unreachable=next((n['id'] for n in route['nodes'] if n['id']!=0 and geometry.visible(n['id'])),None)
   assert unreachable is not None, 'Need a visible unreachable landmark for strict selection checks'
   if w==1280:
    # Mouse hover frames immediately and reveals information after its dwell.
    plain=await page.screenshot();nx,ny=node(0)
    await page.mouse.move(ox+nx*scale,oy+ny*scale);await page.wait_for_timeout(450)
    assert await shot('hover-info')!=plain,'Hover must show framed route information'
    await page.mouse.move(ox+uw*.5*scale,oy+80*scale);await page.wait_for_timeout(150)
    assert await page.screenshot()==plain,'Leaving the node must clear frame and hover information'
    map_assertions.append('Mouse hover inspects; mouse exit clears without departure')
   await tap(*node(unreachable));await remains_map()
   await tap(*blank);await page.keyboard.press('Enter');await remains_map()
   map_assertions.append('Single nonlegal tap never departs; blank clears and Enter cannot depart')
   for gesture in ['hold','cancel','multitouch']:
    await tap(*blank)
    before_gesture=await page.screenshot()
    await touch('touchStart',[touch_point(node(0))])
    if gesture=='hold':
     await page.wait_for_timeout(550)
     held=await shot('hold-info')
     assert held!=before_gesture,'Touch hold must show framed route information'
    elif gesture=='multitouch':
     await touch('touchStart',[touch_point(node(0)),touch_point(blank,1)])
     await page.wait_for_timeout(550)
    await touch('touchCancel' if gesture=='cancel' else 'touchEnd',[])
    await remains_map()
    if gesture=='hold':
     assert await shot('hold-release-sticky')==held,'Long-hold release must retain frame and tooltip'
     await tap(*blank)
     assert await page.screenshot()==before_gesture,'Blank tap must clear sticky frame and tooltip'
    else:
     assert await page.screenshot()==before_gesture,'Canceled/multiple touch sequence must clear its frame'
    map_assertions.append(gesture+' inspects or cancels without departure')
   # Exactly one ordinary release enters; no preselection or confirming tap.
   await tap(*node(0),1000)
   await state('game',-1,0);await shot('battle')
   map_assertions.append('One short tap departs without a preselection or confirming tap')
   if w == 1280:
    async def saved_turn():
     saved=await page.evaluate("localStorage.getItem('yixing.route_run.v0149')")
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
   # Reach a genuinely generated event through legal edges and normal UI. A
   # random first branch may contain battles, camps, or workshops on the way.
   current=0
   for target in path:
    assert target in route['nodes'][current]['next'], (current,target)
    assert geometry.visible(target,current), ('Next route node is not visible',current,target)
    await tap(*node(target,current),350)
    await shot('march' if target==path[-1] else 'march-'+str(target))
    await page.wait_for_timeout(700)
    kind=route['nodes'][target]['kind']
    expected='game' if kind in ['battle','elite','boss'] else 'route_choice'
    await state(expected,current,target)
    if target==path[-1]: break
    if expected=='game':
     await tap(*skip,1200)
     await page.wait_for_function('/"phase": "reward"/.test(localStorage.getItem("yixing.route_run.v0149")||"")',timeout=12000)
     await page.wait_for_timeout(1150)
     await tap(*skip_reward,500)
    else:
     await tap(*leave_point(route['nodes'][target],uw,uh),500)
    await state('map',target,-1);current=target
    await page.wait_for_timeout(450) # Completed-node seal settles before more input.
   event_id=path[-1]
   assert route['nodes'][event_id]['kind']=='event'
   await shot('event')
   await page.reload(); await page.wait_for_timeout(4500); await tap(*resume,500)
   await state('route_choice',current,event_id)
   restored=saved_route(await page.evaluate("localStorage.getItem('yixing.route_run.v0149')"))
   assert restored['nodes']==route['nodes'], 'Reload changed generated graph or coordinates'
   await tap(*leave_point(restored['nodes'][event_id],uw,uh),500)
   await state('map',event_id,-1)
   await shot('event-return'); await page.reload(); await page.wait_for_timeout(4500); await tap(*resume,500)
   await state('map',event_id,-1); await shot('map-resume')
   assert not errors,(w,errors)
   reports.append({'viewport':[w,h],'errors':errors,'state_assertions':assertions,'keyboard_assertions':keyboard_assertions,'map_assertions':map_assertions,'event_path':path,'skipped_eventless_seeds':skipped_seeds,'map_performance':{'touch_scroll_checks':3,'idle_browser_raf_ms':frame_deltas},'note':'Actual Web export: centered map, single-tap departure, blank clearing, unreachable nodes, immediate hover framing and sticky touch hold/cancel/multitouch safety, drag round-trip, battle reload, debug reward return, curved march, event reload/resolve, map refresh.'})
   await context.close()
  await browser.close()
 (OUT/'browser-flow.json').write_text(json.dumps(reports,indent=2))
 print(json.dumps(reports))
if __name__=='__main__':asyncio.run(main())
