# REAPER semantics are captured as golden .RPP fixtures

Nothing in this project's environment can execute `reaper.*` (see ADR-0001), so
real REAPER behaviour can only be established by a human running an action in the
DAW. Rather than re-establishing it by hand on every change, each verified run is
frozen: a scenario directory under `spec/fixtures/` holds a committed `before.RPP`,
the `after.RPP` captured from a real run, and an `expected_plan.lua` that a busted
test asserts the planner reproduces.

`.RPP` is plain text, and everything the suite touches is legible in it — item
`POSITION`/`LENGTH`/`SOFF`/`FADEIN`/`FADEOUT`, `MARKER` lines for markers and
regions, `<TEMPOENVEX>` points, and envelope point lists. No media files are
needed to verify a result.

## Consequences

- **The loop requires a save.** A script's effects reach the `.RPP` only when the
  project is saved. Run the action, save, then diff — an unsaved project yields
  stale state and a confidently wrong verification.
- **`before.rpp` and `after.rpp` are not symmetrical in practice.** `before.rpp`
  is the tracked baseline the scenario reverts to. `after.rpp` is whatever the
  last run produced, and it churns on every experiment, so it is gitignored by
  default. Only once a run is *verified* does its `after.rpp` become the golden
  half of the pair, and then it is committed deliberately with `git add -f`.
  Tracking every scratch run would make the diff that is supposed to be the
  record into noise.
- Fixtures are committed *before* a run, so `git diff` on the `.RPP` is the record
  of what REAPER actually changed. No before/after bookkeeping, no reliance on
  `.RPP-bak`.
- `expected_plan.lua` looks redundant beside `after.RPP` but is not: it is the
  planner's prediction, and the pair is what proves the planner models real
  semantics rather than merely producing a plausible plan.
- A fixture diff appearing after a REAPER update is a **signal, not a broken
  test** — REAPER's behaviour changed, and the suite needs to follow.
- Verification is human-triggered, so this complements the planner unit tests
  rather than replacing them.
