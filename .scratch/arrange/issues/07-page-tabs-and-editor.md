# 07. The page: Run and Edit tabs, and the editor

Status: done
Type: task
Blocked by: 05

Spec: `../spec.md`, "Phase 2", The editor, Headroom in the page, Edits on the wire. `DESIGN.md` for the look.

## What to build
- Run and Edit tabs on `lcrr-arrange.html`. The Arrangement picker and project/bridge status above both, shared. Run is today's page. Last tab remembered per browser (storage wrapped in try/catch).
- Edit tab:
  - Two lists: "In this Arrangement" (ordered) and "Left out, will be parked" (timeline order). Moving a row between them is add/remove. A name not in the project is flagged and can only be removed.
  - Reorder: drag handle on pointer events (mouse and touch), plus ↑/↓ per row. One move per drop or step.
  - Headroom per row: signed seconds ("+4 s at next Apply"), typed or ±1 s.
  - New, Duplicate, Rename, Delete (Delete asks, naming the Arrangement and its region count).
  - "Check this Arrangement": switch to Run and start Check.
  - Invalid sidecar: parse error shown read-only, edits disabled. Missing sidecar: New/Capture offered.
- Re-read on focus/visibility, before each Check, and after a stale refusal (which also says the file changed elsewhere).
- The rewrite question (03) shown as a confirm before the first write to a non-canonical file.

## Acceptance
- Node tests for the pure parts (list model, move indices, Headroom input parsing, wording).
- `npm test` and `npm run check` pass.

## Host check
- Desktop width and tablet, mouse and touch drag, on `podium-dummy` and `Rehearsal_Current`. Edit while the file is open in a text editor: stale refusal and reload.

## Comments

Built in 6bc86a2. Host check still to do (desktop, tablet touch drag, stale refusal with the file open in a text editor).
