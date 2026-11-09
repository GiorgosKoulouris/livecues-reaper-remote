# Bar lines come from an injected tempo oracle, in two phases

ADR-0004 makes bar alignment the Repack invariant. ADR-0001 makes planners pure
functions over plain tables. Those two collide: deciding where to pad a region to
needs time↔bar conversion over a tempo map that includes the Tempo Anchors the
run has not written yet, and REAPER is the only thing that can answer that.

Bar lines therefore reach the planner as an injected **tempo oracle** — a table
of functions, currently just `next_bar_at_or_after(time)`, that wraps REAPER's
`TimeMap` calls in production and is a plain fake in specs. The planner stays
pure; the oracle is a parameter, not a hidden dependency.

Making the oracle answerable requires splitting a run into two phases inside one
undo block:

1. `regions.plan_anchors` decides Tempo Anchors. This needs no bar math — an
   anchor records the tempo already in effect and starts a new measure.
2. The applier writes them, which is what puts every region start on a bar line.
3. `regions.plan_pack` plans Padding, placement and parking, with the oracle now
   reflecting the anchors.

## Considered options

**Reimplementing REAPER's tempo integration in Lua** — linear tempo ramps,
partial-measure time signatures, the lot — was rejected. Nothing in this
environment can execute `reaper.*` (ADR-0001), so the reimplementation would be
unverifiable exactly where it is most likely to be wrong, and the live project in
`prj/` contains both ramps and partial-measure signature points.

**Restricting the suite to piecewise-constant tempo maps**, aborting on ramps,
was rejected for the same reason in reverse: the one real project available has
ramps, so the suite would refuse to run on it.

## Consequences

- A run is two plan/apply phases, not one. It is still a single undo point and a
  single logged plan, so this is invisible from REAPER.
- Phase 2's plan is only as good as the oracle. A wrong `TimeMap` wrapper is
  indistinguishable from a wrong planner until the golden fixtures of ADR-0005
  exist, which makes those fixtures the gate on trusting Padding at all.
- Placement itself needs no bar math. Once a region starts on a bar line and
  spans a whole number of bars, its tempo slice transplants rigidly and its
  duration in seconds is invariant, so packing is a cumulative sum and every
  later region's alignment follows by construction. Only Padding queries the
  oracle.
- That argument is load-bearing, so the transplant is **planned explicitly**:
  `plan_pack` emits a `tempo_moves` entry for every tempo marker inside a placed
  region, carrying the same delta as the region. Without it the cumulative sum
  would be arithmetic resting on an instruction nobody had issued.
- The oracle answers two questions, `next_bar_at_or_after(time)` and
  `tempo_at(time)`. The second exists so the anchor plan can carry the actual bpm
  and time signature: mid-ramp, the tempo in effect is not any marker's bpm, so
  reading the nearest marker would write the wrong anchor.
- Padding must not run a region into its neighbour, since that would capture
  material belonging to the neighbour. The planner aborts on the overlap rather
  than truncating the pad — ADR-0004 says region audio is never overlapped, and
  silently shortening a pad would break bar alignment instead.

## Amendment (issue #4): tempo markers outside every placed region are parked, not left alone

A tempo marker `region_holding` cannot place — one sitting in a gap the Repack
is about to close, or inside a region the Arrangement omits — has no home once
that gap closes: left at its original position, it silently ends up inside
whichever region lands on top of it, changing that region's tempo. The
question this ADR originally deferred ("what should happen to the tempo map
under Parked Material") is settled: it parks, translated by the same shared
offset as the rest of Parked Material (CONTEXT.md), rather than being dropped.
Dropping — deleting the marker outright, the fate of every other category that
touches no region — was considered and rejected: issue #10 shows a deleted
tempo marker can slide any beat-based material downstream of it, and this
suite's one real project is 28/32 tracks beat-based. Unlike the rest of
Parked Material, this is applied this session (`lib/apply.lua`'s
`apply.tempo_moves`), not merely planned — see `lib/regions.lua`'s comment on
why "park" cannot mean "planned but not written" for this one category.

## Amendment (issue #8): envelope points do not get tempo's exception

The question above was reconsidered for envelope points, carried the same way
tempo markers are (a placed region's points transplant by its delta), and the
answer came out the other way. A homeless envelope point — one
`region_holding` cannot place, because it sits in a gap or inside a region the
Arrangement omits — does *not* automatically inherit tempo's "always parked,
never dropped" treatment. The reasoning that carved out that exception for
tempo markers doesn't transfer: issue #10's hazard is that deleting a tempo
marker can reposition *other* material via the tempo map, and nothing about
an envelope point's presence or absence has that kind of effect on anything
else. So an envelope point still inside some region (an omitted one) parks
with it, exactly like an item or a plain marker in the same position — planned
only, not yet applied (#7). One touching no region at all is Dropped, the
general rule, the user's explicit choice over parking it like a tempo marker
precisely because no hazard argues for the exception (`lib/apply.lua`'s
`apply.envelope_drops`, using `DeleteEnvelopePoint`).

## Amendment: Automation Anchors, and a second injected oracle

Confirmed against a real run: automation is sparse, and sparseness encodes
adjacency. A value set at one song's start persists through the next song,
which carries no point of its own — correct only while the two stay adjacent.
A Repack reorders them, so the second song silently inherits whatever now
precedes it, and a ramp can form straight across a song boundary. Nothing in
the plan names this, because from the planner's point of view no point moved
wrongly; the points are all exactly where they were asked to go.

**A point is therefore written at both bounds of every placed region, holding
the value that envelope already had there** — `plan.envelope_anchors`,
`apply.envelope_anchors`. This is the same move ADR-0004 already makes for
tempo, for the same reason: a region should carry its own values rather than
depend on its neighbour. The name follows deliberately.

Three consequences worth stating, because each looks like a bug otherwise:

- **It adds points the project never had.** ADR-0004 already accepted exactly
  this trade for Tempo Anchors, which add tempo markers to projects that had
  none. The run log lists every anchor and the value it carries, since the
  project afterwards cannot distinguish an anchor from an authored point.
- **Adjacent placed regions share a bound, so two anchors land on one time.**
  That is a zero-length segment, which is how REAPER expresses a step — and a
  step is what a song change wants. It is not a duplicate.
- **Every anchor is square, and carries the last *authored* value rather than
  an interpolated one.** Both halves were got wrong once each against real
  data, so both are recorded with their counter-example.

  *Square*, because a point's shape governs the segment after it and a ramp can
  never legitimately begin at a region bound. Writing anchors linear made a run
  ramp an end anchor's 1 down to the 0 the following region set 115 seconds
  later. An earlier fix had start anchors inherit "the shape already in effect",
  which looks more careful and is not: the last point at or before a region
  start is either exactly on it (no anchor is planned there) or strictly before
  the region, so it is always outside and its ramp always crosses the bound.
  There is no intra-region ramp at a region start to preserve.

  *Last authored value*, because a ramp crossing a region bound interpolates
  between two songs the Repack is about to separate — sampling it yields a
  number nobody wrote. Track 14's Transpose points are `0.5`, `0.689` and
  `0.72`, linear, with multi-song gaps; evaluating at each bound produced
  `0.49848908`, `0.49833384`, `0.49787437` …, a staircase of near-`0.5` values
  with each region ramping to the next. Taking the originating point's value
  cancels the doomed ramp and restores the `0.5` that was actually written.
  The oracle still answers the one case the points cannot: no point precedes
  the bound, so the value is the envelope's own default.
- **Only a region *start* can already be covered by a point of its own.**
  Region membership is half-open, `[start, end)`, as it is for every other
  category here. A point exactly on a start is inside the region and travels
  with it, so anchoring there would overwrite a deliberate value with a derived
  one. A point exactly on an *end* is **not** inside the region — it belongs to
  the next region, parks, or is dropped — so an end bound always needs its own
  anchor, and the value it carries is the last one strictly *inside* the
  region. Treating both bounds alike was a real failure: track 14's Transpose
  is authored as step pairs, region "The pain you leave behind" ended exactly
  on one at `5619.164`, both points were dropped as Material touching no
  region, and the suppressed end anchor left that region ramping 265 seconds
  into the next song's `0.696`.
- **Where two points share a time, the last one wins.** Step pairs are how
  real automation expresses an instant change (`0.495` immediately followed by
  `0.72`), so the value in effect going forward is the second of them.

This also stops `envelope_drops` (the amendment above) being lossy: a point
outside every region is deleted as Dropped Material, but it may have been the
thing *establishing* a value some later region relied on. Anchors are
evaluated before anything moves, so that value is captured at the bounds
before the drop removes its source.

**The value arrives through a second injected oracle**, alongside `tempo`.
The planner has every envelope *point* but not the value *between* points, and
REAPER's shapes include bezier and slow start/end — reimplementing that
interpolation in Lua is the same mistake this ADR rejected for bar math.
`LCRR_Arrange_Apply.lua` wraps `Envelope_Evaluate`; the planner stays
pure and the specs inject a table of known values. Absent the oracle, no
anchors are planned, so the category is opt-in for any caller that does not
want it.

## Amendment (issue #4): built, and what real REAPER added to the design

Both phases now exist and have run against REAPER 7.78/win64
(`lib/tempo_oracle.lua`, `regions.plan_anchors` + `apply.anchors`, then
`plan_pack` + `apply.plan`, inside one undo block). The design above survived
contact; four things had to be added to it, each forced by a real run rather
than by reasoning.

**The oracle answers from `TimeMap_*`, and its signatures are primary-sourced.**
`next_bar_at_or_after` is `TimeMap2_timeToBeats` for the measure containing the
time, then `TimeMap_GetMeasureInfo`, whose return value *is* that measure's
start in seconds. `tempo_at` is `TimeMap_GetTimeSigAtTime`, which reports the
*effective* tempo — what a mid-ramp anchor needs. Neither the reference nor the
SDK header says whether measure indices are 0- or 1-based, so the oracle does
not depend on the answer: it verifies the bracket
`measure_start(m) <= time < measure_start(m + 1)` and steps until it holds. See
research/reaper-scripting.md §4.5, including why that page must not be read
through a summarizing fetch tool.

**Phase 2 is planned after phase 1 has already written, and a refusal therefore
arrives with anchors on the timeline.** This is forced by the ADR's own logic —
Padding cannot be computed against a grid that does not exist — so the run
closes the undo block anyway and says so. Everything checkable up front is
checked before phase 1.

**A Tempo Anchor carries the `lineartempo` in effect at the region start**,
rather than a constant. `SetTempoTimeSigMarker` demands the flag, and both
constants are wrong somewhere: always-square flattens a ramp the anchor lands
inside, moving the grid downstream of it and dragging beat-based material
(issue #10's hazard, arriving through an insert instead of a delete);
always-linear invents a ramp aimed at whatever marker follows. Inheriting
preserves the curve, which is what an anchor is for — it changes what a region
*depends on*, never how it sounds. Note this is the opposite answer from the
Automation Anchor amendment's "always square", and the asymmetry is real: there
the preceding point is always strictly outside the region so its ramp always
crosses the bound, whereas here the flag describes the tempo segment the anchor
subdivides.

**Writing the tempo map is not a loop over the plan**, and this is the part no
amount of reasoning produced. Two REAPER rules, both established by real runs
and neither documented anywhere consulted (research §4.4a):

- *Two tempo markers cannot share a position.* Writing one onto an occupied
  position collapses them, and a marker ceases to exist. Measured: 4 in, 3 out,
  reordering an already-packed project — the region that lost its marker
  inherited its neighbour's tempo, exactly what Tempo Anchors exist to prevent.
- *The timeline origin can never be vacated.* Move the marker at `0.0` and
  REAPER puts a fresh one there carrying the project tempo, so a move *to* `0.0`
  is blocked by something that never moves.

So `apply.tempo_moves` orders its writes to avoid occupied destinations,
overwrites the origin marker in that one case, refuses by name if a permanent
blocker sits anywhere else, and verifies afterwards that every destination holds
a marker and that the count dropped by no more than the origin markers it
deliberately absorbed. **Neither failure is visible per-marker** — every marker
the plan named is found and written — which is why the verification is
structural rather than per-entry.

**The consequence for how this suite is verified.** All of the above, plus the
Automation Anchor duplication fixed in the same session, share one property:
they are invisible to a *first* run and appear only when the operation runs
again on its own output. A first Repack of a gapped project never writes onto an
occupied tempo position, never meets its own anchors, and never has to vacate
the origin. ADR-0005's golden pair is what made them findable; **re-running the
same Arrangement twice is now part of verifying any change here.**

## Amendment (issue #7): parking writes, and a parked region keeps its own tempo

The two amendments above settled what *becomes* Parked Material. This settles
what happens to it, which until now was "planned, not written" for every
category except tempo markers.

**Parking is not a fifth way of moving something.** A parked region is a region
being repositioned, a parked marker is a marker being repositioned, and so on;
the only thing parking contributes is *which* offset, and the planner has
resolved that into a `to` on every entry before the applier sees it. So
`apply.split_parks` routes rather than writes — four lists, each in the shape
its category's applier already documents, and no new `reaper.*` call anywhere in
the parked path. The alternative, a dedicated writer per parked kind, would have
duplicated four functions in order to add nothing to any of them.

Two consequences are worth recording, because each looks like an omission.

**Parked items are located in the same up-front pass as carried ones.** The
tempo-map hazard that split `apply.item_moves` in half applies here with more
force, not less: parked material sits furthest out on the timeline, so it is
downstream of every tempo edit a run makes, and a beat-based parked item would
be dragged off its recorded position by all of them.

**No Tempo Anchor is written for a parked region, and one is nonetheless
present.** `plan_anchors` anchors every region in the project rather than only
the ones an Arrangement places. Phase 1 therefore puts a marker on an omitted
region's start; phase 2 re-reads the project, finds that marker inside no
*placed* region, and parks it by the same offset as the region it marks. The
anchor travels with its region for free. Anchoring only the arranged regions —
which reads as the tighter scope — would leave a parked region inheriting
whatever tempo the Packed Block left in effect, which is the exact failure Tempo
Anchors exist to prevent, aimed at the one category that would be exempt from
them.

`PARK_GAP` was raised from 30 s to 300 s at the same time. It is the only thing
marking where a Repack's output ends and its leftovers begin, and at 30 s it
read as an ordinary gap between songs at normal zoom. Being longer than any
region in the live project makes it unambiguous instead. It is a tuning value,
not a load-bearing one — but it had already broken a spec that hard-coded a
position "clear of the block", so specs express distances in terms of the
constant now.

**The clamp stays, and stays silent.** When parked material is already beyond
`packed_end + PARK_GAP`, the offset is zero and nothing is parked at all —
`plan.parks` comes back empty rather than listing entries that would not move.
This is what makes a repeat Repack a clean no-op, and the user's explicit
choice over the two alternatives: reporting zero-offset parks (which would need
a redundancy flag, exactly as `plan_anchors` has for anchors, to keep the no-op),
or always translating so the earliest parked thing lands on the gap (which would
drag material backwards that the user had deliberately left far out).
