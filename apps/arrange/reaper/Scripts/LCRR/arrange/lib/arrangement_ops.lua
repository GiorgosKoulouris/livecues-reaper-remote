-- Operations on parsed Arrangements (the tables `lib/sidecar.lua` parses and
-- serialises), for the page's editor (ADR-0009). Pure: no `reaper.*`, no files.
--
-- An Arrangements table is `{ [name] = { "Region", ..., headroom = { Region =
-- seconds } } }`. Every operation validates, copies, and returns the new table
-- (the argument is never changed), or `nil, code` with a refusal code:
--
--   name_empty, name_taken, arrangement_not_found,
--   region_empty, region_repeated, region_not_in_arrangement,
--   slot_invalid, headroom_invalid
--
-- Names are trimmed by the caller (`env.trim`); a name that is blank after
-- that is `name_empty`. Region names are taken exactly as given.

local ops = {}

local function is_finite(value)
  return type(value) == "number" and value == value
    and value ~= math.huge and value ~= -math.huge
end

local function copy_arrangement(arrangement)
  local out = {}
  for index, region in ipairs(arrangement) do
    out[index] = region
  end
  out.headroom = {}
  for region, seconds in pairs(arrangement.headroom or {}) do
    out.headroom[region] = seconds
  end
  return out
end

local function copy_all(arrangements)
  local out = {}
  for name, arrangement in pairs(arrangements) do
    out[name] = copy_arrangement(arrangement)
  end
  return out
end

local function index_of(arrangement, region)
  for index, entry in ipairs(arrangement) do
    if entry == region then
      return index
    end
  end
  return nil
end

-- The copy of `arrangements` and the copy of the named Arrangement within it.
local function open(arrangements, name)
  if arrangements[name] == nil then
    return nil, nil, "arrangement_not_found"
  end
  local all = copy_all(arrangements)
  return all, all[name]
end

local function fresh_name(arrangements, name)
  if type(name) ~= "string" or name == "" then
    return "name_empty"
  end
  if arrangements[name] ~= nil then
    return "name_taken"
  end
  return nil
end

--- Move a region to a 1-based slot. Slots past the end are refused.
function ops.move(arrangements, name, region, slot)
  local all, arrangement, err = open(arrangements, name)
  if not all then
    return nil, err
  end
  local from = index_of(arrangement, region)
  if not from then
    return nil, "region_not_in_arrangement"
  end
  if math.type(slot) ~= "integer" or slot < 1 or slot > #arrangement then
    return nil, "slot_invalid"
  end
  table.remove(arrangement, from)
  table.insert(arrangement, slot, region)
  return all
end

--- Set one region's Headroom, in seconds (negative is allowed).
function ops.set_headroom(arrangements, name, region, seconds)
  local all, arrangement, err = open(arrangements, name)
  if not all then
    return nil, err
  end
  if not index_of(arrangement, region) then
    return nil, "region_not_in_arrangement"
  end
  if not is_finite(seconds) then
    return nil, "headroom_invalid"
  end
  arrangement.headroom[region] = seconds
  return all
end

--- Add a region at a 1-based slot, or at the end when `slot` is nil.
-- A new entry has a Headroom of 0.
function ops.add(arrangements, name, region, slot)
  local all, arrangement, err = open(arrangements, name)
  if not all then
    return nil, err
  end
  if type(region) ~= "string" or region == "" then
    return nil, "region_empty"
  end
  if index_of(arrangement, region) then
    return nil, "region_repeated"
  end
  slot = slot == nil and #arrangement + 1 or slot
  if math.type(slot) ~= "integer" or slot < 1 or slot > #arrangement + 1 then
    return nil, "slot_invalid"
  end
  table.insert(arrangement, slot, region)
  arrangement.headroom[region] = 0
  return all
end

--- Remove a region (and its Headroom).
function ops.remove(arrangements, name, region)
  local all, arrangement, err = open(arrangements, name)
  if not all then
    return nil, err
  end
  local from = index_of(arrangement, region)
  if not from then
    return nil, "region_not_in_arrangement"
  end
  table.remove(arrangement, from)
  arrangement.headroom[region] = nil
  return all
end

--- Set every region's Headroom to 0, keeping order. The post-Apply offer.
function ops.clear_headroom(arrangements, name)
  local all, arrangement, err = open(arrangements, name)
  if not all then
    return nil, err
  end
  for _, region in ipairs(arrangement) do
    arrangement.headroom[region] = 0
  end
  return all
end

--- A new, empty Arrangement. An empty Arrangement is a valid thing to save.
function ops.new(arrangements, name)
  local err = fresh_name(arrangements, name)
  if err then
    return nil, err
  end
  local all = copy_all(arrangements)
  all[name] = { headroom = {} }
  return all
end

--- A copy of `name` under `new_name`.
function ops.duplicate(arrangements, name, new_name)
  if arrangements[name] == nil then
    return nil, "arrangement_not_found"
  end
  local err = fresh_name(arrangements, new_name)
  if err then
    return nil, err
  end
  local all = copy_all(arrangements)
  all[new_name] = copy_arrangement(arrangements[name])
  return all
end

--- Rename `name` to `new_name`.
function ops.rename(arrangements, name, new_name)
  if arrangements[name] == nil then
    return nil, "arrangement_not_found"
  end
  local err = fresh_name(arrangements, new_name)
  if err then
    return nil, err
  end
  local all = copy_all(arrangements)
  all[new_name], all[name] = all[name], nil
  return all
end

--- Delete `name`.
function ops.delete(arrangements, name)
  if arrangements[name] == nil then
    return nil, "arrangement_not_found"
  end
  local all = copy_all(arrangements)
  all[name] = nil
  return all
end

return ops
