-- The `state` core: read the project's in-ear mixes and the tracks that can
-- feed them into plain tables. It writes nothing (this is the read-only slice;
-- later cores add the writes). Headless, as every core is (Arrange ADR-0008):
-- no dialogs, and results are codes and fields, never sentences.
--
--   local result = state.run({ api = reaper })
--
-- **A mix** is a track named `IEM_<name>`: the same rule as Monitor (exact,
-- case-sensitive prefix, something after it), so the two apps agree. IEM Setup
-- also reports the mixes Monitor does not list yet (no receive, no output).
-- **The folder** is the first track named `IEMs`; a mix is `in_folder` when it
-- lies inside that folder, and a **stray** otherwise. A folder track counts
-- only while its `I_FOLDERDEPTH` is 1: an emptied folder is a plain track
-- (suite CONTEXT.md, issue 01), so nothing is "in" it.
-- **Sources** are every other track, in project order, each with its folder
-- nesting `depth` (0 at the top level) so the page can indent.
--
-- `folder.tracks_after` is true when tracks sit after the folder's last member.
-- `colour` is the shared colour, `rrggbb`: the project's, or the default.
--
-- Sends are reported as REAPER holds them: `vol` is the linear gain (the page
-- makes dB of it), `mode` is `I_SENDMODE` (0 post-fader, 1 pre-FX, 3 post-FX
-- pre-fader, which is what IEM Setup creates), `muted` the send's own mute.
-- An output is `{ channel, mono }`: the 0-based first device channel, and
-- whether it is a mono downmix (`I_DSTCHAN` bit 1024).
-- `device.channels` names the device's outputs; `master_outputs` are the master track's hardware outputs.

local tracks = require("lib.core.tracks")

local state = {}

state.MIX_PREFIX = tracks.MIX_PREFIX
state.FOLDER_NAME = tracks.FOLDER_NAME

local track_name = tracks.name
local is_mix_name = tracks.is_mix_name

local function sends_of(api, track)
  local sends = {}
  for index = 0, api.GetTrackNumSends(track, -1) - 1 do
    local source = api.GetTrackSendInfo_Value(track, -1, index, "P_SRCTRACK")
    sends[#sends + 1] = {
      source = api.GetTrackGUID(source),
      vol = api.GetTrackSendInfo_Value(track, -1, index, "D_VOL"),
      muted = api.GetTrackSendInfo_Value(track, -1, index, "B_MUTE") ~= 0,
      mode = math.floor(api.GetTrackSendInfo_Value(track, -1, index, "I_SENDMODE")),
    }
  end
  return sends
end

--- @param given table { api }
--- @return table { status = "ok", folder, mixes, sources }
function state.run(given)
  local api = given.api
  local mixes, sources = {}, {}
  local folder = nil
  local level = 0          -- folder nesting before the current track
  local folder_base = nil  -- `level` when the IEMs folder opened; nil outside it

  for index = 0, api.CountTracks(0) - 1 do
    local track = api.GetTrack(0, index)
    local name = track_name(api, track)
    local depth = math.floor(api.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH"))
    local guid = api.GetTrackGUID(track)

    if is_mix_name(name) then
      mixes[#mixes + 1] = {
        guid = guid,
        name = name:sub(#state.MIX_PREFIX + 1),
        in_folder = folder_base ~= nil and level > folder_base,
        master_send = api.GetMediaTrackInfo_Value(track, "B_MAINSEND") ~= 0,
        outputs = tracks.outputs(api, track),
        sends = sends_of(api, track),
      }
    elseif not folder and name == state.FOLDER_NAME then
      folder = { guid = guid, is_folder = depth == 1 }
      if depth == 1 then
        folder_base = level
      end
    else
      sources[#sources + 1] = {
        guid = guid,
        name = name,
        depth = math.max(level, 0),
        is_folder = depth == 1,
      }
    end

    level = level + depth
    if folder_base ~= nil and level <= folder_base then
      folder_base = nil
    end
  end

  -- Does anything sit after the folder's last member? (Then the page offers Move to end.)
  if folder then
    local found = tracks.find_folder(tracks.scan(api))
    folder.tracks_after = found.last < api.CountTracks(0) - 1
  end

  -- The audio device's output channel names (empty while the device is closed: REAPER reports none, suite
  -- CONTEXT.md) and the master track's own hardware outputs, so the page can flag a mix that shares one.
  local channels = {}
  for channel = 0, api.GetNumAudioOutputs() - 1 do
    channels[#channels + 1] = api.GetOutputChannelName(channel) or ""
  end

  return {
    status = "ok", folder = folder, colour = tracks.colour(api), mixes = mixes, sources = sources,
    device = { channels = channels }, master_outputs = tracks.outputs(api, api.GetMasterTrack(0)),
  }
end

return state
