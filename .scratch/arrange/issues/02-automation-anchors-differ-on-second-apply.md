# 02. A second Apply writes different automation anchor values at shared bounds

Status: fixed in code 2026-11-07, not yet re-run on the host
Type: bug (engine, not the bridge: the cores are shared by the dialog scripts and the page)

Found 2026-11-07 by running the run-twice rule on the real project (`Rehearsal_Current`, Arrangement `20261109`, 21 regions), from the page. Evidence: `dev/reaper-projects/Rehearsal_Current.arrange.log`, entries 19:32:46 (Check), 19:32:51 (Apply 1), 19:32:54 (Check), 19:32:56 (Apply 2).

## What the log shows

Everything except automation is idempotent. Check 2 says 0 moves and EXACT Padding; Apply 2 rewrites every Tempo Anchor as "already present" and moves nothing.

The automation anchors are not. Both runs plan 164 anchors, but **12 of them carry a different value in run 2** (and 20 of run 2's anchors are not marked "already present", against 72 of run 1's first-time ones). All are binary Mute/Bypass envelopes, at bounds shared by two consecutive regions (the deliberate two-point step: the earlier region's end anchor, then the later region's start anchor):

| Envelope | Time | Region (edge) | Apply 1 | Apply 2 |
|---|---|---|---|---|
| BassDI Mute | 2435.230 | Darkness of Blue (start) | 1.0 | 0.0 |
| BassDI Mute | 2778.087 | Darkness of Blue (end) | 1.0 | 0.0 |
| BassDI Mute | 3565.526 | Sleep Tight (start) | 0.0 | 1.0 |
| BassDI Mute | 3867.208 | Sleep Tight (end) | 0.0 | 1.0 |
| BassDI Mute | 4101.242 | NES 16 (start) | 1.0 | 0.0 |
| BassDI Mute | 4284.354 | NES 16 (end) | 1.0 | 0.0 |
| BassLow Mute | 2178.523 / 2435.230 | God (start / end) | 0.0 | 1.0 |
| BassHigh Bypass / ReaEQ | 2178.523 / 2435.230 | God (start / end) | 1.0 | 0.0 |

Each run-2 value is the *other* half of the step pair at that time (e.g. at 2435.230 run 1 wrote God's end 0.0 then Darkness of Blue's start 1.0; run 2 read 0.0 for Darkness of Blue's start).

## Why it matters

If run 2's anchors are written as planned, **the mute/bypass state in effect from those region starts flips on a second Apply**, with nothing in Check, the summary or Verify to say so (this is the failure `docs/decisions.md` describes for `apply.envelope_anchors`: "the value in effect silently flipped"). Not yet confirmed in the project itself: that needs a look at the envelopes before and after Apply 2.

## Where to look (not investigated yet)

- `lib/regions.lua` `value_at_bound` (around line 1168) takes "the last point at the same position" from the snapshot and relies on the snapshot being in REAPER's own order. After run 1 there are two points at one time. If REAPER returns tied points in a different order than the applier wrote them (or `GetEnvelopePoint` order for equal times is not insertion order), the "last" is the wrong half, and every shared bound of an already-packed project reads the earlier region's value.
- `lib/apply.lua` `envelope_anchors`: the order it writes the pair in, and whether the points get sorted afterwards.
- The existing specs (`regions_spec`, `apply_spec`, "Subset applied twice") use fakes that keep insertion order, so they cannot see this.

## To confirm on the host

On a copy: look at the BassDI Mute envelope around 2435.230 before Apply 1, after it, and after Apply 2 (value in effect just after 2435.230, and the points at exactly that time, in order). Or run `Show envelope points` style output for that envelope if we add a diagnostic.

## Cause and fix (2026-11-07)

The user brought `Rehearsal_Current.rpp` in its original state. Its BassDI Mute envelope holds step pairs in file order, e.g. at 2178.5226 `0` then `1` (so `1` is in effect), yet Apply 1 planned `0.0` for God's start and for Distance's end. That is the wrong half, on the **first** run, so the first Apply also wrote wrong values, not only the second.

Cause: `lib/project.lua` ended `snapshot` with `table.sort(envelope_points, by_position)` over every envelope's points together. `table.sort` is not stable, so points at one time came out in arbitrary order, and `lib/regions.lua`'s `value_at_bound` ("the last point at a position wins; points arrive in REAPER's own order") picked the wrong half. A second run then read the pairs the first had written in yet another arbitrary order.

Fix: `project.lua` sorts regions, markers, items and envelope points with `sort_by_position`, which breaks ties by read order. A spec (`project_spec`: "keeps the order of points that share a time") failed before and passes now. Nothing else in the planner changed.

Consequences to keep in mind:
- Any real Apply before this fix may have written wrong automation values at bounds that carried a step pair (Mute/Bypass most visibly). The run logs list every anchor's value, so they can be compared with the project's original envelopes.
- The same unstable order could have affected anything else that relies on tie order in a snapshot; items and markers had it too and are now stable.

Still to do on the host: re-run Apply twice on a copy of the original `.rpp` and diff the two runs' automation anchors (they should now be identical), and check BassDI Mute at 2178.523 / 2435.230 by eye.
