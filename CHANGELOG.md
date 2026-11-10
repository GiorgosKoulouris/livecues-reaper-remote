# Changelog

## 1.1.0-beta3 (2026-11-10)

- install.ps1 -Uninstall (and a re-install) now also remove or replace the __startup.lua lines written by the LCRR: Install startup hook action; both match on the bridge id (test/startup-ids.test.js)
- The repository is now livecues-reaper-remote and main is its default branch: import the ReaPack URL from the README again
- GitHub: CI, tag-based releases, issue forms, pull request template and SECURITY.md
- The IBM Plex license text ships with the fonts

## 1.1.0-beta2 (2026-11-10)

- Test release to check ReaPack update, Remove startup hook and uninstall; no functional change from beta1 except the version number

## 1.1.0-beta1 (2026-11-10)

- ReaPack delivery: the index carries the web pages and the Lua (per-source type=script), index name LCRR, category Remote
- LCRR: Install startup hook and LCRR: Remove startup hook actions manage the bridge lines in Scripts/__startup.lua
- The suite footer shows the installed version
- README, CONTEXT.md and ADR 0002 describe the ReaPack path
