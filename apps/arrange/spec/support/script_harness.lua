-- Runs an LCRR_Arrange_*.lua entry script, start to finish, against a scripted
-- stand-in for REAPER, and returns everything it did as one transcript.
--
-- This is what pins the dialog front ends' behaviour (spec/dialog_spec.lua):
-- every dialog with its text and the answer it got, every console write,
-- every undo call, every file written and what was in it, and the exact
-- snapshot, plan and anchors handed to the applier. The scripts are loaded as
-- REAPER loads them, from their files, with `reaper` as a global.
--
-- The boundary is drawn where REAPER's own state is read or written:
--
--   * `lib.project`'s `snapshot` returns the scenario's snapshots in turn (a
--     run re-reads after phase 1), so no `.RPP` reader is needed.
--   * `lib.tempo_oracle` and `lib.automation_oracle` return the scenario's
--     oracles. A grid oracle is provided below.
--   * `lib.apply` records each call and its arguments instead of writing.
--   * `io.open` is a small in-memory file system, and `os.date` is fixed.
--
-- Everything between those points -- planners, report, validate, sidecar,
-- log, undo, and the scripts themselves -- is the real code.

local harness = {}

local SCRIPT_DIR = "reaper/Scripts/LCRR/arrange/"

-- A deterministic rendering of a Lua value: keys sorted, floats at a fixed
-- precision, so two runs of the same plan print identically.
local function dump(value, indent)
  indent = indent or ""
  local kind = type(value)
  if kind == "number" then
    if math.type(value) == "integer" then
      return tostring(value)
    end
    return ("%.10g"):format(value)
  elseif kind == "string" then
    return ("%q"):format(value)
  elseif kind ~= "table" then
    return tostring(value)
  end

  local keys = {}
  for key in pairs(value) do
    keys[#keys + 1] = key
  end
  if #keys == 0 then
    return "{}"
  end
  table.sort(keys, function(a, b)
    local ta, tb = type(a), type(b)
    if ta ~= tb then
      return ta < tb
    end
    return a < b
  end)

  local inner = indent .. "  "
  local out = { "{" }
  for _, key in ipairs(keys) do
    local label = type(key) == "string" and key or ("[" .. tostring(key) .. "]")
    out[#out + 1] = ("%s%s = %s,"):format(inner, label, dump(value[key], inner))
  end
  out[#out + 1] = indent .. "}"
  return table.concat(out, "\n")
end
harness.dump = dump

local function copy(value)
  if type(value) ~= "table" then
    return value
  end
  local out = {}
  for key, entry in pairs(value) do
    out[key] = copy(entry)
  end
  return out
end

--- A tempo oracle over an explicit list of bar lines, with every call the
--- planner, report and diagnostics make.
-- @param lines sorted bar-line times
-- @param tempo_at function(time) -> bpm, num, denom
function harness.grid_oracle(lines, tempo_at)
  local tolerance = 1e-4
  local function next_bar_at_or_after(time)
    for _, line in ipairs(lines) do
      if line - time > -tolerance then
        return line
      end
    end
    error("grid does not reach " .. time)
  end
  local function bar_at_or_before(time)
    local found = lines[1]
    for _, line in ipairs(lines) do
      if line <= time + tolerance then
        found = line
      end
    end
    return found
  end
  local function bar_after(time)
    for _, line in ipairs(lines) do
      if line > time + tolerance then
        return line
      end
    end
    error("grid does not reach past " .. time)
  end
  return {
    next_bar_at_or_after = next_bar_at_or_after,
    bar_at_or_before = bar_at_or_before,
    bar_after = bar_after,
    tempo_at = tempo_at or function() return 120, 4, 4 end,
  }
end

--- Bar lines every `step` seconds from 0 to `last`.
function harness.even_grid(step, last, tempo_at)
  local lines = {}
  for index = 0, math.floor(last / step) do
    lines[#lines + 1] = index * step
  end
  return harness.grid_oracle(lines, tempo_at)
end

-- An in-memory io.open. Reads see the scenario's files; writes and appends
-- update them and are recorded when the handle closes.
local function file_system(files, unwritable, record)
  return function(path, mode)
    mode = mode or "r"
    if mode:sub(1, 1) == "r" then
      local content = files[path]
      if content == nil then
        return nil, path .. ": No such file or directory"
      end
      return {
        read = function(_, _) return content end,
        close = function() end,
      }
    end
    if unwritable[path] then
      return nil, path .. ": Permission denied"
    end
    local buffer = {}
    return {
      write = function(self, text)
        buffer[#buffer + 1] = text
        return self
      end,
      close = function()
        local text = table.concat(buffer)
        if mode:sub(1, 1) == "a" then
          files[path] = (files[path] or "") .. text
        else
          files[path] = text
        end
        record(("file %s (%s) <<\n%s>>"):format(path, mode, text))
      end,
    }
  end
end

--- Run one entry script against a scenario.
-- @param script string e.g. "LCRR_Arrange_Apply.lua"
-- @param scenario table
--   snapshots  list of snapshots, returned in turn by project.snapshot
--   tempo      tempo oracle (default: 2 s bars to 200 s)
--   automation automation oracle (default: 0.5 everywhere)
--   files      map path -> content, the file system before the run
--   unwritable set of paths whose open-for-write fails
--   applier_fails map applier name -> message: that applier call raises it
--   answers    { ShowMessageBox = {...}, GetUserInputs = { {ok, text}, ... },
--                GetUserFileNameForRead = { {ok, path}, ... } }
--   tracks     list of { name, mode } for the timebase diagnostic
--   origin_measure value TimeMap2_timeToBeats reports for time 0
-- @return string transcript
function harness.run(script, scenario)
  local events = {}
  local function record(text)
    events[#events + 1] = text
  end

  local answers = copy(scenario.answers or {})
  local function next_answer(name, default)
    local queue = answers[name]
    if queue and #queue > 0 then
      return table.remove(queue, 1)
    end
    return default
  end

  local reaper = {
    get_action_context = function()
      return false, "/resource/Scripts/LCRR/arrange/" .. script, 0, 0, 0, 0, 0
    end,
    ShowMessageBox = function(message, title, kind)
      local answer = next_answer("ShowMessageBox", 1)
      record(("ShowMessageBox(%q, %d) -> %s <<\n%s\n>>"):format(title, kind, answer, message))
      return answer
    end,
    ShowConsoleMsg = function(text)
      record(("ShowConsoleMsg <<\n%s>>"):format(text))
    end,
    GetUserInputs = function(title, count, captions, defaults)
      local answer = next_answer("GetUserInputs", { false, "" })
      record(("GetUserInputs(%q, %d, %q, %q) -> %s, %q"):format(
        title, count, captions, defaults, tostring(answer[1]), answer[2]))
      return answer[1], answer[2]
    end,
    GetUserFileNameForRead = function(initial, title, extension)
      local answer = next_answer("GetUserFileNameForRead", { false, "" })
      record(("GetUserFileNameForRead(%q, %q, %q) -> %s, %q"):format(
        initial, title, extension, tostring(answer[1]), answer[2]))
      return answer[1], answer[2]
    end,
    Undo_BeginBlock = function()
      record("Undo_BeginBlock()")
    end,
    Undo_EndBlock = function(description, flags)
      record(("Undo_EndBlock(%q, %d)"):format(description, flags))
    end,
    CountTracks = function()
      return #(scenario.tracks or {})
    end,
    GetTrack = function(_, index)
      return (scenario.tracks or {})[index + 1]
    end,
    GetMediaTrackInfo_Value = function(track, key)
      assert(key == "C_BEATATTACHMODE", key)
      return track.mode
    end,
    GetSetMediaTrackInfo_String = function(track, key)
      assert(key == "P_NAME", key)
      return true, track.name
    end,
    TimeMap2_timeToBeats = function(_, time)
      assert(time == 0)
      return 0, scenario.origin_measure or 0, 0, 0, 4
    end,
  }
  setmetatable(reaper, {
    __index = function(_, name)
      error("unexpected reaper." .. tostring(name), 2)
    end,
  })

  local snapshots = scenario.snapshots or {}
  local snapshot_index = 0
  local real_project = require("lib.project")
  local project_stub = setmetatable({
    snapshot = function(api)
      assert(api == reaper, "snapshot taken through something other than the reaper API")
      snapshot_index = snapshot_index + 1
      local taken = snapshots[math.min(snapshot_index, #snapshots)]
      assert(taken, "scenario has no snapshot")
      record(("project.snapshot() #%d"):format(snapshot_index))
      return copy(taken)
    end,
  }, { __index = real_project })

  local tempo = scenario.tempo or harness.even_grid(2, 200)
  local automation = scenario.automation or { value_at = function() return 0.5 end }

  local apply_stub = setmetatable({}, {
    __index = function(_, name)
      return function(api, value)
        assert(api == reaper, "applier called with something other than the reaper API")
        record(("apply.%s %s"):format(name, dump(value)))
        local failure = (scenario.applier_fails or {})[name]
        if failure then
          error(failure, 0)
        end
      end
    end,
  })

  -- Swap the boundary modules in, and make every other lib module reload so it
  -- binds to them. Restored afterwards, so other specs see the real modules.
  local saved_loaded = {}
  for name, module in pairs(package.loaded) do
    if name:match("^lib%.") then
      saved_loaded[name] = module
      package.loaded[name] = nil
    end
  end
  package.loaded["lib.project"] = project_stub
  package.loaded["lib.tempo_oracle"] = { new = function() return tempo end }
  package.loaded["lib.automation_oracle"] = { new = function() return automation end }
  package.loaded["lib.apply"] = apply_stub

  local files = copy(scenario.files or {})
  local saved_open, saved_date, saved_path = io.open, os.date, package.path
  local saved_reaper = rawget(_G, "reaper")
  io.open = file_system(files, scenario.unwritable or {}, record) -- luacheck: ignore 122
  os.date = function() return "2026-11-07 12:00:00" end -- luacheck: ignore 122
  _G.reaper = reaper

  local chunk = assert(loadfile(SCRIPT_DIR .. script))
  local ok, err = pcall(chunk)

  io.open, os.date, package.path = saved_open, saved_date, saved_path -- luacheck: ignore 122
  _G.reaper = saved_reaper
  for name in pairs(package.loaded) do
    if name:match("^lib%.") then
      package.loaded[name] = nil
    end
  end
  for name, module in pairs(saved_loaded) do
    package.loaded[name] = module
  end

  if not ok then
    record("ERROR " .. tostring(err))
  end
  return table.concat(events, "\n") .. "\n"
end

return harness
