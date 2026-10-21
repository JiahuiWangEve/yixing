#!/usr/bin/env python3
"""Rebuild with --write; default checks corpus, glyphs and exact reproducible bytes."""
import argparse, hashlib, io, json, re, sys
from pathlib import Path
import fontTools
from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.pens.recordingPen import DecomposingRecordingPen
ROOT = Path(__file__).resolve().parents[1]
GAME = ROOT / 'game'
SOURCE = GAME / 'assets/font.ttc'
TARGET = GAME / 'assets/font-subset.otf'
MANIFEST = GAME / 'assets/font-subset.json'
VERSION = '4.61.1'
FACE = 0  # Verified Godot FontFile cache/0/face_index, not guessed from UI language.
EXTENSIONS = {'.gd', '.tscn', '.tres', '.godot', '.json', '.csv', '.po'}

def corpus():
    chars = set(chr(n) for n in range(32, 127))
    files = []
    for path in sorted(GAME.rglob('*')):
        if not path.is_file() or '.godot' in path.parts or path.suffix not in EXTENSIONS or path == MANIFEST:
            continue
        text = path.read_text(encoding='utf-8')
        chars.update(c for c in text if c.isprintable())
        for short, long in re.findall(r'\\u([0-9a-fA-F]{4})|\\U([0-9a-fA-F]{8})', text):
            chars.add(chr(int(short or long, 16)))
        # Numeric dynamic characters must be literals so the corpus can track them.
        for expr in re.findall(r'\b(?:char|String\.chr)\s*\(\s*([^)]*)\)', text):
            try: chars.add(chr(int(expr.strip(), 0)))
            except (ValueError, OverflowError): raise ValueError(f'{path}: nonliteral char()/chr() needs explicit corpus support: {expr}')
        files.append(str(path.relative_to(ROOT)))
    return sorted(map(ord, chars)), files

def build(codepoints):
    f = TTFont(SOURCE, fontNumber=FACE, recalcTimestamp=False)
    missing = sorted(set(codepoints) - set(f.getBestCmap()))
    if missing: raise ValueError('Original font cannot supply: ' + ', '.join(f'U+{n:04X} {chr(n)!r}' for n in missing))
    options = subset.Options()
    options.recalc_timestamp = False
    options.name_IDs = ['*']; options.name_languages = ['*']; options.name_legacy = True
    options.layout_features = ['*']
    worker = subset.Subsetter(options=options); worker.populate(unicodes=codepoints); worker.subset(f)
    # Modified subset uses its own name; retain all original license/copyright records.
    names = {1:'Yixing UI Subset', 2:'Regular', 3:'YixingUISubset-Regular-v1', 4:'Yixing UI Subset Regular', 6:'YixingUISubset-Regular',16:'Yixing UI Subset',17:'Regular'}
    for record in f['name'].names:
        if record.nameID in names: record.string = names[record.nameID].encode(record.getEncoding())
    if 'CFF ' in f:
        f['CFF '].cff.fontNames = ['YixingUISubset-Regular']
        top = f['CFF '].cff.topDictIndex[0]
        top.FullName='Yixing UI Subset Regular'; top.FamilyName='Yixing UI Subset'
    out = io.BytesIO(); f.save(out); return out.getvalue()

def verify_outlines(data, codepoints):
    original = TTFont(SOURCE, fontNumber=FACE)
    reduced = TTFont(io.BytesIO(data))
    a, b = original.getGlyphSet(), reduced.getGlyphSet()
    ca, cb = original.getBestCmap(), reduced.getBestCmap()
    for cp in codepoints:
        pa, pb = DecomposingRecordingPen(a), DecomposingRecordingPen(b)
        a[ca[cp]].draw(pa); b[cb[cp]].draw(pb)
        if pa.value != pb.value or a[ca[cp]].width != b[cb[cp]].width:
            raise ValueError(f'Changed outline/advance U+{cp:04X}')

def main():
    parser=argparse.ArgumentParser(); parser.add_argument('--write',action='store_true'); args=parser.parse_args()
    if fontTools.__version__ != VERSION: raise ValueError(f'Install pinned tools: python3 -m pip install -r {ROOT}/scripts/font-requirements.txt')
    points, files = corpus(); data=build(points); verify_outlines(data,points)
    meta = {'source':'assets/font.ttc','source_sha256':hashlib.sha256(SOURCE.read_bytes()).hexdigest(),'source_face_index':FACE,'source_face_name':'Noto Sans CJK JP Regular','fonttools':VERSION,'codepoints':points,'corpus_files':files,'subset_sha256':hashlib.sha256(data).hexdigest(),'subset_bytes':len(data),'license':'FONT_LICENSE.txt'}
    manifest=json.dumps(meta,ensure_ascii=False,indent=2)+'\n'
    if args.write:
        TARGET.write_bytes(data); MANIFEST.write_text(manifest,encoding='utf-8')
    elif not TARGET.exists() or TARGET.read_bytes()!=data or not MANIFEST.exists() or MANIFEST.read_text()!=manifest:
        raise ValueError('Font subset is stale/missing. Run python3 scripts/font_subset.py --write and commit font-subset.otf + font-subset.json.')
    print(f'PASS font subset: {len(points)} codepoints; {len(data):,} bytes; every outline and advance matches original face {FACE}; license retained.')
if __name__=='__main__':
    try: main()
    except (ValueError, KeyError) as error: print(f'FAIL {error}',file=sys.stderr); sys.exit(1)
