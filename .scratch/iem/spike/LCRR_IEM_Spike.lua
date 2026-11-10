-- @description LCRR IEM Spike: test the REAPER calls IEM Setup depends on (throwaway, issue 01)
-- @author LCRR
-- @version 1
--
-- Run only in a new, empty, unsaved project tab: it refuses anything else.
-- Writes <resource path>/LCRR_IEM_Spike_Report.txt and repeats it in the console.
-- Run it a second time after the REAPER restart if you accepted the startup test.

local R = reaper
local RES = R.GetResourcePath()
local REPORT = RES .. "/LCRR_IEM_Spike_Report.txt"
local JSFX = RES .. "/Effects/LCRR_IEM_Spike_Tone.jsfx"
local STARTUP = RES .. "/Scripts/__startup.lua"
local HEART = RES .. "/Scripts/LCRR_IEM_Spike_Heartbeat.lua"
local MARKER = "-- LCRR-IEM-SPIKE (temporary)"
local TITLE = "LCRR IEM Spike"
local THRESHOLD = 0.001 -- the tone peaks at 0.01 (-40 dBFS)

local counts = { PASS = 0, FAIL = 0, INFO = 0, SKIP = 0 }
local lines = {}
local wake = 0
local ticks = 0
local sandbox = nil -- the empty project tab the tests run in; nothing is ever changed outside it

local function in_sandbox() return sandbox ~= nil and R.EnumProjects(-1) == sandbox end

-- Report ------------------------------------------------------------------------------------------------------------

local function log(status, id, detail)
  counts[status] = counts[status] + 1
  local line = string.format("%-5s %-30s %s\n", status, id, tostring(detail or ""))
  lines[#lines + 1] = line
  local f = io.open(REPORT, "a")
  if f then f:write(line); f:close() end
end

local function check(id, ok, detail) log(ok and "PASS" or "FAIL", id, detail) end
local function info(id, detail) log("INFO", id, detail) end

local function fresh_report()
  local f = assert(io.open(REPORT, "w"))
  f:write("LCRR IEM spike report, version 1\n")
  f:close()
end

-- Prompts and timing ------------------------------------------------------------------------------------------------

local function wait(seconds)
  wake = R.time_precise() + seconds
  coroutine.yield()
  if sandbox and not in_sandbox() then error("the project tab was switched during the test", 0) end
end

local function ok_cancel(text) return R.ShowMessageBox(text, TITLE, 1) == 1 end

local function ask(text)
  local a = R.ShowMessageBox(text .. "\n\nCancel = can't tell.", TITLE, 3)
  if a == 6 then return "yes" elseif a == 7 then return "no" end
  return "can't tell"
end

-- Tracks ------------------------------------------------------------------------------------------------------------

local function get(tr, key) return R.GetMediaTrackInfo_Value(tr, key) end
local function set(tr, key, value) return R.SetMediaTrackInfo_Value(tr, key, value) end
local function send_get(tr, cat, idx, key) return R.GetTrackSendInfo_Value(tr, cat, idx, key) end
local function send_set(tr, cat, idx, key, value) return R.SetTrackSendInfo_Value(tr, cat, idx, key, value) end

local function name_of(tr)
  local _, name = R.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
  return name
end

local function add(index, name)
  R.InsertTrackAtIndex(index, false)
  local tr = R.GetTrack(0, index)
  R.GetSetMediaTrackInfo_String(tr, "P_NAME", name, true)
  return tr
end

local function wipe()
  if not in_sandbox() then return end
  for i = R.CountTracks(0) - 1, 0, -1 do R.DeleteTrack(R.GetTrack(0, i)) end
end

local function order()
  local out = {}
  for i = 0, R.CountTracks(0) - 1 do
    local tr = R.GetTrack(0, i)
    out[#out + 1] = name_of(tr) .. "(" .. math.floor(get(tr, "I_FOLDERDEPTH")) .. ")"
  end
  return table.concat(out, " ")
end

-- Src A, Src B, Src C, IEMs (folder), IEM_One, IEM_Two
local function layout()
  local t = {}
  t.a = add(0, "Src A"); t.b = add(1, "Src B"); t.c = add(2, "Src C")
  t.folder = add(3, "IEMs"); t.one = add(4, "IEM_One"); t.two = add(5, "IEM_Two")
  set(t.folder, "I_FOLDERDEPTH", 1)
  set(t.two, "I_FOLDERDEPTH", -1)
  return t
end

local function send_to(src, dst, level)
  local idx = R.CreateTrackSend(src, dst)
  send_set(src, 0, idx, "I_SENDMODE", 3)
  send_set(src, 0, idx, "D_VOL", level or 1)
  return idx
end

local function same_track(a, b)
  if type(a) == "userdata" and type(b) == "userdata" then return R.GetTrackGUID(a) == R.GetTrackGUID(b) end
  return false
end

-- Sections ----------------------------------------------------------------------------------------------------------

local function section_environment()
  info("env.reaper", R.GetAppVersion())
  info("env.os", R.GetOS())
  info("env.date", os.date("%Y-%m-%d %H:%M:%S"))
  info("env.audio_running", R.Audio_IsRunning())
  info("env.outputs", R.GetNumAudioOutputs())
end

local function section_folder()
  local t = layout()
  check("folder.names", name_of(t.one) == "IEM_One", name_of(t.one))
  check("folder.order", order() == "Src A(0) Src B(0) Src C(0) IEMs(1) IEM_One(0) IEM_Two(-1)", order())
  check("folder.parent", same_track(R.GetParentTrack(t.one), t.folder) and same_track(R.GetParentTrack(t.two), t.folder))
  check("folder.guid", R.GetTrackGUID(t.one):match("^{.+}$") ~= nil, R.GetTrackGUID(t.one))

  local three = add(R.CountTracks(0), "IEM_Three")
  info("folder.append_raw", order() .. " | parent of new: " .. (R.GetParentTrack(three) and "folder" or "none"))
  set(t.two, "I_FOLDERDEPTH", 0)
  set(three, "I_FOLDERDEPTH", -1)
  check("folder.append_fixed", same_track(R.GetParentTrack(three), t.folder), order())

  R.DeleteTrack(three)
  info("folder.delete_last_child", order())
  set(t.two, "I_FOLDERDEPTH", -1)
  R.DeleteTrack(t.one)
  R.DeleteTrack(t.two)
  info("folder.emptied", order())
  local after = add(R.CountTracks(0), "After empty folder")
  info("folder.track_after_empty", order() .. " | parent of new: " .. (R.GetParentTrack(after) and "folder" or "none"))
end

local function section_sends()
  local t = layout()
  local idx = R.CreateTrackSend(t.a, t.one)
  check("send.create", idx >= 0, idx)
  info("send.defaults", string.format("mode=%s vol=%s pan=%s mute=%s src=%s dst=%s",
    send_get(t.a, 0, idx, "I_SENDMODE"), send_get(t.a, 0, idx, "D_VOL"), send_get(t.a, 0, idx, "D_PAN"),
    send_get(t.a, 0, idx, "B_MUTE"), send_get(t.a, 0, idx, "I_SRCCHAN"), send_get(t.a, 0, idx, "I_DSTCHAN")))
  send_set(t.a, 0, idx, "I_SENDMODE", 3)
  send_set(t.a, 0, idx, "D_VOL", 1)
  check("send.mode3", send_get(t.a, 0, idx, "I_SENDMODE") == 3, send_get(t.a, 0, idx, "I_SENDMODE"))
  check("send.receive_count", R.GetTrackNumSends(t.one, -1) == 1, R.GetTrackNumSends(t.one, -1))

  local src = send_get(t.one, -1, 0, "P_SRCTRACK")
  info("send.P_SRCTRACK_type", type(src))
  check("send.read_source", same_track(src, t.a), type(src))
  local dest = send_get(t.a, 0, idx, "P_DESTTRACK")
  check("send.read_dest", same_track(dest, t.one), type(dest))

  send_to(t.b, t.one); send_to(t.c, t.one)
  R.RemoveTrackSend(t.b, 0, 0)
  check("send.remove_middle", R.GetTrackNumSends(t.one, -1) == 2
    and same_track(send_get(t.one, -1, 1, "P_SRCTRACK"), t.c), R.GetTrackNumSends(t.one, -1))

  send_to(t.a, t.one)
  check("send.duplicate_pair", R.GetTrackNumSends(t.a, 0) == 2, R.GetTrackNumSends(t.a, 0))
  for i = R.GetTrackNumSends(t.a, 0) - 1, 0, -1 do R.RemoveTrackSend(t.a, 0, i) end
  check("send.remove_all_for_pair", R.GetTrackNumSends(t.a, 0) == 0, R.GetTrackNumSends(t.a, 0))

  -- RemoveTrackSend's help text says "category is 0 for hardware outputs"; its neighbours say >0 is hardware.
  local x = add(R.CountTracks(0), "Category test")
  send_to(x, t.two)
  R.CreateTrackSend(x, nil)
  R.RemoveTrackSend(x, 1, 0)
  local s1, h1 = R.GetTrackNumSends(x, 0), R.GetTrackNumSends(x, 1)
  check("remove.category1_hardware", s1 == 1 and h1 == 0, "sends=" .. s1 .. " hw=" .. h1)
  R.RemoveTrackSend(x, 0, 0)
  local s2, h2 = R.GetTrackNumSends(x, 0), R.GetTrackNumSends(x, 1)
  check("remove.category0_send", s2 == 0 and h2 == 0, "sends=" .. s2 .. " hw=" .. h2)

  local hw = R.CreateTrackSend(t.one, nil)
  check("hw.create", hw >= 0 and R.GetTrackNumSends(t.one, 1) == 1, hw)
  info("hw.defaults", string.format("mode=%s vol=%s src=%s dst=%s", send_get(t.one, 1, hw, "I_SENDMODE"),
    send_get(t.one, 1, hw, "D_VOL"), send_get(t.one, 1, hw, "I_SRCCHAN"), send_get(t.one, 1, hw, "I_DSTCHAN")))
  send_set(t.one, 1, hw, "I_DSTCHAN", 2)
  check("hw.stereo_dst", send_get(t.one, 1, hw, "I_DSTCHAN") == 2, send_get(t.one, 1, hw, "I_DSTCHAN"))
  send_set(t.one, 1, hw, "I_DSTCHAN", 2 | 1024)
  check("hw.mono_dst", send_get(t.one, 1, hw, "I_DSTCHAN") == (2 | 1024), send_get(t.one, 1, hw, "I_DSTCHAN"))
end

local function section_appearance()
  local t = layout()
  set(t.one, "B_MAINSEND", 0)
  check("track.mainsend_off", get(t.one, "B_MAINSEND") == 0, get(t.one, "B_MAINSEND"))
  local colour = R.ColorToNative(40, 120, 200) | 0x1000000
  set(t.one, "I_CUSTOMCOLOR", colour)
  check("track.colour", get(t.one, "I_CUSTOMCOLOR") == colour, get(t.one, "I_CUSTOMCOLOR"))
  R.SetProjExtState(0, "LCRR_IEM_SPIKE", "colour", "2878C8")
  local _, value = R.GetProjExtState(0, "LCRR_IEM_SPIKE", "colour")
  check("project.extstate", value == "2878C8", value)
  R.SetProjExtState(0, "LCRR_IEM_SPIKE", "", "")
end

local function section_move()
  local t = layout()
  send_to(t.a, t.one)
  local guid = R.GetTrackGUID(t.one)
  add(R.CountTracks(0), "Late")
  info("move.before", order())
  R.SetOnlyTrackSelected(t.folder)
  R.SetTrackSelected(t.one, true)
  R.SetTrackSelected(t.two, true)
  R.ReorderSelectedTracks(R.CountTracks(0), 0)
  check("move.to_end", order() == "Src A(0) Src B(0) Src C(0) Late(0) IEMs(1) IEM_One(0) IEM_Two(-1)", order())
  check("move.guid_stable", R.GetTrackGUID(t.one) == guid)
  check("move.send_kept", R.GetTrackNumSends(t.one, -1) == 1 and same_track(send_get(t.one, -1, 0, "P_SRCTRACK"), t.a))

  local stray = add(0, "IEM_Stray")
  R.SetOnlyTrackSelected(stray)
  R.ReorderSelectedTracks(R.CountTracks(0), 2)
  check("adopt.extends_folder", same_track(R.GetParentTrack(stray), t.folder), order())
end

local function section_undo()
  layout()
  local before = R.CountTracks(0)
  R.Undo_BeginBlock2(0)
  local mix = add(before, "IEM_Undo")
  R.CreateTrackSend(R.GetTrack(0, 0), mix)
  R.CreateTrackSend(mix, nil)
  R.Undo_EndBlock2(0, "LCRR spike create mix", -1)
  info("undo.label", R.Undo_CanUndo2(0))
  R.Undo_DoUndo2(0)
  check("undo.track_gone", R.CountTracks(0) == before, R.CountTracks(0))
  check("undo.send_gone", R.GetTrackNumSends(R.GetTrack(0, 0), 0) == 0, R.GetTrackNumSends(R.GetTrack(0, 0), 0))
end

local function channel_names()
  local out = {}
  for i = 0, R.GetNumAudioOutputs() - 1 do out[#out + 1] = (i + 1) .. "=" .. R.GetOutputChannelName(i) end
  return table.concat(out, ", ")
end

local function section_device()
  info("device.open.count", R.GetNumAudioOutputs())
  info("device.open.names", channel_names())
  if not ok_cancel("Next the script closes REAPER's audio device for a moment, to read channel names while it's closed.\n\nOK to continue, Cancel to skip.") then
    log("SKIP", "device.closed", "declined")
    return
  end
  R.Audio_Quit()
  wait(1.5)
  info("device.closed.running", R.Audio_IsRunning())
  info("device.closed.count", R.GetNumAudioOutputs())
  info("device.closed.names", channel_names())
  R.Audio_Init()
  wait(3)
  check("device.reopened", R.Audio_IsRunning() == 1, R.Audio_IsRunning())
end

local function write_tone()
  local f = assert(io.open(JSFX, "w"))
  f:write([[
desc:LCRR IEM Spike Tone
slider1:0<0,2,1{Both,Left only,Right only}>Channel
in_pin:none
out_pin:L
out_pin:R
@init
phase = 0;
@sample
s = sin(phase) * 0.01;
phase += 2 * $pi * 440 / srate;
phase > 2 * $pi ? phase -= 2 * $pi;
spl0 = slider1 == 2 ? 0 : s;
spl1 = slider1 == 1 ? 0 : s;
]])
  f:close()
end

local function add_tone(tr)
  local fx = R.TrackFX_AddByName(tr, "JS:LCRR_IEM_Spike_Tone.jsfx", false, -1)
  if fx < 0 then fx = R.TrackFX_AddByName(tr, "LCRR_IEM_Spike_Tone.jsfx", false, -1) end
  return fx
end

local function peak(tr)
  wait(1)
  local top = 0
  for _ = 1, 8 do
    top = math.max(top, R.Track_GetPeakInfo(tr, 0), R.Track_GetPeakInfo(tr, 1))
    wait(0.05)
  end
  return top
end

local function section_signal()
  if R.Audio_IsRunning() ~= 1 then log("SKIP", "signal", "audio device is not running"); return end
  local tone = add(0, "Tone")
  local folder = add(1, "IEMs")
  local one = add(2, "IEM_One")
  set(folder, "I_FOLDERDEPTH", 1)
  set(one, "I_FOLDERDEPTH", -1)
  local fx = add_tone(tone)
  check("signal.tone_loaded", fx >= 0, fx)
  if fx < 0 then return end
  set(tone, "B_MAINSEND", 0)
  local idx = send_to(tone, one)
  R.Main_OnCommand(1007, 0)
  local master = R.GetMasterTrack(0)

  local p = peak(tone)
  check("signal.tone_running", p > THRESHOLD, p)
  if p <= THRESHOLD then R.Main_OnCommand(1016, 0); return end

  local routes = {
    { "control_child1_folder1", 1, 1, true },
    { "child0_folder1", 0, 1, false },
    { "child1_folder0", 1, 0, false },
    { "child0_folder0_shipping", 0, 0, false },
  }
  for _, r in ipairs(routes) do
    set(one, "B_MAINSEND", r[2])
    set(folder, "B_MAINSEND", r[3])
    local m = peak(master)
    check("master." .. r[1], (m > THRESHOLD) == r[4], "master peak " .. m)
  end

  local function mix_gets(id, expected)
    local m = peak(one)
    check(id, (m > THRESHOLD) == expected, "mix peak " .. m)
  end
  mix_gets("mode3.fader_up", true)
  set(tone, "D_VOL", 0)
  mix_gets("mode3.survives_fader_down", true)
  send_set(tone, 0, idx, "I_SENDMODE", 0)
  mix_gets("mode0.follows_fader_down", false)
  set(tone, "D_VOL", 1)
  send_set(tone, 0, idx, "I_SENDMODE", 1)
  mix_gets("mode1.before_fx_is_silent", false)
  send_set(tone, 0, idx, "I_SENDMODE", 3)
  set(tone, "B_MUTE", 1)
  info("mode3.with_source_track_muted", "mix peak " .. peak(one))
  set(tone, "B_MUTE", 0)
  R.Main_OnCommand(1016, 0)
end

local function section_listen()
  if R.Audio_IsRunning() ~= 1 then log("SKIP", "listen", "audio device is not running"); return end
  local count = R.GetNumAudioOutputs()
  local ok, value = R.GetUserInputs(TITLE .. ": output to listen on", 1, "First output number (1 to " .. count .. ")", "1")
  local n = ok and tonumber(value) or nil
  if not n or n < 1 or n > count then log("SKIP", "listen", "no output chosen"); return end
  n = math.floor(n)
  if not ok_cancel("Listening test on output " .. n .. " and " .. (n + 1) .. ". The tone is quiet (-40 dBFS).\n\nTake in-ears out. Watch your interface's meters or listen at low volume.\n\nOK to continue, Cancel to skip.") then
    log("SKIP", "listen", "declined")
    return
  end
  local tone = add(0, "Tone")
  local one = add(1, "IEM_One")
  local fx = add_tone(tone)
  if fx < 0 then log("FAIL", "listen.tone_loaded", fx); return end
  set(tone, "B_MAINSEND", 0)
  set(one, "B_MAINSEND", 0)
  send_to(tone, one)
  local hw = R.CreateTrackSend(one, nil)
  send_set(one, 1, hw, "D_VOL", 1)
  R.Main_OnCommand(1007, 0)
  local d = n - 1
  local cases = {
    { "mono_stereo_source.left", 0, d | 1024, 1, n },
    { "mono_stereo_source.right", 0, d | 1024, 2, n },
    { "mono_mono_source.right", 1024, d | 1024, 2, n },
    { "stereo.left_on_first", 0, d, 1, n },
    { "stereo.left_on_second", 0, d, 1, n + 1 },
  }
  for _, c in ipairs(cases) do
    send_set(one, 1, hw, "I_SRCCHAN", c[2])
    send_set(one, 1, hw, "I_DSTCHAN", c[3])
    R.TrackFX_SetParam(tone, fx, 0, c[4])
    wait(0.5)
    info("listen." .. c[1], ask("Is there a tone on output " .. c[5] .. "?"))
  end
  R.Main_OnCommand(1016, 0)
end

local function section_monitor()
  if not ok_cancel("Monitor test. You need lcrr-monitor.html open on a phone or browser.\n\nOK to continue, Cancel to skip.") then
    log("SKIP", "monitor", "declined")
    return
  end
  local t = layout()
  send_to(t.a, t.one, 1); send_to(t.b, t.one, 0.5); send_to(t.c, t.one, 0.25)
  R.CreateTrackSend(t.one, nil)
  local level = function(tr) return R.GetTrackNumSends(tr, 0) > 0 and send_get(tr, 0, 0, "D_VOL") or -1 end

  if not ok_cancel("On the phone, open the mix 'One'. You should see Src A (0), Src B (-6) and Src C (-12).\n\nOK when it's showing.") then
    log("SKIP", "monitor", "mix not opened")
    return
  end
  ok_cancel("After OK the script removes Src B and waits 5 seconds. Watch the phone.")
  R.RemoveTrackSend(t.b, 0, 0)
  wait(5)
  info("monitor.removed_row_gone", ask("Did Src B's row disappear, leaving Src A (0) and Src C (-12)?"))

  ok_cancel("After OK you have 12 seconds: drag Src C's fader down a little and release.")
  wait(12)
  check("monitor.drag_hits_right_send", level(t.c) ~= 0.25 and level(t.a) == 1, "A=" .. level(t.a) .. " C=" .. level(t.c))

  local a_before = level(t.a)
  ok_cancel("After OK: straight away, press and hold Src C's fader and keep moving it for a full 12 seconds. The script removes Src C about 6 seconds in.")
  wait(6)
  R.RemoveTrackSend(t.c, 0, 0)
  wait(7)
  check("monitor.drag_during_removal_safe", level(t.a) == a_before, "A before=" .. a_before .. " after=" .. level(t.a))
  info("monitor.row_gone_during_drag", ask("Did Src C's row disappear, and Src A's level stay where it was?"))

  ok_cancel("After OK the script adds Src B back and waits 5 seconds.")
  send_to(t.b, t.one, 0.5)
  wait(5)
  info("monitor.added_row_appears", ask("Did Src B's row come back?"))

  ok_cancel("After OK the script renames the mix and waits 5 seconds.")
  R.GetSetMediaTrackInfo_String(t.one, "P_NAME", "IEM_Renamed", true)
  wait(5)
  info("monitor.rename_returns_to_list", ask("Did the phone go back to the mix list, now showing 'Renamed'?"))
end

local function heartbeat_changes(section, key)
  local first = R.GetExtState(section, key)
  wait(2)
  local second = R.GetExtState(section, key)
  return first ~= "" and first ~= second, first, second
end

local function section_background()
  local before = ticks
  local arrange = heartbeat_changes("LCRR_ARRANGE", "heartbeat")
  info("background.arrange_running", arrange)
  check("background.own_loop_runs", ticks - before > 10, (ticks - before) .. " ticks in 2 s")
end

-- The startup test --------------------------------------------------------------------------------------------------

local function read_all(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local text = f:read("a")
  f:close()
  return text
end

local function startup_has_marker()
  local text = read_all(STARTUP)
  return text ~= nil and text:find(MARKER, 1, true) ~= nil
end

local function offer_startup()
  if not ok_cancel("Last test: does a second background script start beside Arrange's bridge?\n\nThis adds one marked line to Scripts/__startup.lua. You then restart REAPER and run this script once more, which removes the line.\n\nOK to continue, Cancel to skip.") then
    log("SKIP", "startup", "declined")
    return false
  end
  local h = assert(io.open(HEART, "w"))
  h:write([[
local n = 0
local function loop()
  if reaper.GetExtState("LCRR_IEM_SPIKE", "stop") == "1" then return end
  n = n + 1
  reaper.SetExtState("LCRR_IEM_SPIKE", "heartbeat", tostring(n), false)
  reaper.defer(loop)
end
reaper.DeleteExtState("LCRR_IEM_SPIKE", "stop", false)
loop()
]])
  h:close()
  local text = read_all(STARTUP) or ""
  if text ~= "" and text:sub(-1) ~= "\n" then text = text .. "\n" end
  local line = 'do local p = reaper.GetResourcePath() .. "/Scripts/LCRR_IEM_Spike_Heartbeat.lua"; '
    .. 'local id = reaper.AddRemoveReaScript(true, 0, p, true); if id ~= 0 then reaper.Main_OnCommand(id, 0) end end '
    .. MARKER .. "\n"
  local f = assert(io.open(STARTUP, "w"))
  f:write(text .. line)
  f:close()
  info("startup.line_added", STARTUP)
  return true
end

local function part_b()
  log("INFO", "startup.part_b", os.date("%Y-%m-%d %H:%M:%S"))
  local own = heartbeat_changes("LCRR_IEM_SPIKE", "heartbeat")
  check("startup.second_script_runs", own)
  info("startup.arrange_also_running", heartbeat_changes("LCRR_ARRANGE", "heartbeat"))

  R.SetExtState("LCRR_IEM_SPIKE", "stop", "1", false)
  wait(0.5)
  local kept = {}
  for line in (read_all(STARTUP) or ""):gmatch("[^\n]*\n?") do
    if line ~= "" and not line:find(MARKER, 1, true) then kept[#kept + 1] = line end
  end
  local text = table.concat(kept)
  if text:match("%S") then
    local f = assert(io.open(STARTUP, "w"))
    f:write(text)
    f:close()
  else
    os.remove(STARTUP)
  end
  R.AddRemoveReaScript(false, 0, HEART, true)
  os.remove(HEART)
  R.DeleteExtState("LCRR_IEM_SPIKE", "heartbeat", false)
  R.DeleteExtState("LCRR_IEM_SPIKE", "stop", false)
  check("startup.line_removed", not startup_has_marker())
end

-- Running -----------------------------------------------------------------------------------------------------------

local cleaned = false
local function cleanup()
  if cleaned or not sandbox then return end
  cleaned = true
  if in_sandbox() then R.Main_OnCommand(1016, 0) end
  wipe()
  os.remove(JSFX)
end

local function run(name, fn)
  if not in_sandbox() then log("SKIP", name, "the project tab was switched"); return end
  local ok, err = pcall(fn)
  if not ok then log("FAIL", "crash." .. name, err) end
  if in_sandbox() then R.Main_OnCommand(1016, 0) end
  wipe()
end

local function finish(extra)
  R.ShowConsoleMsg("\n" .. table.concat(lines) .. "\n")
  R.ShowMessageBox(string.format("PASS %d, FAIL %d, INFO %d, SKIP %d\n\nReport: %s\n\n%s",
    counts.PASS, counts.FAIL, counts.INFO, counts.SKIP, REPORT, extra), TITLE, 0)
end

local function part_a()
  local project, path = R.EnumProjects(-1)
  if R.CountTracks(0) ~= 0 or (path or "") ~= "" then
    R.ShowMessageBox("Open a new, empty project tab first and run this there.\n\nThis script creates and deletes tracks, so it refuses a project that has tracks or has been saved.", TITLE, 0)
    return
  end
  if not ok_cancel("This runs under a minute of automatic checks, then some questions that need your ears and a phone.\n\nOK to start. Stay on this project tab until it finishes.") then
    return
  end
  sandbox = project
  fresh_report()
  write_tone()
  run("environment", section_environment)
  run("folder", section_folder)
  run("sends", section_sends)
  run("appearance", section_appearance)
  run("move", section_move)
  run("undo", section_undo)
  run("device", section_device)
  run("signal", section_signal)
  run("listen", section_listen)
  run("monitor", section_monitor)
  run("background", section_background)
  local again = offer_startup()
  cleanup()
  finish(again and "Now restart REAPER (no need to save this tab) and run this script again." or "Close this project tab without saving.")
end

local function main()
  if startup_has_marker() then
    local ok, err = pcall(part_b)
    if not ok then log("FAIL", "crash.part_b", err) end
    finish("All done. The temporary files and the startup line are gone.")
  else
    part_a()
  end
end

local co = coroutine.create(main)
local function tick()
  ticks = ticks + 1
  if R.time_precise() >= wake then
    local ok, err = coroutine.resume(co)
    if not ok then
      log("FAIL", "crash.main", err)
      cleanup()
      finish("The script stopped early. Close this project tab without saving.")
      return
    end
  end
  if coroutine.status(co) ~= "dead" then R.defer(tick) end
end

R.atexit(cleanup)
tick()
