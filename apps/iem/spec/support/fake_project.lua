-- A stand-in for the `reaper` table: enough to read tracks, folder depth,
-- receives and hardware outputs, and to make the changes the write cores make
-- (insert and name tracks, folder depth, master send, colour, selection,
-- reordering, project ExtState).
--
-- Every change must happen inside an undo block: one made outside is recorded in
-- `api.outside_block` (specs assert it stays empty). `api.undo_steps` lists the
-- description of each closed block; `api.ext` is the project ExtState.
--
--   local api = fake_project.new({
--     path = "C:/Show/Gig.rpp",
--     tracks = {
--       { name = "Kick" },
--       { name = "IEMs", depth = 1 },
--       { name = "IEM_Drums", depth = -1, outputs = { { dest = 2 } },
--         receives = { { from = "Kick", vol = 0.5, mode = 3 } } },
--     },
--   })
--
-- Tracks are named in `from` (first match) so a spec reads as a sentence. The
-- GUID of track N is "{GUID-N}" unless `guid` is given.

local fake_project = {}

function fake_project.new(spec)
  local tracks = {}
  for index, given in ipairs(spec.tracks or {}) do
    tracks[index] = {
      name = given.name or "",
      guid = given.guid or ("{GUID-%d}"):format(index),
      depth = given.depth or 0,
      main_send = given.main_send == nil and 1 or (given.main_send and 1 or 0),
      colour = given.colour or 0,
      selected = given.selected or false,
      outputs = given.outputs or {},
      receives = given.receives or {},
    }
  end

  local function by_name(name)
    for _, track in ipairs(tracks) do
      if track.name == name then return track end
    end
    error("fake_project: no track named " .. tostring(name))
  end

  -- Every receive is also a send of its source (category 0 on the source), listed in project order of the receivers.
  for _, track in ipairs(tracks) do
    track.sends = track.sends or {}
  end
  for _, track in ipairs(tracks) do
    for _, receive in ipairs(track.receives) do
      receive.dest = track
      local source = by_name(receive.from)
      receive.src_track = source
      source.sends[#source.sends + 1] = receive
    end
  end

  -- The master track (its hardware outputs only) and the audio device: `device` lists the output channel names,
  -- empty (the default) is a closed device.
  local master = { name = "MASTER", guid = "{MASTER}", outputs = spec.master_outputs or {}, receives = {} }
  local device = spec.device or {}

  local api = { tracks = tracks, ext = spec.ext or {}, undo_steps = {}, outside_block = {}, open_blocks = 0 }
  local inserted = 0

  local function changing(what)
    if api.open_blocks == 0 then api.outside_block[#api.outside_block + 1] = what end
  end

  function api.EnumProjects() return nil, spec.path or "" end
  function api.CountTracks() return #tracks end
  function api.GetTrack(_, index) return tracks[index + 1] end
  function api.GetTrackGUID(track) return track.guid end

  function api.GetSetMediaTrackInfo_String(track, key, value, set)
    assert(key == "P_NAME", "fake_project: only P_NAME")
    if set then
      changing("rename")
      track.name = value
    end
    return true, track.name
  end

  function api.SetMediaTrackInfo_Value(track, key, value)
    changing("set " .. key)
    if key == "I_FOLDERDEPTH" then track.depth = value
    elseif key == "B_MAINSEND" then track.main_send = value
    elseif key == "I_CUSTOMCOLOR" then track.colour = value
    else error("fake_project: unmodelled track key " .. key) end
    return true
  end

  function api.InsertTrackAtIndex(index, _)
    changing("insert")
    inserted = inserted + 1
    table.insert(tracks, index + 1, {
      name = "", guid = ("{NEW-%d}"):format(inserted), depth = 0, main_send = 1, colour = 0, selected = false,
      outputs = {}, receives = {}, sends = {},
    })
  end

  -- Deleting takes the track's own sends with it, and any receive from it. Depths
  -- of the others are left alone: REAPER does not repair them (suite CONTEXT.md).
  function api.DeleteTrack(track)
    changing("delete")
    for index, candidate in ipairs(tracks) do
      if candidate == track then table.remove(tracks, index) break end
    end
    for _, other in ipairs(tracks) do
      for index = #other.receives, 1, -1 do
        if other.receives[index].src_track == track then table.remove(other.receives, index) end
      end
      for index = #other.sends, 1, -1 do
        if other.sends[index].dest == track then table.remove(other.sends, index) end
      end
    end
  end

  function api.GetMasterTrack() return master end
  function api.GetNumAudioOutputs() return #device end
  function api.GetOutputChannelName(index) return device[index + 1] end

  function api.CreateTrackSend(track, dest)
    changing("create send")
    if dest then
      -- A send to another track: new sends default to post-fader, 0 dB, as REAPER's own do (suite CONTEXT.md).
      local receive = { from = track.name, src_track = track, dest = dest, vol = 1.0, mode = 0 }
      dest.receives[#dest.receives + 1] = receive
      track.sends[#track.sends + 1] = receive
      return #track.sends - 1
    end
    track.outputs[#track.outputs + 1] = { dest = 0, src = 0 }
    return #track.outputs - 1
  end
  function api.RemoveTrackSend(track, category, index)
    changing("remove send")
    if category == 0 then
      local receive = table.remove(track.sends, index + 1)
      for position, candidate in ipairs(receive.dest.receives) do
        if candidate == receive then table.remove(receive.dest.receives, position) break end
      end
      return true
    end
    assert(category == 1, "fake_project: only sends and hardware outputs")
    table.remove(track.outputs, index + 1)
    return true
  end
  function api.SetTrackSendInfo_Value(track, category, index, key, value)
    changing("set send " .. key)
    if category == 0 then
      local receive = track.sends[index + 1]
      if key == "I_SENDMODE" then receive.mode = value
      elseif key == "D_VOL" then receive.vol = value
      elseif key == "D_PAN" then receive.pan = value
      elseif key == "B_MUTE" then receive.muted = value ~= 0
      else error("fake_project: unmodelled send key " .. key) end
      return true
    end
    assert(category == 1, "fake_project: only sends and hardware outputs")
    local out = track.outputs[index + 1]
    if key == "I_DSTCHAN" then out.dest = value
    elseif key == "I_SRCCHAN" then out.src = value
    else error("fake_project: unmodelled output key " .. key) end
    return true
  end

  function api.ColorToNative(r, g, b) return r + g * 256 + b * 65536 end

  function api.IsTrackSelected(track) return track.selected end
  function api.SetTrackSelected(track, selected)
    changing("select")
    track.selected = selected and true or false
  end

  -- Selected tracks go before the track at index `before` (CountTracks: the end) in their order; depths travel with
  -- them (makePrevFolder 0), as measured in the issue 01 spike.
  function api.ReorderSelectedTracks(before, make_prev_folder)
    changing("reorder")
    assert(make_prev_folder == 0, "fake_project: only 'keep depths'")
    local kept, moved, position = {}, {}, nil
    for index, track in ipairs(tracks) do
      if track.selected then table.insert(moved, track)
      else
        if index - 1 >= before and not position then position = #kept + 1 end
        table.insert(kept, track)
      end
    end
    position = position or #kept + 1
    for index = #tracks, 1, -1 do tracks[index] = nil end
    for index = 1, position - 1 do tracks[#tracks + 1] = kept[index] end
    for _, track in ipairs(moved) do tracks[#tracks + 1] = track end
    for index = position, #kept do tracks[#tracks + 1] = kept[index] end
  end

  function api.GetProjExtState(_, section, key)
    local value = api.ext[section .. "/" .. key]
    if value == nil then return 0, "" end
    return 1, value
  end
  function api.SetProjExtState(_, section, key, value)
    changing("ext state")
    api.ext[section .. "/" .. key] = value
    return 0
  end

  function api.Undo_BeginBlock2() api.open_blocks = api.open_blocks + 1 end
  function api.Undo_EndBlock2(_, description)
    assert(api.open_blocks > 0, "fake_project: EndBlock without BeginBlock")
    api.open_blocks = api.open_blocks - 1
    api.undo_steps[#api.undo_steps + 1] = description
  end
  function api.PreventUIRefresh() end
  function api.TrackList_AdjustWindows() end
  function api.UpdateArrange() end

  function api.GetMediaTrackInfo_Value(track, key)
    if key == "I_FOLDERDEPTH" then return track.depth end
    if key == "B_MAINSEND" then return track.main_send end
    if key == "I_CUSTOMCOLOR" then return track.colour end
    error("fake_project: unmodelled track key " .. key)
  end

  function api.GetTrackNumSends(track, category)
    if category == -1 then return #track.receives end
    if category == 1 then return #track.outputs end
    if category == 0 then return #track.sends end
    error("fake_project: bad category " .. tostring(category))
  end

  function api.GetTrackSendInfo_Value(track, category, index, key)
    if category == 0 then
      local send = track.sends[index + 1]
      if key == "P_DESTTRACK" then return send.dest end
      error("fake_project: unmodelled send key " .. key)
    end
    if category == 1 then
      local output = track.outputs[index + 1]
      if key == "I_DSTCHAN" then return output.dest end
      if key == "I_SRCCHAN" then return output.src or 0 end
      error("fake_project: unmodelled output key " .. key)
    end
    assert(category == -1, "fake_project: only receives and outputs")
    local receive = track.receives[index + 1]
    if key == "P_SRCTRACK" then return receive.src_track end
    if key == "D_VOL" then return receive.vol or 1.0 end
    if key == "D_PAN" then return receive.pan or 0.0 end
    if key == "B_MUTE" then return receive.muted and 1 or 0 end
    if key == "I_SENDMODE" then return receive.mode or 3 end
    error("fake_project: unmodelled send key " .. key)
  end

  return api
end

return fake_project
