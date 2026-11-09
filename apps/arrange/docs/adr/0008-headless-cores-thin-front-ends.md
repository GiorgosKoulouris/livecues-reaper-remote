# Every action is a headless core with thin front ends

Each `LCRR_Arrange_*` action is split in three (`.scratch/arrange/spec.md`, step 3):

- **`lib/core/<action>.lua`**, the core. Request table in, result table out. It reads the project, plans, applies, opens and closes the undo block, and writes the run log. It never opens a dialog. Results are codes and fields with no wording in them: `{ status = "ok" | "refused" | "confirm" | "cancelled", ... }`, and a refusal is `{ status = "refused", error = { code, ...fields } }`.
- **`lib/text/<action>.lua`**, the wording. Pure functions from results to strings: dialog text, console text and run-log lines.
- **`LCRR_Arrange_<Verb>.lua`**, the dialog front end. It asks for input between the core's steps and shows the result through `lib/text/`. The bridge (`lib/bridge/`, `docs/bridge.md`) is a second front end over the same cores, and it sends results as JSON.

`lib/report.lua` returns structured findings (`{ severity, code, ...fields }`). Blind spots are codes, and `headroom_requests` replaces the old pre-worded `headroom_prompt`. The planners and appliers are unchanged.

## Decisions inside the split

- **The core writes the run log, not the front end.** For Dropped Material the log is the only record, so an Apply started from the page must write it as well. Apply also writes its log *before* the applier runs, inside the undo block, so a run that fails halfway still leaves its record. Only the core knows when that moment is. The log's wording lives in `lib/text/` with the rest of the wording. Show Bar Lines and Show Track Timebase never wrote a log, and still don't: their console report belongs to the front end.
- **A confirmation is a result, not a callback.** When an Arrangement carries Headroom (ADR-0007), or a Capture would replace an existing name, `run` returns `status = "confirm"` and writes nothing. The front end asks in its own way, then calls `run` again with the answer (`headroom = "apply" | "zero" | "cancel"`, `replace = true`). An answer the core doesn't recognise asks again, so it can't fall through to applying Headroom. Running the checks twice costs nothing, because the snapshot is read once, in `prepare`.
- **Steps follow the dialogs.** `prepare` does everything that used to happen before the first prompt, and it refuses on the same conditions in the same order. A front end can therefore keep every dialog where it was. The sidecar import (`apply.import_sidecar`) is a host-only step: only the dialog front end calls it. Any other front end gets `sidecar_missing` from `run`.
- **Everything external comes in through `lib/core/env.lua`** (`api`, `snapshot`, `tempo`, `automation`, `applier`, `open`, `clock`). The real ones are built from `{ api = reaper }`, and the specs inject stand-ins (`spec/support/core_env.lua`).

## The bridge

- **It silences the console, not the log.** `Logger:write` prints to REAPER's console as well as appending to the file, which would open the console window on the host for every bridge-run action. The bridge hands the cores an `api` whose `ShowConsoleMsg` does nothing (a wrapper whose `__index` is the real `reaper`). The cores are unchanged and the dialog transcripts are byte-identical. The log file is written exactly as before.
- **A reply is picked, never passed through.** A core result carries `env`, the snapshot and plans with numeric keys, so `lib/bridge/service.lua` builds each reply from named fields. A Check mints a check token only when it would proceed; Apply is refused without a live one.

## How behaviour was kept

`spec/dialog_spec.lua` runs every script, as REAPER loads it, through 78 scenarios that reach every abort, cancel, prompt answer and run path. It compares each run with a transcript in `spec/fixtures/dialogs/` covering dialogs and their text, console output, files written, undo calls, and the snapshot, plan and anchors handed to the applier. The transcripts were recorded from the scripts *before* the split (commit `983047b`), and the split left every one byte-identical. To re-record after a deliberate change, run `LCRR_RECORD_DIALOGS=1 busted spec/dialog_spec.lua` and read the diff.

The transcripts stop at `lib/project.lua`'s snapshot and `lib/apply.lua`. Those two are covered as before, by `project_spec`, `apply_spec` and the golden `.RPP` pair (ADR-0005). REAPER itself has not run the split (see `HANDOFF.md`).
