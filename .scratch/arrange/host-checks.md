# Arrange: pending host checks and decisions (after issues 04-10)

Written 2026-11-07. Run `scripts/install.ps1` and restart the bridge first. Tick items as you go; record failures as new issues from `11`.

## Host checks

### Edit tab (issue 07)
- [ OK ] Desktop browser: drag by the handle (mouse), ↑/↓ per row.
- [ OK ] Headroom typed and ±1 s; shown as "+4 s at next Apply".
- [ OK ] Add from "Left out" and Remove.
- [ OK ] New, Duplicate, Rename; Delete prompt names the Arrangement and its region count.
- [ OK ] Tablet: touch drag (pointer events, `touch-action:none`, untested), button size, layout at tablet width.
- [ Check ] Desktop width: layout reads well (Check findings are long).
- [ OK ] Rewrite question on the first edit of a hand-commented sidecar; none on the next edit.
- [ ] Stale file: edit the sidecar in a text editor and save, then edit in the page → refusal + reload. Refocusing the window also re-reads.
- [ ] A region name not in the project: flagged, Remove only.
- [ ] Missing sidecar: Edit tab offers New; unreadable sidecar: parse error shown, no controls.
- [ ] Last tab remembered after a reload.
- [ ] "Check this Arrangement" switches to Run and starts Check.

### Check token and empty Arrangement (issue 06)
- [ ] Check, edit that Arrangement in a text editor, Apply → refused ("edited since this Check").
- [ ] Check, edit a *different* Arrangement, Apply → proceeds.
- [ ] Check on an empty Arrangement (`["Empty"] = {}`) → refused; Edit tab shows the inline hint.

### Undo (issue 08)
- [ ] Undo each kind of edit; the list and `.arrangements.lua` return to what they were.
- [ ] Remove a row that has Headroom, Undo → position and Headroom both return.
- [ ] Edit the sidecar in a text editor between an edit and Undo → Undo cleared, "changed elsewhere" note.
- [ ] Undo disabled when the stack is empty or the bridge is busy; tooltip reads well.

### Clear applied Headroom (issue 09), on `podium-dummy`
- [ ] Arrangement `This` (+300 s on Outro): Check → Apply → "Apply the Headroom" → result shows "Clear the Headroom just applied".
- [ ] Click it → sidecar shows `headroom = 0`; a second Check asks no Headroom question.
- [ ] Undo on the Edit tab brings the Headroom back.
- [ ] Answer "Repack only" → no offer. An Arrangement with no Headroom → no offer.
- [ ] On a hand-edited sidecar, the rewrite question appears inside the result card.

### Bridge commands (issue 05)
- [ ] An edit refused with `sidecar_changed` after editing the sidecar in a text editor (covered by the Edit tab check above if it passes).

### Still open from before phase 2
- [ ] Show Bar Lines and Show Track Timebase (page and Action list).
- [ ] `install.ps1` twice, then `-Uninstall`: `__startup.lua` has one line, then none.
- [ ] The "Applying…" display.
- [ ] Apply refusing after its Tempo Anchors (the "one undo step" message).
- [ ] Remove the old `Scripts\TSB\` actions on the host.

## Decisions for you

- [ ] Undo of New/Duplicate deletes the Arrangement, which writes a Delete entry in the run log. Keep, or skip the log entry?
- [ ] Partial Undo (removed row restored, its Headroom refused): warning only. Enough, or add a repair path?
- [ ] After "Clear the Headroom just applied": stay on Run with a note (current), or switch to Edit?
- [ ] The project path costs ~200 of the ~900 URL characters on every edit; the page refuses before sending if over. Switch to a short path hash now, or wait until it bites?
- [ ] Drag only works inside "In this Arrangement"; Add appends at the end; no autoscroll while dragging. Wanted?

## Follow-ups worth issues

- Capture summary on Run still says to edit the sidecar in a text editor.
- `docs/workflow.md` doesn't describe the editor.
- No browser smoke test for the page (e.g. jsdom).
- A click on "Clear the Headroom just applied" during the re-read right after Apply is dropped as busy.
- Points the plan doesn't move (delta 0) are not lifted before tempo moves; nothing plans this today (`docs/decisions.md`).
- A full code review of `2f12a33..HEAD` (agents only self-reviewed).
