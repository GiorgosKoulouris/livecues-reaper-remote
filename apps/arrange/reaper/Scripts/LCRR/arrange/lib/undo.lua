-- Undo blocking.
--
-- One Undo_BeginBlock/Undo_EndBlock per run, and an empty plan creates no undo
-- point at all (CLAUDE.md, Undo convention). Scripts here run immediately with
-- no confirmation prompt, so a clean single-step undo is half the safety net --
-- the logged plan is the other half.

local undo = {}

--- Run an applier inside one undo block.
-- @param opts table
--   api          the `reaper` table (injected so specs can record calls)
--   description  string label for the undo point, shown in REAPER's undo history
--   apply        function performing the mutations
--   skip         boolean; when true nothing runs and no undo point is created
-- @return any whatever `apply` returned
function undo.run(opts)
  if opts.skip then
    return nil
  end

  opts.api.Undo_BeginBlock()

  -- The block must close even on error: an open block would absorb the user's
  -- next edit into our undo point, so a failed run would become unundoable.
  local ok, result = pcall(opts.apply)

  -- -1 sets all undo flags, so the point captures whatever the applier touched.
  opts.api.Undo_EndBlock(opts.description, -1)

  if not ok then
    error(result, 0)
  end
  return result
end

return undo
