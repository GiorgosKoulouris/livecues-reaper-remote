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

## ReaScript routing facts (verified on real REAPER 7.82, Windows, Nov 2026, IEM Setup spike)

- `InsertTrackAtIndex` at the end of the list puts the new track **outside** a closed folder. To extend the folder, set the old last child's `I_FOLDERDEPTH` to 0 and the new one's to -1.
- `DeleteTrack` **does not repair folder depth**: deleting the last child (-1) leaves the previous child at 0, so the folder stays open. A folder left at depth 1 with no children **swallows the next track** added after it.
- `ReorderSelectedTracks(CountTracks, 0)` moves a selected folder and its children to the end, keeping depths, sends and GUIDs. With `makePrevFolder` 2 a track moved after a folder's last child joins the folder, and REAPER fixes the depths.
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

## Still unverified (suite)

- ReaPack: the generated `index.xml` (one `webinterface` package whose `file` attributes keep the `lcrr/...` subfolders), install and update. Generate it with `npm run release -- --base-url ...`; no index is committed yet because no repo URL exists.
- `scripts/install.ps1` after the restructure (slices, folder symlinks with `-Link`, uninstall removing links without touching their targets): written in the devcontainer, which has no PowerShell. The same goes for its reaper-slice part (`-Resource`, `Scripts\LCRR\`), added 2026-11-07. Also the shared Lua slice (`shared/reaper/` laid in as `Scripts\LCRR\shared`, added 2026-11-09, IEM Setup issue 02), including `-Link`, where each bridge script's `<script folder>\..\shared` must resolve through the folder links.
- Behaviour with several project tabs open.
- The Arrange bridge and page in real REAPER: the `Scripts/__startup.lua` line that `install.ps1` adds (it registers the bridge with `AddRemoveReaScript` and runs it), whether `GetProjectStateChangeCount` stays still between a Check and an Apply, and how long an Apply holds the web interface. See `apps/arrange/docs/limitations.md`.
- The self-hosted fonts (`lcrr/shared/fonts/*.woff2`) from REAPER's web server: REAPER may not send a font content type. Browsers normally still use the face; if they do not, the system-ui fallback applies and the layout holds.
- The Silkscreen Desk look on a real phone and in a dark room: checked only against unit tests, `npm run serve` asset resolution and the design drafts, not in a browser.
- The home page and the suite footer in a real browser and on a phone: checked only by unit tests, a node sandbox run and asset-resolution checks against `npm run serve`.
