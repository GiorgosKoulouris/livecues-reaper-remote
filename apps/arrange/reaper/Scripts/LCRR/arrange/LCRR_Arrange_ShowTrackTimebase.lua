-- @description LCRR Arrange: Show each track's timebase
-- @author George Koulouris
-- @version 1.0
-- @about
--   Lists every track with its timebase, as REAPER reports it through
--   C_BEATATTACHMODE, plus a tally and the running Lua version.
--
--   Timebase decides whether a tempo-map edit moves material: beat-based
--   material stores position in QN, so its absolute time is derived from the
--   tempo map and shifts when a tempo marker changes. Time-based material does
--   not move. Anything touching the tempo map needs to know this split first --
--   see issue #10.
--
--   Read-only.

-- The dialog front end. The readings are lib/core/show_track_timebase.lua;
-- the wording is lib/text/show_track_timebase.lua.
local script_dir = ({ reaper.get_action_context() })[2]:match("^(.*)[\\/]")
package.path = script_dir .. "/?.lua;" .. package.path

local timebase = require("lib.core.show_track_timebase")
local text = require("lib.text.show_track_timebase")

local function main()
  local result = timebase.run({ api = reaper })
  if result.status == "refused" then
    reaper.ShowMessageBox(text.error(result.error), timebase.TITLE, 0)
    return
  end

  reaper.ShowConsoleMsg(text.render(result))
end

-- Read-only: no undo block, nothing to undo.
main()
