-- The `snapshot_save` core: store the level, pan and mute of every send to a mix and each mix's master level (its first
-- hardware output's level), keyed by track GUID. The request carries only the name (and `overwrite`); the contents are
-- read here, from the same reading `state` gives (mixes and the sends they receive), plus each send's pan.
--
--   snapshot_save.run({ api, fields = { name, overwrite = "1" }, now = function() return os.time() end })
--     -> { status = "ok", name, overwritten, mixes, sends }
--
-- Refusals, all decided before anything is written: `empty_name`, `bad_name`, `name_too_long`, `duplicate_name` (the
-- name is taken and `overwrite` is not 1), `not_found` (`overwrite` on a name that is not saved), `nothing_to_save`
-- (no mix has a send), `unreadable` (the stored list cannot be read).
--
-- Project ExtState ignores undo, so this opens no undo block and adds no undo step: the page's press and hold is the
-- only protection for an overwrite.

local tracks = require("lib.core.tracks")
local state = require("lib.core.state")
local store = require("lib.core.snapshot_store")

local snapshot_save = {}

local function capture(api)
  local list = tracks.scan(api)
  local contents, sends = { mixes = {} }, 0
  for _, mix in ipairs(state.run({ api = api }).mixes) do
    if #mix.sends > 0 then
      local track = tracks.find_by_guid(list, mix.guid).track
      local entry = { guid = mix.guid, sends = {} }
      if #mix.outputs > 0 then entry.master = api.GetTrackSendInfo_Value(track, 1, 0, "D_VOL") end
      for index, send in ipairs(mix.sends) do
        entry.sends[#entry.sends + 1] = {
          source = send.source, vol = send.vol, muted = send.muted,
          pan = api.GetTrackSendInfo_Value(track, -1, index - 1, "D_PAN"),
        }
      end
      sends = sends + #entry.sends
      contents.mixes[#contents.mixes + 1] = entry
    end
  end
  return contents, sends
end

function snapshot_save.run(given)
  local api, fields = given.api, given.fields or {}
  local name, code = store.clean_name(fields.name)
  if not name then return tracks.refusal(code) end
  local list, bad = store.list(api)
  if not list then return tracks.refusal(bad) end

  local existing = store.find(list, name)
  local overwrite = fields.overwrite == "1"
  if existing and not overwrite then return tracks.refusal("duplicate_name") end
  if overwrite and not existing then return tracks.refusal("not_found") end

  local contents, sends = capture(api)
  if #contents.mixes == 0 then return tracks.refusal("nothing_to_save") end

  local now = given.now or os.time
  local entry = {
    id = existing and existing.id or store.next_id(list), saved = math.floor(now()), mixes = #contents.mixes,
    sends = sends, name = name,
  }
  store.put(api, list, entry, contents)
  return { status = "ok", name = name, overwritten = existing ~= nil, mixes = entry.mixes, sends = sends }
end

return snapshot_save
