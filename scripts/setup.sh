#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version=4.6.3
case "$(uname -sm)" in
  'Linux x86_64') arch=x86_64 ;;
  'Linux aarch64'|'Linux arm64') arch=arm64 ;;
  *) echo 'This setup supports Linux x86_64 and arm64 only.' >&2; exit 1 ;;
esac
install_dir="${YIXING_TOOLS_DIR:-$HOME/.local/share/yixing-tools}/godot-$version-$arch"
mkdir -p "$install_dir" "$root/bin"
asset="Godot_v${version}-stable_linux.$arch.zip"
binary="$install_dir/${asset%.zip}"
if [[ ! -x "$binary" ]] || [[ "$("$binary" --version)" != "$version.stable.official."* ]]; then
  temp="$(mktemp -d)"; trap 'rm -rf "$temp"' EXIT
  curl -fsSL --retry 2 --connect-timeout 20 --max-time 300 -o "$temp/$asset" "https://downloads.godotengine.org/?version=$version&flavor=stable&slug=linux.$arch.zip"
  curl -fsSL --retry 2 --connect-timeout 20 --max-time 90 -o "$temp/SHA512-SUMS.txt" "https://github.com/godotengine/godot-builds/releases/download/$version-stable/SHA512-SUMS.txt"
  python3 - "$temp" "$asset" "$install_dir" <<'PY'
import sys,pathlib,hashlib,zipfile
folder,asset,dest=sys.argv[1:]; folder=pathlib.Path(folder)
expected=next(line.split()[0] for line in (folder/'SHA512-SUMS.txt').read_text().splitlines() if line.split()[-1]==asset)
assert hashlib.sha512((folder/asset).read_bytes()).hexdigest()==expected, 'Godot checksum mismatch'
with zipfile.ZipFile(folder/asset) as z: z.extractall(dest)
PY
  chmod +x "$binary"
fi
ln -sf "$binary" "$root/bin/godot"
# Stable command for later shells; do not rely on setup's exported PATH surviving.
if [[ -w /usr/local/bin ]]; then ln -sf "$binary" /usr/local/bin/godot; fi
"$root/bin/godot" --version
python3 -m pip install -r "$root/scripts/font-requirements.txt"
bash "$root/scripts/verify.sh"
