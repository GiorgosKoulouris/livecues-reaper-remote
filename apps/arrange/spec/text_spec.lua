-- The wording the dialog front ends show, from structured results.
--
-- spec/dialog_spec.lua pins every sentence byte for byte. This spec keeps the
-- few properties of the wording that are decisions rather than phrasing --
-- chiefly that Headroom announces itself as relative, which is the whole of
-- ADR-0007's guard -- so they read as requirements rather than as a diff.

local check_text = require("lib.text.check")
local verify_text = require("lib.text.verify")
local apply_text = require("lib.text.apply")

describe("lib/text/apply.lua headroom_prompt", function()
  local requests = {
    { name = "Chorus", seconds = 4 },
    { name = "Intro", seconds = -2 },
  }

  it("lists each region and what it will gain or lose, in the order given", function()
    local message = apply_text.headroom_prompt(requests)

    assert.is_truthy(message:find("Intro: -2.000s", 1, true))
    assert.is_truthy(message:find("Chorus: +4.000s", 1, true))
    assert.is_true(message:find("Chorus", 1, true) < message:find("Intro", 1, true))
  end)

  -- The one non-idempotent operation in the suite has to announce itself: this
  -- prompt is the whole of the compensating guard.
  it("says that Headroom is relative", function()
    local message = apply_text.headroom_prompt(requests)
    assert.is_truthy(message:find("RELATIVE", 1, true))
    assert.is_truthy(message:lower():find("second time", 1, true))
  end)

  it("offers all three answers", function()
    local message = apply_text.headroom_prompt(requests)
    assert.is_truthy(message:find("Yes", 1, true))
    assert.is_truthy(message:find("No", 1, true))
    assert.is_truthy(message:find("Cancel", 1, true))
  end)
end)

describe("lib/text/apply.lua error", function()
  it("says a refusal after phase 1 left anchors that Undo removes", function()
    local message = apply_text.error({ code = "plan_refused", error = "Too short.", anchors_written = 3 })
    assert.is_truthy(message:find("^Too short%."))
    assert.is_truthy(message:find("3 Tempo Anchor(s) were written", 1, true))
    assert.is_truthy(message:find("Undo removes them", 1, true))
  end)

  it("says nothing about anchors when none were written", function()
    local message = apply_text.error({ code = "plan_refused", error = "Too short." })
    assert.are.equal("Too short.", message)
  end)

  it("words every refusal the core can return", function()
    for _, err in ipairs({
      { code = "project_unsaved", message = "m" },
      { code = "tempo_env_beats", message = "m" },
      { code = "no_regions" },
      { code = "region_names", problems = {} },
      { code = "sidecar_invalid", error = "e" },
      { code = "sidecar_missing" },
      { code = "import_unreadable", path = "p" },
      { code = "import_invalid", path = "p", error = "e" },
      { code = "save_failed", error = "e" },
      { code = "no_arrangements" },
      { code = "arrangement_unknown", name = "n", available = {} },
      { code = "arrangement_missing_regions", name = "n", missing = {} },
      { code = "plan_refused", error = "e" },
      { code = "plan_out_of_scope", name = "n", error = "e" },
      { code = "anchors_moved_items", moved = {} },
    }) do
      assert.are_not.equal(err.code, apply_text.error(err), err.code .. " has no wording")
    end
  end)
end)

describe("lib/text/check.lua", function()
  it("says outright that Headroom is relative", function()
    local sentence = check_text.finding({ code = "headroom", headroom = {
      { name = "Verse", requested = 20, resolved = 20, bars = 2, from_end = 30, to_end = 50 },
    } })
    assert.is_truthy(sentence:lower():find("relative", 1, true))
  end)

  -- The likeliest "nothing happened" is a request under half a bar, and a
  -- region quietly missing from the report reads as a check that did not
  -- notice the edit.
  it("names a Headroom request that resolved to no change", function()
    local sentence = check_text.finding({ code = "headroom", headroom = {
      { name = "Verse", requested = 2, resolved = 0, bars = 0, from_end = 30, to_end = 30 },
    } })
    assert.is_truthy(sentence:find("Verse", 1, true))
    assert.is_truthy(sentence:find("NO CHANGE", 1, true))
  end)

  it("words every blind spot", function()
    for _, code in ipairs({ "padding_grid", "anchor_drift", "padding_overlap" }) do
      assert.are_not.equal(code, check_text.blind_spot(code))
    end
  end)
end)

describe("lib/text/verify.lua", function()
  it("words its blind spot, which is about Headroom", function()
    assert.is_truthy(verify_text.blind_spot("headroom_count"):find("Headroom", 1, true))
  end)
end)
