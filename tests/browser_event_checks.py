"""Replay production event saves through actual exported Web UI at four sizes.

Native test driver generates fixtures plus deterministic expected state. JS only
sets/reads the ordinary save, never calls game methods. Reload retains current
save (unlike an init script that would accidentally reset every reload).
"""
import asyncio, json, os, re, shutil
from pathlib import Path
from playwright.async_api import async_playwright
ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'verification/v0.13.0/events'
URL = os.environ.get('YIXING_TEST_URL', 'http://127.0.0.1:8765')
KEY = 'yixing.route_run.v0100'

def parse(text):
    route = json.loads(text.split('\nroute=', 1)[1].split('\nbattle=', 1)[0])
    battle = text.split('\nbattle=', 1)[1].rsplit('\nscreen=', 1)[0]
    battle = json.loads(re.sub(r'\bVector2i?\(([^()]*)\)', r'[\1]', battle).replace('&"', '"'))
    return dict(screen=re.search(r'^screen="(\w+)"', text, re.M).group(1),
                **{key:route[key] for key in ['current','pending','visited','prepared','reward_debt','reward_blocked']},
                **{key:battle[key] for key in ['collection','hand','rewards','lives','phase']})

async def boot(page):
    await page.wait_for_function("!document.getElementById('status')", timeout=60000)
    await page.wait_for_timeout(500)

async def main():
    (OUT/'browser').mkdir(parents=True,exist_ok=True)
    reports=[]
    replays=json.loads((OUT/'replays.json').read_text())
    async with async_playwright() as p:
        executable=os.environ.get('CHROMIUM_PATH') or shutil.which('chromium')
        browser=await p.chromium.launch(**({'executable_path':executable} if executable else {}),headless=True,args=['--no-sandbox'])
        for replay in replays:
            w,h=replay['viewport']; uw,uh=replay['logical_size']
            scale=min(w/uw,h/uh); ox=(w-uw*scale)/2; oy=(h-uh*scale)/2
            context=await browser.new_context(viewport={'width':int(w),'height':int(h)},has_touch=True)
            page=await context.new_page(); errors=[]
            page.on('pageerror',lambda e:errors.append(str(e)))
            page.on('console',lambda m: errors.append(m.text) if m.type=='error' and ('SCRIPT ERROR' in m.text or 'Parse Error' in m.text) else None)
            stem=replay['name']+'-'+str(int(w))
            async def tap(x,y,delay=160):
                await page.touchscreen.tap(ox+x*scale,oy+y*scale); await page.wait_for_timeout(delay)
            async def resume():
                pos=(640,497) if w==1280 else ((265,313) if w>h else (240,max(150,uh*.25)+326))
                await tap(*pos,350)
            async def snap(): return parse(await page.evaluate('(key)=>localStorage.getItem(key)',KEY))
            async def screenshot(label): await page.screenshot(path=str(OUT/'browser'/f'{stem}-{label}.png'))
            fixture=(OUT/'fixtures'/replay['fixture']).read_text()
            # Seed only once in a fresh context. Reload must not overwrite progress.
            await page.goto(URL); await boot(page)
            await page.evaluate('([key,value])=>localStorage.setItem(key,value)',[KEY,fixture])
            await page.reload(); await boot(page); await resume()
            assert await snap()==replay['initial'],(stem,'initial',await snap(),replay['initial'])
            await screenshot('initial')
            for number,step in enumerate(replay['steps']):
                if step['kind']=='reload':
                    await page.reload(); await boot(page); await resume()
                else:
                    for pos in step['taps']:
                        await tap(*pos)
                    await page.wait_for_timeout(1000 if step['kind']=='enter' else 400)
                actual=await snap()
                if actual!=step['expected']:
                    await screenshot('failure-'+str(number))
                    raise AssertionError((stem,number,step['label'],actual,step['expected']))
                if step['label'] in ['confirm','debug victory','select_exchange','select_copy'] or step['kind']=='reload':
                    await screenshot(str(number)+'-'+step['label'].replace(' ','-'))
            assert not errors,(stem,errors)
            reports.append({'fixture':replay['fixture'],'viewport':[w,h],'state_assertions':len(replay['steps'])+1,'errors':errors,'final':await snap()})
            await context.close()
            print('PASS',stem,len(replay['steps'])+1,'state checks',flush=True)
        await browser.close()
    (OUT/'browser'/'results.json').write_text(json.dumps(reports,ensure_ascii=False,indent=2))
    print(json.dumps({'replays':len(reports),'state_assertions':sum(x['state_assertions'] for x in reports),'errors':sum(len(x['errors']) for x in reports)}))

if __name__=='__main__': asyncio.run(main())
