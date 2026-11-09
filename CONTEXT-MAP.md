# Context map

| Context | Docs | What it covers |
|---|---|---|
| Suite + shared library | `CONTEXT.md`, `docs/adr/` | Suite layout, REAPER web API facts, `shared/` (parsing, poller, guards, hold, tokens, footer) |
| Home | `apps/home/CONTEXT.md` | `lcrr.html`: app buttons and the connection chip |
| Podium | `apps/podium/CONTEXT.md`, `apps/podium/docs/adr/` | `lcrr-podium.html`: transport bar, regions and markers for the stage |
| Monitor | `apps/monitor/CONTEXT.md`, `apps/monitor/docs/adr/` | `lcrr-monitor.html`: personal in-ear mixes from a phone (page only). Plan in `.scratch/monitor/` |
| Arrange | `apps/arrange/CONTEXT.md`, `apps/arrange/docs/adr/`; start at `apps/arrange/CLAUDE.md` | Region Repack: Lua actions and the background bridge in `apps/arrange/reaper/` (Capture, Check, Apply, Verify, diagnostics), and the page `lcrr-arrange.html` that drives them through the bridge (`apps/arrange/docs/bridge.md`). Plan in `.scratch/arrange/` |

Read the suite `CONTEXT.md` for anything that talks to REAPER, then only the app you are working in.
