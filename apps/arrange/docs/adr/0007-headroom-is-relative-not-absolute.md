# Headroom is relative, not absolute

An Arrangement entry may carry **Headroom**: an adjustment to that region's end,
in seconds, resolved to the nearest bar line. `headroom = 4` means *add about
four seconds to this region's end*, measured from wherever that end currently
sits — **not** *make this region four seconds longer than it was recorded*, and
not *leave exactly four seconds after the last item*.

The consequence is deliberate and is the whole of this decision: applying the
same Arrangement twice moves that end twice. Headroom is the first operation in
this suite that is intentionally not idempotent, and
[`HANDOFF.md`](../../HANDOFF.md)'s central rule — that a single clean run proves
nothing — is precisely the rule it breaks.

## The alternative that was rejected

An **absolute** Headroom — a target length, or a target amount of silence after
the last item — is idempotent by construction. Applying it twice reaches the
same timeline, `is_empty` stays honest, a repeat run leaves no undo point, and
`Verify` could check it directly. On every axis this repo usually cares about,
absolute is the better answer.

It was rejected because it does not express the thing the user is actually
doing. Adjusting a set is iterative and comparative: *this one needs two more
bars of air*, judged by ear against the song before it. That is a change, and it
is stated as a change. Under an absolute rule the same intent has to be
expressed as a length — which means first finding out what the region's current
length is, in seconds, off a bar grid the tempo map decides, and re-deriving it
by hand every time Padding or an earlier edit moves the end. The file stops
being something you can edit by ear and becomes a set of measurements to keep in
sync with the timeline.

There is a second, quieter cost. An absolute value is only meaningful against
the geometry it was written for, and nothing in the sidecar records what that
was. A `length = 42.0` copied between Arrangements, or left behind after the
region was re-recorded, is silently wrong in a way `+4` cannot be.

## What compensates for it

**The confirmation prompt on Apply is the entire guard, and it exists only
because of this decision.** It fires whenever *any* Headroom in the Arrangement
is non-zero — not only when the Arrangement otherwise matches the timeline,
which was considered and rejected: a re-run after any small manual edit produces
a plan that does not match, so the narrower trigger would be absent in the most
common way to double-apply. It offers three answers, and the middle one exists
so that the prompt is not a wall: apply it, repack with every Headroom treated
as zero, or cancel with nothing written.

An Arrangement whose Headroom is all zero shows no dialog at all, which keeps
`CLAUDE.md`'s "scripts run immediately, with no confirmation prompt" true of
every run that behaves like the ones before this feature existed.

## Consequences

- **`Verify` cannot catch a double application, and says so.** A timeline whose
  Headroom was applied twice is bar-aligned, contiguous and in Arrangement
  order, exactly like a correct one. Recording applied lengths in the run log
  and diffing against them was rejected: it would make `Verify` trust the plan
  it exists to check, which is the property that made it worth writing
  ([ADR-0005](0005-golden-rpp-fixtures.md), issue #19).
- **The run log carries the resolved figures**, not the requested ones, because
  the log is the only record of a length change the project afterwards cannot
  explain.
- **The non-idempotence is pinned by a test**, in the golden fixture's
  applied-twice block, rather than left as prose. If a later change makes
  Headroom absolute, that test fails and says which property went away.
- **`0` means exactly today's behaviour**, which is why the adjustment is
  measured from the *padded* end rather than the raw one. From a raw end a
  nearest-bar rule would round *down* and trim audio off a region nobody asked
  to shorten. Pad first, then move.
- **Absolute lengths remain the obvious future direction** if the prompt proves
  insufficient in practice. Nothing here forecloses it; the sidecar would gain a
  second, differently named field rather than changing what `headroom` means.

## What a shrink may not do

A negative Headroom may only ever remove silence. The floor under a region is
the later of the bar line at or after the last content of *any* kind inside it —
item end, plain marker, envelope point or tempo marker — and one bar after the
region start. Below that the whole run refuses, naming every offending region
and the largest shrink each could legally take.

Covering every content kind, not just items, is what keeps the coordinate
decision safe. A region's bounds change only as it is laid into the Packed
Block; membership, Straddling Item cuts and Dropped Material are all still
decided against the region's original bounds. That is what stops a *grown*
region from capturing the following region's material, and it is what stops the
existing overlap refusal — which would otherwise abort on any project whose
regions sit back to back — from firing on a Headroom. In the shrinking
direction, the same frozen membership means anything left past the new end
travels with the region and lands inside whatever the Repack puts next. The
floor is what makes that impossible.

Clamping to the floor instead of refusing was rejected for the reason this repo
refuses elsewhere: a Repack is hard to unpick by hand, and a silently reduced
shrink is a wrong result that looks like a right one.
