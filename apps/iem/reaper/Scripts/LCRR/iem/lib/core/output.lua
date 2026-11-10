-- The `output` core: set, replace or clear a mix's hardware output. A mix has at most one (Monitor's master fader
-- drives only the first), mono or stereo, so all three are one operation inside one undo block:
--
--   output.run({ api, fields = { guid, channel, mono } })
--     -> { status = "ok", changed }
--      | { status = "refused", error = { code } }
--
--   channel  0-based first device channel, or "none" to clear
--   mono     "1" for a mono downmix (I_SRCCHAN 0, I_DSTCHAN = channel | 1024); anything else is stereo
--
-- `guid` may also be the cue track's (`IEM-Cue`, cue.lua): its headphone output is set the same way, in the same step.
-- Setting on a mix with an output replaces it in place (its send settings stay). Sharing a channel with another mix
-- or the master is allowed: flagging it is the page's job. Refusals are decided before the block opens:
--   track_gone, not_a_mix, multiple_outputs (read-only: more than one output), bad_channel (not a whole number, or
--   outside the device), no_device (a set while REAPER reports no channels; a clear still works).
-- `changed` is false when the mix already has exactly that output (no undo step).

local tracks = require("lib.core.tracks")
local undo = require("lib.core.undo")

local output = {}

function output.run(given)
  local api = given.api
  local fields = given.fields or {}
  local list = tracks.scan(api)

  local target, code = tracks.find_mix(list, fields.guid)
  if not target then
    -- The cue track takes an output like a mix (IEM Mix's headphones); any other non-mix is still refused.
    local cue_entry = tracks.find_cue(list)
    if code ~= "not_a_mix" or cue_entry ~= tracks.find_by_guid(list, fields.guid) then return tracks.refusal(code) end
    target = cue_entry
  end

  local existing = tracks.outputs(api, target.track)
  if #existing > 1 then return tracks.refusal("multiple_outputs") end

  local clearing = fields.channel == "none"
  local channel, mono
  if not clearing then
    channel = (fields.channel or ""):match("^%d+$") and tonumber(fields.channel)
    if not channel then return tracks.refusal("bad_channel") end
    mono = fields.mono == "1"
    local count = api.GetNumAudioOutputs()
    if count == 0 then return tracks.refusal("no_device") end
    if channel + (mono and 0 or 1) >= count then return tracks.refusal("bad_channel") end
  end

  local current = existing[1]
  if clearing and not current then return { status = "ok", changed = false } end
  if current and not clearing and current.channel == channel and current.mono == mono then
    return { status = "ok", changed = false }
  end

  undo.run(api, "IEM Setup: set output", function()
    if clearing then
      api.RemoveTrackSend(target.track, 1, 0)
      return
    end
    if not current then api.CreateTrackSend(target.track, nil) end
    api.SetTrackSendInfo_Value(target.track, 1, 0, "I_SRCCHAN", 0)
    api.SetTrackSendInfo_Value(target.track, 1, 0, "I_DSTCHAN", mono and (channel | tracks.DEST_MONO) or channel)
  end)
  return { status = "ok", changed = true }
end

return output
