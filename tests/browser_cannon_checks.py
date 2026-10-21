"""Exercise actual exported Godot through normal Continue/touch/Space flows.

Generate fixtures first with tests/cannon_visual_capture.gd. Fixtures are valid
production saves, not runtime debug hooks. No game internals are injected.
"""
import asyncio
import base64
import io
import json
import math
import os
import re
import shutil
from pathlib import Path
from PIL import Image, ImageDraw
from playwright.async_api import async_playwright

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'verification/v0.11.0/cannon/browser'
FIXTURES = OUT.parent / 'fixtures'
URL = os.environ.get('YIXING_TEST_URL', 'http://127.0.0.1:8765')
KEY = 'yixing.route_run.v0100'
NAMES = ['support_first', 'cannon_first', 'held_support', 'obsolete_line',
         'boss_credit_cap', 'stress_four_cannons']


def parse_save(text):
    battle = text.split('\nbattle=', 1)[1].rsplit('\nscreen=', 1)[0]
    battle = re.sub(r'\bVector2i?\(([^()]*)\)', r'[\1]', battle)
    return json.loads(battle.replace('&"', '"'))


def summary(battle):
    return {'player': battle['player'], 'turn': battle['turn'], 'lives': battle['lives'],
            'pieces': [{'uid': e['uid'], 'kind': e['kind'], 'pos': e['pos'],
                        'cd': e['cd'], 'period': e['period'],
                        'credits': e.get('action_credits', 0),
                        'moves': e.get('normal_moves', 0),
                        'intent': e.get('intent', [-1, -1])}
                       for e in battle['enemies']]}


def layout(w, h):
    if w == 1280:
        return {'scale': 1, 'resume': (640, 497), 'end': (791.5, 600.5),
                'board': (417, 74, 863, 568), 'origin': (448, 105), 'cell': 48}
    uh = max(660, 480 * h / w)
    scale = w / 480
    cell = max(24, min(44, (uh - 450) / 9))
    origin = (240 - 4 * cell, 135)
    bottom = 159 + 9 * cell
    return {'scale': scale, 'resume': (240 * scale, (max(150, uh * .25) + 326) * scale),
            'end': (386.5 * scale, (bottom + 32) * scale),
            'board': ((origin[0] - 24) * scale, 111 * scale,
                      (origin[0] + 8 * cell + 24) * scale, bottom * scale),
            'origin': (origin[0] * scale, 135 * scale), 'cell': cell * scale}


async def load_fixture(page, fixture, geometry):
    await page.add_init_script('localStorage.setItem(' + json.dumps(KEY) + ',' + json.dumps(fixture) + ');')
    await page.goto(URL)
    await page.wait_for_function("!document.getElementById('status')", timeout=60000)
    await page.wait_for_timeout(800)
    await page.touchscreen.tap(*geometry['resume'])
    await page.wait_for_timeout(350)


async def snapshot(page):
    return await page.evaluate('(key) => localStorage.getItem(key)', KEY)


async def instrument(page):
    await page.evaluate('''() => new Promise(resolve => {
      const trace = window.cannonQaTrace = {start: performance.now(), inputAt: null,
        firstSaveAt: null, frames: [], last: null, baselineFrames: 0, running: true};
      const input = () => { if(trace.inputAt === null) trace.inputAt = performance.now(); };
      document.addEventListener('touchstart', input, {once:true, capture:true});
      document.addEventListener('keydown', input, {once:true, capture:true});
      function frame(now) {
        if(!trace.running) return;
        if(trace.last !== null && trace.inputAt !== null) trace.frames.push(now - trace.last);
        trace.last = now;
        if(trace.inputAt === null && ++trace.baselineFrames >= 2) resolve();
        const save = localStorage.getItem('yixing.route_run.v0100') || '';
        if(trace.inputAt !== null && trace.firstSaveAt === null && /"turn": 2[,\\n]/.test(save)) trace.firstSaveAt=now;
        requestAnimationFrame(frame);
      }
      requestAnimationFrame(frame);
    })''')


async def trace_result(page):
    return await page.evaluate('''() => {
      const t = window.cannonQaTrace; t.running=false;
      const sorted=[...t.frames].sort((a,b)=>a-b);
      return {input_to_saved_turn_ms: t.firstSaveAt !== null && t.inputAt !== null ? t.firstSaveAt-t.inputAt : null,
        max_raf_interval_ms: Math.max(...t.frames),
        p95_raf_interval_ms: sorted[Math.floor(sorted.length*.95)],
        raf_samples: t.frames, baseline_frames: t.baselineFrames,
        input_event_recorded: t.inputAt !== null};
    }''')


async def movement_film(context, page, fixture, geometry, stem):
    # A separate replay avoids including screenshot transport in performance data.
    await page.reload()
    await page.wait_for_function("!document.getElementById('status')", timeout=60000)
    await page.wait_for_timeout(500)
    await page.touchscreen.tap(*geometry['resume'])
    await page.wait_for_timeout(200)
    cdp = await context.new_cdp_session(page)
    frames = []
    async def frame(params):
        frames.append(params)
        await cdp.send('Page.screencastFrameAck', {'sessionId': params['sessionId']})
    cdp.on('Page.screencastFrame', frame)
    await cdp.send('Page.startScreencast', {'format': 'jpeg', 'quality': 88, 'everyNthFrame': 1})
    await page.wait_for_timeout(80)
    await page.touchscreen.tap(*geometry['end'])
    await page.wait_for_timeout(1400)
    await cdp.send('Page.stopScreencast')
    await cdp.detach()
    film_dir = OUT / stem
    film_dir.mkdir(exist_ok=True)
    manifest = []
    sheets = []
    t0 = frames[0]['metadata']['timestamp'] if frames else 0
    for i, frame in enumerate(frames):
        data = base64.b64decode(frame['data'])
        (film_dir / f'{i:03d}.jpg').write_bytes(data)
        elapsed = (frame['metadata']['timestamp'] - t0) * 1000
        manifest.append({'frame': i, 'elapsed_ms': elapsed, 'file': f'{i:03d}.jpg'})
        image = Image.open(io.BytesIO(data)).crop(tuple(map(int, geometry['board'])))
        image.thumbnail((223, 247))
        tile = Image.new('RGB', (235, 280), '#ffffff')
        tile.paste(image, ((235-image.width)//2, 24))
        ImageDraw.Draw(tile).text((6, 5), f'{i:02d}: {elapsed:.0f}ms', fill='black')
        sheets.append(tile)
    # Keep all real frames on disk; contact sheet samples preserve chronological order.
    selected = sheets if len(sheets) <= 24 else [sheets[round(i*(len(sheets)-1)/23)] for i in range(24)]
    sheet = Image.new('RGB', (6*235, ((len(selected)+5)//6)*280), '#dddddd')
    for i, tile in enumerate(selected): sheet.paste(tile, ((i%6)*235, (i//6)*280))
    sheet.save(OUT / f'{stem}-contact.png')
    (film_dir/'frames.json').write_text(json.dumps(manifest, indent=2))
    assert len(frames) >= 4, 'Insufficient real animation frames'
    return {'frame_count':len(frames), 'manifest':str((film_dir/'frames.json').relative_to(ROOT)),
            'contact_sheet':str((OUT/f'{stem}-contact.png').relative_to(ROOT))}


async def main():
    OUT.mkdir(parents=True, exist_ok=True)
    expected_doc = json.loads((OUT.parent / 'native-behavior.json').read_text())
    expected = {(r['name'], r['viewport'][0]):r for r in expected_doc['scenarios']}
    reports=[]
    async with async_playwright() as p:
        executable=os.environ.get('CHROMIUM_PATH') or shutil.which('chromium')
        browser=await p.chromium.launch(**({'executable_path':executable} if executable else {}), headless=True,args=['--no-sandbox'])
        for w,h in [(1280,940),(390,844)]:
            context=await browser.new_context(viewport={'width':w,'height':h},has_touch=True)
            geometry=layout(w,h)
            for name in NAMES:
                page=await context.new_page();errors=[]
                page.on('pageerror', lambda e:errors.append(str(e)))
                page.on('console', lambda m:errors.append(m.text) if m.type=='error' and ('SCRIPT ERROR' in m.text or 'Parse Error' in m.text) else None)
                fixture=(FIXTURES/f'{name}.cfg').read_text()
                await load_fixture(page,fixture,geometry)
                before=summary(parse_save(await snapshot(page)))
                assert before==expected[(name,w)]['before'],(name,w,'before',before)
                await page.screenshot(path=str(OUT/f'{name}-before-{w}.png'))
                await instrument(page)
                if w==1280: await page.keyboard.press('Space')
                else: await page.touchscreen.tap(*geometry['end'])
                await page.wait_for_function("/\"turn\": 2[,\\n]/.test(localStorage.getItem('yixing.route_run.v0100')||'')",timeout=20000)
                await page.wait_for_timeout(200)
                after=summary(parse_save(await snapshot(page)))
                performance=await trace_result(page)
                assert after==expected[(name,w)]['after'],(name,w,'after',after,expected[(name,w)]['after'])
                assert all(e['intent']==[-1,-1] for e in after['pieces'])
                if name in ['boss_credit_cap','stress_four_cannons']:
                    assert all(e['moves']<=1 for e in after['pieces'])
                assert performance['input_event_recorded']
                await page.screenshot(path=str(OUT/f'{name}-after-{w}.png'))
                film=await movement_film(context,page,fixture,geometry,f'{name}-motion-{w}') if name in ['cannon_first','support_first'] else None
                assert not errors,(name,w,errors)
                report={'scenario':name,'viewport':[w,h],'input':'Space' if w==1280 else 'touch end-turn',
                        'before':before,'after':after,'performance':performance,'motion':film,'errors':errors}
                reports.append(report)
                (OUT/'browser-cannon-report.json').write_text(json.dumps({'reports':reports,
                    'notes':['Real Chromium Web export, no injected gameplay API. Valid production save fixtures resumed through UI.',
                    'Input-to-save includes animation lock and existing autosave cadence, not just AI execution.',
                    'Mobile is a 390x844 touch viewport on the same cloud CPU, not physical-device performance.',
                    'Screencast recording is a separate replay and is excluded from performance samples.']},indent=2))
                assert performance['baseline_frames'] >= 2
                assert len(performance['raf_samples']) >= 3, 'Empty/insufficient RAF performance samples'
                assert all(isinstance(x,(int,float)) and math.isfinite(x) and x >= 0
                           for x in performance['raf_samples']), 'Invalid RAF sample'
                assert performance['input_to_saved_turn_ms'] is not None and math.isfinite(performance['input_to_saved_turn_ms'])
                assert 0 <= performance['input_to_saved_turn_ms'] <= 8000,(name,w,'Input-to-save exceeds 8 seconds',performance)
                assert math.isfinite(performance['max_raf_interval_ms']) and performance['max_raf_interval_ms'] <= 250,(name,w,'RAF interval exceeds 250ms',performance)
                print(json.dumps({'scenario':name,'viewport':[w,h],'max_raf_ms':performance['max_raf_interval_ms'],'input_to_save_ms':performance['input_to_saved_turn_ms'],'errors':errors}),flush=True)
                await page.close()
            await context.close()
        await browser.close()


if __name__=='__main__': asyncio.run(main())
