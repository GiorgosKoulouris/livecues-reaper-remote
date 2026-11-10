# IEM Setup: create and route the in-ear mixes from a page

Status: ready-for-agent (grilled 2026-11-09; nothing built yet)

An engineer's admin page for the IEM mixes that Monitor plays. Monitor is how a musician balances their own mix from a phone; IEM Setup is how those mixes come to exist and what feeds them. Page `lcrr-iem.html`, app folder `apps/iem/`, CSS and IDs `iem-`, JS `LCRR.iem`.

## Decisions

### Scope

- Create, rename and delete mixes; set each mix's hardware output; choose which tracks feed which mix in a matrix.
- "Inputs" means **receives only**. IEM Setup never touches a source track's record input, and an IEM track never takes a live hardware input.
- Built for an engineer on a laptop or tablet (768px and wider): a real grid with sticky track names and mix headers. On a phone it scrolls sideways and is not designed for. Musicians keep using Monitor.
- First-version extras: **copy routing from a mix** and **row and column toggles**.
- Out for now: a per-mix health check panel, saving a layout across projects, editing levels from the grid.

### Architecture

- REAPER's web API cannot create tracks or sends, rename tracks, set hardware outputs or list device channels, so IEM Setup is a page plus Lua, shaped like Arrange (`apps/arrange/docs/adr/0008`): headless cores, results as codes and fields, wording in the page.
- **Its own background bridge**, `LCRR_IEM_Bridge.lua`, with its own ExtState section (`LCRR_IEM`) and its own marked line in `Scripts/__startup.lua`. Same wire format as Arrange (`apps/arrange/docs/bridge.md`).
- **Shared transport.** The generic Lua (JSON, request parsing, runner loop) moves out of Arrange into a shared Lua folder, used by both bridges.
- Monitor stays page only and needs no change.
- Pure logic in `www/lcrr/iem/js/core.js` with node tests; DOM wiring separate; busted specs for the Lua (Lua 5.4).
- If the bridge is not running, the page shows a banner and cannot edit.

### What counts as a mix

- **Any track named `IEM_<name>`**, the same naming rule as Monitor, so the two apps agree. IEM Setup also shows incomplete mixes that Monitor does not list yet (no receive or no output).
- A mix is shown by `<name>`; the prefix is never typed.
- Names must be unique (Monitor can't open duplicates). Existing duplicates are shown so they can be renamed apart.
- Renaming a mix sends any phone that has it open back to the list. That is Monitor's existing behaviour.

### The IEMs folder

- A folder track named `IEMs`, created at the end of the track list on first use. New mixes go inside it.
- The folder and every mix share one colour, **picked in the page** and stored in the project. Changing it recolours the folder and all mixes in it.
- **Master send is off** on the folder and on every mix, so in-ear audio can't reach FOH.
- If tracks end up after the folder, the page offers **Move to end**. It never moves the folder by itself.
- The folder stays when its last mix is deleted, but as a plain track (`I_FOLDERDEPTH` 0) until the next mix is created. An empty folder at depth 1 swallows the next track added after it (measured, issue 01).
- REAPER doesn't repair folder depth when a track is deleted or appended, so the bridge sets the last child's depth itself, as part of the same undo step.

### Adopting a stray mix

An `IEM_` track outside the folder is shown as a stray with an **Adopt** button. Adopting, as one undo step:

1. moves it to the end of the folder;
2. turns master send off;
3. applies the shared colour;
4. converts all its sends to post-FX pre-fader.

Adopting can change what a musician hears (step 4), and that was accepted.

### Creating and deleting

- Create asks for a **name only**, plus an optional mix to copy from. The output can be set later.
- A mix with no output says so in its column header. It is not on the phones until it has a source and an output.
- Copy-from brings sources, levels, pans, mutes and signal point. It does not bring the output.
- Deleting a mix is press-and-hold (`LCRR.shared.hold`).

### Hardware output

- A mix has **at most one** hardware output, mono or stereo, picked from the audio device's named channels. Monitor's master fader controls only the first output, so more than one would break it.
- Sharing an output with another mix or the master is allowed and flagged.
- An adopted track with several outputs is shown read-only.
- With the audio device closed REAPER reports no channels. The picker is disabled with a message, and an existing output is shown by number.

### The matrix

- Columns are mixes. Rows are **every non-IEM track** in project order, indented by folder, with a name filter. Hidden tracks are listed.
- A folder parent can be a source (one "Drums" fader). If a folder and one of its children both feed the same mix, the cell warns about the double feed.
- A new send is **post-FX, pre-fader, 0 dB**. FOH fader moves don't reach the in-ears, but **muting a source track does** (measured, issue 01).
- An ON cell shows the send's level read-only, dimmed if muted. Levels stay Monitor's job.
- **Switching a cell off deletes the send at once, with no warning.** The source disappears from that musician's Monitor page. REAPER undo restores it. Off removes every send from that source to that mix.
- Sends on mixes already in the folder keep their signal point; a small mark shows one that isn't post-FX pre-fader. Only Adopt converts sends.
- Row and column toggles: bulk on is one tap; **bulk off is press-and-hold**.

### Guarding against accidents

- **The page opens locked**, read-only. One Unlock tap enables editing, with no per-cell prompts after that.
- Each operation is one REAPER undo step.

### On the wire

- Operations name tracks by GUID, not index, and are refused if a target is gone.
- Bulk operations send only the mix or source ID, so requests stay under the ~900-character limit.
- Every reply carries the active project, as Arrange's do.

## To check on real REAPER

Issue 01 settled the design's unknowns; the measured facts are in the suite `CONTEXT.md`. A mono output is a true downmix, and one undo block covers a whole operation, so every project change must be inside one.

Still unseen: channel names on a multi-output interface (the test machine had two outputs, named "Output 1" and "Output 2"). Issue 11 covers it.
