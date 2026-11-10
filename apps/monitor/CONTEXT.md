# Monitor

Each musician opens their own in-ear mix from a phone (`lcrr-monitor.html`). REAPER API facts are in the root `CONTEXT.md`.

## Terms

- **Mix**: a track named `IEM_<name>` with at least one receive and at least one hardware output. Shown by `<name>`.
- **Source**: a receive of the mix track, one row per source in the mix view.

## Behaviour decisions

- The page opens on the mix list every time; nothing is stored on the phone.
- A track is listed only if its name starts with exactly `IEM_` (case-sensitive), has a name after the prefix, at least one receive and at least one hardware output.
- Two listed tracks with the same name both appear with their track numbers and can't be opened: a mix is identified by its name.
- No listed mixes: the page shows setup instructions.
- Polls `NTRACK;TRACK` every 250 ms. A reply whose `TRACK` lines don't match `NTRACK` is ignored, so a partial reply never removes rows. Offline (2 failed polls) keeps the last list and shows a banner.

- Opening a mix reads its receives in separate requests (about 900 URL characters each), outside the poller. Rows come only from `y` -1 to -`recvcnt`; a receive line whose last field is -1 is ignored; a partial reply never removes rows; a reply for another track number than the current one is dropped.
- Every poll re-matches the open mix by name (`IEM_<name>`); gone or duplicated closes it and returns to the list with a message. The mix's track index is refreshed from the match.

- Faders: `value = pos^4 * CAP` (CAP +6 dB). Drag is horizontal, thumb only, relative, 3 px slop. An above-cap level is never written on load or by upward movement; the drag's offset follows the finger past either end so the way back starts at once. A drag that sent no level write sends no `e`. On release the pending value and the `e` go as one `;`-joined request, after any write in flight (one in flight per fader, 50 ms gate, latest value wins). The final request skips the 50 ms gate (not the one-in-flight rule). Every request passes `writeAllowed` when it goes out, and each pointer move re-checks it and cancels the drag if the row's source or the mix changed. Offline, mix closed or row gone: the drag is cancelled with no final write. A pointercancel counts as a release. Poll reads for a row are ignored while it is dragged, until its writes have landed, and if they began before that (`readToken`/`canApply`).
- Mute: a native button per row (click = acts on release; slide-away or scroll cancels). It sends `SET/TRACK/<t>/SEND/<y>/MUTE/<0|1>` from the on-screen state, never a level or `e`, only if `writeAllowed` passes. Taps are ignored while the row's mute write is outstanding; reads that began before that write settled (success or failure) can't change the button (`createMuteWriter` `readToken`/`canApply`, `holdLevels`' `heldMute`). Faders and Mute on a row hold independently. Disabled offline.

- Master fader: reuses `fader.create` with target `{ track: <mix>, y: 0, source: -1 }` (index always the number 0). Its level is read with `GET/TRACK/<t>/SEND/0` as the first command of the first receive request (same cycle, same 900-character limit); only a line for the mix's track with last field -1 and `hwoutcnt >= 1` counts. `applyReceives` still ignores y >= 0. `writeAllowed` passes it only for y 0, source -1 and a known level (`st.master` a number). Same read-hold and cancel rules as rows; built once when the mix opens, removed on close.
- Solo in my mix (issue 10): the API has no per-send solo, so S mutes the other receives and unmutes the soloed one, as plain mute writes through each row's mute writer (same stale check and read hold as M). A toggle: tap S again to restore. The soloed row's S is amber. Moving solo to another row works from the original states. Restoring puts back only what solo changed (a receive another phone or the engineer changed since is left alone; `core.soloPlan`/`restorePlan`). All or nothing: if any needed row is busy or fails the stale check, the tap does nothing. Kept in memory only: Back and `pagehide` restore best-effort; a reload, a lost connection or a locked phone leaves the mutes as they are, and M undoes them by hand. Disabled offline.
- Layout: a mix view row is one 48px line, the fader pill then S and M. The source's name and value (no unit on screen) sit inside the pill; the track colour tints the fill at 25%; a muted row dims (fill and mark to 45%, text to 80% so it stays above 4.5:1), and M on is a recessed face with a 2px red outline, never filled; amber is Solo's alone. With a mix open, the top bar holds the back button, the mix name and the connection chip. Master scrolls with the sources and leaves S's and M's slots empty so the 0 dB marks line up. From 640px wide, Master and the sources fill two columns.
- No level meters: decided against (issue 08).

## Code map

- `www/lcrr-monitor.html`; `www/lcrr/monitor/css/monitor.css`; `www/lcrr/monitor/js/core.js` (pure: `parseTrackReply`, `listMixes`, `findMix`, `parseSendReply`, `applyReceives`, `rowsFor`, `dbText`, `buildReceiveRequests`, `parseMasterReply`, `buildReadRequests`, `tracksKey`, and the parts of the fader that know Monitor's state shape: `writeAllowed`, `holdLevels`, `soloPlan`, `restorePlan`); `www/lcrr/monitor/js/monitor.js` (UI wiring). The fader itself is shared: `shared/www/lcrr/shared/js/fader-core.js` (`LCRR.shared.faderCore`: `CAP`, `faderValue`, `faderPos`, `setVolCommand`, `setMuteCommand`, `createMuteWriter`, `createFaderDrag`) and `fader.js` (`LCRR.shared.fader`: one fader, thumb, Pointer Events; takes a write target, reused by the master fader; Monitor passes `prefix: "monitor"` for its CSS classes). Page load order: `fader-core.js`, `fader.js`, then Monitor's `core.js`, `monitor.js`.

## Still unverified

- The page in a real browser and on a phone (issue 07), including solo.
