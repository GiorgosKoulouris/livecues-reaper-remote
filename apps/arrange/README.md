# Arrange

The [LiveCues ReaperRemote](../../README.md) app that automates one repetitive
job in [REAPER](https://www.reaper.fm/): **laying a project's regions back down
in a different order, carrying everything inside them along.**

You describe the order you want in a small text file. An action reads it and
rearranges the project — regions, the markers inside them, the media items, the
automation, and the tempo map — so the result is contiguous, bar-aligned, and
sounds like the same material in a new sequence.

The scope is deliberately narrow. This is not a general project-management
tool; it does regions and markers, and it tries to do them exactly right.

> **Beta, and it changes your project.** Arrange is used on real projects, but
> its operations are hard to undo by hand. Try it on a copy first, and read
> [What to expect](#what-to-expect).

---

## What it actually does

Given a project with named regions and this file beside it:

```lua
return {
  ["Album"] = { "Intro", "Verse 1", "Chorus", "Verse 2", "Outro" },
  ["Radio"] = { "Intro", { "Chorus", headroom = 4 }, "Verse 2" },
}
```

…applying **`Radio`** produces a timeline where `Intro`, `Chorus` and `Verse 2`
sit back to back from 0:00 with no gaps, each starting exactly on a bar line,
each carrying its own tempo — where `Chorus` has gained about four more seconds
of air at its end, rounded to a bar line — and where `Verse 1` and `Outro` have
been moved out of the way rather than deleted.

That operation has a name in Arrange: a **Repack**. It is not a "reorder";
reorder is what the text file expresses, Repack is what happens to the timeline.
The vocabulary matters enough that it has [its own glossary](CONTEXT.md).

## Requirements

| | |
|---|---|
| **REAPER** | 7.x. Developed and verified against **7.78 / win64** |
| **Extensions** | None. Vanilla ReaScript API only — no SWS, no js_ReaScriptAPI |
| **Lua** | REAPER's built-in Lua 5.4. Nothing to install |
| **Platform** | Developed and tested on Windows. macOS and Linux are untested |

## Setup

Arrange installs with the rest of LiveCues ReaperRemote: follow the
[install steps](../../README.md#install) in the main README, including the
startup hook.

**The page.** The Arrange button on the Home page runs the same actions from a
browser, through a background script that the startup hook starts with REAPER.
The page says "Arrange not running" until that script is running. While an Apply
runs, REAPER's web interface does not answer, so the page shows "Applying…".

**The actions.** With ReaPack, the actions are already in REAPER's Action list,
under names starting `LCRR Arrange:`. Bind keys or add them to a toolbar as you
like. If you installed with the script instead, load them once:
`Actions → Show action list… → New action ▾ → Load ReaScript…`, then select the
`LCRR_Arrange_*.lua` files in `Scripts\LCRR\arrange\`. You can select them all
at once.

Nothing the page does opens a dialog or the console window on the computer
running REAPER. Check, Apply, Capture and Verify run from the Action list show a
short message box and write the detail to the run log beside the project. Only
Show bar lines and Show track timebase use the console, because their output is
a list.

## Quick start

On a **copy** of a real project — Arrange rewrites project state, and you
want the first run to be one you can throw away.

1. **Name your regions.** Every region needs a unique, non-empty name; that name
   is the only handle an Arrangement uses. Run **Find duplicate or unnamed
   regions** to check.
2. **Capture the current order.** Run **Capture the current region order as an
   Arrangement** and call it something like `Full`. This writes
   `<YourProject>.arrangements.lua` next to your `.RPP`.
3. **Duplicate and edit it.** On the Arrange page's Edit tab, pick the
   Arrangement and Duplicate it, then drag or use ↑/↓ to reorder and Remove to
   make a subset. (You can still edit `<YourProject>.arrangements.lua` in a text
   editor.)
4. **Adjust lengths, if you want to.** Set `headroom` on an entry to add or
   remove seconds at that region's end. The result lands on the nearest bar
   line, and `0` — the default — changes nothing.
5. **Check before you commit.** Run **Check an Arrangement before applying it**
   and give it the new name. It changes nothing and tells you what would happen.
   *Read the output.*
6. **Apply.** Run **Apply a named Arrangement**.
7. **Verify.** Run **Verify the timeline against an Arrangement**. Expect PASS.

The full version of this, with what each step means and why, is in
[docs/workflow.md](docs/workflow.md).

## The actions

| Action | Writes? |
|---|---|
| Find duplicate or unnamed regions | No |
| Show each track's timebase | No |
| Show bar lines and Padding for every region | No |
| Capture the current region order as an Arrangement | Sidecar file only |
| **Check an Arrangement before applying it** | No |
| **Apply a named Arrangement** | **Yes — this is the one that changes the project** |
| **Verify the timeline against an Arrangement** | No |

Exactly one action modifies your project. Everything else reads, or writes a
text file beside it. Full reference: [docs/actions.md](docs/actions.md).

## What to expect

**It runs immediately.** No confirmation prompt, with the single exception noted
under Headroom below. The safety net is REAPER's undo (one undo point per run)
plus a log written beside your project — a deliberate decision, on the grounds
that a prompt you always click through is not a safety feature.

**It writes a log.** `<YourProject>.arrange.log`, next to the `.RPP`, appended to on
every run. For discarded material this log is **the only record** — the project
afterwards cannot tell you what was thrown away. Keep it.

**Regions get padded.** A region whose length is not a whole number of bars has
its end extended to the next bar line, so the next region can start on a bar
line with no gap. That puts silence *inside* the region's bounds, permanently.
It happens at most once per region, and the check reports the exact amount per
region beforehand.

**It is idempotent — with one deliberate exception.** Applying the same
Arrangement twice does nothing the second time: no undo point, no log entry. If
a second run does something, that is a bug worth reporting. The exception is
**Headroom**.

**Headroom adjusts a region's end, and it is relative.** Set `headroom` on an
Arrangement entry to add or remove seconds at that region's end; the result is
rounded to the nearest bar line, so anything under half a bar changes nothing.
Because it describes a *change* rather than a target length, applying the same
Arrangement twice moves that end twice — so Apply shows Arrange's only
confirmation dialog whenever any Headroom is non-zero, offering apply,
repack-only, or cancel. Nothing else can catch a double application, and
**Verify** says so rather than letting a PASS imply otherwise. A shrink may only
remove silence: it can never come back past the last thing inside the region,
and a request below that refuses rather than clamping. Why it works this way:
[ADR-0007](docs/adr/0007-headroom-is-relative-not-absolute.md).

**Nothing is deleted for being left out.** An Arrangement naming a subset of
your regions is normal and supported; the omitted regions are moved beyond the
packed material with their contents intact, and the log records the single
offset that reverses it.

**Some things are discarded.** Media lying outside every region is thrown away,
and items straddling a region boundary are cut. See Limitations.

## Limitations

The short version — the full list, with reasoning, is in
[docs/limitations.md](docs/limitations.md).

- **Region names must be unique and non-empty.** Not REAPER's rule; Arrange's,
  because names are how an Arrangement refers to a region.
- **The project must be saved.** The sidecar and log live beside the `.RPP`.
- **Beat-based timebases are refused, not handled.** If tracks or items are set
  to a beats timebase, moving them stretches their content, so a run stops
  rather than guessing.
- **Project Settings → "Timebase for tempo/time signature env" must be `Time`.**
  On `Beats` a Repack cannot move tempo markers reliably, and it refuses.
- **Material outside every region is discarded**, and straddling items are cut.
  Clean up before you Repack.
- **Arrangements are edited on the page, not by a REAPER action.** The Arrange
  page's Edit tab does New, Duplicate, Rename, Delete, reorder, Headroom and
  Undo. The sidecar is still plain text you can edit by hand.
- **Headroom is not idempotent.** It is the one operation here that a second run
  repeats. Apply's prompt is the only guard, and Verify cannot detect a double
  application.

## Documentation

| Document | What it is |
|---|---|
| [docs/workflow.md](docs/workflow.md) | The seven-step path, end to end, with what each step means |
| [docs/actions.md](docs/actions.md) | Every action: what it needs, what it changes, what it refuses on |
| [docs/limitations.md](docs/limitations.md) | What Arrange will not do, and why |
| [CONTEXT.md](CONTEXT.md) | Glossary — Repack, Padding, Headroom, Parked Material, and the rest |
| [docs/adr/](docs/adr/) | Why the architecture is the way it is |

To work on Arrange itself, see [CONTRIBUTING.md](../../CONTRIBUTING.md#working-on-arrange).

## Author

Georgios Koulouris.
