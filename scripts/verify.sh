#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
godot="${GODOT_BIN:-$root/bin/godot}"
[[ "$("$godot" --version)" == 4.6.3.stable.official.* ]] || { echo 'Requires Godot 4.6.3 standard' >&2; exit 1; }
logs="${YIXING_LOG_DIR:-$root/verification/latest}"
mkdir -p "$logs"
# Every verification run uses a disposable save/cache so tests cannot overwrite progress.
state="$(mktemp -d)"; trap 'rm -rf "$state"' EXIT
export XDG_DATA_HOME="$state/data" XDG_CONFIG_HOME="$state/config" XDG_CACHE_HOME="$state/cache" GODOT_SILENCE_ROOT_WARNING=1
run() {
  local label="$1"; shift
  local rc=0
  timeout 120 "$godot" --headless --path "$root/game" "$@" > "$logs/$label.log" 2>&1 || rc=$?
  if [[ $rc != 0 ]] || grep -Eq 'SCRIPT ERROR:|Parse Error:|(^|[[:space:]])ERROR:' "$logs/$label.log"; then
    cat "$logs/$label.log"; echo "FAIL $label (exit $rc)" >&2; return 1
  fi
  echo "PASS $label (exit $rc)"
}
"$godot" --version > "$logs/version.txt"
python3 "$root/tests/font_corpus_checks.py" > "$logs/font-corpus.log" 2>&1 || { cat "$logs/font-corpus.log"; exit 1; }
python3 "$root/scripts/font_subset.py" > "$logs/font-subset-build.log" 2>&1 || { cat "$logs/font-subset-build.log"; exit 1; }
run import --editor --import
for script in "$root"/game/*.gd; do
  run "parse-$(basename "$script" .gd)" --check-only --script "$script"
done
run startup --quit-after 120
run regression --script "$root/tests/recovered_checks.gd"

run starts --script "$root/tests/start_profile_checks.gd"

run routes --script "$root/tests/route_checks.gd"

run map-interaction --script "$root/tests/map_interaction_checks.gd"

run map-state-safety --script "$root/tests/map_state_safety_checks.gd"

run card-rebalance --script "$root/tests/card_rebalance_checks.gd"

run current-tutorials --script "$root/tests/current_tutorial_checks.gd"

run space-shortcut --script "$root/tests/space_shortcut_checks.gd"

run seal-map --script "$root/tests/seal_map_checks.gd"

run font-subset --script "$root/tests/font_subset_checks.gd"

run map-performance --script "$root/tests/map_performance_checks.gd"
