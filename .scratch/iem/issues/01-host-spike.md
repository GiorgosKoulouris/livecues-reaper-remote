# 01. Host spike: confirm the REAPER calls IEM Setup depends on

Status: resolved 2026-11-09
Blocked by: none

REAPER can't be reached from the container. Run a throwaway ReaScript on the host, on a scratch project, and record the results in the suite `CONTEXT.md`.

## How to run

The script is `.scratch/iem/spike/LCRR_IEM_Spike.lua`. It refuses any project that has tracks or has been saved, and removes its temporary files when it finishes.

Have ready: the audio device running, REAPER's web interface on with `lcrr-monitor.html` installed, and a phone or browser on it.

1. In VS Code, right-click the script and choose Download. Save it anywhere on Windows.
2. In REAPER, open a new, empty project tab (File > New project tab). Stay on this tab until the script finishes.
3. Actions > Show action list > New action > Load ReaScript, pick the file, then select it in the list and press Run.
4. Answer the prompts. Take in-ears out for the listening test. It asks which output to listen on, then whether you hear a -40 dBFS tone. For the phone test, each prompt says what to do after you press OK.
5. If you accept the last test, restart REAPER (no need to save) and run the script once more from the Action list. That run checks the startup and removes its startup line and helper script.
6. Close the test tab without saving, and remove the action from the list if you like.

## How to report

The results are in `%APPDATA%\REAPER\LCRR_IEM_Spike_Report.txt`, and are also printed in REAPER's console. Paste the whole file into the conversation, or save it as `.scratch/iem/spike/report.txt`. Lines are `PASS`, `FAIL`, `INFO` or `SKIP`, and a `FAIL` isn't necessarily a problem to fix on your side. `INFO` lines are measurements to read. The results then go into the suite `CONTEXT.md` and any corrections into the spec.

## To confirm

- Create a track at the end, name it, make it a folder and place children inside it.
- Create a track send and a hardware output; set send mode to post-FX pre-fader; read the mode back.
- Master send off on a child track and on the folder: no signal reaches the master.
- Mono hardware output from a stereo mix: left only or a downmix?
- Device channel names, including when the audio device is closed.
- Moving a folder and its children to the end of the track list.
- A second defer script alongside Arrange's bridge, both started from `__startup.lua`.
- Monitor open on a phone while sends on its mix are added and removed.

## Done when

Each item has a recorded result, and `.scratch/iem/spec.md` is corrected wherever one contradicts it.

## Comments

**2026-11-09, first run (REAPER 7.82, Windows, two outputs).** Measured facts are in the suite `CONTEXT.md` and the spec is corrected. Monitor passed every test: rows follow added and removed sends, a drag writes to the right send, a drag during removal doesn't touch another send, and a rename returns the phone to the list.

Two results need the retest, `spike/LCRR_IEM_Spike2.lua` (run it the same way, in a new empty tab; report `LCRR_IEM_Spike2_Report.txt`):

- `undo.track_gone` and `undo.send_gone` failed, but the state undo restored (8 tracks, a send on Src A) is exactly how `section_move` ended. Undo went back to REAPER's last snapshot, because the script's earlier changes were made outside undo blocks. A fault in the test, not evidence about undo.
- `listen.stereo.left_on_second` was "yes": a left-only tone was heard on output 2. Either the listening path sums the channels or the routing is off. Until that's known, `listen.mono_*` can't show whether a mono output is a true downmix.

**2026-11-09, retest (REAPER 7.82).** Both settled, facts in the suite `CONTEXT.md`.

- Undo: every step passed for adopt, create and delete, and one block is one step. `undo.create.send_gone` reported `FAIL 1`, but the test expected 0 while the baseline itself has one send on Src A, so 1 is the correct restored state. A fault in the test.
- Mono: with outputs told apart, a left-only tone stayed on output 1 on a stereo route, so the first run's "yes" came from the listening path. On a mono route, left and right both reached output 1 and neither reached output 2: a true downmix.
