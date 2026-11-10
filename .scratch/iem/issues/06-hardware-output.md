# 06. Set a mix's hardware output

Status: ready-for-agent
Blocked by: 01, 04

## Build

- A picker per mix: mono or stereo, listing the device's named channels (channel numbers if names aren't available).
- At most one hardware output. Setting one replaces the existing one; a mix can also be cleared to none.
- Flag an output shared with another mix or the master, without refusing it.
- A track with several outputs is read-only here.

## Done when

Specs cover set, replace, clear, the clash flag and the read-only case. `npm test` and `npm run check` pass. The mono behaviour matches what issue 01 found.
