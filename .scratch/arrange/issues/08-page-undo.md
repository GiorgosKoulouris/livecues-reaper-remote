# 08. The page's Undo for Arrangement edits

Status: done
Type: task
Blocked by: 07

Spec: `../spec.md`, "Phase 2", Undo and the record.

## What to build
- An Undo button on the Edit tab: an in-session stack of inverse operations, each sent as an ordinary edit (revision-checked, so a stale one is refused like any edit). Covers move, Headroom, add, remove, clear Headroom, New, Duplicate, Rename. Not Delete. No Redo. Lost on reload.
- A stale refusal of an Undo reloads and drops the stack (its inverses no longer apply to what's on disk).

## Acceptance
- Node tests: the inverse of each operation, and that applying an operation then its inverse returns the same Arrangement.

## Comments

Done in 3597be8.
