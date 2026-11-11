# Changelog

## 1.1.1 (2026-11-11)

- Snapshots: save, overwrite and delete work again. The bridge now handles one call at a time
- Snapshots: hold keys fill the whole key, and text selection and the touch callout are blocked during a hold
- IEM Mix and IEM Setup: a quiet key in each bar links to the other page
- IEM Setup: the grid keeps its scroll position after a write
- IEM Setup: a narrower grid with an Outputs row, a shorter More menu, a crosshair on the grid, and the cue track follows the shared colour
- IEM Setup: clearer wording in the Add mix panel
- README: install, update and remove steps for both ReaPack and script installs; the startup hook actions are described correctly

## 1.1.0 (2026-11-10)

- First stable release. LCRR installs and updates through ReaPack: import the index, install the lcrr.html package, run LCRR: Install startup hook once
- Snapshots: save the project's mix under a name and restore it with one press (levels, pans, mutes, solos, polarity, sends and, if ticked, FX on/off and the in-ears), with an undo step for the restore
- Home groups the apps into Stage, Desk and Utilities
- The suite footer shows the installed version
- LCRR: Remove startup hook removes the startup lines again; install.ps1 -Uninstall and a re-install match the same lines by bridge id
- The Install script defaults to port 80, so the address needs no port number
- The IBM Plex license text ships with the fonts
