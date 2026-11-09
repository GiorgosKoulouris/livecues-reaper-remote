# Product: Podium

## Platform

web

## Users

Primary: a performer or operator running a live show or rehearsal, using a phone or tablet on the same trusted LAN as the computer running REAPER. They are on stage or away from the computer, often in low light, and need to start songs (regions) and stop playback without touching the DAW.

## Product Purpose

Podium is the stage app of LiveCues ReaperRemote (see the root `PRODUCT.md`). It is a plain HTML/JS page served by REAPER's built-in web interface. It gives any device on the LAN a transport bar (play/stop, time and state, Rec), a region list and a marker list. Success: the operator reliably starts the right region and stops it, with no accidental actions.

## Positioning

Safe, minimal and glanceable. Only the ▶ button on a row acts (rows are not tappable, so scrolling can't start playback), Rec requires an 800 ms press-and-hold, and Stop a 500 ms one. It is deliberately small, not a full remote.

## Operating Context

- Served by REAPER's web interface as `lcrr-podium.html`, reached from the suite's home page.
- Polls REAPER's web API; the page must show an offline state when the server stops responding.

## Capabilities and Constraints

- Transport: play, stop, time/state display, Stop and Rec with press-and-hold.
- Regions and Markers tabs; current region highlighted only while the transport is active.
- IDs and classes prefixed `podium-`. Home is the shared suite footer.
- Out of scope for v1: pause, prev/next, loop, queued playback, marker add/edit/delete, project selector.
- Behaviour decisions live in `apps/podium/CONTEXT.md`; REAPER API facts in the root `CONTEXT.md`.

## Product Principles

1. Prevent accidents before adding capability: a stray touch must never start playback or recording.
2. Glanceable from a distance, in the dark: current state is readable at once.
3. Stay small; deliberately not a full remote.
4. Fail visibly: when REAPER is unreachable, say so.

## Accessibility & Inclusion

- Dark stage / low-light use: must stay readable without glare.
- Large, error-proof touch targets.
- WCAG AA contrast as the baseline.
