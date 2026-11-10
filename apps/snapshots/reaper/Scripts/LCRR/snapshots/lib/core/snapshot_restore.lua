-- The `snapshot_restore` core: write a saved snapshot's values back to the active project, in ONE undo step (unlike
-- save, overwrite and delete, which touch project ExtState and so cannot be undone).
--
--   snapshot_restore.run({ api, fields = { name, ticks } })
--     -> { status = "ok", name, tracks, sends, skipped, automated, muted_skipped }
--      | refused: `empty_name`, `bad_name`, `name_too_long`, `not_found`, `unreadable`, `no_ticks` (no tick at all),
--        `bad_ticks` (a letter that is no tick)
--
-- `ticks` is a compact string, one letter per tick that is on (any order): L levels, P pans, M mutes, S solos,
-- R polarity, E sends (every send's and hardware output's volume, pan, mute and mode), F FX on/off,
-- I in-ears. The Master follows the same ticks as any track. With I on, every in-ear value is written whatever the
-- other ticks say; with I off none is.
--
-- Tracks are matched by GUID (the Master by its key), a send by its destination GUID and its order among the sends
-- of that pair, a hardware output by its order. Anything gone is skipped and counted in `skipped`; tracks and sends
-- added since the save are left alone; nothing is ever created or removed. `tracks` counts the tracks (Master
-- included) that had a value written, `sends` the sends and outputs written. In-ear tracks and every send into one
-- are recognised by their current names (`IEM_<name>`, `IEM-Cue`, the first `IEMs`) and, with I off, left alone and
-- not counted.
--
-- `automated` counts the written values (track and send volume, pan and mute) with active automation, and
-- `muted_skipped` the mutes left alone because they would reach a Mute envelope in a writing mode (core `automation`,
-- ADR-0001). Neither is part of `skipped`, which is only what is gone.
--
-- Plan first, write afterwards: every refusal comes before the undo block opens, and nothing to write means no undo
-- step. Levels and pans are written as `D_VOL` and `D_PAN`, never the UI functions. A stored `I_SOLO` of 5 is
-- written as 1 and 6 as 2, because writing 5 or 6 reads back 0 (suite CONTEXT.md).

local store = require("lib.core.snapshot_store")
local undo = require("lib.core.undo")
local refusal = require("lib.core.snapshots").refusal
local automation = require("lib.core.automation")

local snapshot_restore = {}

local SEND_CATEGORY, OUTPUT_CATEGORY = 0, 1
local IN_EAR_PREFIX, IN_EAR_CUE, IN_EAR_FOLDER = "IEM_", "IEM-Cue", "IEMs"

snapshot_restore.TICKS = "LPMSREFI"

-- Track keys each tick writes, with the saved field they come from.
local TRACK_TICKS = {
  L = { { "D_VOL", "vol" } },
  P = { { "I_PANMODE", "pan_mode" }, { "D_PAN", "pan" }, { "D_WIDTH", "width" }, { "D_DUALPANL", "dual_l" },
    { "D_DUALPANR", "dual_r" } },
  M = { { "B_MUTE", "mute" } },
  S = { { "I_SOLO", "solo" } },
  R = { { "B_PHASE", "phase" } },
  F = { { "I_FXEN", "fx" } },
}
local SEND_KEYS = { { "D_VOL", "vol" }, { "D_PAN", "pan" }, { "B_MUTE", "mute" }, { "I_SENDMODE", "mode" } }
local SOLO_WRITE = { [5] = 1, [6] = 2 }

local function read_ticks(raw)
  local ticks, any = {}, false
  for letter in tostring(raw or ""):gmatch(".") do
    if not snapshot_restore.TICKS:find(letter, 1, true) then return nil, "bad_ticks" end
    ticks[letter], any = true, true
  end
  if not any then return nil, "no_ticks" end
  return ticks
end

-- Every track now: { by_guid = { [guid] = entry }, in_ear = { [guid] = true } }, entries `{ track, guid, name }`.
local function scan(api)
  local found = { by_guid = {}, in_ear = {} }
  local folder_seen = false
  for index = 0, api.CountTracks(0) - 1 do
    local track = api.GetTrack(0, index)
    local guid = api.GetTrackGUID(track)
    local _, name = api.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
    name = name or ""
    found.by_guid[guid] = { track = track, guid = guid }
    local is_folder = name == IN_EAR_FOLDER and not folder_seen
    folder_seen = folder_seen or is_folder
    if (name:sub(1, #IN_EAR_PREFIX) == IN_EAR_PREFIX and #name > #IN_EAR_PREFIX) or name == IN_EAR_CUE or is_folder then
      found.in_ear[guid] = true
    end
  end
  local master = api.GetMasterTrack(0)
  found.by_guid[store.MASTER] = { track = master, guid = store.MASTER }
  return found
end

local function sends_by_dest(api, track)
  local queues = {}
  for index = 0, api.GetTrackNumSends(track, SEND_CATEGORY) - 1 do
    local guid = api.GetTrackGUID(api.GetTrackSendInfo_Value(track, SEND_CATEGORY, index, "P_DESTTRACK"))
    queues[guid] = queues[guid] or {}
    table.insert(queues[guid], index)
  end
  return queues
end

-- What a restore would write: { track_writes = { { track, key, value } }, send_writes = { { track, category, index,
-- key, value } }, tracks, sends, skipped }.
local function plan(api, contents, ticks)
  local now = scan(api)
  local auto = automation.new(api)
  local result = { track_writes = {}, send_writes = {}, tracks = 0, sends = 0, skipped = 0, automated = 0,
    muted_skipped = 0 }
  for _, saved in ipairs(contents.tracks) do
    local entry = now.by_guid[saved.guid]
    if not entry then
      result.skipped = result.skipped + 1 + #saved.sends + #saved.outputs
    else
      -- In-ear values (an in-ear track's own, every send into one, their outputs) follow only the In-ears tick.
      local ear = now.in_ear[saved.guid] or false
      local touched = false
      for letter in snapshot_restore.TICKS:gmatch(".") do
        local keys = TRACK_TICKS[letter]
        if keys and ((ear and ticks.I) or (not ear and ticks[letter])) then
          for _, key in ipairs(keys) do
            local value = saved[key[2]]
            if key[1] == "I_SOLO" then value = SOLO_WRITE[value] or value end
            if key[1] == "B_MUTE" and auto.guards_mute(entry.track) then
              result.muted_skipped = result.muted_skipped + 1
            else
              result.track_writes[#result.track_writes + 1] = { track = entry.track, key = key[1], value = value }
              if auto.track_follows(entry.track, key[1]) then result.automated = result.automated + 1 end
              touched = true
            end
          end
        end
      end
      if ticks.E or ticks.I then
        local queues = sends_by_dest(api, entry.track)
        local function add(category, index, send)
          local is_send = category == SEND_CATEGORY
          for _, key in ipairs(SEND_KEYS) do
            if key[1] == "B_MUTE" and is_send and auto.guards_send_mute(entry.track, category, index) then
              result.muted_skipped = result.muted_skipped + 1
            else
              result.send_writes[#result.send_writes + 1] =
                { track = entry.track, category = category, index = index, key = key[1], value = send[key[2]] }
              if is_send and auto.send_follows(entry.track, category, index, key[1]) then
                result.automated = result.automated + 1
              end
            end
          end
          result.sends = result.sends + 1
        end
        for _, send in ipairs(saved.sends) do
          local queue = queues[send.dest]
          local index = queue and table.remove(queue, 1)
          local wanted
          if ear or now.in_ear[send.dest] then wanted = ticks.I else wanted = ticks.E end
          if wanted then
            if index then
              add(SEND_CATEGORY, index, send)
            else
              result.skipped = result.skipped + 1
            end
          end
        end
        if ear and ticks.I or not ear and ticks.E then
          local outputs = api.GetTrackNumSends(entry.track, OUTPUT_CATEGORY)
          for order, output in ipairs(saved.outputs) do
            if order <= outputs then
              add(OUTPUT_CATEGORY, order - 1, output)
            else
              result.skipped = result.skipped + 1
            end
          end
        end
      end
      if touched then result.tracks = result.tracks + 1 end
    end
  end
  return result
end

function snapshot_restore.run(given)
  local api, fields = given.api, given.fields or {}
  local name, code = store.clean_name(fields.name)
  if not name then return refusal(code) end
  local ticks, bad = read_ticks(fields.ticks)
  if not ticks then return refusal(bad) end
  local list, unreadable = store.list(api)
  if not list then return refusal(unreadable) end
  local entry = store.find(list, name)
  if not entry then return refusal("not_found") end
  local contents, why = store.read(api, entry)
  if not contents then return refusal(why) end

  local todo = plan(api, contents, ticks)
  if #todo.track_writes > 0 or #todo.send_writes > 0 then
    undo.run(api, "Snapshots: restore " .. name, function()
      for _, w in ipairs(todo.track_writes) do
        api.SetMediaTrackInfo_Value(w.track, w.key, w.value)
      end
      for _, w in ipairs(todo.send_writes) do
        api.SetTrackSendInfo_Value(w.track, w.category, w.index, w.key, w.value)
      end
    end)
  end
  return { status = "ok", name = name, tracks = todo.tracks, sends = todo.sends, skipped = todo.skipped,
    automated = todo.automated, muted_skipped = todo.muted_skipped }
end

return snapshot_restore
