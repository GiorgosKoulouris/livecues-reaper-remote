-- An environment for driving a lib/core/ module the way a front end does,
-- with nothing of REAPER's behind it.
--
-- `core_env.new(options)` returns `given, world`: hand `given` to a core, and
-- read `world` afterwards. `world.events` is one ordered list of what reached
-- the outside -- undo calls, applier calls, console writes, files written --
-- so a spec can ask both what happened and in which order. `world.files` is
-- the file system after the run.
--
--   options.snapshots   list of snapshots, returned in turn
--   options.files       map path -> content before the run
--   options.unwritable  set of paths that refuse to open for writing
--   options.tempo       tempo oracle (default: 2 s bars)
--   options.automation  automation oracle (default: 0.5 everywhere)
--   options.api         extra reaper functions, as for fake_reaper.new

local fake_reaper = require("spec.support.fake_reaper")
local harness = require("spec.support.script_harness")

local core_env = {}

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

function core_env.new(options)
  options = options or {}
  local world = { events = {}, files = copy(options.files or {}), snapshots_taken = 0 }
  local function record(event)
    world.events[#world.events + 1] = event
  end

  local overrides = {
    Undo_BeginBlock = function() record("undo begin") end,
    Undo_EndBlock = function(description) record("undo end " .. description) end,
    ShowConsoleMsg = function(text) record({ console = text }) end,
    ShowMessageBox = function() error("a core opened a dialog") end,
    GetUserInputs = function() error("a core opened a dialog") end,
    GetUserFileNameForRead = function() error("a core opened a dialog") end,
  }
  for name, value in pairs(options.api or {}) do
    overrides[name] = value
  end
  local api = fake_reaper.new(overrides)

  local unwritable = options.unwritable or {}
  local function open(path, mode)
    mode = mode or "r"
    if mode:sub(1, 1) == "r" then
      local content = world.files[path]
      if content == nil then
        return nil, path .. ": No such file or directory"
      end
      return { read = function() return content end, close = function() end }
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
        world.files[path] = mode:sub(1, 1) == "a" and (world.files[path] or "") .. text or text
        record("write " .. path)
      end,
    }
  end

  local applier = setmetatable({}, {
    __index = function(_, name)
      return function(called_with, value)
        assert(called_with == api, "applier called with something other than the api")
        record({ apply = name, value = value })
      end
    end,
  })

  local snapshots = options.snapshots or {}
  local given = {
    api = api,
    snapshot = function()
      world.snapshots_taken = world.snapshots_taken + 1
      return copy(snapshots[math.min(world.snapshots_taken, #snapshots)])
    end,
    tempo = options.tempo or harness.even_grid(2, 200),
    automation = options.automation or { value_at = function() return 0.5 end },
    applier = applier,
    open = open,
    clock = function() return "2026-11-07 12:00:00" end,
  }

  --- The events as short labels, for asserting order.
  function world.labels()
    local labels = {}
    for _, event in ipairs(world.events) do
      if type(event) == "string" then
        labels[#labels + 1] = event
      elseif event.console then
        labels[#labels + 1] = "console"
      else
        labels[#labels + 1] = "apply." .. event.apply
      end
    end
    return labels
  end

  --- Whether anything at all reached the outside.
  function world.untouched()
    return #world.events == 0
  end

  return given, world
end

return core_env
