// IEM Setup: UI wiring. Talks to the Lua bridge through client.js; the logic is core.js and every sentence comes from
// words.js. DOM is built with textContent only: track and mix names are user data.
// Writes (create, rename, colour, move to end, delete, output, matrix cell) go through `write()`, which is the one place that checks the lock
// (core.canEdit); each command adds its keys and calls it the same way.
(function () {
  "use strict";
  var S = LCRR.shared, I = LCRR.iem, wire = I.wire, core = I.core, words = I.words;
  var REFRESH_MS = 3000; // while connected, re-read the project this often (a change made in REAPER shows up)

  var conn = S.guard.createConnection({ failuresToOffline: 2, settleMs: 1000 });
  var beat = wire.createHeartbeat({ staleMs: 2500 });
  var poller = S.poll.createPoller({ intervalMs: 500 });
  poller.addCommand(wire.getCommand("heartbeat"));

  var io = S.bridgeClient.createBrowserIo();
  var client = I.client.createClient({
    fetchText: io.fetchText,
    newId: io.newId
  });

  function $(id) { return document.getElementById(id); }
  var els = {
    chip: $("iem-state"), chipText: $("iem-state-text"), banner: $("iem-banner"),
    project: $("iem-project"), projectName: $("iem-project-name"), filter: $("iem-filter"),
    lock: $("iem-lock"), create: $("iem-create"), createLabel: $("iem-create-label"), createName: $("iem-create-name"),
    createCopy: $("iem-create-copy"), createCopyLabel: $("iem-create-copy-label"),
    createGo: $("iem-create-go"), colourBox: $("iem-colour-box"), colourLabel: $("iem-colour-label"), colour: $("iem-colour"),
    move: $("iem-move"), cue: $("iem-cue"), cueOutBox: $("iem-cue-out-box"), cueOutLabel: $("iem-cue-out-label"),
    cueOut: $("iem-cue-out"),
    message: $("iem-message"), empty: $("iem-empty"), scroll: $("iem-scroll"), head: $("iem-head"), body: $("iem-body")
  };

  // `unlocked`: the page opens locked. `note`: the last write's refusal, kept on screen across refreshes until the next
// attempt. `renaming`: { guid, value, focus } while a column header is being edited.
var ui = { phase: "connecting", everLive: false, state: null, stateKey: null, reading: false, again: false, projectPath: null,
    unlocked: false, busy: false, note: "", renaming: null };

  function h(tag, cls, text) {
    var e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text !== undefined) e.textContent = text;
    return e;
  }
  function clear(e) { while (e.firstChild) e.removeChild(e.firstChild); }

  // ---- the lock and the editing controls ------------------------------------------------------------------------------
  els.createLabel.textContent = words.ui("newMix");
  els.createGo.textContent = words.ui("create");
  els.createCopyLabel.textContent = words.ui("copyFrom");
  els.createCopy.title = words.ui("copyFromHint");

  // The copy-from choice: none, then each mix. Rebuilt only when the list changes (so an open list is not closed by a
  // refresh), and a mix that has gone falls back to none.
  var copyKey = null;
  function updateCopyOptions() {
    var mixes = ui.state ? ui.state.mixes : [];
    var key = JSON.stringify(mixes.map(function (m) { return [m.guid, m.name]; }));
    if (key === copyKey) return;
    copyKey = key;
    var chosen = els.createCopy.value;
    clear(els.createCopy);
    var none = h("option", null, words.ui("copyFromNone"));
    none.value = "";
    els.createCopy.appendChild(none);
    mixes.forEach(function (m) {
      var option = h("option", null, m.name);
      option.value = m.guid;
      els.createCopy.appendChild(option);
    });
    els.createCopy.value = chosen;
    if (els.createCopy.value !== chosen) els.createCopy.value = "";
  }
  els.colourLabel.textContent = words.ui("colour");
  els.move.textContent = words.ui("moveToEnd");
  els.move.title = words.ui("moveToEndHint");
  els.colourBox.title = words.ui("colourHint");

  function editable() { return core.canEdit(ui.phase, ui.unlocked) && !ui.busy; }

  function updateControls() {
    var offer = ui.state ? core.folderOffer(ui.state) : null;
    var ok = editable();
    els.lock.disabled = ui.phase !== "ready";
    els.lock.textContent = words.ui(ui.unlocked ? "lock" : "unlock");
    els.lock.title = words.ui(ui.unlocked ? "unlockedHint" : "unlockHint");
    els.lock.setAttribute("aria-pressed", ui.unlocked ? "true" : "false");
    els.create.hidden = !ui.state;
    els.colourBox.hidden = !ui.state;
    updateCopyOptions();
    els.createName.disabled = !ok;
    els.createCopy.disabled = !ok;
    els.createGo.disabled = !ok;
    els.colour.disabled = !ok;
    els.move.hidden = !(offer && offer.moveToEnd);
    els.move.disabled = !ok;
    updateCue(ok);
  }

  // The cue track: Create cue (or Add missing cue sends) while something is missing, and its output picker once it
  // exists, both while unlocked and through write(). The picker is rebuilt only when what it shows changes, and never
  // while it is open (a refresh must not close it).
  els.cueOutLabel.textContent = words.ui("cueOutput");
  els.cueOutBox.title = words.ui("cueOutputHint");
  function updateCue(ok) {
    var offer = ui.state ? core.cueOffer(ui.state) : null;
    var show = !!offer && ok;
    els.cue.hidden = !(show && offer.action);
    els.cue.disabled = !ok;
    if (offer && offer.action) {
      els.cue.textContent = words.ui(offer.action === "create" ? "createCue" : "addCueSends");
      els.cue.title = words.ui(offer.action === "create" ? "createCueHint" : "addCueSendsHint");
    }
    els.cueOutBox.hidden = !(show && offer.picker);
    if (!show || !offer.picker) return;
    var info = offer.picker;
    var names = ui.state.device ? ui.state.device.channels : [];
    var key = JSON.stringify([info, names]);
    els.cueOut.disabled = ui.busy || info.deviceClosed || info.readOnly;
    if (key === els.cueOut.getAttribute("data-key") || document.activeElement === els.cueOut) return;
    els.cueOut.setAttribute("data-key", key);
    clear(els.cueOut);
    els.cueOut.setAttribute("aria-label", words.cuePickerLabel);
    info.options.forEach(function (o) {
      var opt = h("option", "", info.deviceClosed && o.channel !== null ? words.outputText({ channel: o.channel, mono: o.mono }) : words.optionLabel(names, o));
      opt.value = o.value;
      els.cueOut.appendChild(opt);
    });
    els.cueOut.value = info.value;
  }

  els.cue.addEventListener("click", function () { write(function () { return client.createCue(); }); });
  els.cueOut.addEventListener("change", function () {
    var offer = ui.state && core.cueOffer(ui.state);
    var choice = core.parseOutputChoice(els.cueOut.value);
    if (offer && offer.exists && choice) write(function () { return client.setOutput(offer.guid, choice); });
  });

  function setUnlocked(on) {
    ui.unlocked = on;
    if (!on) { ui.renaming = null; ui.note = ""; showMessage(""); }
    updateControls();
    render();
  }

  // The one gate for every project change: refused while locked, busy or the bridge is away. `send` returns the
  // client's promise. A refusal is shown in words; either way the page then re-reads the project, so it shows what
  // REAPER holds now (including after "that track is gone"). Resolves true when the bridge said ok.
  function write(send) {
    if (!editable()) return Promise.resolve(false);
    ui.busy = true;
    ui.note = "";
    showMessage("");
    updateControls();
    return send().then(function (reply) {
      return !!reply && reply.status === "ok" ? "" : words.error(reply && reply.error);
    }, function (err) {
      return words.error(err);
    }).then(function (note) {
      ui.busy = false;
      ui.note = note;
      showMessage(note);
      updateControls();
      // A refresh that landed while the write was out painted every key disabled, and updateControls does not reach
      // them; with nothing changed in REAPER the next read would not repaint either, so repaint here.
      if (ui.paintedBusy) { ui.paintedBusy = false; render(); }
      readState(true);
      return !note;
    });
  }

  function refuse(code) {
    ui.note = words.error({ code: code });
    showMessage(ui.note);
  }

  els.lock.addEventListener("click", function () { setUnlocked(!ui.unlocked); });

  els.create.addEventListener("submit", function (e) {
    e.preventDefault();
    if (!ui.state || !editable()) return;
    var check = core.checkMixName(ui.state, els.createName.value, null);
    if (!check.ok) { refuse(check.code); return; }
    var copyFrom = els.createCopy.value;
    write(function () { return client.create(check.name, copyFrom); }).then(function (ok) {
      if (ok) { els.createName.value = ""; els.createCopy.value = ""; }
    });
  });

  els.colour.addEventListener("change", function () {
    var hex = core.colourField(els.colour.value);
    if (!hex) { refuse("bad_colour"); return; }
    write(function () { return client.colour(hex); });
  });

  els.move.addEventListener("click", function () {
    var offer = ui.state && core.folderOffer(ui.state);
    if (offer && offer.moveToEnd) write(function () { return client.moveToEnd(offer.guid); });
  });

  function saveRename() {
    var r = ui.renaming;
    if (!r || !ui.state || !editable()) return;
    var check = core.checkMixName(ui.state, r.value, r.guid);
    if (!check.ok) { refuse(check.code); return; }
    if (check.unchanged) { ui.renaming = null; showMessage(""); render(); return; }
    write(function () { return client.rename(r.guid, check.name); }).then(function (ok) {
      if (ok) { ui.renaming = null; render(); }
    });
  }

  // ---- connection phase -------------------------------------------------------------------------------------------
  function applyPhase() {
    var was = ui.phase;
    var next = core.connectionPhase(conn.isOffline(), ui.everLive, beat.state());
    ui.phase = next;
    els.chip.setAttribute("data-state", next);
    document.body.setAttribute("data-state", next);
    if (els.chipText.textContent !== words.chip(next)) els.chipText.textContent = words.chip(next);
    els.banner.textContent = words.banner(next);
    els.banner.hidden = !words.banner(next);
    els.filter.disabled = !ui.state;
    if (ui.unlocked && !core.stillUnlocked(true, next, ui.projectPath, ui.projectPath)) setUnlocked(false); // the bridge went away
    else updateControls();
    if (next === "ready" && was !== "ready") readState();
  }

  poller.subscribe(function (e) {
    var live = e.ok && !!S.reaper.parseTransport(e.text);
    conn.update(live);
    if (live) { ui.everLive = true; beat.update(wire.parseExtState(e.text, "heartbeat")); }
    applyPhase();
  });

  // ---- reading the project ----------------------------------------------------------------------------------------
  function showMessage(text) {
    els.message.textContent = text || "";
    els.message.hidden = !text;
  }

  // `again`: a read is already out (it may have been asked before a write landed), so read once more when it returns.
  function readState(again) {
    if (ui.phase !== "ready") return;
    if (ui.reading) { if (again) ui.again = true; return; }
    ui.reading = true;
    client.state().then(function (reply) {
      ui.reading = false;
      var state = core.readState(reply);
      if (!state) { showMessage(words.error(reply && reply.error)); return; }
      showMessage(ui.note);
      var path = state.project ? state.project.path : "";
      if (ui.unlocked && !core.stillUnlocked(true, ui.phase, ui.projectPath, path)) { ui.unlocked = false; ui.renaming = null; ui.note = ""; showMessage(""); }
      ui.projectPath = path;
      var key = JSON.stringify(state);
      if (key === ui.stateKey) { updateControls(); return; } // nothing changed in REAPER: leave the grid (and its scroll position) alone
      ui.stateKey = key;
      ui.state = state;
      els.project.hidden = false;
      els.projectName.textContent = state.project && state.project.name ? state.project.name : "(unsaved project)";
      els.filter.disabled = false;
      els.colour.value = core.folderOffer(state).colour;
      updateControls();
      render();
    }, function (err) {
      ui.reading = false;
      showMessage(words.error(err));
    }).then(function () {
      if (ui.again) { ui.again = false; readState(); }
    });
  }

  // ---- the grid ---------------------------------------------------------------------------------------------------
  function renameBox(col) {
    var box = h("div", "iem-rename");
    var input = h("input");
    input.type = "text";
    input.id = "iem-rename-input";
    input.value = ui.renaming.value;
    input.spellcheck = false;
    input.setAttribute("aria-label", words.renameLabel(col.name));
    input.addEventListener("input", function () { ui.renaming.value = input.value; });
    input.addEventListener("keydown", function (e) {
      if (e.key === "Enter") { e.preventDefault(); saveRename(); }
      else if (e.key === "Escape") { ui.renaming = null; render(); }
    });
    var keys = h("div", "iem-rename-keys");
    var save = h("button", "iem-primary", words.ui("save"));
    save.type = "button";
    save.disabled = !editable();
    save.addEventListener("click", saveRename);
    var cancel = h("button", "", words.ui("cancel"));
    cancel.type = "button";
    cancel.addEventListener("click", function () { ui.renaming = null; render(); });
    keys.appendChild(save);
    keys.appendChild(cancel);
    box.appendChild(input);
    box.appendChild(keys);
    return box;
  }

  // A press-and-hold key (LCRR.shared.hold), for Delete and bulk off (issue 08). It owns the listeners and tells the render
  // gate a hold is active. A release is caught on the document as well as on the key, so it cancels an unfinished hold
  // even if the key has been replaced. There is no click handler on purpose: a plain tap must never act.
  // `onComplete` is called once, after the hold ends and any deferred rebuild has run; it should go through write().
  var HOLD_MS = 1000;
  function holdKey(btn, onComplete) {
    var down = false;
    function finish() {
      if (!down) return;
      down = false;
      DOC_RELEASE.forEach(function (n) { document.removeEventListener(n, release); });
      btn.classList.remove("holding");
      gate.end();
    }
    var hold = S.hold.createHold({
      holdMs: HOLD_MS,
      onCancel: finish,
      onComplete: function () { finish(); onComplete(); }
    });
    function release() { hold.cancel(); finish(); }
    function start() {
      if (btn.disabled || down) return;
      down = true;
      gate.begin();
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
  var DOC_RELEASE = ["pointerup", "pointercancel"];

  // Delete: through write() like every change, and the key exists only while unlocked.
  function deleteKey(col) {
    var btn = h("button", "iem-quiet iem-delete", words.ui("delete"));
    btn.type = "button";
    btn.disabled = ui.busy;
    btn.title = words.ui("deleteHint");
    btn.setAttribute("aria-label", words.deleteLabel(col.name));
    return holdKey(btn, function () { write(function () { return client.deleteMix(col.guid); }); });
  }

  // Adopt, shown only on a stray, through write() like every change.
  function adoptKey(col) {
    var btn = h("button", "iem-quiet iem-adopt", words.ui("adopt"));
    btn.type = "button";
    btn.disabled = ui.busy;
    btn.title = words.ui("adoptHint");
    btn.setAttribute("aria-label", words.adoptLabel(col.name));
    btn.addEventListener("click", function () { write(function () { return client.adopt(col.guid); }); });
    return btn;
  }

  // Row and column toggles, shown only while unlocked: All on is one tap (it adds what is missing and leaves existing
  // sends alone), All off is press-and-hold (it removes every send of the row or column). Both go through write() and
  // send only the ID; the bridge works out the rest. `kind` is "row" or "column".
  function bulkKeys(kind, item) {
    var box = h("div", "iem-bulk");
    var on = h("button", "iem-quiet iem-bulk-on", words.ui("allOn"));
    on.type = "button";
    on.disabled = ui.busy;
    on.title = words.ui("allOnHint");
    on.setAttribute("aria-label", words.allOnLabel(kind, item.name));
    on.addEventListener("click", function () { bulkWrite(kind, item, true); });
    var off = h("button", "iem-quiet iem-bulk-off", words.ui("allOff"));
    off.type = "button";
    off.disabled = ui.busy;
    off.title = words.ui("allOffHint");
    off.setAttribute("aria-label", words.allOffLabel(kind, item.name));
    holdKey(off, function () { bulkWrite(kind, item, false); });
    box.appendChild(on);
    box.appendChild(off);
    return box;
  }
  var BULK_SEND = {
    row: function (item, on) { var r = core.rowRequest(item, on); return client.row(r.source, r.on); },
    column: function (item, on) { var c = core.columnRequest(item, on); return client.column(c.mix, c.on); },
  };
  function bulkWrite(kind, item, on) {
    write(function () { return BULK_SEND[kind](item, on); });
  }

  // The output picker of one mix, shown only while unlocked and never for a mix with several outputs (read-only: the
  // bridge refuses it too). While it is open the grid is not rebuilt (a refresh, such as a musician moving a fader on
  // Monitor, would close it): the picker guard holds the render gate from its first press or focus until it closes
  // (a choice, or focus leaving), and the rebuild deferred meanwhile then runs once. A choice goes through write().
  function outputPicker(col) {
    var mix = ui.state.mixes.filter(function (m) { return m.guid === col.guid; })[0];
    var info = core.outputPicker(ui.state, mix);
    var names = ui.state.device ? ui.state.device.channels : [];
    var box = h("div", "iem-out-pick");
    var select = h("select", "iem-out-select");
    select.setAttribute("aria-label", words.pickerLabel(col.name));
    info.options.forEach(function (o) {
      var opt = h("option", "", info.deviceClosed && o.channel !== null ? words.outputText({ channel: o.channel, mono: o.mono }) : words.optionLabel(names, o));
      opt.value = o.value;
      select.appendChild(opt);
    });
    select.value = info.value;
    select.disabled = ui.busy || info.deviceClosed;
    if (info.deviceClosed) {
      select.title = words.ui("deviceClosed");
      box.appendChild(select);
      box.appendChild(h("span", "iem-out-note", words.ui("deviceClosed")));
      return box;
    }
    var guard = core.createPickerGuard({ begin: function () { gate.begin(); }, end: function () { gate.end(); } });
    ["focus", "pointerdown", "mousedown", "touchstart"].forEach(function (n) { select.addEventListener(n, guard.open); });
    select.addEventListener("blur", guard.close);
    select.addEventListener("keydown", function (e) { if (e.key === "Escape") guard.close(); });
    select.addEventListener("change", function () {
      var choice = core.parseOutputChoice(select.value);
      guard.close();
      if (!choice) return;
      write(function () { return client.setOutput(col.guid, choice); });
    });
    box.appendChild(select);
    return box;
  }

  function headerCell(col) {
    var th = h("th", "iem-mix" + (col.noOutput ? " is-no-output" : ""));
    th.scope = "col";
    var editing = ui.renaming && ui.renaming.guid === col.guid;
    if (editing) {
      th.appendChild(renameBox(col));
    } else {
      th.appendChild(h("span", "iem-mix-name", col.name));
      if (core.canEdit(ui.phase, ui.unlocked)) {
        var rename = h("button", "iem-quiet", words.ui("rename"));
        rename.type = "button";
        rename.disabled = ui.busy;
        rename.setAttribute("aria-label", words.renameLabel(col.name));
        rename.addEventListener("click", function () { ui.renaming = { guid: col.guid, value: col.name, focus: true }; render(); });
        var keys = h("div", "iem-mix-keys");
        keys.appendChild(rename);
        if (col.stray) keys.appendChild(adoptKey(col));
        keys.appendChild(deleteKey(col));
        keys.appendChild(bulkKeys("column", col));
        th.appendChild(keys);
      }
    }
    if (core.canEdit(ui.phase, ui.unlocked) && !col.readOnlyOutput) th.appendChild(outputPicker(col));
    else th.appendChild(h("span", "iem-mix-out", words.outputText(col.output)));
    var flags = words.headerFlags(col).filter(function (f) { return f.code !== "no-output"; });
    if (flags.length) {
      var box = h("div", "iem-flags");
      flags.forEach(function (f) { box.appendChild(h("span", "iem-flag", f.text)); });
      th.appendChild(box);
    }
    return th;
  }

  // While unlocked a cell is a key: one tap switches it on, or off (every send of the pair, no warning). It goes
  // through write(), so a second tap while one is out is ignored (the key is disabled while busy).
  function cellKey(row, col, cell) {
    var btn = h("button", "iem-cell-key");
    btn.type = "button";
    btn.disabled = ui.busy;
    btn.setAttribute("aria-label", words.cellLabel(row, col, cell) + ". " + words.cellAction(row, col, cell));
    btn.title = words.cellAction(row, col, cell);
    btn.addEventListener("click", function () {
      var ask = core.cellRequest(row, col, cell);
      write(function () { return client.cell(ask.source, ask.mix, ask.on); });
    });
    return btn;
  }

  function dataCell(row, col, cell) {
    var td = h("td", "iem-cell");
    var keyed = core.canEdit(ui.phase, ui.unlocked);
    if (!keyed) td.appendChild(h("span", "lcrr-sr", words.cellLabel(row, col, cell)));
    if (cell) td.className += " is-on" + (cell.muted ? " is-muted" : "");
    if (keyed) td.appendChild(cellKey(row, col, cell));
    if (!cell) return td;
    var inner = h("span", "iem-cell-inner");
    inner.setAttribute("aria-hidden", "true");
    inner.appendChild(h("span", "iem-db", cell.db));
    if (cell.nonStandard) {
      var tag = h("span", "iem-tag", words.modeTag(cell.mode));
      tag.title = words.modeNote(cell.mode);
      inner.appendChild(tag);
    }
    if (cell.doubleFeed) {
      var dbl = h("span", "iem-tag is-double", "2×");
      dbl.title = words.doubleFeedNote(cell.doubleFeed);
      inner.appendChild(dbl);
    }
    if (keyed) { td.firstChild.appendChild(inner); return td; }
    td.appendChild(inner);
    return td;
  }

  // Every rebuild goes through the gate: while a hold key is down the grid is left alone (its buttons stay under the
  // finger) and is rebuilt once, from the latest state, when the hold ends.
  var gate = core.createRenderGate(function () { paint(); });
  function render() { gate.request(); }

  function paint() {
    var state = ui.state;
    if (!state) return;
    ui.paintedBusy = ui.busy; // keys built now are disabled while a write is out; write() repaints once it is done
    var hadFocus = !!ui.renaming && !!document.activeElement && document.activeElement.id === "iem-rename-input";
    var filter = els.filter.value;
    var matrix = core.buildMatrix(state, filter);
    var emptyText = words.emptyMatrix(state);
    if (!emptyText && !matrix.rows.length && matrix.totalRows) emptyText = words.noMatch(filter.trim());
    els.empty.textContent = emptyText;
    els.empty.hidden = !emptyText;
    els.scroll.hidden = !matrix.columns.length;

    clear(els.head);
    clear(els.body);
    var tr = h("tr");
    var corner = h("th", "iem-corner", "Tracks");
    corner.scope = "col";
    tr.appendChild(corner);
    matrix.columns.forEach(function (col) { tr.appendChild(headerCell(col)); });
    els.head.appendChild(tr);

    matrix.rows.forEach(function (row) {
      var r = h("tr", "iem-row" + (row.isFolder ? " is-folder" : ""));
      var th = h("th");
      th.scope = "row";
      var name = h("span", "iem-row-name", row.name);
      name.style.paddingLeft = (0.75 + row.depth * 1.25) + "rem";
      th.appendChild(name);
      if (core.canEdit(ui.phase, ui.unlocked)) th.appendChild(bulkKeys("row", row));
      r.appendChild(th);
      row.cells.forEach(function (cell, i) { r.appendChild(dataCell(row, matrix.columns[i], cell)); });
      els.body.appendChild(r);
    });

    if (ui.renaming && (ui.renaming.focus || hadFocus)) {
      ui.renaming.focus = false;
      var box = $("iem-rename-input");
      if (box) { box.focus(); box.setSelectionRange(box.value.length, box.value.length); }
    }
  }

  els.filter.addEventListener("input", render);
  setInterval(function () { if (!document.hidden) readState(); }, REFRESH_MS);
  document.addEventListener("visibilitychange", function () { if (!document.hidden) readState(); });

  updateControls();
  applyPhase();
  poller.start();
})();
