-- @description LCRR Arrange: Bridge for the LCRR Arrange web page (background)
-- @author George Koulouris
-- @version 1.0
-- @about
--   Runs in the background and answers the LCRR Arrange page, which reaches it
--   through REAPER's web interface (ExtState). The page can run the same
--   actions as this folder's other scripts: the diagnostics, Capture, Verify,
--   and Check followed by Apply. **Nothing it does opens a dialog on this
--   computer**, and the run log beside the project is written as usual.
--
--   While an Apply is running, REAPER's web interface does not answer: the
--   page shows "Applying..." until it finishes.
--
--   The action "LCRR: Install startup hook" (or install.ps1) adds a line to
--   Scripts/__startup.lua so this starts with REAPER. Run this action by hand to start it otherwise; run it again to
--   stop it.

-- The bridge front end over the same cores as the dialog scripts. The request
-- handling is lib/bridge/service.lua, the loop is shared/bridge/runner.lua.
-- `shared` is a sibling of this folder (Scripts/LCRR/shared, suite ADR-0001).
local script_dir = ({ reaper.get_action_context() })[2]:match("^(.*)[\\/]")
package.path = script_dir .. "/?.lua;" .. package.path
package.path = script_dir .. "/../?.lua;" .. package.path

local service = require("lib.bridge.service")
local runner = require("shared.bridge.runner")

local _, _, section_id, command_id = reaper.get_action_context()

local bridge = runner.new({
  api = reaper,
  section = "LCRR_ARRANGE",
  handle = service.new({ api = reaper }).handle,
})

local function set_toggle(state)
  reaper.SetToggleCommandState(section_id, command_id, state)
  reaper.RefreshToolbar2(section_id, command_id)
end

local function loop()
  bridge.tick()
  reaper.defer(loop)
end

reaper.atexit(function()
  bridge.stop()
  set_toggle(0)
end)

set_toggle(1)
bridge.start()
loop()
