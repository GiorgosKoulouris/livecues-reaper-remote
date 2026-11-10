# Arrange

A suite of ReaScript (Lua) actions for [REAPER](https://www.reaper.fm/) that
automate one repetitive job: **laying a project's regions back down in a
different order, carrying everything inside them along.**

You describe the order you want in a small text file. An action reads it and
rearranges the project — regions, the markers inside them, the media items, the
automation, and the tempo map — so the result is contiguous, bar-aligned, and
sounds like the same material in a new sequence.

The scope is deliberately narrow. This is not a general project-management
suite; it does regions and markers, and it tries to do them exactly right.

> **Status: private, and used in anger.** Ships in the suite's ReaPack package
> (beta, see the root README; run the action *LCRR: Install startup hook* once so the
> bridge starts with REAPER) or via `scripts/install.ps1`; not in the release zip. It runs against real
> projects and the design notes are unusually explicit about what it will and
> will not do, because the operations are hard to undo by hand.

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

That operation has a name in this suite: a **Repack**. It is not a "reorder";
reorder is what the text file expresses, Repack is what happens to the timeline.
The vocabulary matters enough that it has [its own glossary](CONTEXT.md).

## Requirements

| | |
|---|---|
| **REAPER** | 7.x. Developed and verified against **7.78 / win64** |
| **Extensions** | None. Vanilla ReaScript API only — no SWS, no js_ReaScriptAPI |
| **Lua** | REAPER's built-in Lua 5.4. Nothing to install |
| **Platform** | The installer (`scripts/install.ps1`) is PowerShell/Windows. On macOS/Linux, copy the folder by hand — the scripts themselves are platform-neutral |

## Setup

Part of LiveCues ReaperRemote: the suite's installer puts these actions in place
along with the web pages (see the root `README.md`).

**1. Install.** On the Windows host, from the repo:

```powershell
.\scripts\install.ps1                     # copies into %APPDATA%\REAPER
.\scripts\install.ps1 -Resource D:\PortableReaper   # a portable REAPER's resource path
.\scripts\install.ps1 -Link               # symlinks instead (Developer Mode), for development
```

The actions land in `<REAPER resource path>\Scripts\LCRR\arrange\`, with `lib\`
beside them. On another platform, copy `apps/arrange/reaper/Scripts/LCRR/` into
REAPER's `Scripts` folder by hand.

> **`lib/` must stay beside the scripts.** Each script locates `lib/` relative
> to itself. Moving either breaks every action with a `module 'lib.project' not
> found` error.

**The web page.** `lcrr-arrange.html` (the Arrange button on the home page) runs the same actions from a browser. It talks to a background script, `LCRR_Arrange_Bridge.lua`, which `install.ps1` starts with REAPER through one marked line in `Scripts\__startup.lua` (restart REAPER after the first install, or run the action once by hand). The page says "Arrange not running" until it is. Nothing the page does opens a dialog or the console window on the host, and neither do Check, Apply, Capture or Verify run from the Action list: they show a short message box and write the detail to the run log beside the project. Only Show bar lines and Show track timebase use the console, because their output is a list. While an Apply runs, REAPER's web interface does not answer, so the page shows "Applying…". See [docs/bridge.md](docs/bridge.md).

**2. Register the actions in REAPER.**

`Actions → Show action list… → New action ▾ → Load ReaScript…`, then select the
`LCRR_Arrange_*.lua` files. You can multi-select all of them at once.

They now appear in the Action list under their `@description`, which starts
`LCRR Arrange:`. Bind keys or add them to a toolbar as you like.

> **Install is one-way: repo → REAPER.** Do not edit these files in REAPER's own
> script editor; the next install overwrites them without warning. Equally,
> editing the repo changes nothing REAPER runs until you install again (unless
> you installed with `-Link`). If an action misbehaves in a way the code says is
> impossible, *re-install first* — that has been the answer more than once.

## Quick start

On a **copy** of a real project — this suite rewrites project state, and you
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
Arrangement twice moves that end twice — so Apply shows the suite's only
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

- **Region names must be unique and non-empty.** Not REAPER's rule; this
  suite's, because names are how an Arrangement refers to a region.
- **The project must be saved.** The sidecar and log live beside the `.RPP`.
- **Beat-based timebases are refused, not handled.** If tracks or items are set
  to a beats timebase, moving them stretches their content, so a run stops
  rather than guessing. (Issue #9 of the old repo.)
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

## Layout

```
reaper/Scripts/LCRR/arrange/       the REAPER actions — one file per Action list entry
reaper/Scripts/LCRR/arrange/lib/   the logic: pure planners over plain tables, plus thin appliers
spec/                              busted specs, including golden .RPP fixtures
docs/                              user documentation and architecture decision records
```

Contributor-facing notes: [CLAUDE.md](CLAUDE.md) for conventions,
[docs/limitations.md](docs/limitations.md) for what is not yet observed in REAPER, [docs/adr/](docs/adr/) for the seven
architecture decisions, and `research/reaper-scripting.md` for sourced ReaScript
API findings.

Running the tests requires `busted` and `luacheck` (the devcontainer has them).
From the repo root, `npm test` and `npm run check` run them; or in `apps/arrange/`:

```sh
busted      # specs
luacheck .  # lint
```

## Documentation

| Document | What it is |
|---|---|
| [docs/workflow.md](docs/workflow.md) | The seven-step path, end to end, with what each step means |
| [docs/actions.md](docs/actions.md) | Every action: what it needs, what it changes, what it refuses on |
| [docs/limitations.md](docs/limitations.md) | What this suite will not do, and why |
| [CONTEXT.md](CONTEXT.md) | Glossary — Repack, Padding, Headroom, Parked Material, and the rest |
| [docs/adr/](docs/adr/) | Why the architecture is the way it is |

## Author

George Koulouris.
