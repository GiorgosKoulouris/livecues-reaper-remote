# Repack is bar-aligned, and works on any timebase

Repack must work on every project, including tempo-varying and beat-based ones.
Regions of differing tempo cannot be packed end-to-end in both seconds and bars,
so the chosen invariant is **bar alignment**: every region begins on a bar line in
the repacked timeline.

Two mechanisms make this well-defined:

- **Padding.** A region whose length is not a whole number of bars has its end
  extended to the next bar line, so regions stay contiguous. Region audio is never
  trimmed and never overlapped. Padding is idempotent — an already-padded region is
  a whole number of bars, so a later Repack pads it by zero.
- **Tempo Anchors.** REAPER tempo is inherited, not stored per region, so a moved
  region would otherwise adopt whatever tempo its new predecessor left in effect.
  Before anything moves, the planner writes an explicit tempo and time-signature
  marker at every region's start, making each region self-contained under any
  reordering.

## Considered options

Preserving seconds durations (transplanting each region's tempo slice and
re-deriving QN positions) was rejected: it keeps audio timing identical but leaves
region starts off the bar grid, which is the wrong trade for a bar-based editing
workflow. Repacking in QN was rejected because time-based audio would drift.
Requiring a time-based project was briefly adopted and then reversed — the suite
should not refuse MIDI projects.

## Consequences

- Bar lines in the new timeline derive from the transplanted tempo and
  time-signature map, so snapping region N forward shifts the grid region N+1
  snaps to. **Placement is sequential, left to right** — it cannot be batched.
- Regions permanently grow the first time they are padded, and their bounds then
  include trailing silence. This is expected.
- The project gains Tempo Anchors it did not have — one per region, visible in the
  tempo envelope, even in a single-tempo project.
- This is the least verifiable code in the suite. It is covered by the golden
  fixture pairs described in ADR-0005, which is what makes it tractable at all.
