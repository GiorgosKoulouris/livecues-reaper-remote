# LiveCues ReaperRemote (LCRR): suite context

A suite of remote-control pages for REAPER, served by REAPER's built-in web interface to a phone, tablet or desktop on the same trusted LAN. Apps: **Home** (`lcrr.html`, the launcher) and **Podium** (`lcrr-podium.html`, the stage transport and cue list). Internet exposure is out of scope for the whole suite. App details: see `CONTEXT-MAP.md`.

## Terms

- **Slice**: a `www/` folder (`shared/www`, `apps/<app>/www`) holding part of `reaper_www_root` at its deployed paths. The slices are laid over each other at install, release and `npm run serve`.
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

## Still unverified (suite)

- ReaPack: the generated `index.xml` (one `webinterface` package whose `file` attributes keep the `lcrr/...` subfolders), install and update. Generate it with `npm run release -- --base-url ...`; no index is committed yet because no repo URL exists.
- `scripts/install.ps1` after the restructure (slices, folder symlinks with `-Link`, uninstall removing links without touching their targets): written in the devcontainer, which has no PowerShell.
- Behaviour with several project tabs open.
- The home page and the suite footer in a real browser and on a phone: checked only by unit tests, a node sandbox run and asset-resolution checks against `npm run serve`.
