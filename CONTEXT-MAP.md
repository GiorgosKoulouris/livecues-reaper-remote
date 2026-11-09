# Context map

| Context | Docs | What it covers |
|---|---|---|
| Suite + shared library | `CONTEXT.md`, `docs/adr/` | Suite layout, REAPER web API facts, `shared/` (parsing, poller, guards, hold, tokens, footer) |
| Home | `apps/home/CONTEXT.md` | `lcrr.html`: app buttons and the connection chip |
| Podium | `apps/podium/CONTEXT.md`, `apps/podium/docs/adr/` | `lcrr-podium.html`: transport bar, regions and markers for the stage |
| Arrange | `apps/arrange/CONTEXT.md`, `apps/arrange/docs/adr/`; start at `apps/arrange/HANDOFF.md` | Region Repack: Lua actions in `apps/arrange/reaper/` (Capture, Check, Apply, Verify, diagnostics). No page yet; plan in `.scratch/arrange/` |

Read the suite `CONTEXT.md` for anything that talks to REAPER, then only the app you are working in.
