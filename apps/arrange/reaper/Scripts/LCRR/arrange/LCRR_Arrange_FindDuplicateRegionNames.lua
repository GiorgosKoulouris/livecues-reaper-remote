-- @description LCRR Arrange: Find duplicate or unnamed regions
-- @author George Koulouris
-- @version 1.1
-- @about
--   Reports every Region Name used by more than one region, and every region
--   with no name at all.
--
--   Arrangements key on Region Name, so a project must have unique, non-empty
--   names before any of the Arrangement actions will run (ADR-0003). This
--   action is how you find the violations -- it only reads, and changes
--   nothing.

-- The dialog front end. Finding the problems, and logging them, is
-- lib/core/find_duplicate_region_names.lua; the wording is
-- lib/text/find_duplicate_region_names.lua.
--
-- Scripts are loaded from REAPER's Scripts folder, where lib/ sits beside
-- this file (see scripts/install.ps1). package.path has no idea about it, so
-- it is extended before anything is required.
local script_dir = ({ reaper.get_action_context() })[2]:match("^(.*)[\\/]")
package.path = script_dir .. "/?.lua;" .. package.path

local find = require("lib.core.find_duplicate_region_names")
local text = require("lib.text.find_duplicate_region_names")

local function main()
  local result = find.run({ api = reaper })

  -- A clean result is reported without a blocking dialog -- the console copy is
  -- enough. Only a failure interrupts, because that one must be seen
  -- (CLAUDE.md, errors vs logs).
  if result.verdict == "problems" then
    reaper.ShowMessageBox(text.problems_message(result), find.TITLE, 0)
  end
end

-- Read-only: no Undo block, because there is nothing to undo, and an undo point
-- for an action that changed nothing would be noise in the history.
main()
