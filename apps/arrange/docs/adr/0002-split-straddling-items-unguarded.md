# Straddling items are split, without guards

A Repack splits every item crossing a region boundary, on every track, so each
region carries exactly its own audio. Membership by item-start-position, strict
containment, and aborting on straddlers were all considered and rejected:
splitting is the only rule that keeps a repacked arrangement musically clean.

Guards were considered and deliberately rejected — no track scoping via
selection, no exemption for items that span a region entirely, no track-name
exclusion convention. A single undo point per run, plus the logged plan, is the
accepted safety net.

## Amendment (2026-07-30): only regions that actually move are cut at

"Every item crossing a region boundary" is narrowed to **every item crossing a
boundary of a region this run moves**. A region that stays where it is carries
its contents by not moving them, so cutting its straddlers edits audio for no
benefit the same plan can point at — and on a real 32-track session that meant
cutting items in regions the run never touched.

Everything else stands. A straddler of a *moving* region is still cut on every
track, with no exemption for an item spanning a region entirely, no track
scoping and no name convention. The rejected alternatives above were rejected
for reasons this does not disturb.

The rule is enforced in `lib/regions.lua` by `moving_boundaries`, which is the
only source of cut positions. The consequence below about reference tracks and
ambience beds still applies — to every region the Repack moves, which in a
full Repack is usually all of them.

## Consequences

- Running a Repack on a project containing a full-length reference track or
  ambience bed will dice that track at every region boundary. This is expected
  behaviour, not a bug.
- Splitting through a crossfade destroys it.
- Cut edges get a short fixed fade (a named constant in `lib/`, default 5 ms)
  while the item's original outer fades are preserved. The suite defines this
  rather than inheriting REAPER's split preference, so behaviour is reproducible
  across machines and predictable from the plan alone.
  **True in the code as of issue #15.** `apply.splits` writes `D_FADEINLEN` /
  `D_FADEOUTLEN` — the *manual* fade lengths, confirmed primary in
  `research/reaper-scripting.md` §4.3a — on the two edges each cut creates, and
  on nothing else. Length only: the fade *shape* and curvature are equally
  preference-derived and are still inherited, because this bullet specifies a
  length and nothing more. Not yet observed in real REAPER (`docs/limitations.md`).
- The piece a cut leaves outside every region is **discarded**, not moved —
  Dropped Material (`CONTEXT.md`), decided 2026-07-30. For a tail that is a
  song's ring-out, that means the ring-out is destroyed, not merely separated
  from its song. A Repack is run on a project that has already been cleaned up,
  so material outside every region is taken to be spent. Extending the region
  to swallow a tail worth keeping is the way to keep it, and has to be done
  before the run. Undo and the run log are the safety net, as everywhere else
  in this suite.
