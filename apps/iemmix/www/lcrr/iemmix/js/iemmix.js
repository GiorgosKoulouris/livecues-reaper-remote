// IEM Mix: UI wiring. The logic is core.js (the grid model, the lock, the panel, the stale check); DOM is built with
// textContent only, because track names are user data.
//
// Reads, in one place so later features can hook in:
//   - the poller asks NTRACK;TRACK every 250 ms; each complete reply updates the model (`onTracks`);
//   - `sweep()` reads every receive of every listed mix once a second (SWEEP_MS), and at once when the layout changes;
//   - `panelRead()` reads the docked panel's visible sends (and a mix's master) on every poll, faster than the grid;
//   - `render()` paints the model's grid and the panel; it is cheap, runs after every poll and read, and rebuilds the
//     table only when what it would show changed.
//
// Writes: every control writes through `canWrite(target)`, which is core.writeAllowed on the latest reads plus the
// one `editable()` gate (the lock). It is the shared fader's `check`, so it runs when each request would go out.
// A panel row is a `ref` (createPanelRow); a control that writes a field of a send (the level fader, mute and pan) registers itself in `ref.parts[field]` and is then held like the fader is: `keepFor` names the fields whose
// parts are still dragging or waiting for their writes, and a read never moves them.
(function () {
  "use strict";
  var S = LCRR.shared, reaper = S.reaper, poll = S.poll, core = LCRR.iemmix.core, wheel = LCRR.iemmix.wheel, faderCore = S.faderCore;
  var PAN_THUMB_PX = 28; // the pan control's thumb; the same number is in the app's CSS
  var MAX_URL = 900;   // encoded URL characters per request, "/_/" included (REAPER truncates near 1026)
  var SWEEP_MS = 1000; // the grid's receives; the rate issue 01 measured as comfortable

  var conn = S.guard.createConnection({ failuresToOffline: 2, settleMs: 1500 });
  var poller = poll.createPoller({ intervalMs: 250 });
  poller.addCommand("NTRACK");
  poller.addCommand("TRACK");
  poller.addCommand(core.markerReadCommand()); // the project marker, in the same reply as the track list
  var model = core.createGridModel();

  function $(id) { return document.getElementById(id); }
  var els = {
    chip: $("iemmix-state"), chipText: $("iemmix-state-text"), banner: $("iemmix-banner"), filter: $("iemmix-filter"),
    empty: $("iemmix-empty"), scroll: $("iemmix-scroll"), head: $("iemmix-head"), body: $("iemmix-body"),
    lock: $("iemmix-lock"), panel: $("iemmix-panel"), panelTitle: $("iemmix-panel-title"), panelFlag: $("iemmix-panel-flag"),
    panelHint: $("iemmix-panel-hint"), panelLockHint: $("iemmix-panel-lock"), panelList: $("iemmix-panel-list")
  };
  var ui = { listed: false, shown: null, sweeping: false, phase: "connecting", unlocked: false, sel: null,
    panelKey: null, rows: {}, panelReading: false, focusShown: null, claim: null, unlocking: false, lockNote: "" };
  var LOCK_HINT = "Locked. Press Unlock to change levels.";
  var LOCK_NOTES = {
    unreadable: "Still locked: REAPER did not report this project’s ID, so the page could not tell when the project changes.",
    mismatch: "Still locked: the project’s ID could not be saved in REAPER, so the page could not tell when the project changes.",
    changed: "Locked: the active project changed. Press Unlock to edit this one."
  };

  function h(tag, cls, text) {
    var e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text !== undefined) e.textContent = text;
    return e;
  }
  function clear(e) { while (e.firstChild) e.removeChild(e.firstChild); }

  function setState(name) {
    ui.phase = name;
    if (els.chipText.textContent === name) return;
    els.chipText.textContent = name;
    els.chip.setAttribute("data-state", name);
    document.body.setAttribute("data-state", name);
  }
  function setOffline(off) {
    els.banner.hidden = !off;
    els.banner.textContent = off ? "REAPER is unreachable. Showing the last known levels. Retrying…" : "";
  }

  // ---- the lock --------------------------------------------------------------------------------------------------
  // The one gate. Every control's write goes through canWrite, which asks it.
  function editable() { return core.canEdit(ui.phase, ui.unlocked); }
  function writeState() { return model.writeState(editable()); }
  function canWrite(target) { return core.writeAllowed(target, writeState()); }

  function cancelAll() {
    Object.keys(ui.rows).forEach(function (k) {
      var parts = ui.rows[k].parts;
      Object.keys(parts).forEach(function (f) { parts[f].cancel(); });
    });
  }
  function updateLock() {
    els.lock.disabled = ui.unlocking || (ui.phase !== "connected" && !ui.unlocked);
    els.lock.textContent = ui.unlocked ? "Lock" : "Unlock";
    els.lock.title = ui.unlocked ? "Lock the page again." : "The page opens locked. Unlock to change levels.";
    els.lock.setAttribute("aria-pressed", ui.unlocked ? "true" : "false");
    els.panel.setAttribute("data-locked", editable() ? "false" : "true");
    els.panelLockHint.hidden = editable();
    var hint = ui.lockNote || LOCK_HINT;
    if (els.panelLockHint.textContent !== hint) els.panelLockHint.textContent = hint;
    Object.keys(ui.rows).forEach(function (k) { setRowEnabled(ui.rows[k]); });
  }
  // Locking ends every drag with no final write.
  function setUnlocked(on) {
    if (ui.unlocked === on) return;
    ui.unlocked = on;
    if (!on) { ui.claim = null; cancelAll(); }
    updateLock();
  }
  // Unlock needs this project's marker: read it, or write it if the project has none. No marker, no Unlock.
  function tryUnlock() {
    ui.unlocking = true;
    ui.lockNote = "";
    updateLock();
    core.claimProject(function (cmd) { return poll.send(cmd); }, Math.random).then(function (claim) {
      ui.unlocking = false;
      if (claim.ok && ui.phase === "connected") { ui.claim = claim; setUnlocked(true); }
      else if (!claim.ok) ui.lockNote = LOCK_NOTES[claim.reason];
      updateLock();
    });
  }
  els.lock.addEventListener("click", function () {
    if (ui.unlocked) { ui.lockNote = ""; setUnlocked(false); }
    else if (ui.phase === "connected" && !ui.unlocking) tryUnlock();
  });

  // ---- painting --------------------------------------------------------------------------------------------------
  function cellEl(cell, mixNumber, label) {
    var td = h("td", "iemmix-cell");
    if (!cell) return td; // inert
    td.classList.add("is-on");
    if (cell.muted) td.classList.add("is-muted");
    var inner = h("button", "iemmix-cell-inner");
    inner.type = "button";
    inner.setAttribute("data-mix", String(mixNumber));
    inner.setAttribute("aria-label", label + ": " + cell.db + " dB" + (cell.muted ? ", muted" : ""));
    inner.appendChild(h("span", "iemmix-db", cell.db));
    if (cell.tag) {
      var tag = h("span", "iemmix-tag", cell.tag);
      tag.title = "More than one send from this source to this mix. Shown: the first.";
      inner.appendChild(tag);
    }
    td.appendChild(inner);
    return td;
  }
  function pickButton(kind, text, hint) {
    var b = h("button", "iemmix-pick", text);
    b.type = "button";
    b.setAttribute("data-pick", kind);
    b.title = hint;
    return b;
  }
  function paint(grid) {
    clear(els.head);
    clear(els.body);
    var tr = h("tr");
    tr.appendChild(h("th", "iemmix-corner", "Source"));
    grid.mixes.forEach(function (m) {
      var th = h("th", "iemmix-mix");
      th.scope = "col";
      th.setAttribute("data-track", String(m.number));
      if (ui.sel && ui.sel.kind === "mix" && ui.sel.number === m.number) th.classList.add("is-selected");
      var pick = pickButton("mix", m.name, "Show this mix's sources and master level in the panel.");
      pick.classList.add("iemmix-mix-name");
      th.appendChild(pick);
      if (m.duplicate) {
        var flags = h("span", "iemmix-flags");
        var f = h("span", "iemmix-flag", "Same name as another");
        f.title = "Track " + m.number + ". A mix is identified by its name, so this one is not editable.";
        flags.appendChild(f);
        th.appendChild(flags);
      }
      tr.appendChild(th);
    });
    els.head.appendChild(tr);
    grid.rows.forEach(function (row) {
      var r = h("tr", "iemmix-row");
      r.setAttribute("data-source", String(row.source));
      if (ui.sel && ui.sel.kind === "source" && ui.sel.number === row.source) r.classList.add("is-selected");
      var th = h("th", "iemmix-row-th");
      th.scope = "row";
      var head = h("div", "iemmix-row-head");
      var css = reaper.colorToCss(row.color);
      if (css) { var sw = h("span", "iemmix-swatch"); sw.style.background = css; head.appendChild(sw); }
      var rp = pickButton("source", row.name, "Show this source's send in every mix in the panel.");
      rp.classList.add("iemmix-row-name");
      head.appendChild(rp);
      if (row.trackMuted) {
        var mf = h("span", "iemmix-flag", "Track muted");
        mf.title = "A muted track silences its sends.";
        head.appendChild(mf);
      }
      th.appendChild(head);
      r.appendChild(th);
      row.cells.forEach(function (c, i) { r.appendChild(cellEl(c, grid.mixes[i].number, row.name + " in " + grid.mixes[i].name)); });
      els.body.appendChild(r);
    });
  }
  // Keeps the table across polls unless its content changed, and keeps the last grid while the model has no usable
  // read for a new layout.
  function render() {
    var grid = model.grid(els.filter.value);
    if (!grid) return;
    renderPanel();
    var key = JSON.stringify([grid, ui.sel && [ui.sel.kind, ui.sel.number]]);
    els.filter.disabled = false;
    if (key === ui.shown) return;
    ui.shown = key;
    var any = grid.mixes.length > 0;
    els.empty.hidden = any && grid.rows.length > 0;
    els.scroll.hidden = !any || grid.totalRows === 0;
    if (!any) els.empty.textContent = "No mixes yet. A mix is a track named IEM_<name> with a receive and a hardware output; set them up in IEM Setup.";
    else if (!grid.totalRows) els.empty.textContent = "No source feeds a mix yet.";
    else if (!grid.rows.length) els.empty.textContent = "No source matches “" + els.filter.value.trim() + "”.";
    paint(grid);
  }

  // ---- the docked panel ------------------------------------------------------------------------------------------
  // A row: a name and level on a shared fader, and the mute and pan controls in `ref.controls`.
  // `ref.data` is the latest panel row; `ref.target()` is the send it addresses right now ({ track, y, source }),
  // which every control passes to the stale check. To add a control: create it in createPanelRow, append it to
  // `ref.controls`, use `ref.target` and `canWrite`, and register `ref.parts[field] = { readToken, canApply, cancel }`
  // (a drag controller or mute writer has all three) so reads hold it; write to the model with `model.setLocal`.
  // Mute and pan are disabled with the rest of the panel while locked or offline (the same gate as every write).
  function setRowEnabled(ref) {
    var on = editable();
    if (ref.muteBtn) ref.muteBtn.disabled = !on;
    if (ref.pan) ref.pan.setEnabled(on);
  }

  // Mute: a native button (a click fires on release and is cancelled by a slide or a scroll). The state sent is
  // worked out from the screen by the shared mute writer, as in Monitor.
  function createMute(ref) {
    var btn = h("button", "iemmix-mute", "M");
    btn.type = "button";
    btn.setAttribute("aria-pressed", "false");
    btn.title = "Mute";
    var muter = faderCore.createMuteWriter({ check: canWrite, send: function (cmd) { return poll.send(cmd); } });
    btn.addEventListener("click", function () {
      var t = ref.target();
      if (!t) return;
      var was = !!ref.data.muted;
      if (muter.press(t, was)) {
        ref.data.muted = !was;
        model.setLocal(t.track, t.y, { muted: !was }); // the screen follows the tap; reads can't override it until the write has landed
        render();
      }
    });
    ref.muteBtn = btn;
    ref.parts.muted = { readToken: muter.readToken, canApply: muter.canApply, cancel: function () {} };
    return btn;
  }

  // Pan: a short slider, centre at the middle, written like the level (faderCore.createFaderDrag with the pan
  // command and a linear -1..1 mapping): one write in flight, the value then `e` on release, held against reads.
  function createPan(ref) {
    var el = h("div", "iemmix-pan"), handle = h("div", "iemmix-pan-handle"), text = h("span", "iemmix-pan-text", "–");
    var thumb = h("div", "iemmix-pan-thumb");
    el.appendChild(h("span", "iemmix-pan-mark"));
    [handle, text, thumb].forEach(function (c) { el.appendChild(c); });
    thumb.setAttribute("aria-label", "Pan");
    thumb.title = "Pan";
    var drag = faderCore.createFaderDrag({
      now: function () { return Date.now(); },
      setTimer: function (fn, ms) { return setTimeout(fn, ms); },
      clearTimer: function (x) { clearTimeout(x); },
      send: function (cmd) { return poll.send(cmd); },
      check: canWrite,
      command: core.setPanCommand, toValue: core.panValue, toPos: core.panPos,
      gateMs: 50, slopPx: 3
    });
    var pan = null, enabled = true;
    function show() {
      el.style.setProperty("--pos", String(core.panPos(pan)));
      text.textContent = core.panText(pan);
    }
    var pointer = S.fader.bindThumb({
      el: el, thumb: thumb, thumbPx: PAN_THUMB_PX, drag: drag, getTarget: ref.target, check: canWrite,
      current: function () { return pan; },
      onMove: function (r, t) {
        pan = r.value;
        show();
        model.setLocal(t.track, t.y, { pan: pan });
        render();
      }
    });
    return {
      el: el,
      thumb: thumb,
      setValue: function (v) { if (drag.active() || v === pan || typeof v !== "number") return; pan = v; show(); },
      setEnabled: function (on) { if (on === enabled) return; enabled = on; el.setAttribute("data-disabled", on ? "false" : "true"); },
      cancel: pointer.cancel,
      readToken: drag.readToken,
      canApply: drag.canApply
    };
  }

  function createPanelRow(d, isMaster) {
    var ref = { key: d.key, data: d, master: isMaster, mode: d.readOnly ? "static" : "fader", parts: {}, fader: null, staticName: null, staticValue: null, staticNote: null };
    ref.el = h("li", "iemmix-prow");
    ref.main = h("div", "iemmix-prow-main");
    ref.controls = h("div", "iemmix-prow-controls"); // pan and mute
    ref.target = function () {
      var x = ref.data;
      if (ref.master) return x.vol === null ? null : { track: x.track, y: 0, source: -1 };
      return { track: x.track, y: x.y, source: x.source };
    };
    if (ref.mode === "fader") {
      ref.fader = S.fader.create({
        prefix: "iemmix",
        label: isMaster ? "Master level" : "Level",
        getTarget: ref.target,
        check: canWrite,
        send: function (cmd) { return poll.send(cmd); },
        onLevel: function (v) {
          var t = ref.target();
          if (!t) return;
          model.setLocal(t.track, t.y, { vol: v }); // the screen follows the thumb; reads can't override it until the writes land
          render();
        }
      });
      ref.parts.vol = ref.fader;
      // The wheel over the level fader nudges it by 0.5 dB. Non-passive, and prevents the page scroll only when
      // wheel.decide says it is acting on a fader: a locked page scrolls as normal. A drag in progress is left alone.
      ref.fader.el.addEventListener("wheel", function (ev) {
        if (ref.fader.active()) return;
        var r = wheel.decide({ locked: !editable(), deltaY: ev.deltaY, deltaMode: ev.deltaMode, vol: ref.fader.level(), now: Date.now(), state: ref.wheel });
        ref.wheel = r.state;
        if (!r.act) return;
        ev.preventDefault();
        if (r.value !== null) ref.fader.nudge(r.value);
      }, { passive: false });
      ref.main.appendChild(ref.fader.el);
      if (!isMaster) { // the master has a level only; a repeated pair is a static row with none of these
        ref.pan = createPan(ref);
        ref.parts.pan = ref.pan;
        ref.controls.appendChild(ref.pan.el);
        ref.controls.appendChild(createMute(ref));
      }
      setRowEnabled(ref);
    } else {
      var box = h("div", "iemmix-prow-static");
      ref.staticName = h("span", "iemmix-prow-name");
      ref.staticValue = h("span", "iemmix-prow-value");
      ref.staticNote = h("span", "iemmix-prow-note");
      box.appendChild(ref.staticName);
      box.appendChild(ref.staticValue);
      box.appendChild(ref.staticNote);
      ref.main.appendChild(box);
    }
    ref.el.appendChild(ref.main);
    ref.el.appendChild(ref.controls);
    return ref;
  }
  function noteFor(d) {
    if (d.tag) return d.tag + ": fixed in IEM Setup or REAPER";
    return d.readOnly ? "Same name as another mix: not editable" : "";
  }
  function updatePanelRow(ref, d) {
    ref.data = d;
    ref.el.classList.toggle("is-muted", !!d.muted);
    ref.el.classList.toggle("is-focused", !!d.focused);
    var db = d.db === null ? "–" : d.db;
    if (ref.mode === "fader") {
      ref.fader.setName(d.name);
      ref.fader.setColor(reaper.colorToCss(d.color || 0));
      ref.fader.setValueText(db);
      if (d.vol !== null) ref.fader.setValue(d.vol);
      if (ref.pan) {
        ref.pan.setValue(d.pan);
        ref.muteBtn.classList.toggle("on", !!d.muted);
        ref.muteBtn.setAttribute("aria-pressed", d.muted ? "true" : "false");
        ref.muteBtn.setAttribute("aria-label", "Mute " + d.name);
        ref.pan.thumb.setAttribute("aria-label", "Pan " + d.name);
      }
    } else {
      ref.staticName.textContent = d.name;
      ref.staticValue.textContent = db;
      ref.staticNote.textContent = noteFor(d);
    }
  }
  function renderPanel() {
    var p = ui.sel ? model.panel(ui.sel) : null;
    if (ui.sel && !p) { ui.sel = null; ui.shown = null; } // the track moved or went: never show another track's panel
    var list = [];
    if (p) {
      if (p.master) list.push({ d: p.master, master: true });
      p.rows.forEach(function (r) { list.push({ d: r, master: false }); });
    }
    els.panelHint.hidden = !!p;
    els.panelTitle.textContent = p ? p.title : "Faders";
    els.panel.setAttribute("data-kind", p ? p.kind : "none");
    var flag = p && p.kind === "source" && p.trackMuted ? "Track muted" : (p && !p.editable ? "Same name as another mix" : "");
    els.panelFlag.textContent = flag;
    els.panelFlag.hidden = !flag;
    var key = list.map(function (x) { return x.d.key + (x.d.readOnly ? "s" : "f"); }).join(",") + "|" + (p ? p.kind + ":" + ui.sel.number : "");
    if (key !== ui.panelKey) { // different rows: rebuild them (a drag on an old one ends with no write)
      cancelAll();
      ui.panelKey = key;
      ui.rows = {};
      clear(els.panelList);
      list.forEach(function (x) {
        var ref = createPanelRow(x.d, x.master);
        ui.rows[ref.key] = ref;
        els.panelList.appendChild(ref.el);
      });
    }
    list.forEach(function (x) { updatePanelRow(ui.rows[x.d.key], x.d); });
    if (p && ui.sel.focus && ui.focusShown !== ui.sel.focus) { // a tapped cell: bring its row into view once
      ui.focusShown = ui.sel.focus;
      var f = els.panelList.querySelector(".is-focused");
      if (f && f.scrollIntoView) f.scrollIntoView({ block: "nearest" });
    }
  }
  // Selecting a name starts a fresh panel and reads it at once; a cell's highlight goes the same way.
  function select(sel) {
    if (!sel) return;
    ui.sel = sel;
    ui.focusShown = null;
    ui.shown = null; // repaint the grid's selection marks
    render();
    panelRead();
  }
  function onGridClick(ev) {
    var tracks = model.tracks();
    var pick = ev.target.closest("[data-pick]"), cell = ev.target.closest("button[data-mix]");
    if (pick) {
      if (pick.getAttribute("data-pick") === "mix") select(core.selectMix(tracks, parseInt(pick.closest("th").getAttribute("data-track"), 10)));
      else select(core.selectSource(tracks, parseInt(pick.closest("tr").getAttribute("data-source"), 10)));
    } else if (cell) {
      var next = core.selectCell(ui.sel, parseInt(cell.closest("tr").getAttribute("data-source"), 10), parseInt(cell.getAttribute("data-mix"), 10));
      if (next !== ui.sel) select(next); // a cell no open panel holds does nothing
    }
  }
  els.head.addEventListener("click", onGridClick);
  els.body.addEventListener("click", onGridClick);

  // ---- holds -----------------------------------------------------------------------------------------------------
  // Taken when a read is sent: for each panel row and field, the token of its control. A reply is applied to a field
  // only if its control is idle and nothing happened since the read began (`canApply`); otherwise the value on screen
  // stays. A row that appeared after the read began has no token and is held for that one reply.
  function takeTokens() {
    var t = {};
    Object.keys(ui.rows).forEach(function (k) {
      var parts = ui.rows[k].parts;
      t[k] = {};
      Object.keys(parts).forEach(function (f) { t[k][f] = parts[f].readToken(); });
    });
    return t;
  }
  function keepFor(tokens) {
    return function (track, y, field) {
      var ref = null;
      Object.keys(ui.rows).forEach(function (k) {
        var d = ui.rows[k].data;
        if (d.track === track && d.y === y) ref = ui.rows[k];
      });
      var part = ref && ref.parts[field];
      return !!part && !part.canApply((tokens[ref.key] || {})[field]);
    };
  }

  // ---- reads -----------------------------------------------------------------------------------------------------
  // One sweep: every receive of every listed mix, in requests under the URL limit, sent side by side. A reply is
  // applied only under the layout it was asked for (the model drops a late one); a failed request just leaves its
  // cells as they were. Never overlaps itself.
  function sweep() {
    if (ui.sweeping || !model.known() || conn.isOffline()) return;
    var req = model.requests(MAX_URL), keep = keepFor(takeTokens());
    ui.sweeping = true;
    Promise.all(req.commands.map(function (cmd) {
      return poll.send(cmd).then(function (text) { if (model.apply(req.key, text, keep)) render(); }, function () {});
    })).then(function () {
      model.endSweep(req.key);
      ui.sweeping = false;
      render();
    });
  }
  // The panel's visible sends and the master, read on every poll (250 ms). Never overlaps itself.
  function panelRead() {
    if (ui.panelReading || !ui.sel || !model.known() || conn.isOffline()) return;
    var cmds = core.buildPanelRequests(model.panel(ui.sel), MAX_URL);
    if (!cmds.length) return;
    var key = model.key(), keep = keepFor(takeTokens());
    ui.panelReading = true;
    Promise.all(cmds.map(function (cmd) {
      return poll.send(cmd).then(function (text) { if (model.apply(key, text, keep)) render(); }, function () {});
    })).then(function () { ui.panelReading = false; });
  }

  function onTracks(list) {
    ui.listed = true;
    if (model.update(list)) sweep();
    render();
    panelRead();
    updateLock();
  }

  poller.subscribe(function (e) {
    var live = e.ok && !!reaper.parseTransport(e.text);
    conn.update(live);
    if (!live) {
      if (!conn.isOffline()) return; // one missed poll keeps the grid
      setOffline(true);
      setState("offline");
      setUnlocked(false); // the connection dropped: lock, and end every drag with no write
      updateLock();
      if (!ui.listed) els.empty.textContent = "Can’t reach REAPER. This page keeps retrying.";
      return;
    }
    setOffline(false);
    setState("connected");
    // Another project became active, or the marker is gone: lock again before anything else (a drag ends with no write).
    if (ui.unlocked && !core.markerHolds(ui.claim, e.text)) {
      ui.lockNote = LOCK_NOTES.changed;
      setUnlocked(false);
    }
    var r = core.parseTrackReply(e.text);
    if (!r) {
      updateLock();
      if (!ui.listed) els.empty.textContent = "Waiting for REAPER’s track list…";
      return; // incomplete reply: keep what is shown
    }
    onTracks(r.tracks);
  });

  els.filter.addEventListener("input", render);
  setInterval(sweep, SWEEP_MS);
  updateLock();
  poller.start();
})();
