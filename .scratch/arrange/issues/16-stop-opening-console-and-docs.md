# 16. Stop opening the console, and update the docs

Status: done
Type: enhancement
Blocked by: 13, 14

Spec: `.scratch/arrange/wording-spec.md`, "Decisions". This goes last, so the message boxes already carry everything the console used to.

## Work

- `lib/log.lua`: stop calling `ShowConsoleMsg`. The file is unchanged, including what Check and Verify write today.
- Show Bar Lines and Show Track Timebase keep their own direct `ShowConsoleMsg` calls.
- `lib/bridge/service.lua` mutes the console for the bridge. Remove that wrapper if nothing written by the bridge can reach the console any more.
- Update the "Errors vs logs" convention in `apps/arrange/CLAUDE.md`, the header of `lib/log.lua`, `docs/workflow.md`, `docs/actions.md` and the README, and add an entry to `docs/decisions.md`: screens are short and the run log holds the detail.

## Acceptance

- Transcripts show no `ShowConsoleMsg` for Check, Apply, Capture or Verify, and the run-log entries are byte-for-byte unchanged apart from issue 13's reworded failures.
- `npm test` and `npm run check` pass.
- On the host, after re-running the installer: run Check and Apply from the action list and confirm that no console opens, and that a refused Check shows its reasons in the message box.

## Comments

Implemented on dev. `npm test` and `npm run check` pass; the dialog transcript diffs were read (only console blocks and the reworded Capture/Show Bar Lines/Show Track Timebase text changed; run-log entries are byte-for-byte unchanged). The on-host acceptance checks are still to be done by hand.
