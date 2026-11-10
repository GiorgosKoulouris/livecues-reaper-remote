# 0001: No lock; destructive keys are press-and-hold

The page used to open locked, and one Unlock tap enabled every change. It is a desk tool: the lock cost a tap per visit, changed the density of the grid when it opened, and protected little, because every change is one REAPER undo step and the keys that remove things were already press-and-hold.

**Decision.** There is no lock. `core.canEdit(phase)` is open while the bridge is live (and the page has no write in flight). What guards a stray touch instead:

- Delete and Adopt are press-and-hold (1 s), in a mix's More group (Adopt on a stray only). The page has no row or column bulk keys.
- A cell tap is a single tap: it adds or removes one send, and the first change of a visit says that undo is in REAPER (Ctrl+Z).
- Every key that writes is 44px.

**Consequences.** `stillUnlocked` and the Unlock key are gone. A change of active project clears a half-done rename and any open More group. Monitor's and IEM Mix's pages keep their own locks (their writes are live-show levels, not setup).
