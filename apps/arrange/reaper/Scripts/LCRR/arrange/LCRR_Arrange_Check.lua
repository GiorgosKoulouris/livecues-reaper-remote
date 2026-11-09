-- @description LCRR Arrange: Check an Arrangement before applying it (read-only)
-- @author George Koulouris
-- @version 1.0
-- @about
--   Prompts for an Arrangement name and reports, in one place, everything
--   knowable about applying it to this project **without writing anything**.
--   No project state changes, and no undo point is created.
--
--   Run it between editing the sidecar and running 'Apply Arrangement'.
--
--   It reports three things, in this order:
--
--   **Refusals** -- what would stop a run: an unsaved project, a missing or
--   unparseable sidecar, an unknown Arrangement name, a Region Name the
--   project does not have, duplicate or unnamed regions, a tempo envelope on a
--   Beats timebase, an item on a timebase this suite cannot safely reposition,
--   or Padding that would run a region into its neighbour. Every refusal it can
--   see is listed, not just the first, so one check is one round trip.
--
--   **Permanent effects that are not refusals** -- what a run would do that
--   running it again will not undo: the regions an Arrangement omits becoming
--   Parked Material, Headroom moving a region's end, Padding added inside a
--   region's bounds, Straddling Items cut, and material touching no region
--   being discarded. Headroom is the one of those that running again would do
--   *again*, so this is where to read what each request resolves to before
--   committing to it.
--
--   **What this check cannot see.** Phase 1 of a run writes a Tempo Anchor at
--   every region start, and that is what puts those starts on bar lines; the
--   tempo oracle reads live project state (ADR-0006), so it cannot be asked
--   about a grid that does not exist yet. Padding is therefore computed against
--   the grid as it stands -- **exact** on a project whose anchors are already
--   present, an **estimate** on a first run. The report says which.

-- The dialog front end. The check itself, and its run-log entry, are
-- lib/core/check.lua; the wording is lib/text/check.lua.
local script_dir = ({ reaper.get_action_context() })[2]:match("^(.*)[\\/]")
package.path = script_dir .. "/?.lua;" .. package.path

local check = require("lib.core.check")
local text = require("lib.text.check")

local TITLE = check.TITLE

local function main()
  local prepared = check.prepare({ api = reaper })
  if prepared.status == "refused" then
    return reaper.ShowMessageBox(text.error(prepared.error), TITLE, 0)
  end

  local name = ""
  if #prepared.available > 0 then
    -- GetUserInputs's caption argument is itself comma-delimited, so the name
    -- list joins on " / " -- ", " would fragment the caption across extra
    -- fields (LCRR_Arrange_Apply hit this first).
    local ok, typed = reaper.GetUserInputs(TITLE, 1,
      ("Arrangement name (%s):,extrawidth=200"):format(table.concat(prepared.available, " / ")), "")
    if not ok then
      return
    end
    name = typed
  end

  local result = check.run(prepared, { name = name })
  reaper.ShowMessageBox(text.summary(result), TITLE, 0)
end

-- No Undo block: this action reads project state and writes nothing, so there
-- is nothing for REAPER's undo history to hold (CLAUDE.md, Undo convention).
main()
