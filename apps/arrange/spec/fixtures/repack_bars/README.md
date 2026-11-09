# `repack_bars` — the small crafted fixture for bar alignment

The golden pair ADR-0006 gates Padding on.
Hand-written to be **readable as a `git diff`**, which is the thing
`repack_basic` cannot be: that directory is the live 32-track project (19
regions, 321 items, 4.6 GB of takes) and is an excellent *corpus* and a useless
*golden fixture*, because a diff at that size records nothing anybody can check.
This one is 4 regions, 3 tracks, 5 items and 4 envelope points, and every number
in it was chosen so the arithmetic can be done by hand.

**It is not renamed to `repack_basic`, deliberately.** That name is still the
live project's directory, which is a real REAPER project folder with REAPER's
own `Backups/` and `PreRecs/` inside it — renaming it would move 4.6 GB across a
drvfs bind mount, possibly while REAPER has the project open. The user's explicit
call was to leave it alone and name this one distinctly instead, so the original
naming proposal is **amended, not followed**.

## Status: **validated against REAPER 7.78/win64** — `Identity`, `Reordered` (2026-08-01), `Subset` (2026-08-05, re-run same day for the cut fade), `Headroom` (2026-08-06, applied twice)

Each ran against a copy of `before.rpp`, and each saved result matched
`expected_plan.lua` **exactly** — every region bound, pad, tempo marker, marker,
item, envelope point and Automation Anchor.

**`after.rpp` and `after.arrange.log` hold the most recent verified run, which is
now `Subset`.** ADR-0005 gives the fixture one after-slot, so a later
verification replaces an earlier one rather than accumulating files; the
`Identity` pair is in git history at `be5ee54` if the bar-alignment record is
what you need. The runs test different things and none supersedes another —
`Identity` isolates Padding and gap closing, `Reordered` exercises the
cumulative-sum argument, `Subset` exercises parking, `Headroom` exercises the
end adjustment and is the only one whose *second* application is supposed to
change something.

**Migrated to LCRR on 2026-11-07, without history.** `after.arrange.log` was
`after.tsb.log`, renamed with its contents unchanged, so it still names the old
`TSB_*` scripts that wrote it; the `TSB_*` actions are now `LCRR_Arrange_*`.
SHAs below (such as `be5ee54`) are in the old ReaperScripts repo, not this one.

**`Headroom` deliberately leaves no after-slot of its own.** It was run on
`after.rpp` and the file restored afterwards, so the golden half keeps matching
`expected_plan.lua`'s `Subset` prediction; `after.arrange.log` is its record. See
runs 6 and 7 below.

Both hand-written hypotheses this file used to carry are now **confirmed**, and
they are the reason the fixture works at all:

1. **Items with no `<SOURCE>` block survive** — REAPER loads them as empty items
   and they split, move and delete like any other. So the fixture needs no media.
   (The alternative, MIDI items, was rejected because a MIDI item's timeline
   length follows the tempo map, and this fixture is *about* the tempo map.)
2. **The short `PT` signature line is accepted** — `PT 48.0 90.0 1 262147`, where
   `262147` is `numerator | denominator << 16`. REAPER read the 3/4 correctly,
   carried it to 26.0 with the region, and re-saved it with its own extra
   trailing fields.

Two observations from that run worth keeping:

- **Split edges got REAPER's own 0.01 s fade, not ADR-0002's `CUT_FADE`
  (0.005 s).** Expected at the time: `CUT_FADE` was planned but unwritten,
  because the fade keys could not be confirmed from any reachable source
  (issue #6's remaining gap, split out as #15). Visible in the diff as
  `FADEIN 1 0.01 …` on the cut item.

  **Fixed, and confirmed by a real run on 2026-08-05** (issue #15) — see the
  `Subset` re-run below. `apply.splits` writes `D_FADEINLEN`/`D_FADEOUTLEN`
  (research/reaper-scripting.md §4.3a, now primary), and the cut piece at
  `POSITION 8` now reads `FADEIN 1 0.005 0 1 0 0 0`.

  **This fixture can only ever verify half of the fix.** Its one cut is on the
  item straddling Bravo's *start*, so the left piece (`11.000..12.000`) is
  outside every region and is Dropped Material — it is deleted before anything
  could read its fade-out. No Arrangement changes that, because which side of
  a cut survives is a property of the item's geometry, not of the ordering. So
  the run confirms `D_FADEINLEN` and says nothing about `D_FADEOUTLEN`.
  Covering the other edge needs an item straddling a region *end*, whose left
  piece stays inside the region and survives — a fixture addition, and one that
  means re-deriving `expected_plan.lua` by hand.

## Run 4 — `Subset` again, 2026-08-05 14:32, for the cut fade (#15)

`after.rpp` and `after.arrange.log` now hold **this** run. It reproduced run 3's
timeline exactly and changed one substantive line:

```
FADEIN 1 0.01 0 1 0 0 0     ->     FADEIN 1 0.005 0 1 0 0 0
```

Third field, the *manual* fade. The fourth — the auto-fade `apply.item_moves`
clears — stayed `0`, which is what proves the write hit the intended pair of
keys and not the `_AUTO` one. The rest of the diff is `IGUID`/`GUID` on the
piece the split creates (a new item each run), `MASTER_TRACKID`, an envelope
`EGUID`, and session noise (`CURSOR`, `MIXERUIFLAGS`, the project timestamp).
**No region bound, tempo marker, envelope point, marker or item position
moved.** A second `Subset` immediately after reported "nothing to do".

### The starting state was not `before.rpp`, and that turned out to be useful

The log reports all four Tempo Anchors as `(already present, rewritten)`,
where run 3's log reported them as new. REAPER's own backup taken at run start
(`Backups/after-2026-08-05_143234.rpp-bak`) explains it: the project held
regions at **before** positions (Alpha 0, Bravo 12, Charlie 32, Delta 48) but
tempo markers already at **all four region starts** (0, 12, 32, 48) carrying
explicit time signatures — whereas `before.rpp` has markers at 0, 32 and 48
only, two of them without an explicit signature. So the run began from
`before.rpp` plus a previous run's phase-1 anchors.

Worth knowing before diffing this pair, and worth not "fixing": it makes the
run a **stronger** result, not a weaker one. Two different starting states
reached a byte-identical timeline, which is ADR-0004's anchor-idempotence
claim demonstrated rather than argued — run 3 could not show it, because it
started from the only state where the anchors were genuinely new.

It is also why the anchor lines in `after.arrange.log` differ from
`expected_plan.lua`'s framing. The plan's *content* matches; only the
redundancy annotation differs, and that annotation is a property of the input,
not of the result.

## Run 5 — `LCRR_Arrange_ShowBarLines`, same session, for the measure base (#14)

Read-only, on the packed result. Two things came out of it:

- `TimeMap2_timeToBeats(0, 0.0) reports measure index 0` — **REAPER numbers
  measures from 0**, which closes the §4.5 open item.
- `0 of 4 region(s) would be padded`, every region reported already on a bar
  line. On a timeline the oracle had just aligned, that is the independent
  check that `TimeMap2_timeToBeats` and `TimeMap_GetMeasureInfo` share the
  base — a mismatch would have offset every bar line by a whole measure and
  produced four spurious pads.
- **All four Tempo Anchors were treated as changes, though three sat on existing
  markers with the same tempo.** **Confirmed by the second run**: the cause is
  that `GetTempoTimeSigMarker` reports `0`/`0` for the time signature of a marker
  whose `PT` line carries no explicit one — which is what `before.rpp`'s markers
  at 0.0 and 32.0 looked like — so `plan_anchors`' redundancy test could not match
  them. It is self-correcting: every marker in `after.rpp` now carries an explicit
  signature, and the second run reported all four as `(already present,
  rewritten)`.

## Runs 6 and 7 — `Headroom`, 2026-08-06 02:11 and 02:12, twice on purpose (#22)

The `Headroom` Arrangement is `Subset` plus `headroom = 4` on Bravo, and nothing
else different — so a diff against run 4 isolates the end adjustment from
everything else a Repack does.

**`after.rpp` does *not* hold these runs.** They were made on it and it was
restored afterwards: ADR-0005 gives the fixture one after-slot, and the golden
half has to keep matching `expected_plan.lua`'s `Subset` prediction. The record
of these two runs is `after.arrange.log`, which is enough, because what they
establish is a *sequence* rather than a state.

`Check` resolved the request before anything was written:

```
[headroom] 1 region(s) will have their end moved by HEADROOM. This is relative, not absolute:
  Bravo: asked +4.000s, resolves to +4.000s (+2 bar(s)), end 18.000 -> 22.000
```

**Then it was applied twice, and the second run moved the end again:**

```
HEADROOM "Bravo": end 18.000 -> 22.000 (+4.000s, +2 bar(s); asked +4.000s)
...
HEADROOM "Bravo": end 22.000 -> 26.000 (+4.000s, +2 bar(s); asked +4.000s)
```

That is the point of running it twice here, and it is the **opposite** of what
every other run in this file is checking. Headroom is deliberately not
idempotent (ADR-0007): a second run that changed nothing would mean it had
quietly become an absolute length. The rest of each run behaved as an ordinary
Repack — Delta and the parked Charlie both followed the moved end by the same
+4, and the envelope point stranded past Delta's old end was dropped and
re-anchored at the new one.

`spec/repack_bars_fixture_spec.lua`'s `with a Headroom on Bravo` block predicts
both applications, and its second-run geometry is hand-derived rather than
transcribed — these runs are what confirm the derivation.

## The second run found a bug — Automation Anchors were not idempotent

Running the same `Identity` Arrangement twice changed **exactly one thing**, and
it was not meant to change anything: the Mute envelope gained three duplicate
points, at 8.0, 18.0 and 26.0. Regions, pads, tempo markers, plain markers and
items were byte-identical, so Padding *is* idempotent as ADR-0004 claims.

**The duplicates were not cosmetic.** Where two points share a time the last one
wins, so the pair at 8.0 went `0, 1` → `0, 1, 0` and the value in effect from that
bound **silently flipped**. Two causes, both now fixed:

1. `apply.envelope_anchors` inserted unconditionally instead of replacing. It now
   **owns an anchor's time**: it clears whatever points are at that time, then
   writes the anchors planned for it, grouped by time so a deliberate step pair at
   a shared bound survives.
2. A point on the *last* placed region's end was classified as Dropped Material
   and deleted, then re-written by the same run's anchor — net-neutral only
   because `apply.plan` orders drops before anchors. `plan_pack` no longer plans a
   drop for a point an anchor is about to occupy.

A third problem fell out of fixing the first: `start_is_already_pointed` would
suppress a start anchor at a shared bound, and the *previous* region's end anchor
would then clear that time and stand alone — collapsing the step and replacing the
value in effect with the preceding region's. A start anchor is now suppressed only
when no end anchor claims the same final time.

**Running the fixed version on the corrupted `after.rpp` repairs it**, back to
exactly the run-1 state.

Re-run after the fix, this fixture behaved: run 1 as before, **run 2 reported
"already matches the timeline. Nothing to do."** — so the project state is
idempotent and no undo point is created. Note *why*, because it is not quite the
mechanism it looks like: `plan.is_empty` does not count `envelope_anchors`, so a
plan whose only work is anchors counts as empty and is skipped. Right here, wrong
in one narrow case — that was issue #13, since fixed.

## The `Reordered` run found a second bug — a destroyed tempo marker

Everything else was correct (regions 0..8 / 8..16 / 16..22 / 22..32, markers,
items, all 12 envelope points), but **four tempo markers went in and three came
out**.

`apply.tempo_moves` moved in plan order: Alpha `0 -> 8` first, while Bravo's
marker was **still at 8.0**. A tempo map cannot hold two markers at one time, so
REAPER collapsed them, and the next step moved the single survivor `8 -> 22` with
Bravo's values. Alpha's marker was gone, so Alpha inherited Charlie's 90 bpm from
0.0 and its internal bar count went 4 bars to 3 — exactly what Tempo Anchors
exist to prevent (ADR-0004: "regions of differing tempo each retain their own
internal bar count"). Bar *alignment* happened to survive, because 8 s is a whole
number of bars at both 120 and 90 bpm; that was luck, not correctness.

**Nothing reported it.** Every marker the plan named was found and written, so a
per-marker check sees nothing wrong; only the count reveals the loss.

**The first fix for that was itself wrong, and the failure was instructive.**
Ordering the writes so no destination is occupied cannot succeed on its own,
because **the timeline origin can never be vacated**: move the marker at `0.0` and
REAPER puts a fresh one there carrying the project tempo. Charlie's move to `0.0`
was therefore blocked by a marker that would never move, the cycle-breaker parked
Charlie 13 times out to `13022s`, and the run aborted with "could not order 4
tempo marker move(s) without collisions". It failed loudly rather than destroying
anything, and the stray marker's position is what proved the rule — `13022 = 1022 +
12 × 1000`, one park per pass.

`apply.tempo_moves` now orders its writes, **overwrites the origin marker** in that
one case (only one tempo can be in effect at an instant, the map must define one at
`0.0`, and the plan says which region starts there), refuses by name if a permanent
blocker sits anywhere else, and verifies two ways afterwards: every destination
holds a marker, and the total dropped by no more than the origin markers
deliberately absorbed.

**All of this is only reachable on a second Repack** — on a project with gaps every
destination lies in a gap being closed, which is why the live project's 69/69
transplant succeeded and why this needed an already-packed project to surface.

## Verified clean, 2026-08-01: `Identity`, `Identity` again, `Reordered`

The sequence that found all three bugs now runs correctly end to end:

- **`Identity`** — as predicted, including both pads.
- **`Identity` again** — "already matches the timeline. Nothing to do." No undo
  point. ADR-0004's idempotence claim and #4's "running it a second time changes
  nothing" criterion, both met.
- **`Reordered`** — regions at 0..8 / 8..16 / 16..22 / 22..32, `verse` at 2,
  `Alpha` at 8, items at 10 / 22 / 0 / 17, all 12 envelope points in place, and
  **4 tempo markers: 0 (90 4/4), 8 (120 4/4), 16 (90 3/4), 22 (120 4/4)**.

ADR-0004's invariant holds exactly, with each region keeping its own internal bar
count under a different tempo:

| Region | Span | Tempo | Bars |
|---|---|---|---|
| Charlie | 0..8 | 90 4/4 | 3 × 2⅔ s |
| Alpha | 8..16 | 120 4/4 | 4 × 2 s |
| Delta | 16..22 | 90 3/4 | 3 × 2 s |
| Bravo | 22..32 | 120 4/4 | 5 × 2 s |

**One thing to know before diffing `after.rpp` against `expected_plan.lua`: they
are different scenarios.** `expected_plan.lua` predicts `Reordered` applied
directly to `before.rpp`; the verified `after.rpp` is `Identity` *then*
`Reordered`, so its deltas differ. The destinations agree, which is the part that
matters — and the planner-side prediction is asserted by
`spec/repack_bars_fixture_spec.lua` rather than by the `.RPP`.

Everything else — the header, `TRACK`, `ITEM`, `MUTEENV` and `TEMPOENVEX` shapes
— was copied from `repack_basic/before.rpp`, a real 7.78/win64 save, rather than
recalled.

`TEMPOENVLOCKMODE` is **`0` (Time)**, unlike `repack_basic`, which carries `1`
and therefore has to be fixed by hand in Project Settings before every run
(`validate.tempo_env_is_time_based` refuses otherwise). Fixing it at source here
is deliberate: HANDOFF's API facts call this out as one of the traps that
recurs, because the setting lives inside the `.RPP` and reverting to a baseline
copy resurrects it.

## The grid

Three tempo/time-signature markers, so bar length changes twice:

| From | Tempo | Signature | Bar length | Bar lines |
|---|---|---|---|---|
| 0.0 | 120 | 4/4 | 2.0 s | 0, 2, 4, … 32 |
| 32.0 | 90 | 4/4 | 8/3 s | 32, 34⅔, 37⅓, 40, 42⅔, 45⅓, 48 |
| 48.0 | 90 | 3/4 | 2.0 s | 48, 50, 52, 54, … |

Both changes land exactly on a bar line of the section before them, so the grid
has no partial measure that is not deliberate.

## The regions

| Region | Start | End | Length in bars | Pad |
|---|---|---|---|---|
| Alpha | 0.0 | 8.0 | 4 bars @ 120 | none |
| Bravo | 12.0 | 21.0 | 4½ bars @ 120 | **+1.0 s → 22.0** |
| Charlie | 32.0 | 40.0 | 3 bars @ 90 | none |
| Delta | 48.0 | 53.0 | 2½ bars @ 90 3/4 | **+1.0 s → 54.0** |

Gaps of 4 s, 11 s and 8 s between them, for a Repack to close. Two regions are a
whole number of bars and two are not, so Padding is exercised and so is its
absence.

## What each element is here to exercise

- **`Bravo` and `Delta` are not whole bars** — Padding, in two different
  signatures, so a single hardcoded bar length cannot pass.
- **The `Reordered` Arrangement puts `Charlie` (90 bpm) first** — after which
  `Alpha` must still start on a bar line. That is ADR-0006's cumulative-sum
  argument: it only works because a placed region spans a whole number of bars,
  so getting it wrong here shows up as a region starting off-grid.
- **`Gtr` item at 11.0–14.0** straddles `Bravo`'s start → cut at 12.0; the
  11.0–12.0 tail touches no region and is **dropped**.
- **`Keys` item at 30.0–42.0** covers all of `Charlie` → diced into three, outer
  pieces dropped, middle carried. ADR-0002's "no exemption for an item spanning a
  whole region".
- **`Perc` item at 9.0–10.0** is a Loose Item in a gap → **dropped**.
- **`Keys` is `BEAT 2`** (beats, position only) — beat-based but safe to
  reposition, so `timebase_safe` is exercised without the run refusing. Mode `1`
  is deliberately absent; that belongs to issue #9's own fixture.
- **Plain marker `verse` at 34.0** sits *inside* `Charlie` rather than at its
  start, so marker carrying is not accidentally coupled to region starts.
- **`Gtr`'s Mute envelope** has points at 1.0 and 3.0 (inside `Alpha`), 33.0
  (inside `Charlie`) and 9.5 (in a gap → dropped). With an automation oracle it
  also gets 8 Automation Anchors, two per placed region.
- **`Identity` and `Reordered` name every region**, so neither produces `parks`.
  **`Subset` omits `Charlie`**, and exists to produce them: issue #7's half of
  the fixture.

## The `Subset` Arrangement — Parked Material

`Subset` is `Alpha, Bravo, Delta` in timeline order, so a diff against
`Identity` isolates parking from reordering. `Charlie` was the region to omit
because it is the only one carrying all four parked kinds at once, plus the
tempo park:

| What | Where | Becomes |
|---|---|---|
| Region `Charlie` | 32..40 | parked, length intact |
| Marker `verse` | 34.0 | parked, still 2.0 s inside its region |
| Mute point | 33.0 | parked, still 1.0 s inside it |
| `Keys` item | 30..42 | parked **whole** |
| Tempo marker | 32.0 | homeless → parked, written this run |

The `Keys` item is the interesting one. Cuts happen at the bounds of *moving*
regions, and `Charlie` does not move, so the item spanning it is not diced the
way `Reordered` dices it — it parks entire. That is the fixture's one proof that
splitting follows placement rather than region membership.

Two further things it pins down, both of which look wrong at a glance:

- **`Alpha` appears in nothing.** It starts at the origin already and is a whole
  number of bars, so neither bound changes; it is absent from `places`,
  `item_moves`, `marker_moves` and `tempo_moves` alike.
- **`Bravo` has no `tempo_moves` entry** in `expected_plan.lua`. The fixture's
  tempo map has markers at 0, 32 and 48 only, and the one at `Bravo`'s start is
  written by *phase 1*. The prediction is against the pre-anchor snapshot, as the
  `Reordered` one is, so there is no slice to transplant there. A real run
  re-reads the project between phases and does move it.

Arithmetic: bounds after Padding are `Alpha` 0..8, `Bravo` 12..22, `Delta`
48..54 — `Charlie` is not padded, because Padding keeps the Packed Block
bar-aligned and `Charlie` is not in it. Packed at lengths 8, 10, 6, the cursor
runs 0 → 8 → 18 → 24. With `PARK_GAP` at 300, parked material begins at 324; the
earliest thing parked is the `Keys` item at 30, so the shared offset is **294**.

### Verified clean, 2026-08-05 — and the clamp got tested at its boundary

`Subset` ran twice. Run 1 matched the prediction exactly; **run 2 reported
"already matches the timeline. Nothing to do."**

Four things confirmed that were hypotheses until this run:

- **A parked region keeps its own tempo.** `after.rpp` carries
  `PT 326.000 90.0 1 262148` — Charlie's Tempo Anchor parked with it and sits
  exactly on its new start. Nothing in the parking code wrote it: phase 1
  anchors every region, and phase 2 parked that anchor as a homeless marker.
- **Four tempo markers in, four out**, with three overwritten in place. The
  collapse hazard that destroyed one during the `Reordered` run did not recur.
- **The Keys item parked whole** — `POSITION 324 LENGTH 12`, never cut, because
  cuts follow *moving* regions and Charlie does not move.
- **Both step pairs survive**, at 8.0 (`0` then `1`) and 18.0 (`1` then `0`), so
  no region inherits its neighbour's automation value.

Counts: items 5 → 4 (−1 Loose Item, −1 cut tail, +1 piece), Mute points 4 → 9
(−1 dropped, +6 anchors), tempo markers 3 → 4, regions and markers 6 → 6.

**Run 2 is a stronger check than it looks.** `packed_end` is 24 and `PARK_GAP`
is 300, so parked material belongs at 324 — and the earliest parked thing, the
Keys item, is already at exactly 324. `park_delta` therefore computes to 0, the
non-negative clamp fires, and `plan.parks` comes back empty. The second run
exercises the clamp at its exact boundary rather than merely finding no work.

One detail that keeps run 2 non-destructive: the Mute point at 24.0 is Delta's
*end*, so half-open membership puts it inside no region and it would be Dropped
Material — except an anchor is about to occupy that time, which `plan_pack`
already accounts for.

## Running it

Per ADR-0005: `before.rpp` is the tracked baseline and is never edited by a run.
Copy it to `after.rpp` (gitignored), open *that*, run the action, **save**, then
diff. A verified `after.rpp` becomes the golden half with an explicit
`git add -f spec/fixtures/repack_bars/after.rpp`.

Run `Identity` first, then `Reordered`, then `Subset`.

`Headroom` is the exception to the paragraph above, and the only Arrangement
here that is: it applies **to the `Subset` result**, twice, and `after.rpp` is
restored afterwards rather than committed. Running it on `before.rpp` works and
proves nothing interesting — the whole claim is that a *second* application
moves Bravo's end a second time (18 → 22 → 26), which only exists as a sequence.
Keep the log lines and put `after.rpp` back:

```sh
git checkout spec/fixtures/repack_bars/after.rpp
```
