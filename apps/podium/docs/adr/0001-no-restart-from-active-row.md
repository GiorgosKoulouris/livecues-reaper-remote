# 0001. The active row has no ▶; ▶ is hold-to-cue while the transport runs

Date: 2026-11-07. Status: accepted. Supersedes the CONTEXT.md line "Tapping the active region's button restarts it".  The Stop part was later amended by ADR 0002.

## Context

A single tap on any row's ▶ sent seek+play immediately, including mid-song. That made a stray touch able to cut the song being played, which conflicts with product principle 1 (a stray touch must never start playback). The active row's ▶ restarted its own song, which is the same hazard (a double-tap restarts the song). The earlier decision was deliberate, so this is a reversal, not an oversight.

## Decision

- While the transport is running (playstate not 0), a ▶ needs a 500 ms press-and-hold (`CUE_HOLD_MS`, `LCRR.shared.hold`) to cue. When stopped, ▶ stays a single tap.
- The active region's ▶ is replaced by a now-playing indicator. Restarting the current song means Stop, then ▶ on the same row.
- Repeat cue taps within 1.5 s are ignored, and the pressed button shows a pending state.
- After an offline period, ▶ stays disabled for 1.5 s after reconnect.

## Consequences

- No one-tap restart from the active row. Accepted: Stop (hold, see ADR 0002) and a hold-cue on another row is the stage workflow.
- Markers use the same hold rule (they have no active row).
- Paused counts as running (playstate 2), so ▶ also needs a hold while paused.
