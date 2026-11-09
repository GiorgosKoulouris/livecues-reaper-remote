# Planning is separated from application

No environment available to this project can execute `reaper.*` — REAPER has no
headless mode, and the development container cannot reach the REAPER install at
all. Every operation is therefore split in two: a **planner**, a pure function
over plain Lua tables that returns a described list of mutations, and an
**applier**, the only code permitted to call `reaper.*`. Planners get real unit
tests; appliers are kept small and few enough to verify by eye.

## Consequences

- `lib/` uses only vanilla `reaper.*` API. Scripts may opt into SWS or
  js_ReaScriptAPI where a task genuinely needs it, declared in the script header
  and guarded with an explicit check, so a missing extension produces a message
  rather than `attempt to call a nil value`.
- Because a plan is a value, logging what a script did is free — and every
  script does log it.
- The indirection is load-bearing, not stylistic. Collapsing a planner into its
  applier removes the only test coverage that operation has.
