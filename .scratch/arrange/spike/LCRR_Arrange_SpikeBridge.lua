-- @description LCRR Arrange: bridge spike (throwaway, delete after the spike)
-- @author Giorgos Koulouris
-- @version 0.0.1
-- @about Answers requests that lcrr-arrange-spike.html writes to ExtState. See .scratch/arrange/issues/01-bridge-spike.md.
--
-- Protocol (spike only):
--   page  -> SET/EXTSTATE/LCRR_ARRANGE_SPIKE/req/<id>|<cmd>|<arg>
--   Lua   -> SetExtState(LCRR_ARRANGE_SPIKE, res, <id>|<payload>)
--   Lua   -> SetExtState(LCRR_ARRANGE_SPIKE, heartbeat, <counter>) about 4 times a second

local S = "LCRR_ARRANGE_SPIKE"

-- Fixed reply for the reply-encoding test. The page holds an identical copy.
local CHARS = "tab:\t nl:\n bs:\\ q:\" pct:% sl:/ sc:; pipe:| amp:& plus:+ sp: utf8:\u{e9}\u{2014}\u{1F3B5} json:{\"a\":[1,2]}"

local UNIT = "abcdefghijklmnopqrstuvwxyz0123456789"

local function pattern(n)
  return string.rep(UNIT, n // #UNIT + 1):sub(1, n)
end

local last_id = nil
local beat, last_beat = 0, 0

local function handle(req)
  local id, cmd, arg = req:match("^([^|]*)|([^|]*)|(.*)$")
  if not id or id == "" or id == last_id then return end
  last_id = id
  local out
  if cmd == "ping" then
    out = arg
  elseif cmd == "echo" then
    out = #arg .. "|" .. arg               -- byte length as Lua received it, then the bytes
  elseif cmd == "len" then
    out = tostring(#arg)
  elseif cmd == "chars" then
    out = CHARS
  elseif cmd == "size" then
    out = pattern(math.floor(tonumber(arg) or 0))
  elseif cmd == "slow" then
    local t0, secs = reaper.time_precise(), (tonumber(arg) or 0) / 1000
    while reaper.time_precise() - t0 < secs do end   -- deliberately blocks the main thread
    out = string.format("slept|%.3f|%.3f", t0, reaper.time_precise())
  else
    out = "unknown command: " .. tostring(cmd)
  end
  reaper.SetExtState(S, "res", id .. "|" .. out, false)
end

local function loop()
  local now = reaper.time_precise()
  if now - last_beat >= 0.25 then
    beat, last_beat = beat + 1, now
    reaper.SetExtState(S, "heartbeat", string.format("%d@%.3f", beat, now), false)
  end
  local req = reaper.GetExtState(S, "req")
  if req ~= "" then handle(req) end
  reaper.defer(loop)
end

local _, _, section_id, cmd_id = reaper.get_action_context()
reaper.SetToggleCommandState(section_id, cmd_id, 1)
reaper.RefreshToolbar2(section_id, cmd_id)

reaper.atexit(function()
  reaper.DeleteExtState(S, "heartbeat", false)
  reaper.DeleteExtState(S, "req", false)
  reaper.DeleteExtState(S, "res", false)
  reaper.SetToggleCommandState(section_id, cmd_id, 0)
  reaper.RefreshToolbar2(section_id, cmd_id)
end)

reaper.DeleteExtState(S, "req", false)
reaper.DeleteExtState(S, "res", false)
reaper.ShowConsoleMsg("LCRR Arrange spike bridge running. Run the action again to stop it.\n")
loop()
