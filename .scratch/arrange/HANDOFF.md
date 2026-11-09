# Arrange: handoff

For a fresh session picking up the **arrange** app (the region Repack suite moving into LCRR). It's short on purpose and carries only what the files don't make obvious.

Read in this order:
1. `/CLAUDE.md` (suite rules, user rules: work on `dev`, never `main`, **no Claude/Anthropic co-author or attribution in commits**).
2. `.scratch/arrange/spec.md`: every decision, and the order of work. **Don't re-open settled decisions** without asking the user.
3. `.scratch/arrange/issues/01-bridge-spike.md`: what the real REAPER web API does with ExtState. It's resolved, and its facts are also in `/CONTEXT.md`.

## Where things stand (2026-11-07)

- **Step 1 is done.** The bridge spike ran on real REAPER (Windows, Chrome, phone). ExtState works both ways. **Requests are silently truncated at ~1026 URL chars**, and **REAPER serves web requests on its main thread**, so every request hangs while the bridge works. `spike/` holds the throwaway page and Lua. Keep them as a reference, but don't build on them.
- **Step 2 is done** (2026-11-07): `apps/arrange/` exists and every spec and lint passes under Lua 5.4 (517 specs). repack_basic's text files are in `apps/arrange/spec/fixtures/repack_basic/` (logs renamed to `.arrange.log`, contents unchanged); its `after.rpp` stays gitignored by the user's choice, so it's local only. `apps/reorg/` was deleted (user OK).
- Decided while doing step 2 (user, 2026-11-07): `install.ps1` took over `sync.ps1` (reaper slices, `-Resource`, `-Link`); **release zip and ReaPack don't carry the Lua yet** (own later step). `npm test`/`check` **fail** when busted/luacheck are missing. The **home button waits for step 4** (no page to link to).
- **Step 3 is done** (2026-11-07): every `LCRR_Arrange_*.lua` is now a dialog front end over a headless core in `lib/core/<action>.lua`, with the wording in `lib/text/<action>.lua`. `report.lua` returns structured findings (codes and fields). The details are in `apps/arrange/docs/adr/0008`. Before the split, a harness recorded 78 transcripts of every script's dialogs, console, log, undo and applier calls (`apps/arrange/spec/dialog_spec.lua`, baseline commit `983047b`), and all 78 are still byte-identical after it. Step 4's bridge calls the same cores: `prepare` then `run(prepared, request)`. A `status = "confirm"` result means "ask, then call again". Apply takes `headroom = "apply" | "zero" | "cancel"`, and a missing sidecar comes back as `sidecar_missing`, because the import is host-only. `Logger:write` always calls `ShowConsoleMsg`, so a bridge-started run would open REAPER's console on the host. Decide that in step 4 (the page must never cause a dialog there).
- **Nothing has run in REAPER since the migration** (nor since step 3). First real run: `install.ps1` on Windows (its reaper-slice code is untested, no PowerShell here), load the `LCRR_Arrange_*` actions, run a read-only one, then the usual run-twice check. The old `Scripts\TSB\` install and its Action list entries are left for the user to remove.
- The old ReaperScripts repo has **no open issues** (the user checked on GitHub, 2026-11-07), so there's nothing to port. New arrange issues go in `.scratch/arrange/issues/`, numbered from `02`.

## Traps

- `apps/reorg/` (the gitignored source copy) was deleted after step 2. `apps/arrange/` is the only copy now.
- **Read `apps/arrange/HANDOFF.md` and `apps/arrange/docs/decisions.md` before changing any Lua.** Many things there look like bugs and aren't. The engine was tested by hand at length on real projects; step 3 (core/front-end split) must keep its behaviour too.
- **REAPER isn't reachable from the container, and there's no Lua here yet.** The root devcontainer (`/.devcontainer/`) needs `lua5.4`, busted and luacheck added. Keep the `.busted` pin `lua = "lua5.4"`: without it, busted runs specs under 5.1, and they pass there but fail inside REAPER (`spec/toolchain_spec.lua` guards this).
- Lua scripts find `lib/` through `reaper.get_action_context()`, so `lib/` must stay a sibling of the scripts: `apps/arrange/reaper/Scripts/LCRR/arrange/{LCRR_Arrange_*.lua, lib/}`.
- `spec/fixtures/repack_basic/` is the 4.6 GB live project. It exists only on the host and is empty here. Never commit media; reorg's `.gitignore` rules (`*.wav`, `*.rpp-bak`, …) must carry over. `spec/fixtures/repack_bars/` is the golden pair (reorg ADR-0005): move it as it is.
- The run log becomes `<Project>.arrange.log`. Fixture files named `*.tsb.log` are golden records: rename the files and their references, but don't edit their contents.
- `scripts/release-lib.js` only knows `www/` slices (`sliceRoots`). `reaper/` slices need adding there, in `install.ps1` (taking over reorg's `tools/sync.ps1`) and in the ReaPack index (per-source `type="script"`, unverified). That may be step 2 or its own step, so ask the user.
- Suite rule: `npm test` and `npm run check` must pass before any commit. They must also run busted and luacheck once the Lua is in.

## Step 2 checklist (from the spec)
- [x] `apps/arrange/` laid out like the other apps (`CLAUDE.md`, `CONTEXT.md`, `docs/adr/`, `test/` or `spec/`, `www/` placeholder only if needed), plus `reaper/Scripts/LCRR/arrange/`.
- [x] Carry over and adapt reorg's `CLAUDE.md`, `CONTEXT.md` (glossary), `HANDOFF.md`, `docs/` (workflow, actions, limitations, decisions, ADRs 0001 to 0007) and `research/`. Drop `docs/agents/` and GitHub-issue references (the suite uses `.scratch/`).
- [x] Rename `TSB_<Verb><Noun>.lua` to `LCRR_Arrange_<Verb>.lua` (`Apply`, `Check`, `Capture`, `Verify`, `FindDuplicateRegionNames`, `ShowBarLines`, `ShowTrackTimebase`). `@description` starts with `LCRR Arrange: `. Update docs and specs that name them.
- [x] `.tsb.log` → `.arrange.log` in code, docs and fixture file names.
- [x] Root devcontainer gains lua5.4, busted and luacheck. `npm test` / `npm run check` call them (keep `.busted` and `.luacheckrc`).
- [x] Suite ADR-0001 amended for `reaper/` slices. `CONTEXT-MAP.md` gets an arrange entry.
- [x] All specs green under Lua 5.4, then commit to `dev`.

## Step 3 checklist (from the spec)
- [x] Every script split into a headless core (request table in, result table out) and a dialog front end that keeps today's Action-list behaviour exactly (pinned by `spec/dialog_spec.lua`).
- [x] `report.lua` returns structured tables. The dialog front ends format text from them through `lib/text/`.
- [x] Specs cover the cores (`spec/core_*_spec.lua`) and the structured reports (`spec/report_spec.lua`, `spec/text_spec.lua`).

Step 4 (bridge and page) is in the spec. Start it in a fresh session.
