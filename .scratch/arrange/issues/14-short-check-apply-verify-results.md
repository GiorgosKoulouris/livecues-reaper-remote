# 14. Short Check, Apply and Verify results

Status: done
Type: enhancement
Blocked by: 13

Spec: `.scratch/arrange/wording-spec.md`, sections "Check", "Apply" and "Verify".

## Work

- Check: new verdicts and one-line effects, in `lib/text/check.lua` and `words.js`. In `arrange.js`, `showCheck` stops rendering severity headings, code chips, `paddingNote` and blind spots.
- Apply: new summary in `lib/text/apply.lua` and `words.applySummary`, sharing the effect lines with Check in the past tense. Short Headroom confirmation in `text.headroom_prompt` and `words.headroomQuestion`.
- Verify: new lines and fix in `lib/text/verify.lua` and `words.js`. `showVerify` drops blind spots. The message box must list the problems, because the console will no longer show them.
- The fix line must depend on the findings: "Apply again" does not help if a region is missing.
- Message boxes use the 8-name cap from issue 13. The Headroom confirmation's cap points at the Edit tab, because nothing is logged yet.
- `blind_spots` and `padding_exact` stay in the reply. The console report and run log keep the full text for now; issue 16 removes the console side.

## Acceptance

- Effects listed in the spec, and only those, appear on Check and after Apply.
- The offer to clear Headroom and the Headroom confirmation still work.
- `test/words.test.js` asserts the new wording rather than the old capitals.
- `npm test` and `npm run check` pass, and the transcript diff has been read.

## Comments

2026-11-08: done. Check, Apply and Verify message boxes and the page use the spec wording; effects are shared in `lib/text/effects.lua`. Console report and run log keep the detailed text until issue 16. Not run against real REAPER or a browser.
