---
target: podium-remote page
total_score: 22
max_score: 40
na_heuristics: 
p0_count: 0
p1_count: 3
target_identity: "file:/workspace/podium-remote/reaper_www_root/podium-remote.html"
target_fingerprint: "sha256:22114a58165dfd50db6d3d26dd106792b3125d7c60c315001313da77845f5fa3"
target_path: /workspace/podium-remote/reaper_www_root/podium-remote.html
timestamp: 2026-11-07T13-21-23Z
slug: podium-remote-reaper-www-root-podium-remote-html
---
Method: dual-agent (A: design review sub-agent · B: detector sub-agent). Browser visualization skipped: no browser binary or Playwright in this environment.

Target: podium-remote/reaper_www_root/podium-remote.html (+ css/js), working tree. Mode: Operate.

## Design Health Score

| # | Heuristic | Score | Key Issue |
|---|---|---|---|
| 1 | Visibility of System Status | 2 | State word is the smallest text (0.8rem / 0.7rem phone); now-playing region only shown as a row highlight that scrolls away; no pressed state on any button; first load claims "stopped / No regions yet." before data |
| 2 | Match System / Real World | 3 | Play/Stop/Rec familiar; "Regions/Markers" are DAW words; millisecond clock digits are noise at 500 ms poll |
| 3 | User Control and Freedom | 2 | One tap on another row's ▶ cuts the playing song; no guard, no undo |
| 4 | Consistency and Standards | 3 | Tabs done properly; "Play" text vs ▶ glyph; Rec needs a hold but looks like its one-tap neighbours |
| 5 | Error Prevention | 2 | Rows and Rec guarded; ▶ mid-song unguarded; double-tap restarts; banner causes layout shift on reconnect |
| 6 | Recognition Rather Than Recall | 2 | Hold-to-record only in a title tooltip (invisible on touch) |
| 7 | Flexibility and Efficiency | 2 | No auto-scroll to active row, no keyboard shortcut for Stop |
| 8 | Aesthetic and Minimalist Design | 3 | Calm and restrained, but flat hierarchy; h1 and ms digits compete with state |
| 9 | Error Recovery | 2 | Offline banner scrolls away; stale time/highlight looks live; raw developer diagnostic copy |
| 10 | Help and Documentation | 1 | Nothing on the page explains hold-to-record or the ▶-only rule |
| **Total** | | **22/40** | **Acceptable** |

## Design Specificity Verdict

LLM assessment: the interaction model is authored for this product (non-tappable rows, 48px ▶ only, 800 ms Rec hold with sweep, state-only colour, dim off-white on charcoal). The composition is not: toolbar → tabs → list is any dark admin app. The stage-console idea lives in the palette, not the layout. Nothing reads from 2 m away; Stop is styled like Play and Rec.

Deterministic scan: HTML alone exit 0; directory scan exit 2 with 1 finding: side-tab at podium-remote.css:44 (6px cue-blue ::before stripe on li.active). Documented as intentional in DESIGN.md (Colors), but DESIGN.md is inconsistent: Lone Accent Rule says Cue Blue is the tab underline only, and the row-active token/component omit the bar. Design review flagged the same inconsistency independently. No false positives.

Visual overlays: none (no browser available).

## Priority Issues

1. [P1] ▶ is a one-tap song killer during playback, with no press feedback. podium-remote.js click sends seek+play immediately; css:11 removes tap highlight, no :active rule. Restart-on-active is a documented decision in CONTEXT.md, but it conflicts with principle 1. Fix: while playing, make row ▶ hold-to-cue (reuse Podium.hold) or arm-then-confirm; replace active row's ▶ with a now-playing indicator; strong :active + pending class; debounce repeats ~1.5 s. Command: /impeccable harden.
2. [P1] State not glanceable; now-playing name absent from sticky bar. css:25,58. Fix: status strip with large shape+colour state chip, current region name in the title slot, m:ss time; scrollIntoView active row. Command: /impeccable layout (+ typeset).
3. [P1] Offline failure scrolls out of view, stale data looks live, reconnect shifts rows under the thumb. html:19 banner outside sticky header; offline branch returns early. Fix: banner inside/sticky with reserved slot or overlay; dim stale time and highlight; 2 consecutive failures before offline; delay ▶ re-enable. Command: /impeccable harden.
4. [P2] Transport bar has no hierarchy; Rec's hold invisible on touch; Rec disabled while recording looks like offline. Fix: Stop largest with ■ glyph; Rec isolated with visible HOLD sub-label + aria-describedby; live ● REC state. Command: /impeccable layout + /impeccable clarify.
5. [P2] False loading state and developer-facing diagnostic. html:15-16,27; js:65. Fix: CONNECTING… / Loading regions…; plain copy with raw reply in <details>. Command: /impeccable clarify.

## Persona Red Flags

Casey: transport at top, Stop top-left; no press feedback → double taps; reconnect layout shift; bar likely wraps at 320px or ≥10:00 + RECORDING; clock shifts as state word length changes on phones.
Sam: hold hint only in title; region change not announced; offline announced twice (alert + status); renderList drops focus; button edge contrast ~1.3:1; active ▶ border on wash ~2.9:1; bare U+25B6 may render as emoji.
On-stage performer: can't read state at distance; doesn't know what's playing once scrolled; one mis-tap ends the song; no remaining-time cue; phone auto-lock (Wake Lock needs HTTPS); region swatch colours can mimic state colours.

## Minor Observations

DESIGN.md vs CSS drift (Cue Blue usage, active name weight 600 vs 400); header full width vs 48rem list on desktop; h1 occupies the slot the song name should; full long names unreadable >480px; hollow swatch noise for uncoloured regions; Markers ▶ get no highlight; "(unnamed)" instead of region number; empty temp.txt at repo root.

## Questions to Consider

- Why is ▶ during a live song a one-tap action when Rec, rarely used on stage, gets the guard?
- What if the sticky bar were a now-playing display first and a control row second?
- Does a performer need Regions/Markers and a play-from-cursor button, or a numbered setlist of Songs with a big Stop?
