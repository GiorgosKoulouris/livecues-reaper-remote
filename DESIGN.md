---
name: LiveCues ReaperRemote
description: A dim, flat, tonal control surface for running REAPER from a phone; shared by every LCRR app.
colors:
  stage-black: "#16181b"
  console-grey: "#1e2125"
  key-grey: "#2a2e33"
  key-grey-hover: "#3a3f46"
  hairline: "#2b2f34"
  cue-blue-wash: "#245382"
  paper-white: "#e8e8e8"
  cue-blue: "#4aa3ff"
  live-green: "#5ad77a"
  rec-red: "#ff5a5a"
  warn-amber: "#e0a030"
  warn-umber: "#5a3d0c"
  warn-edge: "#8a5d14"
  warn-cream: "#ffd48a"
typography:
  body:
    fontFamily: "system-ui, sans-serif"
    fontSize: "16px"
    fontWeight: 400
    lineHeight: 1.4
  title:
    fontFamily: "system-ui, sans-serif"
    fontSize: "1.1rem"
    fontWeight: 400
    lineHeight: 1.4
  label:
    fontFamily: "system-ui, sans-serif"
    fontSize: "0.875rem"
    fontWeight: 600
    lineHeight: 1
    letterSpacing: "0.06em"
  now-playing:
    fontFamily: "system-ui, sans-serif"
    fontSize: "1.25rem"
    fontWeight: 600
    lineHeight: 1.25
  clock:
    fontFamily: "system-ui, sans-serif"
    fontSize: "1.75rem"
    fontWeight: 600
    lineHeight: 1
    fontFeature: "tnum"
  numeric:
    fontFamily: "system-ui, sans-serif"
    fontSize: "0.85rem"
    fontWeight: 400
    lineHeight: 1.4
    fontFeature: "tnum"
rounded:
  control: "6px"
  swatch: "50%"
spacing:
  xs: "0.25rem"
  sm: "0.5rem"
  md: "0.75rem"
  lg: "1rem"
components:
  transport-button:
    backgroundColor: "{colors.key-grey}"
    textColor: "{colors.paper-white}"
    rounded: "{rounded.control}"
    padding: "0.5rem 1rem"
    height: "44px"
  cue-button:
    backgroundColor: "{colors.key-grey}"
    textColor: "{colors.paper-white}"
    rounded: "{rounded.control}"
    size: "48px"
  row-active:
    backgroundColor: "{colors.cue-blue-wash}"
    textColor: "{colors.paper-white}"
  transport-bar:
    backgroundColor: "{colors.console-grey}"
    textColor: "{colors.paper-white}"
    padding: "0.5rem 1rem"
  offline-banner:
    backgroundColor: "{colors.warn-umber}"
    textColor: "{colors.warn-cream}"
    padding: "0.6rem 1rem"
---

# Design System: LiveCues ReaperRemote

One design system for the whole suite. Tokens live in `shared/www/lcrr/shared/css/tokens.css`, base styles and the suite footer in `base.css`; each app adds only its own components. Most component sections below describe Podium (the first app); the Suite footer and Home sections apply suite-wide.

## Overview

**Creative North Star: "The Stage Console"**

A dim, utilitarian backstage control surface. It stays quiet until something is live, then the state color speaks. Everything is flat charcoal with hairline dividers; the interface should never compete with the show for attention, and it must be readable at arm's length in a dark room.

The mood is calm, functional and low-glare. Controls are plain and unmistakable rather than styled. Color is not decoration: it carries state (playing, recording, offline) and the single current-region highlight, and nothing else.

Rejected: neon DAW skeuomorphism, glossy faders and knobs, decorative gradients.

**Key Characteristics:**
- Dark-only (`color-scheme: dark`); no light theme.
- Flat, tonal depth with 1px hairlines; no shadows.
- One cool accent (blue) for selection; green, red and amber reserved for state.
- Large touch targets (44px minimum, 48px for the ▶ cue button).
- System font stack, tabular numerals for time.

## Colors

A near-black charcoal ground with two tonal lifts, one blue selection accent and three status hues.

### Primary
- **Cue Blue** (#4aa3ff): the selected-tab underline only. Its rarity is the point.

### Secondary
- **Live Green** (#5ad77a): transport state text while playing.
- **Rec Red** (#ff5a5a): transport state text while recording, and the press-and-hold fill on the Rec button (at 55% opacity).
- **Warn Amber** (#e0a030): transport state text when REAPER is offline.

### Neutral
- **Stage Black** (#16181b): page background.
- **Console Grey** (#1e2125): the sticky transport bar.
- **Key Grey** (#2a2e33): button faces (transport and ▶ cue buttons).
- **Hairline** (#2b2f34): all borders and list dividers.
- **Cue Blue Wash** (#245382): background of the active (currently playing) region row. No edge bar; the now-playing indicator and a 600-weight name mark it.
- **Paper White** (#e8e8e8): all text.
- **Warn Umber / Warn Edge / Warn Cream** (#5a3d0c / #8a5d14 / #ffd48a): the offline banner's background, bottom border and text.

### Named Rules
**The State-Only Color Rule.** Green, red and amber appear only to report transport or connection state. They are never used for decoration or branding.

**The Lone Accent Rule.** Cue Blue marks selection (the active tab). It is not a button fill or a link color.

**The Dark Room Rule.** Text stays at #e8e8e8 on #16181b (not pure white on black) to limit glare; dimmer secondary text uses opacity (0.6), not a new grey.

## Typography

**Display Font:** none
**Body Font:** system-ui (with generic sans-serif fallback)
**Label/Mono Font:** same family; numerals use tabular figures

**Character:** The platform's own UI face: neutral, instantly legible, zero loading cost. Hierarchy comes from size, case and opacity rather than from font choice.

### Hierarchy
- **Body** (400, 16px, 1.4; 18px at ≥900px width): default text, buttons and tabs.
- **Title** (400, 1.1rem, 1.4): region and marker names; single line, truncated with an ellipsis.
- **Label** (600, 0.875rem, +0.06em, uppercase): the state word inside the state chip; 0.8rem on narrow phones. Hint labels (HOLD under Rec) are 0.7rem, +0.1em, uppercase, 70% opacity.
- **Now playing** (600, 1.25rem, 1.25): the current region name in the status strip. One step above the row Title so it leads the page; single line, truncated.
- **Clock** (600, 1.75rem, tabular): the transport time as m:ss (whole seconds; h:mm:ss from one hour).
- **Numeric** (400, 0.85rem, tabular, 60% opacity): start time on list rows. The transport clock is body size, tabular.
- Podium's page title "Podium" is an h1 kept for screen readers only; the status strip's region name takes its place visually.
- Stop is 1.125rem / 600; Play and Rec are body size.

### Named Rules
**The Tabular Time Rule.** Any time value uses tabular numerals so digits do not jitter while the clock runs.

## Layout

A single column. A sticky transport bar sits on top, followed by a two-tab strip (Regions, Markers), then a centered list capped at 48rem. Lists have rows separated by hairlines, not cards.

The transport bar is a now-playing display first and a control row second, capped at 48rem so it lines up with the list. Top to bottom:
1. **Status strip** (grid): state chip, region name (flexible, truncating), clock. At ≤480px the region name drops to its own full-width row under the chip and clock.
2. **Controls row**: Stop (largest, flex 2, 56px, leads), Play (flex 1, 48px), then Rec set apart by a hairline and extra space, with its HOLD label under it.
3. **Banner slot**: always present, so going offline never moves anything. Empty when online.

Gaps are 0.625rem between the bars rows, 0.5rem at ≤480px. When the region changes, the list scrolls the active row to the middle, unless the user scrolled or typed in the last 3 s. Page padding is 1rem, 0.5rem on narrow phones. At ≥900px the base font rises to 18px.

Spacing scale in use: 0.25rem, 0.5rem, 0.75rem, 1rem.

## Elevation & Depth

Flat. There are no shadows. Depth is conveyed by tonal steps (Stage Black → Console Grey → Key Grey) and 1px Hairline borders. The transport bar is sticky above the content (z-index 10) and separated by a bottom hairline only.

### Named Rules
**The Flat-Always Rule.** No box-shadows, no blur. If a control must stand out, change its tone or border, not its elevation.

## Shapes

Mostly rectangular and square-cornered. Buttons use a gentle 6px radius with a 1px Hairline border. The region color swatch is a 1rem circle with a hairline outline when no color is set. Tabs are borderless with a 3px bottom indicator. Rows have no radius, except the active row, which has the same 6px radius as buttons.

## Components

### Buttons
- **Shape:** gently rounded (6px), 1px Hairline border.
- **Transport (Stop, Play, Rec):** Key Grey face, Paper White text, min 48px tall, padding 0.5rem 1rem. Disabled state is 40% opacity. **Stop** is the largest (56px, 600 weight, a drawn square glyph before the label). **Rec** sits behind a hairline, with a visible HOLD label (`aria-describedby` points at it, with a longer screen-reader sentence).
- **Rec recording:** while recording, the button reads "● REC" in Rec Red with a Rec Red border at full opacity. It is still disabled, but must not look offline-dim.
- **Cue (▶):** 48×48px Key Grey square button at the left of each row; the only element in a row that acts. Stopped: one tap. While the transport runs: hold 500 ms (Paper White sweep at 40%, same mechanism as Rec). Repeat taps within 1.5 s are ignored and the pressed button shows a pending (inverted, 55% opacity) state.
- **Pressed:** every button inverts (Paper White face, Stage Black text) on `:active`; Rec and hold-mode ▶ show their sweep instead.
- **Rec hold:** a Rec Red fill sweeps left to right over the 800 ms hold duration (linear) and then triggers; releasing early cancels. The button blocks text selection, touch callouts and scroll gestures.
- **Focus:** keyboard focus rings show on `:focus-visible`; mouse/touch focus outline is suppressed on cue buttons.

### Tabs
- **Style:** two equal-width, borderless buttons, min 48px tall, text inherits Paper White.
- **Active:** 3px Cue Blue bottom border; inactive has a transparent 3px border so the layout does not shift.

### List rows
- **Style:** flex row with 0.75rem gap, 0.375rem vertical padding, hairline bottom border; cue button, optional color swatch, truncated name, then start time.
- **Active region:** Cue Blue Wash background, name at weight 600, and a drawn three-bar now-playing indicator in place of the ▶ (Live Green while playing, Rec Red while recording, Paper White at 70% when paused). Only while the transport is active. Dimmed to 40% while offline.

### Offline banner
- A full-width line inside the sticky transport bar, always reserving its height so the rows never move: empty while online; Warn Umber background, Warn Cream text, Warn Edge bottom border when offline; announced with `role="alert"`. Offline needs 2 consecutive failed polls. The state word also turns Warn Amber, the clock dims, and ▶ re-enables 1.5 s after reconnect.

### State chip
- Leftmost item of the status strip: a 2px outlined 6px-radius chip holding a drawn shape and the uppercase state word, both in the state colour. Shapes: square = stopped, triangle = playing, disc = recording, two bars = paused, ring = offline. Colours: Paper White (stopped/paused), Live Green (playing), Rec Red (recording), Warn Amber (offline). The shape and the word mean colour is never the only signal.

### Loading, empty and error copy
- First load never claims a state it hasn't seen: the chip reads "CONNECTING…" (ring shape, Paper White at 70%), the region slot "Connecting to REAPER…", the clock "–:––", and each list "Loading regions…" / "Loading markers…" (`aria-busy` until data arrives). If REAPER never answers, the lists and region slot say it can't be reached instead of loading forever.
- Empty lists say what it means and what to do ("No regions in this project. Regions you add in REAPER will appear here.").
- A reply without a region list gets one plain sentence; REAPER's raw reply sits in a collapsed "Show REAPER's reply" `<details>` (monospace, for bug reports only).
- Unnamed rows are "Region N" / "Marker N" (N = REAPER's number), in the row, the cue button's accessible name and the status strip.

### Region name and clock
- Region name: now-playing role, "Nothing playing" at 60% when stopped, "No region here" when playing outside any region, "Region N" for an unnamed region. Dimmed to 40% with the clock while offline.

### Suite footer (every app except Home)
- Sticky at the bottom of every app page, 44px tall, Console Grey with a Hairline top border, content capped at 48rem like the lists. It sits at the bottom of short pages and sticks there on long ones (the page is a flex column; `<main>` grows).
- Holds only **Home**: a drawn house glyph plus the word "Home", left-aligned, 44px tap target, plain tap (navigation, not a transport action). Pressed inverts like every button; focus ring Cue Blue.
- Never put transport or other actions in it. See `docs/adr/0003`.

### Home page
- Sticky header in Console Grey: the suite name ("LiveCues" at 600 weight, "ReaperRemote" at 60% opacity, hidden below 480px) and a connection chip on the right.
- **Connection chip:** same outlined 6px chip and drawn-shape language as Podium's state chip. Connected = Paper White filled disc ("REAPER connected"); unreachable = Warn Amber ring ("REAPER unreachable"); connecting = Paper White ring at 70%. Green is not used: it means "playing".
- **App buttons:** Key Grey tiles with a Hairline border and 6px radius, min 5rem tall, app name at 1.25rem / 600 and a one-line description at 0.875rem / 60%. Grid that fills columns of at least 16rem (one column on phones). Pressed inverts.

## Do's and Don'ts

### Do:
- **Do** keep every touch target at least 44px (transport buttons 48px, Stop 56px), and the ▶ cue button 48px.
- **Do** reserve green, red and amber for state, and Cue Blue for selection.
- **Do** convey depth with tone and hairlines.
- **Do** use tabular numerals for all time values.
- **Do** keep text at #e8e8e8 on #16181b or darker surfaces; verify at least 4.5:1 contrast for any new text color.

### Don't:
- **Don't** make list rows tappable; only the ▶ button acts.
- **Don't** add shadows, glows, gradients or glossy skeuomorphic controls.
- **Don't** add a light theme or bright white surfaces; they glare on a dark stage.
- **Don't** use color alone to convey state; keep the state word beside it.
- **Don't** use new accent hues for decoration.
