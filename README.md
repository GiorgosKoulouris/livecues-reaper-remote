# LiveCues ReaperRemote (LCRR)

Remote-control pages for REAPER, served by REAPER's built-in web interface. Open the home page from a phone, tablet or desktop on the same LAN and pick an app. No compiled code; SWS not required.

| App | Page | What it does |
|---|---|---|
| Home | `lcrr.html` | App buttons and a REAPER connection indicator |
| Podium | `lcrr-podium.html` | Transport bar, region list and marker list for the stage |
| Monitor | `lcrr-monitor.html` | Personal in-ear mixes from a phone: mix list so far |
| Arrange | `lcrr-arrange.html` | Region Repack from the desk: Check, Apply, Verify, Capture and diagnostics, through a background script in REAPER |

## Setup (Windows)

1. In REAPER: **Preferences → Control/OSC/web → Add → Web browser interface**.
2. Set a port (e.g. `8080`). Fill in "Username:password" if you want auth. Trusted LAN only: do not expose it to the internet.
3. Click **User pages...**: it opens `%APPDATA%\REAPER\reaper_www_root`. Install into that folder with `scripts\install.ps1` (below), or extract the release zip there keeping its folders: the `lcrr*.html` pages at the top, the `lcrr\` folder beside them. Do NOT use `C:\Program Files\REAPER (x64)\Plugins\` (REAPER marks it as internal).
4. Re-open the dialog; choose **lcrr.html** in the **Default interface** dropdown (REAPER lists only the top-level `.html` files of the web root) and click Apply.
5. Allow REAPER through Windows Firewall for private networks.
6. Open `http://<pc-ip>:<port>/` from a device on the same LAN. The dialog's "Access URL" shows the address.

## Install / update on the Windows host

Easiest: double-click `scripts\install.bat` in Explorer. It runs `install.ps1` (copy mode) without execution-policy prompts and keeps the window open to show the URLs. Re-run it to update.

From PowerShell (or `scripts\install.bat <same arguments>` from cmd), in the repo folder:

```powershell
.\scripts\install.ps1                 # copy into %APPDATA%\REAPER\reaper_www_root (re-run to update; no admin needed)
.\scripts\install.ps1 -Link           # symlinks instead: edits show on browser refresh (Developer Mode or admin)
.\scripts\install.ps1 -Root D:\www -Port 9000   # custom web root / port for the printed URLs
.\scripts\install.ps1 -Resource D:\PortableReaper   # REAPER resource path for the Lua actions (default %APPDATA%\REAPER)
.\scripts\install.ps1 -Uninstall      # removes lcrr*.html, the lcrr folder and Scripts\LCRR
```

The Lua actions (Arrange) go to `<resource path>\Scripts\LCRR\<app>\`. Load new ones once in REAPER: Actions > Show action list > New action > Load ReaScript.

If scripts are blocked, use `install.bat`, or `powershell -ExecutionPolicy Bypass -File .\scripts\install.ps1`. If the repo lives in WSL or a container, run it via its Windows path (e.g. `\\wsl$\...`).

## Troubleshooting

- **`localhost:8080` shows `ERR_EMPTY_RESPONSE` (but REAPER's dialog says the server is up):** something else owns the port on the host, e.g. a devcontainer publishing `8080:8080`. Never publish REAPER's web port from Docker; check with `netstat -ano | findstr :8080`, or try `http://<pc-ip>:8080/` directly.
- **`lcrr.html` missing from "Default interface":** entry pages must be at the top level of the web root, not in a subfolder; reopen the dialog after installing.
- **Page loads unstyled or does nothing:** the `lcrr\` folder is missing next to the `lcrr*.html` pages.
- **Page unreachable from another device:** allow REAPER through Windows Firewall (private network) and use the dialog's "Access URL".

## Repo layout

```
CLAUDE.md  CONTEXT-MAP.md  CONTEXT.md  DESIGN.md  PRODUCT.md   suite docs (CONTEXT.md has the REAPER API facts)
docs/adr/                       suite decisions
shared/www/lcrr/shared/         shared JS (reaper, poll, guard, hold) and CSS (tokens, base + footer); tests in shared/test/
apps/<app>/                     CLAUDE.md, CONTEXT.md, docs/adr/, test/, and www/ (the app's slice of the web root)
  reaper/Scripts/LCRR/<app>/    Lua actions + lib/ (arrange only; slice of REAPER's resource path; specs in spec/)
  www/lcrr-<app>.html           entry page (home: lcrr.html)
  www/lcrr/<app>/{css,js}/      its assets
scripts/                        install.ps1, serve.js, check.js, lua.js, build-release.js, release-lib.js (tests in test/)
dev/reaper-projects/            dummy REAPER projects for testing
```

Each `www/` folder holds files at the paths REAPER serves them from. Install, release and `npm run serve` lay them over each other.

## Development (devcontainer)

- The container has node, python3, curl, jq, lua5.4, busted and luacheck. No npm dependencies.
- `npm test` runs every test (scripts, shared, apps, plus busted for apps with Lua); `npm run check` syntax-checks every browser script and the scripts, and runs luacheck. Both fail outside the devcontainer if busted/luacheck are missing.
- `npm run serve` serves all slices on `http://localhost:8081/` (use VS Code port forwarding). REAPER runs on the Windows host and is not reachable from the container, so pages show their offline state there; test against REAPER with `install.ps1 -Link`.
- Do **not** publish port 8080 in `.devcontainer/docker-compose.yml` (see Troubleshooting).
- Work happens on the `dev` branch only.

### Dummy projects

`dev/reaper-projects/podium-dummy.rpp` has 5 regions (4 colored, plus an uncolored "Outro (no color)"; back-to-back), 3 markers (one unnamed, one colored) and one track. Hand-written: if REAPER complains or colors look off, fix in REAPER and re-save. REAPER's `Backups/` folder is git-ignored.

## Release (zip + ReaPack)

> **For now the suite is delivered only through `scripts\install.ps1` / `install.bat`.** The zip and ReaPack index below don't carry the Arrange Lua (its bridge and actions) or its `__startup.lua` line, so Arrange would not work from them. Delivery through them will be revisited.

```
npm test && npm run check
npm run release -- --base-url https://raw.githubusercontent.com/<user>/<repo>/<tag>
```

- Writes `dist/lcrr-<version>.zip` (git-ignored): every slice laid over each other plus `lcrr-INSTALL.txt`, to extract into `reaper_www_root` keeping folders. Needs the `zip` CLI. The version comes from the root `package.json`; there is one version for the suite.
- With `--base-url` (the repo root at a tag or commit) also writes `index.xml` at the repo root: one ReaPack `webinterface` package holding every file, with `file` attributes keeping the `lcrr/...` subfolders. Commit `index.xml`; users add its raw URL via Extensions > ReaPack > Import repositories. Not yet verified in a live ReaPack (see `CONTEXT.md`).
