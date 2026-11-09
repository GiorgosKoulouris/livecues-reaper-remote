# Home

Launcher for the suite. Served by REAPER like every other app; intended as the "Default interface", so `http://<pc-ip>:<port>/` opens it.

## Behaviour decisions

- Shows one button per app (Podium, Arrange; hard-coded in `lcrr.html`, no manifest) and a connection chip. Nothing else: no transport state, no project info.
- The chip polls `TRANSPORT` every 2 s through the shared poller. States: "Connecting…" until the first reply, "REAPER connected" (Paper White, filled disc), "REAPER unreachable" (Warn Amber, ring) after the shared guard's 2 failed polls. One missed poll keeps the current chip.
- Connected is Paper White, not green: green is reserved for "playing" (DESIGN.md, State-Only Color Rule).
- No suite footer here.
