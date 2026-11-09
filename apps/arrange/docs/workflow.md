# The Arrangement workflow

The end-to-end path from a project you have laid out by hand to a repacked one
you have confirmed. Seven steps, four REAPER actions and one text edit.

Vocabulary is `CONTEXT.md`'s — **Arrangement**, **Repack**, **Padding**,
**Headroom**, **Tempo Anchor**, **Packed Block**, **Parked Material**,
**Dropped Material**.

---

## 1. Capture the current order

**Action: `Capture the current region order as an Arrangement`**

Writes the project's regions, in timeline order, into the Arrangement sidecar
beside the `.RPP` as a named Arrangement. Name it after what it is — `Full`,
`Album`, `As recorded`.

Capture rewrites the whole sidecar. If the file has comments or hand formatting
(anything `Capture` would not write itself), it asks first, because the rewrite
drops them; after one accepted rewrite the file is in Capture's own form and the
question does not come back until it is hand-edited again.

This changes no project state. It is the only thing that writes the sidecar
from REAPER.

The project needs unique, non-empty Region Names before this will run, because
a Region Name is the key an Arrangement uses (ADR-0003). If it refuses, the
action `Find duplicate or unnamed regions` lists every offender.

## 2. Duplicate it

**No action — this is a text edit, by design.**

ADR-0003 makes the sidecar the authoring surface: REAPER gets two Arrangement
actions and everything else happens in a text editor. Open
`<YourProject>.arrangements.lua` beside the `.RPP`, copy the whole block and
change the key:

```lua
return {
  ["Full"] = {
    { "Intro",   headroom = 0 },
    { "Verse 1", headroom = 0 },
    { "Chorus",  headroom = 0 },
    { "Verse 2", headroom = 0 },
  },

  ["Radio"] = {          -- copied from "Full", renamed
    { "Intro",   headroom = 0 },
    { "Verse 1", headroom = 0 },
    { "Chorus",  headroom = 0 },
    { "Verse 2", headroom = 0 },
  },
}
```

A bare `"Intro"` is still a valid entry and means the same as
`{ "Intro", headroom = 0 }`, so a sidecar written before Headroom existed keeps
working untouched. `Capture` writes the longer form because the sidecar is the
only place the feature can be discovered — see step 4.

Keeping the captured Arrangement untouched is the point of duplicating rather
than editing in place: it stays a record of how the project was laid out, and
you can always get back to it by applying it.

## 3. Reorder or subset the copy

Still in the text editor. Reorder the Region Names, or delete some.

The order of the list **is** the Arrangement. An Arrangement may name a subset
of the project's regions — a radio edit is a subset — and the regions it omits
become Parked Material rather than being deleted (issue #7).

Two rules the file itself enforces when it is read:

- A Region Name may not appear twice in one Arrangement. One region cannot
  occupy two slots on a single repacked timeline.
- Every name must be a non-empty string.

The file is loaded in a sandbox and validated, so a typo produces a message
rather than a partly applied Arrangement.

## 4. Set the Headroom, where you want it

Still in the text editor. `headroom` is the number of seconds to add to or take
off that region's end:

```lua
["Radio"] = {
  { "Intro",   headroom = 0 },   -- leave it exactly as it is
  { "Verse 1", headroom = 4 },   -- about four seconds more air before the next song
  { "Chorus",  headroom = -2 },  -- about two seconds tighter
  { "Verse 2", headroom = 0 },
},
```

Four things to know, all of which the **Check** action in the next step will
tell you again with real numbers:

**The result lands on a bar line.** You type seconds; the new end is rounded to
the *nearest* bar. So `+4` at 120 bpm 4/4 is exactly two bars, and `+5` is three
— and **anything under half a bar rounds to no change at all.** That is the
likeliest reason a Headroom appears to do nothing. Check and the run log always
state what a request resolved to, even when it resolved to zero.

**It is measured on top of Padding, not instead of it.** A region gets padded to
the next bar line first, and the Headroom moves the end on from there. This is
what makes `headroom = 0` mean exactly the behaviour of the step before this one
existed.

**A shrink may only remove silence.** A region's end can never come back past
the last thing inside it — item, marker, envelope point or tempo marker — and
never below one bar. Ask for more and the run refuses, naming every offending
region and the largest shrink each could take. It never quietly clamps, and it
never deletes anything to make room. Shrinking is also not a way to remove a
region; dropping it from the Arrangement parks it, which is step 3's answer.

**It is relative, and applying twice applies twice.** Every other part of a
Repack can be run repeatedly without changing the result. This one cannot: it
moves the end from wherever the end currently is. Apply asks you to confirm
before it moves any end, and that prompt is the only guard —
[ADR-0007](adr/0007-headroom-is-relative-not-absolute.md) records why it was
built this way rather than as a target length.

## 5. Check it

**Action: `Check an Arrangement before applying it (read-only)`**

Prompts for the Arrangement name and reports everything knowable about applying
it **without writing anything**. No project state changes and no undo point is
created.

Three sections, in this order:

1. **Would refuse** — everything that would stop a run. All of them, not just
   the first, so one check is one round trip. A Headroom below its region's
   floor arrives here.
2. **Would happen, and running again will not undo it** — Headroom, Parked
   Material, Padding, Straddling Item cuts, Dropped Material. Headroom is listed
   first and is the one entry running again would do *again*; it names each
   region, what you asked for and what it resolves to.
3. **What this check cannot see** — read this one.

That third section is not boilerplate. Phase 1 of a run writes a Tempo Anchor
at every region start, and that is what puts those starts on bar lines; the
tempo oracle reads live project state (ADR-0006), so it cannot be asked about a
grid that does not exist yet. **Padding and Headroom are therefore exact on a
project whose Tempo Anchors are already present, and estimates on a first run** —
both are measured against bar lines, so both move with the grid. The report says
which case you are in.

## 6. Apply it

**Action: `Apply a named Arrangement`**

Repacks the project into the Arrangement's order. Runs immediately, with no
confirmation prompt — Undo plus the logged plan is the safety net, by explicit
decision.

**Unless the Arrangement carries a non-zero Headroom**, which is the single
exception, and the reason for it is that Headroom is the only thing here a
second run would do a second time. You get one dialog listing every region and
what it will gain or lose, with three answers:

- **Yes** — repack, and apply the Headroom.
- **No** — repack only, treating every Headroom as zero. Useful when you want
  the order without committing to the lengths.
- **Cancel** — nothing has been written. Nothing is written until you answer,
  so cancelling really is free.

An Arrangement whose Headroom is all zero shows no dialog at all and behaves
exactly as it always has.

One undo point for the whole run. The plan goes to the console and appends to
`<YourProject>.arrange.log` beside the project. **For Dropped Material that log is
the only record**, because the project afterwards cannot show what was
discarded — and for Headroom it is the only record of *why* a region is a
different length. Keep it.

## 7. Verify the result

**Action: `Verify the timeline against an Arrangement (read-only)`**

Checks that the timeline now holds the four properties a Repack promises:

- the named regions are in Arrangement order
- they are contiguous, from the start of the timeline — the Packed Block has no
  gaps
- every packed region start lands on a bar line (ADR-0004)
- every omitted region sits beyond the Packed Block as Parked Material

**It derives all of that from the project as it now stands, never from the plan
that produced it.** That is why it is worth running at all: re-applying the
Arrangement and being told "already matches the timeline" tests Apply against
itself, and a Repack that was self-consistently wrong passes it. Issue #19 was
exactly that shape and went unnoticed across several sessions.

It needs nothing but the current timeline, so it still works on a project
packed in an earlier session — unlike Undo, which does not survive one.

**One thing it deliberately cannot check: whether a Headroom was applied once or
twice.** A timeline whose Headroom was applied twice is bar-aligned, contiguous
and in Arrangement order, exactly like a correct one — nothing in the finished
project records how many times an end was moved. The report says so in its own
"what this check cannot see" section rather than letting a PASS imply more than
it means. Apply's prompt in step 6 is the guard; this is not.

---

## Two things worth knowing before the first run

**Padding permanently grows a region.** A region whose length is not a whole
number of bars has its end extended to the next bar line, which puts silence
inside its bounds and does not happen again on a later Repack (ADR-0004). The
check reports it per region with the exact amount.

**A first run on a project not built for this suite is where the refusals
live.** The tempo/time-signature envelope has to be on a Time timebase, every
region needs a unique name, and material on a beat-based timebase is refused
rather than moved (issue #9). All of these are what step 5 exists to surface
before you commit.

## The read-only actions, for reference

None of these write project state or create an undo point:

| Action | Answers |
|---|---|
| `Find duplicate or unnamed regions` | Does the project satisfy the Region Name invariant? |
| `Show each track's timebase` | Which tracks are beat-based? |
| `Show bar lines and Padding for every region` | Where is the bar grid, and what would Padding do? |
| `Check an Arrangement before applying it` | Will *this* Arrangement apply, and what will it change permanently? |
| `Verify the timeline against an Arrangement` | Did it? |

The first three are project-aware; the last two are Arrangement-aware, and take
a name.
