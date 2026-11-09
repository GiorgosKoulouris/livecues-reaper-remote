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
    mixName: document.getElementById("monitor-mix-name"),
    back: document.getElementById("monitor-back"),
    overallHost: document.getElementById("monitor-overall-fader"),
    overallDb: document.getElementById("monitor-overall-db"),
    rows: document.getElementById("monitor-rows"),
    rowsEmpty: document.getElementById("monitor-rows-empty")
  };
  var MAX_URL = 900;    // encoded URL characters per request, "/_/" included (REAPER truncates near 1026)
  var open = null;      // the open mix: { name, number, recvcnt, hwoutcnt, receives, overall (linear level of the first hardware output, null until read), overallFader, viewKey, busy, rows: { n: row refs } }
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
    if (open) Object.keys(open.rows).forEach(function (n) { open.rows[n].mute.disabled = off; });
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
    return open && { number: open.number, receives: open.receives, overall: open.overall, fresh: open.viewKey === tracksKey, offline: conn.isOffline() };
  }
  function cancelDrags() {
    if (!open) return;
    open.overallFader.cancel();
    Object.keys(open.rows).forEach(function (n) { open.rows[n].fader.cancel(); });
  }

  // The overall fader writes the first hardware output (send index 0, always a number), only while the latest
  // poll agrees. It is built once when the mix opens (see openMix).
  function createOverall(m) {
    return LCRR.monitor.fader.create({
      label: "Overall level",
      getTarget: function () { return open === m && m.overall !== null ? { track: m.number, y: 0, source: -1 } : null; },
      check: function (t) { return open === m && core.writeAllowed(t, writeState()); },
      send: function (cmd) { return poll.send(cmd); },
      onLevel: function (v) {
        if (open !== m) return;
        m.overall = v; // the screen follows the thumb; reads can't override it until the writes land
        showOverall();
      }
    });
  }
  // A fresh overall fader with no level (when the mix opens, or its track number changed).
  function mountOverall(m) {
    m.overallFader = createOverall(m);
    els.overallHost.textContent = "";
    els.overallHost.appendChild(m.overallFader.el);
    els.overallDb.textContent = "\u2013";
  }
  function showOverall() {
    var text = open.overall === null ? "\u2013" : core.dbText(open.overall);
    if (els.overallDb.textContent !== text) els.overallDb.textContent = text;
    if (open.overall !== null) open.overallFader.setValue(open.overall);
  }

  function createRow(n) {
    var m = open;
    var el = document.createElement("li");
    el.className = "monitor-row";
    var swatch = document.createElement("span"), name = document.createElement("span"), db = document.createElement("span"), mute = document.createElement("button");
    swatch.className = "monitor-row-swatch";
    name.className = "monitor-row-name";
    db.className = "monitor-row-db";
    mute.className = "monitor-row-mute";
    mute.type = "button";
    mute.textContent = "Mute";
    mute.setAttribute("aria-pressed", "false");
    mute.disabled = conn.isOffline();
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
    [swatch, name, db, mute, fader.el].forEach(function (c) { el.appendChild(c); });
    return { el: el, fader: fader, muter: muter, swatch: swatch, name: name, db: db, mute: mute, color: null, nameText: null, dbText: null, muted: null };
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
      var css = reaper.colorToCss(r.color);
      if (css !== ref.color) { ref.color = css; ref.swatch.style.background = css || ""; }
      if (r.name !== ref.nameText) { ref.nameText = r.name; ref.name.textContent = r.name; }
      if (r.db !== ref.dbText) { ref.dbText = r.db; ref.db.textContent = r.db; }
      ref.fader.setValue(r.vol);
      if (r.muted !== ref.muted) { ref.muted = r.muted; ref.mute.classList.toggle("on", r.muted);
        ref.mute.setAttribute("aria-pressed", r.muted ? "true" : "false");
        ref.mute.textContent = r.muted ? "Muted" : "Mute";
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

  function openMix(name, number) {
    open = { name: name, number: number, recvcnt: 0, hwoutcnt: 0, receives: [], overall: null, overallFader: null, viewKey: null, busy: false, rows: {} };
    mountOverall(open);
    showNotice("");
    els.mixName.textContent = name;
    els.rows.textContent = "";
    els.rowsEmpty.hidden = false;
    els.view.hidden = true;
    els.mixView.hidden = false;
    poller.pollNow(); // the next poll fills in the rows
  }

  function closeMix(reason) {
    cancelDrags();
    els.overallHost.textContent = "";
    open = null;
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
    var muteTokens = {}, overallToken = m.overallFader.readToken();
    Object.keys(m.rows).forEach(function (n) { tokens[n] = m.rows[n].fader.readToken(); muteTokens[n] = m.rows[n].muter.readToken(); });
    Promise.all(core.buildReadRequests(number, m.recvcnt, MAX_URL).map(function (cmd) {
      return poll.send(cmd).then(function (text) {
        // Sources are track numbers: drop a reply read before the track list changed (the next poll re-reads).
        if (open !== m || m.number !== number || key !== tracksKey) return;
        // The overall level, held like a row's: not while dragged, or until its writes landed, or if the read began before.
        var ov = core.parseOverallReply(text, m.number, m.hwoutcnt);
        if (ov && m.overallFader.canApply(overallToken)) { m.overall = ov.vol; showOverall(); }
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
  els.back.addEventListener("click", function () { closeMix(""); });

  function followMix() {
    var f = core.findMix(lastTracks, open.name);
    if (f.status === "gone") return closeMix("The mix “" + open.name + "” is no longer there (renamed, removed, no longer set up as a mix, or another project). Pick a mix again.");
    if (f.status === "duplicate") return closeMix("More than one track is now named IEM_" + open.name + ", so the mix was closed. Rename one of them.");
    if (f.number !== open.number) { // the level was read for another track: start over with no level
      open.overallFader.cancel();
      open.overall = null;
      mountOverall(open);
    }
    open.number = f.number;
    open.hwoutcnt = f.hwoutcnt;
    if (f.recvcnt !== open.recvcnt) { open.recvcnt = f.recvcnt; open.receives = open.receives.slice(0, f.recvcnt); }
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
