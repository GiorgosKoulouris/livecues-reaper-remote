# Home

Launcher for the suite. Served by REAPER like every other app; intended as the "Default interface", so `http://<pc-ip>:<port>/` opens it.

## Behaviour decisions

- Shows one button per app (Podium, Monitor, Arrange, IEM Setup, IEM Mix; hard-coded in `lcrr.html`, no manifest) and a connection chip. Nothing else: no transport state, no project info.
- The chip polls `TRANSPORT` every 2 s through the shared poller. States: "Connecting…" until the first reply, "REAPER connected" (LED Green, filled disc), "REAPER unreachable" (Warn Amber, ring) after the shared guard's 2 failed polls. One missed poll keeps the current chip.
- Connected is the LED Green disc, the same LED as "playing" on the other bars; green only ever reports state (DESIGN.md, LED Rule).
- No suite footer here.
