-- shared/startup/hook.lua: the lines in Scripts/__startup.lua that start the LCRR bridges with REAPER.
-- ReaPack cannot edit that file, so the "Install startup hook" / "Remove startup hook" actions do it with this module.
-- Pure text in, text out (`apply`), plus `run`, which does the file work through injected fs/api so specs can
-- fake it.
--
-- Each bridge has one marked line. It is replaced on every install and removed on remove; the user's own lines and
-- anything else in the file are left alone. Lines written by install.ps1 carry the same bridge id, so they are replaced
-- rather than duplicated.
--
-- A bridge cannot be dofile'd from __startup.lua (get_action_context() would name __startup.lua, and the bridge could
-- not find its lib/), so the line registers the bridge as an action and runs that. The line is tolerant: it runs the
-- bridge only if the file exists, so a stale line after an uninstall is silent. It looks in both places the suite
-- lands: Scripts/LCRR/<part>/ (install.ps1) and Scripts/LCRR/Remote/<part>/ (ReaPack: index name LCRR, category
-- Remote).

local M = {}

M.bridges = {
  { name = "Arrange", id = "LCRR-ARRANGE-BRIDGE", script = "arrange/LCRR_Arrange_Bridge.lua" },
  { name = "IEM Setup", id = "LCRR-IEM-BRIDGE", script = "iem/LCRR_IEM_Bridge.lua" },
}

function M.line(bridge)
  return 'do local r = reaper.GetResourcePath() .. "/Scripts/LCRR/"; '
    .. 'for _, d in ipairs({"", "Remote/"}) do local p = r .. d .. "' .. bridge.script .. '"; '
    .. "if reaper.file_exists(p) then local id = reaper.AddRemoveReaScript(true, 0, p, true); "
    .. "if id ~= 0 then reaper.Main_OnCommand(id, 0) end break end end end "
    .. "-- " .. bridge.id .. " (managed by LCRR startup hook)"
end

local function split_lines(text)
  local lines = {}
  local pos = 1
  while pos <= #text do
    local nl = text:find("\n", pos, true)
    if nl then
      lines[#lines + 1] = text:sub(pos, nl - 1)
      pos = nl + 1
    else
      lines[#lines + 1] = text:sub(pos)
      break
    end
  end
  return lines
end

local function is_ours(line)
  for _, b in ipairs(M.bridges) do
    if line:find(b.id, 1, true) then return true end
  end
  return false
end

-- present = true: our lines are (re)written at the end. false: they are removed. Returns the new file text
-- ("" when nothing is left).
function M.apply(text, present)
  local kept = {}
  for _, line in ipairs(split_lines(text)) do
    if not is_ours(line) then kept[#kept + 1] = line end
  end
  if present then
    for _, b in ipairs(M.bridges) do kept[#kept + 1] = M.line(b) end
  end
  if #kept == 0 then return "" end
  return table.concat(kept, "\n") .. "\n"
end

-- ctx = { api = reaper, fs = { read(path) -> text|nil, write(path, text), remove(path) } }.
-- Returns a message for the user.
function M.run(ctx, present)
  local path = ctx.api.GetResourcePath() .. "/Scripts/__startup.lua"
  local old = ctx.fs.read(path)
  local new = M.apply(old or "", present)
  if new == "" then
    if old ~= nil then ctx.fs.remove(path) end
  else
    ctx.fs.write(path, new)
  end
  if present then
    return "The LCRR bridges (Arrange, IEM Setup) will now start with REAPER. Restart REAPER, or run the bridge "
      .. "actions once by hand, to start them now."
  end
  return "The LCRR bridges no longer start with REAPER. Any already running stay on until REAPER closes."
end

-- The real file access, for the entry scripts.
function M.real_fs()
  return {
    read = function(p)
      local f = io.open(p, "rb")
      if not f then return nil end
      local t = f:read("a")
      f:close()
      return t
    end,
    write = function(p, t)
      local f = assert(io.open(p, "wb"))
      f:write(t)
      f:close()
    end,
    remove = function(p) os.remove(p) end,
  }
end

return M
