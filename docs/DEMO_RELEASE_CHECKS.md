# Demo release checks

The `gpt` branch publishes to the existing `gh-pages` site after the **basic
release gate**, without waiting for the longer browser regression job.
This does not mean the release has passed every test.

## Before publication

- Pinned Godot 4.6.3 import, script parsing, startup and all existing headless rule
  tests, including generated native fixtures.
- Font corpus/subset checks and export/PCK audit.
- A short real Chromium UI flow at 1280×940 and touch 390×844: new run → map →
  battle → debug victory → reward → map → reload/Continue → enter the next event.
- A focused chapter smoke also checks first-boss reward → second-chapter map →
  first battle and final-boss victory, on the same two sizes. Chapter-specific
  narrow-phone/landscape, revival, reinforcement and formation replays run in the
  background.
- Any failure blocks publication. The existing source-head guard prevents an
  obsolete source revision from publishing over a newer one.

## Background regression

The dependent job downloads the exact source-SHA artifact rather than rebuilding,
checks its build-info source SHA and PCK/WASM hashes, then runs all five browser
suites. Its failure remains a failed GitHub check; it does not undo an already
published demo. Failures should be investigated and corrected in a small follow-up
commit, not silently waived. All suites are attempted even if an earlier one fails.

Daily/demo runs cover desktop and portrait touch state behavior. All 13 event
scenarios remain covered on both sizes; all cannon/rook behavior and performance
assertions remain. The repeated landscape/small-phone UI replays and secondary
animation-recording passes are omitted in this mode.

Use Actions → Build GPT branch Web → Run workflow → `full_regression: true` for
all four map/event sizes and historical animation recordings. Use this full mode
for layout/animation changes or broad regressions. No scheduled runs are added.

Only pinned tool downloads are cached; no credentials, saves, or user data are
cached. A cache miss still installs and validates dependencies normally. Source
build metadata and regression evidence remain attached to each workflow run.
