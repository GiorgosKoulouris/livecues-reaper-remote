# 04. The edit core and its operations

Status: done
Type: task
Blocked by: 03

Spec: `../spec.md`, "Phase 2", Edits on the wire, Undo and the record, The editor, Engine. ADR-0008, ADR-0009.

## What to build
- Pure operations over parsed Arrangements: move (region to slot), set Headroom, add, remove, clear Headroom (whole Arrangement), New (empty), Duplicate, Rename, Delete. Each validates (names unique and non-empty, no repeated region, finite Headroom) and returns the new tables or a refusal code.
- A sidecar **revision**: a fingerprint of the file's exact text, in pure Lua.
- `lib/core/edit.lua`: request (operation, fields, revision, project path) in; result out: `ok` (new revision, the edited Arrangement), `refused` (`sidecar_changed`, `other_project`, `sidecar_invalid`, `project_unsaved`, name/region codes), or `confirm` for a non-canonical file (03). Never writes an invalid file. Creates a missing sidecar on New.
- Run-log lines (wording in `lib/text/`) for New, Duplicate, Rename and Delete; Delete logs the full entry list. Other operations log nothing.

## Acceptance
- busted for every operation and refusal, including revision mismatch, other project, invalid sidecar, missing sidecar, and that an empty Arrangement is a valid result.
- Through `spec/support/core_env.lua`; no new dialog script.

## Comments
- Done 2026-11-07. `lib/arrangement_ops.lua` (pure operations), `sidecar.revision`, `lib/core/edit.lua`, `lib/text/edit.lua`; specs `arrangement_ops_spec`, `core_edit_spec`. Choices recorded in `apps/arrange/docs/decisions.md`. Commit: 49b8dc1.
