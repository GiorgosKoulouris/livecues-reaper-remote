# Arrange

A personal suite of ReaScript (Lua) scripts for REAPER that automate repetitive
project-state work — chiefly rearranging regions and the media they contain.

## Language

### Timeline

**Region**:
A named span of time in a project, delimited by a marker pair. It has a position
in time, but no inherent order.
_Avoid_: section, marker, part

**Region Name**:
A region's user-visible name, and the only handle an Arrangement uses to refer to
a region. Required to be unique within a project.
_Avoid_: label, title

**Region Number**:
REAPER's own user-visible per-region index (`markrgnindexnumber`). Deliberately
not used as identity here, because it is user-editable and reassigned when
regions are recreated.
_Avoid_: region id, index

**Straddling Item**:
A media item that crosses a region boundary — one that begins or ends inside a
region but not both. Includes items that cover a region entirely.
_Avoid_: overlapping item, spanning item

**Loose Item**:
A media item lying outside every region, such as a count-in or a stray take.
Includes the piece a Repack's own splitting leaves beyond a region's end. A
Repack discards these rather than moving them — see Dropped Material.
_Avoid_: orphan item, unregioned item

### Ordering

**Arrangement**:
A named, ordered list of Region Names describing a desired sequence of regions.
Stored beside the project and independent of the timeline, so several
Arrangements of the same project can coexist. May name a subset of the project's
regions.
_Avoid_: playlist, order, sequence, version

**Repack**:
Laying regions back down in a given order, carrying their contents with them, so
that each one begins on a bar line and no gaps remain between them.
_Avoid_: reorder, rearrange, sort, move

**Padding**:
The extension of a region's end to the next bar line, so that its successor can
begin on a bar line without a gap. Adds silence inside the region's bounds and
happens at most once per region.
_Avoid_: alignment, quantising, snapping

**Headroom**:
The trailing silence at a region's end, and the per-region adjustment to it
that an Arrangement carries — in seconds, deliberate, and authored by hand.
Distinct from Padding, which is involuntary and rounds up to the next bar line
whether asked for or not: Headroom is what the user asks for *on top of* that,
and the resulting end is itself rounded to the nearest bar line. Unlike every
other operation here it is **relative** — it describes a change to the end
rather than a length to reach — so applying an Arrangement twice adjusts twice.
Never called *delta*: throughout the planner and the run log that word already
means how far something moved along the timeline.
_Avoid_: delta, tail, stretch, trim, gap

**Tempo Anchor**:
An explicit tempo and time-signature marker written at a region's start, so the
region carries its own bar grid and is unaffected by whatever precedes it.
_Avoid_: tempo marker, tempo point

**Automation Anchor**:
An envelope point written at a region's bound, carrying the value that envelope
already held there, so the region keeps its own automation instead of inheriting
whatever the Repack puts in front of it. The Tempo Anchor idea applied to
automation, and named to match.
_Avoid_: automation point, envelope anchor

**Packed Block**:
The contiguous run of regions produced by a Repack, beginning at the start of the
timeline.
_Avoid_: arrangement, edit, sequence

**Parked Material**:
Everything a Repack kept but did not place in the Packed Block — regions the
Arrangement omits, the markers, items and envelope points inside them, and
every tempo/time-signature marker that is not inside a region the Arrangement
places — relocated beyond the Packed Block by a single shared offset that
leaves its internal timing intact. Material is parked because it still
belongs to a region; material belonging to no region is Dropped instead —
**except tempo markers**, which park even when they sit in a gap that belongs
to no region at all, because a Repack closes that gap, and unlike deleting an
item, deleting a tempo marker can silently reposition beat-based material
elsewhere on the timeline. Envelope points carry no such hazard — deleting one
repositions nothing else — so a homeless envelope point follows the general
rule and is Dropped, not parked; only an envelope point that still belongs to
a region (one the Arrangement omits) parks with it. Every Parked category is
written as of issue #7; tempo markers were the only one for a while, which is
why so much of the design writing treats them as the exception.

A parked region keeps its own tempo. Tempo Anchors are planned for *every*
region in the project, not only the ones an Arrangement places, so an omitted
region's start already carries a marker by the time parking happens — and that
marker is itself homeless, so it parks by the same offset and stays on the
region's start. The offset is the whole of parking's contract: negating it
reverses the operation, and it is recorded in the run log for that reason.
_Avoid_: excluded, discarded, outtakes, junk

**Dropped Material**:
Everything a Repack discarded outright: media touching no region at all,
whether it was already lying loose or is the tail a Repack's own splitting left
beyond a region's end — and, the same rule extended to automation, any
envelope point touching no region at all either. A Repack is run on a project
that has already been cleaned up, so material outside every region is spent.
The run log records each piece — and each dropped envelope point, by track,
envelope and position — because afterwards the project does not.
_Avoid_: deleted, removed, trimmed, garbage
