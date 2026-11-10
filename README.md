# LiveCues ReaperRemote

[![CI](https://github.com/GiorgosKoulouris/livecues-reaper-remote/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/GiorgosKoulouris/livecues-reaper-remote/actions/workflows/ci.yml)
[![Latest release](https://img.shields.io/github/v/release/GiorgosKoulouris/livecues-reaper-remote?include_prereleases&label=release)](https://github.com/GiorgosKoulouris/livecues-reaper-remote/releases)
[![License: MIT](https://img.shields.io/github/license/GiorgosKoulouris/livecues-reaper-remote)](LICENSE)

Control REAPER from your phone, tablet or any browser on your network.

LiveCues ReaperRemote (LCRR) is a set of small web pages for live shows and rehearsals. Start cues from the stage, let each musician set their own in-ear mix, and rearrange a project's regions, all without walking over to the computer.

There's nothing to install on the phone: you just open a link. LCRR runs on REAPER's built-in web interface and doesn't need SWS.

> **Currently in beta.** LCRR is developed and tested on Windows. macOS and Linux are untested.

## The apps

Open the **Home** page and pick an app. It also shows whether REAPER is connected.

### On stage

**Podium: cues and transport.** For whoever runs the show. See the regions and markers of your project and start any of them from the list. Built so a stray touch can't disrupt the show: while the song is running, cueing and stopping need a press and hold, and so does Record at all times.
*Needs:* a project with regions or markers.

**Monitor: your own in-ear mix.** Each musician opens their mix on their own phone and sets the level of every source, with mute, solo and a master fader. Nothing is stored on the phone.
*Needs:* in-ear mixes in the project, which IEM Setup creates for you. By hand, a mix is a track named `IEM_<name>` with at least one receive and one hardware output.

### At the desk

**IEM Setup: create and route in-ear mixes.** Create, copy and rename mixes, choose which tracks feed each one, and pick its hardware output.
*Needs:* the startup hook (step 4 of the install).

**IEM Mix: balance every in-ear mix.** The engineer's view: a live grid of every source in every mix, plus a side panel with faders, pans and mutes. Listen to any mix through a cue track, and save and recall snapshots. The page opens locked, and one tap unlocks it.
*Needs:* in-ear mixes in the project. Listen and snapshots also rely on IEM Setup and the startup hook.

**Snapshots: save and restore the whole mix.** Save the project's mix under a name and bring it back with one press, playing or stopped: levels, pans, mutes, solos, polarity, sends and, if you tick them, FX on/off and the in-ears. Restore is one undo step. Tick what to restore, and hold a key to restore, overwrite or delete. Saving, overwriting and deleting can't be undone. Snapshots are stored in the project, so save the project to keep them.
*Needs:* the startup hook (step 4 of the install).

**Arrange: put project regions in a new order.** Describe the order you want, check what would happen, then apply it. Regions move with everything inside them: media, automation, markers and tempo. It changes your project, so try it on a copy first. The [Arrange guide](apps/arrange/README.md) explains how it works and what it won't do.
*Needs:* the startup hook, and a project with uniquely named regions.

## Install

You need REAPER and [ReaPack](https://reapack.com) on the computer, and your phone or tablet on the same network.

1. In REAPER, go to **Extensions > ReaPack > Import repositories...** and paste:

   ```
   https://raw.githubusercontent.com/GiorgosKoulouris/livecues-reaper-remote/main/index.xml
   ```

2. Turn on pre-releases, since LCRR is in beta: **Extensions > ReaPack > Manage repositories**, open the LCRR entry and enable **Show pre-releases** (or use the global option in ReaPack's options).
3. Go to **Extensions > ReaPack > Browse packages**, find **lcrr.html** and install it.
4. Open **Actions > Show action list**, run **LCRR: Install startup hook** once, then restart REAPER. This starts the background scripts that Arrange and IEM Setup rely on.
5. Go to **Preferences > Control/OSC/web > Add > Web browser interface**. Set a port (for example `8080`) and choose **lcrr.html** as the **Default interface**. Add a username and password if you want a login.
6. Allow REAPER through Windows Firewall for private networks.
7. On your phone, open `http://<pc-ip>:<port>/`. The **Access URL** in REAPER's web interface settings shows the address.

**Use LCRR on a network you trust, and don't expose it to the internet.** Anyone who can reach the page can control REAPER. See [SECURITY.md](SECURITY.md) for details and how to report a problem.

## Update

Go to **Extensions > ReaPack > Synchronize packages**, then restart REAPER so the background scripts run the new version. The installed version is shown at the right of the footer on every app page.

## Remove

1. Run the action **LCRR: Remove startup hook**.
2. Uninstall the **lcrr.html** package in ReaPack.

If you uninstall first, the leftover startup lines do nothing. You can still run the action beforehand, or delete the marked lines from `Scripts/__startup.lua` by hand.

## Install without ReaPack

If you can't use ReaPack, a script installs the same pages and scripts on Windows.

1. [Download the repository](https://github.com/GiorgosKoulouris/livecues-reaper-remote/archive/refs/heads/main.zip) and extract it.
2. Double-click `scripts\install.bat`. It installs into `%APPDATA%\REAPER` and shows the addresses to open.
3. Restart REAPER, then follow steps 5 to 7 of the [install](#install).

To use Arrange's actions from REAPER's action list as well as from its page, load them once: **Actions > Show action list > New action > Load ReaScript**, then select the `LCRR_Arrange_*.lua` files in `Scripts\LCRR\arrange\`.

- **Update:** download the repository again and re-run `install.bat`.
- **Remove:** from a command prompt in the `scripts` folder, run `install.bat -Uninstall`. Your own lines in `Scripts\__startup.lua` are kept.
- **Move to ReaPack:** remove the script install first, then follow the [install](#install). ReaPack doesn't take over files it didn't install.

For a portable REAPER or a custom web folder, see the install options in [CONTRIBUTING.md](CONTRIBUTING.md#installing-from-your-checkout).

## Troubleshooting

- **The page can't be reached from another device:** allow REAPER through Windows Firewall (private networks) and use the **Access URL** from REAPER's settings.
- **`lcrr.html` isn't in the Default interface list:** reopen the web interface dialog after installing. REAPER lists only `.html` files at the top level of its web folder.
- **The page loads with no styling or does nothing:** the `lcrr` folder is missing from `reaper_www_root`, next to the `lcrr*.html` pages. Reinstall.
- **Arrange or IEM Setup says it isn't running:** run **LCRR: Install startup hook** and restart REAPER.
- **`localhost:8080` shows `ERR_EMPTY_RESPONSE` although REAPER says the server is up:** another program is using that port. Run `netstat -ano | findstr :8080` to find it, or choose a different port.

Something else wrong? [Open an issue](https://github.com/GiorgosKoulouris/livecues-reaper-remote/issues).

## Contributing

Bug reports, ideas and code are welcome. [CONTRIBUTING.md](CONTRIBUTING.md) covers development setup, tests and how to send a change.

## License

[MIT](LICENSE). The bundled IBM Plex fonts are under the [SIL Open Font License 1.1](shared/www/lcrr/shared/fonts/OFL.txt).
