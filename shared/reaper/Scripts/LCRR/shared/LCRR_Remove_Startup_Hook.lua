-- @description LCRR: Remove startup hook (starts the LCRR bridges with REAPER)
-- @author George Koulouris
-- @version 1.0
-- @about
--   Run once to remove the lines in Scripts/__startup.lua that start the LCRR bridges
--   (Arrange, IEM Setup) when REAPER starts. Your own lines in that file are kept.
--   Run "Remove startup hook" before uninstalling LCRR in ReaPack.

-- `shared` is this script's own folder; its parent holds it as a require root.
local script_dir = ({ reaper.get_action_context() })[2]:match("^(.*)[\\/]")
package.path = script_dir .. "/../?.lua;" .. package.path

local hook = require("shared.startup.hook")
reaper.ShowMessageBox(hook.run({ api = reaper, fs = hook.real_fs() }, false), "LCRR", 0)
