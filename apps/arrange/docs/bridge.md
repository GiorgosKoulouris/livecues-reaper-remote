# The bridge

`LCRR_Arrange_Bridge.lua` is the web page's way into the actions. It runs in the
background, started by REAPER, and is the second front end over the headless
cores (ADR-0008): the dialog scripts are the first. This page is the contract
between it and `www/lcrr/arrange/js/`.

## Transport: ExtState over the web API

The page and the script talk through three ExtState keys in section
`LCRR_ARRANGE` (not persisted). Facts from the spike are in the suite
`CONTEXT.md`.

| Key | Written by | Value |
|---|---|---|
| `req` | the page, `SET/EXTSTATE/LCRR_ARRANGE/req/<encodeURIComponent(value)>` | one request |
| `res` | the bridge | `<id>\|<json>` for the last request it answered |
| `heartbeat` | the bridge, about 4 times a second, and after every request | a counter that changes |

**The page knows the bridge is running only from the heartbeat changing.** A key
that was never set reads as an empty value, which looks like any other empty
value. The bridge clears all three keys when it starts and when it stops.

REAPER serves web requests on its main thread. While an action runs (Apply, mostly) **every
request waits**, the page's own included, and no busy flag can be read. The page
knows an action is running because its own request is still open.

### Request

```
<id>|<length>|<body>
```

- `id`: made up by the page, `[A-Za-z0-9_-]`, at most 40 characters, different for every request.
- `length`: the byte length of `body` as sent. REAPER cuts a request URL at about 1026 characters and still answers HTTP 200, so a body shorter than declared is refused (`request_truncated`). The page keeps the encoded URL under about 900.
- `body`: `key=value&key=value`, each value percent-encoded (`encodeURIComponent`). The bridge decodes every `%XX`; `+` is a plus. The page sends ASCII only, so `length` is its character count.

Fields: `cmd` (always) plus the command's own. The bridge answers a request once,
and ignores the same raw value until the page writes a different one.

### Reply

```
{ "v": 1, "command": "...", "project": { "name": "...", "path": "..." }, "status": "...", ... }
```

`project` is the active project when the bridge answered (`""` and `""` when it has never been saved), and the page shows it. `status` is a core's: `ok`, `refused` (with `error: { code, ... }`), `confirm` or `cancelled`. Replies are codes and fields; the wording is the page's. REAPER escapes `\t`, `\n` and `\\` in the stored value, and the page unescapes them before reading the JSON.

Problems with the request itself are refusals: `bad_request`, `request_truncated` (with `declared` and `received`), `unknown_command`, `missing_field` (with `field`), `internal` (with `message`: a bug, or REAPER refusing a call).

## Commands

| `cmd` | Fields | Core | Reply (on `ok`) |
|---|---|---|---|
| `info` | | none | `bridge_version`, `saved`, `sidecar` (`ok`, `missing`, `invalid` or `unsaved`), `arrangements` (names), `regions` (`name`, `start_time`, `end_time`) |
| `arrangements` | | none (`sidecar`, `edit`) | `saved`, `sidecar` (`ok`, `missing`, `invalid` or `unsaved`), `revision` (`none` when there is no file), `parse_error` (the parse error, only when `invalid`), `canonical` (only when `ok`: false means a write asks the rewrite question first), `arrangements` (name order; each `{ name, entries: [{ name, headroom }] }`, entries in play order, `headroom` in seconds, 0 when none), `regions` (`name`, `start_time`, `end_time`, timeline order). `info` stays, with names only |
| `edit` | `operation`, `revision`, `project`, `rewrite=1`, and the operation's own fields (below) | Edit | `operation`, `name`, `from` (Duplicate and Rename), `revision`, `path`, `names`, `entries` (the edited Arrangement; absent after Delete), `deleted_entries` (Delete) |
| `duplicates` | | Find Duplicate Region Names | `verdict` (`no_regions`, `clean`, `problems`), `problems`, `region_count`, `region_reader` |
| `timebase` | | Show Track Timebase | `tracks` (`track_index`, `name`, `mode`), `tally` (`mode`, `count`, ascending) |
| `barlines` | | Show Bar Lines | `regions` (per region bar figures and `pad`), `padded`, `total_pad`, `origin`, `pad_threshold`, `region_reader` |
| `capture` | `name`, `replace=1`, `rewrite=1` | Capture | `name`, `replaced`, `regions`, `path`. Without `replace=1` an existing name answers `confirm` (`confirm: { code: "replace", name }`) and writes nothing. Without `rewrite=1`, a sidecar that is not canonical (differs from what `serialize` would write for it: comments, hand formatting, bare strings) answers `confirm: { code: "rewrite" }` and writes nothing. One question is asked per reply, `replace` first; the page repeats the request with every Yes so far |
| `verify` | `name` | Verify | `verdict` (`pass`, `fail`), `findings`, `blind_spots`, `region_reader` |
| `check` | `name` | Check | as Verify, plus `padding_exact`, and **`token` when the verdict is `will proceed`** |
| `apply` | `token`, `headroom` | Apply | `name`, `noop`, `counts`, `anchors`, `places`, `headroom`, `pads`, `parked`, `dropped` |

### Edits

One operation per request, saved at once (ADR-0009). `operation` is one of the
rows below; `revision` is `arrangements`' (or the last `edit` reply's) and
`project` is the project path the page read (the reply's `project.path`), so an
edit made against a changed file or another project is refused and nothing is
written. A reply's `revision` is the one for the next edit.

| `operation` | Own fields |
|---|---|
| `move` | `arrangement`, `region`, `slot` (1-based) |
| `set_headroom` | `arrangement`, `region`, `headroom` (seconds, may be negative) |
| `add` | `arrangement`, `region`, `slot` (1-based; omitted appends) |
| `remove` | `arrangement`, `region` |
| `clear_headroom` | `arrangement` |
| `new` | `name` |
| `duplicate` | `arrangement` (source), `name` (the copy) |
| `rename` | `arrangement`, `name` |
| `delete` | `arrangement` |

Refusals (`error.code`): `project_unsaved`, `other_project`, `sidecar_changed`,
`sidecar_invalid` (with `error`), `operation_unknown`, `would_be_invalid`,
`save_failed` (with `error`), and the operations' own: `name_empty`,
`name_taken`, `arrangement_not_found`, `region_empty`, `region_repeated`,
`region_not_in_arrangement`, `slot_invalid`, `headroom_invalid`. A missing
`operation`, `revision` or `project` is `missing_field`.

A file that is not canonical (comments, hand formatting) answers `confirm`
(`confirm: { code: "rewrite" }`) and writes nothing; the page asks, and repeats
the request with `rewrite=1`. New, Duplicate, Rename and Delete leave a run-log
entry; the other operations do not.

**Request size.** `project` is in every edit and is encoded twice (once in the
body, once in the URL), so a path of 80 characters with backslashes costs
about 200 of the ~900 URL characters. The client (`client.edit`) refuses, without
sending, a request that would not fit (`request_too_long`).

`headroom` (Apply's) is `apply`, `zero` or `cancel`. An Arrangement with a Headroom answers
`confirm` (`confirm: { code: "headroom", name, headroom: [{ name, seconds }] }`)
and writes nothing; the page asks, then sends the same request again with the
answer. The token survives that. `cancel` answers `cancelled`.

## Apply only after Check

A Check that would proceed returns a short `token`, and the bridge remembers, in
memory only, the Arrangement name, the project's path and its state-change count
from that moment, plus a fingerprint of the checked Arrangement's entries (in
order) and Headroom. Apply carries nothing but the token and the Headroom answer.
Apply re-reads the sidecar and compares. Edits to other Arrangements don't
matter; a rename does (the old name is gone). It refuses with:

- `token_unknown`: never issued, already used (a double tap), forgotten (the last 16 are kept), or issued before the bridge restarted.
- `token_stale`, with `reason: "other_project"` (another project tab is active) or `"project_changed"` (the project's state-change count differs) or `"arrangement_changed"` (the checked Arrangement's entries or Headroom differ, or it no longer exists, e.g. edited on the page or in a text editor). Check again.

A Check of an Arrangement with no entries refuses with the finding `arrangement_empty` and issues no token.

A token is spent by any final answer from Apply: success, refusal, `cancelled`. Only `confirm` keeps it.

## No dialog, no console on the host

The cores never open a dialog. The run log writes to REAPER's console as well as
to the file beside the project, which would open the console window on the host,
so the bridge hands the cores an `api` whose `ShowConsoleMsg` does nothing. The
log file is written as usual: for Dropped Material it is the only record.

## Starting it

`scripts/install.ps1` adds one marked line to `Scripts/__startup.lua` that registers the script as an action and runs it, and removes it again on `-Uninstall`. The script can also be run by hand from the Action list. REAPER runs a script that is already running again by asking what to do; ending it stops the bridge and clears the keys.
