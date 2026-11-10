// IEM Mix: UI wiring. The logic is core.js (the grid model, the lock, the panel, the stale check); DOM is built with
// textContent only, because track names are user data.
//
// Reads, in one place so later features can hook in:
//   - the poller asks NTRACK;TRACK every 250 ms; each complete reply updates the model (`onTracks`);
//   - `sweep()` reads every receive of every listed mix once a second (SWEEP_MS), and at once when the layout changes;
//   - `panelRead()` reads the docked panel's visible sends (and a mix's master) on every poll, faster than the grid;
//   - `render()` paints the model's grid and the panel; it is cheap and runs after every poll and read. The table is
//     rebuilt only when its shape changes (`core.gridShape`); levels and the selection are painted into it in place,
//     because a wheel gesture stays on the element it began on and would end if that element went away.
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
  // Snapshots live behind IEM Setup's bridge (section LCRR_IEM); its heartbeat rides on the same poll.
  var bridge = LCRR.iemmix.bridge, snaps = LCRR.iemmix.snapshots;
  var beat = bridge.wire.createHeartbeat({ staleMs: 2500 });
  poller.addCommand(bridge.wire.getCommand("heartbeat"));

  function $(id) { return document.getElementById(id); }
  var els = {
    chip: $("iemmix-state"), chipText: $("iemmix-state-text"), banner: $("iemmix-banner"), filter: $("iemmix-filter"),
    empty: $("iemmix-empty"), scroll: $("iemmix-scroll"), head: $("iemmix-head"), body: $("iemmix-body"),
    lock: $("iemmix-lock"), panes: document.querySelector(".iemmix-panes"), panel: $("iemmix-panel"), panelTitle: $("iemmix-panel-title"), panelFlag: $("iemmix-panel-flag"),
    panelHint: $("iemmix-panel-hint"), panelLockHint: $("iemmix-panel-lock"), panelList: $("iemmix-panel-list"),
    snapsNote: $("iemmix-snaps-note"), snapsForm: $("iemmix-snaps-form"), snapsName: $("iemmix-snaps-name"),
    snapsSave: $("iemmix-snaps-save"), snapsEmpty: $("iemmix-snaps-empty"), snapsList: $("iemmix-snaps-list")
  };
  var ui = { listed: false, shown: null, cells: {}, selShown: null, sweeping: false, phase: "connecting", unlocked: false, sel: null,
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
  // The panel's rows are going away. A drag ends with no write, but a wheel burst or a reset is finished: its value has been written,
  // so it still gets its `e` (the undo entry), which the old fader sends on its own after its row has gone.
  function dropRows() {
    Object.keys(ui.rows).forEach(function (k) {
      var parts = ui.rows[k].parts;
      Object.keys(parts).forEach(function (f) { if (!parts[f].finishWheel || !parts[f].finishWheel()) parts[f].cancel(); });
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
    listenRender();
    updateSnaps();
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

  // ---- snapshots -------------------------------------------------------------------------------------------------
  // Save, overwrite and delete go to IEM Setup's bridge and ignore REAPER's undo (project ExtState), so a press and hold
  // is their only protection. Every write goes through snapWrite, which asks the one gate (editable) and the bridge.
  // With the bridge not running only this section is unavailable; the rest of the page does not depend on it.
  var SNAP_REFRESH_MS = 3000, HOLD_MS = 1000;
  var snapUi = { list: null, error: "", reading: false, again: false, readAt: 0, busy: false, holding: 0, pending: false, key: null, result: "" };
  var snapClient = bridge.createClient(S.bridgeClient.createBrowserIo());

  function snapBridge() { return snaps.bridgeState(beat.state()); }
  function snapCanWrite() { return snaps.canWrite(ui.phase, ui.unlocked, snapBridge()) && editable() && !snapUi.busy; }

  function readSnaps() {
    if (snapUi.reading) { snapUi.again = true; return; }
    snapUi.reading = true;
    snapUi.again = false;
    snapUi.readAt = Date.now();
    snapClient.snapshots().then(function (reply) {
      var list = snaps.readList(reply);
      if (list) { snapUi.list = list; if (!snapUi.busy) snapUi.error = ""; }
      else if (reply && reply.status === "refused") snapUi.error = snaps.errorText(reply.error);
    }, function () {}).then(function () {
      snapUi.reading = false;
      if (snapUi.again) readSnaps();
      updateSnaps();
    });
  }

  // `send` returns the bridge's reply; `describe` (recall only) words an ok reply, which stays until the next write.
  function snapWrite(send, describe) {
    if (!snapCanWrite()) return Promise.resolve(false);
    snapUi.busy = true;
    snapUi.error = "";
    snapUi.result = "";
    updateSnaps();
    return send().then(function (reply) {
      if (reply && reply.status === "ok") { if (describe) snapUi.result = describe(reply); return ""; }
      return snaps.errorText(reply && reply.error);
    }, function (err) { return snaps.errorText(err); }).then(function (note) {
      snapUi.busy = false;
      snapUi.error = note;
      readSnaps();
      updateSnaps();
      return !note;
    });
  }

  // A press-and-hold key (LCRR.shared.hold). There is no click handler on purpose: a plain tap must never act. The list is
  // not rebuilt while a hold is down, so a refresh cannot swap the key under the finger; it is repainted once afterwards.
  var DOC_RELEASE = ["pointerup", "pointercancel"];
  function holdKey(btn, label, onComplete) {
    var down = false;
    btn.textContent = label;
    function finish() {
      if (!down) return;
      down = false;
      DOC_RELEASE.forEach(function (n) { document.removeEventListener(n, release); });
      btn.classList.remove("holding");
      snapUi.holding--;
      if (!snapUi.holding && snapUi.pending) { snapUi.pending = false; renderSnapList(); }
    }
    var hold = S.hold.createHold({ holdMs: HOLD_MS, onCancel: finish, onComplete: function () { finish(); onComplete(); } });
    function release() { hold.cancel(); finish(); }
    function start() {
      if (btn.disabled || down) return;
      down = true;
      snapUi.holding++;
      btn.classList.add("holding");
      DOC_RELEASE.forEach(function (n) { document.addEventListener(n, release); });
      hold.start();
    }
    btn.style.setProperty("--hold-ms", HOLD_MS + "ms");
    btn.addEventListener("pointerdown", function (e) { if (e.button === 0) start(); });
    ["pointerup", "pointerleave", "pointercancel", "blur"].forEach(function (n) { btn.addEventListener(n, release); });
    btn.addEventListener("contextmenu", function (e) { e.preventDefault(); });
    btn.addEventListener("keydown", function (e) {
      if ((e.key === " " || e.key === "Enter") && !e.repeat) { e.preventDefault(); start(); }
    });
    btn.addEventListener("keyup", release);
    return btn;
  }

  function snapSavedText(seconds) {
    var d = new Date(seconds * 1000);
    return isNaN(d.getTime()) ? "" : d.toLocaleDateString(undefined, { month: "short", day: "numeric" }) + " " +
      d.toLocaleTimeString(undefined, { hour: "2-digit", minute: "2-digit" });
  }

  // Recall the whole band, or one mix. REAPER's web API has no track GUIDs, so one mix's GUID comes from the bridge's
  // `state` reply, found by the mix's name.
  function recall(name, mixName) {
    var send = function () {
      if (mixName === null) return snapClient.recall(name);
      return snapClient.state().then(function (reply) {
        var found = snaps.findMix(reply, mixName);
        return found.guid ? snapClient.recall(name, found.guid) : { status: "refused", error: { code: found.code } };
      });
    };
    snapWrite(send, function (reply) { return snaps.recallText(reply, name, mixName); });
  }
  function selectedMix() { return core.selectedMixName(model.tracks(), ui.sel); }

  function renderSnapList() {
    var ready = snaps.canRead(ui.phase, snapBridge()) && !!snapUi.list;
    var ok = snapCanWrite();
    var mixName = selectedMix();
    var key = ready ? JSON.stringify([snapUi.list, ok, mixName]) : "";
    els.snapsEmpty.hidden = !ready || snapUi.list.length > 0;
    if (key === snapUi.key) return;
    if (snapUi.holding) { snapUi.pending = true; return; }
    snapUi.key = key;
    clear(els.snapsList);
    if (!ready) return;
    snapUi.list.forEach(function (s) {
      var li = h("li", "iemmix-snap");
      var text = h("div", "iemmix-snap-text");
      text.appendChild(h("span", "iemmix-snap-name", s.name));
      var when = snapSavedText(s.saved);
      text.appendChild(h("span", "iemmix-snap-meta", snaps.counts(s) + (when ? " · " + when : "")));
      li.appendChild(text);
      var keys = [{ kind: "recallAll", run: function () { recall(s.name, null); } }];
      if (mixName !== null) keys.push({ kind: "recallMix", run: function () { recall(s.name, mixName); } });
      keys.push({ kind: "overwrite", run: function () { snapWrite(function () { return snapClient.save(s.name, true); }); } },
        { kind: "delete", run: function () { snapWrite(function () { return snapClient.remove(s.name); }); } });
      keys.forEach(function (k) {
        var b = holdKey(h("button", "iemmix-key iemmix-hold" + (k.kind === "recallMix" ? " is-one-mix" : "")), snaps.keyLabel(k.kind, mixName), k.run);
        b.type = "button";
        b.disabled = !ok;
        b.title = snaps.holdTitle(k.kind, mixName, s.name);
        li.appendChild(b);
      });
      els.snapsList.appendChild(li);
    });
  }

  function updateSnaps() {
    var bridgeState = snapBridge(), ok = snapCanWrite();
    var note = snaps.note(ui.phase, ui.unlocked, bridgeState, snapUi.error, snapUi.result);
    if (els.snapsNote.textContent !== note) els.snapsNote.textContent = note;
    els.snapsNote.hidden = !note;
    var available = snaps.canRead(ui.phase, bridgeState);
    els.snapsForm.hidden = !available;
    els.snapsName.disabled = !ok;
    els.snapsSave.disabled = !ok;
    if (!available) snapUi.list = null;
    else if (!snapUi.reading && Date.now() - snapUi.readAt >= SNAP_REFRESH_MS) readSnaps();
    renderSnapList();
  }
  els.snapsForm.addEventListener("submit", function (ev) {
    ev.preventDefault();
    if (!snapCanWrite()) return;
    var names = (snapUi.list || []).map(function (s) { return s.name; });
    var check = snaps.checkName(els.snapsName.value, names, bridge.nameFits);
    if (!check.name) { snapUi.error = snaps.errorText(check); updateSnaps(); return; }
    snapWrite(function () { return snapClient.save(check.name, false); }).then(function (done) {
      if (done) els.snapsName.value = "";
    });
  });
  poller.subscribe(function (e) {
    if (e.ok) beat.update(bridge.wire.parseExtState(e.text, "heartbeat"));
    updateSnaps();
  });

  // ---- the Source column's width ------------------------------------------------------------------------------------
  // A handle on the corner header's right edge: drag it, use the arrow keys, or double-click for the automatic width. The
  // width is a convenience kept per browser. The one handle element is put back in the corner whenever the table is rebuilt.
  var SOURCE_WIDTH_KEY = "lcrr.iemmix.sourceWidth", SOURCE_KEY_STEP = 16;
  function saveSourceWidth(w) {
    try { if (w === null) localStorage.removeItem(SOURCE_WIDTH_KEY); else localStorage.setItem(SOURCE_WIDTH_KEY, String(w)); } catch (e) { /* the width just isn't remembered */ }
  }
  function setSourceWidth(px) {
    var w = core.sourceWidth(px, els.scroll.clientWidth);
    if (w === null) { els.scroll.removeAttribute("data-sized"); els.scroll.style.removeProperty("--iemmix-src"); resizer.removeAttribute("aria-valuenow"); }
    else { els.scroll.setAttribute("data-sized", ""); els.scroll.style.setProperty("--iemmix-src", w + "px"); resizer.setAttribute("aria-valuenow", String(w)); }
    return w;
  }
  function sourceColumnPx() { return resizer.parentNode.getBoundingClientRect().width; }
  var resizer = h("div", "iemmix-col-resize");
  resizer.setAttribute("role", "separator");
  resizer.setAttribute("aria-orientation", "vertical");
  resizer.setAttribute("aria-label", "Source column width");
  resizer.tabIndex = 0;
  resizer.title = "Drag to set this column's width. Double-click for the automatic width.";
  var resize = null; // { id, x, w, last } while a drag is on
  function endResize() {
    if (!resize) return;
    var w = resize.last;
    resize = null;
    resizer.classList.remove("dragging");
    if (w !== null) saveSourceWidth(w);
  }
  resizer.addEventListener("pointerdown", function (ev) {
    if (resize || (ev.pointerType === "mouse" && ev.button !== 0)) return;
    resize = { id: ev.pointerId, x: ev.clientX, w: sourceColumnPx(), last: null };
    resizer.classList.add("dragging");
    try { resizer.setPointerCapture(ev.pointerId); } catch (e) { /* the drag still works while the pointer is over the handle */ }
    ev.preventDefault();
  });
  resizer.addEventListener("pointermove", function (ev) {
    if (resize && ev.pointerId === resize.id) resize.last = setSourceWidth(resize.w + ev.clientX - resize.x);
  });
  ["pointerup", "pointercancel", "lostpointercapture"].forEach(function (n) { resizer.addEventListener(n, endResize); });
  resizer.addEventListener("dblclick", function () { setSourceWidth(null); saveSourceWidth(null); });
  resizer.addEventListener("keydown", function (ev) {
    var dir = ev.key === "ArrowRight" ? 1 : (ev.key === "ArrowLeft" ? -1 : 0);
    if (!dir) return;
    ev.preventDefault();
    saveSourceWidth(setSourceWidth(sourceColumnPx() + dir * SOURCE_KEY_STEP));
  });
  try { var savedWidth = localStorage.getItem(SOURCE_WIDTH_KEY); if (savedWidth) setSourceWidth(Number(savedWidth)); } catch (e) { /* the automatic width */ }

  // ---- painting --------------------------------------------------------------------------------------------------
  // A send's cell is a look-only slider (fill, 0 dB tick, handle, the number on the left, DESIGN.md): it takes no drags.
  // Each part is kept in ui.cells under the panel row's key, and paintCell writes the level into it.
  function cellEl(cell, source, mixNumber, label) {
    var td = h("td", "iemmix-cell");
    if (!cell) return td; // inert
    td.classList.add("is-on");
    var inner = h("button", "iemmix-cell-inner");
    inner.type = "button";
    inner.setAttribute("data-mix", String(mixNumber));
    if (!cell.readOnly) inner.setAttribute("data-wheel", "1");
    ["fill", "mark", "handle"].forEach(function (p) { inner.appendChild(h("span", "iemmix-cell-" + p)); });
    var text = h("span", "iemmix-cell-text"), flip = h("span", "iemmix-cell-text on-handle");
    var db = text.appendChild(h("span", "iemmix-db")), dbFlip = flip.appendChild(h("span", "iemmix-db"));
    flip.setAttribute("aria-hidden", "true"); // the second copy, clipped to the handle so a digit it crosses stays readable
    inner.appendChild(text);
    inner.appendChild(flip);
    if (cell.tag) {
      var tag = h("span", "iemmix-tag", cell.tag);
      tag.title = "More than one send from this source to this mix. Shown: the first.";
      inner.appendChild(tag);
    }
    td.appendChild(inner);
    ui.cells[mixNumber + ":" + source] = { td: td, inner: inner, db: db, dbFlip: dbFlip, label: label, vol: cell.vol, shown: null };
    return td;
  }
  function paintCell(e, cell) {
    e.vol = cell.vol;
    var shown = cell.vol + "|" + cell.db + "|" + cell.muted;
    if (shown === e.shown) return;
    e.shown = shown;
    e.td.classList.toggle("is-muted", !!cell.muted);
    e.td.classList.toggle("over", cell.vol > faderCore.CAP);
    e.inner.style.setProperty("--pos", String(faderCore.faderPos(cell.vol)));
    e.db.textContent = e.dbFlip.textContent = cell.db;
    e.inner.setAttribute("aria-label", e.label + ": " + cell.db + " dB" + (cell.muted ? ", muted" : ""));
  }
  function paintCells(grid) {
    grid.rows.forEach(function (row) {
      row.cells.forEach(function (c, i) {
        var e = c && ui.cells[grid.mixes[i].number + ":" + row.source];
        if (e) paintCell(e, c);
      });
    });
  }
  // The selection marks: the source's row, the mix's column and the highlighted cell.
  function paintSelection() {
    var sel = ui.sel, shown = JSON.stringify(sel && [sel.kind, sel.number, sel.focus]);
    if (shown === ui.selShown) return;
    ui.selShown = shown;
    Array.prototype.forEach.call(els.head.querySelectorAll(".is-selected"), function (e) { e.classList.remove("is-selected"); });
    Array.prototype.forEach.call(els.body.querySelectorAll(".is-selected, .is-focused"), function (e) { e.classList.remove("is-selected", "is-focused"); });
    if (!sel) return;
    var marked = sel.kind === "mix" ? els.head.querySelector('[data-track="' + sel.number + '"]') : els.body.querySelector('[data-source="' + sel.number + '"]');
    if (marked) marked.classList.add("is-selected");
    var cell = sel.focus && ui.cells[sel.focus.mix + ":" + sel.focus.source];
    if (cell) cell.td.classList.add("is-focused");
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
    ui.cells = {};
    ui.selShown = null;
    crossTd = null;
    crossed = [];
    els.body.style.setProperty("--mark", String(faderCore.faderPos(1)));
    var tr = h("tr");
    var corner = h("th", "iemmix-corner", "Source");
    corner.appendChild(resizer);
    tr.appendChild(corner);
    grid.mixes.forEach(function (m) {
      var th = h("th", "iemmix-mix");
      th.scope = "col";
      th.setAttribute("data-track", String(m.number));
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
      var th = h("th", "iemmix-row-th");
      th.scope = "row";
      var head = h("div", "iemmix-row-head");
      var css = reaper.colorToCss(row.color);
      if (css) { th.classList.add("is-tinted"); th.style.setProperty("--c", css); }
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
      row.cells.forEach(function (c, i) { r.appendChild(cellEl(c, row.source, grid.mixes[i].number, row.name + " in " + grid.mixes[i].name)); });
      els.body.appendChild(r);
    });
  }
  // Keeps the table across polls unless its shape changed, and keeps the last grid while the model has no usable
  // read for a new layout.
  function render() {
    var grid = model.grid(els.filter.value);
    if (!grid) return;
    renderPanel();
    els.filter.disabled = false;
    var key = core.gridShape(grid);
    if (key !== ui.shown) {
      ui.shown = key;
      var any = grid.mixes.length > 0;
      els.empty.hidden = any && grid.rows.length > 0;
      els.scroll.hidden = !any || grid.totalRows === 0;
      if (!any) els.empty.textContent = "No mixes yet. A mix is a track named IEM_<name> with a receive and a hardware output; set them up in IEM Setup.";
      else if (!grid.totalRows) els.empty.textContent = "No source feeds a mix yet.";
      else if (!grid.rows.length) els.empty.textContent = "No source matches “" + els.filter.value.trim() + "”.";
      paint(grid);
    }
    paintCells(grid);
    paintSelection();
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
      el.setAttribute("data-side", pan < 0 ? "left" : "right"); // the readout sits on the side the handle is not
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
      // Alt-click: back to the centre, as one write and one undo entry.
      reset: function () {
        var t = ref.target();
        if (!t || pan === null || pan === 0 || drag.active() || !drag.nudge(t, 0)) return;
        pan = 0;
        show();
        model.setLocal(t.track, t.y, { pan: 0 });
        render();
        drag.finishWheel();
      },
      finishWheel: drag.finishWheel,
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
    if (ui.sel && !p) { ui.sel = null; updateSnaps(); } // the track moved or went: never show another track's panel
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
      dropRows();
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
    render();
    panelRead();
    updateSnaps(); // the one-mix recall key follows the selected mix
  }
  function selectCellAt(source, mixNumber) {
    var next = core.selectCell(model.tracks(), ui.sel, source, mixNumber);
    if (next !== ui.sel) select(next); // the cell already highlighted: nothing to do
  }
  function onGridClick(ev) {
    var tracks = model.tracks();
    var pick = ev.target.closest("[data-pick]"), cell = ev.target.closest("button[data-mix]");
    if (pick) {
      if (pick.getAttribute("data-pick") === "mix") select(core.selectMix(tracks, parseInt(pick.closest("th").getAttribute("data-track"), 10)));
      else select(core.selectSource(tracks, parseInt(pick.closest("tr").getAttribute("data-source"), 10)));
    } else if (cell) {
      selectCellAt(parseInt(cell.closest("tr").getAttribute("data-source"), 10), parseInt(cell.getAttribute("data-mix"), 10));
    }
  }
  els.head.addEventListener("click", onGridClick);
  els.body.addEventListener("click", onGridClick);

  // ---- hover: the cell's row and column ----------------------------------------------------------------------------
  var crossTd = null, crossed = [];
  function setCross(td) {
    if (td === crossTd) return;
    crossTd = td;
    crossed.forEach(function (e) { e.classList.remove("is-cross"); });
    crossed = [];
    if (!td) return;
    var col = td.cellIndex;
    crossed = Array.prototype.slice.call(td.parentNode.cells);
    Array.prototype.forEach.call(els.body.rows, function (r) { crossed.push(r.cells[col]); });
    crossed.push(els.head.rows[0].cells[col]);
    crossed.forEach(function (e) { e.classList.add("is-cross"); });
  }
  els.body.addEventListener("mouseover", function (ev) { setCross(ev.target.closest("td.iemmix-cell")); });
  els.body.addEventListener("mouseleave", function () { setCross(null); });

  // ---- the wheel ---------------------------------------------------------------------------------------------------
  // Over a panel fader or an editable grid cell the wheel nudges the level by 0.5 dB; a cell's step first selects it as a
  // click does, then goes through that row's fader, so there is one write path. One listener for grid and panel, non-passive:
  // it prevents the scroll only when wheel.decide says it is acting. One gesture stays on what it began on (wheel.createWheelLatch).
  var wheelLatch = wheel.createWheelLatch(), wheelStates = {}; // what each send's wheel has gathered, by row key
  // What the pointer is over: { key, cell } or null when a new gesture there should scroll. The pointer's position, not
  // ev.target: browsers keep a wheel gesture's target on the element it began on.
  function wheelTarget(ev) {
    if (!editable()) return null;
    var at = document.elementFromPoint(ev.clientX, ev.clientY) || ev.target;
    var faderEl = at.closest(".iemmix-fader"), btn = at.closest("button[data-wheel]");
    var key = null, cell = null;
    if (faderEl) Object.keys(ui.rows).forEach(function (k) { if (ui.rows[k].fader && ui.rows[k].fader.el === faderEl) key = k; });
    else if (btn) {
      cell = { source: parseInt(btn.closest("tr").getAttribute("data-source"), 10), mix: parseInt(btn.getAttribute("data-mix"), 10) };
      key = cell.mix + ":" + cell.source;
    }
    return key === null ? null : { key: key, cell: cell };
  }
  // The level a gesture steps from, or null when it cannot act now (the row is being dragged or has gone).
  function wheelLevel(t) {
    var ref = ui.rows[t.key];
    if (ref) return ref.fader && !ref.fader.active() ? ref.fader.level() : null;
    return t.cell && ui.cells[t.key] ? ui.cells[t.key].vol : null;
  }
  els.panes.addEventListener("wheel", function (ev) {
    var now = Date.now(), t = wheelLatch.route(now, wheelTarget(ev));
    if (!t) return;
    var r = wheel.decide({ locked: !editable(), deltaY: ev.deltaY, deltaMode: ev.deltaMode, vol: wheelLevel(t), now: now, state: wheelStates[t.key] });
    wheelStates[t.key] = r.state;
    if (!r.act) { wheelLatch.scrolled(now); return; }
    ev.preventDefault();
    if (r.value === null) return; // still gathering, or nothing to write: the panel does not move for it
    if (t.cell) selectCellAt(t.cell.source, t.cell.mix);
    var ref = ui.rows[t.key];
    if (ref && ref.fader) ref.fader.nudge(r.value);
  }, { passive: false });

  // ---- Alt-click: reset ---------------------------------------------------------------------------------------------
  // Alt-click on a cell or a panel fader sets the level to 0 dB; on a pan control, the centre. Unlocked only; through each
  // control's normal write path, as one undo entry, and on release, like a click. A cell comes up highlighted first, as
  // a click does. The press is stopped before it reaches the thumb, so an Alt-click can never start a drag.
  var RESET_LEVEL = 1; // 0 dB
  function rowOwning(prop, el) {
    var found = null;
    Object.keys(ui.rows).forEach(function (k) { var part = ui.rows[k][prop]; if (part && part.el === el) found = ui.rows[k]; });
    return found;
  }
  function resetLevel(ref) {
    if (!ref || !ref.fader || ref.fader.active() || ref.fader.level() === RESET_LEVEL) return;
    if (ref.fader.nudge(RESET_LEVEL)) ref.fader.finishWheel();
  }
  els.panes.addEventListener("pointerdown", function (ev) {
    if (ev.altKey && ev.target.closest(".iemmix-fader, .iemmix-pan")) ev.stopPropagation();
  }, true);
  els.panes.addEventListener("click", function (ev) {
    if (!ev.altKey || !editable()) return;
    var panEl = ev.target.closest(".iemmix-pan"), faderEl = ev.target.closest(".iemmix-fader"), btn = ev.target.closest("button[data-wheel]");
    if (panEl) { var panRow = rowOwning("pan", panEl); if (panRow) panRow.pan.reset(); }
    else if (faderEl) resetLevel(rowOwning("fader", faderEl));
    else if (btn) {
      var source = parseInt(btn.closest("tr").getAttribute("data-source"), 10), mix = parseInt(btn.getAttribute("data-mix"), 10);
      selectCellAt(source, mix);
      resetLevel(ui.rows[mix + ":" + source]);
    }
  }, true);

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

  // ---- Listen ----------------------------------------------------------------------------------------------------
  // One mix at a time is heard through the cue track IEM-Cue, by its send's level (1 or 0, no undo entry). The state is
  // read from the sends (listen.js), so a reload, a second tablet and a REAPER undo all show as they are. A tap
  // goes through the same gate as every write: `editable()`. Reads ride the grid's once-a-second sweep.
  var listen = LCRR.iemmix.listen, listenModel = listen.createListenModel();
  var listenUi = { sweeping: false, writing: false, shown: null };
  function listenView() { return listen.view(model.tracks(), listenModel.found(), listenModel.settled()); }
  function listenRender() {
    var box = $("iemmix-listen");
    if (!box || !model.known()) return;
    var v = listenView(), can = editable();
    box.hidden = !v.rows.length;
    var key = JSON.stringify([v, can, listenUi.writing]);
    if (key === listenUi.shown) return;
    listenUi.shown = key;
    var keys = $("iemmix-listen-keys");
    clear(keys);
    v.rows.forEach(function (r) {
      var b = h("button", "iemmix-listen-key", r.name);
      b.type = "button";
      b.setAttribute("data-listen", String(r.number));
      b.setAttribute("aria-pressed", r.on ? "true" : "false");
      b.disabled = !can || !r.enabled || listenUi.writing;
      b.title = r.status === "nocuetrack" || r.status === "nocue" ? "No cue send for this mix. Set it up in IEM Setup." : "Listen to " + r.name + " in the cue output.";
      keys.appendChild(b);
    });
    var note = v.note;
    if (v.several) note = "More than one mix is on in the cue. Tap one to leave only that one.";
    $("iemmix-listen-note").textContent = note;
  }
  function listenSweep() {
    if (listenUi.sweeping || !model.known() || conn.isOffline() || listenUi.writing) return;
    var tracks = model.tracks(), key = listenModel.key(), mark = listenModel.mark();
    var cmds = listen.buildRequests(tracks, listenModel.found(), MAX_URL);
    listenUi.sweeping = true;
    Promise.all(cmds.map(function (cmd) {
      return poll.send(cmd).then(function (text) { if (listenModel.apply(tracks, key, text, mark)) listenRender(); }, function () {});
    })).then(function () { listenModel.endSweep(key, mark); listenUi.sweeping = false; listenRender(); });
  }
  function listenTap(number) {
    var plan = listen.tapPlan(model.tracks(), listenModel.found(), listenModel.settled(), number, editable());
    if (!plan || listenUi.writing) return;
    listenUi.writing = true;
    listenModel.wrote(); // reads begun before this write no longer count
    plan.writes.forEach(function (w) { listenModel.setLocal(w.track, w.vol); });
    listenRender();
    poll.send(plan.command).then(function () {}, function () {}).then(function () {
      listenUi.writing = false;
      listenModel.wrote();
      listenRender();
      listenSweep();
    });
  }
  $("iemmix-listen-keys").addEventListener("click", function (ev) {
    var b = ev.target.closest("button[data-listen]");
    if (b && !b.disabled) listenTap(parseInt(b.getAttribute("data-listen"), 10));
  });

  function onTracks(list) {
    ui.listed = true;
    if (model.update(list)) sweep();
    if (listenModel.update(list)) { listenUi.shown = null; listenSweep(); }
    listenRender();
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
  setInterval(listenSweep, SWEEP_MS);
  updateLock();
  poller.start();
})();
