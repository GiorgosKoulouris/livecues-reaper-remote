# 11. Page Undo: multi-edit inverses can fail halfway

Status: ready-for-human
Type: decision

Spec: `../spec.md`, "Phase 2", Undo and the record. Found in the review of `2f12a33..HEAD`, 2026-11-08. Related: issue 08 (`3597be8`), `apps/arrange/docs/decisions.md` "The page's Undo (issue 08)".

## What happens today
`editor.js` `inverseOf` turns two operations into **several** edits, sent one after another through `dispatch`:

- `clear_headroom` becomes one `set_headroom` per region that had Headroom.
- `remove` of a region that had Headroom becomes `add` at the old slot, then `set_headroom` with the old value.

Each edit is revision-checked and written separately. If a later step is refused or fails after an earlier one succeeded, the Arrangement is left partly restored. The page then reports `partial`, tells the user to look at the Arrangement, and **drops the Undo entry**, so the user cannot retry it.

Issue 08 asked for each operation to be undoable as "an inverse operation". `clear_headroom` is one operation on the wire, but its inverse is not.

## What I would revisit
- Is warn-and-drop enough? (Already listed as a question in `host-checks.md`, "Decisions for you".)
- Options:
  1. Keep it as is and document it (the failure needs a stale or refused step in the middle of a two-edit sequence, which is rare).
  2. Keep the entry on a partial failure so the user can retry, with the already-done steps skipped.
  3. Add a core operation that sets a region's slot **and** Headroom, or sets many Headrooms, in one revision-checked edit, so these inverses become one edit and cannot be half done. This touches the bridge contract (`docs/bridge.md`), `lib/core/edit.lua`, `lib/text/edit.lua`, `words.js` and the specs.

## Where to look
- `apps/arrange/www/lcrr/arrange/js/editor.js`: `inverseOf`, the undo loop in `createEditor`.
- `apps/arrange/test/editor.test.js`: the partial-undo tests.
- `apps/arrange/docs/decisions.md`: "The page's Undo (issue 08)", the "partial" bullet.

## Acceptance (once decided)
- The chosen behaviour is written in `decisions.md`.
- If option 2 or 3: a node test (and busted spec for 3) that fails for the half-done case on today's code.
- `npm test` and `npm run check` pass.

## Comments
