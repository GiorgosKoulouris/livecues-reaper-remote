-- lib/automation_oracle.lua is a thin translator over `reaper.*`, so what is
-- worth pinning is exactly the translation: which API it asks, which argument
-- order it uses, and which of Envelope_Evaluate's five return values it keeps.
-- Everything it wraps is REAPER's to be right about (ADR-0006's reasoning,
-- applied to envelope shapes rather than bar lines).
--
-- Prior art: spec/tempo_oracle_spec.lua, which fakes the same way for the
-- sibling oracle.

local automation_oracle = require("lib.automation_oracle")

local function fake_api(overrides)
  local api = {
    calls = {},
    GetTrack = function(_, index) return { kind = "track", index = index } end,
    GetMasterTrack = function() return { kind = "master" } end,
    GetTrackEnvelopeByName = function(track, name)
      return { track = track, name = name }
    end,
    -- retval, value, dVdS, ddVdS, dddVdS -- only the second is wanted.
    Envelope_Evaluate = function() return 1, 0.75, 9, 9, 9 end,
  }
  for key, value in pairs(overrides or {}) do
    api[key] = value
  end
  return api
end

describe("automation_oracle.value_at", function()
  it("returns Envelope_Evaluate's value, not its retval", function()
    local oracle = automation_oracle.new(fake_api(), 0)

    assert.are.equal(0.75, oracle.value_at(0, "Volume", 12))
  end)

  it("looks the envelope up by name on the requested track", function()
    local seen
    local oracle = automation_oracle.new(fake_api({
      GetTrackEnvelopeByName = function(track, name)
        seen = { track_index = track.index, name = name }
        return { }
      end,
    }), 0)

    oracle.value_at(3, "Mute", 0)

    assert.are.same({ track_index = 3, name = "Mute" }, seen)
  end)

  -- lib/project.lua's MASTER_TRACK_INDEX is -1, a sentinel rather than a track
  -- index. Handing it to GetTrack would ask for a track that is not there.
  it("routes the master track's sentinel index to GetMasterTrack", function()
    local asked_for_track = false
    local oracle = automation_oracle.new(fake_api({
      GetTrack = function() asked_for_track = true return nil end,
    }), 0)

    assert.are.equal(0.75, oracle.value_at(-1, "Volume", 4))
    assert.is_false(asked_for_track)
  end)

  -- The same answer the planner would reach from having no points to carry.
  it("returns zero when the envelope is not there", function()
    local oracle = automation_oracle.new(fake_api({
      GetTrackEnvelopeByName = function() return nil end,
    }), 0)

    assert.are.equal(0, oracle.value_at(0, "Volume", 12))
  end)

  it("returns zero when the track is not there", function()
    local oracle = automation_oracle.new(fake_api({
      GetTrack = function() return nil end,
    }), 0)

    assert.are.equal(0, oracle.value_at(7, "Volume", 12))
  end)

  it("evaluates at the time it was asked about", function()
    local seen
    local oracle = automation_oracle.new(fake_api({
      Envelope_Evaluate = function(_, time) seen = time return 1, 0, 0, 0, 0 end,
    }), 0)

    oracle.value_at(0, "Volume", 41.5)

    assert.are.equal(41.5, seen)
  end)
end)
