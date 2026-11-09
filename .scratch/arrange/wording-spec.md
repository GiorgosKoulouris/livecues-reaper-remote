# Arrange: shorter, plainer messages

Decided in a grilling session on 2026-11-08. Issues 13 to 16 implement it. Status of the wording below: proposed, for review before any code changes.

## Principle

A user reads a message for one of three reasons: to learn the result, to make a decision, or to fix a problem. Anything else goes to the run log.

## Decisions

| Topic | Decision |
|---|---|
| Scope | Shorten message boxes, the console and the page. The run log keeps every detail. |
| Console | Check, Apply, Capture and Verify never open it. Show Bar Lines and Show Track Timebase still use it, because their whole output is a list. |
| Check | Verdict, each refusal with its fix, and one line per lasting effect. Drop the "cannot see" list, the Padding accuracy note, move counts and severity headings. |
| Apply done | One "done" line, the same lasting-effect lines as Check, Undo, next step. |
| Refusals | Problem, then fix. Add the project's state after a refused Apply or edit. Omit it for Check and Verify, which only read. Every refusal has a fix. |
| Unexpected failures | Plain instruction with Undo. The raw error goes to the run log only. |
| Hints | Only next steps stay. |
| Headroom confirmation | Stays (ADR-0007), shortened. |
| Verify | Result, one plain line per problem, the fix. |
| Long lists | Message boxes show 8 names, then "and N more". The page shows everything. |
| Language | Plain words. On screen, keep only Arrangement, region and Headroom. No code labels, no capitals for emphasis, times to one decimal. Docs and code keep the glossary. |
| Reinstall | Say "the LCRR installer". No script names. |

Lasting effects shown on Check and after Apply: left-out regions moved, silence added, Headroom changes, a Headroom too small to act, material discarded, items cut at region edges, and items on an unsafe timebase. Tempo Anchors, automation anchors and move counts are log-only.

Wording rules:

- "sidecar" becomes "Arrangement file".
- "Would refuse" becomes "can't be applied".
- Script-side messages say "on the Arrange page's Edit tab" where the page says "on the Edit tab".
- The word "about" goes before the silence total when the reply says Padding is not exact. It replaces the accuracy note this cleanup removes.

## Check

| Case | Text |
|---|---|
| Ready | `Ready to apply "X".` |
| Ready, with effects | `Ready to apply "X".` then `This will also:` and the lines below |
| Refused | `"X" can't be applied yet.` then each refusal |
| Refused before planning (`not_planned`) | `Fix these and run Check again to see what else it would do.` |
| Already matches | `"X" already matches the timeline. Nothing to apply.` |
| Beside the Apply button | `Undo in REAPER takes it back.` |

| Effect | Line |
|---|---|
| `parked` | `Move 2 left-out regions after the end of the Arrangement: A, B` |
| `padded` | `Add silence to 3 regions so they end on a bar line (about 6.2 s in total)` |
| `headroom` | `Change the end of 2 regions with Headroom: Bravo -4.0 s, Delta +2.0 s` |
| `headroom`, resolved 0 | `Headroom on Bravo is too small to change anything (under half a bar).` |
| `dropped` | `Discard 1 item and 2 automation points that are in no region` |
| `cut` | `Cut 2 items at region edges` |
| `unsafe_timebase` | `Apply will stop if any of these are inside a moved region: track 3 at 12.0 s. Set those tracks' timebase to Time to avoid this.` |

## Apply

```
Applied "X".

- Added silence to 3 regions (6.2 s)
- Discarded 1 item that is in no region

Undo in REAPER takes it back.
Next: run Verify.
```

Effects use the past tense. No effects means no list. `Arrangement "X" already matches the timeline. Nothing to do.` stays. The offer to clear Headroom stays.

Headroom confirmation:

```
Apply Headroom to 2 regions?

  Bravo: -4.0 s
  Delta: +2.0 s

Each Apply moves these region ends again.

Yes - apply with Headroom
No - apply without Headroom
Cancel - do nothing
```

When capped, this prompt says `and N more (see the Edit tab)`, because no run log entry exists yet at this point.

## Verify

| Case | Text |
|---|---|
| Pass | `The timeline matches "X".` |
| Fail | `The timeline doesn't match "X".` then the lines, then the fix |
| Fix | `Apply "X" again to fix this.` |
| Fix, if a region is missing | `Restore the missing regions in REAPER, or remove them from "X" on the Edit tab, then Apply again.` |
| `region_absent` | `"Bravo" is in the Arrangement but not in the project` |
| `order_mismatch` | `"Bridge" is before "Verse 2"` |
| `gap` | `There is a gap after "Chorus"` |
| `overlap` | `"Bridge" overlaps "Chorus"` |
| `block_start` | `The first region doesn't start at the beginning of the timeline` |
| `off_bar_line` | `"Outro" isn't on a bar line` |
| `not_parked` | `"Bonus" isn't in the Arrangement but is still among its regions` |

## Refusals

| Code | Text |
|---|---|
| `project_unsaved`, `sidecar_unsaved` | `This project hasn't been saved. Save it in REAPER, then try again.` |
| `tempo_env_beats` | `The project's tempo timebase is set to Beats. In Project Settings, set "Timebase for tempo/time signature env" to Time, save the project, and try again.` |
| `no_regions` | `This project has no regions. Add some in REAPER, then try again.` |
| `no_tracks` | `This project has no tracks.` |
| `region_names` | `Every region needs its own name:` list, `Rename these in REAPER, then try again.` |
| `sidecar_invalid` | `The Arrangement file can't be read: <reason>. Fix it in a text editor, then try again.` |
| `sidecar_missing` | `This project has no Arrangements yet. Capture one, or run "LCRR Arrange: Apply Arrangement" in REAPER to import a file.` |
| `no_arrangements` | `This project has no Arrangements yet. Capture one first.` |
| `arrangement_unknown` | `"X" isn't an Arrangement in this project. Choose one of: A, B.` |
| `arrangement_empty` | `"X" has no regions. Add some on the Edit tab.` |
| `arrangement_missing_regions` | `"X" uses regions this project doesn't have:` list, `Restore them in REAPER, or remove them from "X" on the Edit tab.` |
| Headroom shrinks too far | `"Bravo" can't shrink by 20.0 s. The most it can lose without cutting into its content is 8.0 s. Lower its Headroom on the Edit tab, then try again.` |
| Headroom too large | `The Headroom on "Bravo" is too large. Check the value on the Edit tab.` |
| `anchors_moved_items` | `Apply stopped because these items moved with the tempo:` list as `track 1 at 11.0 s`, `Press Ctrl+Z in REAPER, set those tracks' timebase to Time, then try again.` |
| `anchors_written` suffix | `Press Ctrl+Z in REAPER to remove the changes made so far.` Replaces "Nothing was changed." |
| `token_unknown` | `This Check has expired. Run Check again, then Apply.` |
| `token_stale`, project changed | `The project changed since this Check. Run Check again, then Apply. Nothing was changed.` |
| `token_stale`, other project | `A different project is open in REAPER. Open the right one and run Check again. Nothing was changed.` |
| `token_stale`, edited | `"X" was edited since this Check. Run Check again, then Apply. Nothing was changed.` |
| `other_project` | `A different project is open in REAPER. Press Refresh, then redo the edit. Nothing was changed.` |
| `sidecar_changed` | `The Arrangement file changed elsewhere and has been reloaded. Redo the edit. Nothing was changed.` |
| `would_be_invalid` | `That edit can't be saved. Reload the page and try again. Nothing was changed.` |
| `save_failed` | `The Arrangement file couldn't be saved: <reason>. Check that the project folder can be written to, then try again.` |
| `import_unreadable`, `import_invalid` | `That file can't be imported: <reason>. Choose a different Arrangement file.` |
| `bad_request`, `unknown_command`, `operation_unknown`, `missing_field` | `Arrange needs updating. Run the LCRR installer again, then restart REAPER.` |
| `request_truncated`, `request_too_long` | `That name is too long. Use a shorter one.` |
| `internal`, or any error raised mid-Apply | `Apply stopped partway. Press Ctrl+Z in REAPER to undo what it did, then try again. If it happens again, send the run log beside the project.` |
| `no_reply` | `REAPER didn't answer in time. Apply may still be running. Look at the project in REAPER before trying again.` |
| Connection failure | `Can't reach REAPER. Check the connection and try again.` |

"Nothing was changed." is for Apply and for edits that conflict with the file or project. Simple field checks such as `name_empty`, `name_taken`, `region_empty`, `region_repeated`, `slot_invalid` and `headroom_invalid` keep their current short text.

Still to be worded in issue 13, because the engine's text needs reading case by case: the remaining `plan_refused` cases (Padding that runs into a neighbour, an unsafe timebase inside a moved region) and `plan_out_of_scope`.

## Page and Capture

| Where | Change |
|---|---|
| Check/Verify hint | Delete |
| Edit tab Headroom hint | Delete |
| REAPER-only note at the page bottom | Delete. `sidecar_missing` and `sidecar_unsaved` carry those steps. |
| Status chip | `Connected`, `Arrange not running`, `REAPER unreachable`, `Connecting…` |
| Banner, not running | `Arrange isn't running in REAPER. Open the Actions list and run "LCRR Arrange: Bridge".` |
| Banner, offline | `Can't reach REAPER. This page keeps retrying.` |
| Capture done | `Captured "X" with 12 regions. Next: duplicate it on the Edit tab, reorder the copy, then Check.` |
| Delete question | `Delete "X" and its 12 regions? This can't be undone from the page.` |

The Show Bar Lines and Show Track Timebase consoles keep their tables and lose internals: API names, threshold values, Lua version and `regions read via`. Their dialogs stop saying "Nothing has been changed".

## Out of scope

- The run log's content.
- Merging the two copies of the wording (issue 12, section 1).
- Behaviour: what refuses, and when.
