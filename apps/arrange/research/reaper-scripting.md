# REAPER Scripting & Automation Capabilities — Research Notes

Research date: 2026-07-30. Purpose: inform later implementation of automation scripts for (1) applying "default states" to projects, (2) running exports/renders, and (3) manipulating regions/markers. This document is research only — no code was written or tested.

Every claim below is tagged with its source. **Primary** = official Cockos/reaper.fm documentation. **Secondary (first-party-adjacent)** = forum.cockos.com (run by Cockos, but user/community posts, not canonical docs). **Secondary (community)** = third-party sites (X-Raym, Ultraschall/mespotine mirrors, ReaTeam/Doc GitHub, script authors' GitHub repos, SWS extension project). Where a fact could only be confirmed via a secondary source, this is explicitly flagged — it should be treated as needing verification in REAPER itself before being relied upon in implementation.

A recurring practical obstacle during this research: the official function reference page (`reascripthelp.html`) is a single very large HTML file. Automated fetching tools repeatedly truncated it before reaching many alphabetically-later or deeply-nested entries, so several official function *descriptions* could not be retrieved verbatim even though the *signatures* could (signatures appear earlier/denser in the page and came through reliably). Where only the signature was retrievable, this is noted, and description content is instead sourced from mirrors/community docs and flagged accordingly.

---

## 1. ReaScript Overview

Source: [reaper.fm/sdk/reascript/reascript.php](https://www.reaper.fm/sdk/reascript/reascript.php) (primary — Cockos ReaScript intro page).

- **Languages supported**: EEL2 (Cockos' in-house C/JavaScript-like language, embedded, high performance, supports UI/graphics), **Lua 5.4** (embedded, no separate install, described as easiest to learn, good performance), and **Python 2.7–3.x** (must be installed separately by the user, gives access to third-party libraries, lower performance, no native UI/graphics support in ReaScript).
- **API naming convention** differs per language: EEL2 calls functions directly (`APITest()`), Lua prefixes with `reaper.` (`reaper.APITest()`), Python prefixes with `RPR_` (`RPR_APITest()`). Built-in REAPER actions (the same ones in the Action List) are invoked from any of these via `Main_OnCommand(commandID, 0)`.
- **Installation/execution model**: Scripts are created/loaded via the Actions window ("ReaScript: New…" or "Load…") and are saved into the `Scripts` folder inside REAPER's resource path. Once loaded they appear as entries in the Action List like any built-in action, and from there can be run on demand, bound to a keyboard shortcut, mouse/mousewheel modifier, MIDI/OSC controller, or a toolbar button.
- **Execution model**: By default a script runs once, top-to-bottom, and terminates, automatically wrapped in an undo point. For persistent/background behavior, scripts call `reaper.defer(functionName)` (Lua) to re-queue themselves each cycle, which lets a script "react to events, such as the current playback position, a track selection change, user input, etc." without blocking REAPER's UI thread; these can pair with a dockable ImGui/gfx window for a modeless UI.
- **Sandboxing/limitations**: The page explicitly warns "it is still possible to crash REAPER with scripts," though it states permanent damage (e.g. to projects) shouldn't normally occur. Python scripts are only as capable/available as the Python interpreter the user has installed on their machine — REAPER does not bundle Python.

## 2. Project State / "Default States"

### 2.1 Project Templates and Track Templates

- **Primary confirmation is thin** — the official SDK/ReaScript pages fetched did not describe template mechanics in detail; the description below is assembled from **secondary/community sources** (Sound on Sound feature, REAPER Accessibility Wiki, REAPER Blog) and should be spot-checked against the current REAPER User Guide PDF before implementation.
- **Project templates**: saved project files (REAPER project format) placed in the `ProjectTemplates` subfolder of REAPER's resource path; opening "New project from template" in the File menu instantiates a fresh, unsaved project pre-populated with whatever tracks/settings/items the template contained. (Source: [REAPER Accessibility Wiki — Project Templates](https://reaperaccessibility.com/wiki/Project_Templates), secondary/community — not independently verified against a primary Cockos page in this research pass.)
- **Track templates**: individual or multi-track configurations (FX chains, routing/sends, folder structure, track settings) saved with a `.RTrackTemplate` extension into the `TrackTemplates` subfolder of the resource path. Loaded via the Track Control Panel context menu → Templates → "Load track template," or via "Insert track from template." (Sources: [Sound on Sound — Reaper: Total Recall With Track Templates](https://www.soundonsound.com/techniques/reaper-total-recall-track-templates); [REAPER Accessibility Wiki — Track Templates](https://www.reaperaccessibility.com/wiki/Special:MyLanguage/Track_Templates) — both secondary/community.)
- **Programmatic application**: Not directly confirmed against primary docs in this pass. Because both project and track templates are ordinary REAPER project/track-chunk files on disk, a script could plausibly load one via the native "open/insert" actions (through `Main_OnCommand`) or by reading the template file's text and injecting it via `SetProjectStateChunk`/`SetTrackStateChunk`— but no official ReaScript function such as "ApplyProjectTemplate()" was found in the sampled portion of `reascripthelp.html`. **This should be verified directly against the full function index before implementation** (the page could not be fetched in full — see note in the intro).

### 2.2 Setting project-wide defaults via API

- **`GetSetProjectInfo`** (primary, signature confirmed from [reascripthelp.html](https://www.reaper.fm/sdk/reascript/reascripthelp.html)):
  ```
  C:     double GetSetProjectInfo(ReaProject* proj, const char* desc, double value, bool is_set)
  Lua:   number reaper.GetSetProjectInfo(ReaProject proj, string desc, number value, boolean is_set)
  Python: Float RPR_GetSetProjectInfo(ReaProject proj, String desc, Float value, Boolean is_set)
  ```
  This is the generic getter/setter for numeric project properties (tempo/time-signature-adjacent settings, render numeric settings such as `RENDER_SRATE`, `RENDER_CHANNELS`, `RENDER_BOUNDSFLAG`, `RENDER_STARTPOS`, `RENDER_ENDPOS`, etc. — see §3 for the render-specific keys). The full official enumeration of valid `desc` strings could **not** be retrieved verbatim in this research pass because the reference page kept truncating before reaching that section; the render-related subset below was instead corroborated from a real-world community script (see §3.1).
- **`GetSetProjectInfo_String`** (primary signature confirmed):
  ```
  C:     void GetSetProjectInfo_String(ReaProject* proj, const char* desc, char* valueOut, bool is_set)
  Lua:   string reaper.GetSetProjectInfo_String(ReaProject proj, string desc, string value, boolean is_set)
  ```
  Same idea for string-valued project properties (e.g. `RENDER_FILE`, `RENDER_PATTERN`, `RENDER_FORMAT`, `RENDER_METADATA` — see §3.1).
- **`SNM_SetIntConfigVar` / `SNM_GetIntConfigVar` / `SNM_SetStringConfigVar`**: these are **not native REAPER API** — they are provided by the **SWS/S&M extension** (a separately-installed third-party/community extension, though closely associated with Cockos and open-source). Confirmed via SWS's own GitHub repo and issue tracker: [reaper-oss/sws — SnM_Project.cpp](https://github.com/reaper-oss/sws/blob/master/SnM/SnM_Project.cpp), [SNM_GetStringConfigVar()/SNM_SetStringConfigVar() issue #987](https://github.com/reaper-oss/sws/issues/987) (secondary/community, but authoritative for the SWS extension itself). **Any automation plan relying on `SNM_*` functions must document a dependency on the SWS extension being installed** — it is not part of vanilla REAPER.
- **Startup actions**: "global startup action" functionality (run an action automatically whenever REAPER — or a new project — opens) also appears to be an **SWS/S&M extension feature** ("SWS/S&M: Clear global startup action" action exists in SWS), not a documented native REAPER capability, per the SWS GitHub findings above. This was not cross-checked against the native REAPER preferences (there may be a native per-project "on project load" startup action mechanism via Project Settings/Notes — not confirmed in this pass; note as open question).
- **ReaConsole**: a keyboard-driven command console for batch track operations (naming, selection, folder ops via commands like `/` for folder children, `!` to invert selection) is likewise an **SWS extension** feature, documented at the SWS/Standing Water Studios site, not part of native REAPER. (Source: [sws-oss/sws-web — reaconsole.php](https://github.com/reaper-oss/sws-web/blob/master/reaconsole.php), secondary/community.)

### 2.3 Project state chunks — `GetProjectStateChunk` / `SetProjectStateChunk`

- **Existence and signatures confirmed as present** in the official function index at [reascripthelp.html](https://www.reaper.fm/sdk/reascript/reascripthelp.html) (both function names appear in the page's function list), but the full description text could not be extracted in this pass — every fetch attempt at this specific pair of entries returned a "truncated" result, including via two alternate mirrors ([extremraym.com/cloud/reascript-doc](https://www.extremraym.com/cloud/reascript-doc/), [mespotin.uber.space Ultraschall mirror](https://mespotin.uber.space/Ultraschall/Reaper_Api_Documentation.html)). **This is a documented gap in this research pass — the exact signature/parameter semantics (e.g. buffer-size argument, `isundo` flag) should be pulled directly from REAPER's own API function browser (Help → ReaScript documentation, inside REAPER itself) before coding.**
- What is well-established from the wider REAPER community/ecosystem (secondary): these two functions read/write a project's (or a track's, via `GetSetMediaTrackInfo` sibling functions / `GetTrackStateChunk`) entire state as REAPER's native **RPP text chunk format** — the same nested, whitespace-delimited "chunk" syntax used in `.rpp` project files on disk (`<REAPER_PROJECT> … <TRACK> … <ITEM> …` etc.). This is the mechanism scripts use to manipulate project/track state that has **no dedicated getter/setter function** in the ReaScript API (e.g., certain render-matrix cell assignments, certain track visual/layout settings). Source for the chunk format itself: [ReaTeam/Doc — State Chunk Definitions](https://github.com/ReaTeam/Doc/blob/master/State%20Chunk%20Definitions) (secondary/community, community-maintained reverse-engineered spec, not an official Cockos document). Example marker/region line format documented there:
  ```
  MARKER 1 2 "Edit Marker" 8 23514367 1 B {8C98...E6B} 0 // Project marker
  ```
  and regions are represented as a **pair** of `MARKER` lines sharing the same index number (one for the region start, one implied by the region-end field / a second entry), with a bit in the flags field indicating region-vs-marker. Because this is a reverse-engineered community spec rather than an official Cockos file-format reference, exact field semantics should be validated empirically (e.g. by round-tripping `GetProjectStateChunk` output on a small test project) before an automation script parses/writes chunks directly. No render-settings-specific documentation was found in that source; it focuses on markers, tracks, items, envelopes, FX chains.

## 3. Rendering / Exports

### 3.1 Native ReaScript render-configuration API

- **`Main_OnCommand(command, flag)`** (primary signature confirmed): `void Main_OnCommand(int command, int flag)`. This is the general mechanism for triggering built-in REAPER actions (including render-related ones, e.g. "File: Render project to disk" and "File: Render project, using the most recent render settings") from a script by command ID, the same IDs visible in the Action List. Source: [reascripthelp.html](https://www.reaper.fm/sdk/reascript/reascripthelp.html) (primary, signature only — description text not retrieved in this pass). A relevant forum thread specifically documents an action for "Render project, using the most recent render settings," runnable via `Main_OnCommand`: [forums.cockos.com thread p=2767067](https://forums.cockos.com/showthread.php?p=2767067) (secondary/first-party-adjacent).
- **Render settings keys read/written via `GetSetProjectInfo` (numeric) and `GetSetProjectInfo_String` (string)** — the official page could not be fetched in full, so this list is reconstructed from a real, actively-maintained community ReaScript that reads/writes these exact keys against the live API: [cfillion/reascripts — "Apply render preset.lua"](https://github.com/cfillion/reascripts/blob/master/cfillion_Apply%20render%20preset.lua) (secondary/community, but functional code exercising the real API, so a reasonably strong secondary signal). Keys identified:
  - String-valued (`GetSetProjectInfo_String`): `RENDER_FORMAT`, `RENDER_FORMAT2` (primary/secondary output format encoders), `RENDER_PATTERN` (output filename pattern, supports wildcards like `$project`, `$region`, `$track`), `RENDER_METADATA` (embedded metadata tags). **`RENDER_FILE`** (the output directory) is noted in that script's comments as **not accessible via the API as of the version referenced (v6.43+)** — i.e., the render output *directory* may need to be set through the GUI or via a project-state-chunk edit rather than a clean setter. **This is a secondary-source claim and should be re-verified against current REAPER version behavior**, but is flagged here as a likely real limitation worth designing around.
  - Numeric-valued (`GetSetProjectInfo`): `RENDER_SRATE`, `RENDER_CHANNELS`, `RENDER_DITHER`, `RENDER_BOUNDSFLAG`, `RENDER_STARTPOS`, `RENDER_ENDPOS`, `RENDER_SETTINGS` (bitfield covering source selection / stems-vs-master / mono-as-mono etc.), `RENDER_NORMALIZE`, `RENDER_NORMALIZE_TARGET`, `RENDER_BRICKWALL` (limiter threshold, noted as added v6.37+), `RENDER_TAILFLAG`, `RENDER_TAILMS` (added v6.62+), `RENDER_FADEIN`/`RENDER_FADEOUT`, `RENDER_FADEINSHAPE`/`RENDER_FADEOUTSHAPE`.
  - `RENDER_BOUNDSFLAG` values (secondary, from web-search-aggregated summary of the API doc, not independently re-verified against the primary page in this pass): `0` = custom time bounds, `1` = entire project, `2` = time selection, `3` = all project regions, `4` = selected media items, `5` = selected project regions. **Flagged for verification** since it was not obtained via a direct successful fetch of the primary page.
- Because a full, verbatim copy of these keys' official descriptions could not be pulled from `reascripthelp.html` in this pass, **before implementation, someone should open REAPER itself → Help → ReaScript documentation (bundled, searchable, not paginated the way the web copy is) and pull the canonical key list**, since the web version proved unreliable to fetch completely with the tools available here.

### 3.2 Batch / unattended / command-line rendering

Source: [ReaTeam/Doc — REAPER-CLI.md](https://raw.githubusercontent.com/ReaTeam/Doc/master/REAPER-CLI.md) (secondary/community-maintained GitHub doc cataloguing REAPER's own `-h`/`-help` command-line output; not an official Cockos web page, but it purports to directly document REAPER binary switches — cross-check against `reaper.exe -h` output before relying on it). Flags documented:

- **`-renderproject <file.rpp>`** — "render project and exit." This is the key flag for unattended/CI-style batch rendering: launch REAPER from the command line pointed at a project file with this flag and it renders (using the project's saved render settings) and quits without showing the UI for interaction.
- **`-peaktest`** — "dry run render project and report peak output level" (noted as added since REAPER 7.62) — useful for a validation-only pass without writing an actual render file.
- **`-fxoffline`** — load project with FX offline ("recovery mode," since 7.74).
- **`-batchconvert <filelist.txt>`** — batch converter mode: takes a text file listing source files plus an embedded `<CONFIG …>` block specifying sample rate, channel count, dithering, normalization, trimming/padding, and FX-chain application. This is REAPER's format-conversion batch tool (distinct from full project rendering) — relevant if the automation suite needs to bulk-convert already-rendered stems rather than render a project.
- **`-close[all][:save|:nosave][:exit]`** — close project(s), optionally suppressing the save prompt and/or exiting REAPER afterward — useful for scripting a clean unattended shutdown after a render.
- **`-saveas <file>`** — save the (just-created/loaded) project under a new path.
- **`-nonewinst`** — route file-opens/script-runs into an already-running REAPER instance rather than spawning a new one — relevant for pipelines that keep one REAPER instance alive and dispatch multiple jobs to it.
- **`-ignoreerrors`** — suppress load-error dialogs (important for unattended/headless runs where no one is present to click through a dialog).
- **`-nosplash`** — suppress the splash screen (minor, but relevant to fully headless/CI usage).

None of the command-line-flag documentation above was found on a `reaper.fm` first-party page during this pass — WebSearch surfaced only the ReaTeam GitHub mirror and forum discussion, not an official Cockos page enumerating CLI flags. **This entire subsection should be treated as secondary until cross-checked against `reaper.exe -h` / `reaper -h` output directly, or an official Cockos CLI reference if one exists.**

### 3.3 Region Render Matrix / stems

- The **Region Render Matrix** is REAPER's built-in feature for assigning specific tracks to specific regions so that rendering "all regions" produces one file per region containing only its assigned tracks — described in secondary sources as core to game-audio/sound-design workflows (many small named stems per region). Source: [X-Raym — Region Render Matrix Pack description](https://www.extremraym.com/en/download/reascripts-render-region-matrix/) (secondary/community) and forum thread [forum.cockos.com — Scripts: Render Region Matrix](https://forum.cockos.com/showthread.php?p=1917334) (secondary/first-party-adjacent).
- **Scriptability**: The same secondary source states "there are only a few actions related to this feature, and only 4 are available on the action list" — implying the matrix is only partially exposed through the native Action List (hence why third-party script packs like X-Raym's exist specifically to fill in matrix cells programmatically, apparently by manipulating track/region state rather than a documented "set render matrix cell" API call). **No dedicated ReaScript function for setting individual render-matrix cells was found** in the sampled portion of the official API reference; matrix-cell assignment likely lives inside the track's state chunk (see §2.3) rather than as a discrete getter/setter, but this was **not confirmed against a primary source** in this pass.
- **REAPER 6.59** added a feature described as "region render matrix via master" per the official REAPER Blog changelog post: [reaper.blog — What's New in REAPER 6.59](https://reaper.blog/2022/06/659-update/) (this blog is run by a longtime REAPER community figure covering official changelog content — treat as secondary/first-party-adjacent, not a Cockos-authored page itself). The blog post itself, as fetched, did not contain prose explanation beyond the changelog line item and video timestamp — the *mechanism* of the feature was not confirmed in this pass.
- **File-naming wildcards** for render-matrix output: secondary sources describe patterns like `$project\$region-$track` in `RENDER_PATTERN` producing one subfolder per region containing per-track files — consistent with the `RENDER_PATTERN` string key noted in §3.1, but the exact wildcard token list was not verified against a primary source here.

### 3.4 What's NOT cleanly exposed for rendering (per this research)

- Setting the render **output directory** (`RENDER_FILE`) is reported by a secondary source as not settable via the clean API as of the version it referenced — likely requiring a project-state-chunk edit or a GUI action instead of a getter/setter call. Needs re-verification against current REAPER.
- Individual **Region Render Matrix cell** assignment has no confirmed dedicated ReaScript function; existing community tooling appears to work around this via chunk manipulation and/or driving the small number of native actions rather than a rich matrix API.
- The full canonical enumeration of `GetSetProjectInfo`/`GetSetProjectInfo_String` `desc` keys could not be retrieved from the primary page in this pass (tooling truncation) — treat the §3.1 list as a partial, secondary-sourced reconstruction, not the authoritative full set.

## 4. Regions & Markers Manipulation

All signatures below have **confirmed primary sourcing** from [reascripthelp.html](https://www.reaper.fm/sdk/reascript/reascripthelp.html) unless noted otherwise.

| Function | Signature (Lua) | Notes |
|---|---|---|
| `AddProjectMarker2` | `integer reaper.AddProjectMarker2(ReaProject proj, boolean isrgn, number pos, number rgnend, string name, integer wantidx, integer color)` | Confirmed primary, full description retrieved: "Returns the index of the created marker/region, or -1 on failure. Supply wantidx>=0 if you want a particular index number, but you'll get a different index number if wantidx is already in use. color should be 0 (default color), or ColorToNative(r,g,b)\|0x1000000." Note `wantidx` is a *request*, not a guarantee — REAPER will reassign if the index is taken. |
| `EnumProjectMarkers3` | `integer retval, boolean isrgn, number pos, number rgnend, string name, integer markrgnindexnumber, integer color = reaper.EnumProjectMarkers3(ReaProject proj, integer idx)` | Confirmed primary, full description retrieved: "Enumerate project markers/regions by index. idx should start at 0 and increment. Returns false when no more markers/regions. isrgn is true if the entry is a region rather than a marker." **Note the two distinct index concepts**: `idx` is a plain 0-based enumeration position (loop counter), while the returned `markrgnindexnumber` is the marker/region's actual ID number as shown in REAPER's UI — these are *not* the same value and must not be conflated (see next row). |
| `SetProjectMarker4` | Signature retrieved from search-engine caching of the official page, not independently re-verified via direct fetch: `bool SetProjectMarker4(ReaProject* proj, int markrgnidx, bool isrgn, double pos, double rgnend, const char* name, int color, int flags)` (approximate — parameter list not independently confirmed in this pass). | A secondary source paraphrasing the official doc states: "SetProjectMarker4 differs from earlier versions in that markrgnidx represents the displayed marker/region ID number" — i.e. unlike the plain-integer `idx` used for enumeration, functions that *modify* a specific marker/region (this one, and `DeleteProjectMarker`) key off the **displayed ID number** (the same one users see in the UI and in `markrgnindexnumber` from `EnumProjectMarkers3`), not a sequential list position. **This distinction should be re-verified directly in-app** since the full official description text could not be fetched here. |
| `DeleteProjectMarker` | `boolean reaper.DeleteProjectMarker(ReaProject proj, integer markrgnindexnumber, boolean isrgn)` | Confirmed primary, full description retrieved: "Delete a marker. proj==NULL for the active project." Takes the displayed ID number, matching the `markrgnindexnumber` from `EnumProjectMarkers3`. |
| `CountProjectMarkers` | `integer reaper.CountProjectMarkers(ReaProject proj, integer &num_markersOut, integer &num_regionsOut)` | Confirmed primary. Description explicitly states this function is **"discouraged. see GetNumRegionsOrMarkers, GetRegionOrMarker."** — i.e. REAPER's own docs point scripts toward newer functions for counting; `CountProjectMarkers` is legacy. `num_markersOut`/`num_regionsOut` may be NULL. |
| `GoToRegion` | Not retrieved (page truncation) | Existence confirmed (appears in function index), but signature/description not retrieved in this pass. Should be pulled directly before implementation. |
| `InsertTrackAtIndex` | `void InsertTrackAtIndex(int trackidx, bool inMCP)` | Confirmed primary signature; description text not retrieved (relevant to "insert default tracks" use case, not markers/regions, but included here since it surfaced during marker/region-adjacent fetches). |
| `GetUserFileNameForRead` | `boolean retval, string fn = reaper.GetUserFileNameForRead(string fn, string title, string defext)` | **Not independently verified in this pass** — this is long-standing, widely-used community knowledge (ReaTeam/community script corpora consistently use this shape), not a fetch from the primary reference. `defext` of `""` is the standard way to request no required extension. Used by `LCRR_Arrange_Apply`'s sidecar-import path (issue #5); re-verify directly in-app before relying on it further. |

### 4.1 Region "ordering" — how it actually works

No evidence was found of an independent, arbitrary "sort/order" field for regions distinct from their position and ID. Based on the confirmed function semantics above:

- Regions and markers are fundamentally identified by a **`markrgnindexnumber`** (the displayed ID, shared by both marker- and region-type entries, assigned when created via `AddProjectMarker2`'s `wantidx`, which is a *request* REAPER may or may not honor if the number is already taken).
- Their **timeline order is driven by position (`pos`/`rgnend`), not by the ID number** — i.e., "reordering" regions on the timeline in practice means changing each region's `pos`/`rgnend` via `SetProjectMarker4` (or moving it in the GUI), not reassigning some separate sequence field. The ID number is a stable identifier, not a display-order index — two regions can have IDs "5" and "2" while region "5" sits earlier in time than region "2" (REAPER's UI will still show them in whatever order the user created them / whatever ID they carry, but their *timeline position* is independent of that ID).
- The enumeration index `idx` used by `EnumProjectMarkers3` **does walk markers/regions in a defined order** (needs verification whether that's ID order or position order — not confirmed from the truncated description), but that is a read-time iteration convenience, not a persisted "order" property of the data model.
- **This entire subsection is a synthesis from the confirmed function semantics, not a direct quote from an official page discussing "reordering" as a concept** — REAPER's docs do not appear to describe region reordering as a distinct feature; it falls out of position + ID semantics. This should be validated empirically (e.g., inspect `EnumProjectMarkers3` iteration order against known ID/position combinations) before an implementation relies on assumed ordering behavior.

### 4.1a The `.RPP` `MARKER` flags field is a bitfield, not `isrgn` — **verified empirically**

**Source: direct observation of `spec/fixtures/repack_basic/before.rpp` (REAPER 7.78/win64), round-tripped through a real save.** This is the ADR-0005 validation loop working as intended, and it contradicts the obvious reading of the community chunk spec.

The 4th field of a `MARKER` line — the one immediately after the name — is a **flags bitfield**, not a boolean `isrgn`. In this project:

```
MARKER 13 436.03896372451351 "Sleep Tight" 1 0 1 R {FD3F...} 0 1   <- region, flags=1
MARKER 13 737.72120671516768 "" 1                                   <- its end line
MARKER 16 4390.6986233883144 "NES 16" 9 0 1 R {85D1...} 0 1        <- also a region, flags=9
MARKER 16 4571.6986233883144 "" 9                                   <- its end line
```

Both are regions. 18 carry `flags=1`, one carries `flags=9`. **Bit `0x1` is what means "region"**; the higher bits carry something else (unidentified — `0x8` appeared after the region was renamed and recoloured in the GUI). The ReaTeam spec's own example shows `8` in this slot for a plain marker, which is consistent with a bitfield and inconsistent with a boolean.

**Consequence for the ADR-0005 fixture parser: test `flags & 1 == 1`, never `flags == 1`.** An equality test silently drops regions — it dropped exactly one here, and did so while still producing a plausible-looking region list, which is the dangerous failure mode. The end-line of a region repeats the same flags value as its start line.

This does **not** affect `lib/project.lua`, which reads via `EnumProjectMarkers3` and gets a proper boolean `isrgn` back. It affects only code that parses `.RPP` text.

### 4.1b Timebase: `C_BEATATTACHMODE` and the `.RPP` `BEAT` field — **verified empirically**

**Source: `GetMediaTrackInfo_Value` run in REAPER 7.78/win64 against `spec/fixtures/repack_basic/before.rpp`, with a controlled UI change, cross-checked against the `.RPP` text.** This closes a gap the web docs could not — `reascripthelp.html` truncated on every fetch.

Confirmed values for `C_BEATATTACHMODE`:

| Value | Meaning | Evidence |
|---|---|---|
| `-1` | project default | Observed on 4 tracks; matches `BEAT -1` in the `.RPP` |
| `0` | time | **Observed directly**: setting one track's Timebase to "Time" in the TCP context menu moved its reported value from `2` to `0`, with nothing else changed |
| `2` | beats (position only) | Observed on 28 tracks; matches `BEAT 2` in the `.RPP` |
| `1` | beats (position, length, rate) | **Confirmed empirically** (see §4.1c): repositioning an item on a mode-`1` track stretches its content. Previously inferred by elimination only. |

**The `.RPP` `BEAT` field and `C_BEATATTACHMODE` share one encoding.** The fixture has 32 tracks: 4 × `BEAT -1` and 28 × `BEAT 2` in the file, and the API reported `-1` on exactly those 4 and `2` on the other 28. Track-level `BEAT` lines appear at 4-space indent inside `<TRACK>`; item-level ones at 6-space indent inside `<ITEM>`, where the ReaTeam spec documents `-1 = use track timebase`.

Two consequences:

- **Read timebase through the API, not by parsing `BEAT`.** The encoding matches, but the `.RPP` omits the field when unset, so a parser has to model "absent" as well — the API just returns `-1`.
- **This is why issue #10 exists.** Beat-based material stores position in QN, so its absolute time is derived from the tempo map; deleting a tempo marker slides it. This project is 28/32 tracks beat-based with 114 item-level overrides, so tempo-map edits are not safe by default on it.

Also confirmed in the same run: **`_VERSION` reports `Lua 5.4`**, matching the primary Cockos page and the `.busted` interpreter pin.

### 4.1c Moving an item's position across the three timebases — **verified empirically**

**Source: manual test in REAPER 7.78/win64, repositioning one item under each timebase and listening/inspecting the result.** Directly relevant to any code that moves an item's position (e.g. `SetMediaItemInfo_Value(item, "D_POSITION", ...)`, which is what the item-carrying half of the Repack applier needs) rather than just reading the mode.

| `C_BEATATTACHMODE` | Repositioning the item... |
|---|---|
| `0` (time) | **No stretch.** |
| `2` (beats, position only) | **No stretch.** |
| `1` (beats: position, length, rate) | **Stretches the content.** This is the first direct observation of mode `1` in this project — see the table above, §4.1b. |

This confirms the mechanism issue #9 already worried about in the abstract ("beat-based content would otherwise be displaced twice") is real and reproducible, and narrows it: the hazard is specific to full beat-attachment (mode `1`), not to beat-based timebase in general. Modes `0` and `2` — which is 28 of this project's 32 tracks (§4.1b) — can have their items repositioned directly with no special handling. Only mode `1` needs a guard or a fix, and no track in the fixture currently uses it, so this has not yet been tested against a real mode-`1` track in this project, only confirmed as a general REAPER behavior.

Per-item timebase overrides have no confirmed `GetMediaItemInfo_Value` key (§4.2, `LCRR_Arrange_ShowTrackTimebase.lua`'s comment) — an item could carry its own mode independent of its track's. There is a workaround, though, not a dead end: §4.3's `GetItemStateChunk` reads the item's own chunk text, which carries a `BEAT` line when overridden, and `lib/project.lua` uses exactly that to compute a per-item `timebase_safe`.

**A second hazard, distinct from stretching, and confirmed against real data: rewriting the tempo map moves every beat-based item.** Mode `2` is safe to *reposition* (no stretch, above) but it is not immune to tempo-map edits — the item's time is derived from the map, so changing the map changes where the item sits. Measured across a real run's saved project: `apply.tempo_moves` moved all 69 tempo markers, and exactly the **114 items carrying an item-level `BEAT 2` override moved with them** (matched by `IGUID` across the before/after `.RPP`; largest displacement `131.6s`, and the shifts are non-uniform because each depends on the item's own beat position). The **216 items with no override did not move at all**, on the same tracks. Perfect correlation, 114/114 and 216/216.

The consequence for the applier: **an item's position is not a stable identity across a tempo-map edit.** `lib/apply.lua` splits its item handling in two because of this — `apply.locate_items` resolves every `MediaItem*` before the first tempo write, and `apply.item_moves` does the writing afterwards. Writing the planned `to` is still correct (it is an absolute time, and the item re-anchors to whatever beat now sits there); only the lookup had to move earlier. Note this is *not* fixed by setting tracks to time-based — these are item-level overrides, which win over the track and over the project setting.

### 4.1d The modern region/marker family — **PRIMARY, verbatim from the v7.78 reference** (issue #11)

The functions REAPER's own reference points to when it calls `CountProjectMarkers`
and `EnumProjectMarkers*` "discouraged". Issue #11 was filed as `needs-info`
because these signatures "truncated on every fetch, including via two mirrors"
and only a human in front of REAPER could read them. **That is no longer true:**
the `curl`-and-grep route of §4.5 retrieves them intact.

| Function | Lua signature (verbatim, v7.78) |
|---|---|
| `GetNumRegionsOrMarkers` | `integer reaper.GetNumRegionsOrMarkers(ReaProject proj)` |
| `GetRegionOrMarker` | `ProjectMarker reaper.GetRegionOrMarker(ReaProject proj, integer index, string guidStr)` |
| `GetRegionOrMarkerInfo_Value` | `number reaper.GetRegionOrMarkerInfo_Value(ReaProject proj, ProjectMarker regionOrMarker, string parameterName)` |
| `GetSetRegionOrMarkerInfo_String` | `boolean retval, string stringNeedBig = reaper.GetSetRegionOrMarkerInfo_String(ReaProject proj, ProjectMarker regionOrMarker, string parameterName, string stringNeedBig, boolean setNewValue)` |

Descriptions, verbatim:

- `GetNumRegionsOrMarkers` — "the total number of regions and markers in the
  project."
- `GetRegionOrMarker` — "get a single region or marker by internal index, or if
  index < 0, by GUID."
- `GetRegionOrMarkerInfo_Value` parameter names — `"D_STARTPOS"`, `"D_ENDPOS"`
  (= `D_STARTPOS` for markers), `"I_INDEX"` (internal index), `"I_NUMBER"`
  (displayed index number), `"I_LANENUMBER"` (settable, returned value
  read-only), `"I_CUSTOMCOLOR"`, `"I_DISPLAYEDCOLOR"`, `"B_ISREGION"`,
  `"B_UISEL"`, `"B_HIDDEN"`, `"B_VISIBLE"` (read-only).
- `GetSetRegionOrMarkerInfo_String` parameter names — `"GUID"` (read-only),
  `"P_NAME"`.

This is richer than a like-for-like replacement, and three points bear on #11:

- **It is a handle-based family**, not an enumerator: `GetRegionOrMarker` returns
  a `ProjectMarker*` that the `Info_Value`/`Info_String` calls then read. That is
  a different shape from `EnumProjectMarkers3`'s flat tuple, so switching
  `lib/project.lua` is a rewrite of the reader, not a substitution.
- **It makes `I_INDEX` and `I_NUMBER` explicitly distinct** — internal index
  versus displayed number — which is the same trap §4.1's `idx` versus
  `markrgnindexnumber` note already records, now named by the API itself.
- **It does not settle the iteration-order question.** "By internal index" says
  the index is stable and addressable, not that it is position-ordered, so
  `lib/project.lua`'s defensive sort by position should stay until a real run
  shows otherwise. #11 hoped this would make the sort unnecessary; nothing here
  supports dropping it.

`B_HIDDEN` and `I_LANENUMBER` have no equivalent in `EnumProjectMarkers3` and are
the strongest practical argument for eventually switching: a hidden region is
currently indistinguishable from a visible one to this suite.

**Used by `lib/project.lua` since #11, but still not run against REAPER** — the
tables above are documentation, not observation, and `EnumProjectMarkers3`
remains the only one of the two that has actually executed against the live
project. `project.snapshot` therefore *prefers* this family rather than
replacing the enumerator with it: all four calls are checked for existence
first, a build without them reads the old way, and a modern read that comes up
short of `GetNumRegionsOrMarkers`'s own count is discarded rather than trusted,
because a snapshot missing regions would plan a Repack over part of the
timeline and report success. Which reader ran is on the snapshot as
`region_reader`, and every script that snapshots reports it under its heading —
`LCRR_Arrange_ShowBarLines` in its console output, the rest in their logs.

### 4.2 Colors, names, nesting

- **Names**: plain strings, settable via `AddProjectMarker2`'s `name` param and (presumably) `SetProjectMarker4`'s `name` param — confirmed for the former, inferred for the latter pending full signature confirmation.
- **Colors**: `AddProjectMarker2`'s description (confirmed primary) states `color` should be `0` (default/theme color) or `ColorToNative(r,g,b) | 0x1000000` — i.e., colors are native RGB integers with a high bit flag (`0x1000000`) that must be OR'd in to mark the value as an explicit custom color rather than "unset."
- **Nesting**: No evidence of hierarchical/nested regions or markers was found in any source consulted (official or community). REAPER's marker/region model, per all sources here, is a **flat list** of markers and regions, each independently positioned and colored; regions do not contain child regions or markers as a first-class relationship. (Absence-of-evidence caveat: this wasn't the subject of a dedicated targeted search, so treat as provisional rather than a confirmed negative.)

### 4.3 Track/item enumeration and item state — used by item-carrying

**Not independently verified in this pass** — these are long-standing, extremely widely-used ReaScript functions (near-universal in community script corpora), not fetches from the primary reference. Needed by the item-carrying half of the Repack applier (moving items fully contained in a moved region, and reading their effective timebase safety per §4.1c).

| Function | Signature (Lua) |
|---|---|
| `CountTracks` | `integer reaper.CountTracks(ReaProject proj)` |
| `GetTrack` | `MediaTrack reaper.GetTrack(ReaProject proj, integer trackidx)` — `trackidx` is 0-based |
| `CountTrackMediaItems` | `integer reaper.CountTrackMediaItems(MediaTrack track)` |
| `GetTrackMediaItem` | `MediaItem reaper.GetTrackMediaItem(MediaTrack track, integer itemidx)` — `itemidx` is 0-based |
| `GetMediaItemInfo_Value` | `number reaper.GetMediaItemInfo_Value(MediaItem item, string parmname)` — `"D_POSITION"` (start, seconds) and `"D_LENGTH"` (length, seconds) are the two keys used here |
| `SetMediaItemInfo_Value` | `boolean reaper.SetMediaItemInfo_Value(MediaItem item, string parmname, number newvalue)` |
| `GetItemStateChunk` | `boolean retval, string str = reaper.GetItemStateChunk(MediaItem item, string strNeedBig, optional boolean isundo)` — returns the item's chunk text (the `<ITEM> ... >` block, matching `.RPP` syntax), used here to find an item-level `BEAT` override line that `GetMediaItemInfo_Value` has no confirmed key for (§4.1c: per-item timebase overrides are otherwise unreadable) |
| `DeleteTrackMediaItem` | `boolean reaper.DeleteTrackMediaItem(MediaTrack tr, MediaItem it)` — **the one destructive call this suite makes** (Dropped Material, `CONTEXT.md`). Same caveat as the rest of this table: widely used, not re-fetched from the primary reference in this pass. The applier does not read its return value; it locates the item by position **and** length first and errors if there is no exact match, so a wrong guess about the return convention cannot delete the wrong item |

Re-verify all of these directly in-app before relying on them further — none have been re-fetched from `reascripthelp.html` in this research pass.

### 4.3a `SplitMediaItem` — **sources conflict; treat as unresolved**

Needed by the splitting half of the Repack applier (ADR-0002, issue #6). Two fetches of the primary reference in the same pass returned **contradictory signatures**, so nothing here is safe to depend on:

| Source | Claimed signature | Claimed return |
|---|---|---|
| `reascripthelp.html` (fetch 1) | `MediaItem* SplitMediaItem(MediaItem* item, double timepos)` | a `MediaItem` |
| `reascripthelp.html` (fetch 2) | `int SplitMediaItem(MediaItem* item, double snapoffset)` | "the index of the new item" |
| Community/search consensus (secondary) | `MediaItem reaper.SplitMediaItem(MediaItem item, number position)` | the **right-hand** split; the original item becomes the **left-hand** split; `nil`/NULL on failure |

The `int`/`snapoffset` variant is almost certainly a bad read — `snapoffset` is a `D_SNAPOFFSET` parameter name and returning a bare index is not the idiom used elsewhere for item creation — but "almost certainly" is not this repo's standard, and REAPER is unreachable from this container (HANDOFF.md), so it cannot be settled here.

**How `lib/apply.lua` works around it, deliberately:** the applier does **not** use the return value's identity at all. It splits, then re-locates both resulting pieces by position with the existing `find_item`, and treats "the expected right-hand piece is not there afterwards" as the failure signal. That is correct under either candidate semantics, and under the consensus one too, so the ambiguity cannot produce a wrong edit — only a clear error. **Do not "simplify" that back to trusting the returned handle** until the signature is confirmed in-app.

**The fade keys — resolved, primary (issue #15).** These were previously recorded here as unretrievable: "the primary reference's `SetMediaItemInfo_Value` key list did not come back, and the community mirrors served index pages only". That was a limitation of the **fetch tooling**, not of the source — the same one §4.5 documents for `TimeMap_*`. `curl`ing `reascripthelp.html` and grepping locally returns the full key list. Verbatim from the v7.78 copy, under `SetMediaItemInfo_Value`:

```
D_FADEINLEN : double * : item manual fadein length in seconds
D_FADEOUTLEN : double * : item manual fadeout length in seconds
D_FADEINDIR : double * : item fadein curvature, -1..1
D_FADEOUTDIR : double * : item fadeout curvature, -1..1
D_FADEINLEN_AUTO : double * : item auto-fadein length in seconds, if not greater than zero, no auto-fadein
D_FADEOUTLEN_AUTO : double * : item auto-fadeout length in seconds, if not greater than zero, no auto-fadeout
C_FADEINSHAPE : int * : fadein shape, 0..6, 0=linear
C_FADEOUTSHAPE : int * : fadeout shape, 0..6, 0=linear
```

Two things this settles that matter beyond the names:

- **Manual and auto are separate properties**, and the split preference writes the **manual** one. `repack_bars`' cut piece came back carrying `FADEIN 1 0.01 0 1 0 0 0` — the manual field set to REAPER's default 0.01 s, the auto field zero. So `apply.splits` overwrites `D_FADEINLEN`/`D_FADEOUTLEN`, which is a different pair from the `_AUTO` keys `apply.item_moves` clears, and the two passes do not interact: a cut creates no overlap, so it creates no auto-crossfade.
- **Only length is written, not shape or curvature.** `C_FADEINSHAPE` and `D_FADEINDIR` are equally preference-derived, so a fully machine-independent cut edge would pin them too. ADR-0002 specifies a length and nothing else, and inventing a shape decision here would be going beyond it. Recorded as a known narrowing, not an oversight — the audible difference a 5 ms fade's curve makes is far smaller than the 5 ms-vs-10 ms one this closed.

`regions.CUT_FADE` is therefore **planned and applied** as of issue #15. It has **not** run against real REAPER — see HANDOFF.md.

### 4.4 Tempo markers and track envelopes — read-only, used by the #12 refusal

**Verified empirically** against REAPER 7.78/win64: every function in this table ran during the #12 refusal's first live execution on `repack_basic`, and returned usable values (see the confirmations under the table). The *signatures* below are still community/recollection rather than re-fetched from `reascripthelp.html` — what the live run proves is that reading them this way works, not that every documented parameter is as described. `lib/project.lua` calls all of these, and **only reads** — the write side lives in §4.4a (tempo, issue #4) and §4.4b (envelope points, issue #8).

| Function | Signature (Lua) |
|---|---|
| `CountTempoTimeSigMarkers` | `integer reaper.CountTempoTimeSigMarkers(ReaProject proj)` |
| `GetTempoTimeSigMarker` | `boolean retval, number timepos, integer measurepos, number beatpos, number bpm, integer timesig_num, integer timesig_denom, boolean lineartempo = reaper.GetTempoTimeSigMarker(ReaProject proj, integer ptidx)` — `ptidx` 0-based. One marker carries both tempo and time signature; `measurepos`/`beatpos` express the same instant in beats |
| `CountTrackEnvelopes` | `integer reaper.CountTrackEnvelopes(MediaTrack track)` |
| `GetTrackEnvelope` | `TrackEnvelope reaper.GetTrackEnvelope(MediaTrack track, integer envidx)` — `envidx` 0-based |
| `GetEnvelopeName` | `boolean retval, string buf = reaper.GetEnvelopeName(TrackEnvelope env, string buf)` — the community shape, **confirmed by the live run**: names came back as strings ("Volume", "Mute", "Bypass / ReaEQ", "Transpose / Parallax X / Utilities", "Tempo map"). `lib/project.lua` still accepts a plain-string return as well, harmlessly |
| `CountEnvelopePoints` | `integer reaper.CountEnvelopePoints(TrackEnvelope envelope)` |
| `GetEnvelopePoint` | `boolean retval, number time, number value, integer shape, number tension, boolean selected = reaper.GetEnvelopePoint(TrackEnvelope envelope, integer ptidx)` — only `time` is used |
| `GetMasterTrack` | `MediaTrack reaper.GetMasterTrack(ReaProject proj)` — the master is not in `CountTracks`'s enumeration, so its automation has to be asked for separately |

What the live run confirmed, beyond the calls working:

- **The master track enumerates the project tempo map as an envelope named `"Tempo map"`** — the case flagged as unverified when this section was written. It is the *same points* as `GetTempoTimeSigMarker`, 1:1: the refusal reported 1 tempo marker and 1 "Tempo map" point in region "Sundown", 4 and 4 in "What I Deserve", 1 and 1 in each of "NES_15" and "NES_22". `lib/project.lua` therefore skips it, by name and only on the master, so a tempo point is not counted twice — noise in a refusal, but a **double move** once #4's transplant and #8's carry both write. If a version or locale renames it, the points read as an ordinary envelope again: noisier, still refused, never silently carried twice.
- **`CountTrackEnvelopes` includes FX parameter and bypass envelopes**, not just the built-in Volume/Pan/Mute — the run turned up "Bypass / ReaEQ" and "Transpose / Parallax X / Utilities". All are absolute, so all are stranded by a Repack and all belong in the refusal.

One scope decision, not an API claim:

- **Take envelopes are deliberately not read.** They are stored relative to their take, so they travel with the item the applier already moves. Only track envelopes are absolute, and only those get stranded by a Repack.

### 4.4a `SetTempoTimeSigMarker` — **sources unavailable in this pass; treat as unverified**

Needed by the tempo transplant's write half (issue #4, `lib/apply.lua`'s `apply.tempo_moves`). Unlike every other call in §4.4, this one was never fetched from `reascripthelp.html` or any mirror in any research pass recorded in this document — the write side of tempo markers was out of scope until issue #4. What follows is the long-standing, widely-used community shape, consistent with `GetTempoTimeSigMarker`'s own confirmed return order:

```
Lua: boolean reaper.SetTempoTimeSigMarker(ReaProject proj, integer ptidx, number timepos,
  integer measurepos, number beatpos, number bpm, integer timesig_num, integer timesig_denom,
  boolean lineartempo)
```

- `ptidx` is treated as a **position-sorted enumeration index, not a persistent ID** — the same shape as `GetTempoTimeSigMarker`'s `ptidx`, and unlike a region's or a plain marker's `markrgnindexnumber` (`SetProjectMarker4`, `DeleteProjectMarker`), which survive edits. Nothing in any source consulted confirms this, but no dedicated per-marker ID getter was found either, and treating `ptidx` as unstable is the conservative reading. `lib/apply.lua` is written not to depend on it staying valid across more than one edit: it re-locates each marker by its recorded position, immediately before writing it, rather than caching a `ptidx` from an earlier read.
- **Passing `-1` for `measurepos` and `beatpos` is reported, in community ReaScript code (e.g. tempo-marker-moving snippets from the X-Raym/cfillion ecosystem cited elsewhere in this document), to mean "derive this from `timepos`."** This is the convention `apply.tempo_moves` relies on, rather than computing a measure/beat position itself — recomputing it would mean reimplementing REAPER's bar math in Lua, which ADR-0006 already rejected for the planner for the same reason (unverifiable from this container, and the live project has ramps and partial-measure signature points). **This has not been independently confirmed in any research pass and should be checked against REAPER's in-app ReaScript documentation, or a real run, before being trusted further.**
- No `DeleteTempoTimeSigMarker` call is used by this suite. Homeless tempo markers are parked (moved), never deleted — see CONTEXT.md's Parked Material and the ADR-0006 amendment — so a delete function was not needed and its signature was not researched.
- ~~**This entire subsection should be re-verified directly in-app**~~ **Done — and it holds.** Fetched from the v7.78 `reascripthelp.html` and cross-checked against Cockos's own SDK header, both `curl`ed and read as text rather than through a summarizer (the method, and why it matters, is in §4.5). The signature above is confirmed **character-for-character**, and the description resolves three things this subsection had flagged as convention:

  > Set parameters of a tempo/time signature marker. Provide either timepos (with measurepos=-1, beatpos=-1), or measurepos and beatpos (with timepos=-1). If timesig_num and timesig_denom are zero, the previous time signature will be used. **ptidx=-1 will insert a new tempo/time signature marker.** See CountTempoTimeSigMarkers, GetTempoTimeSigMarker, AddTempoTimeSigMarker.

  So: `-1`/`-1` for `measurepos`/`beatpos` **is** primary-documented as "provide timepos instead", not merely community convention (it was already confirmed empirically by a successful run; now it is sourced too). `ptidx = -1` **inserts**, which is what `apply.anchors` relies on to write a Tempo Anchor where a project has no marker — and, by the same token, why it must locate and overwrite an existing marker rather than pass `-1` blindly, or every Repack would stack a duplicate at each region start. Note also that `timesig_num`/`timesig_denom` of **zero** means "keep the previous signature"; this suite always passes real values, so a `0` reaching that argument would be a bug that silently inherits rather than failing.

  Still not settled by any source: whether `ptidx` is **stable** across edits within one run. `lib/apply.lua` continues to assume it is not, and re-locates by position before every write.

**Confirmed by a real run, plus the one project setting that governs whether any of it works.** `SetTempoTimeSigMarker` ran for the first time against REAPER 7.78/win64 and moved all 69 of `repack_basic`'s tempo/time-signature markers correctly — but only after the project setting below was changed. The community shape above (including `-1`/`-1` for `measurepos`/`beatpos`) is therefore now **confirmed working**, not just plausible.

**`TEMPOENVLOCKMODE` — Project Settings -> "Timebase for tempo/time signature env" — decides whether tempo writes are independent of each other.** Values, read off a real project paired with its UI (so this is primary, and it contradicts what secondary web sources claim):

| `.RPP` value | UI | Behaviour |
|---|---|---|
| `1` | `Beats` | A marker holds its measure/beat; REAPER **derives** its time. Writing one marker re-derives the time of **every marker after it**. |
| `0` | `Time` | A marker holds its absolute time. Writes are independent. |

Measured, from the saved project of a failed run: with `TEMPOENVLOCKMODE 1`, the first `SetTempoTimeSigMarker` call (`642.394 -> 3096.443`) slid all 64 downstream markers by exactly `+1.121486470s`, and re-inserting it slid everything after the insertion point by a further `-3.129305s`. `apply.tempo_moves` then failed to re-locate its second marker and aborted the run. **No lookup tolerance can absorb this** — the drift is ~11,000x `BOUNDARY_TOLERANCE`. Matching on `measurepos`/`beatpos` instead would find the right marker but write it to a stale target time, which is worse: a scrambled tempo map instead of a clean crash.

**Two more tempo-map rules, established empirically by real runs, and neither is
in any documentation consulted.** Both are invisible until a *second* Repack, and
both destroy a marker silently when violated:

1. **A tempo map cannot hold two markers at one position: writing one onto an
   occupied position collapses the two into one.** Measured on
   `spec/fixtures/repack_bars`, reordering an already-packed project: the applier
   moved a marker `0 -> 8` while another was still at `8`, and 4 markers became
   3. The region that lost its marker inherited its neighbour's tempo and its
   internal bar count changed. **Nothing reports this** — every marker the plan
   named was found and written, so only the marker *count*, or a check that each
   destination still holds a marker, reveals it. `lib/apply.lua`'s
   `apply.tempo_moves` therefore orders its writes so a destination is never
   occupied when written, and verifies both afterwards.
2. **The timeline origin always carries a tempo marker, and it cannot be
   vacated.** Move the marker sitting at `0.0` and REAPER immediately puts a fresh
   one there carrying the project tempo (the `TEMPO` line). So a move *to* `0.0`
   can be blocked by a marker that will never move, and no ordering can free it.
   Measured: a first attempt at (1) treated this as a cycle and parked the
   incoming marker repeatedly — 13 times, ending at `13022s` — before giving up.
   `apply.tempo_moves` now overwrites the origin marker in that one case, which is
   correct rather than merely expedient: only one tempo can be in effect at an
   instant, the map must define one at `0.0`, and the plan says which region
   starts there. A permanent blocker anywhere *else* means the plan wants two
   markers at one position, which is unrealisable, and is refused by name.

**A Repack therefore requires the tempo envelope timebase set to `Time`.** Currently this is a manual precondition; whether it can be read or written from vanilla ReaScript is **unresolved** — the candidate route is `projectconfig_var_getoffs("tempoenvtimelock")` + `projectconfig_var_addr`, but that returns a pointer, and whether Lua (as opposed to EEL) can write through it was not established. The SWS route (`SNM_SetIntConfigVar*`) is an extension, so ADR-0001 keeps it out of `lib/`. **Open: verify in-app.**

### 4.4b `SetEnvelopePointEx`, `DeleteEnvelopePointEx`, `GetTrackEnvelopeByName` -- **`DeleteEnvelopePoint` confirmed NOT to exist; corrected against real REAPER**

Needed by the envelope-point carry's write half (issue #8, `lib/apply.lua`'s
`apply.envelope_moves`/`apply.envelope_drops`).

**The original guess in this subsection was wrong, and a real run proved it.**
A live run against REAPER 7.78/win64 raised `apply.lua:284: attempt to call a
nil value (field 'DeleteEnvelopePoint')` -- that bare function name does not
exist in this REAPER version. The correct call is the `Ex`-suffixed form,
`DeleteEnvelopePointEx`, which takes an extra `autoitem_idx` parameter
(automation items are a distinct object type from a plain envelope point,
§4.4's scope note -- this suite never reads or writes them, so `-1`, meaning
"the envelope itself, not an automation item," is hardcoded at every call
site). `lib/apply.lua` was corrected to use `SetEnvelopePointEx` and
`DeleteEnvelopePointEx` for both writes, on the assumption that the plain
`SetEnvelopePoint` might be equally absent -- **this has not itself been
independently confirmed** (the crash happened in `apply.envelope_drops`,
which runs before `apply.envelope_moves` in `apply.plan`'s order, so the
Set call was never reached in the run that caught this), but using the `Ex`
form for both is the conservative, consistent choice and the actual failure
mode (a bare non-`Ex` name existing for `Get` but not for `Set`/`Delete`)
would be a strange asymmetry to rely on:

```
Lua: boolean reaper.SetEnvelopePointEx(TrackEnvelope envelope, integer autoitem_idx,
  integer ptidx, number time, number value, integer shape, number tension,
  boolean selected, optional boolean noSortIn)
Lua: boolean reaper.DeleteEnvelopePointEx(TrackEnvelope envelope, integer autoitem_idx,
  integer ptidx)
Lua: TrackEnvelope reaper.GetTrackEnvelopeByName(MediaTrack track, string envname)
```

`GetTrackEnvelopeByName` has not itself produced any error in a real run yet
(the crash happened at the delete call, after the envelope lookup already
succeeded), so its signature stands unchanged here, still without a primary
source, but with a stronger empirical signal behind it than the other two
had before this correction.

- `ptidx` is treated the same way `SetTempoTimeSigMarker`'s is (§4.4a): a
  position-sorted enumeration index, not a persistent ID. Nothing in any
  source consulted confirms this, but no dedicated per-point ID getter was
  found either, and treating it as unstable is the conservative reading --
  the same one already adopted for tempo markers. `lib/apply.lua` is written
  not to depend on it staying valid across more than one edit: it re-locates
  each point by its recorded position, immediately before writing it, exactly
  like `apply.tempo_moves` already does.
- **`noSortIn`** is community convention for "skip re-sorting the point list
  after this write," used by scripts that batch many point edits before
  sorting once at the end for performance. `apply.envelope_moves` always
  passes `false`, so every write re-sorts immediately -- it moves at most a
  handful of points per envelope per run, so the performance case this flag
  exists for does not apply, and re-locating by position before every write
  (the point above) already tolerates re-sorting between writes.
- **`GetTrackEnvelopeByName`** is the read side's own handle for an envelope
  (`lib/project.lua`'s `envelope_name`, §4.4), used here as the write side's
  lookup too -- there is no persistent envelope identity carried through the
  plan, only `(track_index, envelope_name)`. Whether it matches REAPER's own
  display name exactly, or is case-sensitive, was not confirmed in this pass.
- No `InsertEnvelopePoint`/`InsertEnvelopePointEx` call is used by this
  suite: every write moves an existing point (`SetEnvelopePointEx`) or
  deletes one (`DeleteEnvelopePointEx`, for a point touching no region at all
  -- issue #8's Dropped Material case, the user's explicit choice over
  parking it like a homeless tempo marker, since deleting an envelope point
  carries none of issue #10's repositioning hazard).
- **`SetEnvelopePointEx` and `GetTrackEnvelopeByName` should still be
  re-verified directly in-app** (Help -> ReaScript documentation) before the
  next real-REAPER run of the envelope carry -- only the delete call has
  actually failed and been corrected so far; the others are corrected by
  analogy and caution, not by their own independent failure.

### 4.5 `TimeMap_*` — bar lines and effective tempo — **PRIMARY, verbatim from the v7.78 reference**

Needed by ADR-0006's real tempo oracle (issue #4): `next_bar_at_or_after(time)`
and `tempo_at(time)`, the two questions the planner cannot answer from plain
data. Unlike every other subsection here, these signatures were **not**
reconstructed from community convention — see the method note below, which is
the reason to trust them and the reason the earlier attempts had to be thrown
away.

**Method, and a hazard worth naming.** The signatures below come from two
primary sources, fetched as raw text and read directly rather than through a
summarizing fetch tool:

1. `https://www.reaper.fm/sdk/reascript/reascripthelp.html`, downloaded whole
   with `curl` and grepped locally. **The page self-reports `REAPER v7.78`,
   which is exactly the version this suite runs against**, so these are the
   bindings the user's REAPER actually exposes.
2. `https://raw.githubusercontent.com/justinfrankel/reaper-sdk/main/sdk/reaper_plugin_functions.h`
   — Cockos's own SDK header, for the C declarations and doc comments, likewise
   `curl`ed and grepped.

**The hazard: summarizing web-fetch tooling confabulates on this page.** Two
successive fetches of the *same* `reascripthelp.html` URL, asking for the same
function, returned two *different* and both *wrong* signatures for
`TimeMap2_timeToBeats` — one dropping every multi-value return, the other
inventing a `bool` return with `beatsOut`/`measuresOut` parameters that do not
exist. A third fetch invented a `tempo_humanizedOut` return for
`TimeMap_GetMeasureInfo`. The page is ~950 KB, past what the fetch summarizer
handles, and it fails by *fabricating plausible signatures* rather than by
saying it could not read them. `wiki.cockos.com` is behind a JS/CAPTCHA wall
and returns nothing usable at all. **`curl` works from this container** and is
the only route here that produced text matching the SDK header. Prefer it, and
treat any `reascripthelp.html` signature obtained through a summarizer as
unsourced regardless of how confident it looks — this is §4.4a's lesson
repeating in a new form.

| Function | Lua signature (verbatim, v7.78) |
|---|---|
| `TimeMap2_timeToBeats` | `number retval, optional integer measures, optional integer cml, optional number fullbeats, optional integer cdenom = reaper.TimeMap2_timeToBeats(ReaProject proj, number tpos)` |
| `TimeMap_GetMeasureInfo` | `number retval, number qn_start, number qn_end, integer timesig_num, integer timesig_denom, number tempo = reaper.TimeMap_GetMeasureInfo(ReaProject proj, integer measure)` |
| `TimeMap_GetTimeSigAtTime` | `integer timesig_num, integer timesig_denom, number tempo = reaper.TimeMap_GetTimeSigAtTime(ReaProject proj, number time)` |
| `TimeMap2_QNToTime` | `number reaper.TimeMap2_QNToTime(ReaProject proj, number qn)` |
| `TimeMap2_timeToQN` | `number reaper.TimeMap2_timeToQN(ReaProject proj, number tpos)` |
| `TimeMap2_GetNextChangeTime` | `number reaper.TimeMap2_GetNextChangeTime(ReaProject proj, number time)` |
| `TimeMap_QNToMeasures` | `integer retval, optional number qnMeasureStart, optional number qnMeasureEnd = reaper.TimeMap_QNToMeasures(ReaProject proj, number qn)` |
| `TimeMap2_GetDividedBpmAtTime` | `number reaper.TimeMap2_GetDividedBpmAtTime(ReaProject proj, number time)` |

Descriptions, verbatim from the same sources:

- `TimeMap2_timeToBeats` — "convert a time into beats. / if measures is
  non-NULL, measures will be set to the measure count, return value will be
  beats since measure. / if cml is non-NULL, will be set to current measure
  length in beats (i.e. time signature numerator) / if fullbeats is non-NULL,
  and measures is non-NULL, fullbeats will get the full beat count (same value
  returned if measures is NULL). / if cdenom is non-NULL, will be set to the
  current time signature denominator."
- `TimeMap_GetMeasureInfo` — "Get the QN position and time signature
  information for the start of a measure. **Return the time in seconds of the
  measure start.**"
- `TimeMap_GetTimeSigAtTime` — "get the effective time signature and tempo".
  Note it is `void` in C: there is **no `retval`**, so the Lua form returns
  exactly three values and the first is `timesig_num`. Reading it as
  `retval, num, denom` would silently shift every field.
- `TimeMap2_GetDividedBpmAtTime` — "get the effective BPM at the time
  (seconds) position (i.e. 2x in /8 signatures)". **Not used** by the oracle:
  the `/8` doubling is the metronome's effective click rate, not the bpm a
  tempo marker stores, so writing it into a Tempo Anchor would double the tempo
  of every `x/8` region. `TimeMap_GetTimeSigAtTime`'s `tempo` is the undivided
  one, and it comes with the time signature the same anchor needs.

**How the oracle is built from these.** Both answers come from REAPER, with no
bar arithmetic in Lua (ADR-0006):

- `tempo_at(time)` is one call: `TimeMap_GetTimeSigAtTime`, returning the
  *effective* tempo, which is what ADR-0006 requires — mid-ramp the tempo in
  effect is not any marker's bpm.
- `next_bar_at_or_after(time)` is `TimeMap2_timeToBeats` for the measure index
  containing `time`, then `TimeMap_GetMeasureInfo` for that measure's start
  time in seconds, stepping to `measure + 1` when `time` is past the start.
  `TimeMap_GetMeasureInfo`'s `retval` *is* the seconds position, so no
  QN round-trip through `TimeMap2_QNToTime` is needed.

**The measure-index base — settled empirically, 2026-08-05 (issue #14).**
Neither the reference nor the SDK header states whether
`TimeMap2_timeToBeats`'s `measures` and `TimeMap_GetMeasureInfo`'s `measure`
are 0-based or 1-based, nor whether they share a base. `LCRR_Arrange_ShowBarLines`,
run on `repack_bars` in REAPER 7.78/win64, answers it:

```
TimeMap2_timeToBeats(0, 0.0) reports measure index 0 -- so REAPER numbers measures from this
```

**REAPER numbers measures from 0.** The same run reported every one of the
four regions as already on a bar line and `0 of 4 region(s) would be padded`,
against a timeline the oracle itself had just aligned — so the two calls do
share the base, since a mismatch would have put the bar lines a whole measure
off and produced four spurious pads.

The stakes were real: an off-by-one here is **silent** and costs a whole bar
of Padding — at the live project's tempos, 1.4 to 2.4 seconds of unwanted
silence inside a region, and a run that aborts on any back-to-back region
pair. `lib/tempo_oracle.lua` therefore does not trust the base at all: it asks
`TimeMap_GetMeasureInfo` for the candidate measure and **verifies the bracket**
(`measure_start <= time < next_measure_start`), stepping until it holds.

That loop stays, and is now belt-and-braces against a *known* base rather than
a guard against an unknown one. It is worth keeping for two reasons that
survive the measurement: it still absorbs rounding at a measure boundary, and
the base is observed on one REAPER version rather than documented by Cockos,
so a future version could move it without announcement.

## 5. Actions List, Custom Actions, and Automation Glue

- **Action List**: native REAPER feature (File/Actions menu → "Show action list"), lists every built-in action and every loaded ReaScript, each with a numeric/string command ID usable with `Main_OnCommand`. Source: general secondary summary from [Audeobox — Reaper Custom Actions guide](https://www.audeobox.com/learn/reaper/custom-actions-guide/) and [Sound on Sound — Automate Anything With Reaper's Custom Actions](https://www.soundonsound.com/techniques/automate-anything-reapers-custom-actions) (both secondary/community magazine-style writeups, not primary Cockos docs — no official reaper.fm page was successfully fetched specifically for Action List/custom action mechanics in this pass).
- **Custom Actions**: native REAPER feature — combine multiple existing actions/scripts (including ReaScripts) into one macro-like composite action from within the Action List's "New" button. This is a plausible mechanism for chaining several of the eventual automation scripts into one user-facing action, but its exact scripting-relevant behavior (e.g., can a custom action itself be invoked via `Main_OnCommand` from another script — very likely yes, since it gets its own command ID, but not independently confirmed here) should be verified directly.
- **ReaConsole**: confirmed to be an **SWS extension** feature (§2.2), not native — a text-command interface primarily for track selection/organization, not rendering or region editing.

## 6. What's Explicitly NOT Scriptable / Known Gaps in This Research

1. **Full canonical list of `GetSetProjectInfo`/`GetSetProjectInfo_String` desc keys** — not retrieved from the primary source in this pass due to page-fetch truncation; only a partial, community-corroborated subset (§3.1) is documented here.
2. **`GetProjectStateChunk`/`SetProjectStateChunk` exact signatures and parameter semantics** — existence confirmed primary, full description not retrieved; treat current understanding (§2.3) as provisional.
3. **`GoToRegion` and `SetProjectMarker4` full official descriptions** — not retrieved; only partial/indirect (search-cached) information available.
4. **Render output directory (`RENDER_FILE`)** — a secondary source claims this is not settable via the clean numeric/string project-info API as of REAPER 6.43+, implying chunk-editing or GUI interaction may be required. Not confirmed primary.
5. **Region Render Matrix per-cell assignment** — no dedicated ReaScript setter function found; likely requires state-chunk manipulation. Not confirmed primary.
6. **Applying a Project Template or Track Template programmatically** — no dedicated "load template" ReaScript function was found; likely requires either driving the native menu action via `Main_OnCommand` or treating the template file as a chunk to inject. Not confirmed primary.
7. **Startup actions / global "on project open" automation** — appears to be an SWS-extension-only capability (`SWS/S&M: Clear global startup action` etc.), not native REAPER; whether a *native* per-project startup-action equivalent exists was not confirmed either way in this pass.
8. **SWS extension dependency boundary** — several commonly-cited "REAPER scripting" capabilities in community tutorials (`SNM_*` config-var functions, ReaConsole, and likely more) are actually **SWS/S&M extension** functions requiring a separate install, not native REAPER/ReaScript. Any implementation plan should explicitly decide whether to take a dependency on SWS or stay native-API-only, since this materially changes what's available (SWS meaningfully expands scriptable surface area for exactly this project's kind of use case — project defaults, startup automation).

---

## References

Primary (official Cockos / reaper.fm):
- [ReaScript overview](https://www.reaper.fm/sdk/reascript/reascript.php)
- [REAPER Extensions/Plugin SDK overview](https://www.reaper.fm/sdk/plugin/plugin.php)
- [ReaScript API function reference (reascripthelp.html)](https://www.reaper.fm/sdk/reascript/reascripthelp.html) — large single-page reference; several sections could not be fully retrieved with the fetch tooling available in this session (see notes throughout).
- [REAPER SDK index](https://www.reaper.fm/sdk/)
- [`reaper_plugin_functions.h`, Cockos's own SDK header](https://raw.githubusercontent.com/justinfrankel/reaper-sdk/main/sdk/reaper_plugin_functions.h) — C declarations plus doc comments for every API call, as plain text. **`curl` this and grep it locally**; it is the most reliable primary route found from this container (§4.5).
- [REAPER User Guide download index](https://www.reaper.fm/userguide.php)
- [REAPER User Guide v5.30 PDF](https://dlcf.reaper.fm/userguide/ReaperUserGuide530c.pdf) — located via search; not opened/read in this pass, cited only for the existence and chapter structure ("Loops, Markers and Regions," from page 163) surfaced by the search snippet. Should be read directly for anything claimed as coming from the User Guide.

Secondary — first-party-adjacent (Cockos-run forum, or long-standing REAPER-community sites closely tracking official changelogs):
- [forum.cockos.com — Scripts: Render Region Matrix](https://forum.cockos.com/showthread.php?p=1917334)
- [forums.cockos.com — Render project using most recent render settings](https://forums.cockos.com/showthread.php?p=2767067)
- [REAPER Blog — What's New in REAPER 6.59 (region render matrix via master)](https://reaper.blog/2022/06/659-update/)

Secondary — community (third-party docs, mirrors, and open-source script/extension repos, useful but not canonical):
- [ReaTeam/Doc — REAPER-CLI.md](https://raw.githubusercontent.com/ReaTeam/Doc/master/REAPER-CLI.md) (command-line flags)
- [ReaTeam/Doc — State Chunk Definitions](https://github.com/ReaTeam/Doc/blob/master/State%20Chunk%20Definitions) (RPP chunk format, MARKER line format)
- [cfillion/reascripts — Apply render preset.lua](https://github.com/cfillion/reascripts/blob/master/cfillion_Apply%20render%20preset.lua) (real GetSetProjectInfo/_String render keys)
- [extremraym.com — ReaScript API Documentation mirror](https://www.extremraym.com/cloud/reascript-doc/)
- [extremraym.com — Region Render Matrix Pack](https://www.extremraym.com/en/download/reascripts-render-region-matrix/)
- [mespotin.uber.space — Ultraschall REAPER API doc mirror](https://mespotin.uber.space/Ultraschall/Reaper_Api_Documentation.html)
- [reaper-oss/sws (GitHub) — SnM_Project.cpp](https://github.com/reaper-oss/sws/blob/master/SnM/SnM_Project.cpp), [sws issue #987](https://github.com/reaper-oss/sws/issues/987), [sws-web reaconsole.php](https://github.com/reaper-oss/sws-web/blob/master/reaconsole.php) (SWS extension internals — confirms SNM_*/ReaConsole are SWS-only, not native)
- [Sound on Sound — Reaper: Total Recall With Track Templates](https://www.soundonsound.com/techniques/reaper-total-recall-track-templates)
- [Sound on Sound — Automate Anything With Reaper's Custom Actions](https://www.soundonsound.com/techniques/automate-anything-reapers-custom-actions)
- [REAPER Accessibility Wiki — Project Templates](https://reaperaccessibility.com/wiki/Project_Templates), [Track Templates](https://www.reaperaccessibility.com/wiki/Special:MyLanguage/Track_Templates)
- [Audeobox — Reaper Custom Actions guide](https://www.audeobox.com/learn/reaper/custom-actions-guide/)

## Open Items Requiring Direct Verification Before Implementation

- Fetch the complete, current `reascripthelp.html` (or use REAPER's in-app Help → ReaScript documentation, which is the same content but not subject to the web-fetch truncation problems hit in this session) to confirm: full `GetSetProjectInfo`/`GetSetProjectInfo_String` desc key list, `GetProjectStateChunk`/`SetProjectStateChunk` full signatures, `GoToRegion` and `SetProjectMarker4` full descriptions, and `GetNumRegionsOrMarkers`/`GetRegionOrMarker` (the functions the docs say should be used instead of the discouraged `CountProjectMarkers`).
- Confirm current-version behavior of `RENDER_FILE` (output directory) settability via API — the "not accessible via API" claim is secondary-sourced and version-specific (v6.43+ at time of that script's writing).
- Confirm command-line flags against `reaper -h`/`reaper.exe -h` output directly, since no official Cockos web page enumerating them was found.
- Confirm whether a native (non-SWS) mechanism exists for "run action on project open."
- Confirm empirically whether template application has a dedicated ReaScript function or requires driving native menu actions / chunk injection.
- ~~Confirm whether `TimeMap2_timeToBeats`'s `measures` and
  `TimeMap_GetMeasureInfo`'s `measure` are 0- or 1-based, and whether they
  share a base (§4.5)~~ — **settled empirically** (§4.5, issue #14).
  `LCRR_Arrange_ShowBarLines` on `repack_bars`, REAPER 7.78/win64: measures are
  numbered **from 0**, and the two calls share the base. Still not stated by
  either primary source, so it is an observation on one version, not a
  documented guarantee — the oracle's bracket search stays.
- ~~Confirm `SetTempoTimeSigMarker`'s actual signature … and whether `-1` for `measurepos`/`beatpos` really means "derive from `timepos`"~~ — **settled, primary** (§4.4a). The signature matches character-for-character and the `-1` convention is documented. **What remains open is only whether `ptidx` is stable across edits within one run**; no source addresses it, so `lib/apply.lua` keeps re-locating by position before every write.
