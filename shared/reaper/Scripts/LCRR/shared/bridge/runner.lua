-- The ExtState loop every bridge shares, minus the defer: one `tick` is one
-- look at the request, and each bridge script calls it from reaper.defer.
--
--   page  -> SET/EXTSTATE/<section>/req/<id>|<length>|<body>
--   tick  -> SetExtState(<section>, res, <id>|<json>)
--   tick  -> SetExtState(<section>, heartbeat, <counter>), about 4 times a second
--
-- **The heartbeat is the only way the page knows the bridge is running.** A
-- key that was never set reads as an empty string, which cannot be told from
-- an empty value (spike, question 6), so "running" means "the heartbeat
-- changed since I last looked".
--
-- A request is answered once: the bridge remembers the last raw value it
-- handled and ignores it until the page writes a different one.

local runner = {}

runner.BEAT_EVERY = 0.25 -- seconds

--- @param opts table
--   api      the `reaper` table
--   section  the bridge's ExtState section (LCRR_ARRANGE, LCRR_IEM)
--   handle   function(raw) -> id, reply (the bridge's service)
--   clock    function() -> seconds (default reaper.time_precise)
function runner.new(opts)
  local api, handle = opts.api, opts.handle
  local clock = opts.clock or api.time_precise
  local section = assert(opts.section, "runner: section is required")

  local self = {}
  local beat, beat_at, last_raw = 0, nil, nil

  local function write_beat(now)
    beat, beat_at = beat + 1, now
    api.SetExtState(section, "heartbeat", ("%d"):format(beat), false)
  end

  --- Clear anything a previous run left behind, and start beating.
  function self.start()
    api.DeleteExtState(section, "req", false)
    api.DeleteExtState(section, "res", false)
    write_beat(clock())
  end

  --- Remove every key, so the page sees the bridge stop.
  function self.stop()
    api.DeleteExtState(section, "heartbeat", false)
    api.DeleteExtState(section, "req", false)
    api.DeleteExtState(section, "res", false)
  end

  --- One look: answer a new request, and beat when it is time.
  function self.tick()
    local raw = api.GetExtState(section, "req")
    if raw ~= "" and raw ~= last_raw then
      last_raw = raw
      local id, reply = handle(raw)
      if id then
        api.SetExtState(section, "res", id .. "|" .. reply, false)
      end
      -- A long action ends here, so beat straight away rather than leaving the
      -- page to wait for the next quarter second.
      write_beat(clock())
      return
    end

    local now = clock()
    if now - beat_at >= runner.BEAT_EVERY then
      write_beat(now)
    end
  end

  return self
end

return runner
