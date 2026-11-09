# Podium

The stage page of the suite (`lcrr-podium.html`): a phone/tablet/desktop on the same trusted LAN gets a transport bar, a region list and a marker list. REAPER API facts it relies on are in the root `CONTEXT.md`; ADRs in `apps/podium/docs/adr/`.

## Behaviour decisions (not obvious from the code)

- Region/marker rows are not tappable; only the ▶ button on the left seeks and plays (prevents accidental starts while scrolling). Playback continues past the end of a region. While the transport runs, ▶ needs a 500 ms hold (a tap alone can't cut a song), the active region shows a now-playing indicator instead of ▶, and repeat taps within 1.5 s are ignored; see `docs/adr/0001-no-restart-from-active-row.md`.
- The header is one sticky row (state chip, region name, clock, Play/Stop slot, Rec) wrapped with the tab bar in `#podium-sticky`. Play and Stop share one slot: Stop while playing or recording, Play otherwise (paused shows Play so it can resume). Stop needs a 500 ms hold, like cue; a tap never stops (`docs/adr/0002`). Below 480 px the chip shows only its shape. Only input on the list (`<main>`) pauses autoscroll; the header, tabs and suite footer don't.
- Rec needs an 800 ms press-and-hold (`HOLD_MS`); a plain tap must never record.
- Region highlight: only while the transport is active (not when stopped), `start <= pos < end`, latest-starting region wins when regions overlap.
- Home is the shared sticky suite footer at the bottom, a plain-tap link (suite `docs/adr/0003`). Leaving the page doesn't touch REAPER's transport.
- Out of scope for v1: pause, prev/next, loop, queued playback, marker add/edit/delete, project selector.

## Code map

- `www/lcrr-podium.html`; `www/lcrr/podium/css/podium.css`; `www/lcrr/podium/js/core.js` (pure: `transportSlot`, `activeRegionId`, `formatTime`, `formatClock`; `LCRR.podium.core`); `www/lcrr/podium/js/podium.js` (UI wiring).
- Uses `LCRR.shared.reaper` (parsing, `seekPlayCommand`), `.poll`, `.guard` (offline verdict, cue cooldown), `.hold` (Rec, Stop, hold-to-cue).

## Still unverified

- Rec (`1013`, behaviour with no armed track) and the 800 ms hold time on a real touchscreen.
- Hold-to-cue (500 ms) and hold-to-stop on a real touchscreen, and the whole page in a real browser: the Nov 2026 UI passes (state chip, status strip, hold-to-cue, offline slot, copy) were checked only by unit tests, a stub-DOM smoke run and source review. No visual check, no phone check.
- The one-row bar on a ~360 px phone (region name room, chip without text), and contrast of the dim HOLD hint and row start times.
- The sticky suite footer on a phone: the 44 px strip it takes from the list, and that autoscroll's "centre the active row" still looks right above it.
- Open critique items: ▶ looks the same in tap and hold mode until pressed; state chip is small beside the clock; Rec-while-recording could read as a control; autoscroll pause also triggers from touches in the transport bar.
