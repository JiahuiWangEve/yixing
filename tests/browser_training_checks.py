"""Fast real-Web training gate: three viewports, ordinary UI and save files only.

Generate tests/training_visual_fixtures.gd first. The browser never evaluates a
Godot object or installs a gameplay hook. It reads production localStorage,
including complete snapshots created by the actual '另存局面' button. Run against
an already authorized CI server via YIXING_TEST_URL. This script starts no server.
--validate-only does not launch a browser or make any network requests.
--full adds real undo/restart state checks after the critical smoke path.
"""
import argparse
import asyncio
import base64
import hashlib
import io
import json
import os
from pathlib import Path
import shutil
import struct
import time

from PIL import Image, ImageChops, ImageStat
from playwright.async_api import async_playwright

from browser_chapter_checks import assert_rendered
from browser_enemy_impact_checks import state as formal_state

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'verification/v0.16.0/training'
URL = os.environ.get('YIXING_TEST_URL', 'http://127.0.0.1:8765')
TRAINING_KEY = 'yixing.training.presets.v1'
FORMAL_KEY = 'yixing.route_run.v0149'
VIEWPORTS = {(1280, 940), (390, 844), (844, 390)}
OMITTED_FIELDS = ['initial_threat', 'notice', 'enemies[*].visual']


class VariantReader:
    """Read Godot's safe var_to_bytes data, never objects or executable values.

    Integer RNG states remain Python int, with no JavaScript-number round-trip.
    Unknown or object-bearing encodings fail rather than silently skipping data.
    """
    def __init__(self, data):
        self.data = data
        self.offset = 0

    def unpack(self, fmt):
        size = struct.calcsize('<' + fmt)
        assert self.offset + size <= len(self.data), 'Truncated Godot Variant'
        values = struct.unpack_from('<' + fmt, self.data, self.offset)
        self.offset += size
        return values[0] if len(values) == 1 else list(values)

    def string(self):
        size = self.unpack('I')
        assert size <= 4_194_304 and self.offset + size <= len(self.data)
        result = self.data[self.offset:self.offset + size].decode('utf-8')
        self.offset += (size + 3) & ~3
        return result

    def value(self, depth=0):
        assert depth < 64, 'Excessively nested production save'
        header = self.unpack('I'); kind = header & 0xff
        wide = bool(header & (1 << 16))
        if kind == 0: return None
        if kind == 1: return bool(self.unpack('I'))
        if kind == 2: return self.unpack('q' if wide else 'i')
        if kind == 3: return self.unpack('d' if wide else 'f')
        if kind in (4, 21): return self.string()
        if kind == 5: return self.unpack('dd' if wide else 'ff')
        if kind == 6: return self.unpack('ii')
        if kind == 7: return self.unpack('dddd' if wide else 'ffff')
        if kind == 8: return self.unpack('iiii')
        if kind in (27, 28):
            assert header >> 16 == 0, ('Unexpected typed container', header)
            size = self.unpack('I') & 0x7fffffff
            assert size < 100_000
            if kind == 28: return [self.value(depth + 1) for _ in range(size)]
            result = {}
            for _ in range(size):
                key = self.value(depth + 1)
                assert isinstance(key, (str, int, float, bool)), 'Unsupported dictionary key'
                result[key] = self.value(depth + 1)
            return result
        raise AssertionError(('Unsupported safe Godot Variant kind', kind, header, self.offset))


def decode(encoded):
    assert isinstance(encoded, str) and encoded, 'Missing training production save'
    reader = VariantReader(base64.b64decode(encoded, validate=True))
    result = reader.value()
    assert reader.offset == len(reader.data), ('Unconsumed bytes', reader.offset, len(reader.data))
    assert result['version'] == 1 and isinstance(result['presets'], list)
    return result


def normalize(snapshot):
    snapshot = json.loads(json.dumps(snapshot))
    snapshot.pop('initial_threat', None); snapshot.pop('notice', None)
    for enemy in snapshot['enemies']: enemy.pop('visual', None)
    return snapshot


def fixture(name):
    return (OUT / 'fixtures' / name).read_text()


def validate():
    manifest = json.loads((OUT / 'replays.json').read_text())
    assert manifest['schema'] == 1 and manifest['failures'] == 0
    assert manifest['formal_key'] == FORMAL_KEY and manifest['training_key'] == TRAINING_KEY
    replays = manifest['replays']
    assert len(replays) == 3 and {tuple(r['viewport']) for r in replays} == VIEWPORTS
    for r in replays:
        envelope = decode(fixture(r['presets']))
        assert envelope == json.loads(fixture(r['presets_json'])), 'Binary decoder differs from native source'
        assert len(envelope['presets']) == 1 and envelope['recent_id'] == r['preset_id']
        preset = envelope['presets'][0]['data']
        assert preset['player'] == [4, 5] and preset['hand'] == ['grappling_hook']
        assert preset['treasure_ids'] == ['longevity_seal', 'life_talisman', 'tiger_tally', 'decoy_tally']
        assert {e.get('ai_role') for e in preset['enemies']} >= {'outrider', 'guard_horse'}
        saved = formal_state(fixture(r['formal']))
        assert saved['screen'] == 'game' and saved['battle']['phase'] == 'play'
        start, decoy, hook = (r['expected'][key] for key in ('initial', 'after_decoy', 'after_hook'))
        assert start['hand'] == ['grappling_hook', 'decoy_card'] and start['energy'] == 3
        assert decoy['hand'] == ['grappling_hook'] and decoy['energy'] == 3
        object_ = next(e for e in decoy['enemies'] if e['kind'] == 'decoy')
        assert object_['pos'] == [6, 3] and object_['hp'] == object_['max_hp'] == 2
        assert hook['player'] == [5, 4] and hook['energy'] == 2 and not hook['hand']
        assert hook['active_displacements'] == 1 and hook['deck'] == start['deck'] == ['sword']
        assert hook['treasure_battle']['tiger_moves'] == 1
        samples = decode(fixture(r['snapshot_samples']))
        assert samples == json.loads(fixture(r['snapshot_samples_json'])), 'Full snapshot binary decoder differs from native source'
        assert len(samples['presets']) == 4
        assert [normalize(entry['data']['snapshot']) for entry in samples['presets'][1:]] == [start, decoy, hook]
        uw, uh = r['logical_size']
        for point in [r['home_entry'], r['resume'], *r['editor']['tabs']] + [r['editor'][key] for key in
                ('recent', 'presets', 'save', 'play', 'home', 'close', 'rename', 'name_input', 'name_confirm')] + [r['battle'][key] for key in
                ('save', 'return', 'undo', 'restart', 'decoy_card', 'target', 'origin', 'landing', 'hook_card')]:
            assert 0 <= point[0] < uw and 0 <= point[1] < uh, (r['stem'], point)
        assert len(r['battle']['treasures']) == 4
        for x, y, w, h in r['battle']['treasures']:
            assert w >= 44 and h >= 44 and 0 <= x < x + w <= uw and 0 <= y < y + h <= uh
    return replays


class Geometry:
    def __init__(self, replay):
        w, h = replay['viewport']; uw, uh = replay['logical_size']
        self.scale = min(w / uw, h / uh)
        self.offset = ((w - uw * self.scale) / 2, (h - uh * self.scale) / 2)

    def point(self, value):
        return tuple(self.offset[i] + value[i] * self.scale for i in range(2))

    def box(self, value):
        x, y, w, h = value
        return tuple(map(round, (*self.point((x, y)), *self.point((x + w, y + h)))))


def difference(before, after, box=None):
    a = Image.open(io.BytesIO(before)).convert('RGB')
    b = Image.open(io.BytesIO(after)).convert('RGB')
    if box:
        a, b = a.crop(box), b.crop(box)
    return sum(ImageStat.Stat(ImageChops.difference(a, b)).mean) / 3


def board_present(data, geometry, rect):
    x, y, _, _ = rect
    sample = Image.open(io.BytesIO(data)).convert('RGB').crop(geometry.box((x + 6, y + 6, 7, 7)))
    pixels = list(sample.getdata())
    return sum(max(abs(p[i] - (210, 184, 140)[i]) for i in range(3)) <= 12
               for p in pixels) / max(1, len(pixels)) > .7


async def main(validate_only=False, full=False):
    replays = validate()
    if validate_only:
        print(json.dumps({'validated_replays': len(replays), 'viewports': sorted(VIEWPORTS),
                          'rendered': False, 'omitted_snapshot_fields': OMITTED_FIELDS,
                          'manifest_sha256': hashlib.sha256((OUT / 'replays.json').read_bytes()).hexdigest()}))
        return
    output = OUT / ('browser-full' if full else 'browser'); output.mkdir(parents=True, exist_ok=True)
    reports = []; started = time.monotonic()
    async with async_playwright() as p:
        executable = os.environ.get('CHROMIUM_PATH') or shutil.which('chromium')
        browser = await p.chromium.launch(**({'executable_path': executable} if executable else {}),
                                          headless=True, args=['--no-sandbox'])
        try:
            for r in replays:
                w, h = r['viewport']; geometry = Geometry(r)
                context = await browser.new_context(viewport={'width': w, 'height': h}, has_touch=True)
                page = await context.new_page(); errors = []; shots = []; assertions = []
                page.on('pageerror', lambda error: errors.append(str(error)))
                page.on('console', lambda message: errors.append(message.text) if message.type == 'error' and
                        ('SCRIPT ERROR' in message.text or 'Parse Error' in message.text) else None)
                stem = r['stem']; original = fixture(r['formal']); original_presets = decode(fixture(r['presets']))

                async def raw(key=TRAINING_KEY):
                    return await page.evaluate('(key) => localStorage.getItem(key)', key)

                async def isolation(label):
                    assert await raw(FORMAL_KEY) == original, (stem, label, 'Formal run save changed')
                    assertions.append(label + ': formal save unchanged byte-for-byte')

                async def tap(point):
                    x, y = geometry.point(point)
                    if w == 1280: await page.mouse.click(x, y)
                    else: await page.touchscreen.tap(x, y)

                async def frames():
                    await page.evaluate('() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)))')

                async def wait_image(predicate, label, timeout=12):
                    deadline = time.monotonic() + timeout
                    while True:
                        data = await page.screenshot()
                        if predicate(data): return data
                        assert time.monotonic() < deadline, (stem, label)
                        await asyncio.sleep(.04)

                async def settled(label, minimum=.18, timeout=10):
                    # Wait for an observed stable canvas, not a fixed animation delay.
                    deadline = time.monotonic() + timeout; since = None; previous = await page.screenshot()
                    while True:
                        await frames(); data = await page.screenshot()
                        if difference(previous, data) < .035:
                            since = since or time.monotonic()
                            if time.monotonic() - since >= minimum: return data
                        else: since = None
                        previous = data
                        assert time.monotonic() < deadline, (stem, label, 'Canvas never stabilized')

                async def shot(label, data=None):
                    data = data or await page.screenshot()
                    assert_rendered(data, r['viewport'])
                    name = f'{stem}-{label}.png'; (output / name).write_bytes(data); shots.append(name)
                    return data

                async def expect_saved(predicate, label, timeout=12):
                    deadline = time.monotonic() + timeout; observed = None
                    while True:
                        encoded = await raw()
                        if encoded:
                            observed = decode(encoded)
                            if predicate(observed): return observed
                        assert time.monotonic() < deadline, (stem, label, observed)
                        await asyncio.sleep(.035)

                async def save_snapshot(expected, label):
                    await settled(label + '-settle')
                    before = decode(await raw()); count = len(before['presets'])
                    print('SNAPSHOT BEFORE', stem, label, count, [e['id'] for e in before['presets']], flush=True)
                    await tap(r['battle']['save'])
                    saved = await expect_saved(lambda value: len(value['presets']) == count + 1, label + '-saved')
                    actual = normalize(saved['presets'][-1]['data']['snapshot'])
                    assert actual == expected, (stem, label, actual, expected)
                    await isolation(label)
                    assertions.append(label + ': exact gameplay/RNG/card IDs/treasure counters')
                    # The save action has a short debounce; state must remain saved
                    # and the canvas stable before the next genuine interaction.
                    await settled(label + '-ready', minimum=.30)
                    return saved

                async def restore_formal_home():
                    nonlocal original
                    # Load the real formal run into memory before opening training;
                    # merely seeding localStorage would miss route-active failures.
                    await tap(r['resume'])
                    await wait_image(lambda data: board_present(data, geometry, r['battle']['board']), 'Formal Continue did not render')
                    await tap(r['battle']['return'])
                    await wait_image(lambda data: not board_present(data, geometry, r['battle']['board']), 'Formal Home did not render')
                    observed = await raw(FORMAL_KEY)
                    assert formal_state(observed) == formal_state(fixture(r['formal'])), 'Explicit Continue/Home changed formal gameplay'
                    # Ordinary Home saves live render interpolation. Freeze that
                    # authentic save as the byte-for-byte training isolation baseline.
                    original = observed
                    assertions.append('Formal run resumed and retained in memory before training')

                async def open_editor():
                    await tap(r['home_entry'])
                    await wait_image(lambda data: board_present(data, geometry, r['editor']['board']), 'Editor board did not render')
                    await tap(r['editor']['recent'])
                    return await settled('Load recent preset')

                try:
                    await page.add_init_script('''if (!sessionStorage.getItem('training-gate-seeded')) {
                        localStorage.setItem(%s,%s); localStorage.setItem(%s,%s);
                        localStorage.setItem('yixing.settings.v1','[settings]\\n\\ndebug_mode=false\\n');
                        sessionStorage.setItem('training-gate-seeded','1');
                    }''' % (json.dumps(FORMAL_KEY), json.dumps(original), json.dumps(TRAINING_KEY), json.dumps(fixture(r['presets']))))
                    await page.add_init_script('''window.trainingStorageWrites = [];
                        const originalSetItem = Storage.prototype.setItem;
                        Storage.prototype.setItem = function(key, value) {
                            const result = originalSetItem.call(this, key, value);
                            if (key === 'yixing.training.presets.v1') window.trainingStorageWrites.push({time: performance.now(), value});
                            return result;
                        };''')
                    await page.goto(URL)
                    await page.wait_for_function("!document.getElementById('status')", timeout=60000); await frames()
                    await restore_formal_home()
                    await shot('editor', await open_editor())
                    # Rename through the native LineEdit using genuine key events.
                    await tap(r['editor']['presets']); await frames(); await tap(r['editor']['rename']); await frames()
                    await tap(r['editor']['name_input']); await page.keyboard.press('Control+A')
                    await page.keyboard.type(r['saved_name']); await tap(r['editor']['name_confirm'])
                    await expect_saved(lambda value: any(e['id'] == r['preset_id'] and e['data']['name'] == r['saved_name'] for e in value['presets']), 'Native name input/save')
                    await shot('named-save'); await isolation('Name save')
                    await page.reload()
                    await page.wait_for_function("!document.getElementById('status')", timeout=60000); await frames()
                    await restore_formal_home()
                    await shot('reloaded-editor', await open_editor())
                    # An ordinary save after loading must retain the typed name and
                    # every fixture field, proving the loaded editor was not blank.
                    await tap(r['editor']['save'])
                    expected_preset = original_presets['presets'][0]['data'].copy(); expected_preset['name'] = r['saved_name']
                    await expect_saved(lambda value: next(e['data'] for e in value['presets'] if e['id'] == r['preset_id']) == expected_preset, 'Refresh restores exact named preset')
                    assertions.append('Native name entry, save, refresh and exact preset reload')
                    for tab in (1, 2, 3, 0):
                        before = await page.screenshot(); await tap(r['editor']['tabs'][tab])
                        area = None if r['editor']['portrait'] else geometry.box(r['editor']['panel'])
                        data = await wait_image(lambda data: difference(before, data, area) > .35, f'Editor tab {tab} did not change')
                        await shot('tab-' + str(tab), data)
                        if r['editor']['portrait']:
                            await tap(r['editor']['close'])
                            await wait_image(lambda data: board_present(data, geometry, r['editor']['board']), 'Drawer did not return to editor')
                    await isolation('All four editor tabs')
                    await tap(r['editor']['play'])
                    await wait_image(lambda data: board_present(data, geometry, r['battle']['board']), 'Trial board did not render')
                    await save_snapshot(r['expected']['initial'], 'Trial entry')
                    await shot('trial-four-treasures')
                    await tap(r['battle']['decoy_card']); await frames(); await tap(r['battle']['target'])
                    await save_snapshot(r['expected']['after_decoy'], 'Decoy card placement')
                    before_hook = await shot('decoy-placed')
                    await tap(r['battle']['hook_card']); await frames(); await tap(r['battle']['target'])
                    pending = await wait_image(lambda data: difference(before_hook, data, geometry.box(r['battle']['landing_rect'])) > 2,
                                               'Diagonal hook did not expose landing choices')
                    assert difference(before_hook, pending, geometry.box(r['battle']['energy_rect'])) < .35, 'Anchor stage spent energy before landing'
                    origin = r['battle']['origin']; radius = r['battle']['cell_size'] * .2
                    origin_box = geometry.box([origin[0]-radius, origin[1]-radius, radius*2, radius*2])
                    assert difference(before_hook, pending, origin_box) < .35, 'Anchor stage moved player before landing'
                    await shot('hook-landing-choice', pending)
                    await tap(r['battle']['landing'])
                    await save_snapshot(r['expected']['after_hook'], 'Hook landing commit')
                    await shot('hook-committed')
                    if full:
                        await tap(r['battle']['undo']); await save_snapshot(r['expected']['after_decoy'], 'Undo hook')
                        await tap(r['battle']['restart']); await save_snapshot(r['expected']['initial'], 'Restart trial')
                        await shot('restarted-trial')
                    await tap(r['battle']['return'])
                    await wait_image(lambda data: board_present(data, geometry, r['editor']['board']), 'Return did not restore editor')
                    await tap(r['editor']['save'])
                    saved = await expect_saved(lambda value: value['recent_id'] == r['preset_id'], 'Return/save original editor preset')
                    assert next(e['data'] for e in saved['presets'] if e['id'] == r['preset_id']) == expected_preset, 'Trial mutated original editor preset'
                    await shot('returned-original-editor'); await isolation('Return to original editor')
                    await tap(r['editor']['home']); await settled('Return home'); await isolation('Exit training')
                    assert not errors, (stem, errors)
                    reports.append({'stem': stem, 'passed': True, 'screenshots': shots, 'assertions': assertions,
                                    'typed_name': r['saved_name'], 'two_stage_hook': True, 'formal_save_sha256': hashlib.sha256(original.encode()).hexdigest()})
                    print('PASS training Web', stem, 'name/save/reload, four tabs, decoy, two-stage hook, return, formal isolation', flush=True)
                except Exception as exc:
                    print('TRAINING CONSOLE ERRORS', errors, flush=True)
                    writes = await page.evaluate('() => window.trainingStorageWrites || []')
                    print('TRAINING STORAGE WRITES', [{'time': item['time'], 'ids': [e['id'] for e in decode(item['value'])['presets']]} for item in writes], flush=True)
                    try: await shot('FAILED')
                    except Exception: pass
                    reports.append({'stem': stem, 'passed': False, 'screenshots': shots, 'assertions': assertions, 'error': str(exc), 'console_errors': errors})
                    raise
                finally:
                    (output / 'report.json').write_text(json.dumps({'full': full, 'elapsed_seconds': round(time.monotonic()-started, 2),
                        'omitted_snapshot_fields': OMITTED_FIELDS, 'replays': reports}, ensure_ascii=False, indent=2))
                    await context.close()
        finally:
            await browser.close()
    print(f'PASS training Web gate: {len(reports)} viewports in {time.monotonic()-started:.1f}s')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--validate-only', action='store_true')
    parser.add_argument('--full', action='store_true', help='Also verify actual undo and restart')
    args = parser.parse_args()
    asyncio.run(main(validate_only=args.validate_only, full=args.full))
