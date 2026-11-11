# Contributing to LiveCues ReaperRemote

Thanks for helping. LCRR is plain HTML, CSS and JavaScript, plus Lua for the apps with a REAPER side. There is no build step, no compiled code, no runtime dependency and no SWS, and changes need to keep it that way.

## How to send a change

1. Report bugs and suggest ideas in [GitHub Issues](https://github.com/GiorgosKoulouris/livecues-reaper-remote/issues). For anything larger than a small fix, agree the approach in an issue first.
2. Work from the `dev` branch and open your pull request against `dev`.
3. Make sure `npm test` and `npm run check` both pass. CI runs them on every pull request.

For security problems, follow [SECURITY.md](SECURITY.md) instead of opening an issue.

Paths under `.scratch/` in docs and code comments point at the maintainer's private planning notes, which are not in the repo.

By contributing, you agree that your work is released under the [MIT License](LICENSE).

## Development setup

Use the devcontainer in `.devcontainer/`. It has node, python3, curl, jq, gh, lua5.4, busted and luacheck. There are no npm dependencies to install.

| Command | What it does |
|---|---|
| `npm test` | Runs every test: scripts, shared code, apps, and busted for apps with Lua |
| `npm run check` | Syntax-checks every browser script and the scripts, and runs luacheck |
| `npm run serve` | Serves all the pages on `http://localhost:8081/` (use VS Code port forwarding) |

`npm test` and `npm run check` fail outside the devcontainer if busted or luacheck are missing.

REAPER runs on the Windows host and can't be reached from the container, so pages served by `npm run serve` show their offline state. To test against REAPER, install from your checkout with `-Link` (below).

**Don't publish port 8080 in `.devcontainer/docker-compose.yml`.** The container would take REAPER's web port on the host, and `localhost:8080` would then show `ERR_EMPTY_RESPONSE` even though REAPER's dialog says the server is up.

## Installing from your checkout

Run this on the Windows host, from the repo folder, in PowerShell. `scripts\install.bat` takes the same arguments from cmd and avoids execution-policy prompts.

```powershell
.\scripts\install.ps1                               # copy into %APPDATA%\REAPER (re-run to update; no admin needed)
.\scripts\install.ps1 -Link                         # symlinks instead: edits show on browser refresh (Developer Mode or admin)
.\scripts\install.ps1 -Root D:\www -Port 9000       # custom web root, and the port the printed URLs show (default 80, left out of the URL)
.\scripts\install.ps1 -Resource D:\PortableReaper   # REAPER resource path for the Lua (default %APPDATA%\REAPER)
.\scripts\install.ps1 -Uninstall                    # removes lcrr*.html, the lcrr folder, Scripts\LCRR and LCRR's startup lines
```

- The Lua goes to `<resource path>\Scripts\LCRR\<part>\`. Load new actions once in REAPER: **Actions > Show action list > New action > Load ReaScript**.
- If scripts are blocked, use `install.bat` or `powershell -ExecutionPolicy Bypass -File .\scripts\install.ps1`.
- If the repo lives in WSL or a container, run the script through its Windows path (for example `\\wsl$\...`).
- Don't install into `C:\Program Files\REAPER (x64)\Plugins\`: REAPER treats that folder as internal.
- Install is one-way. Don't edit the installed files in REAPER's script editor, because the next install overwrites them. If REAPER's behaviour doesn't match the code, re-run the install first.

## Repo layout

```
CONTEXT-MAP.md  CONTEXT.md  DESIGN.md  PRODUCT.md   suite docs (CONTEXT.md has the REAPER API facts)
docs/adr/                       suite decisions
shared/www/lcrr/shared/         shared JS and CSS; tests in shared/test/
shared/reaper/                  shared Lua: bridge plumbing and the startup hook actions
apps/<app>/                     one folder per app
  CONTEXT.md  docs/adr/  test/  that app's facts, decisions and tests
  www/lcrr-<app>.html           entry page (Home: lcrr.html)
  www/lcrr/<app>/{css,js}/      its assets
  reaper/Scripts/LCRR/<app>/    Lua actions and lib/, for apps with a REAPER side (specs in spec/)
scripts/                        install, local server, checks and release build (tests in test/)
```

Each `www/` folder holds files at the exact paths REAPER serves them from. Install, release and `npm run serve` lay them over each other. A `reaper/` folder does the same for REAPER's resource path.

Before changing an app, read its `CONTEXT.md` and ADRs. [CONTEXT-MAP.md](CONTEXT-MAP.md) lists them all. Naming and suite rules are in [CLAUDE.md](CLAUDE.md), and the visual system is in [DESIGN.md](DESIGN.md).

## Working on Arrange

Start at [apps/arrange/CLAUDE.md](apps/arrange/CLAUDE.md), which lists the traps and conventions. The decisions behind it are in [apps/arrange/docs/adr/](apps/arrange/docs/adr/), and [apps/arrange/docs/limitations.md](apps/arrange/docs/limitations.md) says what has not been observed in real REAPER.

- `lib/` must stay beside the `LCRR_Arrange_*.lua` scripts, because each script finds it relative to itself.
- To run only Arrange's specs and lint, run `busted` and `luacheck .` in `apps/arrange/`.

## Releases

One ReaPack package and one version cover the whole suite. The maintainer cuts releases, following [docs/agents/release.md](docs/agents/release.md).
