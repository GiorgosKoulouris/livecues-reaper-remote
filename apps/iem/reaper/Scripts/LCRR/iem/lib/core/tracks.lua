-- What every IEM core needs to know about the track list: names, the IEMs
-- folder and where it ends, the shared colour, and finding a track by GUID.
-- Headless and free of sentences (Arrange ADR-0008): refusals are codes.
--
-- A **mix** is `IEM_<name>` (Monitor's rule). The **folder** is the first track
-- named `IEMs`; it holds tracks only while its `I_FOLDERDEPTH` is 1 (an emptied
-- folder is a plain track, suite CONTEXT.md). `scan` reads every track once;
-- `find_folder` says where the folder's members end.

local tracks = {}

tracks.MIX_PREFIX = "IEM_"
tracks.FOLDER_NAME = "IEMs"
-- The cue track IEM Mix listens through: exact and case-sensitive, and not a mix (no `IEM_` prefix).
tracks.CUE_NAME = "IEM-Cue"

-- The colour of the folder and its mixes lives in the project (ExtState), so it
-- travels with the .rpp. `DEFAULT_COLOUR` is used until the engineer picks one.
tracks.EXT_SECTION = "LCRR_IEM"
tracks.EXT_COLOUR = "colour"
tracks.DEFAULT_COLOUR = "3b82c4"

function tracks.name(api, track)
  local _, name = api.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
  return name or ""
end

function tracks.is_mix_name(name)
  return name:sub(1, #tracks.MIX_PREFIX) == tracks.MIX_PREFIX and #name > #tracks.MIX_PREFIX
end

--- Every track in project order: { track, index (0-based), name, guid, depth }.
function tracks.scan(api)
  local list = {}
  for index = 0, api.CountTracks(0) - 1 do
    local track = api.GetTrack(0, index)
    list[#list + 1] = {
      track = track,
      index = index,
      name = tracks.name(api, track),
      guid = api.GetTrackGUID(track),
      depth = math.floor(api.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")),
    }
  end
  return list
end

--- The IEMs folder: the first track named `IEMs`, with `last` the 0-based index
--- of its last member (itself when it holds nothing). Nil when there is none.
function tracks.find_folder(list)
  for position, entry in ipairs(list) do
    if entry.name == tracks.FOLDER_NAME then
      local last = entry.index
      if entry.depth == 1 then
        local level = 1
        for next_position = position + 1, #list do
          level = level + list[next_position].depth
          last = list[next_position].index
          if level <= 0 then break end
        end
      end
      return { entry = entry, index = entry.index, last = last, depth = entry.depth, open = entry.depth == 1 }
    end
  end
  return nil
end

--- The cue track: the first track named `IEM-Cue` (a later one is an ordinary source), as the folder is the first
--- `IEMs`. Nil when there is none.
function tracks.find_cue(list)
  for _, entry in ipairs(list) do
    if entry.name == tracks.CUE_NAME then return entry end
  end
  return nil
end

function tracks.find_by_guid(list, guid)
  for _, entry in ipairs(list) do
    if entry.guid == guid then return entry end
  end
  return nil
end

--- Whether the entry is a source: any track that is not a mix, not the IEMs folder and not the cue track (a second
--- track named `IEMs` or `IEM-Cue` is an ordinary source). The cue track is never a source, so no cell can feed it
--- back into a mix.
function tracks.is_source(list, entry)
  local folder = tracks.find_folder(list)
  return not tracks.is_mix_name(entry.name) and not (folder and folder.entry == entry)
    and tracks.find_cue(list) ~= entry
end

--- A refusal reply: a code and nothing else (wording is the page's).
function tracks.refusal(code)
  return { status = "refused", error = { code = code } }
end

--- The mix with this GUID, or nil and the refusal code: `track_gone` (no such track), `not_a_mix` (its name
--- is not `IEM_<name>`).
function tracks.find_mix(list, guid)
  local entry = tracks.find_by_guid(list, guid or "")
  if not entry then return nil, "track_gone" end
  if not tracks.is_mix_name(entry.name) then return nil, "not_a_mix" end
  return entry
end

--- A mix name as typed: trimmed, never empty, and not already taken.
-- @param own table|nil the entry being renamed (it may keep its own name)
-- @return string|nil the clean name
-- @return string|nil refusal code: `empty_name` or `duplicate_name`
function tracks.check_name(list, raw, own)
  local name = (raw or ""):match("^%s*(.-)%s*$")
  if name == "" then return nil, "empty_name" end
  local full = tracks.MIX_PREFIX .. name
  for _, entry in ipairs(list) do
    if entry.name == full and entry ~= own then return nil, "duplicate_name" end
  end
  return name
end

-- A hardware output's I_DSTCHAN: the low bits are the first device channel (0-based), bit 1024 marks a mono
-- downmix (suite CONTEXT.md, issue 01). A stereo output occupies `channel` and `channel + 1`.
tracks.DEST_MONO = 1024
tracks.DEST_CHANNEL = 1023

--- A track's hardware outputs as `{ channel, mono }`, in REAPER's order.
function tracks.outputs(api, track)
  local outputs = {}
  for index = 0, api.GetTrackNumSends(track, 1) - 1 do
    local dest = math.floor(api.GetTrackSendInfo_Value(track, 1, index, "I_DSTCHAN"))
    outputs[#outputs + 1] = { channel = dest & tracks.DEST_CHANNEL, mono = (dest & tracks.DEST_MONO) ~= 0 }
  end
  return outputs
end

function tracks.valid_colour(hex)
  return type(hex) == "string" and hex:match("^%x%x%x%x%x%x$") ~= nil
end

--- The shared colour as `rrggbb`: the project's, or the default.
function tracks.colour(api)
  local found, value = api.GetProjExtState(0, tracks.EXT_SECTION, tracks.EXT_COLOUR)
  if found and found ~= 0 and tracks.valid_colour(value) then return value:lower() end
  return tracks.DEFAULT_COLOUR
end

function tracks.set_colour(api, track, hex)
  local r, g, b = tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16)
  api.SetMediaTrackInfo_Value(track, "I_CUSTOMCOLOR", api.ColorToNative(r, g, b) | 0x1000000)
end

function tracks.new_track(api, at, name, depth, colour)
  api.InsertTrackAtIndex(at, false)
  local track = api.GetTrack(0, at)
  api.GetSetMediaTrackInfo_String(track, "P_NAME", name, true)
  api.SetMediaTrackInfo_Value(track, "I_FOLDERDEPTH", depth)
  api.SetMediaTrackInfo_Value(track, "B_MAINSEND", 0)
  tracks.set_colour(api, track, colour)
  return track
end

--- Make room for one more mix at the end of the IEMs folder, creating the folder when there is none (`folder` is
--- `tracks.find_folder(list)`). Edits the depths around the slot; returns the 0-based index the mix takes (a track
--- inserted there, or an existing one moved before it, lands in the folder) and the depth it needs. Call inside an
--- undo block. Used by `create` and `adopt`.
function tracks.open_slot(api, list, folder, colour)
  local at, depth
  if not folder then
    -- At the end of the list, so nothing is swallowed; the mix follows it.
    tracks.new_track(api, #list, tracks.FOLDER_NAME, 1, colour)
    at, depth = #list + 1, -1
  elseif folder.open and folder.last > folder.index then
    -- The old last member closed the folder (and maybe parents of it): the
    -- new one takes over that closing.
    local last = list[folder.last + 1]
    depth = math.min(last.depth, -1)
    api.SetMediaTrackInfo_Value(last.track, "I_FOLDERDEPTH", 0)
    at = folder.last + 1
  elseif folder.open then
    at, depth = folder.index + 1, -1 -- an open folder with nothing in it
  else
    -- An emptied folder is a plain track: open it, and let the mix close it
    -- along with whatever the folder itself used to close.
    depth = folder.depth - 1
    api.SetMediaTrackInfo_Value(folder.entry.track, "I_FOLDERDEPTH", 1)
    at = folder.index + 1
  end
  return at, depth
end

--- Repair the folder depths around a track that is about to leave its place (deleted or moved), as REAPER does not
--- (suite CONTEXT.md): what it closed (depth < 0) goes to the track before it, what it opened (depth > 0) to the
--- track that closed it. `list` is `tracks.scan` from before the change; the track's own depth is left alone.
--- Shared by `delete` and `adopt`.
function tracks.repair_depth(api, list, target)
  local position = target.index + 1
  if target.depth < 0 and position > 1 then
    local before = list[position - 1]
    api.SetMediaTrackInfo_Value(before.track, "I_FOLDERDEPTH", before.depth + target.depth)
  elseif target.depth > 0 then
    local level = target.depth
    for next_position = position + 1, #list do
      level = level + list[next_position].depth
      if level <= 0 then
        local closer = list[next_position]
        api.SetMediaTrackInfo_Value(closer.track, "I_FOLDERDEPTH", closer.depth + target.depth)
        break
      end
    end
  end
end

return tracks
