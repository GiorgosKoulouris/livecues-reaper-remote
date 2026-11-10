# IEM Setup

The engineer's admin page for the in-ear mixes Monitor plays (`lcrr-iem.html`). Decisions: `.scratch/iem/spec.md`. REAPER facts (measured in the issue 01 spike) are in the suite `CONTEXT.md`.

## Terms

- **Mix**: a track named `IEM_<name>`, exact and case-sensitive, with something after the prefix: Monitor's rule, so the two agree. Shown by `<name>`. IEM Setup also shows mixes Monitor does not list yet (no receive or no output).
- **IEMs folder**: the first track named `IEMs`. A mix inside it is *in the folder*; any other is a **stray** (shown, flagged, to be adopted by a later issue). A folder track at `I_FOLDERDEPTH` 0 is a plain track and holds nothing.
- **Source**: every other track, in project order, with its folder `depth` (0 at the top).
- **Send**: a receive of a mix. Level `vol` is linear gain; `mode` is `I_SENDMODE` (3 = post-FX pre-fader, what IEM Setup creates; anything else gets the POST or PRE mark); `muted` is the send's own mute.
- **Output**: a hardware output of a mix, `{ channel, mono }`, `channel` 0-based. A mix with none is "No output".
- **Double feed**: a folder track and one of its children both feed the same mix.

## The `state` command (issue 03)

Request `cmd=state`. Reply `{ v, command, project: { name, path }, status: "ok", colour, folder?: { guid, is_folder, tracks_after }, mixes: [ { guid, name, in_folder, master_send, outputs: [ { channel, mono } ], sends: [ { source (GUID), vol, muted, mode } ] } ], sources: [ { guid, name, depth, is_folder } ], device: { channels: [name] }, master_outputs: [ { channel, mono } ] }`. `device.channels` are the audio device's output names (`GetOutputChannelName`), empty while the device is closed; `master_outputs` are the master track's own hardware outputs (issue 06). `folder` is absent when no track is named `IEMs`; `tracks_after` is true while tracks sit after its last member (what makes the page offer Move to end). It is also true for an emptied folder (a plain track) with tracks after it, on purpose: `create` reopens the folder right after itself, so the new mix would not sit at the end, and Move to end then moves that one track. `colour` is the shared colour as `rrggbb`: the project's (ExtState `LCRR_IEM` / `colour`), else the default `3b82c4`. Mixes and sources are in project order. Refusals are `{ status: "refused", error: { code } }`: `bad_request`, `request_truncated`, `unknown_command`, `internal`. Wording is `words.js`; the recorded replies are `test/fixtures/bridge-replies.txt`.

## The write commands (issue 04)

Each names tracks by GUID, answers `{ v, command, project, status, ... }` and is **one undo block** (`Undo_BeginBlock2`/`Undo_EndBlock2`, `lib/core/undo.lua`); a refusal is decided before the block opens, so it leaves no undo point. Refusals are `{ status: "refused", error: { code } }`.

- `create` (`name`) -> `{ guid, folder_created }`. The name is trimmed and the prefix is the bridge's. Codes `empty_name`, `duplicate_name` (exact, case-sensitive, any mix, stray or not). The first create adds the `IEMs` folder at the end of the list (depth 1, master send off, shared colour) and the mix inside it (depth -1). Later creates go after the folder's last member: that member's depth moves to the new mix (the old one becomes 0), so a folder nested in another keeps closing both. An emptied folder (plain, depth 0 or a negative closing depth) is reopened: it becomes 1 and the mix takes its old depth minus one. Folder and mix get master send off and the colour; a folder that already exists is not touched otherwise.
- `rename` (`guid`, `name`) -> `{ changed }`. Codes `track_gone`, `not_a_mix`, `empty_name`, `duplicate_name`. A mix's own name (even one a duplicate shares) is `changed: false`, no undo step, so duplicates can be renamed apart.
- `colour` (`colour`, `rrggbb`) -> `{ colour }`. Code `bad_colour`. Stored in the project, applied to the folder and every mix inside it (not to a stray, not to sources).
- `move_to_end` (`guid` of the folder) -> `{}`. Codes `track_gone`, `not_the_folder`, `nothing_to_move`. Selects the folder and its members, `ReorderSelectedTracks(CountTracks, 0)`, restores the engineer's selection. Never runs by itself.

- `delete` (`guid` of a mix) -> `{}`. Codes `track_gone`, `not_a_mix` (the folder, a source and a bare `IEM_` are refused). `DeleteTrack` takes the mix's sends with it. REAPER does not repair folder depth, so in the same undo step ("IEM Setup: delete mix") a mix that closed levels (depth < 0) adds them to the previous track's depth (the folder's last mix gives the previous member its closing; the folder's only mix leaves the folder at 0, or at a negative depth if the mix closed beyond it; a stray inside another folder works the same way), and a mix that opened a folder of its own (depth > 0) adds that to the track that closed it. A mix that is the first track of the project has no previous track to hand its closing depth to; nothing is repaired and the delete still succeeds (a malformed project, covered by a spec). The page's key is press-and-hold (1 s, `LCRR.shared.hold`) in each mix's header, shown only while unlocked, through `write()`.

- `output` (`guid` of a mix, `channel` 0-based or `none`, `mono` `1`/`0`) -> `{ changed }` (issue 06). Set, replace and clear are one operation in one undo step ("IEM Setup: set output"): a mix with an output has it changed in place (so there is never more than one), `none` removes it. Mono is `I_SRCCHAN` 0 with `I_DSTCHAN` `channel | 1024`, stereo `I_DSTCHAN` `channel` (suite CONTEXT.md). Codes `track_gone`, `not_a_mix`, `multiple_outputs` (a mix with several outputs is read-only: the bridge refuses set and clear), `bad_channel` (not a whole number, outside the device, or a stereo pair running past the last channel), `no_device` (a set while the device is closed; a clear still works). An output already as asked is `changed: false`, no undo step.

There is no lock command: the lock is the page's.

## Page behaviour (this slice)

- Connection states and the heartbeat are Arrange's: the page knows the bridge runs only from its heartbeat changing; if it stops, a banner says so and no editing is possible.
- The page reads `state` when it becomes ready, every 3 s while visible, and when the tab is shown again. An identical reply leaves the grid untouched, so a refresh never moves its scroll.
- Grid: sticky row and column headers, name filter (case-insensitive substring), ON cells with the level read-only (dimmed and struck through when muted), POST/PRE tag on a send that is not post-FX pre-fader, `2x` tag on a double feed, "No output" in the column header. A send from a track that is not a source row (another mix) is not drawn.
- **The lock.** The page opens locked: the Unlock key is the only live control. One tap unlocks (the key then reads Lock). `core.canEdit(phase, unlocked)` is the single gate; `iem.js`'s `write()` checks it and every write goes through it, so every write command reuses it. The lock closes again when the bridge goes away or another project becomes the active one (a safety the spec does not list; kept on purpose).
- **Controls** (shown once the project is read, enabled when unlocked): a name field and Create; the colour input (a change sends `colour`); Move to end (shown only while `folder.tracks_after`); a Rename key in each mix's column header, which turns the name into a field with Save and Cancel (Enter and Esc work). Names are checked by `core.checkMixName` before sending (the bridge checks again); a refusal is worded by `words.js` and stays on screen until the next attempt. After every write the page re-reads the project.

## Conventions

- Names are exact and case-sensitive everywhere (`IEM_Bass` and `IEM_bass` are two mixes), as in Monitor. The spec does not say so; this is the decision.
- Cores refuse through `tracks.refusal(code)` and look a mix up with `tracks.find_mix(list, guid)` (`track_gone`, `not_a_mix`), so a new core does not copy that prelude.
- A blank channel name from the device is shown by its number (`words.channelName`).
- Touch targets in `iem.css` are a hard-coded `44px`; `DESIGN.md` has no touch-target token yet (open).

## Hardware output (issue 06)

- Picker per mix in its column header, shown only while unlocked: None, Mono per device channel, Stereo per pair from an even channel, plus the current output if the list does not offer it. Labels carry REAPER's channel names ("Mono 2 Output 2"). A mix with several outputs shows its outputs as text and "N outputs, read-only", no picker. With the device closed the picker is disabled with a note and the existing output is shown by number.
- A shared output is flagged in the header, never refused. `core.outputClashes` compares occupied channels (stereo = channel and channel + 1), against other mixes' outputs (all of them) and the master's hardware outputs.
- An open picker holds the render gate (`core.createPickerGuard`, from focus or press until a choice or blur), so a refresh cannot close it; the deferred rebuild runs once afterwards. The choice goes through `write()`.

## Still unverified

- Issue 06 in real REAPER, none of it seen yet: `CreateTrackSend(track, nil)` then `SetTrackSendInfo_Value` on category 1 for `I_SRCCHAN` and `I_DSTCHAN` (the spike set mono outputs this way, the page's whole set/replace/clear in one undo block was not run), `RemoveTrackSend(track, 1, 0)`, that a replace in place keeps the output's level, that `GetMasterTrack(0)` hardware outputs read like a track's, and the picker in a browser (a native `<select>` held open across a refresh, focus after a choice, touch). Channel names on a multi-output interface (the test machine had two outputs, "Output 1" and "Output 2"): the labels assume `GetOutputChannelName` names are usable as given, and the stereo pairs from even channels suit consecutive pairs only. Whether REAPER accepts a stereo pair starting on an odd channel is not tested (the picker never offers one; an existing one is shown).

- Issue 05 in real REAPER, none of it seen yet: `DeleteTrack` removing the mix's sends and hardware output with the track, the depth fix-ups (last mix, only mix, a stray inside another folder, a mix that was itself a folder) as one undo step, and that undo restores the track and the depths together. The fake project models `DeleteTrack` as "removes the track and receives from it, leaves other depths alone", as the suite CONTEXT.md measured. The hold key in a browser (pointer, touch and Space/Enter; the fill animation; that a hold survives a refresh: the grid rebuild is deferred while a hold key is down (`core.createRenderGate`) and runs once when the hold ends, and a release on the document also cancels it).

- Issue 04 in real REAPER, none of it seen yet: the first create (folder at the end, mix inside, depths), a later create, reopening an emptied folder, Rename, Move to end (and that the engineer's track selection comes back), the colour (`I_CUSTOMCOLOR` with `ColorToNative` and the 0x1000000 flag, so the track shows it in the TCP and arrange view), and that `InsertTrackAtIndex(index, false)` plus the depth edits behave as the spike measured with a folder that sits inside another folder.
- That one `Undo_BeginBlock2`/`Undo_EndBlock2` undoes a whole create or Move to end in one step, and that **project ExtState** (the stored colour, `SetProjExtState`) is rolled back with it, rather than staying while the track colours revert.
- `ReorderSelectedTracks(CountTracks, 0)` when the IEMs folder is itself nested in another folder, or when the track after it closes a parent: the spike measured only top-level folders. Move to end does not adjust depths itself.
- The page in a browser: the Unlock key, the create form, the colour input (a `change` fires when the picker closes, in every browser?), the rename field inside a sticky header. Only node tests and a stubbed-DOM smoke run of `iem.js` were done.

- The bridge in real REAPER: the `__startup.lua` line `install.ps1` adds for it (a second marked line beside Arrange's, `-- LCRR-IEM-BRIDGE`), the first load of `LCRR_IEM_Bridge.lua` as an action, the heartbeat from `LCRR_IEM`, and both bridges running together.
- `scripts/install.ps1` after the change that made its `__startup.lua` handling a loop over two bridges (written in the devcontainer, which has no PowerShell): install, re-install, `-Uninstall`, and that Arrange's line and the user's own lines survive each.
- The `state` reply against a real project: `GetTrackSendInfo_Value` with `P_SRCTRACK` for receives (measured in the spike for a send, used here for a receive), folder membership on a real nested project, and how long `state` takes on a project with hundreds of tracks (it runs on REAPER's main thread, every 3 s per open page).
- The page in a real browser: sticky headers on both axes, the grid's height and scrolling, the look in a dark room. Checked only by node tests and `npm run serve` asset resolution.
- The fonts and the shared styles from REAPER's web server (suite-wide, see the suite `CONTEXT.md`).

## Candidates

- `wire.js` and `client.js` are copies of Arrange's with another ExtState section. With two apps on the same format they could move to `shared/` with the section as a parameter.
