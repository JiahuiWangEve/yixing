"""Exercise the shipped catalog only through ordinary UI and saved preferences.

Generate descriptors with card_catalog_checks.gd. No injected gameplay hooks,
runtime state access, canvas instrumentation, or special exported test code.
Default is a desktop/phone gate; --full includes small phone and landscape.
"""
import argparse
import asyncio
import hashlib
import json
import os
from pathlib import Path
import shutil
import time

from playwright.async_api import async_playwright
from browser_chapter_checks import assert_rendered, image_difference

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'verification/v0.14.13/catalog'
URL = os.environ.get('YIXING_TEST_URL', 'http://127.0.0.1:8765')
KEY = 'yixing.route_run.v0149'


def validate_manifest(manifest):
    assert manifest['schema'] == 1
    assert manifest['groups'] == ['common', 'king', 'horse', 'artillery', 'special']
    replays = manifest['replays']
    assert [int(r['viewport'][0]) for r in replays] == [1280, 390, 360, 844]
    for replay in replays:
        assert [g['id'] for g in replay['groups']] == manifest['groups']
        assert sum(g['count'] for g in replay['groups']) == manifest['catalog_count']
        for group in replay['groups']:
            ids = [c['id'] for c in group['cards']]
            assert len(ids) == group['count'] == len(set(ids))
            assert [c['slot'] for c in group['cards']] == list(range(group['count']))
            assert all(c['name'] and 0 <= c['scroll'] <= group['scroll_limit'] for c in group['cards'])
        fixture = (OUT / 'fixtures' / replay['fixture']).read_text()
        assert '\nroute=' in fixture and '\nbattle=' in fixture
    return replays


async def main(full=False, validate_only=False):
    manifest = json.loads((OUT / 'replays.json').read_text())
    all_replays = validate_manifest(manifest)
    if validate_only:
        print('CATALOG WEB FIXTURES VALID', len(all_replays), 'viewports', manifest['catalog_count'], 'identities')
        return
    selected = [r for r in all_replays if full or r['viewport'][0] in [1280, 390]]
    output = OUT / ('browser-full' if full else 'browser-smoke')
    output.mkdir(parents=True, exist_ok=True)
    reports = []
    started = time.monotonic()
    async with async_playwright() as p:
        executable = os.environ.get('CHROMIUM_PATH') or shutil.which('chromium')
        browser = await p.chromium.launch(**({'executable_path': executable} if executable else {}), headless=True, args=['--no-sandbox'])
        for replay in selected:
            geometry = replay
            w, h = map(int, replay['viewport'])
            context = await browser.new_context(viewport={'width': w, 'height': h}, has_touch=True)
            page = await context.new_page()
            cdp = await context.new_cdp_session(page)
            errors, screenshots, visited = [], [], []
            page.on('pageerror', lambda e: errors.append(str(e)))
            page.on('console', lambda m: errors.append(m.text) if m.type == 'error' and any(s in m.text for s in ['SCRIPT ERROR', 'Parse Error']) else None)
            fixture = (OUT / 'fixtures' / replay['fixture']).read_text()
            await page.add_init_script('localStorage.setItem(%s,%s)' % (json.dumps(KEY), json.dumps(fixture)))

            def xy(pos):
                width, height = geometry['viewport']
                uw, uh = geometry['logical_size']
                scale = min(width / uw, height / uh)
                return {'x': (width - uw * scale) / 2 + pos[0] * scale,
                        'y': (height - uh * scale) / 2 + pos[1] * scale}

            async def storage():
                return await page.evaluate('Object.fromEntries(Object.entries(localStorage).sort())')

            async def stable(previous=None, changed=False, label='state'):
                # Wait for actual animation frames, then bound polling on a visible
                # transition. No fixed screenshot sleep or injected game hook.
                deadline = time.monotonic() + 12
                while time.monotonic() < deadline:
                    await page.evaluate('new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)))')
                    current = await page.screenshot()
                    assert_rendered(current, geometry['viewport'])
                    different = previous is None or image_difference(previous, current) > .10
                    if not changed or different:
                        return current
                    await asyncio.sleep(.06)
                raise AssertionError(('Visible state did not settle/change', label))

            async def tap(pos, previous=None, changed=True, label='tap'):
                pt = xy(pos)
                if replay['viewport'][0] == 1280:
                    await page.mouse.click(pt['x'], pt['y'])
                else:
                    await page.touchscreen.tap(pt['x'], pt['y'])
                return await stable(previous, changed and previous is not None, label)

            async def shot(label, data=None):
                data = data or await stable(label=label)
                path = output / f"{replay['name']}-{label}.png"
                path.write_bytes(data)
                screenshots.append({'file': path.name, 'sha256': hashlib.sha256(data).hexdigest()})
                return data

            async def drag(grid, delta, cancel=False):
                x, y, width, height = grid
                a = [x + width * .5, y + height * .8 if delta >= 0 else y + height * .2]
                b = [a[0], a[1] - delta]
                pa, pb = xy(a), xy(b)
                await cdp.send('Input.dispatchTouchEvent', {'type': 'touchStart', 'touchPoints': [{**pa, 'id': 1}]})
                for fraction in [.25, .5, .75, 1]:
                    pt = {axis: pa[axis] + (pb[axis] - pa[axis]) * fraction for axis in ['x', 'y']}
                    await cdp.send('Input.dispatchTouchEvent', {'type': 'touchMove', 'touchPoints': [{**pt, 'id': 1}]})
                    await asyncio.sleep(.02)
                await cdp.send('Input.dispatchTouchEvent', {'type': 'touchCancel' if cancel else 'touchEnd', 'touchPoints': []})
                return await stable(label='scroll')

            async def scroll_to(group, current, desired):
                limit = max(24, group['grid'][3] * .55)
                while abs(desired - current) > .5:
                    delta = max(-limit, min(limit, desired - current))
                    await drag(group['grid'], delta)
                    current = max(0, min(group['scroll_limit'], current + delta))
                return current

            try:
                await page.goto(URL)
                await page.wait_for_function("!document.getElementById('status')", timeout=60000)
                home = await stable(label='home')
                initial = await storage()
                assert initial.get(KEY) == fixture, 'Boot must retain the existing expedition'
                role = await tap(replay['start'], home, label='role chooser')
                await shot('role-chooser', role)
                grid = await tap(replay['open'], role, label='catalog opens')
                await shot('catalog-common', grid)
                for group in replay['groups']:
                    grid = await tap(group['tab'], grid, changed=group['id'] != 'common', label=group['id'])
                    current_scroll = 0.0
                    await shot(group['id'] + '-grid', grid)
                    chosen_cards = group['cards'] if full else [c for c in group['cards'] if c['id'] in {'sword', 'airdrop', 'last_stand', 'chain_assault', 'reload', 'fatigue', '__free_artillery_attack'}]
                    if not chosen_cards:
                        chosen_cards = group['cards'][-1:]
                    for card_number, card in enumerate(chosen_cards):
                        current_scroll = await scroll_to(group, current_scroll, card['scroll'])
                        grid = await page.screenshot()
                        detail = await tap(card['tap'], grid, label=card['id'] + ' full face')
                        await shot(group['id'] + '-' + card['id'] + '-base', detail)
                        for shortcut in (['1', '2', '3', '4', '5', '6', '7', 'Space', 'Enter'] if card_number == 0 else []):
                            await page.keyboard.press(shortcut)
                        unchanged = await stable(label='isolated shortcuts')
                        assert image_difference(detail, unchanged) < .10, ('Shortcut leaked into UI', card['id'])
                        if card['upgrade_id']:
                            upgraded = await tap(card['variant'], detail, label='upgrade variant')
                            await shot(group['id'] + '-' + card['upgrade_id'], upgraded)
                            detail = await tap(card['variant'], upgraded, label='base restored')
                        if card['detail_scroll_limit'] > 0:
                            # Actual swipe within the focused face exposes its final effect line.
                            area = card['detail']
                            remain = card['detail_scroll_limit']
                            while remain > .5:
                                delta = min(remain, max(24, area[3] * .55))
                                await drag(area, delta)
                                remain -= delta
                            await shot(group['id'] + '-' + card['id'] + '-effect-bottom')
                        assert await storage() == initial, ('Catalog mutated saved state/preferences', card['id'])
                        visited.append({'group': group['id'], 'id': card['id'], 'upgrade': card['upgrade_id']})
                        grid = await tap(card['back'], detail, label='back to same grid')
                    assert len([v for v in visited if v['group'] == group['id']]) == len(chosen_cards)
                    # A real touch-cancel on a card must not open detail.
                    before = await stable()
                    pt = xy(group['cards'][-1]['tap'])
                    await cdp.send('Input.dispatchTouchEvent', {'type': 'touchStart', 'touchPoints': [{**pt, 'id': 1}]})
                    await cdp.send('Input.dispatchTouchEvent', {'type': 'touchCancel', 'touchPoints': []})
                    after = await stable()
                    assert image_difference(before, after) < .10, 'Canceled touch opened a card'
                assert len(visited) == manifest['catalog_count'] if full else len(visited) >= len(manifest['groups'])
                # Rotate while focused, then Escape must return to role selection.
                last = replay['groups'][-1]['cards'][-1]
                focused = await tap(last['tap'], after, label='focus before rotation')
                alternate = next(r for r in all_replays if r['viewport'][0] == (390 if w == 844 else 844))
                geometry = alternate
                await page.set_viewport_size(dict(zip(['width', 'height'], map(int, alternate['viewport']))))
                await shot('rotated-detail')
                await page.keyboard.press('Escape')
                role = await stable(label='Escape closes catalog')
                await shot('rotated-role', role)
                grid = await tap(alternate['open'], role, label='reopen after rotation')
                role = await tap(alternate['cancel'], grid, label='catalog back')
                grid = await tap(alternate['open'], role, label='repeat catalog open')
                await page.keyboard.press('Escape')
                role = await stable(grid, changed=True, label='repeat Escape')
                assert await storage() == initial, 'Repeated/rotated viewing changed save/settings'
                home = await tap(alternate['role_back'], role, label='return home')
                resumed = await tap(alternate['resume'], home, label='resume existing expedition')
                await shot('resumed-existing-expedition', resumed)
                assert await storage() == initial, 'Catalog replaced or rewrote existing expedition'
                assert not errors, errors
                reports.append({'name': replay['name'], 'viewport': replay['viewport'], 'visited': visited, 'expected_catalog_identities': manifest['catalog_count'],
                                'screenshots': screenshots, 'saved_state_unchanged': True, 'errors': errors})
                print('PASS CATALOG WEB', replay['name'], len(visited), 'identities', flush=True)
            except Exception:
                await page.screenshot(path=str(output / f"{replay['name']}-failure.png"))
                raise
            finally:
                await cdp.detach()
                await context.close()
        await browser.close()
    result = {'replays': len(reports), 'catalog_count': manifest['catalog_count'],
              'elapsed_seconds': round(time.monotonic() - started, 2), 'cases': reports}
    (output / 'results.json').write_text(json.dumps(result, ensure_ascii=False, indent=2))
    print('CATALOG WEB RESULT', len(reports), 'viewports')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--full', action='store_true')
    parser.add_argument('--validate-only', action='store_true')
    args = parser.parse_args()
    asyncio.run(main(args.full, args.validate_only))
