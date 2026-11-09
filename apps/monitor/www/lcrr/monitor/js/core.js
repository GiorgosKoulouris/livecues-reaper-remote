// Monitor: pure helpers (no DOM, no network). Works in browsers and in node tests.
// Track replies are parsed here until a second app needs them (shared/CLAUDE.md). Facts: root CONTEXT.md.
(function (root, factory) {
  var api = factory();
  if (typeof module === "object" && module.exports) module.exports = api;
  else { var L = root.LCRR = root.LCRR || {}; (L.monitor = L.monitor || {}).core = api; }
})(this, function () {
  "use strict";

  var MIX_PREFIX = "IEM_"; // exact, case-sensitive

  // NTRACK\t<n> and TRACK\tnumber\tname\tflags\tvol\tpan\tpeak\tpos\twidth\tpanmode\tsendcnt\trecvcnt\thwoutcnt\tcolor.
  // Returns { ntrack, tracks } (master left out; `number` is the t in GET/TRACK/<t>/...), or null when the reply
  // has no NTRACK or does not carry every track (a partial reply must never remove rows).
  function parseTrackReply(text) {
    var ntrack = null, tracks = [];
    String(text).split(/\r?\n/).forEach(function (line) {
      var f = line.split("\t");
      if (f[0] === "NTRACK") {
        var n = parseInt(f[1], 10);
        if (!isNaN(n)) ntrack = n;
      } else if (f[0] === "TRACK") {
        var number = parseInt(f[1], 10), sendcnt = parseInt(f[10], 10), recvcnt = parseInt(f[11], 10), hwoutcnt = parseInt(f[12], 10);
        if (isNaN(number) || number < 1 || isNaN(sendcnt) || isNaN(recvcnt) || isNaN(hwoutcnt)) return;
        tracks.push({ number: number, name: f[2], sendcnt: sendcnt, recvcnt: recvcnt, hwoutcnt: hwoutcnt, color: parseInt(f[13], 10) || 0 });
      }
    });
    if (ntrack === null || tracks.length !== ntrack) return null;
    return { ntrack: ntrack, tracks: tracks };
  }

  // Mix list rule: exact IEM_ prefix, a name after it, at least one receive and at least one hardware output.
  // `name` is shown without the prefix; `duplicate` marks every listed track whose name is shared (not openable).
  function listMixes(tracks) {
    var out = [], count = {};
    tracks.forEach(function (t) {
      if (t.name.indexOf(MIX_PREFIX) !== 0 || t.name.length === MIX_PREFIX.length) return;
      if (t.recvcnt < 1 || t.hwoutcnt < 1) return;
      var name = t.name.slice(MIX_PREFIX.length);
      count[name] = (count[name] || 0) + 1;
      out.push({ name: name, number: t.number, duplicate: false });
    });
    out.forEach(function (m) { m.duplicate = count[m.name] > 1; });
    return out;
  }

  // Name match for the open mix, run on every poll: the one track named IEM_<name> that is still listed.
  // `duplicate` when the name is on more than one track (listed or not), `gone` when absent or no longer a mix.
  function findMix(tracks, name) {
    var full = MIX_PREFIX + name, hits = tracks.filter(function (t) { return t.name === full; });
    if (hits.length > 1) return { status: "duplicate" };
    if (hits.length === 0 || hits[0].recvcnt < 1 || hits[0].hwoutcnt < 1) return { status: "gone" };
    return { status: "ok", number: hits[0].number, recvcnt: hits[0].recvcnt, hwoutcnt: hits[0].hwoutcnt };
  }

  // SEND\tt\ty\tflags\tvol\tpan\tother_track_index. `muted` is flags & 8.
  function parseSendReply(text) {
    var out = [];
    String(text).split(/\r?\n/).forEach(function (line) {
      var f = line.split("\t");
      if (f[0] !== "SEND") return;
      var t = parseInt(f[1], 10), y = parseInt(f[2], 10), flags = parseInt(f[3], 10), vol = parseFloat(f[4]), other = parseInt(f[6], 10);
      if (isNaN(t) || isNaN(y) || isNaN(flags) || isNaN(vol) || isNaN(other)) return;
      out.push({ track: t, y: y, vol: vol, muted: (flags & 8) !== 0, source: other });
    });
    return out;
  }

  // Merge SEND lines into the receive list (index n-1 holds receive y=-n). Only lines for `mixNumber`, only
  // y from -1 to -recvcnt, and never a line whose last field is -1 (REAPER's answer for a missing send).
  // Rows a partial reply does not cover are kept; rows beyond recvcnt are dropped. Returns a new array.
  function applyReceives(receives, text, mixNumber, recvcnt) {
    var out = receives.slice(0, recvcnt);
    parseSendReply(text).forEach(function (s) {
      if (s.track !== mixNumber || s.y > -1 || s.y < -recvcnt || s.source < 0) return;
      out[-s.y - 1] = { source: s.source, vol: s.vol, muted: s.muted };
    });
    return out;
  }

  // Linear level to the dB value shown in a fader, with no unit: "0.0", "-6.0", "+6.0", "-inf".
  function dbText(vol) {
    if (!(vol > 0)) return "-inf";
    var d = Math.round(20 * Math.log(vol) / Math.LN10 * 10) / 10;
    if (d === 0) d = 0; // no "-0.0"
    return (d > 0 ? "+" : "") + d.toFixed(1);
  }

  // The mix's master level: the SEND line for index 0 of `mixNumber`, accepted only when its last field is -1 (a
  // hardware output; an ordinary send has a real track number there) and the mix has a hardware output (a missing
  // send answers like a silent one). Returns { vol } or null.
  function parseMasterReply(text, mixNumber, hwoutcnt) {
    if (!(hwoutcnt >= 1)) return null;
    var found = null;
    parseSendReply(text).forEach(function (s) {
      if (s.track === mixNumber && s.y === 0 && s.source === -1) found = { vol: s.vol };
    });
    return found;
  }

  // GET commands for every receive, joined with ";" and split so "/_/" + command stays within maxChars.
  function buildReceiveRequests(track, recvcnt, maxChars) {
    return pack(track, recvcnt, maxChars, []);
  }
  // The same, with the master level (send index 0) read first, on the same cycle as the receives.
  function buildReadRequests(track, recvcnt, maxChars) {
    return pack(track, recvcnt, maxChars, ["GET/TRACK/" + track + "/SEND/0"]);
  }
  function pack(track, recvcnt, maxChars, cmds) {
    var out = [], cur = "";
    for (var n = 1; n <= recvcnt; n++) cmds.push("GET/TRACK/" + track + "/SEND/-" + n);
    for (var i = 0; i < cmds.length; i++) {
      var c = cmds[i];
      if (cur && 3 + cur.length + 1 + c.length > maxChars) { out.push(cur); cur = ""; }
      cur = cur ? cur + ";" + c : c;
    }
    if (cur) out.push(cur);
    return out;
  }

  // View rows for the mix: one per known receive, in receive order. Source name and colour come from the track list.
  function rowsFor(receives, tracks) {
    var byNumber = {};
    tracks.forEach(function (t) { byNumber[t.number] = t; });
    var rows = [];
    receives.forEach(function (r, i) {
      if (!r) return;
      var t = byNumber[r.source];
      rows.push({ n: i + 1, y: -(i + 1), source: r.source, name: t ? t.name : "Track " + r.source, color: t ? t.color : 0, vol: r.vol, db: dbText(r.vol), muted: r.muted });
    });
    return rows;
  }

  // Identity of the track list as far as rows care (numbers, names, colours). A receive's source is a track
  // number, so replies read under one key must not be shown against another.
  function tracksKey(tracks) {
    return tracks.map(function (t) { return t.number + ":" + t.color + ":" + t.name; }).join("\n");
  }

  // ---- Faders ----
  var CAP = Math.pow(10, 6 / 20); // +6 dB, the highest level any drag can write

  // value = pos^4 * CAP. pos is the thumb position from 0 (silence) to 1 (+6 dB); 0 dB sits at about 0.84.
  function faderValue(pos) {
    if (!(pos > 0)) return 0;
    return pos >= 1 ? CAP : Math.pow(pos, 4) * CAP;
  }
  // Inverse. A level above the cap parks at 1 (the thumb's end); the dB readout still shows the true level.
  function faderPos(value) {
    if (!(value > 0)) return 0;
    return value >= CAP ? 1 : Math.pow(value / CAP, 0.25);
  }

  // SET/TRACK/<t>/SEND/<y>/VOL/<v>; with `end` the "e" suffix, which only ends the move (and adds the undo entry).
  function setVolCommand(track, y, value, end) {
    var v = value.toFixed(6).replace(/\.?0+$/, "");
    return "SET/TRACK/" + track + "/SEND/" + y + "/VOL/" + (v === "" ? "0" : v) + (end ? "e" : "");
  }

  // May a write for `target` ({ track, y, source }) go out? `st` is the latest state: { number: the mix's track
  // index from the latest poll, receives, fresh: the receives were read under the latest track list, offline }.
  // A source (y < 0) must also still be the receive at that index. The master fader (y 0, source -1, the first
  // hardware output) needs its level to have been read (`st.master`, a number); nothing else with y >= 0 passes.
  function writeAllowed(target, st) {
    if (!st || !target || st.offline || !st.fresh || st.number !== target.track) return false;
    if (target.y < 0) {
      var r = st.receives[-target.y - 1];
      return !!r && r.source === target.source && r.source >= 0;
    }
    return target.y === 0 && target.source === -1 && typeof st.master === "number" && isFinite(st.master);
  }

  // After a read: rows whose fader is held (dragging, or writes not landed, or a read begun too early) keep the
  // level on screen; rows whose mute is held (`heldMute`, optional) keep the mute on screen; everything else in
  // `next` is taken. The two holds are independent. `held(index)` is for the 0-based receive index.
  function holdLevels(prev, next, held, heldMute) {
    return next.map(function (r, i) {
      var p = prev[i];
      if (!r || !p || p.source !== r.source) return r;
      var keepVol = !!held(i), keepMute = !!heldMute && !!heldMute(i);
      if (!keepVol && !keepMute) return r;
      return { source: r.source, vol: keepVol ? p.vol : r.vol, muted: keepMute ? p.muted : r.muted };
    });
  }

  // SET/TRACK/<t>/SEND/<y>/MUTE/<0|1>: the state to set, never a toggle, never a level.
  function setMuteCommand(track, y, muted) {
    return "SET/TRACK/" + track + "/SEND/" + y + "/MUTE/" + (muted ? 1 : 0);
  }

  // One row's mute writes. press() works out the new state from the on-screen state and sends it, unless the
  // stale check fails or the previous mute write is still outstanding (a double tap). Whether the write worked
  // or not, a read must have begun after it settled before it can change the screen (readToken/canApply).
  // opts: check(target) -> bool, send(cmd) -> Promise.
  function createMuteWriter(opts) {
    var inflight = false, seq = 0;
    return {
      press: function (target, mutedOnScreen) {
        if (inflight || !opts.check(target)) return false;
        inflight = true;
        var done = function () { inflight = false; seq++; };
        var p;
        try { p = opts.send(setMuteCommand(target.track, target.y, !mutedOnScreen)); } catch (err) { p = Promise.reject(err); }
        p.then(done, done);
        return true;
      },
      busy: function () { return inflight; },
      readToken: function () { return inflight ? -1 : seq; },
      canApply: function (token) { return token === seq && !inflight; }
    };
  }

  // Solo in my mix: the web API has no per-send solo, so it mutes the other receives (and unmutes the soloed
  // one). `changes` is what solo changed: [{ index, source, from, to }] (0-based receive index, muted states).
  // soloPlan works from the original states (`prev` changes still in effect are undone first), so moving solo
  // to another row never loses what the first solo muted. moves: [{ index, to }] are the writes still needed.
  function soloPlan(receives, index, prev) {
    var changes = [], moves = [];
    receives.forEach(function (r, i) {
      if (!r) return;
      var cur = !!r.muted, orig = cur, want = i !== index;
      (prev || []).forEach(function (c) { if (c.index === i && c.source === r.source && c.to === cur) orig = c.from; });
      if (orig !== want) changes.push({ index: i, source: r.source, from: orig, to: want });
      if (cur !== want) moves.push({ index: i, to: want });
    });
    return { changes: changes, moves: moves };
  }

  // Ending solo puts back only what solo changed: a receive still where the source and the muted state solo left
  // it. One that another phone or the engineer has changed since (or that is now another source) is left alone.
  function restorePlan(receives, changes) {
    var moves = [];
    (changes || []).forEach(function (c) {
      var r = receives[c.index];
      if (r && r.source === c.source && !!r.muted === c.to) moves.push({ index: c.index, to: c.from });
    });
    return { moves: moves };
  }

  // One fader's drag and write state, shared by the source rows and (issue 06) the master fader.
  // opts: now(), setTimer(fn, ms), clearTimer(h), send(cmd) -> Promise, check(target) -> bool (the stale check,
  // run at the moment each request would go out), gateMs (50), slopPx (3), travelPx (thumb travel in px).
  // Movement is relative: move(dx) takes the distance from the press, positive toward louder.
  function createFaderDrag(opts) {
    var now = opts.now, gateMs = opts.gateMs === undefined ? 50 : opts.gateMs, slopPx = opts.slopPx === undefined ? 3 : opts.slopPx;
    var travel = opts.travelPx || 1;
    var active = false, target = null, startVol = 0, offset = 0, anchor = null, pos = 0, value = 0, wrote = false;
    var pending = null;    // { target, value }: latest level not yet sent
    var endReq = null;     // { target, value }: the move was released and still needs its e
    var inflight = false, lastSent = -Infinity, timer = null, seq = 0;

    function fire(cmd) {
      inflight = true; lastSent = now();
      var done = function () { inflight = false; seq++; pump(); };
      var p;
      try { p = opts.send(cmd); } catch (err) { p = Promise.reject(err); }
      p.then(done, done);
    }
    function pump() {
      if (inflight) return;
      if (endReq) {
        var e = endReq, p = pending; endReq = null; pending = null;
        if (!opts.check(e.target)) return;
        var set = setVolCommand(e.target.track, e.target.y, e.value, false);
        fire((p ? set + ";" : "") + setVolCommand(e.target.track, e.target.y, e.value, true));
        return;
      }
      if (!pending) return;
      var wait = lastSent + gateMs - now();
      if (wait > 0) {
        if (timer === null) timer = opts.setTimer(function () { timer = null; pump(); }, wait);
        return;
      }
      var w = pending; pending = null;
      if (!opts.check(w.target)) return;
      wrote = true;
      fire(setVolCommand(w.target.track, w.target.y, w.value, false));
    }

    return {
      // Starts a drag at the thumb. Refused while the previous drag's final request has not gone out.
      begin: function (t, vol, travelPx) {
        if (active || endReq) return false;
        if (travelPx) travel = travelPx;
        active = true; target = t; startVol = vol; value = vol; pos = faderPos(vol); offset = pos; anchor = null; wrote = false; seq++;
        return true;
      },
      // Returns { pos, value } when the level changed (and queues the write), null when nothing changes.
      move: function (dx) {
        if (!active) return null;
        if (anchor === null) { // inside the slop nothing moves; the drag then continues from the slop's edge
          if (Math.abs(dx) < slopPx) return null;
          anchor = dx > 0 ? slopPx : -slopPx;
        }
        var raw = offset + (dx - anchor) / travel;
        // Past an end the offset follows the finger, so the way back starts at once (no dead zone).
        if (raw > 1) { offset = 1 - (dx - anchor) / travel; raw = 1; }
        else if (raw < 0) { offset = -(dx - anchor) / travel; raw = 0; }
        if (raw === pos) return null;
        pos = raw; value = faderValue(pos);
        pending = { target: target, value: value };
        pump();
        return { pos: pos, value: value };
      },
      // Release: the latest value (if not yet sent) and the e in one request, only if a level was written.
      end: function () {
        if (!active) return;
        active = false; seq++;
        if (wrote || pending) endReq = { target: target, value: value };
        pump();
      },
      // The drag ends with no final write: mix closed, offline, row gone.
      cancel: function () {
        active = false; pending = null; endReq = null; wrote = false; seq++;
        if (timer !== null) { opts.clearTimer(timer); timer = null; }
      },
      active: function () { return active; },
      pos: function () { return pos; },
      busy: function () { return active || inflight || !!pending || !!endReq; },
      // A read may be applied only if it began while this fader was idle and nothing has happened since.
      readToken: function () { return (active || inflight || pending || endReq) ? -1 : seq; },
      canApply: function (token) { return token === seq && !active && !inflight && !pending && !endReq; }
    };
  }

  return { CAP: CAP, faderValue: faderValue, faderPos: faderPos, setVolCommand: setVolCommand, writeAllowed: writeAllowed, setMuteCommand: setMuteCommand, soloPlan: soloPlan, restorePlan: restorePlan, createMuteWriter: createMuteWriter,
    holdLevels: holdLevels, createFaderDrag: createFaderDrag, tracksKey: tracksKey, parseTrackReply: parseTrackReply, listMixes: listMixes, findMix: findMix, parseSendReply: parseSendReply,
    applyReceives: applyReceives, parseMasterReply: parseMasterReply, buildReadRequests: buildReadRequests, dbText: dbText, buildReceiveRequests: buildReceiveRequests, rowsFor: rowsFor };
});
