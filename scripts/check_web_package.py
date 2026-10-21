#!/usr/bin/env python3
"""Audit Godot 4.6 PCK v3: excluded originals, expected assets, bounded web payload."""
import gzip, hashlib, json, struct, sys
from pathlib import Path
p=Path(sys.argv[1] if len(sys.argv)>1 else 'build/web/index.pck')
data=p.read_bytes()
magic, version, major, minor, patch, flags, base, directory=struct.unpack_from('<6I2Q',data)
assert magic==0x43504447 and version==3 and not flags&1, 'Unsupported/encrypted PCK'
pos=directory; count,=struct.unpack_from('<I',data,pos);pos+=4
entries=[]
for _ in range(count):
    n,=struct.unpack_from('<I',data,pos);pos+=4
    name=data[pos:pos+n].rstrip(b'\0').decode();pos+=n
    offset,size=struct.unpack_from('<QQ',data,pos);pos+=16
    md5=data[pos:pos+16];pos+=16
    flag,=struct.unpack_from('<I',data,pos);pos+=4
    assert hashlib.md5(data[base+offset:base+offset+size]).digest()==md5, name
    entries.append({'path':name,'bytes':size})
names=[e['path'] for e in entries]
for banned in ['font.ttc','ink_landscape','military_landmarks']:
    assert not any(banned in name for name in names), f'Unneeded asset still bundled: {banned}'
assert any('font-subset.otf' in name for name in names),'Subset font missing'
assert any('FONT_LICENSE.txt' in name for name in names),'Font license missing'
assert any('assets/map/seals' in name for name in names),'Current seal assets missing'
assert len(data)<2_000_000,f'PCK unexpectedly large: {len(data)}'
report={'pck_bytes':len(data),'pck_gzip9_bytes':len(gzip.compress(data,compresslevel=9,mtime=0)),'entries':entries}
print(json.dumps(report,ensure_ascii=False,indent=2))
print('PASS web package: original TTC/legacy art excluded; subset, license and seals present; PCK < 2 MB')
