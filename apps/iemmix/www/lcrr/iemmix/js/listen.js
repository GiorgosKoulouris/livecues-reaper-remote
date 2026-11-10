// IEM Mix: Listen, pure logic (no DOM, no network). One mix at a time is heard through the cue track (IEM-Cue), by
// the level of that mix's send to it: 1 on, 0 off, written with no "e" suffix (no undo entry). The state lives in
// REAPER and is read from the sends. Facts: spec "Listen", suite CONTEXT.md.
(function (root, factory) {
  var api = factory(root.LCRR && root.LCRR.iemmix && root.LCRR.iemmix.core || (typeof require === "function" ? require("./core.js") : null));
  if (typeof module === "object" && module.exports) module.exports = api;
  else { var L = root.LCRR = root.LCRR || {}; (L.iemmix = L.iemmix || {}).listen = api; }
})(this, function (core) {
  "use strict";

  var CUE_NAME = "IEM-Cue";
  var ON_MIN = 0.001; // a send at or above this level is heard (a REAPER undo can leave any value)

  function trackOf(tracks, number) {
    for (var i = 0; i < tracks.length; i++) if (tracks[i].number === number) return tracks[i];
    return null;
  }

  // The cue track: the first track named exactly IEM-Cue, in project order (as IEM Setup). Its number, or null.
  function findCue(tracks) {
    for (var i = 0; i < tracks.length; i++) if (tracks[i].name === CUE_NAME) return tracks[i].number;
    return null;
  }

  // The `y` values a mix's ordinary sends can have, as { from, to }. Inferred from a measurement on a track with one
  // hardware output: hardware outputs are numbered before ordinary sends, so with `hwoutcnt` outputs the sends are
  // y = hwoutcnt .. hwoutcnt + sendcnt - 1 (the same 1 .. sendcnt with one output). A listed mix has at least one
  // output. Unverified with several outputs (CONTEXT.md, "Still unverified"): this is the one place to correct.
  function sendRange(track) {
    var hw = Math.max(1, track.hwoutcnt || 0), n = track.sendcnt || 0;
    return { from: hw, to: hw + n - 1 };
  }

  // Identity of what the sends depend on: which track is the cue, each mix's number, name, output count and send
  // count. Adding an output shifts the ordinary sends, so a cue send found under one key is never kept under another.
  function layoutKey(tracks) {
    return findCue(tracks) + "|" + core.listMixes(tracks).map(function (m) {
      var tr = trackOf(tracks, m.number);
      return m.number + ":" + m.name + ":" + (tr.hwoutcnt || 0) + ":" + (tr.sendcnt || 0);
    }).join("\n");
  }

  // GET commands for the sends: a mix whose cue send is known is read at its y only, the others at every y of
  // `sendRange`. Joined with ";" and split so "/_/" + command stays within maxChars. [] with no cue track.
  function buildRequests(tracks, found, maxChars) {
    if (findCue(tracks) === null) return [];
    var cmds = [];
    core.listMixes(tracks).forEach(function (m) {
      var known = found[m.number];
      if (known) { cmds.push("GET/TRACK/" + m.number + "/SEND/" + known.y); return; }
      var range = sendRange(trackOf(tracks, m.number));
      for (var y = range.from; y <= range.to; y++) cmds.push("GET/TRACK/" + m.number + "/SEND/" + y);
    });
    var out = [], cur = "";
    cmds.forEach(function (c) {
      if (cur && 3 + cur.length + 1 + c.length > maxChars) { out.push(cur); cur = ""; }
      cur = cur ? cur + ";" + c : c;
    });
    if (cur) out.push(cur);
    return out;
  }

  // What the page keeps: for each mix, { y, vol } of its first send to the cue track. A reply merges send by send;
  // a send that reads as another destination forgets what was known at that y; a missing line changes nothing.
  // `mark()` is taken when a read goes out and `apply(.., mark)` drops a reply that began before a later write.
  function createListenModel() {
    var key = null, found = {}, writes = 0, ready = {};
    return {
      // Returns true when the layout changed (what was found is dropped).
      update: function (tracks) {
        var k = layoutKey(tracks);
        if (k === key) return false;
        key = k; found = {};
        return true;
      },
      key: function () { return key; },
      found: function () { return found; },
      mark: function () { return writes; },
      // A write is going out: replies that began earlier are stale.
      wrote: function () { writes++; },
      apply: function (tracks, forKey, text, mark) {
        if (forKey !== key || mark !== writes) return false;
        var cue = findCue(tracks);
        core.parseSendReply(text).forEach(function (s) {
          if (s.y < 1 || cue === null) return;
          var known = found[s.track];
          if (s.source === cue) {
            if (!known || s.y <= known.y) found[s.track] = { y: s.y, vol: s.vol };
          } else if (known && known.y === s.y && s.source >= 0) delete found[s.track];
        });
        return true;
      },
      // A level written ahead of its read.
      setLocal: function (mixNumber, vol) { if (found[mixNumber]) found[mixNumber].vol = vol; },
      // Every read of a sweep under this key has settled: a mix with no cue send found is known to have none.
      endSweep: function (forKey, mark) { if (forKey === key && mark === writes) ready[forKey] = true; },
      settled: function () { return !!ready[key]; }
    };
  }

  // What the screen shows. `settled`: the sends have been read in full under this layout. Per mix: status "ok" (has a
  // cue send), "nocue" (read, none), "pending" (not read yet) or "nocuetrack"; `on` (heard); `enabled` says the key can
  // be pressed (a mix that is not editable, a duplicated name, never can; the lock gate is separate).
  function view(tracks, found, settled) {
    var cue = findCue(tracks), mixes = core.listMixes(tracks);
    var rows = mixes.map(function (m) {
      var f = found[m.number];
      var status = cue === null ? "nocuetrack" : f ? "ok" : settled ? "nocue" : "pending";
      return { number: m.number, name: m.name, status: status, vol: f ? f.vol : null, on: !!f && f.vol >= ON_MIN, enabled: status === "ok" && m.editable };
    });
    var onCount = rows.filter(function (r) { return r.on; }).length;
    var note = "";
    if (cue === null) { if (mixes.length) note = "No cue track named IEM-Cue. Create it in IEM Setup."; }
    else if (rows.some(function (r) { return r.status === "nocue"; })) note = "A mix with no send to IEM-Cue cannot be listened to. Add the sends in IEM Setup.";
    return { cue: cue, rows: rows, onCount: onCount, several: onCount > 1, note: note };
  }

  // The writes a tap on `target` (a mix number) makes: [ { track, y, vol } ]. The only mix on is turned off. Otherwise
  // every other mix that is on goes to 0 and the target to 1, so a tap on a mix that is on among several leaves just
  // that one. A target that cannot be listened to: [].
  function plan(rows, found, target) {
    var me = rows.filter(function (r) { return r.number === target; })[0];
    if (!me || !me.enabled || !found[target]) return [];
    var writes = [], others = rows.filter(function (r) { return r.number !== target && r.on && found[r.number]; });
    if (me.on && !others.length) return [{ track: target, y: found[target].y, vol: 0 }];
    others.forEach(function (r) { writes.push({ track: r.number, y: found[r.number].y, vol: 0 }); });
    if (found[target].vol !== 1) writes.push({ track: target, y: found[target].y, vol: 1 });
    return writes;
  }

  // SET/TRACK/<t>/SEND/<y>/VOL/<v> with no "e": no undo entry.
  function levelCommand(w) { return "SET/TRACK/" + w.track + "/SEND/" + w.y + "/VOL/" + (w.vol ? "1" : "0"); }

  // The lock gate: a tap acts only while the page can edit (`canEdit`, core.canEdit's verdict). Returns
  // { writes, command } (the writes' commands joined by ";" into one request) or null.
  function tapPlan(tracks, found, settled, target, canEdit) {
    if (!canEdit) return null;
    var v = view(tracks, found, settled);
    if (v.cue === null) return null;
    var writes = plan(v.rows, found, target);
    return writes.length ? { writes: writes, command: writes.map(levelCommand).join(";") } : null;
  }

  return { CUE_NAME: CUE_NAME, findCue: findCue, layoutKey: layoutKey, buildRequests: buildRequests, createListenModel: createListenModel,
    view: view, plan: plan, levelCommand: levelCommand, tapPlan: tapPlan };
});
