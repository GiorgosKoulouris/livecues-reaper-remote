# 07. Switch a matrix cell on and off

Status: ready-for-agent
Blocked by: 01, 04

## Build

- On: create a send from source to mix, post-FX pre-fader at 0 dB.
- Off: delete every send from that source to that mix at once, with no warning.
- One undo step each. Only while unlocked. Double taps can't queue conflicting operations.

## Done when

Specs cover on, off, several sends between one pair, and a source or mix that has gone. `npm test` and `npm run check` pass. Removing a send doesn't misdirect an open Monitor page's writes (issue 01 result).
