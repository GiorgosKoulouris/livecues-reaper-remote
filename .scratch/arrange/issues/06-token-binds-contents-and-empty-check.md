# 06. The check token binds the Arrangement's contents; Check refuses an empty Arrangement

Status: done
Type: task

Spec: `../spec.md`, "Phase 2", Check token and The editor.

## What to build
- The bridge's token also remembers a fingerprint of the checked Arrangement's entries and Headroom. Apply refuses `token_stale` with reason `arrangement_changed` when they differ. Other Arrangements' edits don't stale it; a rename does.
- Check (core) refuses an empty Arrangement with its own code. Both front ends word it. The dialog transcripts gain a scenario for it.

## Acceptance
- busted: edit the sidecar between Check and Apply (same Arrangement → refused; another Arrangement → proceeds).
- `docs/bridge.md` and HANDOFF's "Known gaps" entry about the token updated; `words.js` knows the new reason.

## Host check
- Check on the page, edit that Arrangement in a text editor, Apply → refused.

## Comments

Done. Fingerprint lives in `lib/bridge/tokens.lua`; Apply compares after `apply.prepare` re-reads the sidecar. Empty Arrangement: refusal finding `arrangement_empty` in `report.check` (skips Parked and planning, so `not_planned` also shows). Host check outstanding: Check on the page, edit that Arrangement in a text editor, Apply -> refused.
