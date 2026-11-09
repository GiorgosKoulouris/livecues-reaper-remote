-- Show Track Timebase, headless: every track with its timebase, as REAPER
-- reports it through C_BEATATTACHMODE, and a tally by mode. Reads only, and
-- writes nothing -- not even the run log.
--
--   local result = timebase.run({ api = reaper })

local timebase = {}

timebase.TITLE = "Show Track Timebase"

--- @return table { status = "refused", error = { code = "no_tracks" } }, or
---   { status = "ok", lua_version, tracks = { { track_index, name, mode } },
---     tally = { [mode] = count } }
function timebase.run(given)
  local api = assert(given and given.api, "a core needs env.api")

  local track_count = api.CountTracks(0)
  if track_count == 0 then
    return { status = "refused", error = { code = "no_tracks" } }
  end

  local tracks, tally = {}, {}
  for index = 0, track_count - 1 do
    local track = api.GetTrack(0, index)
    local mode = api.GetMediaTrackInfo_Value(track, "C_BEATATTACHMODE")
    local _, name = api.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)

    tally[mode] = (tally[mode] or 0) + 1
    tracks[#tracks + 1] = { track_index = index, name = name, mode = mode }
  end

  -- Items carry their own timebase too -- the .RPP shows item-level BEAT lines,
  -- and ReaTeam documents -1 there as "use track timebase". Deliberately not
  -- reported: the item attribute name is unconfirmed, and GetMediaItemInfo_Value
  -- returns 0 for an unknown key, which is indistinguishable from a real "time"
  -- answer. Add it once the name is confirmed in REAPER's in-app ReaScript docs.
  return { status = "ok", lua_version = _VERSION, tracks = tracks, tally = tally }
end

return timebase
