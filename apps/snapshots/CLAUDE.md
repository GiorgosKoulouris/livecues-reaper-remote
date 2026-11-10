# Snapshots

The engineer's page for saving the project's mix under a name and restoring it in one press: `lcrr-snapshots.html`. A page plus a background Lua bridge, shaped like IEM Setup (`apps/iem/CLAUDE.md`). Read `CONTEXT.md` here, the suite `CONTEXT.md` (web API and ReaScript facts, the Snapshots spike results) and `.scratch/snapshots/spec.md` before changing behaviour.

Suite rules in `/CLAUDE.md` apply: work on `dev`, never `main`; **no Claude/Anthropic/AI co-author, trailer or attribution** in commits, docs or comments.

## Layout

- `reaper/`: a reaper slice (suite ADR-0001). `Scripts/LCRR/snapshots/LCRR_Snapshots_Bridge.lua` is the background script (ExtState section `LCRR_SNAPSHOTS`); `lib/` sits **beside it** and the script finds it through `reaper.get_action_context()`. The transport (JSON, request parsing, the ExtState loop) is the suite's shared Lua, `require("shared.bridge.*")`. `spec/layout_spec.lua` guards both.
- `lib/core/<command>.lua`: one headless core per command (request in, result table out, no dialogs, codes and fields only: Arrange ADR-0008). Today: `state.lua` (read-only). `lib/bridge/service.lua` maps a request to a core and builds the reply (`{ v, command, project, status, ... }`); it owns no ExtState or loop, so it runs under busted.
- `www/` and `test/`: the page (`lcrr-snapshots.html`, `lcrr/snapshots/{css,js}/`) and its node tests. Pure: `wire.js`, `client.js`, `core.js`, `words.js` (every sentence). `snapshots.js` is the DOM wiring. IDs and classes use `snapshots-`.
- `spec/`: busted specs; `spec/support/fake_project.lua` is the fake REAPER (grow it with the commands). `test/fixtures/bridge-replies.txt` is the bridge's real output, recorded by `spec/bridge_contract_spec.lua` (`LCRR_RECORD_BRIDGE=1 busted spec/bridge_contract_spec.lua`); `test/core.test.js` and `test/words.test.js` push it through the page's logic.

## Adding a command

Core in `lib/core/`, handler in `service.lua`, a scenario in the contract spec (re-record, read the diff), the page logic in `core.js`, wording in `words.js`, DOM in `snapshots.js`. A project change runs inside one `Undo_BeginBlock2`/`Undo_EndBlock2` pair, names tracks by GUID, and keeps its request under about 900 encoded characters.

## Commands

From the repo root, `npm test` and `npm run check` run busted and luacheck from inside `apps/snapshots/` (`scripts/lua.js`). Directly: `cd apps/snapshots && busted && luacheck .`. **Do not remove `lua = "lua5.4"` from `.busted`** (Debian's busted defaults to 5.1; REAPER embeds 5.4; `spec/toolchain_spec.lua` guards it).
