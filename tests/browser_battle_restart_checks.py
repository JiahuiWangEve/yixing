"""Restart the current battle through real exported-Web UI at 1280 and 390.

Starts an ordinary, non-debug expedition through the home menu. JavaScript only
reads production localStorage, except for the explicit legacy-save case, which
removes battle_start from a save produced by those same real UI actions. No game
API, QA endpoint, fixture generator, or runtime state injection is used.

Run against build/web on port 8765, or set YIXING_TEST_URL. CHROMIUM_PATH may
select the CI browser. Screenshots and complete observed saves accompany results.
"""
import asyncio
import copy
import hashlib
import json
import os
import re
import shutil
import time
from pathlib import Path

from playwright.async_api import async_playwright

from browser_chapter_checks import assert_rendered
from browser_event_checks import KEY, boot, parse, variant_json
from browser_map_checks import RouteGeometry, saved_route

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'verification/v0.15.4/battle-restart/browser'
URL = os.environ.get('YIXING_TEST_URL', 'http://127.0.0.1:8765')
VIEWPORTS = [(1280, 940), (390, 844)]


def field_match(text, name):
    # ConfigFile writes top-level keys at column zero. Nested Variant dictionary
    # members are quoted, so this also handles multiline checkpoint dictionaries.
    return re.search(r'^' + re.escape(name) + r'=(.*?)(?=^[A-Za-z_]\w*=|\Z)',
                     text, re.M | re.S)


def field(text, name, default=None):
    match = field_match(text, name)
    return default if match is None else variant_json(match.group(1).strip())


def without_checkpoint(text):
    match = field_match(text, 'battle_start')
    assert match is not None, 'New production save has no entry checkpoint key'
    result = text[:match.start()] + text[match.end():]
    assert field(result, 'battle_start') is None
    return result


def decode(text):
    if not text:
        return None
    # Keep exercising the existing production-save helpers. battle_start is an
    # optional run key after screen, not embedded in the battle dictionary.
    return {'summary': parse(text), 'route': saved_route(text),
            'battle': field(text, 'battle'),
            'checkpoint': field(text, 'battle_start', {}),
            'budget': field(text, 'normal_undos_remaining'), 'raw': text}


def gameplay(battle, ignore_notice=False):
    result = copy.deepcopy(battle)
    # Only elapsed presentation and rendered piece positions are volatile.
    # In particular, retain exact RNG integers, ordered cards/UIDs, HP, effects,
    # role, encounter counters, collection, logs and per-battle treasure state.
    result.pop('initial_threat', None)
    for enemy in result['enemies']:
        enemy.pop('visual', None)
    if ignore_notice:
        result.pop('notice', None)
    return result


def same_run(actual, expected):
    return (actual['summary']['screen'] == 'game' and
            actual['route'] == expected['route'] and
            actual['budget'] == expected['budget'] and
            actual['checkpoint'] == expected['checkpoint'])


async def main():
    OUT.mkdir(parents=True, exist_ok=True)
    reports = []
    async with async_playwright() as p:
        executable = os.environ.get('CHROMIUM_PATH') or shutil.which('chromium')
        browser = await p.chromium.launch(
            **({'executable_path': executable} if executable else {}),
            headless=True, args=['--no-sandbox'])
        try:
            for width, height in VIEWPORTS:
                desktop = width == 1280
                uw, uh = (1280, 940) if desktop else (480, max(660, 480 * height / width))
                scale = min(width / uw, height / uh)
                ox, oy = (width - uw * scale) / 2, (height - uh * scale) / 2
                cell = 48 if desktop else min(44, max(24, (uh - 450) / 9))
                origin = (448, 105) if desktop else (240 - cell * 4, 135)
                restart = (838, 40) if desktop else (159, 35)
                undo = (1130, 40) if desktop else (394, 35)
                menu_top, menu_step = (180, 72) if desktop else (max(150, uh * .25), 74)
                context = await browser.new_context(
                    viewport={'width': width, 'height': height}, has_touch=not desktop)
                page = await context.new_page()
                errors, checks, screenshots, observations = [], [], [], []
                page.on('pageerror', lambda error: errors.append(str(error)))
                page.on('console', lambda msg: errors.append(msg.text)
                        if msg.type == 'error' and
                        ('SCRIPT ERROR' in msg.text or 'Parse Error' in msg.text) else None)

                def menu(index):
                    return (640 if desktop else 240,
                            menu_top + (29 if desktop else 30) + menu_step * index)

                async def painted():
                    await asyncio.wait_for(page.evaluate('''() => new Promise(resolve =>
                        requestAnimationFrame(() => requestAnimationFrame(resolve)))'''), 8)

                async def tap(point):
                    x, y = ox + point[0] * scale, oy + point[1] * scale
                    assert 0 <= x < width and 0 <= y < height, ('Offscreen tap', point)
                    if desktop:
                        await page.mouse.click(x, y)
                        await page.mouse.move(1, 1)
                    else:
                        await page.touchscreen.tap(x, y)
                    await painted()

                async def snapshot():
                    return decode(await page.evaluate('(key) => localStorage.getItem(key)', KEY))

                async def expect(label, predicate, timeout=15):
                    started = time.monotonic()
                    actual = None
                    while time.monotonic() - started < timeout:
                        actual = await snapshot()
                        if actual is not None and predicate(actual):
                            observations.append({'label': label,
                                                 'wait_ms': round((time.monotonic() - started) * 1000),
                                                 'turn': actual['battle']['turn'],
                                                 'budget': actual['budget']})
                            return actual
                        await asyncio.sleep(.08)
                    if actual:
                        (OUT / f'{width}-timeout-{label}.cfg').write_text(actual['raw'])
                    raise AssertionError((width, label, 'Expected production save did not arrive', actual))

                async def shot(label, state=None):
                    path = OUT / f'{width}-{label}.png'
                    data = await page.screenshot(path=str(path))
                    assert_rendered(data, [width, height])
                    screenshots.append({'file': path.name, 'sha256': hashlib.sha256(data).hexdigest()})
                    if state is None:
                        state = await snapshot()
                    if state:
                        (OUT / f'{width}-{label}.cfg').write_text(state['raw'])

                async def next_turn(before, label):
                    assert before['battle']['phase'] == 'play', (label, before['battle']['phase'])
                    await page.keyboard.press('Space')
                    return await expect(label, lambda s: s['summary']['screen'] == 'game' and
                                        s['battle']['turn'] == before['battle']['turn'] + 1)

                async def move_forward(label):
                    await tap((origin[0] + cell * 4, origin[1] + cell * 8))
                    return await expect(label, lambda s: s['summary']['screen'] == 'game' and
                                        s['battle']['player'] == [4, 8] and s['battle']['basic_used'] and
                                        len(s['battle']['hand']) == 1)

                async def restarted(expected, label):
                    await tap(restart)
                    # restart saves synchronously while its 0.25-second lock is
                    # active. A later threat-timer save proves that lock expired;
                    # do not immediately test Undo against a still-locked button.
                    entry_threat = expected['checkpoint']['state']['initial_threat']
                    return await expect(label, lambda s: same_run(s, expected) and
                                        gameplay(s['battle']) == gameplay(expected['battle']) and
                                        s['battle']['initial_threat'] < entry_threat)

                async def observe_no_undo(expected, label):
                    # Negative input checks must outlast the one-second autosave
                    # cadence, not pass immediately against a stale saved value.
                    deadline = time.monotonic() + 1.3
                    samples = 0
                    while time.monotonic() < deadline:
                        actual = await snapshot()
                        assert actual and same_run(actual, expected), (label, actual)
                        assert gameplay(actual['battle']) == gameplay(expected['battle']), (label, actual)
                        samples += 1
                        await asyncio.sleep(.08)
                    observations.append({'label': label, 'unchanged_samples': samples,
                                         'window_seconds': 1.3})

                try:
                    await page.goto(URL)
                    await boot(page)
                    assert await snapshot() is None, 'New browser context unexpectedly has a saved run'
                    await tap(menu(0))  # Start game, not debug mode or tutorial.
                    await tap(menu(0))  # Default king role.
                    map_state = await expect('new-expedition-map', lambda s:
                                             s['summary']['screen'] == 'map' and
                                             s['route']['current'] == s['route']['pending'] == -1)
                    geometry = RouteGeometry(map_state['route'], width, height)
                    assert map_state['route']['nodes'][0]['kind'] == 'battle' and geometry.visible(0)
                    await tap(geometry.node(0))
                    entry = await expect('saved-entry-checkpoint', lambda s:
                                         s['summary']['screen'] == 'game' and
                                         s['route']['current'] == -1 and s['route']['pending'] == 0 and
                                         s['battle']['turn'] == 1 and bool(s['checkpoint'].get('state')))
                    assert entry['budget'] == 3
                    assert gameplay(entry['checkpoint']['state']) == gameplay(entry['battle'])
                    assert entry['checkpoint']['identity']['pending'] == 0
                    await shot('initial', entry)
                    checks.append('A real new expedition saves the battle-entry checkpoint before the first action')

                    moved = await move_forward('first-real-move')
                    assert moved['battle']['hand'] == [entry['battle']['deck'][-1]]
                    assert moved['battle']['deck'] == entry['battle']['deck'][:-1]
                    first_turn = await next_turn(moved, 'first-space-turn')
                    await tap(undo)
                    undone = await expect('spent-undo', lambda s: s['budget'] == 2 and
                                          gameplay(s['battle']) == gameplay(moved['battle']))
                    changed = await next_turn(undone, 'replay-space-after-undo')
                    assert gameplay(changed['battle']) == gameplay(first_turn['battle'])
                    # The real opening has three pawns. Standing on file four
                    # eventually takes a hit, advancing combat RNG via AI/recoil.
                    # Require actual HP/RNG/enemy changes, not vacuous equality
                    # of values which never changed before pressing Restart.
                    if desktop:
                        for index in range(32):
                            if changed['battle']['lives'] < entry['battle']['lives']:
                                break
                            changed = await next_turn(changed, f'wait-for-real-hit-{index}')
                        assert 0 < changed['battle']['lives'] < entry['battle']['lives'], 'Opening never inflicted a real hit'
                    else:
                        # The two-viewport release gate repeats core restart,
                        # refresh and quota coverage, not the long damage walk.
                        changed = await next_turn(changed, 'mobile-enemy-movement')
                    if desktop:
                        assert changed['battle']['rng_state'] != entry['battle']['rng_state'], 'Combat RNG was not exercised'
                    assert gameplay(changed['battle'])['enemies'] != gameplay(entry['battle'])['enemies']
                    assert changed['battle']['hand'] != entry['battle']['hand']
                    assert changed['route'] == entry['route']
                    assert changed['checkpoint'] == entry['checkpoint'], 'Entry checkpoint mutated with play/undo'
                    assert changed['battle']['collection'] == entry['battle']['collection']
                    assert changed['budget'] == 2
                    await shot('after-actions', changed)
                    checks.append('Move, Space and a paid undo change cards, enemies and RNG' +
                                  ('; real enemy damage also changes HP' if desktop else ''))

                    expected = copy.deepcopy(entry)
                    expected['budget'] = 2
                    restored = await restarted(expected, 'restart-restores-entry')
                    await shot('after-restart', restored)
                    checks.append('Restart restores all entry battle fields and RNG without changing route, treasure or used undo allowance')
                    await tap(undo)
                    await observe_no_undo(expected, 'empty-history-button')
                    await page.keyboard.press('Control+z')
                    await observe_no_undo(expected, 'empty-history-keyboard')
                    checks.append('Restart clears history: neither button nor Ctrl+Z can restore an old action or spend another undo')

                    replay_move = await move_forward('replayed-move')
                    assert gameplay(replay_move['battle']) == gameplay(moved['battle']), 'Restart changed the next drawn card or card IDs'
                    replay_turn = await next_turn(replay_move, 'replayed-space')
                    assert gameplay(replay_turn['battle']) == gameplay(first_turn['battle']), 'Restart changed identical replay results'
                    assert replay_turn['budget'] == 2
                    checks.append('The same real move and Space replay exactly, including card order, IDs and enemy/RNG outcome')

                    await page.reload()
                    await boot(page)
                    await tap(menu(3))
                    # A new persisted turn proves Continue really resumed; an
                    # unchanged localStorage value alone cannot prove that UI.
                    resumed = await next_turn(replay_turn, 'reload-continue-space')
                    assert resumed['route'] == entry['route'] and resumed['checkpoint'] == entry['checkpoint']
                    assert resumed['budget'] == 2
                    restored = await restarted(expected, 'restart-after-refresh')
                    await shot('after-refresh-restart', restored)
                    checks.append('Refresh and Continue retain the original checkpoint and can restart the same battle')

                    legacy = without_checkpoint(changed['raw'])
                    assert field(legacy, 'route') == changed['route']
                    assert field(legacy, 'battle') == changed['battle']
                    await page.evaluate('([key, value]) => localStorage.setItem(key, value)', [KEY, legacy])
                    await page.reload()
                    await boot(page)
                    await tap(menu(3))
                    legacy_before = await next_turn(changed, 'legacy-continues-normally')
                    assert not legacy_before['checkpoint'], 'Legacy save manufactured an entry checkpoint'
                    await tap(restart)
                    legacy_after = await expect('legacy-restart-unavailable', lambda s:
                                                '旧战斗无开场记录' in s['battle']['notice'])
                    assert legacy_after['summary']['screen'] == 'game'
                    assert legacy_after['route'] == legacy_before['route']
                    assert legacy_after['budget'] == legacy_before['budget'] == 2
                    assert not legacy_after['checkpoint']
                    assert gameplay(legacy_after['battle'], True) == gameplay(legacy_before['battle'], True)
                    assert await page.evaluate('(key) => Boolean(localStorage.getItem(key))', KEY)
                    await shot('legacy-no-reset', legacy_after)
                    checks.append('A real save missing battle_start remains playable; Restart only explains unavailability and never resets or clears it')
                    assert not errors, errors
                    reports.append({'viewport': [width, height], 'input': 'mouse' if desktop else 'touch',
                                    'route_seed': entry['route']['seed'], 'changed_turn': changed['battle']['turn'],
                                    'hp_changed': changed['battle']['lives'] < entry['battle']['lives'],
                                    'assertions': checks, 'screenshots': screenshots,
                                    'observations': observations, 'errors': errors})
                    (OUT / 'results.json').write_text(json.dumps(reports, ensure_ascii=False, indent=2))
                    print('PASS battle restart Web', width, len(checks), 'checks', flush=True)
                except Exception:
                    await shot('failure')
                    (OUT / f'{width}-failure-observations.json').write_text(json.dumps(
                        {'assertions': checks, 'observations': observations, 'errors': errors},
                        ensure_ascii=False, indent=2))
                    raise
                finally:
                    await context.close()
        finally:
            await browser.close()
    assert {tuple(report['viewport']) for report in reports} == set(VIEWPORTS)
    print(json.dumps({'viewports': len(reports), 'checks': sum(len(r['assertions']) for r in reports),
                      'screenshots': sum(len(r['screenshots']) for r in reports), 'errors': 0}))


if __name__ == '__main__':
    asyncio.run(main())
