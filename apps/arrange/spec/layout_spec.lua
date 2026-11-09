-- Guards the reaper/ slice layout, not the suite's behaviour.
--
-- Inside REAPER each script extends package.path from its own folder
-- (get_action_context), and lib/ must sit beside it. Specs load lib/ through
-- .busted's lpath instead, so nothing else here would notice a script whose
-- package.path line no longer matches where lib/ actually is: it would pass
-- every spec and fail in REAPER with "module 'lib.project' not found".
local SCRIPT_DIR = "reaper/Scripts/LCRR/arrange"

local function scripts()
  local list = {}
  local pipe = assert(io.popen('ls "' .. SCRIPT_DIR .. '"'))
  for name in pipe:lines() do
    if name:match("^LCRR_Arrange_.+%.lua$") then list[#list + 1] = name end
  end
  pipe:close()
  table.sort(list)
  return list
end

local function read(path)
  local handle = assert(io.open(path, "r"), "missing: " .. path)
  local source = handle:read("a")
  handle:close()
  return source
end

describe("reaper/ slice layout", function()
  local names = scripts()

  it("finds the entry scripts", function()
    assert.is_true(#names >= 8, "expected the LCRR_Arrange_*.lua scripts in " .. SCRIPT_DIR)
  end)

  for _, name in ipairs(names) do
    it(name .. " resolves every lib module it requires from its own folder", function()
      local source = read(SCRIPT_DIR .. "/" .. name)
      local requires = {}
      -- Dotted, so a front end's `lib.core.<action>` is checked as well.
      for module in source:gmatch('require%("(lib%.[%w_.]+)"%)') do
        requires[#requires + 1] = module
      end
      if #requires == 0 then return end

      local suffix = source:match('package%.path = script_dir %.%. "([^"]*)" %.%. package%.path')
      assert.is_not_nil(suffix, name .. " requires lib/ but never extends package.path")
      local search = SCRIPT_DIR .. suffix:gsub(";$", "")
      for _, module in ipairs(requires) do
        assert.is_not_nil(package.searchpath(module, search),
          ("%s: %s not found via %s"):format(name, module, search))
      end
    end)
  end
end)
