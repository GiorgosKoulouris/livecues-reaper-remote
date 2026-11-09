# 10. Envelope points on beat-timebase tracks drift when the tempo map is rewritten

Status: done
Type: bug

Spec: `../spec.md`. Found on the user's real project `Rehearsal_Current` (REAPER 7.82 win64), last Apply in `dev/reaper-projects/Rehearsal_Current.arrange.log` (2026-11-07 21:25:10).

## What happened
The page reported `The bridge failed: could not find the envelope point to move on track 12, envelope "Mute", at 275.600s -- did the project change after this run started?` and the project was left partly changed. The page also said "Nothing may have been done", which was wrong.

Every track in that project is `BEAT 2` (beats, position only). Envelope points on a beat-timebase track follow the tempo map, exactly as items do (`apply.locate_items`' comment; research 4.1c). `apply.plan` runs `apply.tempo_moves` and only then `apply.envelope_moves`, which re-locates each point by its pre-tempo `from` time. Payback's 121 bpm marker moved onto 273.600 where Deserve's 120 bpm one was, so the BassDI Mute points at 275.600 had drifted to about 275.583 (2 s x 120/121). Points at 273.600 were found only because they sit on a tempo marker. Parked envelope points (`parked.envelopes`) have the same problem.

## What to build
- Engine: make envelope-point moves immune to tempo-map drift. Delete every envelope point the plan moves (normal and parked) located by its original `from`, before `apply.tempo_moves`; insert them at their absolute `to` afterwards with the plan's value, shape, tension and selected, preserving step-pair order (decisions.md, issue 02), sorting once per envelope. Anchors must still win at their times.
- Spec: model beat-timebase envelope points following tempo moves in `fake_reaper`; a busted spec reproducing the failure (a step pair and a point shortly after a region's start, regions of different tempo swapped) that fails before the fix; apply twice, the second a no-op.
- Message: the page's `internal` wording says "Nothing may have been done", wrong after a partial write. Say the run stopped partway, that what was done before the failure is one REAPER undo step (Ctrl+Z reverts it), and to check the run log. Keep the dialog front end's wording in step.
- Run log: the plan is logged before the applier runs and nothing records a failure. When the applier errors after the plan was logged, append a line saying the run failed, with the error, and that what follows the failing step was not done. Core-level, so both front ends get it.
- Docs: decisions.md, research 4.1c, HANDOFF, limitations if affected.

## Acceptance
- The new spec fails on the old applier and passes on the new one.
- `npm test` and `npm run check` pass; dialog transcripts and recorded bridge replies change only where the wording changed.

## Host check
- Re-run `install.ps1`. On `Rehearsal_Current` (restore it from a backup first), Check then Apply the same Arrangement: no error, a second Apply is a no-op, and the BassDI Mute points sit at their planned times.

## Comments

Implemented in 0c60b55.

Host check passed (user, 2026-11-07): Apply on Rehearsal_Current runs without error and the envelopes come out right. Resolved.
