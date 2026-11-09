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
