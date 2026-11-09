-- A recording stand-in for the `reaper` table.
--
-- `lib/` never reaches for the global `reaper` directly; the modules that touch
-- the API take it as an injected dependency (see ADR-0001 -- appliers are the
-- only reaper.* callers, and they stay small enough to fake wholesale). This
-- records every call in order so specs can assert on the sequence, which is
-- what matters for undo blocks.

local fake_reaper = {}

function fake_reaper.new(overrides)
  local calls = {}

  local api = {
    calls = calls,

    -- Return the calls made to one function, in order.
    calls_to = function(name)
      local matches = {}
      for _, call in ipairs(calls) do
        if call.name == name then
          matches[#matches + 1] = call
        end
      end
      return matches
    end,

    -- The ordered list of function names, for asserting call sequence.
    call_names = function()
      local names = {}
      for index, call in ipairs(calls) do
        names[index] = call.name
      end
      return names
    end,
  }

  local function record(name, result)
    api[name] = function(...)
      calls[#calls + 1] = { name = name, args = table.pack(...) }
      if type(result) == "function" then
        return result(...)
      end
      return result
    end
  end

  record("Undo_BeginBlock")
  record("Undo_EndBlock")
  record("ShowConsoleMsg")
  record("ShowMessageBox", 0)

  for name, result in pairs(overrides or {}) do
    record(name, result)
  end

  return api
end

return fake_reaper
