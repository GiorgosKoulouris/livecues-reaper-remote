# Handoff

Read this first in a fresh session. It carries only what the code, the ADRs and
the issues do not — chiefly the environment traps below, which are cheap
to trip over and expensive to discover.

Everything else is indexed from `CLAUDE.md`. Open work lives in
`.scratch/arrange/` (the spec and its numbered issues); no roadmap is
duplicated here. `#N` references are issues of the retired ReaperScripts repo. **`docs/decisions.md` lists the decisions that look
like bugs and are not — read it before "fixing" anything surprising.**

## Environment facts that are not obvious

- **REAPER is not reachable from this container.** It runs on the Windows host
  on a drive that is not mounted. No script can ever be executed against the
  real API from here. This is the reason for ADR-0001 and ADR-0005.
- **Install is one-way, repo → REAPER, via `scripts/install.ps1` (or
  `install.bat`), run on the Windows side — and this is a trap, not a
  footnote.** Editing files here changes nothing REAPER runs until it is
  re-run (unless installed with `-Link`); the old `sync.ps1` produced
  "identical output, no error" more than once. **Whenever real-REAPER
  behaviour doesn't match what the code should do, the first question is "was
  `install.ps1` re-run?"** The repo is the sole source of truth — REAPER's own
  script editor must not be used to edit these files, because the next install
  overwrites them.
- Scripts add their own folder to `package.path` via
  `reaper.get_action_context()` and require `lib.<module>`, so `lib/` must stay
  beside the `LCRR_Arrange_*.lua` files: `Scripts\LCRR\arrange\{*.lua, lib\}`
  in REAPER, `reaper/Scripts/LCRR/arrange/` here. `spec/layout_spec.lua` checks
  it. Specs reach `lib/` through `.busted`'s `lpath` instead.
- This suite was migrated from the ReaperScripts repo without its history.
  SHAs and `TSB_*` script names in old notes and fixture logs refer to that
  repo. REAPER installs from before the migration still have a `Scripts\TSB\`
  folder and Action list entries for it, which `install.ps1` does not touch.

## The rule that matters most

**A single clean run is not evidence of correctness for anything idempotent.**
Four of this work's bugs produced *correct output on a first run* and appeared
only when the same Arrangement was applied twice, to the operation's own output.
A first Repack of a gapped project never writes onto an occupied tempo position,
never meets its own anchors, and never has to vacate the timeline origin. **Run
it twice, always**, and diff the two results.

Its only automated expression is `spec/repack_bars_fixture_spec.lua`'s "Subset
applied twice" block, which covers the *plan* half on one fixture — not the
applier, not the live project, and no other Arrangement.

**Headroom is the one operation this rule reads backwards for** (ADR-0007). It
is deliberately *not* idempotent: applying an Arrangement twice moves those
region ends twice, by design, and a second run that changes nothing means it has
quietly become an absolute length. So a second run is still the test — it is
just that here the expected result is a *further* change. The
"Subset applied twice" block's nested `with a Headroom on Bravo` cases pin both
directions; the second-run geometry there is derived by hand rather than
transcribed from a REAPER-written `.RPP`, and says so.

**Before any real run**, every time: `scripts/install.ps1` on the Windows side,
and confirm it ran.

## API facts

`research/reaper-scripting.md` holds the sourced detail, tagged primary vs
secondary, and **is to be preferred to recollection**. These are the ones that
bite and that it does not frame as warnings:

- **Do not read `reascripthelp.html` through a summarizing fetch tool. It
  confabulates.** Two fetches of the same page returned two different, both
  wrong, signatures for the same function, and a third invented a return value.
  **`curl` it and grep locally** — the copy self-reports `REAPER v7.78`, the
  version this suite runs against — and cross-check against Cockos's own
  `reaper_plugin_functions.h`. Method in §4.5.
- **Do not compute bar positions in this container.** An estimate of the live
  project's Padding predicted 2 regions and ~3.5 s; the real oracle produced 8
  regions and 7.237 s, and only one of the eight matched.
  `LCRR_Arrange_ShowBarLines.lua` asks the real oracle without writing anything.
- **`TEMPOENVLOCKMODE` must be `0`** or a Repack is refused up front (`1` =
  Beats, under which writing one tempo marker re-derives the time of every
  marker after it — measured at `1.121486470 s` across 64 markers). **It lives
  inside the `.RPP`, so reverting to a baseline copy resurrects it.**
  `repack_basic` carries `1`; `repack_bars` carries `0` deliberately.
- An item's position is **not** a stable identity across a tempo edit: rewriting
  the tempo map drags every beat-anchored item. `apply.locate_items` resolves
  every `MediaItem*` before the first tempo write.

## Fixtures

| Fixture | What it is |
|---|---|
| `spec/fixtures/repack_bars/` | The **golden pair** (ADR-0005). Crafted small enough that a `git diff` of `after.rpp` is readable, and asserted against `expected_plan.lua`. Its `README.md` records every run. |
| `spec/fixtures/repack_basic/` | The **live project**, and *not* a fixture directory — a real REAPER project folder with REAPER's own `Backups/` and 4.6 GB of takes in `PreRecs/`. Only its small text files (`before.rpp`, `before.arrangements.lua`, the run log) are tracked; the media exists only on the host and is never committed (`.gitignore`). An excellent corpus, a useless golden pair: at 19 regions and 330 items no diff is readable. Runs are recorded in `after.arrange.log` beside the `.RPP` (runs before the migration, as `after.tsb.log`, renamed with its contents unchanged). |

A prepared copy, not `before.rpp` unmodified, is what live runs are made on: it
needs `TEMPOENVLOCKMODE` set to `0`, and the four tracks on `BEAT -1` set
explicitly to `0`, or `lib/project.lua` refuses their items.

## Never run in REAPER

**Nothing has run in REAPER since the migration to LCRR** (2026-11-07): the
renamed scripts, their new `package.path` line (lib/ beside the scripts, not
one level up), the `.arrange.log` name and `install.ps1`'s reaper-slice code
are covered only by specs here. Neither has step 3's split of every script
into a core and a dialog front end (ADR-0008). `spec/dialog_spec.lua` shows
each script still makes the same dialogs, console output, log, undo calls and
applier calls as before, but only against a scripted stand-in for REAPER.
`LCRR_Arrange_ShowTrackTimebase` now requires `lib/` too, so it needs the
whole folder installed. The first real run should be a read-only
action (`LCRR_Arrange_FindDuplicateRegionNames`), then the usual run-twice
check. `LCRR_Arrange_ShowTrackTimebase`'s packaged version is untested. `apply.splits`' cut
fade-*out* is written but unobserved — `repack_bars`' one cut leaves its left
piece Dropped before anything reads it; covering it needs an item straddling a
region *end*.

## Process state

The suite's agent setup (`/docs/agents/`, issues in `.scratch/`) applies.
`/mattpocock-skills:to-spec` was run once in the old repo, producing issue #22
(Headroom); such skills are `disable-model-invocation: true` — **only the user
can launch them.** The test seam a spec should reach for is already
decided: the planner/applier boundary from ADR-0001, planners covered by
`busted` and the applier by the golden `.RPP` pair of ADR-0005.
