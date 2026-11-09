# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Users

Performers, operators and engineers running a REAPER session (live show, rehearsal, recording) who need to act on it from a phone, tablet or second computer on the same trusted LAN, away from the DAW and often in low light.

## Product Purpose

LiveCues ReaperRemote (LCRR) is a suite of small remote-control pages served by REAPER's built-in web interface. A home page (`lcrr.html`) launches each app; each app does one job well. Apps: **Podium** (stage transport and cue list; `apps/podium/PRODUCT.md`). More will follow.

## Positioning

A set of focused, safe tools rather than one full remote. Zero install on the client: open a URL.

## Operating Context

- Served from `%APPDATA%\REAPER\reaper_www_root` by REAPER's web interface; installed with the PowerShell install script or via ReaPack (unverified). The home page is meant to be the "Default interface".
- Windows is the primary host; used from phone, tablet or desktop browsers.
- Every app polls REAPER's web API and must show an offline state when the server stops responding.

## Capabilities and Constraints

- Plain HTML/CSS/JS; no compiled code, no SWS, no build step, no runtime dependencies.
- All files carry the `lcrr` prefix or live under `lcrr/`. One package, one version for the whole suite.
- Every app has the same suite footer with Home, at the bottom.
- Out of scope for the suite: internet exposure.

## Product Principles

1. Prevent accidents before adding capability: a stray touch must never disrupt the session.
2. Glanceable from a distance, in the dark.
3. Stay small and zero-install; add nothing that needs compiled code or extra tooling.
4. Fail visibly: when REAPER is unreachable, say so.
5. One suite, one look: apps share tokens, base styles and navigation.

## Accessibility & Inclusion

- Dark stage / low-light use: must stay readable without glare.
- Large, error-proof touch targets (44px minimum).
- WCAG AA contrast as the baseline.
