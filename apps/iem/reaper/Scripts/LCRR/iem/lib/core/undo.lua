-- One undo step per operation. Every project change a core makes runs inside
-- `undo.run` (suite CONTEXT.md: changes made outside a block are not a step of
-- their own and are lost with the next undo). A core decides whether to refuse
-- *before* calling this, so a refusal leaves no undo point.

local undo = {}

--- @param api table the `reaper` table
--- @param description string shown in REAPER's undo history
--- @param apply function the whole change
--- @return any whatever `apply` returned
function undo.run(api, description, apply)
  api.Undo_BeginBlock2(0)
  api.PreventUIRefresh(1)
  local ok, result = pcall(apply)
  api.PreventUIRefresh(-1)
  -- Close the block even on error: an open one would swallow the user's next edit.
  api.Undo_EndBlock2(0, description, -1)
  api.TrackList_AdjustWindows(false)
  api.UpdateArrange()
  if not ok then error(result, 0) end
  return result
end

return undo
