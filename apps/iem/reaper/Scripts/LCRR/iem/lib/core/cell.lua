-- The `cell` core: switch one matrix cell (a source row, a mix column) on or off.
--
--   cell.run({ api, fields = { source, mix, on } })
--     -> { status = "ok", changed }
--      | { status = "refused", error = { code } }
--
--   source  GUID of a source track (any track that is not a mix and not the IEMs folder)
--   mix     GUID of a mix
--   on      "1" to switch on, anything else to switch off
--
-- On creates a send from the source to the mix, post-FX pre-fader (`I_SENDMODE` 3) at 0 dB. Off deletes EVERY send from
-- the source to the mix at once, with no warning (the page's lock is the only guard). Each is one undo step.
-- The sends are found and removed from the source's side (category 0), highest index first, so the indexes still to be
-- removed do not move; REAPER's own receive numbering on the mix (what Monitor reads) is not touched by anything but
-- the removal itself, which Monitor follows (issue 01 result).
-- `changed` is false when the cell is already as asked (on with a send there, off with none): no undo step.
-- Refusals are decided before the block opens: track_gone (source or mix), not_a_mix, not_a_source (a mix or the
-- IEMs folder).

local tracks = require("lib.core.tracks")
local undo = require("lib.core.undo")

local cell = {}

cell.SEND_MODE = 3 -- post-FX, pre-fader (suite CONTEXT.md)

--- The indexes, on the source, of its sends to the mix (also used by the row and column cores, `bulk.lua`).
function cell.sends_between(api, source, mix)
  local found = {}
  for index = 0, api.GetTrackNumSends(source.track, 0) - 1 do
    local dest = api.GetTrackSendInfo_Value(source.track, 0, index, "P_DESTTRACK")
    if api.GetTrackGUID(dest) == mix.guid then found[#found + 1] = index end
  end
  return found
end

--- A new send source -> mix with the settings of an existing one (`{ vol, pan, muted, mode }`, as `create` reads them).
function cell.copy_send(api, source_track, mix_track, settings)
  local index = api.CreateTrackSend(source_track, mix_track)
  api.SetTrackSendInfo_Value(source_track, 0, index, "D_VOL", settings.vol)
  api.SetTrackSendInfo_Value(source_track, 0, index, "D_PAN", settings.pan)
  api.SetTrackSendInfo_Value(source_track, 0, index, "B_MUTE", settings.muted)
  api.SetTrackSendInfo_Value(source_track, 0, index, "I_SENDMODE", settings.mode)
end

--- A new send source -> mix, post-FX pre-fader at 0 dB (REAPER's own defaults are post-fader).
function cell.add_send(api, source, mix)
  local index = api.CreateTrackSend(source.track, mix.track)
  api.SetTrackSendInfo_Value(source.track, 0, index, "I_SENDMODE", cell.SEND_MODE)
  api.SetTrackSendInfo_Value(source.track, 0, index, "D_VOL", 1.0)
end

--- Switch pairs on or off, in one undo step named after `kind` ("cell", "row", "column"). `pairs_list` is
--- { { source, mix } ... }. On adds a send only to a pair with none; off removes every send of every pair, highest
--- index first (sends are numbered per source, so that order holds across all of a source's pairs). Returns
--- { status = "ok", changed, count }, count being the sends added or removed; no undo step when it is 0. Shared with
--- `bulk`.
function cell.switch(api, kind, on, pairs_list)
  local plan = {}
  for _, pair in ipairs(pairs_list) do
    local existing = cell.sends_between(api, pair[1], pair[2])
    if on and #existing == 0 then plan[#plan + 1] = { pair = pair }
    elseif not on then
      for _, index in ipairs(existing) do plan[#plan + 1] = { pair = pair, index = index } end
    end
  end
  if #plan == 0 then return { status = "ok", changed = false, count = 0 } end
  if not on then
    table.sort(plan, function(a, b) return a.index > b.index end)
  end
  undo.run(api, "IEM Setup: switch " .. kind .. (on and " on" or " off"), function()
    for _, item in ipairs(plan) do
      if on then
        cell.add_send(api, item.pair[1], item.pair[2])
      else
        api.RemoveTrackSend(item.pair[1].track, 0, item.index)
      end
    end
  end)
  return { status = "ok", changed = true, count = #plan }
end

function cell.run(given)
  local api = given.api
  local fields = given.fields or {}
  local list = tracks.scan(api)

  local source = tracks.find_by_guid(list, fields.source or "")
  if not source then return tracks.refusal("track_gone") end
  local mix, code = tracks.find_mix(list, fields.mix)
  if not mix then return tracks.refusal(code) end
  if not tracks.is_source(list, source) then
    return tracks.refusal("not_a_source")
  end

  local result = cell.switch(api, "cell", fields.on == "1", { { source, mix } })
  return { status = "ok", changed = result.changed }
end

return cell
