-- The Automation Anchor oracle: what value an envelope holds at a given time.
--
-- The planner has every envelope *point*, but not the value *between* points --
-- REAPER's shapes include bezier and slow start/end, and reimplementing that
-- interpolation in Lua is the same mistake ADR-0006 rejected for bar math.
-- `Envelope_Evaluate` is REAPER's own answer to the question, so the planner
-- asks it rather than guessing.
--
-- The sibling of `lib/tempo_oracle.lua`, and the same shape: a thin, read-only
-- translator over `reaper.*`, injected into the pure planner as a parameter and
-- faked in specs. ADR-0001 confines `reaper.*` to thin appliers; an oracle is
-- the other half of that pattern.
--
-- Lifted out of `LCRR_Arrange_Apply.lua`, where it was defined
-- inline, once `LCRR_Arrange_Check.lua` needed the same thing
-- (issue #21). Two scripts holding their own copy of a `reaper.*` call is how
-- the two drift.

local automation_oracle = {}

--- Build an oracle bound to a project.
-- @param api table the reaper API table (injected so specs can fake it)
-- @param proj number project index, 0 for the active one
-- @return table { value_at }
function automation_oracle.new(api, proj)
  proj = proj or 0

  --- The value `envelope_name` holds on `track_index` at `time`.
  --
  -- A track index below zero is the master track's sentinel
  -- (`lib/project.lua`'s `MASTER_TRACK_INDEX`), which is not a track index at
  -- all and must not be passed to `GetTrack`.
  --
  -- Returns 0 for an envelope that is not there, which is the same answer the
  -- planner would reach from having no points to carry.
  local function value_at(track_index, envelope_name, time)
    local track = track_index < 0 and api.GetMasterTrack(proj) or api.GetTrack(proj, track_index)
    local envelope = track and api.GetTrackEnvelopeByName(track, envelope_name)
    if not envelope then
      return 0
    end
    -- Envelope_Evaluate -> retval, value, dVdS, ddVdS, dddVdS. Only the value
    -- is wanted; the sample rate affects the derivatives, not it.
    local _, value = api.Envelope_Evaluate(envelope, time, 48000, 1)
    return value
  end

  return { value_at = value_at }
end

return automation_oracle
