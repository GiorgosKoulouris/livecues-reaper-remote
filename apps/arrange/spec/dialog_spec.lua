-- Pins what each LCRR_Arrange_*.lua script does when run from REAPER's Action
-- list: its dialogs and their text, its console output, the log it appends,
-- its undo calls and what it hands the applier.
--
-- Each scenario (spec/support/dialog_scenarios.lua) runs the real script under
-- spec/support/script_harness.lua and compares the transcript with the one
-- recorded in spec/fixtures/dialogs/<script>/<scenario>.txt. The recordings
-- were taken before the scripts were split into cores and dialog front ends
-- (spec step 3), so a passing run here is the evidence that the split kept
-- the Action-list behaviour exactly.
--
-- To re-record after a deliberate change in behaviour:
--
--   LCRR_RECORD_DIALOGS=1 busted spec/dialog_spec.lua
--
-- then read the diff of spec/fixtures/dialogs/ before committing it.

local harness = require("spec.support.script_harness")
local scenarios = require("spec.support.dialog_scenarios")

local ROOT = "spec/fixtures/dialogs/"
local RECORD = os.getenv("LCRR_RECORD_DIALOGS") == "1"

local function read(path)
  local handle = io.open(path, "r")
  if not handle then
    return nil
  end
  local text = handle:read("a")
  handle:close()
  return text
end

local function write(path, text)
  os.execute(('mkdir -p "%s"'):format(path:match("^(.*)/")))
  local handle = assert(io.open(path, "w"))
  handle:write(text)
  handle:close()
end

local function sorted_keys(map)
  local keys = {}
  for key in pairs(map) do
    keys[#keys + 1] = key
  end
  table.sort(keys)
  return keys
end

for _, script in ipairs(sorted_keys(scenarios)) do
  describe(script .. " from the Action list", function()
    local cases = scenarios[script]
    for _, case in ipairs(sorted_keys(cases)) do
      it(case, function()
        local path = ROOT .. script:gsub("%.lua$", "") .. "/" .. case .. ".txt"
        local transcript = harness.run(script, cases[case])
        if RECORD then
          write(path, transcript)
        end
        local expected = read(path)
        assert.is_not_nil(expected, "no recording at " .. path)
        assert.are.equal(expected, transcript)
        assert.is_nil(transcript:find("\nERROR ", 1, true), "the script raised an error")
      end)
    end
  end)
end
