# Home

The suite launcher, `lcrr.html`: the page users pick as REAPER's "Default interface". Context: `apps/home/CONTEXT.md`.

- `www/lcrr.html`: header (suite name, connection chip) and one hard-coded link button per app. Add a button here when an app is added.
- `www/lcrr/home/js/status.js`: pure chip verdict (`LCRR.home.status`), tested in `test/`. `home.js`: wiring to the shared poller and guard.
- `www/lcrr/home/css/home.css`: page styles on top of the shared tokens and base CSS.
- No suite footer on this page (it would only hold a Home link to itself).
