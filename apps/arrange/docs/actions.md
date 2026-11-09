# Action reference

Every action in the suite: what it needs, what it changes, and what it refuses
on. The **Action list entry** column is the text you search for in REAPER's
`Actions → Show action list…`.

Vocabulary is [CONTEXT.md](../CONTEXT.md)'s. The path these actions sit in is
[docs/workflow.md](workflow.md).

| File | Action list entry | Changes the project? |
|---|---|---|
| `LCRR_Arrange_FindDuplicateRegionNames.lua` | Find duplicate or unnamed regions | No |
| `LCRR_Arrange_ShowTrackTimebase.lua` | Show each track's timebase | No |
| `LCRR_Arrange_ShowBarLines.lua` | Show bar lines and Padding for every region (read-only) | No |
| `LCRR_Arrange_Capture.lua` | Capture the current region order as an Arrangement | Writes the sidecar file only |
| `LCRR_Arrange_Check.lua` | Check an Arrangement before applying it (read-only) | No |
| `LCRR_Arrange_Apply.lua` | Apply a named Arrangement | **Yes** |
| `LCRR_Arrange_Verify.lua` | Verify the timeline against an Arrangement (read-only) | No |

Every action except `Apply` leaves REAPER's undo history untouched — they create
no undo point at all, so running one does not push a real edit further down the
stack.

---

## Files these actions read and write

Two files live beside your `.RPP`, both named after it:

| File | Written by | What it holds |
|---|---|---|
| `<Project>.arrangements.lua` | `Capture`, and you, in a text editor | The Arrangements. This is the authoring surface |
| `<Project>.arrange.log` | Every action that produces output | Appended to on every run. **The only record of discarded material, and of Headroom** |

The sidecar is plain Lua, read in a sandbox with an empty environment — a typo
produces an error message, never a partly applied Arrangement.

An entry is either a bare Region Name or a table carrying the name plus a
`headroom` — seconds to add to or take off that region's end
([ADR-0007](adr/0007-headroom-is-relative-not-absolute.md)):

```lua
return {
  ["Radio"] = {
    { "Intro",  headroom = 0 },   -- unchanged; same as writing just "Intro"
    { "Chorus", headroom = 4 },   -- about four seconds more at the end
    { "Outro",  headroom = -2 },  -- about two seconds tighter
  },
}
```

The result is rounded to the nearest bar line, so a request under half a bar
resolves to no change. A field the parser does not recognise is refused rather
than ignored — `headrom = 4` is a typo whose only other outcome is a run that
silently does nothing to that region.

---

## Find duplicate or unnamed regions

**Needs:** nothing.
**Changes:** nothing.

Lists every Region Name used by more than one region, and every region with no
name at all.

An Arrangement refers to regions **by name**, so names must be unique and
non-empty before any Arrangement action will run. That is this suite's rule, not
REAPER's — REAPER is perfectly happy with three regions called `Take 1`. This
action is how you find the violations.

Run it first on any project you have not repacked before.

---

## Show each track's timebase

**Needs:** nothing.
**Changes:** nothing.

Lists every track with its timebase, as REAPER reports it, plus a tally.

Timebase decides whether editing the tempo map moves material. Beat-based
material stores its position in quarter-notes, so its absolute time is *derived*
from the tempo map and shifts when a tempo marker changes; time-based material
does not move. Since a Repack writes tempo markers, this distinction is what
makes some projects safe to Repack and others not.

Use it to answer "which tracks do I need to change?" — though `Check an
Arrangement` will also name the specific offending items.

---

## Show bar lines and Padding for every region

**Needs:** at least one region.
**Changes:** nothing.

For every region, prints where its bounds sit relative to the bar grid and how
much Padding a Repack would add.

This exists because the bar-line arithmetic is the least verifiable part of the
suite, and REAPER is the only thing that can confirm it. It asks REAPER exactly
the two questions a Repack depends on and prints the raw answers. Run it when
you want to see the grid itself rather than a verdict about an Arrangement.

---

## Capture the current region order as an Arrangement

**Needs:** a saved project, at least one region, unique non-empty Region Names.
**Changes:** writes `<Project>.arrangements.lua`. No project state, no undo point.

Writes the project's regions, in timeline order, into the sidecar as a named
Arrangement. Prompts for the name, and asks before replacing an Arrangement that
already exists.

This is how you seed a sidecar from a project you have already laid out by hand.
It is one of only two Arrangement actions REAPER gets — authoring and reordering
happen in a text editor, deliberately ([ADR-0003](adr/0003-arrangements-as-name-keyed-lua-sidecar.md)).

**After it runs, the next step is a text edit**, and the success dialog spells it
out: duplicate the block, rename the copy, reorder the copy. Editing a duplicate
rather than the original leaves the captured Arrangement intact as a record of
how the project was laid out — and applying it gets you back there.

---

## Check an Arrangement before applying it

**Needs:** at least one region. Everything else it reports on rather than
requiring.
**Changes:** nothing. No project state, no undo point.

Prompts for an Arrangement name and reports everything knowable about applying
it, in three sections.

### 1. Would refuse

Everything that would stop a run — **all of them, not just the first**, so one
check is one round trip:

| Code | Meaning |
|---|---|
| `project_unsaved` | The project has never been saved, so the sidecar and log have nowhere to live |
| `sidecar_missing` | No `<Project>.arrangements.lua` yet |
| `sidecar_invalid` | The sidecar exists but will not parse — usually a hand-edit typo |
| `arrangement_unknown` | That name is not in the sidecar. Lists the names that are |
| `arrangement_missing_regions` | The Arrangement names a region the project does not have — a misspelling |
| `region_names` | Duplicate or unnamed regions |
| `tempo_env_beats` | Project Settings → "Timebase for tempo/time signature env" is `Beats` |
| `plan_refused` | The Repack itself cannot be planned — an item on an unsafe timebase, Padding that would run a region into its neighbour, or a Headroom that would shrink a region past its contents. Every offending region is named, with the largest shrink each could legally take |

An Arrangement that *omits* a region is **not** in this list. That is supported,
and it is the difference between a misspelled name (an error) and an absent one
(an instruction).

### 2. Would happen, and running again will not undo it

| Code | Meaning |
|---|---|
| `headroom` | Regions whose end this Arrangement adjusts, with what you asked for, what it resolves to in seconds and bars, and the end before and after. **Listed even when a request resolves to no change** — anything under half a bar does, and a region quietly missing from the list would read as a check that had not noticed the edit |
| `parked` | Regions this Arrangement omits, which will be moved beyond the packed material. Named individually |
| `padded` | Regions that will be extended to the next bar line, with the exact amount each |
| `dropped` | Material and envelope points touching no region, which will be **discarded**. Named individually |
| `cut` | Straddling Items that will be cut, by track and position |

### 3. What this check cannot see

Not boilerplate — read it. A run writes a **Tempo Anchor** at every region start
*first*, and those anchors are what put region starts on bar lines. The bar grid
they create does not exist until they are written, so:

- **On a project whose Tempo Anchors are already present** (any project you have
  already repacked), the current grid *is* the grid a run would plan against, and
  the Padding and Headroom figures are **exact**.
- **On a first run**, they are an **estimate**. The report says which case you
  are in. Headroom is affected for the same reason Padding is: it resolves to a
  bar line, so it moves with the grid.

Measured on a real 19-region project, the estimate matched the eventual figures
to the millisecond — but that held because those regions' starts did not change
tempo under the Repack. A region whose start lands on a different tempo has a
different bar length than the pre-anchor grid predicted, and there it will drift.

Also invisible until the anchors are written: whether writing them moves
beat-attached material, and whether Padding then runs a region into its
neighbour. A run refuses on both.

---

## Apply a named Arrangement

**Needs:** a saved project, at least one region, unique non-empty Region Names, a
readable sidecar, a known Arrangement name, every named region present, and the
tempo envelope on a `Time` timebase.
**Changes:** **the project.** One undo point per run.

Repacks the project into the Arrangement's order. Runs immediately, with no
confirmation prompt — **unless the Arrangement carries a non-zero Headroom**,
which is the one exception in the suite.

### The Headroom prompt

Headroom is relative, not absolute: it moves a region's end from wherever that
end currently is, so applying the same Arrangement twice moves it twice. Nothing
in the finished project records that it happened, and `Verify` cannot detect it
— so this dialog is the whole of the guard
([ADR-0007](adr/0007-headroom-is-relative-not-absolute.md)).

It lists every region and the seconds it will gain or lose, and offers three
answers:

| Answer | What happens |
|---|---|
| **Yes** | Repack, and apply the Headroom |
| **No** | Repack only, treating every Headroom as zero |
| **Cancel** | Nothing at all. Nothing is written before you answer |

It fires whenever **any** Headroom in the Arrangement is non-zero — not only
when the Arrangement already matches the timeline. A re-run after a small manual
edit produces a plan that does not match, so the narrower trigger would be
missing in the commonest way to double-apply. An all-zero Arrangement shows no
dialog and behaves exactly as it did before the feature existed.

The seconds shown are the ones you typed, not what they resolve to: on a first
run the bar grid does not exist yet, so nothing could be resolved without
writing the Tempo Anchors first — and then "Cancel" would no longer be true.
`Check` and the run log are where the resolved figures live.

### What it moves

Regions, the plain markers inside them, the tempo and time-signature markers and
envelope points inside a moved region, and media items fully contained in one —
all by the same amount.

### The two phases

The run is two phases inside **one** undo block:

1. **Tempo Anchors.** An explicit tempo and time-signature marker is written at
   every region start, recording the tempo that region *already* starts at. This
   is what puts every region start on a bar line, and it is tempo-neutral — the
   project sounds the same afterwards.
2. **The Repack.** Only now can Padding, placement and everything carried be
   planned, because only now does the bar grid exist.

A consequence worth knowing: a phase-2 refusal arrives with the anchors already
written. They are still a single undo step, the message says so, and they are
correct in their own right.

### What it refuses on

Everything in the check's "would refuse" list. Additionally, if writing the
Tempo Anchors moves any media item — which means beat-attached material followed
a tempo-map edit — the run stops before planning anything against the moved
timeline, and names what moved. Refusing there is the point: the alternative is
not a worse Repack, it is a silent one.

### What it does not refuse on

- **An Arrangement naming a subset** of the project's regions. The omitted ones
  become Parked Material.
- **A Straddling Item.** It is cut, and the piece left outside every region is
  discarded.

### Output

- A dialog summarising what happened, with Headroom, Padding, anchors, parking
  and discards called out separately from the counts.
- The full plan to the console, and appended to `<Project>.arrange.log`. Headroom is
  logged with the **resolved** seconds and bars beside the request, so the line
  matches the timeline — and it is the only record of why a region is a
  different length than it was recorded at.
- An Arrangement that already matches the timeline produces **no undo point and
  no log entry** at all. That still holds after answering "repack only" to the
  Headroom prompt.

---

## Verify the timeline against an Arrangement

**Needs:** a saved project with a readable sidecar, at least one region, and a
known Arrangement name.
**Changes:** nothing. No project state, no undo point.

Checks that the timeline holds the four properties a Repack promises:

- the regions the Arrangement names appear in that order
- they are contiguous, starting at the beginning of the timeline
- every one of their starts lands on a bar line
- the regions the Arrangement omits sit beyond the packed material

**It derives all of that from the project as it now stands, never from the plan
that produced it** — which is the whole reason to run it. Re-applying an
Arrangement and being told "already matches the timeline" tests Apply against
itself, and a Repack that was self-consistently wrong passes that test. This
asks the project instead.

Because it needs nothing but the current timeline, it works on a project you
packed in an earlier session — unlike undo, which does not survive one.

Naming a *different* Arrangement than the one you applied is legitimate: it
answers "which Arrangement does this timeline actually match?"

### What it cannot see

One thing, stated in the report rather than left implied: **whether a Headroom
was applied once or twice.** A timeline whose Headroom was double-applied is
bar-aligned, contiguous and in Arrangement order exactly like a correct one, and
nothing in the project records how many times an end was moved. Recording
applied lengths in the log and diffing against them was rejected — it would make
this trust the plan it exists to check
([ADR-0007](adr/0007-headroom-is-relative-not-absolute.md)). Apply's prompt is
the guard; a PASS here is not.

### Failure codes

| Code | Meaning |
|---|---|
| `region_absent` | The Arrangement names a region the project does not have |
| `order_mismatch` | The regions are not in Arrangement order. Reported alone — nothing else is meaningful once this is true |
| `block_start` | The packed regions do not start at the beginning of the timeline |
| `gap` | The packed regions are not contiguous |
| `overlap` | Two packed regions overlap |
| `off_bar_line` | A packed region's start is not on a bar line, with the actual and expected positions |
| `not_parked` | A region the Arrangement omits is still sitting inside the packed material |

Float noise is not a failure: the tolerance is the planner's own, so this never
fails a run the planner considers clean.
