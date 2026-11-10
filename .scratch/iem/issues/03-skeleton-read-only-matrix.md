# 03. App skeleton: bridge running, read-only matrix on the page

Status: ready-for-agent
Blocked by: 02

The first end-to-end slice. Nothing writes to the project yet.

## Build

- `apps/iem/` with the suite's shape (`CLAUDE.md`, `CONTEXT.md`, `docs/adr/`, `test/`, `www/`, `reaper/`, `spec/`). Add it to `apps/home/www/lcrr.html` and `CONTEXT-MAP.md`.
- `LCRR_IEM_Bridge.lua` and its marked `__startup.lua` line in `install.ps1`.
- A `state` command returning mixes (GUID, name, in folder or stray, output, sends with level, mute and signal point), source tracks in project order with folder depth, and the active project.
- The page: grid with sticky row and column headers, name filter, ON cells with read-only dB (dimmed if muted), non-standard send mark, double-feed warning, "no output" in the column header, bridge-not-running banner.

## Done when

Fake-REAPER specs cover the `state` reply, a contract fixture feeds the page's node tests, and `npm test` and `npm run check` pass.
