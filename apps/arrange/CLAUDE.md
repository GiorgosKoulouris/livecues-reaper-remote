# Arrange

The region Repack suite: REAPER ReaScript (Lua) actions that lay a project's regions back down in a different order, carrying everything inside them along. Scope is deliberately narrow: **regions and markers only**. Migrated from the private ReaperScripts repo (ex-`apps/reorg`) in step 2 of `.scratch/arrange/spec.md`. Step 4 added the bridge (`LCRR_Arrange_Bridge.lua`) and the page `lcrr-arrange.html`.

Suite rules in `/CLAUDE.md` apply: work on `dev`, never `main`; **no Claude/Anthropic/AI co-author, trailer or attribution** in commits, docs or comments.

## Start here

Read the **Traps** section below, then **`docs/decisions.md` before "fixing" anything surprising**. The engine was tested by hand at length on real projects.

| File | What it holds |
|---|---|
| `CONTEXT.md` | Glossary. The vocabulary below is defined here |
| `README.md` | Setup, quick start, what to expect. Keep it in step with the actions |
| `docs/workflow.md` | The user-facing path end to end: capture, duplicate, reorder, check, apply, verify |
| `docs/actions.md` | Per-action reference: what each needs, changes and refuses on. Add a row here when adding a script |
| `docs/bridge.md` | The bridge's wire contract with the page: ExtState keys, request/reply format, commands, the check token |
| `docs/limitations.md` | What the suite will not do, and why, and what has never been observed in real REAPER |
| `docs/decisions.md` | Decisions that look like bugs and are not |
| `docs/adr/` | Nine ADRs: architecture, splitting, storage, bar alignment, verification, the injected tempo oracle, Headroom's non-idempotence, headless cores with thin front ends, the page editing the sidecar |
| `research/reaper-scripting.md` | Sourced ReaScript API research, tagged primary vs secondary. **Prefer it to recollection** |

Open work: `.scratch/arrange/` (spec, numbered issues, host checks). `#N` in code and docs means an issue of the retired ReaperScripts GitHub repo: historical, not tracked anywhere now.

## Traps

Cheap to trip over, expensive to discover.

- **REAPER is not reachable from this container.** It runs on the Windows host, on a drive that is not mounted, so no script can be run against the real API from here (the reason for ADR-0001 and ADR-0005). The container also has no PowerShell and no browser: `install.ps1` and `arrange.js` can only be checked on the host.
- **Install is one-way, repo to REAPER, via `scripts/install.ps1` (or `install.bat`), run on the Windows side.** Editing files here changes nothing REAPER runs until it is re-run (unless installed with `-Link`). When real-REAPER behaviour does not match the code, the first question is "was `install.ps1` re-run?" The repo is the only source of truth: never edit these files in REAPER's script editor, the next install overwrites them.
- **`lib/` stays beside the `LCRR_Arrange_*.lua` files** (`Scripts\LCRR\arrange\{*.lua, lib\}` in REAPER, `reaper/Scripts/LCRR/arrange/` here), because scripts find it through `reaper.get_action_context()`. `spec/layout_spec.lua` checks it; specs reach `lib/` through `.busted`'s `lpath`.
- **Run it twice, always.** A single clean run proves nothing about anything idempotent: four of this work's bugs gave correct output on a first run and appeared only when the same Arrangement was applied to the operation's own output (a first Repack never meets its own anchors, never writes onto an occupied tempo position, never has to vacate the timeline origin). Run it twice and diff the results. Its only automated expression is `spec/repack_bars_fixture_spec.lua`'s "Subset applied twice" block, which covers the plan half on one fixture. **Headroom reads this backwards** (ADR-0007): it is deliberately not idempotent, so a second run is still the test, but the expected result is a further change, and a second run that changes nothing means it has quietly become an absolute length.
- **Do not read `reascripthelp.html` through a summarizing fetch tool.** It confabulates: two fetches of the same page gave two different, both wrong, signatures for one function. `curl` it and grep locally (the copy self-reports `REAPER v7.78`, the version this suite runs against) and cross-check `reaper_plugin_functions.h`. Method in `research/reaper-scripting.md` section 4.5, which is to be preferred to recollection.
- **Do not compute bar positions in this container.** An estimate of the live project's Padding predicted 2 regions and about 3.5 s; the real oracle produced 8 regions and 7.237 s, and only one of the eight matched. `LCRR_Arrange_ShowBarLines.lua` asks the real oracle without writing anything.
- **`TEMPOENVLOCKMODE` must be `0`**, or a Repack is refused up front (`1` is Beats, under which writing one tempo marker re-derives the time of every marker after it: measured at 1.121486470 s across 64 markers). It lives inside the `.RPP`, so reverting to a baseline copy resurrects it. `repack_basic` carries `1`; `repack_bars` carries `0` deliberately.
- **An item's position is not a stable identity across a tempo edit.** Rewriting the tempo map drags every beat-anchored item, so `apply.locate_items` resolves every `MediaItem*` before the first tempo write.
- **Requests from the page stay under about 900 encoded URL characters, and REAPER answers web requests on its main thread**, so every request hangs while the bridge works. Spike facts are in `/CONTEXT.md`.
- **Never commit media.** `spec/fixtures/repack_basic/` is a 4.6 GB live project that exists only on the host. See `spec/fixtures/README.md`.
- SHAs and `TSB_*` script names in old notes and fixture logs refer to the ReaperScripts repo this suite was migrated from, without its history.

## Layout

- `reaper/`: a **reaper slice**, mirroring REAPER's resource path as `www/` mirrors the web root (suite ADR-0001). Scripts in `reaper/Scripts/LCRR/arrange/LCRR_Arrange_<Verb>.lua`, with `lib/` **beside them**: each script adds its own folder to `package.path` via `reaper.get_action_context()` and requires `lib.<module>`. The bridge script also adds its parent folder and requires the suite's shared Lua as `shared.bridge.*` (`shared/reaper/`, installed as the sibling `Scripts\LCRR\shared`). `spec/layout_spec.lua` guards both.
- Inside the slice, `lib/` holds the planners and appliers, plus `lib/core/<action>.lua` (one headless core per action) and `lib/text/<action>.lua` (its wording). Each `LCRR_Arrange_<Verb>.lua` script is only the dialog front end over its core (ADR-0008).
- `spec/`: busted specs, `spec/support/` (`fake_reaper.lua`, `core_env.lua` for driving cores, `script_harness.lua` for running whole scripts) and `spec/fixtures/` (golden records, see `spec/fixtures/README.md`). `spec/fixtures/dialogs/` holds the dialog transcripts `spec/dialog_spec.lua` compares against.
- `www/` and `test/`: the page (`lcrr-arrange.html`, `lcrr/arrange/{css,js}/`) and its node tests. `js/wire.js` (request/reply format, heartbeat), `client.js` (one call over the shared fetch) and `words.js` (every sentence) and `editor.js` (the editor's list model, move and Headroom arithmetic, and where an edit is sent) are pure and tested; `arrange.js` is the DOM wiring. IDs and classes use `arrange-`. `test/fixtures/bridge-replies.txt` is the bridge's real output, recorded by `spec/bridge_contract_spec.lua` (`LCRR_RECORD_BRIDGE=1 busted spec/bridge_contract_spec.lua`), and `test/words.test.js` pushes it through `words.js`. A change to a reply's shape fails the busted spec; a field `words.js` doesn't know fails the node test.
- `lib/bridge/`: the bridge front end (`service.lua` requests and replies, `tokens.lua`; `json`, `request` and `runner`, the ExtState loop, are now shared: `shared/reaper/Scripts/LCRR/shared/bridge/`). The wire contract is `docs/bridge.md`: read it before changing either end.
- Installed by `scripts/install.ps1` (Windows) into `<resource path>\Scripts\LCRR\arrange\`.

## Vocabulary

Use the glossary's terms. The timeline operation is **Repack**, never "reorder": *reorder* describes only what an Arrangement expresses. The per-region end adjustment is **Headroom**, never "delta" (in the planner and the run log, `delta` already means how far something moved). See `CONTEXT.md` for Arrangement, Padding, Headroom, Tempo Anchor, Parked Material, Loose Item and Straddling Item.

## Commands

From the repo root, `npm test` runs busted and `npm run check` runs luacheck (via `scripts/lua.js`), both from inside `apps/arrange/`. Directly:

```sh
cd apps/arrange
busted      # specs; config in .busted
luacheck .  # lint; config in .luacheckrc
```

**Do not remove `lua = "lua5.4"` from `.busted`.** Debian's `lua-busted` installs lua5.1 as its interpreter, so without the pin specs run under 5.1 and pass while the same code fails inside REAPER, which embeds 5.4. `spec/toolchain_spec.lua` guards it. The devcontainer installs lua5.4, busted and luacheck.

## Conventions

- **Script naming:** `LCRR_Arrange_<Verb>.lua`, `@description` starting `LCRR Arrange: `. The filename is the REAPER Action list entry, so it is the primary UI.
- **Headers:** every script carries ReaPack-shaped comments (`@description`, `@author`, `@version`, `@about`). The suite's ReaPack package ships the Lua (per-source `type="script"`, installed under `Scripts/LCRR/Remote/arrange/`; entry scripts `LCRR_Arrange_*.lua` register as actions); the release zip does not. The bridge starts with REAPER through `LCRR: Install startup hook` (ReaPack) or the `install.ps1` line (suite ADR 0002 amendment).
- **Architecture:** pure planners over plain tables, plus thin appliers that are the only `reaper.*` callers that write. `lib/` uses vanilla API only, no SWS. See ADR-0001. Every action is a headless core (request table in, result table out, never a dialog) with thin front ends: the script is the dialog front end, and the bridge (`lib/bridge/`, `docs/bridge.md`) is the other. Results are codes and fields, and the words are in `lib/text/`. See ADR-0008.
- **Changing what a script shows or logs** changes a transcript in `spec/fixtures/dialogs/`. Re-record with `LCRR_RECORD_DIALOGS=1 busted spec/dialog_spec.lua`, then read the diff before committing. An unexpected diff there means behaviour changed.
- **Errors vs logs:** aborts and precondition failures use `ShowMessageBox`; screens are short (the verdict, what to do, a line per lasting effect) and the detail goes only to `<Project>.arrange.log` beside the `.RPP`, never to the console. Check, Apply, Capture and Verify never call `ShowConsoleMsg`; only Show Bar Lines and Show Track Timebase do, because their whole output is a list. For Dropped Material that log is the **only** record. (Logs written before the migration are `*.tsb.log` and are left alone.)
- **Undo:** one `Undo_BeginBlock`/`Undo_EndBlock` per run. An empty plan creates no undo point at all.
- Scripts run immediately, with no confirmation prompt (Headroom is the one exception, ADR-0007). Undo plus the logged plan is the safety net, by explicit decision.
