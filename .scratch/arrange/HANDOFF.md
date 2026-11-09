# Arrange: handoff

For a fresh session picking up the **arrange** app (the region Repack suite moving into LCRR). It's short on purpose and carries only what the files don't make obvious.

Read in this order:
1. `/CLAUDE.md` (suite rules, user rules: work on `dev`, never `main`, **no Claude/Anthropic co-author or attribution in commits**, ask questions with AskUserQuestion).
2. `.scratch/arrange/spec.md`: every decision, and the order of work. **Don't re-open settled decisions** without asking the user.
3. `.scratch/arrange/issues/01-bridge-spike.md`: what the real REAPER web API does with ExtState (also in `/CONTEXT.md`). Read it before building the bridge.
4. `apps/arrange/CLAUDE.md`, `apps/arrange/HANDOFF.md`, `apps/arrange/docs/decisions.md`, then `apps/arrange/docs/adr/0008-headless-cores-thin-front-ends.md`: the core contract the bridge builds on.

## Where things stand (2026-11-07, end of the step-4 session)

- **Steps 1 to 4 are done and have run in real REAPER** (7.82/win64): the bridge, started by `Scripts/__startup.lua`, and the page. Commits on `dev` up to `33875c3`. `npm test` (93 node, 768 busted) and `npm run check` pass; the 78 dialog transcripts are unchanged.
- **Step 4 in one paragraph.** `LCRR_Arrange_Bridge.lua` is a background defer script over the same cores as the dialog scripts (`lib/bridge/`: `service` requests and replies, `request`, `json`, `tokens`, `runner`). The page `lcrr-arrange.html` (`apps/arrange/www/`) talks to it through ExtState; contract in `apps/arrange/docs/bridge.md`. Apply needs the token of a Check that would proceed. The bridge silences REAPER's console (an `api` wrapper) and still writes the run log file. `install.ps1` adds and removes one marked line in `Scripts/__startup.lua`. The page's wording (`js/words.js`) is tested against replies recorded from the real Lua (`apps/arrange/test/fixtures/bridge-replies.txt`, `spec/bridge_contract_spec.lua`).
- **Verified on the host by the user:** the startup line starts the bridge after a REAPER restart; the page shows "Bridge running", and Capture, Check, Verify, the duplicate-names diagnostic and Apply all work from it, on `podium-dummy` and on the real project `Rehearsal_Current` (21 regions). **Apply takes under a second** (recorded in `spec.md`). Apply twice on the real project: the second run is a clean no-op except for the bug below, and after the fix the user judged the result correct. A Check followed by clicking around in REAPER and then Apply was refused by the check-token guard ("project changed"); the user accepts that.
- **A real engine bug was found and fixed (issue 02, `33875c3`).** `lib/project.lua` sorted envelope points with the unstable `table.sort`, so step pairs (two points at one time) came out in arbitrary order and the Automation Anchor planner read the wrong half, on the first Apply as well as the second, flipping Mute/Bypass values at shared bounds. Now ties keep read order (`sort_by_position`; `docs/decisions.md`). **Any Apply made before the fix on a real project may have written wrong automation values**; the old run logs list every anchor, so they can be compared with the original envelopes.
- **Host checks since the fix (user, 2026-11-07 ~19:54, `Rehearsal_Current.arrange.log`):** on the original `.rpp`, Apply 1 now anchors every BassDI Mute bound with the last half of its step pair (God start/end 1.0, Low Fall start 1.0, and so on, matching the file); the following Check says "already matches the timeline" with Padding EXACT; a second Apply wrote no log entry, which is correct (an empty plan with every anchor redundant logs nothing and creates no undo point). The bridge was stopped and restarted with the page open: all good. Check-token sensitivity: accepted as is.
- **Decisions made this session** (user): the bridge silences the console and keeps the log file; bridge and page in one session. **Mine, not asked (cheap to change):** a Check mints a token only when it would proceed; Apply is a plain button with a 1.5 s repeat-tap guard (no hold); the page replaces its result panel on each command.
- **Not seen yet in REAPER or a browser:** a Headroom Apply through the page's question; Show Bar Lines and Show Track Timebase (from the page or the Action list); Apply refusing after its Tempo Anchors (the "one undo step" message); the page on the tablet; how the page looks at desktop and tablet widths (nobody has reported on it; Check findings are long); the bridge being stopped and restarted while the page is open; `-Uninstall` removing only its `__startup.lua` line, and a second `install.ps1` not duplicating it (written without PowerShell to run it).
- **The user's `dev/reaper-projects/` files are uncommitted** (`Rehearsal_Current.*`, `podium-dummy.*`, `Backups/`) and so is `temp.txt` (an old copy of the step-4 prompt). Leave them alone unless asked; ask before committing any of them (the real project's `.rpp` and log are the user's data).

## Next steps, in order

1. **Phase 2 grilling** (user's call, 2026-11-07: ready). Phase 2 is the Arrangement editor in the page: drag the order, Headroom controls. It needs a grilling session before any code (`/mattpocock-skills:grilling`, or the `grilling` skill) and its decisions go in `spec.md`. Seeds, not decisions:
   - It **overturns reorg ADR-0003** (`apps/arrange/docs/adr/0003-arrangements-as-name-keyed-lua-sidecar.md`): the sidecar is authored only in a text editor, which is why Capture's output tells the user to edit the file by hand. Today the page cannot write an Arrangement at all except through Capture.
   - **Known trap: a Lua rewrite of a hand-edited sidecar loses its comments** (`lib/sidecar.lua` parses in a sandbox and `serialize`s from tables). Options to weigh: keep comments by editing text, write a separate machine-owned file, or accept and warn.
   - **The bridge's 900-character request limit**: an Arrangement of 21 regions with long names will not fit in one request, so the spec's "large payloads are sent in chunks" becomes real. Needs a chunk protocol in `docs/bridge.md`, `lib/bridge/request.lua` and `client.js`.
   - Who owns the file when it is also open in a text editor on the host (stale overwrite), concurrency with the check token (the token binds the name, not the contents), Undo, validation (reuse `sidecar.parse`), how Headroom's relative semantics (ADR-0007) are shown safely in a UI, omitted regions (Parked Material), and whether a page-edited Arrangement can be a new `bridge` command or needs a new core (ADR-0008: cores take a request table and never open a dialog).
2. **Release question, still open (user's):** see "What ReaPack is here" below. The release zip includes the page but not the Lua.
3. **Host checks not done yet** (not blocking): a Headroom Apply through the page (the Arrangement `This` had a +300 s Headroom on Outro), Show Bar Lines and Show Track Timebase, `install.ps1` twice then `-Uninstall` (look at `__startup.lua`), the page on a tablet and at desktop widths, and the "Applying…" display (Apply is under a second, so it barely shows). Record failures as issues from `03`.
4. **Housekeeping that remains on the host:** remove the old `Scripts\TSB\` actions. (Done in the repo: spike deleted, EnumProjectMarkers3 fallback deliberately kept, an end-to-end step-pair spec added.)

## What ReaPack is here

ReaPack is REAPER's package manager. Suite ADR-0002 says LCRR ships as **one** ReaPack package of type `webinterface` (main file `lcrr.html`), built by `npm run release -- --base-url ...` into `index.xml` plus a zip; users import the repository URL and ReaPack installs the files into `reaper_www_root`. Today the index lists only `www/` slice files, so a ReaPack or zip user gets the Arrange **page** but not the **Lua** (`apps/arrange/reaper/Scripts/LCRR/arrange/`: scripts, `lib/`, the bridge) or the `__startup.lua` line that `install.ps1` adds, so the page would sit on "Bridge not running" with no way for them to fix it. The planned step: have the same package also carry the Lua as `type="script"` sources (ReaPack scripts install under `Scripts/<repo>/...`, with `lib/` beside them, which must keep matching `get_action_context()`), and decide how the bridge starts there (ReaPack can't edit `__startup.lua`; the user would run the action once, or ReaPack's own "run at startup" handling). The spec marks "per-source `type="script"`" as "to verify". Nothing of the ReaPack index has ever been verified in a live ReaPack either (`/CONTEXT.md`). Until it is done, the decision is: hold the Arrange page back from the release, or ship the release as install.ps1-only for Arrange.

## Known gaps and traps

- **The token binds the Arrangement name, not the sidecar's contents.** Edit the sidecar between Check and Apply and Apply uses the new contents. The dialog front end has the same gap. Leave unless the user wants it.
- **Read `apps/arrange/HANDOFF.md` and `apps/arrange/docs/decisions.md` before changing any Lua.** Many things there look like bugs and aren't. Rule that found issue 02: a single clean run proves nothing about anything idempotent; run it twice and diff.
- REAPER serves web requests on its main thread, so every request hangs while the bridge works (spike facts in `/CONTEXT.md`). Requests stay under about 900 encoded URL chars.
- REAPER isn't reachable from the container. Keep the `.busted` pin `lua = "lua5.4"`. The container has no PowerShell and no browser: `install.ps1` and `arrange.js` can only be checked on the host.
- `spec/fixtures/repack_basic/` is the 4.6 GB live project. It exists only on the host. Never commit media.
- Lua scripts find `lib/` through `reaper.get_action_context()`, so `lib/` stays a sibling of the scripts (`spec/layout_spec.lua` guards this).
- Changing a bridge reply: update `docs/bridge.md`, `lib/bridge/service.lua`, re-record `test/fixtures/bridge-replies.txt` (`LCRR_RECORD_BRIDGE=1 busted spec/bridge_contract_spec.lua`), and `www/lcrr/arrange/js/words.js`. The Lua wording in `lib/text/` and the page's `words.js` say the same things and are kept in step by hand.

## Next-session prompt

```
We're continuing the "arrange" app (the REAPER region-Repack Lua suite in apps/arrange/).
Steps 1-4 are done and run in real REAPER (bridge + page), and issue 02 is fixed and
confirmed on the real project. This session is the PHASE 2 GRILLING: no code until it's done.

Read, in order: /CLAUDE.md, .scratch/arrange/HANDOFF.md ("Next steps" item 1 has the seeds),
.scratch/arrange/spec.md (phase 2 is mentioned under Scope), then apps/arrange/CLAUDE.md,
apps/arrange/CONTEXT.md, apps/arrange/docs/adr/0003-arrangements-as-name-keyed-lua-sidecar.md
(the decision phase 2 overturns), 0007 (Headroom is relative) and 0008 (headless cores, thin
front ends), apps/arrange/docs/bridge.md, apps/arrange/reaper/Scripts/LCRR/arrange/lib/sidecar.lua
and apps/arrange/www/lcrr/arrange/js/arrange.js. Look at a real sidecar:
dev/reaper-projects/Rehearsal_Current.arrangements.lua.

Then run the grilling skill (mattpocock-skills:grilling) on phase 2: the Arrangement editor in
the page (reorder, Headroom controls, create/duplicate/delete Arrangements). Ask one decision at
a time with AskUserQuestion, give your recommendation for each, and walk the dependency order
(where the source of truth lives and what happens to hand-written comments comes first). The
900-character request limit, the check token, undo, the stale-overwrite problem when the file is
also open in a text editor on the host, and ADR-0007's relative Headroom are all in scope. Record
the result in .scratch/arrange/spec.md (a phase 2 section, decisions only, not how) and write an
ADR in apps/arrange/docs/adr/ for anything that overturns an existing one; split the work into
issues in .scratch/arrange/issues/ (numbered from 03). Don't re-open settled decisions in the
spec without asking.

The release/ReaPack question (HANDOFF, "What ReaPack is here") is separate and mine to decide;
raise it at the end, don't fold it in. Don't commit the files under dev/reaper-projects/ or
temp.txt. Work on dev, never main, and don't add Claude/Anthropic as co-author.
```
