# 0002. One ReaPack package and one version for the whole suite

Date: 2026-11-07. Status: accepted.

## Context

Every app depends on the shared library (`lcrr/shared/`). ReaPack refuses to let two packages own the same file, so per-app packages would need a separate shared package that users must also install, and versions that can drift apart.

## Decision

- The suite ships as one ReaPack `webinterface` package (main file `lcrr.html`) containing the home page, every app and the shared library, and as one zip.
- There is one version, in the root `package.json`. One root `package.json` also runs every test and check.

## Consequences

- Installing LCRR gives the user every app; a fix to one app is a suite release.
- No file-ownership conflicts and no shared-version skew between apps.
- Revisit only if apps become large or are meant to be installed separately.

## Amendment (2026-11-10): ReaPack is the delivery path, with Lua

Arrange and IEM Setup ship Lua, and ReaPack cannot edit `__startup.lua`. Decided with the owner (grilling, 2026-11-10):

- ReaPack is the install and update path (a prerequisite for users; no self-made updater, no native extension). Hosted in the public GitHub repo `GiorgosKoulouris/LiveCues-RRemote`, `index.xml` committed at the root, file URLs pinned to a release tag. Windows first; macOS should work but is unverified.
- Still one package and one version. The index is named `LCRR`, with one category `Remote`; the web files are the package's `webinterface` sources, the Lua files are per-source `type="script"` sources whose `file` carries the part folder (`arrange/...`, `iem/...`, `shared/...`), so the parts stay siblings and the `..` lookup of `shared` (ADR 0001 amendment) is unchanged. Scripts land under `Scripts/LCRR/Remote/`; a package has one category, so ReaPack categories cannot name the parts. Entry scripts (`LCRR_*.lua` at the top of a part) register as actions.
- The bridge start-up line is installed by the action `LCRR: Install startup hook` and removed by `LCRR: Remove startup hook` (`shared/startup/hook.lua`). The lines are tolerant (start a bridge only if its file exists, looking in both install layouts), so a forgotten uninstall is silent.
- Updates take effect after a REAPER restart (documented, no self-restart). The version is in the footer (`shared/.../version.js`, kept equal to `package.json` by a test); the ReaPack changelog is the `## <version>` section of `CHANGELOG.md`.
- Releases go out as a pre-release first, imported in real REAPER by the owner, then promoted. `install.ps1` and the zip stay as development and fallback tools; switching from `install.ps1` means running its `-Uninstall` first.
- If live ReaPack rejects per-source types, stop and re-discuss (the two-package split was considered, not pre-approved).
- Live tests (2026-11-10, Windows, 1.1.0-beta1 and beta2): install, subfolders, per-source script types (Lua lands in `Scripts\LCRR\Remote\<part>\`), startup hook, footer, update, Remove startup hook and uninstall all worked; the hook's lines stay after an uninstall by design. macOS remains unverified: see `CONTEXT.md`.

## Amendment (2026-11-10): one public home for the import URL

Decided with the owner (grilling, 2026-11-10), before the first public launch:

- The repo is renamed `GiorgosKoulouris/livecues-reaper-remote`. Earlier mentions of `LiveCues-RRemote` in this ADR and in `CONTEXT.md`'s verified notes describe what was true at the time.
- `main` is the default branch from 1.1.0-beta3 on, and the ReaPack import URL is `.../main/index.xml` for betas and stable alike, so users only ever need one URL. `dev` stays the working branch. `main` moves only to a release commit that has passed the live test.
- The history is condensed once before launch. The tags `v1.1.0-beta1` and `v1.1.0-beta2` are deleted as a one-time exception to "tags are immutable", and 1.1.0-beta3 is the first release in the clean history.
