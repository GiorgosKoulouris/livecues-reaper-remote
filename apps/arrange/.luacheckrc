-- Luacheck configuration.
--
-- luacheck itself runs under lua5.1 (see its shebang), which is irrelevant --
-- `std` below is what governs the syntax and globals it accepts.
std = "lua54"

-- REAPER injects these into every script's environment. Declaring them
-- read_globals is what makes a typo'd API name (reaper.CountProjectMarkerz) a
-- lint error here instead of a nil-index crash inside the DAW.
read_globals = {
  "reaper",
  "gfx",
}

-- Scripts are entry points invoked by REAPER; they legitimately have no exports.
-- The glob matches the entry scripts only: lib/ sits beside them in the same
-- folder and keeps the stricter default.
files["reaper/Scripts/LCRR/arrange/*.lua"] = {
  ignore = { "212" }, -- unused argument
}

files["spec/"] = {
  std = "+busted",
}

exclude_files = {
  "spec/fixtures/",
}
