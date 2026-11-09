# 12. Editor and text: duplication and repeated switches

Status: ready-for-human
Type: refactor

Spec: none (a cleanup, no behaviour change). Found in the standards review of `2f12a33..HEAD`, 2026-11-08. All of these are judgement calls, not bugs. Do it test-first where a test is cheap; behaviour must not change, and dialog transcripts and recorded bridge replies must not change.

## 1. The same sentences are written twice
`lib/text/edit.lua` (the dialog and run-log wording of `arrangement_not_found`, `region_repeated`, `slot_invalid`, `would_be_invalid`) and `www/lcrr/arrange/js/words.js` word the same refusals separately. They already differ ("finite number" in one, "number" in the other), so they will drift further. Decide which is the source, or add a test that fails when the two disagree for the same code.

## 2. Operation names are switched on in three places
`inverseOf`, `fold` (both in `editor.js`) and `words.undoLabel` each switch on `move`, `set_headroom`, `add`, `remove`, `clear_headroom`, `new`, `duplicate`, `rename`, `delete`. A new operation touches all three. One table keyed by operation (inverse builder, fold rule, label) that the three read would do. `inverseOf` also repeats the `{ operation, fields = { arrangement, region, slot } }` literal in each case: a small builder would remove that.

## 3. `createEditor` does several jobs
State loading, folding replies, the undo stack and dispatch share one closure. Split along those seams if issue 11 changes the undo stack anyway; otherwise leave it.

## 4. Smaller items
- `lib/bridge/service.lua` `h.edit` copies fields from `result` into the reply one by one, and calls `need(fields, ...)` the same way three times.
- `editor.js` `load()` builds the change signature `revision|sidecar|projectPath|loaded` twice (`before` and `after`): one helper, and better names than `before`/`after`. `{project, revision, rewrite}` travels together as `base`.
- `service.lua` `h.edit`: the variable `bad` is a refusal, not a flag; name it for what it holds.
- `lib/core/apply.lua` / `lib/apply.lua`: `apply.plan` builds `lifted` by concatenating `plan.envelope_moves` and `parked.envelopes` inline. A small planner or applier helper would read better.
- CSS: `.arrange-headroom input { width:5rem }`, `.arrange-headroom-label { font-size:.8rem; min-width:8rem }` and `.arrange-flag { font-size:.75rem }` sit outside DESIGN's scale. Left alone on purpose while the app is re-documented; revisit then.
- Optional: reserve the 3 px border on every `.arrange-row` so the drop indicator does not grow the row by 2 px while dragging.

## Acceptance
- `npm test` and `npm run check` pass with no change to any recorded dialog transcript or bridge reply.

## Comments
