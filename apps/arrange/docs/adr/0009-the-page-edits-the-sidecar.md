# The page edits the sidecar

Amends [ADR-0003](0003-arrangements-as-name-keyed-lua-sidecar.md). Decided in
the phase 2 grilling, 2026-11-07 (`.scratch/arrange/spec.md`, "Phase 2").

ADR-0003 made a text editor the only place an Arrangement is authored: REAPER
got two actions, Capture and Apply, and reordering, subsetting and Headroom were
text edits. The web page (`lcrr-arrange.html`) now edits Arrangements too:
reorder, add and remove regions, Headroom, New, Duplicate, Rename, Delete.

## What stays

The **storage** decision stands: one Lua sidecar beside the project, keyed on
Region Name, read in a sandbox and validated, with the unique-name invariant,
no repeats, and unknown fields refused. Editing by hand in a text editor stays
supported. There is no second store and no machine-owned file: two stores
would need a rule for which one wins, and the user would have to know it.

## What changes

- **The page is a second authoring surface**, through the bridge and a new
  headless core (`lib/core/edit.lua`, ADR-0008) that only the bridge fronts.
  Each edit is one small operation, saved at once. That keeps every request
  under the bridge's ~900-character limit, so no chunk protocol is needed.
- **A write rewrites the whole file from tables, and hand-written comments are
  lost.** That was already true of Capture. Preserving them would mean editing
  Lua source text in place, which is fragile; the cost was judged not worth it.
  Instead, **any write to a file that isn't in canonical form (what `serialize`
  would produce) asks first**, from the page and from the dialog Capture
  alike, and the generated header says comments are not kept.
- **Nothing is overwritten blind.** Every edit carries a revision (a fingerprint
  of the file's exact text) and the project path it was made against. A
  mismatch is refused and the page reloads. A file that won't parse is never
  written by the page.
- **The check token binds the checked Arrangement's contents**, not only its
  name, so an edit between Check and Apply makes Apply refuse
  (`arrangement_changed`).
- **Undo for sidecar edits is the page's**, since REAPER's Undo doesn't cover
  the file. New, Duplicate, Rename and Delete go into the run log; Delete
  can't be undone and asks first.

## Consequences

- ADR-0003's last consequence ("Authoring and reordering happen in the editor,
  not in REAPER") no longer holds for the page. It still holds for REAPER's
  Action list: there is no edit script, and no ReaImGui dependency.
- ADR-0003's reason for writing `headroom = 0` explicitly ("the sidecar is the
  only place the feature can be discovered") is weaker now that the page shows
  Headroom. The explicit form stays anyway, to avoid a reformat diff on every
  existing sidecar.
- Headroom stays relative (ADR-0007). The page shows it as a signed change, and
  after an Apply that applied Headroom it offers, never forces, to clear it.
