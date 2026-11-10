-- Luacheck configuration for the shared Lua. Same rules as apps/arrange/.luacheckrc.
std = "lua54"

read_globals = {
  "reaper",
  "gfx",
}

files["spec/"] = {
  std = "+busted",
}
