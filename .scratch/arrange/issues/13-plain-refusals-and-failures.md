# 13. Plain refusals and failures

Status: done
Type: enhancement

Spec: `.scratch/arrange/wording-spec.md`, section "Refusals".

Every step that stops says what is wrong and what to do. Applies to `lib/text/*.lua` and `www/lcrr/arrange/js/words.js`, which word the same results separately.

## Work

- Replace the wording of every refusal and failure, on both surfaces, with the spec's text.
- `tempo_env_beats`, `project_unsaved` and `plan_refused` pass prose from `lib/validate.lua` and `lib/regions.lua` straight to the screen. Move them to codes and fields, as ADR-0008 expects, and let `lib/text` and `words.js` word them. The run log can keep its detail. This changes reply shapes, so re-record `test/fixtures/bridge-replies.txt` and update `docs/bridge.md`.
- Word the remaining `plan_refused` cases, each with a fix. Find out whether `plan_out_of_scope` can still be reached; word it if so, and say so here if not.
- Mid-Apply errors: show the plain "stopped partway" text, keep the raw error in the run log (`text.failure_line` already records it). Check that a script run shows the plain text too, not only the bridge.
- Add the 8-name cap for message boxes in `lib/text` (`and N more (see the run log)`). The page is not capped.

## Acceptance

- No refusal lacks a fix, except plain field checks.
- No screen text contains a code label, "sidecar", a script path, or an API name.
- Transcripts are re-recorded and the diff read. `npm test` and `npm run check` pass.

## Comments

2026-11-08: done. `plan_out_of_scope` cannot be reached: `validate.PLAN_CATEGORIES` is empty, so `plan_is_region_move_only` always passes. It is worded anyway (the "needs updating" text). `plan_refused` now carries a `reason` (`region_overlap`, `region_missing`, `headroom`, `items_unsafe`, `planner_bug`) and fields; see `docs/bridge.md`. Shared Lua wording is in `lib/text/refusals.lua`. The Apply script now catches a mid-run error and shows the plain text (scenario `fails_midway`). Sidecar load/save reasons were reworded so they carry no "sidecar" or doubled path. Check, Apply and Verify result wording is left for issues 14 and 15.
