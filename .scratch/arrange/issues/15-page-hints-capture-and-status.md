# 15. Page hints, Capture and status text

Status: done
Type: enhancement

Spec: `.scratch/arrange/wording-spec.md`, section "Page and Capture".

## Work

- `lcrr-arrange.html`: delete the Check/Verify hint, the Edit tab Headroom hint and the REAPER-only note.
- `arrange.js`: new note by Apply, new chip and banner text, and remove any CSS left unused (`.arrange-host-note`, `.arrange-code`).
- Capture's summary in `lib/text/capture.lua` and `words.captureSummary`. Keep the script's next step correct for someone not on the page.
- Shorter delete question.
- Show Bar Lines and Show Track Timebase: drop internals from the console report and "Nothing has been changed" from dialogs.

## Acceptance

- Capture still tells the user what to do next.
- `npm test` and `npm run check` pass, and the transcript diff has been read.
- On the host: the page shows no leftover empty spaces where hints were.

## Comments

Implemented on dev. `npm test` and `npm run check` pass; the dialog transcript diffs were read (only console blocks and the reworded Capture/Show Bar Lines/Show Track Timebase text changed; run-log entries are byte-for-byte unchanged). The on-host acceptance checks are still to be done by hand.
