# Snapshots

The engineer's page for saving the project's mix under a name and restoring it (`lcrr-snapshots.html`). Decisions: `.scratch/snapshots/spec.md`. REAPER facts (measured in the issue 01 spike) are in the suite `CONTEXT.md`.

In this app a **snapshot** is a project snapshot; IEM Mix's are **mix snapshots** (`apps/iemmix/CONTEXT.md`), stored and restored separately.

## The `state` command (issue 02)

Request `cmd=state`. Reply `{ v, command, project: { name, path }, status: "ok" }`: the active project's name (its `.rpp` file name without extension, empty when unsaved) and path. Every reply carries `project`. Refusals are `{ status: "refused", error: { code } }`: `bad_request`, `request_truncated`, `unknown_command`, `internal`. Wording is `words.js`; the recorded replies are `test/fixtures/bridge-replies.txt`.

## The page

A bar with the title, the project name and the connection chip. Connection and heartbeat handling are IEM Setup's: no bridge running means a banner and no controls (`#snapshots-controls` stays hidden).
