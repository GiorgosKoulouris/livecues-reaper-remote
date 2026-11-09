# 0002. Stop is hold-to-stop; Play and Stop share one slot

Date: 2026-11-07. Status: accepted. Amends the consequence in ADR 0001 that "Stop is one tap".

## Context

Stop was a single tap, so a stray touch on the always-visible header could kill a running song or take. That conflicts with product principle 1 (a stray touch must not disrupt the show). ADR 0001 accepted the one-tap Stop deliberately, so this is a reversal, not an oversight.

## Decision

- Stop needs a 500 ms press-and-hold (`STOP_HOLD_MS`, `LCRR.shared.hold`) with a sweep fill, playing or recording. Keyboard: hold Enter or Space. A click or tap alone never stops.
- Play and Stop share one slot in the one-row sticky header: Stop while playing or recording, Play otherwise (paused shows Play so it can resume; offline shows a disabled Play).
- Stop is icon-only (square glyph, accessible name "Hold to stop").

## Consequences

- Restarting the current song is Stop (hold), then ▶ on the same row; the stage workflow in ADR 0001 now costs a hold at each step.
- Stop is slower in an emergency. Accepted: 500 ms matches hold-to-cue, and a stray stop on stage is worse than a half-second delay.
