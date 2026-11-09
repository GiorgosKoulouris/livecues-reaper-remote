# 10. Later: solo in my mix

Status: resolved
Type: task
Blocked by: 07

Let a musician hear one source alone in their own ears for a moment. The web API has no per-send solo, so this means muting the mix's other receives and restoring them afterwards.

## To decide

- Where the previous mute states are kept, and what restores them if the phone locks, loses Wi-Fi or leaves the page. A lost phone must not leave a mix silent.
- Whether it works while held or as a toggle.
- How it interacts with other phones on the same mix, and with undo.

## Comments

Still needs triage: the maintainer will review it in a separate session. Issue 07 is resolved, so nothing blocks it.

Layout decided in the visuals review: if Solo is built, each row becomes `[fader][S][M]`. No space is reserved until then.

Decided by the maintainer when implementing: a toggle (not hold); the previous mute states are kept in page memory only; restore puts back only what solo changed (other phones' later changes are left alone); undo is not special-cased.

Implemented: S button before M on each source row (`core.soloPlan`/`restorePlan`, wiring in `monitor.js`). Tap S again, or Back, to restore; moving solo to another row keeps the original states. `npm test` and `npm run check` pass.

Open: with memory-only state, a page reload, lost Wi-Fi or a locked phone while solo is on leaves the mix muted (M undoes it by hand). Not tried on a phone yet (issue 07).
