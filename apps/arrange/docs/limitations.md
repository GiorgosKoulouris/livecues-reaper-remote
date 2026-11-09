# Limitations

What this suite will not do, and why. Most of these are deliberate — the design
consistently prefers refusing loudly to guessing quietly, because a Repack is
hard to unpick by hand once it has happened.

Vocabulary is [CONTEXT.md](../CONTEXT.md)'s.

---

## Preconditions: things that must be true first

### Every region needs a unique, non-empty name

An Arrangement refers to regions by **name**. It is the only handle it has.

REAPER does not require this — it will happily give you three regions called
`Take 1`, or none with a name at all. Region *Numbers* exist, but they are
user-editable and get reassigned when regions are recreated, so they are not
identity.

**Fix:** run **Find duplicate or unnamed regions**, then rename in REAPER's
Region/Marker Manager.

### The project must be saved

The Arrangement sidecar and the run log both live beside the `.RPP`. An unsaved
project has nowhere to put them.

### Project Settings → "Timebase for tempo/time signature env" must be `Time`

On a `Beats` timebase, every tempo marker holds its *bar* position and REAPER
derives its time from the markers before it. Writing one marker therefore
re-derives the time of every marker after it.

This is measured, not theoretical: on a real project, one write slid all 64
downstream markers by exactly 1.121486470s, and the run then aborted partway
through, unable to re-locate its second marker.

There is no fix on the suite's side. Re-locating markers by measure and beat
would find the right marker but write it to a time the next write invalidates
again — turning a clean crash into a scrambled tempo map. So it is a
precondition, checked before anything is written.

**Fix:** `Project Settings → Timebase for tempo/time signature env → Time`, then
**save**. The setting is read from the saved `.RPP`, so an unsaved change reads
stale — which refuses a run that would have worked, never the reverse.

### Beat-based track and item timebases are refused

Material on a beats timebase stores its position in quarter-notes, so moving it
around a tempo map can stretch its content. Rather than guess, a run refuses and
names the tracks and positions.

This is the largest outstanding gap in the suite, recorded as **issue #9** of the old ReaperScripts repo. Today
the answer is "set those tracks to a time timebase, or don't Repack this
project".

Beat-attached *envelope points* on a beat-timebase track are not refused: they follow the tempo map like items, and the applier lifts them before the tempo is rewritten and puts them back at their planned times (decisions.md, issue 10).

**Fix:** **Show each track's timebase** lists them; **Check an Arrangement**
names the specific items.

---

## Destructive behaviour: things it does on purpose

### Material outside every region is discarded

A Repack is intended to run on a project that has already been cleaned up, so
media touching no region at all is treated as spent and thrown away. This
includes the tail that the suite's own splitting leaves beyond a region's end,
and — the same rule extended to automation — envelope points touching no region.

**The run log is the only record.** The project afterwards cannot tell you what
was discarded. Undo restores it within the session; the log survives the
session.

**Before you run:** **Check an Arrangement** lists every piece by track and
position under `dropped`.

### Straddling Items are cut

An item crossing a region boundary is split at that boundary; the piece inside a
region travels with it, and the piece outside every region is discarded per the
rule above. This is unguarded and by decision
([ADR-0002](adr/0002-split-straddling-items-unguarded.md)).

One known rough edge: the fade applied at a cut edge is the suite's intended
value in the plan, but the write currently falls back to REAPER's own split
preference, because the relevant API keys could not be confirmed from any
reachable source.

### Padding permanently grows a region

A region whose length is not a whole number of bars has its end extended to the
next bar line, so its successor can start on a bar line with no gap. That puts
silence **inside** the region's bounds, and it is permanent.

It happens at most once per region — a later Repack of the same project pads
nothing, because the region is already a whole number of bars long.

**Before you run:** **Check an Arrangement** reports the exact amount per region.

### Headroom permanently moves a region's end, and applying twice moves it twice

`headroom` on an Arrangement entry adds seconds to — or takes them off — that
region's end, rounded to the nearest bar line. It is the **one operation in this
suite that is not idempotent**, and the only exception to the entry two below
this one.

It is relative by design: it describes a change to the end rather than a length
to reach, because that is how a set is actually adjusted — by ear, against the
song before it, iteratively. The idempotent alternative was on the table and
[ADR-0007](adr/0007-headroom-is-relative-not-absolute.md) records what was
traded away.

**What compensates:** Apply shows a confirmation dialog whenever any Headroom is
non-zero, listing every region and offering apply / repack-only / cancel. That
prompt is the *entire* guard. Nothing else can catch a double application:

- The project afterwards cannot, because the region is simply a different length
  and nothing records how it got there.
- **Verify cannot**, and says so in its own report. A double-applied timeline is
  bar-aligned, contiguous and in Arrangement order, exactly like a correct one.
- The run log can, if you keep it — every adjustment is recorded with the
  resolved seconds and bars.

**Two things it will not do.** A shrink may only ever remove silence: the end
cannot come back past the last item, marker, envelope point or tempo marker in
the region, or below one bar. Ask for more and the run **refuses**, naming every
offending region and the largest shrink each could take — it never quietly
clamps, and it never deletes content to make room. And shrinking is not a way to
remove a region; drop it from the Arrangement and it parks.

**Before you run:** **Check an Arrangement** reports every adjustment with what
you asked for and what it resolves to, including where that is zero — anything
under half a bar rounds to no change, which is the likeliest reason a Headroom
appears to have been ignored.

### Regions an Arrangement omits are moved, not deleted

This one is *not* destructive, but it looks like it. Omitted regions become
**Parked Material**: they are moved beyond the packed material, together with
everything belonging to them, by one shared offset. Nothing is deleted, and the
log records the offset — negating it reverses the parking.

---

## Design decisions that are sometimes mistaken for bugs

### There is no confirmation prompt, with one exception

Actions run immediately. The safety net is one undo point per run plus the
logged plan, on the reasoning that a prompt you always click through is not a
safety feature. The **Check** action exists to be the deliberate pause instead —
it is read-only and can be run as often as you like.

The exception is Headroom, above, and it exists precisely because the general
argument does not hold there: undo is the safety net for everything a *second*
run would decline to repeat, and Headroom is the one thing a second run would do
again. An Arrangement whose Headroom is all zero still shows no prompt.

### There is no GUI, and no action to duplicate an Arrangement

Authoring and reordering happen in a text editor, on the sidecar file
([ADR-0003](adr/0003-arrangements-as-name-keyed-lua-sidecar.md)). REAPER gets
exactly two Arrangement-writing actions: `Capture`, and `Apply`. Duplicating an
Arrangement is a copy/paste and a renamed key.

### An Arrangement may not name the same region twice

One region cannot occupy two slots on a single repacked timeline. There is no
"repeat the chorus" — that would require duplicating media, which is outside
this suite's scope.

### Applying twice does nothing the second time — except Headroom

This is intended, and it is load-bearing: several past bugs produced correct
output on a *first* run and only appeared on a second. If a second run of the
same Arrangement changes anything **other than a Headroom**, that is a bug worth
reporting.

A Headroom moving again on a second run is not a bug; it is the documented
behaviour of the one deliberately non-idempotent operation here
([ADR-0007](adr/0007-headroom-is-relative-not-absolute.md)). Answering "repack
only" to Apply's prompt gives back the old guarantee for that run.

### Hidden regions and region lanes are ignored

The project reader knows about both, but nothing consumes them. A hidden region
is packed like any other.

---

## Verification status, stated honestly

REAPER cannot be reached from the development container, so no script can be
executed against the real API from there. Local evidence is `busted` specs
against golden `.RPP` fixtures, plus `luacheck`. Real behaviour is established
only by a human running an action and saving the result.

The rule the repo holds itself to: **a single clean run is not evidence of
correctness for anything idempotent.** Four past bugs produced correct output on
a first run and appeared only on a second. Run it twice.

That rule matters *more* around Headroom, not less, and for the opposite reason:
it is the one operation whose second run is supposed to change something. So a
second run is how you confirm it is behaving — and a second run that changes
nothing means it has quietly become absolute.

What has actually been run, and what each run established, is recorded beside the
projects themselves: `spec/fixtures/repack_bars/README.md` for the golden pair,
and the `.arrange.log` files beside each fixture's `.RPP`.

---

## Not implemented

| | Reference |
|---|---|
| Beat-based timebase support | issue #9 |
| Tempo marker pruning | issue #10 |
| Cut-edge fades written by the suite rather than inherited from REAPER's preference | ADR-0002 |
| Any use of hidden-region or region-lane data | — |
| macOS/Linux installer (`scripts/install.ps1` is PowerShell; copy by hand) | — |

`#N` references are issues of the retired ReaperScripts repo (none was open at the migration). New work goes in `.scratch/arrange/issues/`.
