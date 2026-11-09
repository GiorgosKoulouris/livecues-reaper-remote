# Arrangements live in a name-keyed Lua sidecar

> Amended by [ADR-0009](0009-the-page-edits-the-sidecar.md): the web page is now a second authoring surface. The storage decision below stands.

An Arrangement is stored beside the project (`MySong.RPP` →
`MySong.arrangements.lua`) as a Lua file returning a table, read with `load()` in
an empty environment. A sidecar was chosen over project ExtState because the file
is hand-editable in an ordinary editor, diffable, and versionable; a Lua table was
chosen over JSON because Lua has no built-in JSON parser, and over a line-based
format because it nests without a format change.

Arrangements key on **Region Name**, not on `markrgnindexnumber`. REAPER's region
number is user-editable and reassigned when regions are recreated, so it is not
the stable identifier it appears to be. `AddProjectMarker2`'s official description
confirms this directly: `wantidx` is a *request*, and "you'll get a different index
number if wantidx is already in use."

An entry is either a bare Region Name or a table carrying the name positionally
alongside a `headroom` field — the per-region end adjustment, in seconds
([ADR-0007](0007-headroom-is-relative-not-absolute.md)):

```lua
return {
  ["Full"]  = { { "Intro", headroom = 0 }, { "Verse 1", headroom = 4 } },
  ["Radio"] = { "Intro", "Chorus" },  -- still valid, headroom 0 throughout
}
```

A bare string means a Headroom of `0`, so every sidecar written before that
feature existed keeps its exact meaning. `Capture` writes the table form with an
explicit `headroom = 0` on every entry, at the cost of a one-time diff when an
existing project is re-captured: the sidecar is the only authoring surface, so
it is also the only place the feature can be discovered.

## Consequences

- Keying on names forces a **unique-region-name invariant**, which REAPER itself
  does not require. Every script touching Arrangements validates it first and
  aborts listing the duplicates. This check is not optional decoration — names
  are the primary key.
- The same invariant rules out **empty names**. A region with no name is no more
  addressable than a duplicated one, so it is a precondition failure on the same
  footing, not a region that silently becomes Parked Material. A name that is
  only whitespace counts as empty: REAPER's ruler renders it identically to a
  blank one, so treating it as a distinct key would hide the collision the
  invariant exists to catch. `prj/`'s live project contains one such region.
- An Arrangement may name a **subset** of the project's regions, but may not name
  the same region **twice**: one region cannot occupy two slots on one repacked
  timeline, so the sidecar rejects the repeat at parse time rather than letting
  the planner pick a winner.
- Arrangements require a saved project, since an unsaved one has no path to sit
  beside. Scripts abort with a message rather than falling back to another store.
- A sidecar does not follow a Save As or a rename. Recovery is manual: when no
  sidecar is found for a project that has regions, the script offers to import
  one via `reaper.GetUserFileNameForRead` (vanilla, no extension needed).
- The parser **normalises both entry shapes to one**. What it returns is what an
  Arrangement has always been — a dense array of Region Name strings — with the
  Headroom carried beside it on a `headroom` field keyed by Region Name. So
  every consumer that only wants the order needs no knowledge of Headroom at
  all, and the one that does reads a single table rather than re-deriving it
  from mixed entry types.
- A field the parser does not recognise is **refused, not ignored**.
  `{ "Intro", headrom = 4 }` is a plausible typo whose only other outcome is a
  Repack that silently does nothing to the region being edited.
- Authoring and reordering happen in the editor, not in REAPER. REAPER gets only
  two dependency-free actions — capture the current region order, and apply an
  Arrangement by name — which is why no ReaImGui dependency exists.
