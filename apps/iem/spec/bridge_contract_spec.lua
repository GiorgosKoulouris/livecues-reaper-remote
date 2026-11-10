-- The replies the web page is written against, recorded from the real service.
--
-- test/fixtures/bridge-replies.txt holds one line per scenario:
-- `<name>\t<reply json>`. This spec compares what the service says now with that
-- file, so a change to a reply's shape cannot go unnoticed; test/core.test.js
-- and test/words.test.js then push the same file through the page's logic, so
-- the page cannot drift from it.
-- After a deliberate change: LCRR_RECORD_BRIDGE=1 busted spec/bridge_contract_spec.lua,
-- and read the diff.

local service = require("lib.bridge.service")
local fake_project = require("spec.support.fake_project")

local FIXTURE = "test/fixtures/bridge-replies.txt"
local PATH = "C:/Shows/Sunday/Sunday.rpp"

local function raw(id, body)
  return ("%s|%d|%s"):format(id, #body, body)
end

local function bridge(tracks, path, extra)
  extra = extra or {}
  local handler = service.new({ api = fake_project.new({
    path = path or PATH, tracks = tracks, device = extra.device, master_outputs = extra.master_outputs,
  }) })
  local count = 0
  return function(body)
    count = count + 1
    local _, reply = handler.handle(raw("q" .. count, body))
    return reply
  end
end

-- A band: nested source tracks, a folder of mixes with one stray, and the
-- awkward cases the page has to show (a mono output, a muted send, a send that
-- is not post-FX pre-fader, a folder and its child feeding one mix, a mix with
-- no output, a duplicate name, a mix with several outputs).
local function band()
  return {
    { name = "Drums", depth = 1 },
    { name = "Kick" },
    { name = "Snare", depth = -1 },
    { name = "Bass" },
    { name = "Vocals" },
    { name = "IEM_Stray", receives = { { from = "Vocals", vol = 1.0, mode = 3 } }, outputs = { { dest = 4 } } },
    { name = "IEMs", depth = 1, main_send = false },
    { name = "IEM_Drummer", main_send = false,
      outputs = { { dest = 0 } },
      receives = {
        { from = "Drums", vol = 0.5, mode = 3 },
        { from = "Kick", vol = 1.0, mode = 3 },
        { from = "Vocals", vol = 0.25, mode = 3, muted = true },
        { from = "Bass", vol = 2.0, mode = 0 },
      } },
    { name = "IEM_Singer", main_send = false,
      outputs = { { dest = 2 | 1024 } },
      receives = { { from = "Vocals", vol = 1.0, mode = 3 } } },
    { name = "IEM_Bassist", main_send = false },
    { name = "IEM_Singer", main_send = false, outputs = { { dest = 0 }, { dest = 2 } },
      receives = { { from = "Bass", vol = 1.0, mode = 1 } }, depth = -1 },
  }
end

local scenarios = {
  { "state_band", function() return bridge(band())("cmd=state") end },
  { "state_empty", function() return bridge({})("cmd=state") end },
  { "state_unsaved", function() return bridge({ { name = "Kick" } }, "")("cmd=state") end },
  { "state_no_folder", function()
    return bridge({ { name = "Kick" }, { name = "IEM_A", receives = { { from = "Kick" } } } })("cmd=state")
  end },
  { "state_empty_folder", function()
    return bridge({ { name = "Kick" }, { name = "IEMs" } })("cmd=state")
  end },
  { "state_tracks_after", function()
    return bridge({ { name = "IEMs", depth = 1 }, { name = "IEM_A", depth = -1 }, { name = "Kick" } })("cmd=state")
  end },
  { "create_first", function() return bridge({ { name = "Kick" } })("cmd=create&name=Drummer") end },
  { "create_later", function()
    return bridge({ { name = "IEMs", depth = 1 }, { name = "IEM_A", depth = -1 } })("cmd=create&name=Singer")
  end },
  { "create_copy", function()
    return bridge({
      { name = "Kick", guid = "{K}" },
      { name = "IEMs", depth = 1 },
      { name = "IEM_A", depth = -1, guid = "{A}", receives = { { from = "Kick", vol = 0.5, mode = 3 } } },
    })("cmd=create&name=Singer&copy=%7BA%7D")
  end },
  { "create_copy_gone", function() return bridge({})("cmd=create&name=Singer&copy=%7BA%7D") end },
  { "adopt_ok", function()
    return bridge({ { name = "IEM_A", guid = "{A}" }, { name = "Kick" } })("cmd=adopt&guid=%7BA%7D")
  end },
  { "adopt_not_a_stray", function()
    return bridge({ { name = "IEMs", depth = 1 }, { name = "IEM_A", depth = -1, guid = "{A}" } })(
      "cmd=adopt&guid=%7BA%7D")
  end },
  { "create_empty_name", function() return bridge({})("cmd=create&name=%20") end },
  { "create_duplicate_name", function() return bridge({ { name = "IEM_A" } })("cmd=create&name=A") end },
  { "rename_ok", function()
    return bridge({ { name = "IEM_A", guid = "{A}" } })("cmd=rename&guid=%7BA%7D&name=B")
  end },
  { "rename_unchanged", function()
    return bridge({ { name = "IEM_A", guid = "{A}" } })("cmd=rename&guid=%7BA%7D&name=A")
  end },
  { "rename_gone", function() return bridge({})("cmd=rename&guid=%7BA%7D&name=B") end },
  { "colour_ok", function() return bridge({})("cmd=colour&colour=ff8000") end },
  { "colour_bad", function() return bridge({})("cmd=colour&colour=orange") end },
  { "move_to_end_ok", function()
    return bridge({ { name = "IEMs", depth = 1, guid = "{F}" }, { name = "IEM_A", depth = -1 }, { name = "Kick" } })(
      "cmd=move_to_end&guid=%7BF%7D")
  end },
  { "move_to_end_nothing", function()
    return bridge({ { name = "IEMs", guid = "{F}" } })("cmd=move_to_end&guid=%7BF%7D")
  end },
  { "delete_ok", function()
    return bridge({ { name = "IEMs", depth = 1 }, { name = "IEM_A", depth = -1, guid = "{A}" } })(
      "cmd=delete&guid=%7BA%7D")
  end },
  { "delete_gone", function() return bridge({})("cmd=delete&guid=%7BA%7D") end },
  { "delete_not_a_mix", function()
    return bridge({ { name = "Kick", guid = "{K}" } })("cmd=delete&guid=%7BK%7D")
  end },
  { "state_device_open", function()
    return bridge(band(), nil, { device = { "Output 1", "Output 2", "Output 3", "Output 4", "Output 5" },
      master_outputs = { { dest = 0 } } })("cmd=state")
  end },
  { "output_set", function()
    return bridge({ { name = "IEM_A", guid = "{A}" } }, nil, { device = { "Output 1", "Output 2" } })(
      "cmd=output&guid=%7BA%7D&channel=0&mono=1")
  end },
  { "output_clear", function()
    return bridge({ { name = "IEM_A", guid = "{A}", outputs = { { dest = 0 } } } })(
      "cmd=output&guid=%7BA%7D&channel=none")
  end },
  { "output_multiple", function()
    return bridge({ { name = "IEM_A", guid = "{A}", outputs = { { dest = 0 }, { dest = 2 } } } })(
      "cmd=output&guid=%7BA%7D&channel=none")
  end },
  { "output_no_device", function()
    return bridge({ { name = "IEM_A", guid = "{A}" } })("cmd=output&guid=%7BA%7D&channel=0&mono=0")
  end },
  { "output_bad_channel", function()
    return bridge({ { name = "IEM_A", guid = "{A}" } }, nil, { device = { "Output 1", "Output 2" } })(
      "cmd=output&guid=%7BA%7D&channel=9&mono=0")
  end },
  { "output_gone", function() return bridge({})("cmd=output&guid=%7BA%7D&channel=none") end },
  { "cell_on", function()
    return bridge({ { name = "Kick", guid = "{K}" }, { name = "IEM_A", guid = "{A}" } })(
      "cmd=cell&source=%7BK%7D&mix=%7BA%7D&on=1")
  end },
  { "cell_off", function()
    return bridge({
      { name = "Kick", guid = "{K}" }, { name = "IEM_A", guid = "{A}", receives = { { from = "Kick" } } },
    })(
      "cmd=cell&source=%7BK%7D&mix=%7BA%7D&on=0")
  end },
  { "cell_unchanged", function()
    return bridge({ { name = "Kick", guid = "{K}" }, { name = "IEM_A", guid = "{A}" } })(
      "cmd=cell&source=%7BK%7D&mix=%7BA%7D&on=0")
  end },
  { "cell_gone", function()
    return bridge({ { name = "IEM_A", guid = "{A}" } })("cmd=cell&source=%7BK%7D&mix=%7BA%7D&on=1")
  end },
  { "cell_not_a_source", function()
    return bridge({ { name = "IEM_B", guid = "{B}" }, { name = "IEM_A", guid = "{A}" } })(
      "cmd=cell&source=%7BB%7D&mix=%7BA%7D&on=1")
  end },
  { "row_on", function()
    return bridge({
      { name = "Kick", guid = "{K}" }, { name = "IEM_A", guid = "{A}", receives = { { from = "Kick" } } },
      { name = "IEM_B", guid = "{B}" },
    })("cmd=row&source=%7BK%7D&on=1")
  end },
  { "row_off", function()
    return bridge({
      { name = "Kick", guid = "{K}" }, { name = "IEM_A", guid = "{A}", receives = { { from = "Kick" } } },
    })("cmd=row&source=%7BK%7D&on=0")
  end },
  { "row_not_a_source", function()
    return bridge({ { name = "IEM_A", guid = "{A}" } })("cmd=row&source=%7BA%7D&on=1")
  end },
  { "column_on", function()
    return bridge({
      { name = "Kick", guid = "{K}" }, { name = "Snare", guid = "{S}" },
      { name = "IEM_A", guid = "{A}", receives = { { from = "Kick" } } },
    })("cmd=column&mix=%7BA%7D&on=1")
  end },
  { "column_off", function()
    return bridge({
      { name = "Kick", guid = "{K}" }, { name = "IEM_A", guid = "{A}", receives = { { from = "Kick" } } },
    })("cmd=column&mix=%7BA%7D&on=0")
  end },
  { "column_not_a_mix", function()
    return bridge({ { name = "Kick", guid = "{K}" } })("cmd=column&mix=%7BK%7D&on=1")
  end },
  { "unknown_command", function() return bridge({})("cmd=nope") end },
  { "request_truncated", function()
    local handler = service.new({ api = fake_project.new({ path = PATH }) })
    local _, reply = handler.handle("q1|40|cmd=sta")
    return reply
  end },
  { "bad_request", function()
    local handler = service.new({ api = fake_project.new({ path = PATH }) })
    local _, reply = handler.handle("q1|3|cmd")
    return reply
  end },
}

local function recorded()
  local handle = io.open(FIXTURE, "r")
  if not handle then return {} end
  local found = {}
  for line in handle:lines() do
    local name, reply = line:match("^([^\t]+)\t(.*)$")
    found[name] = reply
  end
  handle:close()
  return found
end

describe("bridge replies the page is written against", function()
  local expected = recorded()
  local lines = {}

  for _, scenario in ipairs(scenarios) do
    local name, play = scenario[1], scenario[2]
    local reply = play()
    lines[#lines + 1] = name .. "\t" .. reply

    it(name .. " matches test/fixtures/bridge-replies.txt", function()
      if os.getenv("LCRR_RECORD_BRIDGE") then return end
      assert.are.equal(expected[name], reply)
    end)
  end

  if os.getenv("LCRR_RECORD_BRIDGE") then
    local handle = assert(io.open(FIXTURE, "w"))
    handle:write(table.concat(lines, "\n"), "\n")
    handle:close()
  end
end)
