#!/usr/bin/env bash
set -euo pipefail
version=4.6.3
asset="Godot_v${version}-stable_export_templates.tpz"
target="${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/$version.stable"
if [[ -s "$target/web_debug.zip" && -s "$target/web_release.zip" && "$(cat "$target/version.txt" 2>/dev/null)" == "$version.stable" ]]; then echo 'Web templates already installed'; exit 0; fi
temp="$(mktemp -d)"; trap 'rm -rf "$temp"' EXIT
# Official bundle includes all platforms; only Web templates are installed here.
curl -fsSL --retry 2 --connect-timeout 20 --max-time 1800 -o "$temp/$asset" "https://downloads.godotengine.org/?version=$version&flavor=stable&slug=export_templates.tpz"
curl -fsSL --retry 2 --connect-timeout 20 --max-time 90 -o "$temp/SHA512-SUMS.txt" "https://github.com/godotengine/godot-builds/releases/download/$version-stable/SHA512-SUMS.txt"
python3 - "$temp" "$asset" "$target" <<'PY'
import sys,pathlib,hashlib,zipfile
folder,asset,target=sys.argv[1:]; folder=pathlib.Path(folder); target=pathlib.Path(target)
expected=next(line.split()[0] for line in (folder/'SHA512-SUMS.txt').read_text().splitlines() if line.split()[-1]==asset)
h=hashlib.sha512()
with (folder/asset).open('rb') as f:
 for chunk in iter(lambda:f.read(1024*1024),b''):h.update(chunk)
assert h.hexdigest()==expected, 'Template checksum mismatch'
with zipfile.ZipFile(folder/asset) as z:
 assert z.read('templates/version.txt').decode().strip()=='4.6.3.stable'
 target.mkdir(parents=True,exist_ok=True)
 for name in ['web_debug.zip','web_release.zip','version.txt']:(target/name).write_bytes(z.read('templates/'+name))
print('Installed Godot 4.6.3 Web templates:',target)
PY
