-- @description LCRR Arrange: Verify the timeline against an Arrangement (read-only)
-- @author George Koulouris
-- @version 1.0
-- @about
--   Prompts for an Arrangement name and checks that the project's timeline
--   holds the properties a Repack promises. **Changes nothing** -- no writes,
--   no undo point.
--
--   Run it after 'Apply Arrangement'. It checks four things:
--
--   * the regions the Arrangement names appear in that order
--   * they are contiguous, starting at the beginning of the timeline -- the
--     Packed Block has no gaps
--   * every one of their starts lands on a bar line (ADR-0004)
--   * the regions the Arrangement omits sit beyond the Packed Block as Parked
--     Material
--
--   **It derives all of that from the project as it now stands, never from the
--   plan that produced it,** and that is the whole point. Re-running 'Apply
--   Arrangement' and being told "already matches the timeline" tests Apply
--   against itself: a Repack that was self-consistently wrong passes it. This
--   asks the project instead, so it is a second opinion rather than an echo.
--
--   Because it needs nothing but the current timeline, it works on a project
--   packed in an earlier session -- unlike Undo, which does not survive one.
--   Naming a different Arrangement than the one applied is legitimate: it
--   answers "which Arrangement does this timeline actually match?".

-- The dialog front end. Verifying, and its run-log entry, are
-- lib/core/verify.lua; the wording is lib/text/verify.lua.
local script_dir = ({ reaper.get_action_context() })[2]:match("^(.*)[\\/]")
package.path = script_dir .. "/?.lua;" .. package.path

local verify = require("lib.core.verify")
local text = require("lib.text.verify")

local TITLE = verify.TITLE

local function abort(err)
  reaper.ShowMessageBox(text.error(err), TITLE, 0)
end

local function main()
  local prepared = verify.prepare({ api = reaper })
  if prepared.status == "refused" then
    return abort(prepared.error)
  end

  -- The caption is comma-delimited, so the name list joins on " / " (see
  -- LCRR_Arrange_Apply, where this bit us first).
  local ok, typed = reaper.GetUserInputs(TITLE, 1,
    ("Arrangement name (%s):,extrawidth=200"):format(table.concat(prepared.available, " / ")), "")
  if not ok then
    return
  end

  local result = verify.run(prepared, { name = typed })
  if result.status == "refused" then
    return abort(result.error)
  end

  return reaper.ShowMessageBox(text.summary(result), TITLE, 0)
end

-- No Undo block: this action reads project state and writes nothing (CLAUDE.md,
-- Undo convention).
main()
