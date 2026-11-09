# Fixtures

| Fixture | What it is |
|---|---|
| `repack_bars/` | The **golden pair** (ADR-0005). Crafted small enough that a `git diff` of `after.rpp` is readable, and asserted against `expected_plan.lua`. Its `README.md` records every run. |
| `repack_basic/` | The **live project**, and not a fixture directory: a real REAPER project folder with REAPER's own `Backups/` and 4.6 GB of takes in `PreRecs/`. Only its small text files (`before.rpp`, `before.arrangements.lua`, the run log) are tracked; the media exists only on the host and is never committed (`.gitignore`). An excellent corpus, a useless golden pair: at 19 regions and 330 items no diff is readable. Runs are recorded in `after.arrange.log` beside the `.RPP` (runs before the migration, as `after.tsb.log`, renamed with its contents unchanged). |
| `dialogs/` | Dialog transcripts that `spec/dialog_spec.lua` compares against. Re-record with `LCRR_RECORD_DIALOGS=1 busted spec/dialog_spec.lua` and read the diff. |

A prepared copy, not `repack_basic/before.rpp` unmodified, is what live runs are made on: it needs `TEMPOENVLOCKMODE` set to `0`, and the four tracks on `BEAT -1` set explicitly to `0`, or `lib/project.lua` refuses their items.
