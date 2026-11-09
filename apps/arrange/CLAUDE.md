# Arrange

The region Repack suite: REAPER ReaScript (Lua) actions that lay a project's regions back down in a different order, carrying everything inside them along. Scope is deliberately narrow: **regions and markers only**. Migrated from the private ReaperScripts repo (ex-`apps/reorg`) in step 2 of `.scratch/arrange/spec.md`. Step 4 added the bridge (`LCRR_Arrange_Bridge.lua`) and the page `lcrr-arrange.html`.

Suite rules in `/CLAUDE.md` apply: work on `dev`, never `main`; **no Claude/Anthropic/AI co-author, trailer or attribution** in commits, docs or comments.

## Start here

`HANDOFF.md` is the entry point. It carries only what nothing else does: REAPER is not reachable from the container, the run-it-twice rule, API traps, the fixtures, and what has never been run. Then **`docs/decisions.md` before "fixing" anything surprising**. The engine was tested by hand at length on real projects.

| File | What it holds |
|---|---|
| `CONTEXT.md` | Glossary. The vocabulary below is defined here |
| `README.md` | Setup, quick start, what to expect. Keep it in step with the actions |
| `docs/workflow.md` | The user-facing path end to end: capture, duplicate, reorder, check, apply, verify |
| `docs/actions.md` | Per-action reference: what each needs, changes and refuses on. Add a row here when adding a script |
| `docs/bridge.md` | The bridge's wire contract with the page: ExtState keys, request/reply format, commands, the check token |
| `docs/limitations.md` | What the suite will not do, and why |
| `docs/decisions.md` | Decisions that look like bugs and are not |
| `docs/adr/` | Eight ADRs: architecture, splitting, storage, bar alignment, verification, the injected tempo oracle, Headroom's non-idempotence, headless cores with thin front ends |
| `research/reaper-scripting.md` | Sourced ReaScript API research, tagged primary vs secondary. **Prefer it to recollection** |

Open work: `.scratch/arrange/` (spec, issues numbered from `02`). `#N` in code and docs means an issue of the retired ReaperScripts GitHub repo: historical, not tracked anywhere now.

## Layout

- `reaper/`: a **reaper slice**, mirroring REAPER's resource path as `www/` mirrors the web root (suite ADR-0001). Scripts in `reaper/Scripts/LCRR/arrange/LCRR_Arrange_<Verb>.lua`, with `lib/` **beside them**: each script adds its own folder to `package.path` via `reaper.get_action_context()` and requires `lib.<module>`. `spec/layout_spec.lua` guards this.
- Inside the slice, `lib/` holds the planners and appliers, plus `lib/core/<action>.lua` (one headless core per action) and `lib/text/<action>.lua` (its wording). Each `LCRR_Arrange_<Verb>.lua` script is only the dialog front end over its core (ADR-0008).
- `spec/`: busted specs, `spec/support/` (`fake_reaper.lua`, `core_env.lua` for driving cores, `script_harness.lua` for running whole scripts) and `spec/fixtures/` (golden records, see `HANDOFF.md`). `spec/fixtures/dialogs/` holds the dialog transcripts `spec/dialog_spec.lua` compares against.
- `www/` and `test/`: the page (`lcrr-arrange.html`, `lcrr/arrange/{css,js}/`) and its node tests. `js/wire.js` (request/reply format, heartbeat), `client.js` (one call over the shared fetch) and `words.js` (every sentence) are pure and tested; `arrange.js` is the DOM wiring. IDs and classes use `arrange-`. `test/fixtures/bridge-replies.txt` is the bridge's real output, recorded by `spec/bridge_contract_spec.lua` (`LCRR_RECORD_BRIDGE=1 busted spec/bridge_contract_spec.lua`), and `test/words.test.js` pushes it through `words.js`. A change to a reply's shape fails the busted spec; a field `words.js` doesn't know fails the node test.
- `lib/bridge/`: the bridge front end (`service.lua` requests and replies, `request.lua`, `json.lua`, `tokens.lua`, `runner.lua` the ExtState loop). The wire contract is `docs/bridge.md`: read it before changing either end.
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
- **Headers:** every script carries ReaPack-shaped comments (`@description`, `@author`, `@version`, `@about`). The suite's ReaPack package does not ship the Lua yet (later step).
- **Architecture:** pure planners over plain tables, plus thin appliers that are the only `reaper.*` callers that write. `lib/` uses vanilla API only, no SWS. See ADR-0001. Every action is a headless core (request table in, result table out, never a dialog) with thin front ends: the script is the dialog front end, and the bridge (`lib/bridge/`, `docs/bridge.md`) is the other. Results are codes and fields, and the words are in `lib/text/`. See ADR-0008.
- **Changing what a script shows or logs** changes a transcript in `spec/fixtures/dialogs/`. Re-record with `LCRR_RECORD_DIALOGS=1 busted spec/dialog_spec.lua`, then read the diff before committing. An unexpected diff there means behaviour changed.
- **Errors vs logs:** aborts and precondition failures use `ShowMessageBox`; plan output goes to `ShowConsoleMsg` and appends to `<Project>.arrange.log` beside the `.RPP`. For Dropped Material that log is the **only** record. (Logs written before the migration are `*.tsb.log` and are left alone.)
- **Undo:** one `Undo_BeginBlock`/`Undo_EndBlock` per run. An empty plan creates no undo point at all.
- Scripts run immediately, with no confirmation prompt (Headroom is the one exception, ADR-0007). Undo plus the logged plan is the safety net, by explicit decision.
