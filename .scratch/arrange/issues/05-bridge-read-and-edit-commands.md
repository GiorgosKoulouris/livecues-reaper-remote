# 05. Bridge commands to read and edit Arrangements

Status: done
Type: task
Blocked by: 04

Spec: `../spec.md`, "Phase 2", Edits on the wire.

## What to build
- A read command returning the sidecar state (`ok`/`missing`/`invalid` with the parse error/`unsaved`), its revision, every Arrangement's entries with Headroom, and the project's regions in timeline order (or extend `info`; decide in code).
- An edit command fronting `lib/core/edit.lua`, one operation per request, carrying the revision and the project path.
- `docs/bridge.md`, `lib/bridge/service.lua`, re-recorded `test/fixtures/bridge-replies.txt`, `client.js`/`wire.js` and `words.js` for every new reply and refusal.

## Acceptance
- `spec/bridge_contract_spec.lua` covers each new command and refusal; `test/words.test.js` passes on the recording.
- The page refuses before sending an edit whose request would exceed the URL limit, with a clear message (node test).

## Comments

Done on `dev` (commit recorded in git log: "Arrange: bridge read and edit commands (issue 05)"). New `arrangements` (read) and `edit` commands; `info` unchanged. See `apps/arrange/docs/bridge.md` and the "editor's wire" section of `docs/decisions.md`.
