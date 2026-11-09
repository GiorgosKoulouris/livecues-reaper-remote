# Monitor: personal in-ear mixes from a phone

Status: ready-for-agent

Monitor (`apps/monitor/`, `lcrr-monitor.html`) gives each musician their own in-ear mix from a phone. V1 has the same features as REAPER's stock `more_me.html` page (added in REAPER 5.51; not part of SWS), rebuilt in the suite's look, with the stock page's faults fixed and level limits added.

`more_me.html` in this folder is Cockos's file, kept as a reference. Read it for behaviour only, do not copy its code, and **do not commit or ship it**. `.scratch/` is not gitignored.

## Scope

**In V1:** mix list, setup instructions, master fader, one row per source (name, track colour, level fader, dB readout, Mute), offline state, shared footer.

**Page only:** no Lua and no `reaper/` slice. Everything goes through REAPER's web API.

**Not in V1:** pan (not in stock, not wanted), access control, remembering a phone's mix, and the later issues: level meters, transport and song, solo in my mix.

## REAPER setup a mix needs

- A monitor track named `IEM_<name>`, for example `IEM_Drums`.
- At least one receive, one per source to monitor.
- At least one hardware output, going to the performer's output. The master fader controls the first one.
- Usually with its master send disabled.

## Behaviour

### Mix list

- The page opens on the list every time. Nothing is stored on the phone, and there are no per-musician links.
- A track is listed only if its name starts with exactly `IEM_` (case-sensitive) **and** it has at least one receive **and** at least one hardware output.
- The list shows the name without the prefix (`IEM_Drums` appears as `Drums`).
- Any phone can open any listed mix, within the suite's trusted-LAN assumption.
- Two listed tracks with the same name both appear, each with its track number.
- With no listed tracks, the page shows setup instructions based on the section above.
- Opening a duplicated name is not allowed: a mix is identified by a name that must be unique.

### Mix view

- Layout, top to bottom: mix name with a way back to the list, master fader, source rows in receive order, shared footer.
- A source row shows the source track's name and colour (neutral when it has none), a level fader, the level in dB and Mute.
- The master fader controls the track's first hardware output, which is send index 0 (hardware outputs come before ordinary sends, issue 01). Every listed mix has one, so the fader is always shown.

### Faders

Every fader, master and source, uses the same law:

- `value = pos^4 * CAP`, with `pos` from 0 to 1 and `CAP = 10^(6/20)` (about 1.995, +6 dB). `value` is REAPER's linear volume (1.0 = 0 dB).
- `pos = 0` is silence, `pos = 1` is +6 dB and 0 dB sits at about 84% of the travel, with a visible mark.

Dragging:

- A drag can start only on the thumb. Tapping the track does nothing, and the page still scrolls vertically.
- The drag is relative: the thumb moves by the distance dragged and never jumps to the finger.
- Works with touch and mouse.
- A press and release with no movement writes nothing.
- One writer per fader. While a fader is being dragged, poll replies don't move it.

Above the cap:

- A level set above +6 dB in REAPER shows its true dB, with the thumb parked at the end.
- The page never writes it on its own. Upward movement from there writes nothing. Downward movement follows the fader law, so the level drops to just under +6 dB as soon as the drag moves down.

Writes:

- At most one write per fader per 50 ms, latest value wins.
- On release, first send the latest value without a suffix if it hasn't gone out yet, then end the move with `SET/TRACK/<t>/SEND/<y>/VOL/<value>e`. The `e` request doesn't set the level (issue 01), so it must never be the only write carrying the final value.
- This applies to every fader, including the master one. Each drag adds an "Adjust send volume" undo entry (accepted, same as stock's source rows).

### Mute

- Acts when the finger lifts. Sliding away first cancels it.
- It sends an explicit state worked out from what's on screen (`SET/TRACK/<t>/SEND/<y>/MUTE/<0|1>`), so a double tap or a second phone can't flip it the wrong way. Releasing on Mute never writes a level. Each actual mute change adds one "Toggle send mute" undo entry in REAPER (accepted).

### Safety

- The open mix is matched by its name on every poll, and its track index is refreshed from that match.
- If the name has gone or is now on more than one track, the mix closes at once, faders stop writing and the page returns to the list with a message saying why. It never guesses. This also covers switching project tabs.
- Before any write, the page checks that the mix's track index and the row's source (`other_track_index`) still match the latest poll, and drops the write if not.
- A request for a send that doesn't exist still gets a normal-looking reply: silent, with `other_track_index` `-1` (issue 01). Rows come only from indexes within `recvcnt`, and a receive line with `other_track_index` `-1` is ignored, so a removed receive never shows as a silent row.
- Offline (`LCRR.shared.guard`, 2 failed polls): the page says so and all faders and Mute stop working. A drag in progress ends without its final write.

## Web API use

Checked on real REAPER in issue 01.

| Purpose | Request | Reply |
|---|---|---|
| Track count | `NTRACK` | `NTRACK\t<n>` |
| All tracks | `TRACK` | `TRACK\tnumber\tname\tflags\tvol\tpan\tpeak\tpos\twidth\tpanmode\tsendcnt\trecvcnt\thwoutcnt\tcolor` |
| Source | `GET/TRACK/<t>/SEND/<-n>` (`-1` is the first receive) | `SEND\tt\ty\tflags\tvol\tpan\tother_track_index` |
| Master | `GET/TRACK/<t>/SEND/0` | same; `other_track_index` is `-1` for a hardware output |
| Set level | `SET/TRACK/<t>/SEND/<y>/VOL/<value>` | |
| Set mute | `SET/TRACK/<t>/SEND/<y>/MUTE/<0\|1>` | `flags & 8` means muted |

- Poll every 250 ms (`intervalMs`). Stock polls at 10 ms; REAPER handles web requests on its main thread and several phones will be polling at once.
- Keep each request under about 900 encoded URL characters (see the 1026-character limit in the root `CONTEXT.md`). A large mix is split over more than one request, and replies from a partial set must not remove rows.
- Track parsing stays in the app until a second app needs it (`shared/CLAUDE.md`).

## Faults in stock that must not come back

Taken from reading the source, not observed on REAPER.

1. Releasing anywhere on a source row, including on Mute, sends that row an end-of-move request. Issue 01 showed `e` doesn't set the level, so this most likely adds a stray undo entry rather than changing what's heard.
2. The mix's track index is worked out only when it's first selected, so adding or moving tracks can redirect the page to another track.
3. Name lookup takes the first match, so duplicate names control the first track.
4. The master fader's command uses a non-numeric send index (`NaN`) and has no end-of-move marker.
5. Listeners are added again on every poll reply.

## Testing

- Pure logic in `www/lcrr/monitor/js/core.js` (`LCRR.monitor.core`, UMD), tested from `apps/monitor/test/` as in Podium: reply parsing, mix list rule, name matching, fader law and inverse, above-cap rule, write gating, request splitting.
- `npm test` and `npm run check` must pass before committing.
- Real REAPER and phone behaviour is checked in issues 01 and 07.

## Issues

| # | Issue | Status | Blocked by |
|---|---|---|---|
| 01 | Web API checks on real REAPER | resolved | |
| 02 | App skeleton and mix list | resolved | |
| 03 | Mix view and lost-mix handling | resolved | 02 |
| 04 | Source faders | resolved | 03 |
| 05 | Mute | resolved | 03 |
| 06 | Master fader | resolved | 04 |
| 07 | Host and phone check | resolved | 04, 05, 06 |
| 08 | Later: level meters | wontfix | 07 |
| 09 | Later: transport and song | wontfix | 07 |
| 10 | Later: solo in my mix | resolved | 07 |
