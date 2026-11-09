# Arrange: host checks for issues 06, 07 and 09

Written 2026-11-08, after the review of `2f12a33..HEAD`. Issues 06, 07 and 09 are marked `Status: done`, but their host checks were never recorded as passed. This file says exactly how to run each one. It covers only what is still open in `host-checks.md` for these three issues; the rest of that file is untouched.

When a check passes or fails, tick it here, then record the result under `## Comments` in the issue file (as issue 10 did: "Host check passed (user, date)"). A failure becomes a new issue from `13`.

## Before you start (once)

1. On Windows, from the repo root on the `dev` branch, run `.\scripts\install.ps1`. This copies the pages into `reaper_www_root` and the scripts into `Scripts\LCRR\arrange\`. Re-run it after any code change, or you are testing old code.
2. Restart REAPER so the bridge (`LCRR_Arrange_Bridge.lua`) restarts on the new code. If unsure, run the action once by hand from the Action list.
3. Open `http://<host>:<port>/lcrr-arrange.html` (the port is the one set under Preferences, Control/OSC/web). The page header must not say "Bridge not running". If it does, the bridge is not started: see step 2.
4. Use a **copy** of each project. Back up `podium-dummy.rpp` and its `.arrangements.lua` (and `Rehearsal_Current.*`) before you begin; Apply rewrites the timeline. `Ctrl+Z` in REAPER reverts an Apply, but a backup is cheaper.
5. Open the project you are testing in REAPER and make sure it is the **active project tab**. The bridge only sees the active tab.
6. Have a text editor open on the project's `<Project>.arrangements.lua` (the file sits beside the `.rpp`). Save with the editor's normal Save. After a page edit the file is rewritten whole, so reload it in the editor before editing it again.

The sidecar looks like this (one Arrangement per line, one entry per region, Headroom in seconds):

```lua
return {
  ["This"] = {
    { "Intro", headroom = 0 },
    { "Outro", headroom = 300 },
  },
  ["Empty"] = {},
}
```

---

## Issue 06: the Check token binds the Arrangement's contents

Needs `podium-dummy` (or any project with two Arrangements that Check as "will proceed") and a text editor on its sidecar.

### 06-a. Edit the checked Arrangement, then Apply: refused
- [ ] 1. On the page's **Run** tab, pick Arrangement A and click **Check**. Wait for the verdict "will proceed" and for the Apply button to become active.
  2. Switch to your text editor, swap two region names inside A (or change a `headroom` number), and **save**. Do not touch the page.
  3. Back on the page, click **Apply**.
  - **Pass:** Apply does nothing to the project, and the page says *"This Arrangement was edited since this Check, so what you read is not what would run. Nothing was applied. Check again, then apply."* The run log beside the project has no new "Apply Arrangement" entry, and the REAPER timeline is unchanged.
  - **Then:** click Apply again. It should say the Check has expired or was already used (the token was dropped). Check again, then Apply: it now proceeds.
  - **Fail:** the Apply runs, or the page shows a different error.

### 06-b. Edit a different Arrangement, then Apply: proceeds
- [ ] 1. Check Arrangement A as above ("will proceed").
  2. In the text editor, change only Arrangement B (a different name), and save.
  3. Click **Apply** on the page.
  - **Pass:** Apply runs as normal. Editing B must not invalidate A's token.
  - **Fail:** a "was edited since this Check" refusal.
  - After this check, Undo in REAPER (`Ctrl+Z`) or restore your backup before the next test.

### 06-c. Check on an empty Arrangement
- [ ] 1. Add `["Empty"] = {},` to the sidecar, save, and click the page's reload (or refocus the window).
  2. Pick **Empty** on the Run tab and click **Check**.
  - **Pass:** the verdict is "would refuse" with a finding that reads *"Arrangement "Empty" has no regions in it. Applying it would park every region…"*, plus the usual "not planned" note. **No Apply button/token** appears.
  3. Go to the **Edit** tab and pick Empty.
  - **Pass:** an inline hint says the Arrangement is empty and tells you to add regions (see `emptyArrangementNote`).
  - **Fail:** a token is issued, Apply is enabled, or the Edit tab shows no hint.

---

## Issue 07: Run and Edit tabs and the editor (the unticked remainder)

The drag, Headroom, Add/Remove, New/Duplicate/Rename, Delete prompt, tablet and rewrite-question checks are already ticked in `host-checks.md`. These are left. Do them on `podium-dummy`, then repeat 07-a on `Rehearsal_Current`.

### 07-a. Stale file: refusal and reload
- [ ] 1. Open the Edit tab on an Arrangement, with the sidecar also open in your text editor.
  2. In the editor, change something small (add a comment line or move a region) and **save**.
  3. On the page, make **any** edit (e.g. step a Headroom by 1 s) **without** refocusing the page first if you can (clicking inside the page counts as focus on some browsers: if the page already re-read the file, the edit simply succeeds, and that is the second half of this check).
  - **Pass (stale path):** the edit is refused with a stale message, the page reloads the file and shows the text-editor change, and your page edit was **not** applied.
  - **Pass (refocus path):** when you return to the browser window after saving, the page re-reads the file by itself and shows the new content without an error.
  - **Fail:** your page edit overwrites the text-editor change.

### 07-b. A region name not in the project
- [ ] 1. In the sidecar, add a region name that does not exist in the project (e.g. `{ "Zulu", headroom = 0 }`) to an Arrangement, and save.
  2. Open that Arrangement on the Edit tab.
  - **Pass:** the row for "Zulu" is flagged (an amber "not in the project" style flag), and **only Remove** is offered: no drag handle, ↑/↓ or Headroom box. Removing it works.

### 07-c. Missing and unreadable sidecar
- [ ] 1. **Missing:** with the project closed or the file renamed away (`<Project>.arrangements.lua` → `.bak`), open the Edit tab.
  - **Pass:** the tab offers **New** and nothing else. Creating one writes a new sidecar.
  2. **Unreadable:** restore the file and break its syntax (delete a closing brace), save, and reload the page.
  - **Pass:** the tab shows the parse error and **no edit controls**. Fix the file, reload: controls return.

### 07-d. Last tab remembered
- [ ] Select the **Edit** tab, reload the page (`F5`). It opens on Edit. Select **Run**, reload: it opens on Run.

### 07-e. "Check this Arrangement" hand-off
- [ ] On the Edit tab, with an Arrangement selected, click **Check this Arrangement**.
  - **Pass:** the page switches to the Run tab with that Arrangement selected and starts the Check.

### 07-f. Desktop width layout
- [ ] On a normal desktop browser window, run a Check that produces long findings (e.g. a Check with Headroom on a project with many regions, or a refusal). Read the result card.
  - **Pass:** text wraps, nothing is clipped or overflows horizontally, and the Edit tab rows don't jitter when you hover a drag over them (the drop indicator is a 3 px border that grows the row by 2 px; note if the jitter bothers you, see issue 12's CSS note).

---

## Issue 09: clear the Headroom just applied

Use `podium-dummy` (backed up). Arrangement `This` had +300 s on Outro; if your copy no longer has it, set Outro's Headroom to 300 on the Edit tab.

### 09-a. The offer after a Headroom Apply
- [ ] 1. On the Run tab, pick `This` and **Check**. The result should list the Headroom (Outro +300 s) and ask nothing yet.
  2. Click **Apply**. The page asks the Headroom question.
  3. Answer **Apply the Headroom** (not "Repack only").
  - **Pass:** the Repack runs, and the result card shows a button **Clear the Headroom just applied**.

### 09-b. Clear it
- [ ] 1. Click **Clear the Headroom just applied**.
  - **Pass:** the card says the Headroom was cleared. Open the sidecar (reload it in the editor): Outro reads `headroom = 0`.
  2. **Check** `This` again.
  - **Pass:** no Headroom question appears (nothing left to ask), and Apply is a plain Apply.

### 09-c. Undo brings it back
- [ ] On the **Edit** tab, click **Undo**. The tooltip should name what it undoes. Outro's Headroom returns to 300 and the sidecar shows `headroom = 300`.

### 09-d. No offer when it does not apply
- [ ] 1. Repeat 09-a but answer **Repack only**. **Pass:** no "Clear" button.
  2. Apply an Arrangement that has **no** Headroom at all. **Pass:** no "Clear" button.
  3. Answer cancel to the Headroom question. **Pass:** nothing is applied and no "Clear" button.

### 09-e. Rewrite question inside the result card
- [ ] 1. Put a hand-written comment into the sidecar (e.g. `-- my note` above `return {`), save, and use an Arrangement with Headroom through 09-a.
  2. Click **Clear the Headroom just applied**.
  - **Pass:** the rewrite question ("the page rewrites this file and drops comments") appears **inside the result card**, not on the Edit tab. Answering it completes the clear.
  - **Fail:** the question is not visible from the Run tab, or the clear silently drops your comment.

---

## Unrequested scope to document

- Commit `c99d175` rewrote the Capture summary wording in both front ends (the page and the dialog) and changed five dialog transcripts in `spec/fixtures/dialogs/LCRR_Arrange_Capture/`. It also added a 26-line `regions_spec.lua` test, "guard zero-delta plan entries". Neither is in any issue; the spec says the Capture transcripts change "for this [rewrite question] on purpose" only. Add a line to `apps/arrange/docs/decisions.md`, or an issue, recording why.

## Recording results

- Tick the boxes above. When every box under an issue passes, append `Host check passed (user, <date>).` to that issue's `## Comments`.
- If a check cannot run (no tablet, no second project), say so under the issue instead of ticking it.
