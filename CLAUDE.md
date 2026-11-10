# LiveCues ReaperRemote (LCRR)

A suite of remote-control pages for REAPER, served by REAPER's built-in web interface. Plain HTML/CSS/JS, no build step, no dependencies, no compiled code, no SWS. Windows is the primary host.

## Where things are

- `apps/<app>/`: one folder per app (`home`, `podium`, `arrange`). Each has its own `CLAUDE.md`, `CONTEXT.md`, `docs/adr/`, `test/` and `www/`. Work inside one app and read only that app's docs. Arrange is Lua plus a page: a `reaper/` slice and busted `spec/` beside `www/` and `test/`.
- `shared/`: code and CSS every app uses (REAPER reply parsing, poller, guards, press-and-hold, tokens, base CSS, suite footer). See `shared/CLAUDE.md` before changing it.
- `scripts/`: install (Windows), release, syntax check, local server. `test/`: tests for those scripts.
- `CONTEXT.md`: suite facts and the verified REAPER web API facts. `docs/adr/`: suite decisions. `DESIGN.md`: the suite's design system. `README.md`: setup, install, dev, release.

## Suite rules

- Each `www/` folder is a slice of REAPER's `reaper_www_root`, at the exact paths it deploys to. Install, release and `npm run serve` lay the slices over each other (`docs/adr/0001`). A `reaper/` folder is a slice of REAPER's resource path (`Scripts/LCRR/<app>/`), laid in by `install.ps1` (same ADR, amendment).
- Naming: entry pages `lcrr.html` (home) and `lcrr-<app>.html` at the top level of a slice; everything else under `lcrr/<app>/{css,js}/` with no file prefix. CSS classes and IDs use `lcrr-` for shared parts and `<app>-` for app parts. JS goes under the one global `LCRR` (`LCRR.shared.*`, `LCRR.<app>.*`), using the UMD wrapper already in use so node tests can `require` the same file.
- Every app page links the shared icons (`lcrr/shared/img/`), loads `lcrr/shared/css/tokens.css` and `base.css` first, and ends with the shared footer (Home link to `lcrr.html`). The home page has no footer (`docs/adr/0003`).
- A new app: add `apps/<app>/` with the same shape, add its button to `apps/home/www/lcrr.html`, and add it to `CONTEXT-MAP.md`.
- One ReaPack package and one version for the whole suite (`docs/adr/0002`); the version lives in the root `package.json` and, kept equal by a test, in `shared/www/lcrr/shared/js/version.js` (shown in the footer). Releases and the ReaPack index: see the README's Release section and the ADR 0002 amendment.
- `npm test` and `npm run check` must pass before committing. They also run busted and luacheck (Lua 5.4) for apps with Lua, and fail if those tools are missing: use the devcontainer.

## Agent skills

### Issue tracker

Issues and specs are local markdown files under `.scratch/`. See `docs/agents/issue-tracker.md`.

### Triage labels

Default five-role vocabulary (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Releasing

Versions, tags, `index.xml`, ReaPack and live testing: **read `docs/agents/release.md` before bumping a version, creating or pushing a tag, or touching `index.xml`.** Never push or tag-push without the owner's explicit say-so.

### Domain docs

Multi-context: `CONTEXT-MAP.md` at the root points at each context's `CONTEXT.md`; suite ADRs in `docs/adr/`, app ADRs in `apps/<app>/docs/adr/`. See `docs/agents/domain.md`.

## User rules

- When asking questions, use AskUserTool.
- Development note: All changes are made in a branch named dev. Do not merge into main and do not work directly on main.
- Development note: Do not include Claude/Anthropic as co-author in commits.
