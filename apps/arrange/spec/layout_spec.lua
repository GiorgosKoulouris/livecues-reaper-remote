-- Guards the reaper/ slice layout, not the suite's behaviour.
--
-- Inside REAPER each script extends package.path from its own folder
-- (get_action_context), and lib/ must sit beside it. Specs load lib/ through
-- .busted's lpath instead, so nothing else here would notice a script whose
-- package.path line no longer matches where lib/ actually is: it would pass
-- every spec and fail in REAPER with "module 'lib.project' not found".
--
-- Shared Lua (shared.*) sits beside the app folder once installed
-- (Scripts\LCRR\shared next to Scripts\LCRR\arrange), so a script that
-- requires it must also add its parent folder. In the repo that folder is the
-- shared/ slice, which is where the guard looks for the module.
local SCRIPT_DIR = "reaper/Scripts/LCRR/arrange"
local SHARED_SLICE = "../../shared/reaper/Scripts/LCRR"

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
      local own, shared = {}, {}
      -- Dotted, so a front end's `lib.core.<action>` is checked as well.
      for module in source:gmatch('require%("(lib%.[%w_.]+)"%)') do
        own[#own + 1] = module
      end
      for module in source:gmatch('require%("(shared%.[%w_.]+)"%)') do
        shared[#shared + 1] = module
      end
      if #own + #shared == 0 then return end

      local suffixes = {}
      for suffix in source:gmatch('package%.path = script_dir %.%. "([^"]*)" %.%. package%.path') do
        suffixes[#suffixes + 1] = suffix:gsub(";$", "")
      end
      assert.is_true(#suffixes > 0, name .. " requires modules but never extends package.path")

      local function has(suffix)
        for _, found in ipairs(suffixes) do
          if found == suffix then return true end
        end
        return false
      end

      if #own > 0 then
        assert.is_true(has("/?.lua"), name .. " requires lib/ but does not put its own folder on package.path")
        for _, module in ipairs(own) do
          assert.is_not_nil(package.searchpath(module, SCRIPT_DIR .. "/?.lua"),
            ("%s: %s not found beside the script"):format(name, module))
        end
      end
      if #shared > 0 then
        assert.is_true(has("/../?.lua"), name .. " requires shared/ but does not put its parent folder on package.path")
        for _, module in ipairs(shared) do
          assert.is_not_nil(package.searchpath(module, SHARED_SLICE .. "/?.lua"),
            ("%s: %s not found in the shared slice"):format(name, module))
        end
      end
    end)
  end
end)
