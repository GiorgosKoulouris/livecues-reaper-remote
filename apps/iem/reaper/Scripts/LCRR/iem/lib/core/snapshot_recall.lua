-- The `snapshot_recall` core: write a saved snapshot back to the project, for the whole band or one mix, in ONE undo
-- step (unlike save, overwrite and delete, which touch project ExtState and so cannot be undone).
--
--   snapshot_recall.run({ api, fields = { name, mix = <mix GUID, optional> } })
--     -> { status = "ok", name, mixes, sends, skipped, missing }
--      | refused: `empty_name`, `bad_name`, `name_too_long`, `not_found` (no such snapshot), `unreadable` (the index
--        or the snapshot's contents cannot be read), `track_gone` / `not_a_mix` (`mix` is not a mix now),
--        `mix_not_saved` (`mix` is a mix but the snapshot holds nothing for it)
--
-- Each stored send's level, pan and mute are written back to the receive on its mix from the same source, and each
-- mix's master level to its first hardware output, all matched by GUID. A stored send that no longer has a receive
-- (its source or its mix is gone, or the pair is no longer routed) is skipped and counted in `skipped`, and so is a
-- stored master level whose mix has no hardware output now; a mix that is gone counts in `missing` (and its sends in
-- `skipped`). A send added since the save is not in the snapshot and is left
-- alone, and so is every mix outside a one-mix recall. Two sends from one source to one mix are matched in order.
-- `mixes` and `sends` count what was written. Nothing is written, and no undo step made, when that is nothing.
-- Refusals are decided before anything is written. A drag on another page keeps writing while this runs: the last
-- write wins, and the page shows the result on its next read.

local tracks = require("lib.core.tracks")
local undo = require("lib.core.undo")
local store = require("lib.core.snapshot_store")

local snapshot_recall = {}

-- The receive indexes of a mix track by source GUID, in REAPER's order.
local function receives_by_source(api, track)
  local found = {}
  for index = 0, api.GetTrackNumSends(track, -1) - 1 do
    local guid = api.GetTrackGUID(api.GetTrackSendInfo_Value(track, -1, index, "P_SRCTRACK"))
    found[guid] = found[guid] or {}
    table.insert(found[guid], index)
  end
  return found
end

-- What a recall would write, decided before the undo block opens: { writes = { { track, index, send } },
-- masters = { { track, value } }, mixes, skipped, missing }.
local function plan(api, list, saved_mixes)
  local result = { writes = {}, masters = {}, mixes = 0, skipped = 0, missing = 0 }
  for _, saved in ipairs(saved_mixes) do
    local entry = tracks.find_by_guid(list, saved.guid)
    if not entry or not tracks.is_mix_name(entry.name) then
      result.missing = result.missing + 1
      result.skipped = result.skipped + #saved.sends
    else
      local touched = false
      local queues = receives_by_source(api, entry.track)
      for _, send in ipairs(saved.sends) do
        local queue = queues[send.source]
        local index = queue and table.remove(queue, 1)
        if index then
          result.writes[#result.writes + 1] = { track = entry.track, index = index, send = send }
          touched = true
        else
          result.skipped = result.skipped + 1
        end
      end
      if saved.master then
        if api.GetTrackNumSends(entry.track, 1) > 0 then
          result.masters[#result.masters + 1] = { track = entry.track, value = saved.master }
          touched = true
        else
          result.skipped = result.skipped + 1
        end
      end
      if touched then result.mixes = result.mixes + 1 end
    end
  end
  return result
end

function snapshot_recall.run(given)
  local api, fields = given.api, given.fields or {}
  local name, code = store.clean_name(fields.name)
  if not name then return tracks.refusal(code) end
  local index, bad = store.list(api)
  if not index then return tracks.refusal(bad) end
  local entry = store.find(index, name)
  if not entry then return tracks.refusal("not_found") end
  local contents, unreadable = store.read(api, entry)
  if not contents then return tracks.refusal(unreadable) end

  local list = tracks.scan(api)
  local saved_mixes = contents.mixes
  if fields.mix and fields.mix ~= "" then
    local mix, why = tracks.find_mix(list, fields.mix)
    if not mix then return tracks.refusal(why) end
    saved_mixes = {}
    for _, saved in ipairs(contents.mixes) do
      if saved.guid == mix.guid then saved_mixes[1] = saved end
    end
    if not saved_mixes[1] then return tracks.refusal("mix_not_saved") end
  end

  local todo = plan(api, list, saved_mixes)
  local count = #todo.writes
  if count > 0 or #todo.masters > 0 then
    undo.run(api, "IEM Mix: recall snapshot " .. name, function()
      for _, w in ipairs(todo.writes) do
        api.SetTrackSendInfo_Value(w.track, -1, w.index, "D_VOL", w.send.vol)
        api.SetTrackSendInfo_Value(w.track, -1, w.index, "D_PAN", w.send.pan)
        api.SetTrackSendInfo_Value(w.track, -1, w.index, "B_MUTE", w.send.muted and 1 or 0)
      end
      for _, m in ipairs(todo.masters) do
        api.SetTrackSendInfo_Value(m.track, 1, 0, "D_VOL", m.value)
      end
    end)
  end
  return { status = "ok", name = name, mixes = todo.mixes, sends = count, skipped = todo.skipped,
    missing = todo.missing }
end

return snapshot_recall
