# Decisions that look like bugs

Each of these was chosen against alternatives, several after a real REAPER run
proved the obvious version wrong. Read the entry — and the ADR it names — before
"fixing" any of them. Vocabulary is [CONTEXT.md](../CONTEXT.md)'s.

## Design choices

- **Every Straddling Item is split, on every track, with no scoping and no
  exemption for items spanning a whole region** — reference tracks and ambience
  beds included (ADR-0002).
- **Region names must be unique and non-empty, and a run aborts otherwise**, an
  invariant REAPER itself does not impose (ADR-0003).
- **Padding grows a region out to the next bar line**, permanently, putting
  silence inside its bounds (ADR-0004).
- **Headroom is relative, so applying an Arrangement twice moves those ends
  twice** (ADR-0007). The only non-idempotent operation here, and the only
  confirmation prompt. Do not "fix" it into a target length without reading the
  ADR — the idempotent version was on the table and rejected for a reason.
- **A Headroom is measured from the *padded* end, not the raw one.** Forced, not
  chosen: `0` has to change nothing, and from a raw end a nearest-bar rule would
  round *down* and trim audio off a region nobody asked to shorten.
- **A Headroom changes only the length a region is laid down with, never its
  `bounds`.** Membership, cuts and drops stay decided against original bounds,
  which is what stops a grown region capturing its neighbour's material and
  stops `pad_regions`' overlap refusal firing on every back-to-back project.
- **A blocked shrink refuses the whole run rather than clamping.** The floor
  covers the last content of *any* kind in the region — item, marker, envelope
  point, tempo marker — because frozen membership means anything past the new
  end travels with the region into the next one.
- **A Tempo Anchor is written at every region start**, adding tempo markers to
  projects that had none (ADR-0004).
- **The planner/applier split.** Collapsing it removes the only test coverage an
  operation has (ADR-0001).
- **`expected_plan.lua` is not redundant beside `after.rpp`**: it is the
  planner's prediction, and the pair is the proof (ADR-0005).

## Tempo

- **`apply.tempo_moves` reorders its writes instead of following the plan,
  overwrites the marker at the timeline origin, and verifies the result two
  ways.** Three measured REAPER facts force it (research §4.4a, ADR-0006): two
  markers cannot share a position and writing onto an occupied one silently
  destroys a marker (4 in, 3 out); the origin always carries a marker and cannot
  be vacated, so ordering alone deadlocks; and neither failure is visible
  per-marker, because every marker named is found and written. **It was a
  straight loop twice, and lost a marker both times.**
- **A Tempo Anchor takes its values from a tempo marker coincident with the
  region start (within `BOUNDARY_TOLERANCE`), and only otherwise from the
  oracle** (#19). A *narrowing* of "take the tempo from the oracle", not a
  reversal — the oracle still owns the mid-ramp case. Both original spec cases
  must keep passing unmodified; if either has to change, the fix has overreached.
- **…except the time signature, which falls back to the oracle when the marker
  has none.** A tempo-only marker reports `-1/-1`, and `0/0` reaching
  `SetTempoTimeSigMarker` means "keep the previous signature" (research §4.4a) —
  either way the region start stops being a bar line. A marker that *does* carry
  a signature still wins: 7/8 at a region start must not become 4/4.
- **A Tempo Anchor inherits `lineartempo` from the marker in effect**, rather
  than being square. Always-square flattens a ramp it lands inside and drags
  beat-based material; always-linear invents one. **Deliberately the opposite of
  Automation Anchors' "always square"** — there the preceding point is always
  outside the region, here the flag describes the segment the anchor subdivides.
  Reasoned, not observed.
- **A homeless tempo marker is folded into `tempo_moves` rather than staying in
  `plan.parks`**, unlike every other Parked category, or it is reported twice.
  It parks even when it belongs to no region, because deleting or stranding one
  silently repositions beat-based material.

## Automation

- **`apply.envelope_anchors` deletes every point at an anchor's time before
  writing, and groups anchors by time to do it.** Inserting unconditionally made
  a second Repack add a duplicate point at every shared bound, and where two
  points share a time the last wins — so `0, 1` became `0, 1, 0` and **the value
  in effect silently flipped**. Grouping preserves the deliberate two-point step;
  replacing per anchor would collapse it.
- **A start anchor is suppressed only when no *end* anchor claims the same final
  time.** ADR-0006's rule holds for an isolated region start, but packed regions
  share bounds, and there the earlier region's end anchor clears the time anyway.
- **`plan_pack` does not plan an `envelope_drop` for a point an anchor will
  occupy.** Doing so is net-neutral *only* because `apply.plan` orders drops
  before anchors — resting a delete and a write at the same instant on applier
  ordering is what becomes data loss when someone reorders it.

- **Envelope points are lifted before the tempo map is touched and put back after it** (issue 10). `apply.lift_envelope_points` deletes every point the plan moves (normal and parked), found by its original `from`, and `apply.envelope_moves` inserts them at their absolute `to` with the plan's value, shape, tension and selected, unsorted, then sorts each envelope once. Looks like a roundabout `SetEnvelopePointEx`; it is not. On a beat-timebase track (`BEAT 2`, the whole of `Rehearsal_Current`) a point follows the tempo map exactly as an item does, so `apply.tempo_moves` drags it off the time the plan recorded and the old re-locate-by-time failed ("could not find the envelope point to move ... at 275.600s") after the map was already rewritten, leaving the project half changed. An item can be located by handle first (`apply.locate_items`); a point has no handle, only a sorted index, so it is taken off the timeline instead. Step pairs: each plan entry deletes the first point left at its `from`, and entries are inserted in plan (read) order, which `project.sort_by_position` keeps; do not sort the lift or the insert. `apply.envelope_anchors` is unchanged and still runs last, clearing its own times, so an anchor still wins over a moved point that lands on its time. Points the plan does not move (a region whose delta is 0) are not lifted and so still follow a tempo write; nothing in the plan makes that happen today, since a tempo write only follows a region move.
- **A failure after the plan was logged is logged too** (issue 10, ADR-0008). The core appends `RUN FAILED: <error> -- every step after the failing one was not done ...` to the run log (`text.failure_line`) and re-raises, for either front end. A failure while the Tempo Anchors are being written happens before phase 2 can be planned, so the plan is not logged yet but the tempo map may be half rewritten: that failure gets its own heading and the same `RUN FAILED` line. Any other failure before the plan is logged writes nothing, since nothing was changed. The page's `internal` message no longer says "Nothing may have been done": the run stopped partway, the changes before the failure are one REAPER undo step (Ctrl+Z), and the log says whether it failed. The dialog front end does not catch the error (REAPER shows its own script-error box), so it has no wording of its own to keep in step.

## Tolerances and no-ops

- **The snapshot's sorts break ties by read order (`project.sort_by_position`).** `table.sort` is not stable, and for envelope points the order of two points at one time is data: the last is the value in effect. An unstable sort made `value_at_bound` read the wrong half of a step pair, on the first run as well as the second (issue 02). Do not swap it for a plain `table.sort`. Specs with in-order fakes cannot see the difference; `project_spec` has a case big enough to.

- **Region boundaries within `BOUNDARY_TOLERANCE` collapse to one cut.** Two
  regions can meet microseconds apart (measured: `8.07e-06 s`), and cutting at
  both asks REAPER for a **0.39-sample** fragment, which aborts the run.
- **The pad threshold is `BOUNDARY_TOLERANCE` (1e-4), not `EPSILON`.** It
  compares a bar line REAPER computed against a region end a human dragged; real
  ends miss by up to ~1e-5 s, so at `EPSILON` the oracle returns the *next* bar
  and Padding invents a **whole bar** — which also aborts on the overlap check
  and breaks ADR-0004's idempotence claim. Genuine pads run 0.211–1.836 s.
- **`plan_anchors`' `redundant`/`is_noop` is not the skipping ADR-0004 forbids.**
  Every region is still anchored, planned, logged and written; the flag answers
  whether the writes would change the map at all.
- **Automation Anchors carry the same flag, decided per *time*, not per anchor**
  (#13), because the applier clears a time and writes the whole group — so a
  shared bound's step pair is redundant only if both halves match, in order.
  **`selected` is excluded on purpose**: the applier writes anchors unselected,
  so counting it would end the no-op whenever the user had clicked a point.
- **A Headroom under half a bar resolves to no change, and is still reported.**
  The nearest-bar rule makes this the likeliest "nothing happened", so the check,
  the summary and the log all name the region with a resolved value of zero
  rather than omitting it.
- **`plan.parks` comes back empty when nothing needs to move**, rather than
  listing zero-offset entries. The user's explicit choice; it is what keeps a
  repeat Repack a clean no-op.
- **`PARK_GAP` is 300 s**, up from 30, where it read as an ordinary gap between
  songs. Express distances in specs as `regions.PARK_GAP + n`, never a literal.

## Structure

- **The bridge silences REAPER's console and keeps the log file** (ADR-0008). Looks like dropping a log line; the file is the only record of Dropped Material, and the console would open a window on the host the page must never touch.
- **A Check mints its token only when it would proceed, and Apply is a plain button.** No hold-to-apply: the token already makes Apply follow a Check and be used once, and the suite's rule is that scripts run immediately with Undo and the logged plan as the safety net. The Headroom question is the one confirmation, as in the dialog front end.

- **The run log is written by the core, not by the dialog front end**
  (ADR-0008). It looks like presentation, but for Dropped Material it is the
  only record, so a run from any front end must write it, and Apply writes it
  *before* the applier runs so a failed run still has one. Only the wording
  lives in `lib/text/`.
- **A core asks for confirmation by returning `status = "confirm"` and
  writing nothing, and the front end calls it again with the answer**
  (ADR-0008). The checks run twice, and that is deliberate: it is what lets
  one core serve a dialog and a web page without a callback into either.

- **`lib/project.lua` keeps `EnumProjectMarkers3` as a fallback** after #11
  switched the reader to `GetRegionOrMarker`. It also fires on a *short* read:
  "by internal index" does not promise `0 .. count-1` addresses every entry
  (research §4.1d), and a snapshot missing regions would Repack part of the
  timeline and report success. Every snapshotting script reports which reader it
  used. Fair to delete once real runs have exercised the modern path. They have (every 2026-11-07 log says `regions read via GetRegionOrMarker`), and it was **kept on purpose** (user, 2026-11-07): the short-read guard has no other protection and the fallback costs nothing.
- **Parking writes nothing of its own** (#7). `apply.split_parks` routes each
  parked kind into the applier its category already had, so there is no
  `apply.parks` to find.
- **A parked region gets a Tempo Anchor, and this needs no code.**
  `plan_anchors` anchors *every* region, so phase 1 marks an omitted region's
  start and phase 2 parks it with the region. Do not "tighten" anchoring to the
  arranged regions (ADR-0006, #7 amendment).
- **The item-timebase guard is "track check + chunk-parse fallback"**, the
  user's explicit choice over two narrower options: a per-item mode-`1` override
  cannot be detected through any confirmed numeric API key, so `lib/project.lua`
  chunk-parses `BEAT`. Do not simplify it to a track-only check.
- **The edit core (`lib/core/edit.lua`, issue 04) choices the spec left open.**
  The revision is FNV-1a 64 over the file's exact text (16 hex digits), and a
  missing file's revision is the fixed string `none`, so New on a missing
  sidecar needs `none` and a file that appeared meanwhile is `sidecar_changed`.
  Checks run in the order: operation known, project saved, same project,
  revision, parse, the operation's own validation, the round-trip guard, and
  only then the rewrite question, so a bad edit is refused rather than asked
  about. A non-New operation on a missing sidecar answers
  `arrangement_not_found`. The core does not check that an added region exists
  in the project (an Arrangement may name a region that is not there; Check
  reports it). It reads the project path alone (`env.project_path`), not a
  whole snapshot, since an edit needs nothing else. Numbers may arrive as text
  (the bridge's flat fields) and are converted by the core. The operations are
  in `lib/arrangement_ops.lua`, pure and copying.

## The editor's wire (issue 05)

- **`arrangements` is a new read command; `info` is unchanged.** `info` stays the cheap names-only call the page already uses. `arrangements` carries entries, Headroom, the revision and the regions in timeline order, and reads the sidecar's text once so the revision is the text the Arrangements came from.
- **The edit's field names on the wire:** `operation`, `revision`, `project` (the project path; not `path`, which would clash with the reply's `path` for the file), `arrangement`, `region`, `slot`, `headroom`, `name`, `rewrite=1`. Everything is a string; the core parses numbers.
- **An unreadable sidecar still has a revision** (of its text), and `arrangements` sends the parse error. The page never edits it, so the revision is only informational there.
- **A long project path eats the URL budget** (see `bridge.md`). No fix now: the client refuses what does not fit with a clear message. If a real path ever makes ordinary edits unsendable, send a short hash of the path instead of the path.

## The page's editor (issue 07)

- **`js/editor.js` is the editor's model and the one place an edit is sent** (pure, node-tested): `splitLists`, `slotForDrop`/`slotForStep`/`gapAt` (move arithmetic; a move's `slot` is the final 1-based position), `parseHeadroom`/`formatSeconds`/`stepHeadroom`, `checkName`/`copyName`, and `createEditor(client)` with `load`, `dispatch(operation, fields, { rewrite })` and `subscribe`. `dispatch` never rejects; it resolves `ok` (with `before`/`after` entries of the Arrangement, for Undo, issue 08), `confirm`, `stale` (state already reloaded), `refused` or `failed`. `arrange.js` only draws it.
- **Headroom input** accepts `4`, `+4`, `-2.5`, `2,5`, `4 s` and empty (= 0), rounds to milliseconds, and is sent as plain seconds. Anything else is refused on the page.
- **Quiet calls.** Edits and re-reads hold the page like any command (no polling, no second command) but do not show the busy bar, which would make the sticky header jump on a sub-second call. A second edit while one is in flight is dropped silently.
- **Re-read** on window focus, on regaining visibility and before each Check; the editor is redrawn only if the revision, sidecar state or project changed, so a half-typed Headroom survives a focus event. A stale refusal reloads and redraws and says so.
- **Add** appends to the end of the Arrangement (then move it); there is no drop from the "Left out" list. A name that is not in the project shows only a flag and Remove.
- **Duplicate** proposes "<name> copy"; **Rename** to the same name is a no-op; names are checked on the page first (empty, taken) and again by the core.
- **Tab** is remembered in `localStorage` (`lcrr.arrange.tab`), wrapped in try/catch. The picker, its note and the project line are above both tabs; the result panel lives in Run.
- **Edit tab with a missing sidecar** offers New only (Capture is on Run, and the note says so); with an unreadable one it shows the parse error and no controls.

## The page's Undo (issue 08)

- **The stack lives in `createEditor`** (`editor.js`, pure, node-tested). **Every successful `dispatch` pushes its inverse** (`inverseOf`), from wherever on the page it was sent, so issue 09's `clear_headroom` after Apply is undoable with no extra call. `undo()` pops the newest and sends its steps through `dispatch` with an internal `undo` flag (not pushed back: no Redo). Depth is capped at 100. Lost on reload.
- **Inverses.** move: move back to the old 1-based slot. set_headroom: set the old value. add: remove. remove: add at the old slot, then set the old Headroom if it was not 0 (two edits, one undo entry). clear_headroom: one set_headroom per region that had Headroom (one entry, several edits; none had any: nothing pushed). New and Duplicate: delete the created Arrangement (so the run log gets a Delete entry for it). Rename: rename back. Delete: no inverse.
- **Staleness.** An Undo step is an ordinary revision-checked edit. A stale refusal reloads and drops the whole stack. Beyond the issue: any re-read that finds the file or project changed (`load()` after the first) also drops the stack, because the reload refreshes the revision and would otherwise let an old inverse through onto content it was not made for. A stale refusal of a normal edit does the same, being a reload.
- **Delete drops the stack entries about that Arrangement**; other entries stay. An entry that is refused for any other reason (the region is gone, the name is taken) is dropped and says so; an Undo that gets no answer keeps its entry; a multi-edit inverse that fails after its first step is dropped as "partial" and tells the user to look.
- **Undo works from the Edit tab only**; the button is disabled with nothing to undo, and its tooltip names what it would undo. The note under the buttons says what was undone and is replaced by the next message.

## The post-Apply Headroom offer (issue 09)

- **The decision is `clearHeadroomOffer(answer, reply)` in `js/editor.js`** (pure, node-tested). It offers only for an `ok`, non-noop Apply whose answer was not `zero`/`cancel` and whose reply `headroom` has an entry with `requested` other than 0. It judges by `requested`, not `resolved`: a request under half a bar resolves to 0 yet is still in the sidecar, so the offer stands. The page passes the answer it sent (`null` when no question was asked).
- **The button lives in the Run result card** and sends `clear_headroom` for the reply's `name` straight through `editor.dispatch`, so the edit is revision-checked and pushed on the Undo stack like any other. Its answer (cleared, nothing left to clear, rewrite question, refusal) replaces the offer in the card, since the Edit tab's note is not visible from Run. It is not automatic and not repeated: the card is replaced by the next command.
- **If the Arrangement was edited between Apply and the click**, the clear acts on the current file (revision-checked) and clears whatever Headroom is there; a stale refusal reloads and shows the usual message.

