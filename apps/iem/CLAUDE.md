# IEM Setup

The engineer's page for the in-ear mixes that Monitor plays: `lcrr-iem.html`. A page plus a background Lua bridge, shaped like Arrange. Read `CONTEXT.md` here, the suite `CONTEXT.md` (web API and ReaScript facts) and `.scratch/iem/spec.md` before changing behaviour.

Suite rules in `/CLAUDE.md` apply: work on `dev`, never `main`; **no Claude/Anthropic/AI co-author, trailer or attribution** in commits, docs or comments.

## Layout

- `reaper/`: a reaper slice (suite ADR-0001). `Scripts/LCRR/iem/LCRR_IEM_Bridge.lua` is the background script; `lib/` sits **beside it** and the script finds it through `reaper.get_action_context()`. The transport (JSON, request parsing, the ExtState loop) is the suite's shared Lua, `require("shared.bridge.*")`, reached by also adding the script's parent folder to `package.path`. `spec/layout_spec.lua` guards both.
- `lib/core/<command>.lua`: one headless core per command (request in, result table out, no dialogs, codes and fields only: Arrange ADR-0008). Today: `state.lua` (read-only), `create.lua`, `adopt.lua`, `rename.lua`, `colour.lua`, `move_to_end.lua`, `delete.lua`, `output.lua`, `cell.lua`, `bulk.lua` (row and column) (writes, each in one undo block through `undo.lua`; `tracks.lua` holds the shared track/folder reading). `lib/bridge/service.lua` maps a request to a core and builds the reply (`{ v, command, project, status, ... }`); it owns no ExtState or loop, so it runs under busted.
- `www/` and `test/`: the page (`lcrr-iem.html`, `lcrr/iem/{css,js}/`) and its node tests. Pure: `wire.js` (request/reply format, heartbeat), `client.js`, `core.js` (matrix, dB, phase) and `words.js` (every sentence). `iem.js` is the DOM wiring. IDs and classes use `iem-`.
- `spec/`: busted specs; `spec/support/fake_project.lua` is the fake REAPER (tracks, folder depth, receives, outputs). `test/fixtures/bridge-replies.txt` is the bridge's real output, recorded by `spec/bridge_contract_spec.lua` (`LCRR_RECORD_BRIDGE=1 busted spec/bridge_contract_spec.lua`), and `test/core.test.js` / `test/words.test.js` push it through the page's logic. A change to a reply's shape fails the busted spec; a field the page doesn't know fails the node tests.

## Adding a command

Core in `lib/core/`, handler in `service.lua`, a scenario in the contract spec (re-record, read the diff), the page logic in `core.js`, wording in `words.js`, DOM in `iem.js`. Every project change runs inside one `Undo_BeginBlock2`/`Undo_EndBlock2` pair (suite `CONTEXT.md`), names tracks by GUID, and keeps its request under about 900 encoded characters.

## Commands

From the repo root, `npm test` and `npm run check` run busted and luacheck from inside `apps/iem/` (`scripts/lua.js`). Directly: `cd apps/iem && busted && luacheck .`. **Do not remove `lua = "lua5.4"` from `.busted`** (Debian's busted defaults to 5.1; REAPER embeds 5.4; `spec/toolchain_spec.lua` guards it).
