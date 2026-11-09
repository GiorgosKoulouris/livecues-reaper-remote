-- @description LCRR Arrange: Capture the current region order as an Arrangement
-- @author George Koulouris
-- @version 1.0
-- @about
--   Writes the project's regions, in timeline order, into the Arrangement
--   sidecar beside the .RPP as a named Arrangement.
--
--   This is one of only two Arrangement actions REAPER gets; authoring and
--   reordering happen in a text editor, on the sidecar file (ADR-0003). Use
--   this to seed a sidecar from a project you have already laid out by hand.
--
--   Changes no project state -- it writes one file next to the project.

-- The dialog front end. Capturing, and its run-log entry, are
-- lib/core/capture.lua; the wording is lib/text/capture.lua.
local script_dir = ({ reaper.get_action_context() })[2]:match("^(.*)[\\/]")
package.path = script_dir .. "/?.lua;" .. package.path

local capture = require("lib.core.capture")
local text = require("lib.text.capture")

local TITLE = capture.TITLE

local function abort(err)
  reaper.ShowMessageBox(text.error(err), TITLE, 0)
end

local function main()
  local prepared = capture.prepare({ api = reaper })
  if prepared.status == "refused" then
    return abort(prepared.error)
  end

  local ok, name = reaper.GetUserInputs(TITLE, 1, "Arrangement name:,extrawidth=200",
    capture.DEFAULT_NAME)
  if not ok then
    return -- cancelled
  end

  local request = { name = name }
  local result = capture.run(prepared, request)

  if result.status == "confirm" then
    local confirm = reaper.ShowMessageBox(text.replace_question(result.confirm), TITLE, 4)
    if confirm ~= 6 then -- 6 = Yes
      return
    end
    request.replace = true
    result = capture.run(prepared, request)
  end

  if result.status == "refused" then
    return abort(result.error)
  end

  reaper.ShowMessageBox(text.summary(result), TITLE, 0)
end

-- No Undo block: this action writes a sidecar file, not project state, so there
-- is nothing for REAPER's undo history to hold (CLAUDE.md, Undo convention).
main()
