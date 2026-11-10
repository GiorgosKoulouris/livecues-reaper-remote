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
-- nesting `depth` (0 at the top level) so the page can indent, and a `tint` (`rrggbb`) when the track has its own
-- colour.
--
-- **The cue track** is the first track named `IEM-Cue` (IEM Mix listens through it): neither a mix nor a source row.
-- `cue = { guid, outputs, missing, unprotected }` (absent when there is none): its hardware outputs, how many mixes and
-- cue tracks lack solo defeat (`unprotected`) and the number of mixes with
-- no send to it.
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
local cue_core = require("lib.core.cue")

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
-- The track's own colour as `rrggbb`, or nil when it has none (bit 0x1000000 clear). REAPER keeps it in the
-- platform's native order, so it goes through ColorFromNative.
local function track_tint(api, track)
  local native = api.GetMediaTrackInfo_Value(track, "I_CUSTOMCOLOR") | 0
  if native & 0x1000000 == 0 then return nil end
  local r, g, b = api.ColorFromNative(native & 0xFFFFFF)
  return ("%02x%02x%02x"):format(r, g, b)
end

function state.run(given)
  local api = given.api
  local mixes, sources = {}, {}
  local folder = nil
  local cue = nil          -- the first track named `IEM-Cue`: not a source, not a mix
  local unprotected = 0    -- mixes without solo defeat (the cue track is counted with them)
  local level = 0          -- folder nesting before the current track
  local folder_base = nil  -- `level` when the IEMs folder opened; nil outside it

  for index = 0, api.CountTracks(0) - 1 do
    local track = api.GetTrack(0, index)
    local name = track_name(api, track)
    local depth = math.floor(api.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH"))
    local guid = api.GetTrackGUID(track)

    if is_mix_name(name) then
      if not cue_core.is_protected(api, track) then unprotected = unprotected + 1 end
      mixes[#mixes + 1] = {
        guid = guid,
        name = name:sub(#state.MIX_PREFIX + 1),
        in_folder = folder_base ~= nil and level > folder_base,
        master_send = api.GetMediaTrackInfo_Value(track, "B_MAINSEND") ~= 0,
        outputs = tracks.outputs(api, track),
        sends = sends_of(api, track),
      }
    elseif not cue and name == tracks.CUE_NAME then
      cue = { guid = guid, outputs = tracks.outputs(api, track), track = track,
              solo_defeat = cue_core.is_protected(api, track) }
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
        tint = track_tint(api, track),
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

  -- The cue track (absent when there is none): its output, and how many mixes still lack a send to it.
  if cue then
    local senders = cue_core.senders(api, cue.track)
    local missing = 0
    for _, mix in ipairs(mixes) do
      if not senders[mix.guid] then missing = missing + 1 end
    end
    if not cue.solo_defeat then unprotected = unprotected + 1 end
    cue = { guid = cue.guid, outputs = cue.outputs, missing = missing, unprotected = unprotected }
  end

  return {
    status = "ok", folder = folder, cue = cue, colour = tracks.colour(api), mixes = mixes, sources = sources,
    device = { channels = channels }, master_outputs = tracks.outputs(api, api.GetMasterTrack(0)),
  }
end

return state
