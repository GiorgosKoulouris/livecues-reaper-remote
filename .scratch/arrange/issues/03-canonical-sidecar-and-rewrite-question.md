# 03. Canonical sidecar, and asking before a rewrite drops hand edits

Status: done (host check passed, user, 2026-11-07)
Type: task

Spec: `../spec.md`, "Phase 2", Source of truth and the file. ADR-0009.

## What to build
- A way to tell whether a sidecar's text is canonical (equal to what `sidecar.serialize` would write for what it parses to).
- Capture (the core) returns `confirm` (a new code, e.g. `rewrite`) before rewriting a non-canonical file, and writes nothing until answered. Both front ends ask: the dialog script with one more Yes/No, the page with its confirm panel. Order with the existing `replace` question to be decided in code; both answers must be able to arrive together.
- The generated header says the file is rewritten by Capture and the page, and that comments are not kept. (This makes every existing sidecar non-canonical once; that's expected.)

## Acceptance
- busted: canonical detection (comments, bare strings, reordered keys, CRLF), Capture asks on non-canonical and not on canonical.
- Dialog transcripts re-recorded deliberately; the diff reviewed shows only the new question and header.
- `docs/bridge.md`, the recorded bridge replies and `words.js` updated for the new confirm.
- `docs/workflow.md` and `docs/actions.md` mention the question.

## Host check
- Capture over a hand-commented sidecar from the Action list and from the page: asked, then rewritten; a second Capture doesn't ask.

## Done (2026-11-07)
- `sidecar.is_canonical(source)`; `sidecar.load` returns it as a 4th value. Header now says Capture and the page rewrite the file and comments are not kept.
- Capture core: `confirm { code = "rewrite" }` for a non-canonical existing file, nothing written until `rewrite = true`. Order: `replace` first, then `rewrite`; both can arrive in one request. Dialog script loops over the core's questions; bridge takes `rewrite=1`; page `doCapture` repeats the request with every Yes so far.
- Dialog transcripts re-recorded: diffs are only the header lines, the new question, and four new scenarios (`rewrite_yes`, `rewrite_no`, `replace_yes_rewrite_no`, `canonical_no_question`). Existing capture scenarios that are not about the question now use a canonical fixture sidecar.
- `docs/bridge.md`, `bridge-replies.txt` (new `capture_rewrite`), `words.js` (`replaceQuestion`, `rewriteQuestion`), `docs/workflow.md`, `docs/actions.md` updated.
- Host check done by the user (REAPER Action list and page).
