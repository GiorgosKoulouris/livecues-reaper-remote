// Monitor: UI wiring (mix list, mix view, offline). The pure logic is in core.js.
(function () {
  "use strict";
  var S = LCRR.shared, reaper = S.reaper, poll = S.poll, core = LCRR.monitor.core;
  var conn = S.guard.createConnection({ failuresToOffline: 2, settleMs: 1500 });
  var poller = poll.createPoller({ intervalMs: 250 });
  poller.addCommand("NTRACK");
  poller.addCommand("TRACK");

  var els = {
    view: document.getElementById("monitor-list-view"),
    loading: document.getElementById("monitor-loading"),
    list: document.getElementById("monitor-mixes"),
    setup: document.getElementById("monitor-setup"),
    notice: document.getElementById("monitor-notice"),
    state: document.getElementById("monitor-state"),
    stateText: document.getElementById("monitor-state-text"),
    banner: document.getElementById("monitor-banner"),
    mixView: document.getElementById("monitor-mix-view"),
    title: document.getElementById("monitor-title"),
    back: document.getElementById("monitor-back"),
    masterHost: document.getElementById("monitor-master-fader"),
    rows: document.getElementById("monitor-rows"),
    rowsEmpty: document.getElementById("monitor-rows-empty")
  };
  var MAX_URL = 900;    // encoded URL characters per request, "/_/" included (REAPER truncates near 1026)
  var open = null;      // the open mix: { name, number, recvcnt, hwoutcnt, receives, master (linear level of the first hardware output, null until read), masterFader, viewKey, busy, rows: { n: row refs }, solo (null, or { index, source, changes } while a source is soloed) }
  var lastTracks = [];  // latest complete track list
  var tracksKey = "";    // core.tracksKey(lastTracks)
  var listed = false;   // a complete track reply has been shown at least once
  var lastKey = null;   // what the list currently shows, so unchanged polls don't rebuild the DOM

  function setState(name) {
    if (els.stateText.textContent === name) return;
    els.stateText.textContent = name;
    els.state.setAttribute("data-state", name);
    document.body.setAttribute("data-state", name);
  }
  function setOffline(off) {
    document.body.classList.toggle("offline", off);
    if (open) Object.keys(open.rows).forEach(function (n) { open.rows[n].mute.disabled = off; open.rows[n].solo.disabled = off; });
    els.banner.textContent = off ? "REAPER is unreachable. Showing the last known list. Retrying…" : "";
  }
  // Message above the list (the later mix view uses it for "your mix is gone"). Pass "" to clear.
  function showNotice(text) {
    els.notice.textContent = text;
    els.notice.hidden = !text;
  }

  function renderMixes(mixes) {
    var key = JSON.stringify(mixes);
    els.loading.hidden = true;
    els.view.setAttribute("aria-busy", "false");
    if (key === lastKey) return;
    lastKey = key;
    els.setup.hidden = mixes.length > 0;
    els.list.hidden = mixes.length === 0;
    els.list.textContent = "";
    mixes.forEach(function (m) {
      var li = document.createElement("li");
      var b = document.createElement("button");
      b.type = "button";
      b.className = "monitor-mix";
      var name = document.createElement("span");
      name.className = "monitor-mix-name";
      name.textContent = m.name;
      b.appendChild(name);
      var note = document.createElement("span");
      note.className = "monitor-mix-note";
      if (m.duplicate) {
        // A mix is identified by its name, so a shared name can't be opened.
        b.classList.add("duplicate");
        b.setAttribute("aria-disabled", "true");
        note.textContent = "Track " + m.number + " · same name as another track";
        b.appendChild(note);
      } else {
        b.setAttribute("data-track", String(m.number));
        b.setAttribute("data-name", m.name);
      }
      li.appendChild(b);
      els.list.appendChild(li);
    });
  }

  // ---- Mix view ----
  // The latest state a write is checked against (core.writeAllowed).
  function writeState() {
    return open && { number: open.number, receives: open.receives, master: open.master, fresh: open.viewKey === tracksKey, offline: conn.isOffline() };
  }
  function cancelDrags() {
    if (!open) return;
    open.masterFader.cancel();
    Object.keys(open.rows).forEach(function (n) { open.rows[n].fader.cancel(); });
  }

  // The master fader writes the first hardware output (send index 0, always a number), only while the latest
  // poll agrees. It is built once when the mix opens (see openMix).
  function createMaster(m) {
    return LCRR.monitor.fader.create({
      label: "Master level",
      getTarget: function () { return open === m && m.master !== null ? { track: m.number, y: 0, source: -1 } : null; },
      check: function (t) { return open === m && core.writeAllowed(t, writeState()); },
      send: function (cmd) { return poll.send(cmd); },
      onLevel: function (v) {
        if (open !== m) return;
        m.master = v; // the screen follows the thumb; reads can't override it until the writes land
        showMaster();
      }
    });
  }
  // A fresh master fader with no level (when the mix opens, or its track number changed).
  function mountMaster(m) {
    m.masterFader = createMaster(m);
    els.masterHost.textContent = "";
    els.masterHost.appendChild(m.masterFader.el);
    m.masterFader.setName("Master");
    m.masterFader.setValueText("\u2013");
  }
  function showMaster() {
    open.masterFader.setValueText(open.master === null ? "\u2013" : core.dbText(open.master));
    if (open.master !== null) open.masterFader.setValue(open.master);
  }

  function createRow(n) {
    var m = open;
    var el = document.createElement("li");
    el.className = "monitor-row";
    var mute = document.createElement("button");
    mute.className = "monitor-row-mute";
    mute.type = "button";
    mute.textContent = "M";
    mute.setAttribute("aria-pressed", "false");
    mute.title = "Mute";
    mute.disabled = conn.isOffline();
    var solo = document.createElement("button");
    solo.className = "monitor-row-solo";
    solo.type = "button";
    solo.textContent = "S";
    solo.setAttribute("aria-pressed", "false");
    solo.title = "Solo in my mix";
    solo.disabled = conn.isOffline();
    solo.addEventListener("click", function () { if (open === m) toggleSolo(n); });
    // The fader writes to this row's receive (send index -n) of the mix, and only while the latest poll still agrees.
    var fader = LCRR.monitor.fader.create({
      label: "Level",
      getTarget: function () {
        var r = open === m && m.receives[n - 1];
        return r ? { track: m.number, y: -n, source: r.source } : null;
      },
      check: function (t) { return open === m && core.writeAllowed(t, writeState()); },
      send: function (cmd) { return poll.send(cmd); },
      onLevel: function (v) {
        if (open !== m || !m.receives[n - 1]) return;
        m.receives[n - 1].vol = v; // the screen follows the thumb; reads can't override it until the writes land
        renderRows();
      }
    });
    // Mute: a native button, so the click fires on release and the browser cancels it when the finger slides
    // away or the page scrolls. The state sent is worked out from what is on screen (core.createMuteWriter).
    var muter = core.createMuteWriter({
      check: function (t) { return open === m && core.writeAllowed(t, writeState()); },
      send: function (cmd) { return poll.send(cmd); }
    });
    mute.addEventListener("click", function () {
      var r = open === m && m.receives[n - 1];
      if (!r) return;
      if (muter.press({ track: m.number, y: -n, source: r.source }, !!r.muted)) {
        r.muted = !r.muted; // the screen follows the tap; reads can't override it until the write has landed
        renderRows();
      }
    });
    el.appendChild(fader.el);
    el.appendChild(solo);
    el.appendChild(mute);
    return { el: el, fader: fader, muter: muter, mute: mute, solo: solo, nameText: null, muted: null, soloOn: null };
  }

  // Keeps each row's DOM across polls and touches only what changed.
  function renderRows() {
    var rows = core.rowsFor(open.receives, lastTracks), seen = {};
    rows.forEach(function (r, i) {
      seen[r.n] = true;
      var ref = open.rows[r.n];
      if (!ref) ref = open.rows[r.n] = createRow(r.n);
      if (els.rows.children[i] !== ref.el) els.rows.insertBefore(ref.el, els.rows.children[i] || null);
      ref.el.setAttribute("data-y", String(r.y));
      ref.el.setAttribute("data-source", String(r.source));
      ref.fader.setColor(reaper.colorToCss(r.color));
      if (r.name !== ref.nameText) { ref.nameText = r.name; ref.fader.setName(r.name); ref.mute.setAttribute("aria-label", "Mute " + r.name); ref.solo.setAttribute("aria-label", "Solo " + r.name + " in my mix"); }
      var soloOn = !!open.solo && open.solo.index === r.n - 1;
      if (soloOn !== ref.soloOn) { ref.soloOn = soloOn; ref.solo.classList.toggle("on", soloOn); ref.solo.setAttribute("aria-pressed", soloOn ? "true" : "false"); }
      ref.fader.setValueText(r.db);
      ref.fader.setValue(r.vol);
      if (r.muted !== ref.muted) { ref.muted = r.muted; ref.mute.classList.toggle("on", r.muted);
        ref.el.classList.toggle("muted", r.muted);
        ref.mute.setAttribute("aria-pressed", r.muted ? "true" : "false");
      }
    });
    Object.keys(open.rows).forEach(function (n) {
      if (seen[n]) return;
      open.rows[n].fader.cancel(); // the row is gone: its drag ends with no final write
      els.rows.removeChild(open.rows[n].el);
      delete open.rows[n];
    });
    els.rowsEmpty.hidden = rows.length > 0;
  }

  // Solo in my mix (a toggle, kept in memory only): mutes the other receives, and a second tap puts back only
  // what it changed (core.soloPlan / restorePlan). Every write is a plain mute write through the row's mute
  // writer, so the stale check and the read hold are the same as for the M button.
  function applyMoves(moves) {
    // All or nothing: if any row can't be written right now (a mute write outstanding, or the stale check
    // fails) nothing is sent and the tap does nothing.
    var targets = moves.map(function (mv) {
      var r = open.receives[mv.index], ref = open.rows[mv.index + 1];
      return r && ref ? { ref: ref, r: r, to: mv.to, target: { track: open.number, y: -(mv.index + 1), source: r.source } } : null;
    });
    var ok = targets.every(function (t) { return t && !t.ref.muter.busy() && core.writeAllowed(t.target, writeState()); });
    if (!ok) return false;
    targets.forEach(function (t) { t.ref.muter.press(t.target, !t.to); t.r.muted = t.to; });
    return true;
  }
  function toggleSolo(n) {
    var m = open, i = n - 1, r = m.receives[i];
    if (!r) return;
    if (m.solo && m.solo.index === i) { endSolo(); return; }
    var plan = core.soloPlan(m.receives, i, m.solo && m.solo.changes);
    if (!applyMoves(plan.moves)) return;
    m.solo = { index: i, source: r.source, changes: plan.changes };
    renderRows();
  }
  // Puts back what solo changed. Returns false when it could not (nothing is sent; solo stays on).
  function endSolo() {
    var m = open;
    if (!m || !m.solo) return true;
    if (!applyMoves(core.restorePlan(m.receives, m.solo.changes).moves)) return false;
    m.solo = null;
    renderRows();
    return true;
  }

  function openMix(name, number) {
    open = { solo: null, name: name, number: number, recvcnt: 0, hwoutcnt: 0, receives: [], master: null, masterFader: null, viewKey: null, busy: false, rows: {} };
    mountMaster(open);
    showNotice("");
    els.title.textContent = name;
    els.back.hidden = false;
    els.rows.textContent = "";
    els.rowsEmpty.hidden = false;
    els.view.hidden = true;
    els.mixView.hidden = false;
    poller.pollNow(); // the next poll fills in the rows
  }

  function closeMix(reason) {
    cancelDrags();
    els.masterHost.textContent = "";
    open = null;
    els.title.textContent = "Monitor";
    els.back.hidden = true;
    els.mixView.hidden = true;
    els.view.hidden = false;
    lastKey = null; // list DOM was left as it was; rebuild it from the latest poll
    showNotice(reason || "");
    if (listed) renderMixes(core.listMixes(lastTracks));
  }

  // Reads every receive of the open mix, in requests small enough for REAPER's URL limit. A reply is applied
  // only if the mix is still the same one at the same track index (a late reply is dropped, never applied).
  function fetchReceives() {
    var m = open;
    if (m.busy || conn.isOffline() || m.recvcnt < 1) return;
    m.busy = true;
    var number = m.number, key = tracksKey, tokens = {};
    var muteTokens = {}, masterToken = m.masterFader.readToken();
    Object.keys(m.rows).forEach(function (n) { tokens[n] = m.rows[n].fader.readToken(); muteTokens[n] = m.rows[n].muter.readToken(); });
    Promise.all(core.buildReadRequests(number, m.recvcnt, MAX_URL).map(function (cmd) {
      return poll.send(cmd).then(function (text) {
        // Sources are track numbers: drop a reply read before the track list changed (the next poll re-reads).
        if (open !== m || m.number !== number || key !== tracksKey) return;
        // The master level, held like a row's: not while dragged, or until its writes landed, or if the read began before.
        var ov = core.parseMasterReply(text, m.number, m.hwoutcnt);
        if (ov && m.masterFader.canApply(masterToken)) { m.master = ov.vol; showMaster(); }
        // A row being dragged, or whose writes haven't landed, or whose read began before that, keeps its level.
        m.receives = core.holdLevels(m.receives, core.applyReceives(m.receives, text, m.number, m.recvcnt), function (i) {
          var ref = m.rows[i + 1];
          return !!ref && !ref.fader.canApply(tokens[i + 1]);
        }, function (i) {
          var ref = m.rows[i + 1];
          return !!ref && !ref.muter.canApply(muteTokens[i + 1]);
        });
        m.viewKey = key;
        renderRows();
      }, function () {});
    })).then(function () { m.busy = false; });
  }

  els.list.addEventListener("click", function (ev) {
    var b = ev.target.closest("button[data-track]");
    if (b && !open) openMix(b.getAttribute("data-name"), parseInt(b.getAttribute("data-track"), 10));
  });
  // Leaving the mix puts solo back first (best effort: offline or stale, nothing can be written and the
  // mutes stay as they are; the page keeps no copy, so a reload can't undo them).
  els.back.addEventListener("click", function () {
    // Online but the restore was refused (a mute write outstanding): stay, so a second tap retries.
    if (!endSolo() && !conn.isOffline()) return;
    closeMix("");
  });
  window.addEventListener("pagehide", function () { endSolo(); });

  function followMix() {
    var f = core.findMix(lastTracks, open.name);
    if (f.status === "gone") return closeMix("The mix “" + open.name + "” is no longer there (renamed, removed, no longer set up as a mix, or another project). Pick a mix again.");
    if (f.status === "duplicate") return closeMix("More than one track is now named IEM_" + open.name + ", so the mix was closed. Rename one of them.");
    if (f.number !== open.number) { // the level was read for another track: start over with no level
      open.masterFader.cancel();
      open.master = null;
      mountMaster(open);
    }
    open.number = f.number;
    open.hwoutcnt = f.hwoutcnt;
    if (f.recvcnt !== open.recvcnt) { open.recvcnt = f.recvcnt; open.receives = open.receives.slice(0, f.recvcnt); }
    if (open.solo && (!open.receives[open.solo.index] || open.receives[open.solo.index].source !== open.solo.source)) open.solo = null; // the soloed source is gone or moved
    if (open.viewKey === tracksKey) renderRows(); // else the receives were read for an older track list
    fetchReceives();
  }

  poller.subscribe(function (e) {
    var live = e.ok && !!reaper.parseTransport(e.text);
    conn.update(live);
    if (!live) {
      if (!conn.isOffline()) return; // one missed poll keeps the list
      cancelDrags();                 // offline: a drag ends with no final write
      setOffline(true);
      setState("offline");
      if (!listed) els.loading.textContent = "Can’t reach REAPER. This page keeps retrying.";
      return;
    }
    setOffline(false);
    setState("connected");
    var r = core.parseTrackReply(e.text);
    if (!r) {
      if (!listed) els.loading.textContent = "Waiting for REAPER’s track list…";
      return; // incomplete reply: keep the list as it is
    }
    listed = true;
    lastTracks = r.tracks;
    tracksKey = core.tracksKey(r.tracks);
    if (open) followMix();
    else renderMixes(core.listMixes(r.tracks));
  });

  poller.start();
})();
