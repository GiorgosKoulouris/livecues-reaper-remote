-- The `state` core: what the page needs to start. Read-only and headless, as every core is (Arrange ADR-0008): no
-- dialogs, codes and fields only. The project's name and path are added to every reply by lib/bridge/service.lua, so
-- this slice has nothing of its own to report yet; later commands (list, save, restore) add theirs.
--
--   local result = state.run({ api = reaper })

local state = {}

--- @param _ table { api }
--- @return table { status = "ok" }
function state.run(_)
  return { status = "ok" }
end

return state
