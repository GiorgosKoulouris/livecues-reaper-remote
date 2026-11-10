# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Users

- **Performers and stage operators** running a REAPER session (live show, rehearsal) who act on it from a phone or tablet on the same trusted LAN, away from the DAW, often in low light. Podium serves the operator; Monitor serves each performer adjusting their own in-ear mix.
- **The engineer or producer at the desk** using Arrange to repack regions from a browser, not on stage.

## Product Purpose

LiveCues ReaperRemote (LCRR) is a suite of small remote-control pages served by REAPER's built-in web interface. A home page (`lcrr.html`) launches each app; each app does one job well. Apps: **Podium** (stage transport, region and marker cue list), **Monitor** (personal in-ear mixes from a phone), **Arrange** (region Repack: Check, Apply, Verify, Capture, diagnostics, through a background Lua script). Success is a session that runs without anyone walking to the DAW and without a stray touch disrupting it.

## Positioning

A set of focused, safe tools rather than one full remote. Zero install on the client (open a URL), no compiled code, no SWS.

## Operating Context

- Served from `%APPDATA%\REAPER\reaper_www_root` by REAPER's web interface; installed via ReaPack (verified on Windows with the 1.1.0 betas) or with the PowerShell script (development and fallback). The home page is meant to be the "Default interface".
- Windows is the primary host; clients are phone, tablet or desktop browsers on a trusted LAN.
- Every app polls REAPER's web API and must show an offline state when the server stops responding.

## Capabilities and Constraints

- Plain HTML/CSS/JS, no build step, no runtime dependencies. Arrange adds a Lua slice installed into REAPER's resource path.
- One ReaPack package and one version for the whole suite.
- Every app page except Home ends with the shared suite footer (Home link).
- Out of scope: internet exposure.
- Verified REAPER API facts live in `CONTEXT.md`.

## Product Principles

1. Prevent accidents before adding capability: a stray touch must never disrupt the session.
2. Glanceable from a distance, in the dark.
3. Stay small and zero-install; add nothing that needs compiled code or extra tooling.
4. Fail visibly: when REAPER is unreachable, say so.
5. One suite, one look: apps share tokens, base styles and navigation.

## Accessibility & Inclusion

- Dark stage and low-light use: readable without glare.
- Large, error-proof touch targets (44px minimum).
- WCAG AA contrast as the baseline; state never conveyed by color alone.
