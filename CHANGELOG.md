# Changelog

## 1.1.0-beta3 (2026-11-10)

- install.ps1 -Uninstall (and a re-install) now also remove or replace the __startup.lua lines written by the LCRR: Install startup hook action; both match on the bridge id (test/startup-ids.test.js)
- The repository is now livecues-reaper-remote and main is its default branch: import the ReaPack URL from the README again
- GitHub: CI, tag-based releases, issue forms, pull request template and SECURITY.md
- The IBM Plex license text ships with the fonts

## 1.1.0-beta2 (2026-11-10)

- Test release to check ReaPack update, Remove startup hook and uninstall; no functional change from beta1 except the version number

## 1.1.0-beta1 (2026-11-10)

- ReaPack delivery: the index carries the web pages and the Lua (per-source type=script), index name LCRR, category Remote
- LCRR: Install startup hook and LCRR: Remove startup hook actions manage the bridge lines in Scripts/__startup.lua
- The suite footer shows the installed version
- README, CONTEXT.md and ADR 0002 describe the ReaPack path

## 2026-11-10

- Restructure as the LiveCues ReaperRemote (LCRR) suite (02b0cfb8dc)
- Podium polish: hover colors, whole-second times, padded rows, suite favicon (5a5f85d971)
- Tooling: install.bat wrapper and LCRR devcontainer (a09efdd8ac)
- Arrange: migrate the Repack Lua suite and split scripts into core and dialog front end (adca184b0e)
- Arrange: bridge front end and web page, fix step-pair order (issue 02) (0b0b388a82)
- Arrange: phase 2 spec, sidecar detection, edit core, check token, bridge commands (issues 03-06) (0d7b053c77)
- Arrange: Run and Edit tabs, Arrangement editor, Undo, clear applied Headroom (issues 07-09) (276de24c50)
- Arrange: envelope points survive tempo moves on beat tracks (issue 10) (96913ec8f5)
- Arrange: review follow-ups, docs consolidation, host-check notes (49d74e8921)
- Monitor: app skeleton, mix view, source faders, mute and master (issues 02-06) (b6c0e03a7d)
- Arrange: plain refusals, short results and trimmed hints (issues 13-16) (85c507e5fe)
- Monitor: compact one-line rows and solo in my mix (ac51569c13)
- Remove done scratch issues and stale files (869e9b30af)
- Rebrand to Silkscreen Desk: Impeccable docs, tokens, self-hosted IBM Plex fonts, new icon (0636cc1b1e)
- IEM Setup: spec, bridge, lock, mixes, delete and hardware outputs (issues 01-06) (9af3221647)
  - IEM Setup: spec, issues and host spike results (issue 01)
  - IEM Setup: move the bridge transport into shared Lua (issue 02)
  - IEM Setup: bridge with a state command and the read-only matrix page (issue 03)
  - IEM Setup: lock, create and rename mixes, the IEMs folder and its colour (issue 04)
  - IEM Setup: delete a mix by press-and-hold, folder depth repaired in the same undo step (issue 05)
  - IEM Setup: a hold survives a grid refresh, rebuild deferred while a hold key is down (issue 05)
  - IEM Setup: set, replace and clear a mix's hardware output, shared outputs flagged (issue 06)
  - IEM Setup: share the refusal and mix lookup across cores, drop stale comments, cover a first-track delete and blank channel names
  - IEM Setup: record the review decisions in CONTEXT.md
- IEM Setup: cells, bulk switches, copy and adopt, shared cleanups, compact bar (22e1e3f4ca)
  - IEM Setup: switch a matrix cell on and off, off removes every send of the pair (issue 07)
  - IEM Setup: switch a whole source row or mix column on (one tap) or off (press and hold) (issue 08)
  - IEM Setup: create a mix by copying another's sends, same undo step as the creation (issue 09)
  - IEM Setup: adopt a stray mix into the IEMs folder in one undo step (issue 10)
  - IEM Setup: pin adopting a folder-parent stray and send removal order in specs, note Monitor check as unverified
  - IEM Setup: own class for the Copy from list, simpler bulk count and request flags
  - IEM Setup: one tracks.is_source for cell, bulk and create
  - IEM Setup: open_slot and new_track live in tracks.lua, not create.lua
  - IEM Setup: cell, row and column share one switch
  - IEM Setup: the send-copy settings live next to add_send in cell.lua
  - IEM Setup: delete and adopt share one depth repair
  - IEM Setup: one helper encodes the on flag in the client
  - IEM Setup: row and column wording and writes come from one lookup by kind
  - IEM Setup: mark issues 02-10 resolved with their commits in the tracker
  - IEM Setup: repaint the grid after a write if a refresh painted its keys disabled
  - IEM Setup: adopt skips a reorder that moves nothing and writes its depths after it, as REAPER rewrites depths around a reordered track
  - IEM Setup: issue 11 resolved, real-REAPER results and the reorder depth finding recorded
  - IEM Setup: remove the eleven resolved issues (kept in git history, results in apps/iem/CONTEXT.md)
  - IEM Setup: compact bar, tools row and grid headers; control height 44px on touch, 34px with a mouse
- IEM Mix: skeleton, live grid, docked panel, wheel and pan, shared fader (7e3f258673)
  - Shared: move Monitor's fader logic and fader control to shared/, Monitor behaviour unchanged
  - IEM Mix: app skeleton and the read-only live grid of sources by mixes, with name filter, 2x tag, muted-track mark and offline banner
  - IEM Mix: the lock, the docked panel with level faders, the stale check and holds, and faster panel reads
  - IEM Mix: mute and pan on every panel row, with the fader's drag controller generalised so the level and the pan share it
  - IEM Mix: mouse-wheel step on the level faders, 0.5 dB per notch through the fader's normal write path, one undo entry per burst
  - Shared: one copy of the mix listing rule and dbText, the pan functions back in IEM Mix, fader.js under the UMD wrapper with tests, and one copy of the pointer-drag wiring
  - IEM Mix: a project marker in project ExtState relocks on a project change, the wheel steps per notch with small events gathered, a name on an unlisted track is read-only, and a cell tap only highlights
  - IEM Mix: 44px hit areas on the pan thumb and the name buttons, the Lock key chamfered with an inset focus ring, and a Signal edge in place of the selection's box-shadow
  - IEM Mix: docs brought in line with the code, a DESIGN.md section for the pan control, panel and lock, and small cleanups
- IEM Mix: Listen, snapshots and recall, IEM-Cue track, shared bridge client (f0cfd4b528)
  - Shared: one bridge wire and client transport for Arrange and IEM Setup, with the ExtState section as a parameter
  - IEM Setup: a cue track (IEM-Cue) with a level-0 send from every mix, its own output, the send added by create and adopt, and no source row for it
  - IEM Mix: Listen, a key per mix that switches the level of its send to the cue track IEM-Cue, one mix at a time, read from the sends, with the missing cases disabled and a note, and gated by the lock
  - IEM Mix: save, list and delete snapshots through IEM Setup's bridge, with Overwrite and Delete by press and hold and no undo step
  - IEM Mix: recall a snapshot for the whole band or one mix in one undo step, by press and hold, skipping sends that are gone and saying so
  - IEM Mix: recall one mix by the mix's short name, so the bridge's list of mixes holds it and the key reads Recall A, not Recall IEM_A
  - IEM Mix: recall counts a stored master level whose mix has no hardware output as skipped, and the result says output as well as source and mix
  - IEM Mix: Listen reads a mix's ordinary sends from after its hardware outputs, so a mix with two outputs still has its cue send found, and the layout key holds the output count
  - IEM Mix: the snapshot key labels and hold titles are pure sentences in snapshots.js, Listen's tap plan returns one command, and the Listen names say what they are
  - Shared: one browser fetch and id helper in the bridge client, used by Arrange, IEM Setup and IEM Mix instead of three copies
  - Docs: the Recall keys in the design system, IEM Mix and the browser io in the shared notes, and two comments that had gone stale
  - IEM Mix: key labels come from one table, mixByNumber replaces three lookups, the recall note counts skipped levels (sends and master levels), and the Listen tap plan has a name
  - Docs: the send pan, send index, undo and project ExtState facts measured for IEM Mix, and the read cost of a sweep
- IEM Setup and IEM Mix: cue creation, summary line, track colour, one strip, look-only cells (83820df359)
  - IEM Setup: create and adopt make the IEM-Cue track when the project has none, every mix and the cue track get solo defeat, Create cue repairs a missing send or solo defeat, and the cue output asks to be chosen
  - IEM Setup: summary line with Mixes, Folder and Cue disclosures, hold keys for Adopt and Delete, keyboard grid navigation, and the IEM Mix spec
  - Design system: document IEM Mix Listen and wheel, the hard-line shadow exceptions, and add the .impeccable sidecar
  - IEM Setup and IEM Mix: a track's own colour fills its name cell at 25% over Key (the bridge reports a tint per source); the IEM Mix swatch is gone
  - IEM Setup and IEM Mix: one strip above the grid with the filter, legend and setup keys or Listen; the project name moves to the IEM Setup bar and only an empty project opens a panel; IEM Mix fits the screen with matching grid and panel boxes, panel column legends and aligned snapshot keys
  - IEM Mix: cells are look-only sliders; a click or the wheel on a cell brings up its fader highlighted; one wheel gesture stays on what it began on; hover lifts a cell's row and column; the Source column can be resized; Alt-click resets a level to 0 dB and a pan to centre
- ReaPack delivery: Lua in the index, startup-hook actions, version in the footer (97cd461d06)
  - ReaPack index carries the Lua; startup-hook install and remove actions
  - Footer shows the suite version; ReaPack changelog comes from CHANGELOG.md
  - Docs: ReaPack install, release steps, ADR 0002 amendment, unverified list
- ReaPack betas 1.1.0-beta1 and beta2 verified live; delivery docs and agent release guide (322e7b3f55)
  - 1.1.0-beta1: pre-release for the live ReaPack test, with its index.xml
  - Docs: ReaPack install verified live with 1.1.0-beta1
  - 1.1.0-beta2: test release for ReaPack update, remove-hook and uninstall
  - Docs: ReaPack update, remove-hook and uninstall verified live
  - ADR 0002: record the live update, remove-hook and uninstall results
  - Docs: bring every delivery mention in line with the ReaPack beta
  - Docs: agent-readable release and testing guide
- install.ps1 removes the hook's startup lines by bridge id; README on uninstall (93ccc1f498)
  - install.ps1 matches startup lines by bridge id so it removes the hook's lines too
  - README: say what uninstall does to __startup.lua
- Public launch prep: README, MIT license, CI, tag releases, community files, repo rename (4bd36670b0)
  - Docs: user-first README, CONTRIBUTING.md and MIT license
  - Untrack local working state: planning notes and tool settings
  - GitHub: CI, tag-based releases, and gh in the devcontainer
  - Community files: issue forms, pull request template, SECURITY.md, IBM Plex license
  - Docs: new repository name, main as the import branch, public issues and the launch plan
- Devcontainer: lock the github-cli feature (5de72688b5)
  - Devcontainer: lock the github-cli feature
- 1.1.0-beta3: first release under the new repository name and main import URL; release guide on tags (f0c2438e6f)
  - Release guide: tags go on stage, main moves through branch-flow
  - 1.1.0-beta3: first release under the new repository name and main import URL
  - Release guide: archive tags stay local
