"""Two-viewport real exported-Web keyboard gate using ordinary saved fixtures.

Generate with hand_shortcut_checks.gd. JS only seeds/reads localStorage; all
selection and confirmation goes through normal keyboard/mouse/touch events.
No runtime game access, debug hooks, or production backdoors.
"""
import asyncio, hashlib, io, json, os, shutil
from pathlib import Path
from PIL import Image, ImageChops
from playwright.async_api import async_playwright
from browser_event_checks import boot, KEY, variant_json

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'verification/v0.14.10/hand-shortcuts'
URL = os.environ.get('YIXING_TEST_URL', 'http://127.0.0.1:8765')


def battle(text):
    return variant_json(text.split('\nbattle=', 1)[1].rsplit('\nscreen=', 1)[0])


def gameplay(state):
    return {k: v for k, v in state.items() if k not in ('notice', 'free_selected')}


def pixels_changed(first, second):
    diff = ImageChops.difference(Image.open(io.BytesIO(first)).convert('RGB'),
                                Image.open(io.BytesIO(second)).convert('RGB'))
    return sum(max(pixel) > 20 for pixel in diff.getdata())


async def main():
    replays = json.loads((OUT / 'replays.json').read_text())
    assert len(replays) == 2 and {int(r['viewport'][0]) for r in replays} == {1280, 390}
    output = OUT / 'browser'; output.mkdir(parents=True, exist_ok=True)
    reports = []
    async with async_playwright() as p:
        exe = os.environ.get('CHROMIUM_PATH') or shutil.which('chromium')
        browser = await p.chromium.launch(**({'executable_path': exe} if exe else {}),
                                          headless=True, args=['--no-sandbox'])
        for replay in replays:
            w, h = map(int, replay['viewport']); uw, uh = replay['logical_size']
            scale = min(w / uw, h / uh); ox = (w - uw * scale) / 2; oy = (h - uh * scale) / 2
            context = await browser.new_context(viewport={'width': w, 'height': h}, has_touch=w < h)
            page = await context.new_page(); errors = []; screenshots = []
            page.on('pageerror', lambda e: errors.append(str(e)))
            page.on('console', lambda m: errors.append(m.text) if m.type == 'error' and ('SCRIPT ERROR' in m.text or 'Parse Error' in m.text) else None)
            def point(pos): return ox + pos[0] * scale, oy + pos[1] * scale
            async def click(pos):
                if w < h: await page.touchscreen.tap(*point(pos))
                else: await page.mouse.click(*point(pos)); await page.mouse.move(1, 1)
                await page.wait_for_timeout(450)
            async def snap(): return battle(await page.evaluate('(key)=>localStorage.getItem(key)', KEY))
            async def shot(label):
                path = output / f"{replay['name']}-{label}.png"
                data = await page.screenshot(path=str(path)); screenshots.append({'file': path.name, 'sha256': hashlib.sha256(data).hexdigest()})
                # Limit comparison to hand; ignore status text, board animations and HUD.
                x, y, cw, ch = replay['hand_area']
                crop = Image.open(io.BytesIO(data)).crop((int(ox+x*scale), int(oy+y*scale), int(ox+(x+cw)*scale), int(oy+(y+ch)*scale)))
                buf = io.BytesIO(); crop.save(buf, format='PNG'); return buf.getvalue()
            try:
                fixture = (OUT / 'fixtures' / replay['fixture']).read_text(); initial = battle(fixture)
                await page.add_init_script('localStorage.setItem(%s,%s)' % (json.dumps(KEY), json.dumps(fixture)))
                await page.goto(URL); await boot(page); await click(replay['resume']); await page.wait_for_timeout(1100)
                assert gameplay(await snap()) == gameplay(initial)
                baseline = await shot('dense-hand-initial')
                if w > h:
                    await page.keyboard.press('Numpad1'); await page.wait_for_timeout(1200)
                    assert (await snap())['free_selected'], 'numpad 1 must select free movement first'
                    assert gameplay(await snap()) == gameplay(initial), 'selection must not play or spend'
                    await shot('numpad-free-selected')
                    await page.keyboard.press('Numpad1'); await page.wait_for_timeout(1200)
                    assert not (await snap())['free_selected'], 'same key toggles same as click'
                    await page.keyboard.down('2'); await page.keyboard.down('2'); await page.keyboard.up('2')
                    await page.wait_for_timeout(500)
                    selected = await shot('number-life-selected')
                    assert pixels_changed(baseline, selected) > 200, 'keyboard selection must visibly raise/highlight card'
                    for combo in ['Shift+2', 'Control+2', 'Alt+2', 'Meta+2', '8', '9', '0', 'Numpad8']:
                        await page.keyboard.press(combo)
                    await page.wait_for_timeout(1100)
                    assert gameplay(await snap()) == gameplay(initial), 'modified/extra keys or repeats played a card'
                    guarded = await shot('modifier-repeat-protected')
                    assert pixels_changed(selected, guarded) < 100, 'modifier/repeat altered visible selection'
                    # Compare the actual single-click path to the actual key path.
                    await page.keyboard.press('Escape'); await page.wait_for_timeout(350)
                    await click(replay['life']); await page.wait_for_timeout(350)
                    mouse_selected = await shot('mouse-life-selected')
                    assert pixels_changed(selected, mouse_selected) < 100, 'keyboard and mouse selection differ visually'
                    await page.keyboard.press('Escape'); await page.keyboard.press('Numpad2'); await click(replay['confirm'])
                    await page.wait_for_timeout(1200)
                    after = await snap()
                    assert after['lives'] == initial['lives'] + 1 and after['hand'] == initial['hand'][1:], 'numpad selected wrong hand card'
                    assert after['energy'] == initial['energy'] - 2, 'confirmation must spend exactly the life card cost'
                    await shot('confirmed-exact-card')
                else:
                    for code in ['1', '2', '7', 'Numpad1', 'Numpad2']:
                        await page.keyboard.press(code)
                    await page.wait_for_timeout(1200)
                    assert await snap() == initial, 'mobile keyboard selected or changed persisted state'
                    mobile = await shot('mobile-no-number-selection')
                    assert pixels_changed(baseline, mobile) < 100, 'mobile keyboard changed visible selection'
                assert not errors, errors
                reports.append({'viewport': [w,h], 'screenshots': screenshots, 'errors': errors})
                print('PASS hand shortcuts', replay['name'], flush=True)
            except Exception:
                await page.screenshot(path=str(output / f"{replay['name']}-failure.png")); raise
            finally:
                await context.close()
        await browser.close()
    (output / 'results.json').write_text(json.dumps(reports, ensure_ascii=False, indent=2))
    print('HAND SHORTCUT WEB RESULT 2 viewports')

if __name__ == '__main__': asyncio.run(main())
