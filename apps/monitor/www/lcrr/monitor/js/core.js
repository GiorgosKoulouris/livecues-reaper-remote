// Monitor: pure helpers (no DOM, no network). Works in browsers and in node tests.
// Track replies are parsed here until a second app needs them (shared/CLAUDE.md). Facts: root CONTEXT.md.
(function (root, factory) {
  var api = factory(root.LCRR && root.LCRR.shared && root.LCRR.shared.reaper || (typeof require === "function" ? require("../../../../../../shared/www/lcrr/shared/js/reaper.js") : null));
  if (typeof module === "object" && module.exports) module.exports = api;
  else { var L = root.LCRR = root.LCRR || {}; (L.monitor = L.monitor || {}).core = api; }
})(this, function (reaper) {
  "use strict";

  var listMixes = reaper.listMixes, dbText = reaper.dbText; // the shared rule and format; still exported from here

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

  // Name match for the open mix, run on every poll: the one track named IEM_<name> that is still listed.
  // `duplicate` when the name is on more than one track (listed or not), `gone` when absent or no longer a mix.
  function findMix(tracks, name) {
    var hits = reaper.tracksNamed(tracks, name);
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

  // ---- Fader write gating (the fader itself is shared/js/fader-core.js) ----
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

  return { writeAllowed: writeAllowed, soloPlan: soloPlan, restorePlan: restorePlan, holdLevels: holdLevels,
    tracksKey: tracksKey, parseTrackReply: parseTrackReply, listMixes: listMixes, findMix: findMix, parseSendReply: parseSendReply,
    applyReceives: applyReceives, parseMasterReply: parseMasterReply, buildReadRequests: buildReadRequests, dbText: dbText, buildReceiveRequests: buildReceiveRequests, rowsFor: rowsFor };
});
