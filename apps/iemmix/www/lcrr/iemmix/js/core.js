// IEM Mix: pure logic (no DOM, no network). Works in browsers and in node tests. Facts: root CONTEXT.md.
// The mix listing rule and dbText are shared (LCRR.shared.reaper). The track and send reply parsers started as
// Monitor's and carry more: the track's mute and the send's pan.
(function (root, factory) {
  var api = factory(root.LCRR && root.LCRR.shared && root.LCRR.shared.reaper || (typeof require === "function" ? require("../../../../../../shared/www/lcrr/shared/js/reaper.js") : null));
  if (typeof module === "object" && module.exports) module.exports = api;
  else { var L = root.LCRR = root.LCRR || {}; (L.iemmix = L.iemmix || {}).core = api; }
})(this, function (reaper) {
  "use strict";

  var dbText = reaper.dbText;
  var MUTE_FLAG = 8;       // TRACK flags and SEND flags: &8 is muted

  // NTRACK\t<n> and TRACK\tnumber\tname\tflags\tvol\tpan\tpeak\tpos\twidth\tpanmode\tsendcnt\trecvcnt\thwoutcnt\tcolor.
  // Returns { ntrack, tracks } (master left out; `number` is the t in GET/TRACK/<t>/...; `muted` is flags & 8), or
  // null when the reply has no NTRACK or does not carry every track (a partial reply must never remove rows).
  function parseTrackReply(text) {
    var ntrack = null, tracks = [];
    String(text).split(/\r?\n/).forEach(function (line) {
      var f = line.split("\t");
      if (f[0] === "NTRACK") {
        var n = parseInt(f[1], 10);
        if (!isNaN(n)) ntrack = n;
      } else if (f[0] === "TRACK") {
        var number = parseInt(f[1], 10), flags = parseInt(f[3], 10), sendcnt = parseInt(f[10], 10), recvcnt = parseInt(f[11], 10), hwoutcnt = parseInt(f[12], 10);
        if (isNaN(number) || number < 1 || isNaN(sendcnt) || isNaN(recvcnt) || isNaN(hwoutcnt)) return;
        tracks.push({ number: number, name: f[2], muted: ((flags || 0) & MUTE_FLAG) !== 0, sendcnt: sendcnt, recvcnt: recvcnt, hwoutcnt: hwoutcnt, color: parseInt(f[13], 10) || 0 });
      }
    });
    if (ntrack === null || tracks.length !== ntrack) return null;
    return { ntrack: ntrack, tracks: tracks };
  }

  // The suite's listing rule (reaper.listMixes), with what this page needs on top: the receive count, and `editable`.
  // A mix is identified by its name, so a name on more than one track, listed or not, marks it `duplicate`: every
  // listed one shows, none is `editable` (the same refusal as Monitor's findMix).
  function listMixes(tracks) {
    var byNumber = {};
    tracks.forEach(function (t) { byNumber[t.number] = t; });
    return reaper.listMixes(tracks).map(function (m) {
      var duplicate = reaper.tracksNamed(tracks, m.name).length > 1;
      return { name: m.name, number: m.number, recvcnt: byNumber[m.number].recvcnt, duplicate: duplicate, editable: !duplicate };
    });
  }

  // SEND\tt\ty\tflags\tvol\tpan\tother_track_index. `muted` is flags & 8; `pan` is -1 to 1 (REAPER does not clamp, so it can read outside).
  function parseSendReply(text) {
    var out = [];
    String(text).split(/\r?\n/).forEach(function (line) {
      var f = line.split("\t");
      if (f[0] !== "SEND") return;
      var t = parseInt(f[1], 10), y = parseInt(f[2], 10), flags = parseInt(f[3], 10), vol = parseFloat(f[4]), pan = parseFloat(f[5]), other = parseInt(f[6], 10);
      if (isNaN(t) || isNaN(y) || isNaN(flags) || isNaN(vol) || isNaN(pan) || isNaN(other)) return;
      out.push({ track: t, y: y, vol: vol, pan: pan, muted: (flags & MUTE_FLAG) !== 0, source: other });
    });
    return out;
  }

  // Send pan: position 0..1 on the control is -1 (left) to 1 (right), linear, centre at 0.5.
  function panValue(pos) {
    if (!(pos > 0)) return -1;
    return pos >= 1 ? 1 : pos * 2 - 1;
  }
  function panPos(value) {
    if (typeof value !== "number" || isNaN(value)) return 0.5;
    return value <= -1 ? 0 : value >= 1 ? 1 : (value + 1) / 2;
  }

  // SET/TRACK/<t>/SEND/<y>/PAN/<v>; with `end` the "e" suffix, which only ends the move (and adds the undo entry):
  // "e" alone does not set the pan, so a release sends the value first. REAPER stores any pan, so clamp to -1..1 here.
  function setPanCommand(track, y, value, end) {
    var c = typeof value !== "number" || isNaN(value) ? 0 : Math.max(-1, Math.min(1, value));
    var v = c.toFixed(6).replace(/\.?0+$/, "");
    if (v === "" || v === "-0" || v === "-") v = "0";
    return "SET/TRACK/" + track + "/SEND/" + y + "/PAN/" + v + (end ? "e" : "");
  }

  // The pan as text: "C", "L25", "R100" (percent, clamped to the control's range); a dash before it is read.
  function panText(pan) {
    if (typeof pan !== "number" || isNaN(pan)) return "–";
    var n = Math.round(Math.min(1, Math.abs(pan)) * 100);
    return n === 0 ? "C" : (pan < 0 ? "L" : "R") + n;
  }

  // Commands joined with ";" and split so "/_/" + request stays within maxChars.
  function joinCommands(cmds, maxChars) {
    var out = [], cur = "";
    cmds.forEach(function (c) {
      if (cur && 3 + cur.length + 1 + c.length > maxChars) { out.push(cur); cur = ""; }
      cur = cur ? cur + ";" + c : c;
    });
    if (cur) out.push(cur);
    return out;
  }

  // GET commands for every receive of every mix, joined with ";" and split so "/_/" + command stays within maxChars.
  function buildReadRequests(mixes, maxChars) {
    var cmds = [];
    mixes.forEach(function (m) {
      for (var n = 1; n <= m.recvcnt; n++) cmds.push("GET/TRACK/" + m.number + "/SEND/-" + n);
    });
    return joinCommands(cmds, maxChars);
  }

  // Identity of the track list as far as receives care. A receive's source is a track number, so a read taken under
  // one key must never be shown against another. Mute and colour change all the time and are not part of it.
  function layoutKey(tracks) {
    return tracks.map(function (t) { return t.number + ":" + t.recvcnt + ":" + t.hwoutcnt + ":" + t.name; }).join("\n");
  }

  // The grid for the screen. `receives` is { <mix track number>: [ { source, vol, muted } | undefined, ... ] } (index
  // n-1 holds receive y = -n). Rows are the sources with at least one send to a listed mix, in project order; a cell
  // is null (no send) or { vol, db, muted, sends, tag, readOnly }. Several sends of one pair show the first one (the
  // lowest receive index) with `tag` "2x"; `readOnly` marks the cells that stay so when editing arrives (a repeated
  // pair, a duplicated mix). `filter` is the name box (case-insensitive substring on the source name); `totalRows`
  // counts the rows before it.
  function buildGrid(tracks, receives, filter) {
    var needle = String(filter || "").trim().toLowerCase();
    var mixes = listMixes(tracks);
    var byNumber = {};
    tracks.forEach(function (t) { byNumber[t.number] = t; });
    var found = {}; // source number -> { col: cell }
    mixes.forEach(function (m, col) {
      (receives[m.number] || []).slice(0, m.recvcnt).forEach(function (r) {
        if (!r || !(r.source >= 1)) return;
        var cells = found[r.source] || (found[r.source] = {});
        var cell = cells[col];
        if (cell) { cell.sends++; cell.tag = cell.sends + "x"; cell.readOnly = true; return; }
        cells[col] = { vol: r.vol, db: dbText(r.vol), muted: !!r.muted, sends: 1, tag: null, readOnly: m.duplicate };
      });
    });
    var rows = Object.keys(found).map(Number).sort(function (a, b) { return a - b; }).map(function (s) {
      var t = byNumber[s];
      var cells = mixes.map(function (m, col) { return found[s][col] || null; });
      return { source: s, name: t ? t.name : "Track " + s, color: t ? t.color : 0, trackMuted: !!(t && t.muted), cells: cells };
    });
    var shown = rows.filter(function (r) { return !needle || r.name.toLowerCase().indexOf(needle) !== -1; });
    return { mixes: mixes, rows: shown, totalRows: rows.length };
  }

  // ---- editing: the lock, the panel, the stale check ----------------------------------------------------------------
  // The page opens locked and one Unlock tap enables editing. `canEdit` is the one gate every write goes through
  // (IEM Setup's shape): a live connection and an Unlock. The page passes its result into writeState(), so the
  // stale check below cannot be asked without it.
  function canEdit(phase, unlocked) { return phase === "connected" && !!unlocked; }

  // The web API names no project, so the page keeps its own ID in project ExtState and reads it on every poll: the
  // same reply as the track list. Only this block knows the commands and the reply format, which have not been measured
  // on real REAPER (CONTEXT.md, "Still unverified").
  var MARKER_SECTION = "LCRR_IEMMIX", MARKER_KEY = "project_id", MARKER_REPLY = "PROJEXTSTATE";
  function markerReadCommand() { return "GET/PROJEXTSTATE/" + MARKER_SECTION + "/" + MARKER_KEY; }
  function markerWriteCommand(id) { return "SET/PROJEXTSTATE/" + MARKER_SECTION + "/" + MARKER_KEY + "/" + encodeURIComponent(id); }
  // The marker in a reply: its value, "" when it was never set, null when the reply has no marker line.
  function parseMarker(text) {
    var found = null;
    String(text).split(/\r?\n/).forEach(function (line) {
      var f = line.split("\t");
      if (f[0] === MARKER_REPLY && f[1] === MARKER_SECTION && f[2] === MARKER_KEY) found = f[3] || "";
    });
    return found;
  }
  function newProjectId(random) {
    var out = "";
    while (out.length < 16) out += Math.floor(random() * 36).toString(36);
    return out;
  }

  // The Unlock tap: read the marker; if there is none yet, write a new ID and require the read-back to match. A second
  // tablet finds the ID there and writes nothing. Resolves to { ok: true, id, fresh } (`fresh`: this tap wrote it) or
  // { ok: false, reason: "unreadable" | "mismatch" }; the page stays locked on the second kind.
  function claimProject(send, random) {
    var unreadable = { ok: false, reason: "unreadable" };
    return send(markerReadCommand()).then(function (text) {
      var seen = parseMarker(text);
      if (seen === null) return unreadable;
      if (seen !== "") return { ok: true, id: seen, fresh: false };
      var id = newProjectId(random);
      return send(markerWriteCommand(id) + ";" + markerReadCommand()).then(function (back) {
        var v = parseMarker(back);
        if (v === null) return unreadable;
        return v === id ? { ok: true, id: id, fresh: true } : { ok: false, reason: "mismatch" };
      });
    }).catch(function () { return unreadable; });
  }

  // One poll's verdict while unlocked: only the same ID holds the lock. A changed, empty or absent one relocks. The one
  // poll that was already out when this tap wrote the ID can still answer empty, so a fresh claim forgives one empty reply.
  function markerHolds(claim, text) {
    if (!claim) return false;
    var v = parseMarker(text), fresh = claim.fresh;
    claim.fresh = false;
    return v === claim.id || (!!fresh && v === "");
  }

  // May a write for `target` ({ track, y, source }) go out? `st` is model.writeState(canEdit). The row must still
  // address the same send: the track is a listed, editable mix; a source row (y < 0) is still that source's only
  // receive at that index; the master (y 0, source -1) has been read. Used as the fader's `check`, so it runs at the
  // moment each request would go out: a change during a drag stops the drag with no final write.
  function writeAllowed(target, st) {
    if (!st || !st.canEdit || !target) return false;
    var mix = null;
    st.mixes.forEach(function (m) { if (m.number === target.track) mix = m; });
    if (!mix || !mix.editable) return false;
    if (target.y < 0) {
      if (-target.y > mix.recvcnt) return false;
      var list = st.receives[mix.number] || [], r = list[-target.y - 1];
      if (!r || r.source !== target.source || !(r.source >= 1)) return false;
      for (var i = 0; i < mix.recvcnt; i++) if (i !== -target.y - 1 && list[i] && list[i].source === r.source) return false; // a repeated pair
      return true;
    }
    var ms = st.masters[mix.number];
    return target.y === 0 && target.source === -1 && !!ms && typeof ms.vol === "number" && isFinite(ms.vol);
  }

  // What the panel shows: a source (its send in every mix) or a mix (its sources and master level). The name guards
  // against track numbers shifting under the selection.
  function selectSource(tracks, number) {
    var t = tracks.filter(function (x) { return x.number === number; })[0];
    return t ? { kind: "source", number: number, name: t.name, focus: null } : null;
  }
  function mixByNumber(tracks, number) { return listMixes(tracks).filter(function (x) { return x.number === number; })[0]; }
  function selectMix(tracks, number) {
    var m = mixByNumber(tracks, number);
    return m ? { kind: "mix", number: number, name: tracks.filter(function (x) { return x.number === number; })[0].name, focus: null } : null;
  }
  // The short name (prefix stripped, as the bridge lists it) of the selected mix, or null when the selection is not a
  // listed mix. `sel.name` stays the full track name: it guards against track numbers shifting.
  function selectedMixName(tracks, sel) {
    if (!sel || sel.kind !== "mix") return null;
    var m = mixByNumber(tracks, sel.number);
    return m ? m.name : null;
  }
  // A click on a cell (or the wheel's first step on it) brings up its fader, highlighted. The open panel stays if it
  // holds the cell; otherwise a panel of the same kind opens for the cell's source or mix, and with none open the
  // cell's mix. The cell already highlighted, or a track that is gone: `sel` comes back as it was.
  function selectCell(tracks, sel, source, mixNumber) {
    var focus = { mix: mixNumber, source: source };
    if (sel && sel.focus && sel.focus.mix === mixNumber && sel.focus.source === source) return sel;
    var held = sel && ((sel.kind === "source" && sel.number === source) || (sel.kind === "mix" && sel.number === mixNumber));
    var next = held ? { kind: sel.kind, number: sel.number, name: sel.name } : (sel && sel.kind === "source" ? selectSource(tracks, source) : selectMix(tracks, mixNumber));
    if (!next) return sel;
    next.focus = focus;
    return next;
  }

  // The Source column's width in px, kept usable: at least 120, at most 480 and never so wide that no mix column fits in
  // `box` (the grid's width, 0 while it is hidden). Null when `px` is not a number (nothing saved).
  var SOURCE_MIN_PX = 120, SOURCE_MAX_PX = 480, SOURCE_ROOM_PX = 96;
  function sourceWidth(px, box) {
    if (typeof px !== "number" || !isFinite(px)) return null;
    var max = box > 0 ? Math.max(SOURCE_MIN_PX, Math.min(SOURCE_MAX_PX, box - SOURCE_ROOM_PX)) : SOURCE_MAX_PX;
    return Math.round(Math.min(max, Math.max(SOURCE_MIN_PX, px)));
  }

  // What the grid's DOM is built from: everything but the levels and mutes, which are painted into the cells in place.
  // A wheel gesture stays on the element it began on, so rebuilding the table under one would end the gesture.
  function gridShape(grid) {
    return JSON.stringify([grid.totalRows, grid.mixes.map(function (m) { return [m.number, m.name, !!m.duplicate]; }), grid.rows.map(function (r) {
      return [r.source, r.name, r.color, r.trackMuted, r.cells.map(function (c) { return c ? [c.tag, !!c.readOnly] : 0; })];
    })]);
  }

  // One send as a panel row. `key` stays the same while the row's source and mix do, so the DOM row persists when
  // a receive index shifts. `readOnly`: a repeated pair or a duplicated mix (no fader).
  function panelRow(mix, source, name, color, r, y, sends, focus) {
    return { key: mix.number + ":" + source, track: mix.number, y: y, source: source, name: name, color: color, vol: r.vol, db: dbText(r.vol), pan: r.pan,
      muted: !!r.muted, sends: sends, tag: sends > 1 ? sends + "x" : null, readOnly: mix.duplicate || sends > 1,
      focused: !!focus && focus.mix === mix.number && focus.source === source };
  }
  // `masters` is { <mix number>: { vol } }. Returns null when the selection no longer matches the track list.
  function buildPanel(tracks, receives, masters, sel) {
    if (!sel) return null;
    var byNumber = {};
    tracks.forEach(function (t) { byNumber[t.number] = t; });
    var self = byNumber[sel.number];
    if (!self || self.name !== sel.name) return null;
    var mixes = listMixes(tracks), focus = sel.focus || null;
    // first[mixNumber][source] = { r, y, sends }
    function firsts(m) {
      var out = {};
      (receives[m.number] || []).slice(0, m.recvcnt).forEach(function (r, i) {
        if (!r || !(r.source >= 1)) return;
        if (out[r.source]) out[r.source].sends++; else out[r.source] = { r: r, y: -(i + 1), sends: 1 };
      });
      return out;
    }
    if (sel.kind === "source") {
      var rows = [];
      mixes.forEach(function (m) {
        var f = firsts(m)[sel.number];
        if (f) rows.push(panelRow(m, sel.number, m.name, byNumber[m.number].color, f.r, f.y, f.sends, focus));
      });
      return { kind: "source", title: self.name, trackMuted: self.muted, color: self.color, editable: true, rows: rows, master: null };
    }
    var mix = mixes.filter(function (m) { return m.number === sel.number; })[0];
    if (!mix) return null;
    var bySource = firsts(mix);
    var list = Object.keys(bySource).map(Number).sort(function (a, b) { return a - b; }).map(function (s) {
      var t = byNumber[s];
      return panelRow(mix, s, t ? t.name : "Track " + s, t ? t.color : 0, bySource[s].r, bySource[s].y, bySource[s].sends, focus);
    });
    var masterRead = masters[mix.number], known = !!masterRead && typeof masterRead.vol === "number";
    return { kind: "mix", title: mix.name, trackMuted: false, color: self.color, editable: mix.editable, rows: list,
      master: { key: mix.number + ":master", track: mix.number, y: 0, source: -1, name: "Master", vol: known ? masterRead.vol : null, db: known ? dbText(masterRead.vol) : null, readOnly: mix.duplicate, focused: false } };
  }
  // The panel's visible sends (and the master) as read commands, split under the URL limit.
  function buildPanelRequests(panel, maxChars) {
    if (!panel) return [];
    var cmds = panel.rows.map(function (r) { return "GET/TRACK/" + r.track + "/SEND/" + r.y; });
    if (panel.master) cmds.push("GET/TRACK/" + panel.master.track + "/SEND/0");
    return joinCommands(cmds, maxChars);
  }

  // A read slot with the fields a control is still holding kept from the screen. `keep(track, y, field)` says
  // whether `field` ("vol", "muted", "pan") of that send is held (dragging, writes not landed, or a read begun too early).
  // A slot that is now another source's is taken whole.
  var HELD_FIELDS = ["vol", "muted", "pan"];
  function holdSlot(prev, next, keep, track, y) {
    if (!keep || !prev || prev.source !== next.source) return next;
    var out = { source: next.source, vol: next.vol, muted: next.muted, pan: next.pan };
    HELD_FIELDS.forEach(function (f) { if (keep(track, y, f)) out[f] = prev[f]; });
    return out;
  }

  // What the page keeps between polls. The track list arrives every 250 ms (update), the receives in sweeps a second
  // (requests, apply, endSweep). Rules:
  //   - a read is applied only under the layout it was requested for, so a track list that changed mid-sweep never
  //     puts a level on the wrong row;
  //   - a reply merges slot by slot, so a partial reply (a missing or unusable line) never removes a cell;
  //   - when the layout changes the old receives are dropped, and `grid()` is null until the new layout has been
  //     read in full or a sweep has ended under it, so the page keeps what it shows and never paints stale levels.
  function createGridModel() {
    var tracks = null, key = null, receives = {}, masters = {}, settled = false;

    function mixesNow() { return tracks ? listMixes(tracks) : []; }
    function complete() {
      return mixesNow().every(function (m) {
        var r = receives[m.number] || [];
        for (var n = 0; n < m.recvcnt; n++) if (!r[n]) return false;
        return true;
      });
    }
    return {
      // A complete track list from the poller. Returns true when the layout changed (the page should sweep now).
      update: function (list) {
        var k = layoutKey(list), changed = k !== key;
        tracks = list;
        if (changed) { key = k; receives = {}; masters = {}; settled = false; }
        return changed;
      },
      key: function () { return key; },
      known: function () { return tracks !== null; },
      // The sweep to run now: { key, commands }.
      requests: function (maxChars) { return { key: key, commands: buildReadRequests(mixesNow(), maxChars) }; },
      // One reply of a sweep. Returns false when it was dropped (read under another layout).
      // `keep(track, y, field)` (optional) names the levels and mutes a control still holds: they keep the value on
      // screen (holdSlot). The master (y 0, a hardware output, source -1) is read only when the panel asks for it.
      apply: function (forKey, text, keep) {
        if (!tracks || forKey !== key) return false;
        var mixes = {};
        mixesNow().forEach(function (m) { mixes[m.number] = m; });
        parseSendReply(text).forEach(function (s) {
          var m = mixes[s.track];
          if (!m) return;
          if (s.y === 0) {
            if (s.source !== -1) return;
            var prevMaster = masters[m.number];
            masters[m.number] = { vol: prevMaster && keep && keep(m.number, 0, "vol") ? prevMaster.vol : s.vol };
            return;
          }
          if (s.y > -1 || s.y < -m.recvcnt || !(s.source >= 1)) return; // a missing line (source -1)
          var r = (receives[m.number] || (receives[m.number] = []));
          var next = { source: s.source, vol: s.vol, muted: s.muted, pan: s.pan };
          r[-s.y - 1] = r[-s.y - 1] ? holdSlot(r[-s.y - 1], next, keep, m.number, s.y) : next;
        });
        return true;
      },
      // A level moved on screen ahead of its read (a drag): patch is { vol }, { muted } or { pan }.
      setLocal: function (track, y, patch) {
        var slot = y === 0 ? masters[track] || (masters[track] = {}) : (receives[track] || [])[-y - 1];
        if (!slot) return;
        Object.keys(patch).forEach(function (f) { slot[f] = patch[f]; });
      },
      tracks: function () { return tracks || []; },
      // The panel for a selection (core selectSource/selectMix/selectCell), or null.
      panel: function (sel) { return tracks ? buildPanel(tracks, receives, masters, sel) : null; },
      // The state writeAllowed checks, with the page's canEdit verdict; null before any track list.
      writeState: function (canEditNow) { return tracks ? { canEdit: !!canEditNow, mixes: mixesNow(), receives: receives, masters: masters } : null; },
      // Every request of a sweep has settled (answered or failed).
      endSweep: function (forKey) { if (forKey === key) settled = true; },
      // The screen's grid, or null while the current layout has no usable read yet.
      grid: function (filter) {
        if (!tracks || !(settled || complete())) return null;
        return buildGrid(tracks, receives, filter);
      }
    };
  }

  return { parseTrackReply: parseTrackReply, listMixes: listMixes, parseSendReply: parseSendReply, panText: panText, panValue: panValue, panPos: panPos, setPanCommand: setPanCommand,
    buildReadRequests: buildReadRequests, layoutKey: layoutKey, buildGrid: buildGrid, createGridModel: createGridModel,
    canEdit: canEdit, markerReadCommand: markerReadCommand, markerWriteCommand: markerWriteCommand, parseMarker: parseMarker, newProjectId: newProjectId,
    claimProject: claimProject, markerHolds: markerHolds, writeAllowed: writeAllowed, selectSource: selectSource,
    selectMix: selectMix, selectedMixName: selectedMixName, selectCell: selectCell, gridShape: gridShape, sourceWidth: sourceWidth, buildPanel: buildPanel, buildPanelRequests: buildPanelRequests, holdSlot: holdSlot };
});
