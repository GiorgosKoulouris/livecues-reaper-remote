# Arrange: bring the region Repack suite (ex-`apps/reorg`, ex-ReaperScripts) into LCRR

Status: ready-for-agent (phase 1); phase 2 needs its own grilling

Decided in a grilling session on 2026-11-07. The Lua engine stays; the web page is a new front end over it.

## Decisions

### Scope
- **Phased.** Phase 1: remote control + report viewer. Phase 2: Arrangement editor (drag order, Headroom controls), which overturns reorg ADR-0003 (sidecar authored only in a text editor) and must be grilled separately. Known phase-2 trap: a Lua rewrite of a hand-edited sidecar loses its comments.
- Studio tool, desktop/tablet at the desk. The page **never** causes a dialog on the REAPER host.
- Phase 1 exposes: Diagnostics (duplicate/unnamed regions, track timebases, bar lines/Padding), Capture (with in-page overwrite confirm), Verify, Check → Apply.
- Host-only steps (sidecar import after Save As, unsaved project) are explained in the page, which names the host action to run. The page never triggers them.

### Lua stays the engine
- Every script splits into a headless **core** (request table in, result table out) and two thin front ends: the existing **dialog** front end (Action list keeps working as tested) and the **bridge** front end.
- `lib/` planners/appliers are unchanged, except that `report.lua` returns **structured tables**. The dialog front ends format text from them, and the bridge sends JSON (encode-only JSON in Lua; requests are flat key/value fields, so Lua never parses JSON).
- **Apply only after Check.** Check returns a short **check token**, and the bridge keeps that token's project path and state-change count in memory. An Apply request carries only the token and the Headroom choice (apply / zero / cancel). The bridge refuses if the token is unknown or if the path or count differs (stale screen, double tap, other project tab, bridge restarted).
- Every reply carries the active project's name and path, and the page shows them.

### Bridge
- One background defer script, `LCRR_Arrange_Bridge.lua`, watching ExtState for requests that carry an ID. There's a busy flag. The page shows "bridge not running" through the shared guard.
- `install.ps1` adds an idempotent, marked line to `Scripts/__startup.lua`. A manual start action also exists.
- Wire facts come from the spike (`issues/01-bridge-spike.md`):
  - Requests: keep them under ~900 encoded URL chars. REAPER silently truncates at ~1026, so each request declares its length and the bridge refuses a short one. Large payloads are sent in chunks.
  - Replies: the page unescapes `\t`, `\n` and `\\`. Detect the bridge only from a changing heartbeat.
  - REAPER serves web requests on its main thread, so **every request hangs while the bridge works**. There's no readable busy flag. The page knows a long action is running from its own outstanding request: it shows "Applying…" with elapsed seconds instead of the guard's offline state, and uses a long timeout (120 s). Design for an Apply of **5 to 30 s** on the real 19-region, 330-item project. The user remembers it as quick, but it hasn't been measured, so measure it on the first real run and record the result here. Bridge requests can share the suite poller (`SET;GET;TRANSPORT` in one request works).

### Repo, naming, packaging
- Fresh copy (no history) into `apps/arrange/`. Page `lcrr-arrange.html`, JS `LCRR.arrange`, CSS/IDs `arrange-`.
- Lua lives in a new **reaper slice**: `apps/arrange/reaper/Scripts/LCRR/arrange/{LCRR_Arrange_<Verb>.lua, lib/}`, mirroring REAPER's resource path as `www/` mirrors the web root (amends suite ADR-0001). Specs and fixtures go in `apps/arrange/spec/`.
- Scripts: `LCRR_Arrange_Apply`, `_Check`, `_Capture`, `_Verify`, `_FindDuplicateRegionNames`, `_ShowBarLines`, `_ShowTrackTimebase`, `_Bridge`. Each `@description` starts with `LCRR Arrange: `.
- Run log is renamed `<Project>.arrange.log` (old `.tsb.log` files are left alone). The sidecar `<Project>.arrangements.lua` is unchanged.
- Same ReaPack package (suite ADR-0002), with the Lua carried by per-source `type="script"` (to verify).
- `install.ps1` takes over `tools/sync.ps1` (copies `reaper/` slices, `-Link` for dev). `sync.ps1` is deleted.
- `npm test` / `npm run check` also run busted and luacheck under **Lua 5.4** (keep the `.busted` `lua = "lua5.4"` pin). The LCRR devcontainer gains lua5.4, busted and luacheck.
- The ReaperScripts repo had no open issues (checked 2026-11-07), so nothing is ported. It is deleted after the migration.
- Home gets an Arrange button, and `CONTEXT-MAP.md` gets an entry.

## Order of work
1. Bridge spike on real REAPER (`issues/01-bridge-spike.md`). Everything else depends on it.
2. Migrate and rename into `apps/arrange/`, then get the tests green (npm wraps busted and luacheck).
3. Split scripts into core and front ends, and make `report.lua` structured.
4. Build the bridge and the page.
