# IEM Mix: balance every in-ear mix from one page

Status: ready-for-agent (grilled 2026-11-09; nothing built yet)

An engineer's mixing page for the whole band's in-ear mixes. Monitor is how a musician balances their own mix from a phone, one mix at a time. IEM Setup is how those mixes come to exist and what feeds them. IEM Mix is how one person balances all of them at once. Page `lcrr-iemmix.html`, app folder `apps/iemmix/`, CSS and IDs `iemmix-`, JS `LCRR.iemmix`. Home button label "IEM Mix".

## Why it exists

An engineer can already open each mix in Monitor, one at a time. IEM Mix earns its place with the two things neither Monitor nor REAPER's own mixer gives:

- **One source across all mixes**: a fader for Lead Vocal in every musician's mix, like sends-on-faders on a console.
- **Every level at once**: a live sources by mixes grid, to spot an odd level and go straight to it.

## Decisions

### Scope

- Levels, pans, mutes, listening and snapshots. **No setup**: no adding, removing or renaming mixes or sends. An empty cell does nothing.
- Built for an engineer on a laptop or tablet (768px and wider), usually away from the REAPER computer, in soundcheck and during the show. On a phone it is not designed for: below 768px the panel stacks under the grid so nothing is lost, and that is all. Musicians keep using Monitor.
- Out for now: trimming a source across mixes in one move, signal meters, a master level row in the grid (master level is in the panel), typed dB values, snapshots that follow regions, locking a musician out of their mix.

### Architecture

- **Page only for everything except Snapshots**: levels, pans, mutes and Listen go through REAPER's web API, as Monitor does, and keep working without any Lua bridge.
- **Snapshots use IEM Setup's bridge** (`LCRR_IEM`). No third bridge. The web API can't do them safely: URLs truncate at about 1,026 characters, so recalling 8 mixes by 24 sources is about 18 sequential requests, not atomic, with no single undo step, and tracks can only be named by position or name. If the bridge is not running, only the Snapshots controls are unavailable, with a note saying why.
- Monitor's fader logic (`faderValue`, `faderPos`, write gating, the drag, the mute writer, `fader.js`) moves to `shared/` so both apps use one copy. Monitor's behaviour does not change.
- Pure logic in `www/lcrr/iemmix/js/core.js` with node tests; DOM wiring separate.

### What is on the grid

- **Columns** are mixes by Monitor's listing rule: `IEM_<name>`, exact and case-sensitive, at least one receive and one hardware output. A name on more than one track, listed or not, cannot be edited (every listed one still shows), because a mix is identified by name.
- **Rows** are sources with at least one send to a listed mix, in project order.
- A cell shows the send's level, dimmed when the send is muted. Empty cells are inert.
- **Several sends from one source to one mix**: the cell shows the first level with a `2x` tag and is read-only. It is fixed in IEM Setup or REAPER.
- A source whose **track is muted** is marked in its row header, because a muted track silences its post-FX pre-fader sends (measured, suite `CONTEXT.md`).
- **Track colours** show in the grid (a swatch by the source name) and tint the panel's fader fills.
- Name filter and sticky row and column headers, as in IEM Setup.

### The docked fader panel

- Grid and panel are visible together. Tap a source name to fill the panel with that source's send in every mix. Tap a mix name to fill it with that mix's sources and its master level. Tap a cell to bring up its fader, highlighted: the open panel stays if it holds the cell, otherwise a panel of the same kind opens for the cell's source or mix, and with none open the cell's mix. An empty cell does nothing.
- Each source row has a fader, a **pan control** and a mute. All must fit a 768px tablet. The **master row is level only**: no pan and no mute, because it is the mix's hardware output level.
- Faders follow Monitor's law: `value = pos^4 * CAP`, CAP +6 dB, relative horizontal thumb drag, an above-cap level never written by an upward move.
- On a laptop the **mouse wheel over a fader or an editable cell nudges it by 0.5 dB**, respecting the lock and the cap. A wheel step on a cell selects it as a tap does. One wheel movement stays on what it began on until the wheel is idle: an edit keeps changing that one cell or fader wherever the pointer goes, and a scroll stays a scroll. No text field for typed values.
- **Alt-click resets** a cell or level fader to 0 dB and a pan control to the centre, respecting the lock, as one undo entry.
- Master level is the hardware output's level (`SEND/0`), as in Monitor.
- No per-mix Solo: Monitor's Solo mutes the musician's other sources, so an engineer using it changes what that musician hears. Listen replaces it.

### Shared control

- Musicians and the engineer write the same sends and **the last move wins**. Monitor does not change. IEM Mix shows current values from its reads and the same read-hold rules as Monitor apply to a fader being dragged.

### The lock

- The page **opens locked**, read-only. One Unlock tap enables every control. It relocks when the connection drops or another project becomes active. There is no idle relock, so mixing is never interrupted mid-show. A manual **Lock** button locks it again at any time.
- "Another project" is told by a **project marker**: an ID the page keeps in project ExtState (section `LCRR_IEMMIX`, key `project_id`), read in the same poll as the track list. Unlock reads it; if empty it writes a random ID and needs the read-back to match, and a second tablet just reads the same ID. A changed or missing ID relocks and cancels any drag. If the marker can't be read or the read-back doesn't match, the page stays locked with a note saying why, with no fallback to track names. A write can still land in the up to 250 ms between a project switch and the next poll: the API can't close that gap. The marker's web API form is unmeasured until issue 12.
- One gate function, as in IEM Setup (`canEdit`), and every write goes through it.

### Listen

- One-tap Listen to any mix through the engineer's own headphone output. One mix at a time. Nothing changes for the musician.
- REAPER has no per-mix cue, so it runs on a **cue track**, `IEM-Cue` (exact, case-sensitive), inside the `IEMs` folder with master send off (confirmed 2026-11-10), with a hardware output to the headphones and a send from each mix to it, created by IEM Setup.
- The page finds each mix's cue send from its sends (`GET/TRACK/<t>/SEND/<y>`, `y` from `hwoutcnt` to `hwoutcnt + sendcnt - 1`, since hardware outputs are numbered before ordinary sends (inferred from one measurement), destination the cue track). A mix with no cue send has its Listen key disabled, with a note.
- **Listen switches the cue send's level, not its mute**: 1.0 on, 0 off, with no `e` suffix, so a Listen tap adds no undo entries (`.../MUTE/` adds one per change).
- Listen hears the mix's **balance, not Monitor's master level**, because the master is the level of the hardware output. Headphone loudness is the engineer's own, at the cue track or the interface.
- The state lives in REAPER and is read from the sends, so a reload or a second tablet shows it correctly. A REAPER undo can change which mix is being listened to (measured, issue 01), and the page follows it. Nothing changes for the musicians.

### Snapshots

- A **named list**, stored in the project (project ExtState through the bridge). Save with a name, overwrite and delete by press and hold (`LCRR.shared.hold`).
- Each stores level, pan and mute for every send, and each mix's master level, matched by **track GUID**.
- **Recall is manual**, of the whole band or one mix, confirmed by press and hold, and is **one REAPER undo step**.
- Recall overwrites anything musicians changed in Monitor since the save.
- **Saving, overwriting and deleting a snapshot cannot be undone**, because project ExtState ignores undo (measured, issue 01). They add no undo step. Press and hold is their only protection.
- A send that no longer exists is skipped and reported. A send added since the save is left alone.

### Changes to IEM Setup

- A new bridge command creates the cue track and its sends in one undo step, and offers it from the page. Newly created and adopted mixes get the cue send as well.
- The cue track needs its own output picker for the engineer's headphones: the existing `output` command refuses anything that is not a mix.
- The cue track is **excluded from the source rows**, so no cell can feed it back into a mix (a routing loop). Its name must not start with `IEM_`, so that it never becomes a mix.
- New bridge commands for snapshots: list, save, recall (whole band or one mix guid), delete.
- `wire.js` and `client.js` get a third user, which is the moment to do the move to `shared/` that `apps/iem/CONTEXT.md` lists as a candidate.

### Reading REAPER

- `NTRACK;TRACK` every 250 ms, as Monitor.
- The whole grid's receives in split requests (under the URL limit) once a second, and the panel's visible sends every 250 ms.
- Web requests run on REAPER's main thread. 8 mixes by 24 sources is 200 reads with the masters, 5 requests per sweep, measured at about 150 ms with room to spare at two sweeps per second (issue 01).

## Measured on real REAPER (issue 01, 2026-11-09)

Full results are in the suite `CONTEXT.md`.

- Send pan works on receives, -1 to 1, read back from the `SEND` line. It is not clamped by REAPER, so the page clamps. It follows `VOL`'s pattern: the value with no suffix, then `e` on release for one undo entry.
- A REAPER undo moves the cue send's level. Listen still switches by level: the effect is limited to the engineer's headphones, and the page shows the true state from the sends.
- Project ExtState ignores undo, so snapshot storage stands.
- The full grid costs about 150 ms per sweep with no visible effect on REAPER's main thread, on a 33-track project with no media or FX. A real project is checked in issue 12.

## Open points

- How the bridge's snapshot size behaves on a large project. ExtState replies of 4 MB are measured to work, so it should fit.
