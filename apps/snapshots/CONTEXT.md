# Snapshots

The engineer's page for saving the project's mix under a name and restoring it in one press (`lcrr-snapshots.html`). Decisions: `.scratch/snapshots/spec.md` and `docs/adr/0001`. REAPER facts (measured in the issue 01 spike) are in the suite `CONTEXT.md`. The owner's live-test checklist is `.scratch/snapshots/live-test.md` (git-ignored); nothing in it has been run yet.

## Terms

- **Snapshot**: a project snapshot, this app's. It holds every track's and the Master's volume, full pan state, mute, solo, polarity and FX chain on/off, and every send's and hardware output's volume, pan, mute and mode. IEM Mix's are **mix snapshots** (`apps/iemmix/CONTEXT.md`): in-ear sends only. The two are stored (project ExtState sections `LCRR_SNAPSHOTS` and `LCRR_IEMMIX`) and restored separately; neither knows the other.
- **Tick**: a kind of value a restore writes (Levels, Pans, Mutes, Solos, Polarity, Sends, FX on/off, In-ears). Saving always stores everything; the ticks act only at restore. They reset at each page load.
- **In-ear tracks**: `IEM_<name>` (exact, case-sensitive, something after the prefix), `IEM-Cue`, and the first track named `IEMs`, recognised by their **current** names at restore. **In-ear values**: those tracks' own values, every send into them, and their hardware outputs. With In-ears off none is written; with it on all are, whatever the other ticks say.
- **Marks**: `Solo` (any non-zero `I_SOLO`, the Master's included) and `Master muted`, decided at save and kept in the list.

## Commands

The bridge is `LCRR_Snapshots_Bridge.lua`, ExtState section `LCRR_SNAPSHOTS`. Each reply is `{ v, command, project: { name, path }, status, ... }` (`project` is the active project's `.rpp` file name without extension, empty when unsaved). Refusals are `{ status: "refused", error: { code } }`. Every command can also be refused with `bad_request`, `request_truncated`, `unknown_command` or `internal`. Wording is `words.js`; the recorded replies are `test/fixtures/bridge-replies.txt`.

- `state` -> `{}` (just `project`).
- `snapshots` -> `{ snapshots: [ { name, saved (epoch seconds), tracks, sends, solo, master_muted } ] }` in save order. Reads only the index. `tracks` does not count the Master; `sends` counts sends and hardware outputs, the Master's included. Code `unreadable` (the stored index is not one this version wrote; it is never guessed at).
- `snapshot_save` (`name`, optional `overwrite` `1`) -> `{ name, overwritten, tracks, sends }`. The request carries only the name; the bridge reads the values. The name is trimmed, at most 40 characters, no control characters, unique and case-sensitive. An overwrite keeps the snapshot's id and place in the list and refreshes `saved`, counts and marks. Codes `empty_name`, `bad_name`, `name_too_long`, `duplicate_name` (taken, no `overwrite`), `not_found` (`overwrite` on a name not saved), `unreadable`. A project with no tracks still saves (it holds the Master).
- `snapshot_delete` (`name`) -> `{}`. Codes `empty_name`, `bad_name`, `name_too_long`, `not_found`, `unreadable`.
- `snapshot_restore` (`name`, `ticks`) -> `{ name, tracks, sends, skipped, automated, muted_skipped }`. `ticks` is one letter per tick that is on, in any order: `L` levels, `P` pans, `M` mutes, `S` solos, `R` polarity, `E` sends, `F` FX on/off, `I` in-ears. Codes `empty_name`, `bad_name`, `name_too_long`, `not_found`, `unreadable`, `no_ticks` (empty), `bad_ticks` (a letter that is no tick). All refusals come before any write.
  - Tracks match by GUID (the Master by the key `master`), a send by its destination's GUID and its order among the sends of that pair, a hardware output by its order on the track. Values only: nothing is created or removed. A stored item with no counterpart now is `skipped`; tracks and sends added since the save are left alone.
  - `tracks` counts tracks (Master included) that had a value written; `sends` counts sends and outputs written. Levels and pans are written as `D_VOL` and `D_PAN`, pans as `I_PANMODE`, `D_PAN`, `D_WIDTH`, `D_DUALPANL` and `D_DUALPANR`.
  - A stored solo of 5 is written as 1 and 6 as 2 (writing either reads back 0). REAPER's solo-defeat setting is not part of a snapshot.
  - **One undo step** (`Snapshots: restore <name>`), the only snapshot command that touches the project. Nothing written means no undo step.
  - `automated` counts the written track and send volume, pan and mute values with active automation (envelope exists, has points, `ACTIVE` is "1"); they will follow the envelope. `muted_skipped` counts mutes left alone because the value would reach a Mute envelope: a track's (Master included) mute is skipped when it has a Mute envelope and its own mode or the global override is Touch, Write or Latch; a send's the same with its own `I_AUTOMODE` (-1 follows the track) and "has points" for "has an envelope". Hardware outputs are neither guarded nor counted. Neither count is part of `skipped`, which is only what is gone. `docs/adr/0001`, `lib/core/automation.lua`.
  - With In-ears off, in-ear values of tracks that still exist are neither written nor counted. A track that is gone counts once if any tick that writes a track value is on (Levels, Pans, Mutes, Solos, Polarity, FX on/off or In-ears), and its sends and outputs count only if Sends or In-ears is on. A snapshot does not record which tracks were in-ear, so a deleted in-ear track follows this rule like any other.
- Storage (`lib/core/snapshot_store.lua`): project ExtState, an index key `snapshots` and one key `snapshot.<id>` per snapshot, each a single line, so the list stays small however large a snapshot is. Contents are written before the index lists them. It is in the `.rpp`, so a snapshot travels with the project and is kept once the project is saved. Save, Overwrite and Delete ignore undo (nothing can undo them) and call `MarkProjectDirty(0)` afterwards, so REAPER prompts to save. Only an index entry the store cannot read is `unreadable`; a snapshot's contents that cannot be read refuse the restore the same way.

## Page behaviour

One flat screen (`lcrr-snapshots.html`), no lock (`apps/iem` ADR-0001 shape). No bridge heartbeat means a banner and `#snapshots-controls` stays hidden.

- Bar: the title, the active project's name (or "(unsaved project)") and the connection chip. The project name and the list are re-read every 3 s while the tab is visible, so a project change shows. An identical list reply leaves the rows untouched.
- A "Restore" box of eight ticks, defaults: Levels, Pans, Mutes, Solos, Polarity and Sends on; FX on/off and In-ears off. A standing note under it: with In-ears off the in-ear tracks and the sends into them are left alone, but restoring a source track's mute, polarity or FX can still change what the musicians hear (a track's mute silences its `I_SENDMODE` 3 sends; accepted in the spec). With no tick on the Restore keys are disabled.
- A Name field and a Save key (a tap, since a new name destroys nothing). The name is checked on the page first (`core.checkName`, including that the request fits the URL limit) and again by the bridge; a refusal stays on screen until the next attempt, and the field is emptied only after a save succeeds.
- The list, in save order: name, "N tracks, N sends" with the saved date and time, the marks as words (`Solo`, `Master muted`), and the keys Overwrite, Delete and Restore. All three are press-and-hold (1 s, `LCRR.shared.hold`): a tap does nothing. The list is not rebuilt while a hold is down. One request is in flight at a time.
- A note under the Save field gives the last restore's result: how many tracks and sends were written, how many saved items were skipped because they are gone, how many restored values have active automation and will follow it, how many mutes were left alone because of the automation mode. A restore that wrote nothing says so. The note is replaced by the next restore. (The spec says it stays until the next write; only a restore replaces it in the code, so a Save, Overwrite or Delete does not clear it.)
- The layout is one column of rows with flex wrapping, no media queries.

## Not measured, or decided and not tried on real REAPER

All of this is for the live test (`.scratch/snapshots/live-test.md`). The unit specs run against a fake REAPER and cannot settle any of it.

## Still unseen

- What restoring `D_VOL` under a volume envelope does to the audio in Read and Trim (the spike measured only that the envelope gets no points and `D_VOL` reads the stored value).
- Whether `I_FXEN` clicks when many chains wake at once, with the owner's real plugins (the spike: 48 stock plugins in 3 ms, no underruns, click not settled by ear; third-party plugins untried).
- Whether `B_MUTE` on a send reaches the send's Mute envelope, and `D_WIDTH` a width envelope (the spike did not test send mute, send pan, width or FX bypass envelopes). The send rule in ADR-0001 is a precaution and can be dropped if send mutes prove safe. Hardware-output envelopes were not looked at.
- Whether a real safe-soloed track reads `I_SOLO` 5 or 6, and how the 5-to-1 and 6-to-2 mapping behaves (the spike's track had no solo defeat and only showed that writing 5 or 6 reads back 0).
- Whether `MarkProjectDirty(0)` makes REAPER prompt to save at close and adds no undo entry, and whether the save survives Save and reopen. How a stored value of project-ExtState size (a 12-mix by 120-source snapshot is about 100 KB in a spec) round-trips through `SetProjExtState` and the `.rpp` is also unmeasured.
- Restore on an automated track playing and stopped in every mode, through the page: the guard's wording and counts against what REAPER does.
- Restore with `IEM_` mixes in use (the In-ears tick on and off), with a track reordered, renamed and deleted since the save, and with a solo or a muted Master in the snapshot.
- One undo step through the page, including that Undo brings back every tick's values.
- A track renamed to `IEM_x` since the save counts as an in-ear track at restore (decided, not tried; a spec open point).
- `IsProjectDirty` is documented as always 0 when REAPER's dirty-flag preference is off; the spike did not check it.
- Behaviour with several project tabs open (the restore acts on REAPER's active project; unverified across the suite).
- The page's layout on a phone and a tablet, and its press-and-hold keys by touch, in a real browser.
- `install.ps1`'s startup line and the ReaPack hook for `LCRR_Snapshots_Bridge.lua` on Windows (`test/startup-ids.test.js` reads them as text only).
