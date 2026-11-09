# Shared library

`www/lcrr/shared/` deploys to `reaper_www_root/lcrr/shared/` and is loaded by every app. A change here changes every app: run the full `npm test` and check each app's page.

- `js/reaper.js`: REAPER reply parsing and command strings (`LCRR.shared.reaper`). Facts it relies on are in the root `CONTEXT.md`.
- `js/poll.js`: one combined request per tick with a 3 s timeout; apps add commands with `addCommand()`. `send()` for one-off commands.
- `js/guard.js`: offline verdict (2 failed polls, settle time after reconnect) and a repeat-trigger cooldown.
- `js/hold.js`: press-and-hold helper for accident protection.
- `img/`: the suite icon (`icon.svg`, plus `icon-32.png` and `apple-touch-icon.png` as raster fallbacks). Every page links all three in its head.
- `css/tokens.css`: design tokens from `DESIGN.md`, plus the `@font-face` rules for the self-hosted IBM Plex Sans and IBM Plex Mono (`fonts/*.woff2`, open licence; no internet on the stage LAN, so never link a font host). `css/base.css`: reset, column page layout, the suite footer (`.lcrr-footer`, `.lcrr-home`).

Rules: JS stays pure where it is now (no DOM in `reaper`, `guard`, `hold`; timers and fetch injectable) and uses the UMD wrapper so tests `require` the same file. Something moves here only once it is not specific to one app. Tests: `shared/test/`.
