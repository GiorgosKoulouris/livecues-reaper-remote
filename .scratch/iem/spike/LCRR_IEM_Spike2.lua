-- @description LCRR IEM Spike 2: retest undo blocks and mono output (throwaway, issue 01)
-- @author LCRR
-- @version 1
--
-- Run only in a new, empty, unsaved project tab: it refuses anything else.
-- Writes <resource path>/LCRR_IEM_Spike2_Report.txt and repeats it in the console.

local R = reaper
local RES = R.GetResourcePath()
local REPORT = RES .. "/LCRR_IEM_Spike2_Report.txt"
local JSFX = RES .. "/Effects/LCRR_IEM_Spike_Tone.jsfx"
local TITLE = "LCRR IEM Spike 2"

local lines = {}
local wake = 0
local sandbox = nil

local function in_sandbox() return sandbox ~= nil and R.EnumProjects(-1) == sandbox end

local function log(status, id, detail)
  local line = string.format("%-5s %-30s %s\n", status, id, tostring(detail or ""))
  lines[#lines + 1] = line
  local f = io.open(REPORT, "a")
  if f then f:write(line); f:close() end
end
local function check(id, ok, detail) log(ok and "PASS" or "FAIL", id, detail) end

local function wait(seconds)
  wake = R.time_precise() + seconds
  coroutine.yield()
  if not in_sandbox() then error("the project tab was switched during the test", 0) end
end

local function ok_cancel(text) return R.ShowMessageBox(text, TITLE, 1) == 1 end
local function ask(text)
  local a = R.ShowMessageBox(text .. "\n\nCancel = can't tell.", TITLE, 3)
  if a == 6 then return "yes" elseif a == 7 then return "no" end
  return "can't tell"
end

local function get(tr, key) return R.GetMediaTrackInfo_Value(tr, key) end
local function set(tr, key, value) return R.SetMediaTrackInfo_Value(tr, key, value) end

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

local function order()
  local out = {}
  for i = 0, R.CountTracks(0) - 1 do
    local tr = R.GetTrack(0, i)
    out[#out + 1] = name_of(tr) .. "(" .. math.floor(get(tr, "I_FOLDERDEPTH")) .. ")"
  end
  return table.concat(out, " ")
end

local function wipe()
  if not in_sandbox() then return end
  for i = R.CountTracks(0) - 1, 0, -1 do R.DeleteTrack(R.GetTrack(0, i)) end
end

local function block(label, fn)
  R.Undo_BeginBlock2(0)
  fn()
  R.Undo_EndBlock2(0, label, -1)
end

-- Every change here is inside a block, so REAPER's snapshots stay current.
local function section_undo()
  block("spike baseline", function()
    local stray = add(0, "IEM_Stray")
    local a = add(1, "Src A")
    local folder = add(2, "IEMs")
    add(3, "IEM_One")
    local two = add(4, "IEM_Two")
    set(folder, "I_FOLDERDEPTH", 1)
    set(two, "I_FOLDERDEPTH", -1)
    R.CreateTrackSend(a, stray)
  end)
  local baseline = order()
  log("INFO", "undo.baseline", baseline)

  -- Adopt: reorder, master send, colour and send mode as one operation.
  block("spike adopt", function()
    local stray = R.GetTrack(0, 0)
    R.SetOnlyTrackSelected(stray)
    R.ReorderSelectedTracks(R.CountTracks(0), 2)
    set(stray, "B_MAINSEND", 0)
    set(stray, "I_CUSTOMCOLOR", R.ColorToNative(40, 120, 200) | 0x1000000)
    R.SetTrackSendInfo_Value(stray, -1, 0, "I_SENDMODE", 3)
  end)
  log("INFO", "undo.adopt.applied", order())
  check("undo.adopt.top_entry", R.Undo_CanUndo2(0) == "spike adopt", R.Undo_CanUndo2(0))
  R.Undo_DoUndo2(0)
  check("undo.adopt.order_restored", order() == baseline, order())
  local stray = R.GetTrack(0, 0)
  check("undo.adopt.mainsend_restored", get(stray, "B_MAINSEND") == 1, get(stray, "B_MAINSEND"))
  check("undo.adopt.mode_restored", R.GetTrackSendInfo_Value(stray, -1, 0, "I_SENDMODE") == 0,
    R.GetTrackSendInfo_Value(stray, -1, 0, "I_SENDMODE"))
  check("undo.adopt.one_step_only", R.Undo_CanUndo2(0) == "spike baseline", R.Undo_CanUndo2(0))

  -- Create: a track, a send and a hardware output.
  local before = R.CountTracks(0)
  block("spike create", function()
    local mix = add(before, "IEM_New")
    R.CreateTrackSend(R.GetTrack(0, 1), mix)
    R.CreateTrackSend(mix, nil)
  end)
  R.Undo_DoUndo2(0)
  check("undo.create.track_gone", R.CountTracks(0) == before, R.CountTracks(0))
  check("undo.create.send_gone", R.GetTrackNumSends(R.GetTrack(0, 1), 0) == 0, R.GetTrackNumSends(R.GetTrack(0, 1), 0))

  -- Delete the last child and repair the folder depth by hand.
  block("spike delete", function()
    local n = R.CountTracks(0)
    R.DeleteTrack(R.GetTrack(0, n - 1))
    set(R.GetTrack(0, n - 2), "I_FOLDERDEPTH", -1)
  end)
  log("INFO", "undo.delete.applied", order())
  R.Undo_DoUndo2(0)
  check("undo.delete.restored", order() == baseline, order())
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

local function section_listen()
  if R.Audio_IsRunning() ~= 1 then log("SKIP", "listen", "audio device is not running"); return end
  if not ok_cancel("Listening test on outputs 1 and 2. The tone is quiet (-40 dBFS).\n\nYou must be able to tell output 1 from output 2: use per-channel output meters on your interface or in its software, or headphones with one side on each output. Laptop speakers or a mono path won't work.\n\nOK to continue, Cancel to skip.") then
    log("SKIP", "listen", "declined")
    return
  end
  local tone = add(0, "Tone")
  local one = add(1, "IEM_One")
  local fx = R.TrackFX_AddByName(tone, "JS:LCRR_IEM_Spike_Tone.jsfx", false, -1)
  if fx < 0 then log("FAIL", "listen.tone_loaded", fx); return end
  set(tone, "B_MAINSEND", 0)
  set(one, "B_MAINSEND", 0)
  local idx = R.CreateTrackSend(tone, one)
  R.SetTrackSendInfo_Value(tone, 0, idx, "I_SENDMODE", 3)
  local hw = R.CreateTrackSend(one, nil)
  R.Main_OnCommand(1007, 0)

  local function case(id, dst, slider, output)
    R.SetTrackSendInfo_Value(one, 1, hw, "I_SRCCHAN", 0)
    R.SetTrackSendInfo_Value(one, 1, hw, "I_DSTCHAN", dst)
    R.TrackFX_SetParam(tone, fx, 0, slider)
    wait(0.5)
    local answer = ask("Is there a tone on output " .. output .. "?")
    log("INFO", "listen." .. id, answer)
    return answer
  end

  local control = case("control.left_on_output2", 0, 1, 2)
  if control ~= "no" then
    log("INFO", "listen.separation", "cannot tell the outputs apart; mono cases not asked")
    return
  end
  case("control.left_on_output1", 0, 1, 1)
  case("mono.left_on_output1", 1024, 1, 1)
  case("mono.right_on_output1", 1024, 2, 1)
  case("mono.left_on_output2", 1024, 1, 2)
  case("mono.right_on_output2", 1024, 2, 2)
end

local function run(name, fn)
  if not in_sandbox() then log("SKIP", name, "the project tab was switched"); return end
  local ok, err = pcall(fn)
  if not ok then log("FAIL", "crash." .. name, err) end
  if in_sandbox() then R.Main_OnCommand(1016, 0) end
  wipe()
end

local cleaned = false
local function cleanup()
  if cleaned or not sandbox then return end
  cleaned = true
  if in_sandbox() then R.Main_OnCommand(1016, 0) end
  wipe()
  os.remove(JSFX)
end

local function finish()
  cleanup()
  R.ShowConsoleMsg("\n" .. table.concat(lines) .. "\n")
  R.ShowMessageBox("Done.\n\nReport: " .. REPORT .. "\n\nClose this project tab without saving.", TITLE, 0)
end

local function main()
  local project, path = R.EnumProjects(-1)
  if R.CountTracks(0) ~= 0 or (path or "") ~= "" then
    R.ShowMessageBox("Open a new, empty project tab first and run this there.", TITLE, 0)
    return
  end
  if not ok_cancel("About a minute: automatic undo checks, then a few listening questions.\n\nOK to start. Stay on this project tab until it finishes.") then return end
  sandbox = project
  local f = assert(io.open(REPORT, "w"))
  f:write("LCRR IEM spike 2 report, version 1\n")
  f:close()
  log("INFO", "env.reaper", R.GetAppVersion())
  write_tone()
  run("undo", section_undo)
  run("listen", section_listen)
  finish()
end

local co = coroutine.create(main)
local function tick()
  if R.time_precise() >= wake then
    local ok, err = coroutine.resume(co)
    if not ok then
      log("FAIL", "crash.main", err)
      finish()
      return
    end
  end
  if coroutine.status(co) ~= "dead" then R.defer(tick) end
end

R.atexit(cleanup)
tick()
