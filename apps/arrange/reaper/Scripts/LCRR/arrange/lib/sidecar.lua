-- Arrangement sidecar: reading and writing `MySong.arrangements.lua`.
--
-- Per ADR-0003 an Arrangement is a named, ordered list of Region Names stored
-- beside the project as a Lua chunk returning a table. Nothing here calls
-- `reaper.*` -- the caller supplies the project path and does the file I/O.
--
-- The chunk is hand-edited, so `parse` treats it as untrusted input: it loads
-- in text-only mode with an empty environment and validates the shape before
-- returning. A sidecar with a typo produces a message, never a partially
-- applied Arrangement.
--
-- Two entry shapes, one meaning
-- ----------------------------
-- An entry is either a bare Region Name, as it always was, or a table carrying
-- the name positionally plus a `headroom` field -- the per-region end
-- adjustment in seconds (CONTEXT.md, Headroom):
--
--   return {
--     ["Full"]  = { { "Intro", headroom = 0 }, { "Verse 1", headroom = 4 } },
--     ["Radio"] = { "Intro", "Chorus" },  -- still valid, headroom 0 throughout
--   }
--
-- A bare string means a Headroom of `0`, so every sidecar written before the
-- feature existed keeps its exact meaning. `serialize` emits the table form
-- with an explicit `headroom = 0`, which is what makes the feature
-- discoverable in the one file the user edits.
--
-- **`parse` normalises both shapes to one.** What comes back is what an
-- Arrangement has always been -- a dense array of Region Name strings -- with
-- the Headroom carried beside it on a `headroom` field keyed by Region Name.
-- Every consumer that only wants the order (`lib/validate.lua`,
-- `report.verify`, the scripts) therefore needs no knowledge of Headroom at
-- all, and the one consumer that does (`regions.plan_pack`) reads a single
-- table rather than re-deriving it from mixed entry types.

local paths = require("lib.paths")

local sidecar = {}

local SIDECAR_SUFFIX = ".arrangements.lua"

--- Derive the sidecar path that sits beside a project file.
-- @param project_path string absolute path to a saved .RPP
-- @return string|nil sidecar path, or nil plus an error message
function sidecar.path_for(project_path)
  return paths.sibling(project_path, SIDECAR_SUFFIX, "an Arrangement sidecar")
end

-- Reject sparse or non-sequential arrays. `#` is undefined over holes, so the
-- count is taken by walking pairs rather than trusting the length operator.
local function is_dense_array(value)
  local count = 0
  for key in pairs(value) do
    if math.type(key) ~= "integer" or key < 1 then
      return false
    end
    count = count + 1
  end
  return count == #value
end

local function is_finite(value)
  return type(value) == "number" and value == value
    and value ~= math.huge and value ~= -math.huge
end

-- One entry, either shape, reduced to a Region Name and a Headroom.
--
-- A field this does not recognise is refused rather than ignored, and that is
-- the point rather than fussiness: `{ "Intro", headrom = 4 }` is a plausible
-- typo whose only other outcome is a Repack that silently does nothing to the
-- region the user was editing.
local function normalise_entry(name, index, entry)
  if type(entry) == "string" then
    if entry == "" then
      return nil, ("arrangement %q entry %d is an empty Region Name"):format(name, index)
    end
    return { name = entry, headroom = 0 }
  end

  if type(entry) ~= "table" then
    return nil, ("arrangement %q entry %d must be a Region Name string or a "
      .. "{ \"Region Name\", headroom = seconds } table, got %s"):format(name, index, type(entry))
  end

  local region_name = entry[1]
  if type(region_name) ~= "string" then
    return nil, ("arrangement %q entry %d must name a region in its first slot, got %s")
      :format(name, index, type(region_name))
  end
  if region_name == "" then
    return nil, ("arrangement %q entry %d is an empty Region Name"):format(name, index)
  end

  local headroom = entry.headroom
  if headroom ~= nil and not is_finite(headroom) then
    return nil, ("arrangement %q entry %d (%q) has a headroom that is not a finite number "
      .. "of seconds"):format(name, index, region_name)
  end

  for key in pairs(entry) do
    if key ~= 1 and key ~= "headroom" then
      return nil, ("arrangement %q entry %d (%q) has an unknown field %s -- an entry carries a "
        .. "Region Name and, optionally, `headroom`"):format(name, index, region_name, tostring(key))
    end
  end

  return { name = region_name, headroom = headroom or 0 }
end

local function validate(arrangements)
  if type(arrangements) ~= "table" then
    return nil, ("it must return a table, got %s"):format(type(arrangements))
  end

  local normalised = {}
  for name, entries in pairs(arrangements) do
    if type(name) ~= "string" then
      return nil, ("arrangement names must be strings, got %s"):format(type(name))
    end
    if type(entries) ~= "table" then
      return nil, ("arrangement %q must be a list of Region Names, got %s")
        :format(name, type(entries))
    end
    if not is_dense_array(entries) then
      return nil, ("arrangement %q must be a plain list with no gaps"):format(name)
    end

    local region_names, headroom, seen = {}, {}, {}
    for index, entry in ipairs(entries) do
      local parsed, entry_err = normalise_entry(name, index, entry)
      if not parsed then
        return nil, entry_err
      end
      -- One region cannot occupy two slots on a single repacked timeline.
      if seen[parsed.name] then
        return nil, ("arrangement %q names region %q twice, at entries %d and %d")
          :format(name, parsed.name, seen[parsed.name], index)
      end
      seen[parsed.name] = index
      region_names[#region_names + 1] = parsed.name
      headroom[parsed.name] = parsed.headroom
    end

    region_names.headroom = headroom
    normalised[name] = region_names
  end

  return normalised
end

--- Parse sidecar source into a table of Arrangements.
-- @param source string contents of the sidecar file
-- @return table|nil arrangements keyed by name, or nil plus an error message
function sidecar.parse(source)
  if type(source) ~= "string" then
    return nil, ("its contents must be a string, got %s"):format(type(source))
  end

  -- Mode "t" refuses precompiled chunks; the empty environment means a stray
  -- `os.time()` is a caught error rather than a call into the host.
  local chunk, load_err = load(source, "@arrangements", "t", {})
  if not chunk then
    return nil, ("it is not valid Lua (%s)"):format(load_err)
  end

  local ok, result = pcall(chunk)
  if not ok then
    return nil, ("it failed to run (%s)"):format(result)
  end

  return validate(result)
end

local ESCAPES = {
  ["\\"] = "\\\\",
  ['"'] = '\\"',
  ["\n"] = "\\n",
  ["\r"] = "\\r",
  ["\t"] = "\\t",
}

local function quote(text)
  return '"' .. text:gsub('[\\"\n\r\t]', ESCAPES) .. '"'
end

-- `%.14g` rather than `%g`: a Headroom is seconds a human typed, and the
-- default six significant digits would quietly round one back on every
-- rewrite. Integers still come out as `0` and `-2` rather than `0.0`.
local function number(value)
  return ("%.14g"):format(value)
end

--- Render Arrangements as sidecar source.
-- Arrangement names are sorted so that regenerating a sidecar produces a
-- minimal diff; Region Name order within an arrangement is the Arrangement.
--
-- Every entry is written in the table form with an explicit `headroom`, even
-- where it is `0`. That is deliberate: the sidecar is the only authoring
-- surface (ADR-0003), so it is also the only place the feature can be
-- discovered. The cost is a one-time diff the first time an existing project
-- is re-captured.
-- @param arrangements table arrangements keyed by name
-- @return string Lua source
function sidecar.serialize(arrangements)
  local names = {}
  for name in pairs(arrangements) do
    names[#names + 1] = name
  end
  table.sort(names)

  local out = {
    "-- REAPER Arrangements. Each entry is an ordered list of Region Names.",
    "-- `headroom` adjusts a region's end, in seconds; 0 leaves it alone, and the",
    "-- new end is always rounded to the nearest bar line. Shrinking may only ever",
    "-- remove silence -- a run refuses rather than cutting into a region's content.",
    "-- Edit freely; this file is read in a sandbox and validated on load.",
    "-- Capture and the Arrange page rewrite this whole file when they save, so",
    "-- comments and hand formatting are not kept.",
    "return {",
  }

  for _, name in ipairs(names) do
    local arrangement = arrangements[name]
    local headroom = arrangement.headroom or {}
    out[#out + 1] = ("  [%s] = {"):format(quote(name))
    for _, region_name in ipairs(arrangement) do
      out[#out + 1] = ("    { %s, headroom = %s },")
        :format(quote(region_name), number(headroom[region_name] or 0))
    end
    out[#out + 1] = "  },"
  end

  out[#out + 1] = "}"
  return table.concat(out, "\n") .. "\n"
end

--- Whether sidecar text is exactly what `serialize` writes for what it parses to.
-- Anything else (comments, hand formatting, bare-string entries, reordered keys,
-- CRLF line endings) would be changed by a rewrite, so Capture asks first.
-- @param source string contents of the sidecar file
-- @return boolean
function sidecar.is_canonical(source)
  local arrangements = sidecar.parse(source)
  return arrangements ~= nil and sidecar.serialize(arrangements) == source
end

--- A fingerprint of a sidecar's exact text (FNV-1a, 64 bit, as 16 hex digits).
-- An edit carries the revision it was based on; if the file's text has changed
-- since, the edit is refused rather than written over the change. A missing
-- file has the fixed revision "none". Pure Lua (Lua 5.4 integers wrap).
-- @param source string|nil contents of the file, nil when it does not exist
-- @return string
function sidecar.revision(source)
  if source == nil then
    return "none"
  end
  local hash = -3750763034362895579 -- 0xcbf29ce484222325
  for index = 1, #source do
    hash = (hash ~ source:byte(index)) * 1099511628211
  end
  return ("%016x"):format(hash)
end

--- The Arrangement names a sidecar holds, sorted.
-- Every script that prompts for an Arrangement name needs this list twice --
-- once for the prompt's caption and once for the "available:" line of a
-- refusal -- so it lives here rather than being rewritten per script.
-- @param arrangements table Arrangements keyed by name
-- @return table sorted list of names
function sidecar.names(arrangements)
  local names = {}
  for name in pairs(arrangements or {}) do
    names[#names + 1] = name
  end
  table.sort(names)
  return names
end

--- Read and parse the sidecar beside a project.
-- A missing sidecar is not an error: a project may simply have no Arrangements
-- yet. It comes back as `nil, nil, "missing"` so callers can tell that apart
-- from a sidecar that exists but will not parse -- ADR-0003 has the script
-- offer to import one in the first case and abort in the second.
-- @param project_path string
-- @param open function io.open-alike (injected for specs)
-- A fourth value says whether the file is canonical (`is_canonical`).
-- @return table|nil arrangements, string|nil error, string|nil reason, boolean|nil canonical
function sidecar.load(project_path, open)
  local path, path_err = sidecar.path_for(project_path)
  if not path then
    return nil, path_err, "unsaved"
  end

  local handle = (open or io.open)(path, "r")
  if not handle then
    return nil, nil, "missing"
  end

  local source = handle:read("a")
  handle:close()

  local arrangements, parse_err = sidecar.parse(source)
  if not arrangements then
    return nil, ("%s: %s"):format(path, parse_err), "invalid"
  end
  return arrangements, nil, nil, sidecar.is_canonical(source)
end

--- Write Arrangements to the sidecar beside a project.
-- @return string|nil path written, string|nil error
function sidecar.save(project_path, arrangements, open)
  local path, path_err = sidecar.path_for(project_path)
  if not path then
    return nil, path_err
  end

  local handle, open_err = (open or io.open)(path, "w")
  if not handle then
    return nil, open_err or ("could not write " .. path)
  end

  handle:write(sidecar.serialize(arrangements))
  handle:close()
  return path
end

return sidecar
