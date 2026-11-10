---
name: LiveCues ReaperRemote
description: A flat dark control panel with silkscreen legends and one signal orange, for running REAPER from a phone; shared by every LCRR app.
colors:
  chassis: "#191a17"
  bar: "#141512"
  display: "#0c0d0b"
  key: "#282a25"
  key-hover: "#343630"
  edge: "#3a3c34"
  line: "#2d2e29"
  active-wash: "#22241f"
  legend: "#dcdbcd"
  legend-dim: "#8d8c80"
  signal: "#ff6a1a"
  signal-ink: "#1c0b00"
  led-green: "#79e08a"
  led-red: "#ff4a3a"
  warn-amber: "#e0a030"
  warn-umber: "#5a3d0c"
  warn-edge: "#8a5d14"
  warn-cream: "#ffd48a"
typography:
  body:
    fontFamily: "IBM Plex Sans, system-ui, sans-serif"
    fontSize: "16px"
    fontWeight: 500
    lineHeight: 1.4
  title:
    fontFamily: "IBM Plex Sans, system-ui, sans-serif"
    fontSize: "1.25rem"
    fontWeight: 600
    lineHeight: 1.25
  legend:
    fontFamily: "IBM Plex Sans, system-ui, sans-serif"
    fontSize: "0.72rem"
    fontWeight: 600
    lineHeight: 1
    letterSpacing: "0.12em"
  key-label:
    fontFamily: "IBM Plex Sans, system-ui, sans-serif"
    fontSize: "1.2rem"
    fontWeight: 700
    lineHeight: 1.25
    letterSpacing: "0.06em"
  readout:
    fontFamily: "IBM Plex Mono, ui-monospace, Consolas, monospace"
    fontSize: "1.05rem"
    fontWeight: 500
    lineHeight: 1.2
    fontFeature: "tnum"
  numeric:
    fontFamily: "IBM Plex Mono, ui-monospace, Consolas, monospace"
    fontSize: "0.8rem"
    fontWeight: 400
    lineHeight: 1.4
    fontFeature: "tnum"
rounded:
  none: "0"
  led: "50%"
spacing:
  xs: "0.25rem"
  sm: "0.5rem"
  md: "0.75rem"
  lg: "1rem"
components:
  key:
    backgroundColor: "{colors.key}"
    textColor: "{colors.legend}"
    rounded: "{rounded.none}"
    size: "44px"
  key-lit:
    backgroundColor: "{colors.signal}"
    textColor: "{colors.signal-ink}"
    rounded: "{rounded.none}"
  readout:
    backgroundColor: "{colors.display}"
    textColor: "{colors.signal}"
    typography: "{typography.readout}"
    padding: "0.25rem 0.5rem"
  bar:
    backgroundColor: "{colors.bar}"
    textColor: "{colors.legend}"
    padding: "0.5rem 1rem"
  row-active:
    backgroundColor: "{colors.active-wash}"
    textColor: "{colors.legend}"
  fader:
    backgroundColor: "{colors.display}"
    textColor: "{colors.legend}"
    rounded: "{rounded.none}"
    height: "44px"
  fader-fill:
    backgroundColor: "{colors.key-hover}"
  offline-banner:
    backgroundColor: "{colors.signal}"
    textColor: "{colors.signal-ink}"
    padding: "0.375rem 1rem"
  panel:
    backgroundColor: "{colors.display}"
    textColor: "{colors.legend}"
    rounded: "{rounded.none}"
    padding: "1rem"
---

# Design System: LiveCues ReaperRemote

One design system for the whole suite. Tokens and the self-hosted fonts live in `shared/www/lcrr/shared/css/tokens.css`, base styles and the suite footer in `base.css`; each app adds only its own components. The component sections below describe Podium (the first app) unless headed otherwise; the Suite footer and Home sections apply suite-wide, and Monitor, Arrange, IEM Setup and IEM Mix have their own sections.

## Overview

**Creative North Star: "The Silkscreen Desk"**

A flat panel on a backstage desk. The chassis is a warm near-black; keys are matte with a chamfered corner; legends are printed in small spaced capitals; readouts sit in recessed black slots; LEDs report state. It stays quiet until something is live, then one signal orange (and a few LEDs) speak. It must be readable at arm's length in a dark room, and it should look like an instrument, not like a web app.

Color is not decoration: orange marks selection and the one lit action, and green, red and amber are LEDs that carry state.

Rejected: gloss, bevels and shaded knobs (the desk is flat), gradients, rounded "friendly" corners, a blue accent, system-ui as the voice.

**Key Characteristics:**
- Dark-only (`color-scheme: dark`); no light theme.
- Flat, tonal depth with 1px lines and edges; no shadows. The only glow is a 6px halo on a lit LED.
- Square corners everywhere, except keys, which have one chamfered corner (top right, 8px; 12px on Home's app keys).
- One signal orange for selection, focus and the lit action; green, red and amber reserved for state.
- Large touch targets (44px minimum).
- IBM Plex Sans for legends and names, IBM Plex Mono for readouts and numbers, both self-hosted.

## Colors

A warm near-black chassis with three tonal steps (bar, display, key), one signal orange and three LED hues.

### Primary
- **Signal** (#ff6a1a): the selected-tab underline, the active row's edge, keyboard focus rings, the project-time readout while the transport runs, the one lit action key (Apply, Check this Arrangement, Solo on, the active cue's key), a fader handle while it is being dragged, drop-position edges in Arrange's reorder list, and the offline banner's fill. **Signal Ink** (#1c0b00) is the text on any Signal fill.

### Secondary (LEDs)
- **LED Green** (#79e08a): playing, and the "connected" LED on every bar.
- **LED Red** (#ff4a3a): recording, a muted source, the Rec key's symbol and the press-and-hold fill (at 55% opacity).
- **Warn Amber** (#e0a030): REAPER offline or the bridge down, a fader handle and value pushed past 0, and Arrange's refusal and missing-region flags.

### Neutral
- **Chassis** (#191a17): page background.
- **Bar** (#141512): sticky bars and the footer.
- **Display** (#0c0d0b): recessed slots: readouts, faders, fields, result panels, rows in Arrange's editor.
- **Key** (#282a25) and **Key Hover** (#343630): key faces, and the fader fill.
- **Edge** (#3a3c34): borders of recessed slots and fields. **Line** (#2d2e29): list dividers and bar underlines.
- **Active Wash** (#22241f): the active region row, and Arrange's busy strip (with a Signal bottom edge).
- **Legend** (#dcdbcd): all primary text. **Legend Dim** (#8d8c80): secondary text and unselected tabs.
- **Warn Umber / Warn Edge / Warn Cream** (#5a3d0c / #8a5d14 / #ffd48a): Monitor's setup notice.

### Named Rules
**The Lit-Key Rule.** At most one key per view is filled with Signal: the forward action, or the thing that is currently on. Orange is never a resting fill for ordinary buttons or a link color.

**The LED Rule.** Green, red and amber appear only to report state: transport, connection, a solo that is on, a muted source, a level past 0, a refused or missing item. Every LED has a shape or a word beside it, so color is never the only signal.

**The Dark Room Rule.** Text stays at #dcdbcd on #191a17 (not pure white on black) to limit glare; secondary text uses Legend Dim or opacity (0.6), not new greys.

## Typography

**Display and Body Font:** IBM Plex Sans (500, 600, 700), self-hosted woff2, with `system-ui, sans-serif` as the fallback.
**Mono Font:** IBM Plex Mono (400, 500), self-hosted, with `ui-monospace, Consolas` as the fallback.

**Character:** Plain, engineered letterforms with clear numerals, like the print on a mixing desk: legible first, with the personality left to the panel. Fonts ship inside the web root because the stage LAN has no internet.

### Hierarchy
- **Body** (500, 16px, 1.4; 18px at ≥900px width): default text, names, buttons.
- **Title** (600, 1.25rem, 1.25): page and mix titles in the bars.
- **Legend** (600, 0.72rem, +0.12em, uppercase): everything printed on the panel: state words, tab labels, section labels, field labels, the Home link, banner text (700).
- **Key label** (700, 1.2rem, +0.06em, uppercase): app names on Home's keys.
- **Readout** (IBM Plex Mono 500, 1.05rem, tabular): the project-time clock in Podium, in a recessed Display slot.
- **Numeric** (IBM Plex Mono 400, 0.8–0.85rem, tabular): list start times, fader values, paths, the busy strip.
- Row and region names are body size (1rem), 700 when active. The active region's name appears on the status line, not as a large headline.
- Podium's page title "Podium" is an h1 kept for screen readers only.

### Named Rules
**The Tabular Time Rule.** Any time or level value uses tabular numerals so digits do not jitter while the clock runs. Fader values show the number only, with no unit on screen (the unit is in the accessible name).

## Layout

A single column, capped at 48rem (72rem for Arrange's desk layout; IEM Setup's grid uses the whole screen). Lists have rows separated by lines, not cards.

**Podium's bar is compact on purpose**, because a project can have many regions and markers. It is a two-row grid, about 80px in total, sticky above a two-tab strip:
1. **Clock and keys:** the project-time readout at left, Stop-or-Play and Rec at right, symbols only (no text on the keys).
2. **State and region:** the state shape and word, then the region name (flexible, truncating) on one line.
3. **Banner slot:** overlays the top of the list just under the tabs, so nothing shifts when it appears.

Prev and Next are not part of the transport. When the region changes, the list scrolls the active row to the middle, unless the user scrolled or typed in the last 3 s. Page padding is 1rem, 0.5rem on narrow phones.

Spacing scale in use: 0.25rem, 0.5rem, 0.75rem, 1rem.

## Elevation & Depth

Flat. There are no shadows. Depth is conveyed by tone: Chassis → Bar, Key, and the recessed Display slots with an Edge border. Bars are sticky (z-index 10) and separated by a Line.

### Named Rules
**The Flat-Always Rule.** No box-shadows for elevation, no blur, no gradients. The only exceptions: a sunk (muted) key uses an inset 2px outline, and a lit LED has a 6px halo.

## Shapes

Square by default. **Keys** (every button that acts) have one chamfered corner, top right, 8px (12px on Home's app keys), cut with `clip-path` and a 44px minimum size. Slots (readouts, faders, fields, panels) are square with a 1px Edge. LEDs and the Podium region swatch: LEDs are discs; the swatch is a small square. Tabs have no chamfer: a 3px bottom indicator in Signal. Keyboard focus is a 2px Signal ring drawn inside the key (offset −4px) so the chamfer does not clip it.

## Components

### Keys
- **Transport (Stop-or-Play, Rec):** 44×44px Key face, symbol only: a play triangle, a stop square, a record disc (LED Red). Stop and Rec carry a small bar under the symbol: hold, don't tap. Disabled is 40% opacity.
- **Rec recording:** the key is sunk (Chassis face, inset 2px LED Red outline) with the disc in LED Red at full opacity. It is still disabled, but must not look offline-dim.
- **Cue (▶):** 44×44px Key, a drawn triangle, at the left of each row; the only element in a row that acts. Stopped: one tap. While the transport runs: hold 500 ms (Legend sweep at 40%, same mechanism as Rec). Repeat taps within 1.5 s are ignored and the pressed key shows a pending (inverted, 55% opacity) state.
- **Pressed:** every key inverts (Legend face, Chassis text) on `:active`; Rec, Stop and hold-mode ▶ show their sweep instead.
- **Hold:** an LED Red fill sweeps left to right over the hold duration (800 ms for Rec, 500 ms for Stop) and then triggers; releasing early cancels. The key blocks text selection, touch callouts and scroll gestures.
- **Lit key:** Signal face, Signal Ink text, 700 weight (see the Lit-Key Rule).

### Tabs
- **Style:** equal-width, borderless, min 44px tall, Legend text in Legend Dim.
- **Active:** Legend text and a 3px Signal bottom border; inactive has a transparent 3px border so nothing shifts.

### List rows
- **Style:** flex row with 0.625rem gap, 0.25rem vertical padding, Line bottom border; cue key, optional square swatch, name (truncated), then start time in IBM Plex Mono.
- **Active region:** Active Wash background, a 3px Signal edge on the left, the name at 700, and a drawn three-bar now-playing indicator in place of the ▶ (LED Green while playing, LED Red while recording, Legend at 70% when paused). Only while the transport is active. Dimmed to 40% while offline.

### Offline banner
- A Signal strip in Signal Ink legend caps ("REAPER is unreachable. Showing the last known state. Retrying…"), `role="alert"`. Offline needs 2 consecutive failed polls. The state word turns Warn Amber, the clock and active row dim, and ▶ re-enables 1.5 s after reconnect.

### State LED
- Leftmost item of the status line: a drawn shape and the uppercase state word. Shapes: square = stopped, triangle = playing, disc = recording, two bars = paused, ring = offline or connecting. The shape is LED Green (playing), LED Red (recording) or Legend Dim; the word turns Warn Amber when offline. Shape and word mean colour is never the only signal.

### Loading, empty and error copy
- First load never claims a state it hasn't seen: the state reads "CONNECTING…" (ring shape, 70%), the region slot "Connecting to REAPER…", the clock "–:––", and each list "Loading regions…" / "Loading markers…" (`aria-busy` until data arrives). If REAPER never answers, the lists and region slot say it can't be reached instead of loading forever.
- Empty lists say what it means and what to do ("No regions in this project. Regions you add in REAPER will appear here.").
- A reply without a region list gets one plain sentence; REAPER's raw reply sits in a collapsed "Show REAPER's reply" `<details>` (IBM Plex Mono, for bug reports only).
- Unnamed rows are "Region N" / "Marker N" (N = REAPER's number), in the row, the cue key's accessible name and the status line.

### Project clock
- Project time as m:ss (whole seconds; h:mm:ss from one hour) in IBM Plex Mono on a Display slot with an Edge border. Signal while playing or recording, Legend Dim otherwise, 40% opacity while offline.

### Suite footer (every app except Home)
- Sticky at the bottom of every app page, 44px tall, on Bar with a Line top border, content capped at 48rem like the lists. It sits at the bottom of short pages and sticks there on long ones (the page is a flex column; `<main>` grows).
- Holds only **Home**: a drawn house glyph plus the legend "Home", left-aligned, 44px tap target, plain tap (navigation, not a transport action). Legend Dim; Signal while pressed; focus ring Signal.
- Never put transport or other actions in it. See `docs/adr/0003`.

### Monitor (`lcrr-monitor.html`)
- **Bar:** sticky Bar, 3rem minimum: a 1.25rem / 600 title (with a 44px back key beside it once a mix is open), and a connection state in the Home language (LED Green disc = connected, ring = connecting or offline, Warn Amber when offline). A Signal banner strip sits under it.
- **Mix list:** Line-separated rows, 56px minimum, 1.1rem name truncated, optional 0.85rem note at 70%. The whole row is the button; pressed inverts. A mix already taken by someone else is dimmed to 60% with a not-allowed cursor.
- **Fader:** a plain 44px slot (Display, 1px Edge, no scale or ruler) holding a Key Hover fill up to the handle, the source name left and a IBM Plex Mono value right. A 2px Legend mark at 45% shows 0 dB. The 10px Legend handle is the only thing that takes touches (an invisible 44px thumb around it), so scrolling past a row never moves a level. Text over the handle flips to Chassis. The handle turns Warn Amber above 0 dB and Signal while dragging. A track colour tints the fill at 25% so text stays above 4.5:1.
- **Rows:** 48px high, 6px gap: fader, then Solo and Mute 44px keys, each with a small LED above the letter. Mute on = sunk: Chassis face, 2px LED Red outline, red letter and a lit red LED; Solo on = the Lit Key (Signal face, Signal Ink letter). A muted row's fill and mark drop to 45% and its text to 80% (4.5:1 or better on any track colour). Master is the first row, 600 weight, with a Line under it; its right padding (100px) keeps its 0 dB mark aligned with the faders below.
- **Wide:** from 640px the master and sources fill two columns with a 1rem column gap.
- **Offline:** the mixer dims to 60%.

### Arrange (`lcrr-arrange.html`)
- **Bar and state:** same sticky Bar and state LED as Monitor (disc = running, ring = connecting, amber ring = offline or bridge down); a Signal banner strip and an Active Wash busy strip (IBM Plex Mono, Signal bottom edge) sit under it.
- **Sections:** Line-topped blocks under a 1.1rem heading; legend-style labels; selects and text inputs are 44px, Display with a 1px Edge, Signal focus ring; text inputs use IBM Plex Mono.
- **Keys:** the same 44px keys. The one forward action in a view (Apply, Verify after Apply, Check this Arrangement, a confirming answer) is the only lit key. A destructive answer (Delete) is never lit; the safe answer is, and holds the focus. A quiet action is borderless and underlined. Other keys invert when pressed.
- **Results:** sits directly under Check and Verify, and on arrival is scrolled into view with its title focused (unless the user is typing in a field). A Display panel with an Edge border (Warn Edge when it reports a problem), a 1.1rem / 600 title, and a verdict line led by a drawn mark (✓ in LED Green, or ✕ in Warn Amber). Findings are grouped under legend titles (Warn Amber for refusals) and tables use IBM Plex Mono with Line rows.
- **Desk layout:** from 64rem wide the page widens to 72rem and the Run tab becomes two columns: the controls on the left (18–24rem), the result on the right, sticky below the bar. Phones keep the single column.
- **Resulting order:** a ready Check lists "Region order after Apply" (numbered, from the Arrangement the page just re-read) and, in 60% text, the parked regions. No positions or times are shown; only REAPER can compute them.
- **Run / Edit tabs:** the same tabs as Podium: Legend Dim, selected in Legend with a 3px Signal underline.
- **Region editor:** rows in Display slots with an Edge border: a 44px drag handle key (grab cursor), name, a small amber flag when a region is missing, the Headroom control (−1 s, a IBM Plex Mono field with a trailing "s", +1 s) and 44px keys for move and remove. While dragging, the row dims to 50% and a 3px Signal edge marks where it will drop.

### IEM Setup (`lcrr-iem.html`)
- **Built for a laptop or tablet** (768px and wider), not a phone: the page is the full screen width, and the grid scrolls inside its own bordered Display box so its row and column headers stay put on both axes.
- **Bar and state:** the same sticky Bar, state LED and Signal banner strip as Arrange ("IEM Setup not running" in Warn Amber when the bridge is down). The bar sits above the grid's headers.
- **Grid:** columns are mixes, rows are every non-IEM track in project order, each name indented 1.25rem per folder level (folders in 700 weight). Row and column headers are Bar faces with Line gridlines, sticky. Cells are 44px high. A mix header shows its name (600), its output in IBM Plex Mono (Warn Amber when there is none, "No output") and small Warn Umber flags for a stray mix, a duplicate name or several outputs.
- **ON cell:** a Key face holding the send level in IBM Plex Mono, dB with one decimal and no unit, read-only. A muted send keeps its face but the figure drops to Legend Dim and is struck through in LED Red. OFF cells are empty Display.
- **Cell tags:** two small Warn Edge boxes in the corner of a cell's content: POST or PRE when the send is not post-FX pre-fader (with a tooltip saying so), and 2x (Warn Umber fill) when a folder and its child both feed the mix. Each also has a screen-reader sentence in the cell.
- **Filter:** a 44px text field, IBM Plex Mono, Signal focus ring.

### IEM Mix (`lcrr-iemmix.html`)
- **Built for a laptop or tablet** (768px and wider): the same full-width page, grid and cells as IEM Setup, with a docked panel beside the grid. Below 768px the panel stacks under the grid; that is not a designed phone layout.
- **Selection:** the selected source has a 3px Signal edge on the left of its row header, the selected mix a 3px Signal edge along the bottom of its column header (the active row's edge and the tab's underline). A source name or a mix name is a 44px target (the whole header cell) with the text unchanged; a cell tap only highlights its row in the panel.
- **Lock:** a Key in the bar, chamfered, opening as "Unlock"; unlocked it is the Lit Key reading "Lock". Focus ring inside the key (offset −4px). While locked the panel's faders dim to 60%, pan and mute are disabled, and a line in the panel says the page is locked, or why it stayed or went locked.
- **Panel:** a Display box with an Edge border, 22rem wide and sticky beside the grid, titled with the source or mix. A source row is one line at 768px: the Monitor fader, a 6.5rem pan control and a 44px Mute key. The master row of a mix is level only, first in the list. A repeated pair or a duplicated mix is a static row with its level and a short note, no controls. A tapped cell's row has a Signal border on a Key face.
- **Pan control:** a 44px Display slot with an Edge border, a centre mark like the fader's 0 dB mark, a 10px Legend handle (Signal while dragging) and a small IBM Plex Mono readout at top left ("C", "L25", "R100"). The handle is the only thing that takes touches: a 28px thumb for its travel, widened to a 44px hit area that stops short of the neighbouring controls, so scrolling past a row never moves a pan.
- **Mute:** as Monitor's (sunk with a 2px LED Red outline when on), disabled at 40% while locked or offline.
- **Snapshots:** a section below the panel's faders, set off by an Edge rule. A name field with a chamfered Key reading "Save", then one Display row per snapshot: name, a small Legend Dim line ("4 mixes, 7 sends · Nov 10 14:32") and the Keys Recall all, Recall <mix> (only while a mix is selected, named by its short name), Overwrite and Delete, all press-and-hold: a Warn Amber fill runs across the key for 1 s (reduced motion: it fades in instead). With the bridge not running the section is one line saying why, and nothing else.

### Home page
- Sticky Bar: the suite name ("LiveCues" in Legend, "ReaperRemote" in Signal; the second word hidden below 480px) and a connection state on the right.
- **Connection state:** the same drawn shape and word as the other bars. Connected = LED Green disc ("REAPER connected"); unreachable = Warn Amber ring ("REAPER unreachable"); connecting = ring at 70%.
- **App keys:** Key faces with the larger 12px chamfer, min 5rem tall: the app name in key-label caps, a 2–3 word description in Legend Dim ("Cues and transport", "In ear mixes", "Reorder project regions", "Create and route in ear mixes"), and a Signal triangle at the right. Grid that fills columns of at least 16rem (one column on phones). Pressed inverts.

## Do's and Don'ts

### Do:
- **Do** keep every touch target at least 44px.
- **Do** keep the project clock small and the transport symbols-only, so the list gets the screen.
- **Do** reserve green, red and amber for state, and Signal for selection, focus, drags in progress and the one lit key.
- **Do** keep sliders safe to scroll past: only a small handle area takes touches.
- **Do** keep faders plain (slot, fill, handle, one 0 dB mark).
- **Do** convey depth with tone and edges.
- **Do** use tabular numerals for all time and level values.
- **Do** keep text at #dcdbcd on #191a17 or darker surfaces; verify at least 4.5:1 contrast for any new text color.

### Don't:
- **Don't** make list rows tappable; only the ▶ key acts.
- **Don't** add shadows, gradients, bevels or glossy skeuomorphic controls.
- **Don't** round corners; chamfer keys, square everything else.
- **Don't** add Prev or Next to the transport, or text labels to its keys.
- **Don't** add a light theme or bright white surfaces; they glare on a dark stage.
- **Don't** use color alone to convey state; keep the shape or word beside it.
- **Don't** use new accent hues for decoration, or load fonts from the internet.
