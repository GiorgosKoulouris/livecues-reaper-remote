-- @description LCRR Arrange: Show bar lines and Padding for every region (read-only)
-- @author George Koulouris
-- @version 1.0
-- @about
--   Reports, for every region, where its bounds sit relative to the bar grid
--   and how much Padding a Repack would add. **Changes nothing** -- no writes,
--   no undo point.
--
--   This exists because the tempo oracle is the least verifiable code in the
--   suite (ADR-0004, ADR-0006) and REAPER is the only thing that can confirm
--   it. Run this before trusting a Repack's Padding on a project that matters:
--   it exercises exactly the two oracle calls a Repack depends on, prints their
--   raw answers, and needs no undo.
--
--   It also prints the raw measure indices, which settles the one thing
--   research/reaper-scripting.md §4.5 could not: whether REAPER numbers
--   measures from 0 or from 1. The oracle does not depend on the answer, but it
--   should be pinned rather than worked around.

-- The dialog front end. The readings are lib/core/show_bar_lines.lua; the
-- wording is lib/text/show_bar_lines.lua.
local script_dir = ({ reaper.get_action_context() })[2]:match("^(.*)[\\/]")
package.path = script_dir .. "/?.lua;" .. package.path

local bars = require("lib.core.show_bar_lines")
local text = require("lib.text.show_bar_lines")

local TITLE = bars.TITLE

local function main()
  local result = bars.run({ api = reaper })
  if result.status == "refused" then
    return reaper.ShowMessageBox(text.error(result.error), TITLE, 0)
  end

  reaper.ShowConsoleMsg(text.render(result))
  reaper.ShowMessageBox(text.summary(result), TITLE, 0)
end

main()
