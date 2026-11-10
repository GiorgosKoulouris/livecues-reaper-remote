# LiveCues ReaperRemote (LCRR): suite context

A suite of remote-control pages for REAPER, served by REAPER's built-in web interface to a phone, tablet or desktop on the same trusted LAN. Apps: **Home** (`lcrr.html`, the launcher), **Podium** (`lcrr-podium.html`, the stage transport and cue list), **Monitor** (`lcrr-monitor.html`, personal in-ear mixes from a phone), **Arrange** (`lcrr-arrange.html`, a page over region Repack ReaScript actions through a background Lua bridge) and **IEM Setup** (`lcrr-iem.html`, the engineer's page for creating and routing the in-ear mixes, through its own background Lua bridge). Internet exposure is out of scope for the whole suite. App details: see `CONTEXT-MAP.md`.

## Terms

- **Slice**: a `www/` folder (`shared/www`, `apps/<app>/www`) holding part of `reaper_www_root` at its deployed paths. The slices are laid over each other at install, release and `npm run serve`.
- **Reaper slice**: an `apps/<app>/reaper/` folder, or `shared/reaper/`, holding part of REAPER's resource path (only `Scripts/LCRR/<part>/`, where `<part>` is the app or `shared`), laid in by `install.ps1` (suite ADR-0001 amendments). `Scripts/LCRR/shared/` is the Lua every bridge uses; a script reaches it as `require("shared.<module>")` after adding its parent folder to `package.path`.
- **Entry page**: a top-level `lcrr*.html` file; the only kind REAPER offers as "Default interface".
- **Shared library**: `lcrr/shared/` (`LCRR.shared.reaper`, `.poll`, `.guard`, `.hold`, plus `tokens.css`, `base.css` and the suite footer).

## REAPER web root facts (verified on real REAPER)

- REAPER lists only the **top-level** `.html` files of `%APPDATA%\REAPER\reaper_www_root` as "Default interface". Entry pages must sit there.
- REAPER **does serve files from subfolders** of the web root (`/lcrr/test.txt` returned the file, Nov 2026). Assets live under `lcrr/`.
- Never publish REAPER's web port from Docker; it shadows the host's port.

## REAPER web API facts (verified on real REAPER unless noted)

- Request `/_/CMD;CMD;...`. Lists are `/_/REGION` and `/_/MARKER` (NOT `REGION_LIST`/`MARKER_LIST`, which return empty). Combine with `TRANSPORT` in one request (the shared poller does this).
- Reply blocks are `REGION_LIST ... REGION_LIST_END` with lines `REGION\tname\tid\tstart\tend\tcolor` (markers: `MARKER\tname\tid\tpos\tcolor`); not guaranteed sorted. Names may be empty. They always describe the active project.
- Color: `0` = none; otherwise flag `0x1000000` plus RGB with **blue in the low byte** (`0x10000FF` is blue). Not BGR.
- Seek+play in one request: `SET/POS/<seconds>;1007`. Stop `1016`. Record `1013`.
- `TRANSPORT\t<playstate>\t<pos_s>...`; playstate is a bitfield (1 play, 2 pause, 4 record).
- A hung web server never fails a `fetch`, so requests need a timeout (3 s, in the shared poller) for offline states to appear. Offline = 2 consecutive failed polls (`LCRR.shared.guard`).
- ExtState (verified Nov 2026, REAPER on Windows, Chrome on localhost, plus a phone): `SET/EXTSTATE/<section>/<key>/<encodeURIComponent(value)>` reaches Lua's `GetExtState` byte-exact. `GET/EXTSTATE/<section>/<key>` replies `EXTSTATE\t<section>\t<key>\t<value>`, with `\t`, `\n` and `\\` escaped in the value. A key that was never set replies with an empty value (HTTP 200). Replies of 4 MB work.
- **Request URLs are silently truncated at ~1026 chars** of path (`/_/` included, measured on the encoded URL), still with HTTP 200.
- REAPER handles web requests on its **main thread**: while a script blocks it, every request waits (a 3 s Lua block made a `SET` take 3064 ms). Round trips through a defer script take about 94 ms.
- Sends (verified Nov 2026, one track with two receives, one hardware output and one ordinary send): `GET/TRACK/<t>/SEND/<y>` replies `SEND\tt\ty\tflags\tvol\tpan\tother_track_index`. `y` is `-1`, `-2`... for receives in order; `0` was the hardware output and `1` the ordinary send, even with the send created first. `other_track_index` is `-1` for a hardware output. A **missing index still replies** with a normal-looking line (flags 0, volume 0, `other_track_index` `-1`), so bound reads with the counts in `TRACK` (`sendcnt` field 10, `recvcnt` 11, `hwoutcnt` 12). `NTRACK` excludes the master.
- `SET/TRACK/<t>/SEND/<y>/VOL/<v>` sets the level with no undo entry. `.../VOL/<v>e` **does not set the level**: it ends the move and adds an "Adjust send volume" undo entry, so send the value without a suffix first. `.../MUTE/<0|1>` sets mute explicitly (flag 8) and adds one "Toggle send mute" undo entry per actual change; repeating the same state adds none.
- `SET/TRACK/<t>/SEND/<y>/PAN/<v>` (verified 2026-11-09, IEM Mix issue 01) sets a receive's pan with no undo entry; `v` is -1 to 1 and reads back as field 5 of the `SEND` line. **It does not clamp**: 1.5 is stored and read as 1.5, so clamp before writing. `.../PAN/<v>e` **does not set the pan**: like `VOL`, it ends the move and adds an "Adjust send pan" undo entry, so send the value without a suffix first (both in one `;`-joined request work).
- For an ordinary send, `other_track_index` is the destination's track number as used in `/TRACK/<n>/` (1-based; measured the same day).
- A send level written with no `e` is not an undo point, but **any undo restores the level from the earlier snapshot** (measured the same day: a cue send set to 1 fell back to 0 whether the undone edit came before or after the write).
- Project ExtState **ignores undo** (measured the same day with `SetProjExtState` and `Undo_DoUndo2`): a value saved inside or outside a block survives undoing later edits, and undoing the block that saved it does not remove or restore it.
- Reading 8 mixes by 24 sources plus their masters (200 `GET/TRACK/<t>/SEND/<y>` in 5 requests of up to 900 characters, measured the same day on a 33-track project with no media or FX) took 147 ms on average and 159 ms at most, at one sweep per second and at two, with `NTRACK;TRACK` every 250 ms answering in about 25 ms. The longest gap between a defer script's ticks (47 ms) was no worse than idle (61 ms).

## ReaScript routing facts (verified on real REAPER 7.82, Windows, Nov 2026, IEM Setup spike)

- `InsertTrackAtIndex` at the end of the list puts the new track **outside** a closed folder. To extend the folder, set the old last child's `I_FOLDERDEPTH` to 0 and the new one's to -1.
- `DeleteTrack` **does not repair folder depth**: deleting the last child (-1) leaves the previous child at 0, so the folder stays open. A folder left at depth 1 with no children **swallows the next track** added after it.
- `ReorderSelectedTracks(CountTracks, 0)` moves a selected folder and its children to the end, keeping depths, sends and GUIDs. With `makePrevFolder` 2 a track moved after a folder's last child joins the folder, and REAPER fixes the depths.
- `ReorderSelectedTracks` **rewrites folder depths around the track it moves, even when the move changes nothing** (measured 2026-11-09, IEM Setup issue 11): a no-op move put a closing depth of -1 on the track after it, and handed back a depth the caller had just set on the previous track. Skip a move that changes nothing, and write any depth you need *after* the reorder, not before.
- `CreateTrackSend(tr, dest)` defaults here: `I_SENDMODE` 0 (post-fader), `D_VOL` 1, `D_PAN` 0, unmuted, channels 0. `CreateTrackSend(tr, nil)` creates a hardware output.
- `RemoveTrackSend` category is -1 receive, 0 send, 1 hardware output, the same as the other send functions. Its help text ("category is 0 for hardware outputs") is wrong.
- `GetTrackSendInfo_Value(..., "P_SRCTRACK")` and `"P_DESTTRACK"` return a usable `MediaTrack` userdata in Lua.
- `I_SENDMODE` 3 is post-FX pre-fader: the send survives the source fader at zero. 0 follows the fader, 1 is before the FX.
- **A track's mute silences its `I_SENDMODE` 3 sends**, unlike its fader.
- `B_MAINSEND` 0 on a folder child or on the folder each stops the signal reaching the master.
- A mono hardware output of a stereo mix is `I_SRCCHAN` 0 and `I_DSTCHAN` `<output index> | 1024`. It is a true downmix: left and right both reach that one output, and nothing reaches the next one.
- One `Undo_BeginBlock2`/`Undo_EndBlock2(..., -1)` pair is one undo step, including a `ReorderSelectedTracks` and folder depth repairs inside it. Undo restores REAPER's last snapshot, so changes made **outside** a block are not a step of their own and get lost or rolled back with the next undo. Every project change must be inside a block.
- With the audio device closed (`Audio_Quit`), `GetNumAudioOutputs` is 0 and there are no channel names.
- Two background defer scripts run side by side, both started from marked lines in `__startup.lua`. (The Arrange and IEM bridges do exactly this, one marked line each, in separate ExtState sections.)

## ReaScript automation and restore facts (measured 2026-11-10, REAPER 7.82 x64, Snapshots spike)

Fixture unless noted: an empty project with no media, one track with Volume, Pan and Mute envelopes and one send with a volume envelope, each value written once inside one undo block, compared with a run that wrote nothing.

- **Track and send `D_VOL` are stored values that an envelope does not change.** With an envelope at 0.25, `D_VOL` read 1 in Read and Trim, stopped and playing, while `GetTrackUIVolPan` and `GetTrackSendUIVolPan` showed 0.25 in Read (1 in Trim). Save and restore `D_VOL`/`D_PAN`, never the UI values. A track write of 0.5 read back 0.5 through playback, a seek and a stop. In Read mode the UI value stayed at the envelope's. What a `D_VOL` written under an envelope does to the audio was not measured.
- Showing a volume envelope (action 40406) on a track with its fader at 0.7 left `D_VOL` at 1.
- **`B_MUTE` written with `SetMediaTrackInfo_Value` adds points to an existing Mute envelope** in Touch, Write and Latch, stopped or playing, and in those modes through the global override. It adds none in Trim, Read or Latch Preview, or with override 0, 1 or 5.
- `D_VOL` and `D_PAN` on a track and `D_VOL`, `D_PAN` and `B_MUTE` on a send added no points of their own in any mode, on the envelopes that existed (track Volume and Pan, send volume). Not tested: send pan and mute envelopes, width envelopes, FX bypass envelopes.
- Write mode adds points just from playing, and the restored value did not appear in them. Recording behaves as playing.
- A track with no envelope gets none from these writes in Touch, Write or Latch.
- `GetTrackAutomationMode` does not change under the global override, so read both. `GetGlobalAutomationOverride` round-trips 0 to 5, where 5 is bypass. Track mode 5 is Latch Preview: it is accepted and reads back, though the reference lists only 0 to 4 for `I_AUTOMODE`. A send has its own `I_AUTOMODE` (-1 follows the track): 3 on a send of a Read track recorded that send's envelope and nothing else.
- **Finding active automation:** a track's `GetTrackEnvelopeByName` is nil when there is no envelope. A send's `P_ENV:<VOLENV` returns a valid pointer even with no envelope (0 points). `GetTrackEnvelopeByChunkName` returned non-nil for all of `<VOLENV`, `<VOLENV2`, `<VOLENV3`, `<PANENV`, `<PANENV2` and `<MUTEENV` with only Volume, Pan and Mute present, so it proves nothing by itself. Use: the envelope exists, `CountEnvelopePoints` > 0, and `GetSetEnvelopeInfo_String(env, "ACTIVE", "", false)` is `"1"`. `CountTrackEnvelopes` counts a send's envelope on the sending track.
- **The Master** reads and writes `D_VOL`, `D_PAN`, `D_WIDTH`, `B_MUTE`, `I_SOLO`, `B_PHASE` and `I_FXEN` like a track. Its hardware outputs work with `CreateTrackSend(master, nil)` and the send functions, category 1. A new project's Master here already had one hardware output. `GetTrackGUID` returns a GUID; whether it differs between projects was not measured.
- **`I_SOLO`:** REAPER's own solo action gave 2 here. 0, 1 and 2 round-trip. **Writing 5 or 6 reads back 0** (no solo) on a track with no solo defeat, despite the reference listing them.
- **Undo:** one `Undo_BeginBlock2`/`Undo_EndBlock2(..., -1)` pair is one step for track, Master, send and hardware output values, including `I_PANMODE`, dual pan, width, `I_SOLO`, `B_PHASE`, `I_FXEN` and `I_SENDMODE`; undo and redo both restored all of them. **A change made with no undo point is not brought back:** after a live write of 0.9 over a baseline of 0.2, undoing a later restore gave 0.2 on both track and send.
- **Time held:** writing 4 values per track and 3 per send across 64 tracks and 640 sends took 125 to 131 ms, and ending the undo block 3 ms (no media, no FX). Reading 10 values per track and 4 per send took under 2 ms. `SetProjExtState` of 34 KB read as 0.0 ms.
- **`SetProjExtState` did not mark the project dirty** (a fresh tab: `IsProjectDirty` stayed 0 and `GetProjectStateChangeCount` did not change), so a project whose only change is project ExtState may close with no prompt to save. `IsProjectDirty` is documented as always 0 if that preference is off, which was not checked.
- **`I_FXEN`** on 16 chains of 3 stock plugins (48 plugins), during playback: 3 ms, no audio or media underruns. Whether it clicks was not settled (the owner could not tell by ear), and third-party plugins were not tried.

## Verified: ReaPack install (2026-11-10, owner's live test, 1.1.0-beta1)

- Importing `https://raw.githubusercontent.com/GiorgosKoulouris/LiveCues-RRemote/dev/index.xml` and installing the `lcrr.html` package (index `LCRR`, category `Remote`, type Web Interface) works: the per-source `type="script"` entries are accepted, the web files keep their `lcrr/...` subfolders in `reaper_www_root`, the pages load, `LCRR: Install startup hook` starts the bridge after a REAPER restart, and the footer shows the version.
- 1.1.0-beta2 (same day): ReaPack update from beta1 to beta2 works; `LCRR: Remove startup hook` removes the marked lines (a user's own line stayed); uninstalling the package in ReaPack removes the pages and Lua. The Lua lands in `Scripts\LCRR\Remote\<part>\` (e.g. `Scripts\LCRR\Remote\arrange\`), so `shared` is `Scripts\LCRR\Remote\shared\` and the `..` lookup works there. ReaPack never touches `__startup.lua`, so after an uninstall the hook's lines stay until Remove startup hook is run; they are tolerant and harmless.
- 1.1.0-beta3 (same day): the owner reported that the live test passed after the repo rename to `livecues-reaper-remote`. The individual checklist results weren't recorded.

## Still unverified (suite)

- `install.ps1 -Uninstall` and re-install removing/replacing `__startup.lua` lines written by the ReaPack hook action (fixed 2026-11-10 after the owner saw the lines survive an uninstall: the filter matched the marker's `(managed by install.ps1)` suffix; it now matches the bridge id, like `hook.lua`). Guarded only by `test/startup-ids.test.js` (reads the script as text, no PowerShell here); needs a run on Windows.

- ReaPack on macOS (and anything but Windows): unverified. If per-source types ever fail on another ReaPack version: stop and re-discuss with the owner.
- After a ReaPack uninstall with the startup hook still installed, a restart with the stale lines: the owner saw the lines remain (by design) and reported no problem; no error text was recorded.
- `scripts/install.ps1` after the restructure (slices, folder symlinks with `-Link`, uninstall removing links without touching their targets): written in the devcontainer, which has no PowerShell. The same goes for its reaper-slice part (`-Resource`, `Scripts\LCRR\`), added 2026-11-07. Also the shared Lua slice (`shared/reaper/` laid in as `Scripts\LCRR\shared`, added 2026-11-09, IEM Setup issue 02), including `-Link`, where each bridge script's `<script folder>\..\shared` must resolve through the folder links.
- Behaviour with several project tabs open.
- The Arrange bridge and page in real REAPER: the `Scripts/__startup.lua` line that `install.ps1` adds (it registers the bridge with `AddRemoveReaScript` and runs it), whether `GetProjectStateChangeCount` stays still between a Check and an Apply, and how long an Apply holds the web interface. See `apps/arrange/docs/limitations.md`.
- The self-hosted fonts (`lcrr/shared/fonts/*.woff2`) from REAPER's web server: REAPER may not send a font content type. Browsers normally still use the face; if they do not, the system-ui fallback applies and the layout holds.
- The Silkscreen Desk look on a real phone and in a dark room: checked only against unit tests, `npm run serve` asset resolution and the design drafts, not in a browser.
- The home page and the suite footer in a real browser and on a phone: checked only by unit tests, a node sandbox run and asset-resolution checks against `npm run serve`.
