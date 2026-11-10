-- Automation, as the restore sees it (ADR-0001 of this app). Headless, read-only: it asks REAPER, it never writes.
--
--   local auto = automation.new(api)
--   auto.guards_mute(track)                    -- a track's B_MUTE would reach a Mute envelope: skip it
--   auto.guards_send_mute(track, category, i)  -- the same for a send
--   auto.track_follows(track, key)             -- the track value `key` (D_VOL, D_PAN, B_MUTE) has active automation
--   auto.send_follows(track, category, i, key) -- the same for a send's value
--
-- Active automation (suite CONTEXT.md, spike): the envelope exists, `CountEnvelopePoints` > 0 and `ACTIVE` is "1". A
-- send's envelope pointer always exists, so its point count is what tells; for the same reason a send "has a Mute
-- envelope" when it has points. Only mute is guarded: a track's mute is skipped when it has a Mute envelope and its
-- own mode or the global override is 2 (Touch), 3 (Write) or 4 (Latch). A send uses its own `I_AUTOMODE` (-1 follows
-- the track). Levels and pans never reach an envelope, so they are never guarded.

local automation = {}

local TRACK_ENVELOPES = { D_VOL = "Volume", D_PAN = "Pan", B_MUTE = "Mute" }
local SEND_ENVELOPES = { D_VOL = "P_ENV:<VOLENV", D_PAN = "P_ENV:<PANENV", B_MUTE = "P_ENV:<MUTEENV" }

local function writes_envelope(mode) return mode == 2 or mode == 3 or mode == 4 end

function automation.new(api)
  local self = {}

  local function active(env)
    if not env or api.CountEnvelopePoints(env) <= 0 then return false end
    local _, flag = api.GetSetEnvelopeInfo_String(env, "ACTIVE", "", false)
    return flag == "1"
  end

  local function send_env(track, category, index, key)
    return api.GetTrackSendInfo_Value(track, category, index, SEND_ENVELOPES[key])
  end

  local function send_mode(track, category, index)
    local own = api.GetTrackSendInfo_Value(track, category, index, "I_AUTOMODE")
    if own == -1 then return api.GetTrackAutomationMode(track) end
    return own
  end

  function self.guards_mute(track)
    if not api.GetTrackEnvelopeByName(track, "Mute") then return false end
    return writes_envelope(api.GetTrackAutomationMode(track)) or writes_envelope(api.GetGlobalAutomationOverride())
  end

  function self.guards_send_mute(track, category, index)
    local env = send_env(track, category, index, "B_MUTE")
    if not env or api.CountEnvelopePoints(env) <= 0 then return false end
    return writes_envelope(send_mode(track, category, index)) or writes_envelope(api.GetGlobalAutomationOverride())
  end

  function self.track_follows(track, key)
    local name = TRACK_ENVELOPES[key]
    return name ~= nil and active(api.GetTrackEnvelopeByName(track, name))
  end

  function self.send_follows(track, category, index, key)
    return SEND_ENVELOPES[key] ~= nil and active(send_env(track, category, index, key))
  end

  return self
end

return automation
