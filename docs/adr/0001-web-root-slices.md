# 0001. Each app is a slice of reaper_www_root: entry pages at the top, assets under lcrr/

Date: 2026-11-07. Status: accepted.

## Context

The repo became a suite (LiveCues ReaperRemote) with a home page and several apps. REAPER lists only the top-level `.html` files of `reaper_www_root` as "Default interface", which is why Podium Remote shipped every file flat with a `podium-remote-` prefix. Flat folders don't scale to several apps, and an app's code, docs and tests should sit together so an agent working on one app doesn't load the others.

Verified on real REAPER (Nov 2026): the web server does serve files from subfolders (`/lcrr/test.txt`).

## Decision

- Entry pages stay at the top level: `lcrr.html` (home) and `lcrr-<app>.html`. All other files go under `lcrr/<app>/{css,js}/` and `lcrr/shared/{css,js}/`, without a file prefix.
- In the repo, each app's `apps/<app>/www/` (and `shared/www/`) holds its files at their exact deployed paths: a slice of the web root. `scripts/install.ps1`, `npm run release` and `npm run serve` lay all slices over each other; two slices shipping the same path is an error.
- Rejected: one repo-level `www/` mirror (splits each app across two trees); flat app folders moved into place by scripts (relative URLs would differ between the repo and REAPER); keeping everything flat.

## Consequences

- Repo paths are one level deeper (`apps/podium/www/lcrr/podium/js/`), but what you see is exactly what REAPER serves, and `install.ps1 -Link` keeps working (folder symlinks per `lcrr/<part>`).
- Pages need the `lcrr/` folder beside them; a copy of only the `.html` files loads unstyled.
- Fallback if a REAPER version ever stops serving subfolders: flatten at install and release time, keeping the repo layout.

## Amendment (2026-11-07): reaper/ slices

Arrange (`.scratch/arrange/spec.md`) ships ReaScript actions, which live under REAPER's resource path, not the web root.

- An app may also have `apps/<app>/reaper/`: a **reaper slice**, mirroring REAPER's resource path the way `www/` mirrors the web root. It holds only `Scripts/LCRR/<app>/`: the entry scripts `LCRR_<App>_<Verb>.lua` with their `lib/` beside them (scripts find `lib/` through `get_action_context()`).
- `scripts/install.ps1` lays each `Scripts/LCRR/<part>` folder into `<resource path>\Scripts\LCRR\` (copies, or folder links with `-Link`), and `-Uninstall` removes `Scripts\LCRR`. It refuses anything else in a reaper slice, and two slices shipping the same part.
- Release (zip) and the ReaPack index don't carry reaper slices yet; that is a later step (per-source `type="script"`, unverified).
- An app with Lua keeps its specs in `apps/<app>/spec/` (busted, `.busted`, `.luacheckrc`); `npm test` and `npm run check` run busted and luacheck in every app that has those configs (`scripts/lua.js`).
