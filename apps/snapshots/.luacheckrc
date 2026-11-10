-- Luacheck configuration.
std = "lua54"

-- REAPER injects `reaper` into every script's environment; declaring it
-- read_globals makes a typo'd API name a lint error here instead of a nil-index
-- crash inside the DAW.
read_globals = {
  "reaper",
}

-- Entry points invoked by REAPER; they legitimately have no exports.
files["reaper/Scripts/LCRR/snapshots/*.lua"] = {
  ignore = { "212" }, -- unused argument
}

files["spec/"] = {
  std = "+busted",
}
