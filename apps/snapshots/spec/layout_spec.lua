-- Guards the reaper/ slice layout, not the bridge's behaviour (same reason as
-- Arrange's spec): inside REAPER the script extends package.path from its own
-- folder, and specs load lib/ through .busted's lpath instead, so nothing else
-- would notice a script whose package.path line no longer matches the layout.
local SCRIPT_DIR = "reaper/Scripts/LCRR/snapshots"
local SHARED_SLICE = "../../shared/reaper/Scripts/LCRR"

local function read(path)
  local handle = assert(io.open(path, "r"), "missing: " .. path)
  local source = handle:read("a")
  handle:close()
  return source
end

describe("reaper/ slice layout", function()
  local source = read(SCRIPT_DIR .. "/LCRR_Snapshots_Bridge.lua")

  it("puts its own folder and its parent on package.path", function()
    assert.is_truthy(source:find('package.path = script_dir .. "/?.lua;" .. package.path', 1, true))
    assert.is_truthy(source:find('package.path = script_dir .. "/../?.lua;" .. package.path', 1, true))
  end)

  it("finds every lib module beside the script and every shared module in the shared slice", function()
    local count = 0
    for module in source:gmatch('require%("(lib%.[%w_.]+)"%)') do
      count = count + 1
      assert.is_not_nil(package.searchpath(module, SCRIPT_DIR .. "/?.lua"), module)
    end
    for module in source:gmatch('require%("(shared%.[%w_.]+)"%)') do
      count = count + 1
      assert.is_not_nil(package.searchpath(module, SHARED_SLICE .. "/?.lua"), module)
    end
    assert.is_true(count >= 2)
  end)

  it("runs the shared runner in its own ExtState section", function()
    assert.is_truthy(source:find('section = "LCRR_SNAPSHOTS"', 1, true))
  end)
end)
