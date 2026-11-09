# Arrange: bring the region Repack suite (ex-`apps/reorg`, ex-ReaperScripts) into LCRR

Status: ready-for-agent (phase 1 built; phase 2 grilled 2026-11-07, issues 03 to 09)

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
  - REAPER serves web requests on its main thread, so **every request hangs while the bridge works**. There's no readable busy flag. The page knows a long action is running from its own outstanding request: it shows "Applying…" with elapsed seconds instead of the guard's offline state, and uses a long timeout (120 s). Design for an Apply of **5 to 30 s** on the real 19-region, 330-item project. **Measured 2026-11-07 (user, from the page, on `Rehearsal_Current`, 21 regions): under a second.** The 120 s timeout and the elapsed-seconds display are therefore generous; they stay as cheap insurance against a much bigger project or a slow host. Bridge requests can share the suite poller (`SET;GET;TRANSPORT` in one request works).

### Repo, naming, packaging
- Fresh copy (no history) into `apps/arrange/`. Page `lcrr-arrange.html`, JS `LCRR.arrange`, CSS/IDs `arrange-`.
- Lua lives in a new **reaper slice**: `apps/arrange/reaper/Scripts/LCRR/arrange/{LCRR_Arrange_<Verb>.lua, lib/}`, mirroring REAPER's resource path as `www/` mirrors the web root (amends suite ADR-0001). Specs and fixtures go in `apps/arrange/spec/`.
- Scripts: `LCRR_Arrange_Apply`, `_Check`, `_Capture`, `_Verify`, `_FindDuplicateRegionNames`, `_ShowBarLines`, `_ShowTrackTimebase`, `_Bridge`. Each `@description` starts with `LCRR Arrange: `.
- Run log is renamed `<Project>.arrange.log` (old `.tsb.log` files are left alone). The sidecar `<Project>.arrangements.lua` is unchanged.
- Same ReaPack package (suite ADR-0002), with the Lua carried by per-source `type="script"` (to verify). **Deferred (user, 2026-11-07):** for now the whole suite is delivered only through `scripts/install.ps1` / `install.bat`. The zip and ReaPack delivery will be revisited later.
- `install.ps1` takes over `tools/sync.ps1` (copies `reaper/` slices, `-Link` for dev). `sync.ps1` is deleted.
- `npm test` / `npm run check` also run busted and luacheck under **Lua 5.4** (keep the `.busted` `lua = "lua5.4"` pin). The LCRR devcontainer gains lua5.4, busted and luacheck.
- The ReaperScripts repo had no open issues (checked 2026-11-07), so nothing is ported. It is deleted after the migration.
- Home gets an Arrange button, and `CONTEXT-MAP.md` gets an entry.

## Order of work
1. Bridge spike on real REAPER (`issues/01-bridge-spike.md`). Everything else depends on it.
2. Migrate and rename into `apps/arrange/`, then get the tests green (npm wraps busted and luacheck).
3. Split scripts into core and front ends, and make `report.lua` structured.
4. Build the bridge and the page. **Built 2026-11-07; not yet run in REAPER** (see `HANDOFF.md`). Apply's timing is still to be measured and recorded here.

## Phase 2: the Arrangement editor

Decided in a grilling session on 2026-11-07. Decisions only; the work is split into `issues/03` to `09`. Overturns reorg ADR-0003's "authored only in a text editor": see `apps/arrange/docs/adr/0009-the-page-edits-the-sidecar.md`.

### Source of truth and the file
- **The sidecar stays the only store.** `<Project>.arrangements.lua` beside the `.RPP`, format unchanged (ADR-0003's storage, keys and validation stand). The page is a second editor of it, through the bridge; editing by hand in a text editor stays supported.
- **Every write rewrites the whole file through `serialize`**, as Capture already does. Hand-written comments and formatting are not kept, and the generated header says so. `serialize` keeps writing an explicit `headroom = 0` on every entry.
- **A rewrite of a non-canonical file asks first.** When the file's text differs from what `serialize` would write for it (comments, hand formatting, bare-string entries), any write (a page edit, or Capture from the page *or* the Action-list dialog) returns a confirmation and writes nothing until answered. After one accepted rewrite the file is canonical and the question does not come back until someone hand-edits it again. The dialog transcripts change for this on purpose.
- **The page never writes a sidecar that won't parse.** It shows the parse error, read-only, and says to fix the file in the text editor. A missing sidecar is created by New or Capture. An unsaved project is refused, as today.

### Edits on the wire
- **One small bridge request per operation, saved at once.** Operations: move a region to a slot, set a region's Headroom, add a region, remove a region, clear an Arrangement's Headroom (one operation, for the post-Apply offer), New, Duplicate, Rename, Delete. **No chunk protocol is built**: every operation fits under the ~900-character limit. A request that would not (an absurdly long name) is refused by the page with a clear message.
- **Stale overwrite: refuse and reload.** Reading the sidecar returns a **revision**, a fingerprint of the file's exact text. Every edit carries the revision it was based on and the **project path** it was made against. If the file no longer matches, or another project is active, the bridge refuses, the page reloads the Arrangement and says it changed elsewhere, and the user redoes the one edit. Nothing is ever written blind. (A text editor saving an older buffer over the page's edit cannot be prevented from our side.)
- **When the page re-reads:** on regaining focus, before each Check, and after any stale refusal. No background polling of the file.

### Check token
- **The token also binds the checked Arrangement's contents** (its order and Headroom). If they changed before Apply, from the page or a text editor, Apply refuses (`token_stale`, a new reason `arrangement_changed`). Edits to other Arrangements do not stale it. Renaming the checked Arrangement does (the token already binds the name). This closes the gap HANDOFF lists under "Known gaps", for the dialog-less page path; the dialog front end has no token and is unchanged.

### Undo and the record
- **Undo is the page's**, an in-session stack of inverse operations, each sent as an ordinary edit through the same revision check. Lost on reload. **No Redo.** REAPER's Undo does not cover the sidecar.
- **Delete is not undoable.** It asks first, naming the Arrangement and its region count.
- **The run log records New, Duplicate, Rename and Delete** (Delete with the full entry list, so a deleted Arrangement can be rebuilt from the log). Moves, adds, removes and Headroom changes are not logged.

### Headroom in the page (ADR-0007 stands)
- **Shown as a signed change** ("+4 s at next Apply"), never as a length.
- **Entered in seconds**, typed or stepped ±1 s, and stored in seconds: the file format is unchanged. The bar-resolved figure is what Check already reports. Negative values are allowed; the shrink floor stays the engine's to enforce.
- **The Apply confirmation is unchanged.**
- **After an Apply that applied Headroom**, the result offers "Clear the Headroom just applied", which sets that Arrangement's Headroom to 0 as one ordinary, undoable edit. Offered, never automatic.

### The editor
- **Two lists.** "In this Arrangement" (ordered) and "Left out, will be parked" (project regions it omits, in timeline order). A region is added or removed by moving it between them. A name in the Arrangement with no matching region in the project is flagged "not in the project" and can only be removed. The page never adds, renames or changes regions in the project.
- **Reorder** with a drag handle built on pointer events (mouse and touch) plus ↑/↓ buttons on each row. A drop or a step is one move operation.
- **Managing Arrangements:** New (empty), Duplicate (of the selected one, under a new name), Rename, Delete, plus the existing Capture. An empty or already-taken name is refused, never overwritten (only Capture keeps its replace confirmation).
- **An empty Arrangement may be saved** as work in progress; **Check refuses it** ("Arrangement is empty") rather than parking every region.
- **Layout:** one page with **Run** and **Edit** tabs. The Arrangement picker and the project/bridge status sit above the tabs and are shared. Run is today's page. Edit holds the editor and Undo, plus "Check this Arrangement", which switches to Run and starts Check. The last tab is remembered per browser (optional convenience).

### Engine
- **A new headless core, `lib/core/edit.lua`** (ADR-0008): request table in (operation, fields, revision, project path), result out (`ok` with the new revision and Arrangement, `refused`, or `confirm` for the rewrite question). The operations are pure functions over parsed Arrangements. **Only the bridge fronts it**: no new Action-list script.

### Phase 2 order of work
1. Canonical sidecar and the rewrite question, Capture included (`issues/03`).
2. The edit core and its operations (`issues/04`).
3. Bridge commands for reading and editing (`issues/05`).
4. The token binds contents; Check refuses an empty Arrangement (`issues/06`).
5. The page: tabs and the editor (`issues/07`), Undo (`issues/08`), the post-Apply Headroom offer (`issues/09`).
6. Host checks in REAPER and on the tablet (listed in each issue).
