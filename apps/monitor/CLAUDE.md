# Monitor

Personal in-ear mixes from a phone, `lcrr-monitor.html`. Plan: `.scratch/monitor/spec.md` and its issues. Read `apps/monitor/CONTEXT.md` and the suite `CONTEXT.md` (web API facts) before changing behaviour.

- Page only: no Lua, no `reaper/` slice. Everything goes through REAPER's web API.
- Pure logic goes in `www/lcrr/monitor/js/core.js` (`LCRR.monitor.core`) with tests in `test/`; DOM wiring in `monitor.js`. Later issues add the mix view, the fader law, write gating and request splitting to `core.js`. Anything not Monitor-specific belongs in `shared/` (see `shared/CLAUDE.md`).
- IDs and classes use the `monitor-` prefix. Shared look comes from `lcrr/shared/css/`; `DESIGN.md` is the design system.
- Do not copy or ship REAPER's stock `more_me.html` (Cockos's file, kept in `.scratch/monitor/` for reference only).
