// IEM Setup: UI wiring. Talks to the Lua bridge through client.js; the logic is core.js and every sentence comes from
// words.js. DOM is built with textContent only: track and mix names are user data.
// Writes (create, rename, colour, move to end, delete, output, matrix cell) go through `write()`, which is the one place that checks
// core.canEdit (a live bridge, nothing in flight; there is no lock: apps/iem/docs/adr/0001); each command adds its keys and calls it the same way.
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
    setup: $("iem-setup"), projectName: $("iem-project-name"), filter: $("iem-filter"), create: $("iem-create"), createLabel: $("iem-create-label"), createName: $("iem-create-name"),
    createCopy: $("iem-create-copy"), createCopyLabel: $("iem-create-copy-label"),
    createGo: $("iem-create-go"), colourBox: $("iem-colour-box"), colourLabel: $("iem-colour-label"), colour: $("iem-colour"),
    move: $("iem-move"), cue: $("iem-cue"), cueOutBox: $("iem-cue-out-box"), cueOutLabel: $("iem-cue-out-label"),
    cueOut: $("iem-cue-out"),
    message: $("iem-message"), empty: $("iem-empty"), scroll: $("iem-scroll"), head: $("iem-head"), body: $("iem-body"),
    panels: $("iem-panels"), legend: $("iem-legend"),
    folderNote: $("iem-folder-note"), cueNote: $("iem-cue-note"), footer: document.querySelector(".lcrr-footer")
  };
  // The three setup jobs: a disclosure key in the strip above the grid and the panel it opens.
  var SETUP = ["mixes", "folder", "cue"];
  var setup = {};
  SETUP.forEach(function (k) {
    setup[k] = { toggle: $("iem-tog-" + k), status: $("iem-status-" + k), panel: $("iem-panel-" + k) };
  });

  // `note`: the last write's refusal, kept on screen across refreshes until the next attempt. `renaming`: { guid, value, focus }
  // while a column header is being edited. `open`: the setup panel showing (undefined until the first read picks one, null
  // for none). `more`: the mix whose More group is open.
  var ui = { phase: "connecting", everLive: false, state: null, stateKey: null, reading: false, again: false, projectPath: null,
    busy: false, focusCell: null, note: "", renaming: null, more: null, focusMore: null, open: undefined, outputs: undefined };

  function h(tag, cls, text) {
    var e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text !== undefined) e.textContent = text;
    return e;
  }
  function clear(e) { while (e.firstChild) e.removeChild(e.firstChild); }

  // ---- the editing controls ------------------------------------------------------------------------------
  setup.mixes.toggle.firstChild.textContent = words.ui("panelMixes");
  setup.folder.toggle.firstChild.textContent = words.ui("panelFolder");
  setup.cue.toggle.firstChild.textContent = words.ui("panelCue");
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
    els.createCopy.parentNode.hidden = !mixes.length; // nothing to copy from yet
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

  // The Outputs row under the mix names: hidden until asked for, except that the first read of a project shows it
  // while a mix has no output (a silent mix must not go unnoticed). The choice then stays for the session.
  var outputsToggle = $("iem-tog-outputs"), outputsStatus = $("iem-status-outputs");
  function noOutputCount() { return ui.state ? ui.state.mixes.filter(function (m) { return m.outputs.length === 0; }).length : 0; }
  function showOutputs() {
    if (ui.outputs === undefined && ui.state) ui.outputs = noOutputCount() > 0;
    return !!ui.outputs;
  }
  outputsToggle.firstChild.textContent = words.ui("panelOutputs");
  outputsToggle.title = words.ui("outputsHint");
  outputsToggle.addEventListener("click", function () { ui.outputs = !showOutputs(); updateControls(); render(); });

  function editable() { return core.canEdit(ui.phase) && !ui.busy; }

  function updateControls() {
    var offer = ui.state ? core.folderOffer(ui.state) : null;
    var ok = editable();
    els.setup.hidden = !ui.state;
    renderChip();
    updateCopyOptions();
    els.createName.disabled = !ok;
    els.createCopy.disabled = !ok;
    els.createGo.disabled = !ok;
    els.colour.disabled = !ok;
    // The Move key stays in its place; it is only live while something sits after the folder.
    els.move.disabled = !(ok && offer && offer.moveToEnd);
    els.folderNote.textContent = offer && offer.moveToEnd ? words.folderNote(offer) : ""; // only while there is something to say
    updateCue(ok);
    updateSetup(offer);
  }

  // The strip's keys: a status in words per setup job (never colour alone), and the panel that is open. A job that needs
  // something (no mix yet, tracks after the folder, a cue track to make or repair or give an output) is marked. Only an
  // empty project opens a panel by itself (Mixes, the job it starts on); otherwise the grid keeps the height.
  function setupAttention(folder, cue) {
    return { mixes: !!ui.state && ui.state.mixes.length === 0, folder: !!folder && folder.moveToEnd, cue: !!cue && (!!cue.action || !!cue.needsOutput) };
  }
  function updateSetup(folder) {
    if (!ui.state) return;
    var cue = core.cueOffer(ui.state);
    var attn = setupAttention(folder, cue);
    var text = { mixes: words.mixesStatus(ui.state.mixes.length), folder: words.folderStatus(folder), cue: words.cueSummary(cue) };
    if (ui.open === undefined) {
      ui.open = attn.mixes ? "mixes" : null;
    }
    var missing = noOutputCount();
    outputsToggle.hidden = !ui.state.mixes.length;
    outputsToggle.setAttribute("aria-pressed", showOutputs() ? "true" : "false");
    outputsToggle.setAttribute("data-attn", missing > 0 ? "true" : "false");
    if (outputsStatus.textContent !== words.outputsStatus(missing)) outputsStatus.textContent = words.outputsStatus(missing);
    SETUP.forEach(function (k) {
      var on = ui.open === k;
      if (setup[k].status.textContent !== text[k]) setup[k].status.textContent = text[k];
      setup[k].toggle.setAttribute("aria-expanded", on ? "true" : "false");
      setup[k].toggle.setAttribute("data-attn", attn[k] ? "true" : "false");
      setup[k].panel.hidden = !on;
    });
    fitScroll();
  }
  SETUP.forEach(function (k) {
    setup[k].toggle.addEventListener("click", function () { ui.open = ui.open === k ? null : k; updateControls(); });
  });

  // The grid scrolls inside its own box so its headers stay put; the box takes what is left between its top and the footer,
  // so the page does not scroll as well. It never gets shorter than the CSS minimum.
  function fitScroll() {
    if (els.scroll.hidden) return;
    var top = els.scroll.getBoundingClientRect().top + (window.pageYOffset || 0);
    var room = window.innerHeight - top - (els.footer ? els.footer.offsetHeight : 0) - 8;
    els.scroll.style.maxHeight = Math.max(192, Math.floor(room)) + "px";
  }
  window.addEventListener("resize", fitScroll);

  // The cue track: Create cue (or Repair cue) while something is missing, and its output picker once it
  // exists, both through write(). The picker is rebuilt only when what it shows changes, and never
  // while it is open (a refresh must not close it).
  function updateCue(ok) {
    var offer = ui.state ? core.cueOffer(ui.state) : null;
    var show = !!offer;
    els.cue.hidden = !(show && offer.action);
    els.cue.disabled = !ok;
    els.cueNote.textContent = offer && (offer.action || offer.needsOutput) ? words.cueStatus(offer) : "";
    if (offer && offer.action) {
      els.cue.textContent = words.ui(offer.action === "create" ? "createCue" : "repairCue");
      els.cue.title = words.ui(offer.action === "create" ? "createCueHint" : "repairCueHint");
    }
    // Until the engineer has chosen the headphone output the label says so.
    var needed = !!offer && offer.needsOutput;
    els.cueOutLabel.textContent = words.ui(needed ? "cueOutputNeeded" : "cueOutput");
    els.cueOutBox.title = words.ui(needed ? "cueOutputNeededHint" : "cueOutputHint");
    els.cueOutBox.hidden = !(show && offer.picker);
    if (!show || !offer.picker) return;
    var info = offer.picker;
    var names = ui.state.device ? ui.state.device.channels : [];
    var key = JSON.stringify([info, names]);
    els.cueOut.disabled = !ok || info.deviceClosed || info.readOnly;
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

  // The one gate for every project change: refused while busy or the bridge is away. `send` returns the client's
  // promise. A refusal is shown
  // in words; either way the page then re-reads the project, so it shows what REAPER holds now (including after "that
  // track is gone"). Resolves true when the bridge said ok.
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
  // The chip says "Applying…" while a write is out, so the engineer sees the page took the touch.
  function renderChip() {
    var text = ui.busy && ui.phase === "ready" ? words.ui("applying") : words.chip(ui.phase);
    if (els.chipText.textContent !== text) els.chipText.textContent = text;
  }

  function applyPhase() {
    var was = ui.phase;
    var next = core.connectionPhase(conn.isOffline(), ui.everLive, beat.state());
    ui.phase = next;
    els.chip.setAttribute("data-state", next);
    document.body.setAttribute("data-state", next);
    renderChip();
    els.banner.textContent = words.banner(next);
    els.banner.hidden = !words.banner(next);
    els.filter.disabled = !ui.state;
    updateControls();
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
      // Another project became the active one: nothing half-done (a rename, an open More, a message) carries over.
      if (ui.projectPath !== null && ui.projectPath !== path) { ui.renaming = null; ui.more = null; ui.note = ""; showMessage(""); ui.open = undefined; ui.outputs = undefined; }
      ui.projectPath = path;
      var key = JSON.stringify(state);
      if (key === ui.stateKey) { updateControls(); return; } // nothing changed in REAPER: leave the grid (and its scroll position) alone
      ui.stateKey = key;
      ui.state = state;
      els.projectName.textContent = state.project && state.project.name ? state.project.name : words.ui("unsavedProject");
      els.projectName.title = els.projectName.textContent;
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
    var save = h("button", "", words.ui("save"));
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

  // A press-and-hold key (LCRR.shared.hold), for Delete and Adopt. It owns the listeners and tells the render
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

  // A hold key reads as one: a chamfered key with a warn edge and a HOLD legend, never a link-like quiet button.
  function holdFace(btn, text) {
    btn.appendChild(h("span", "iem-hold-text", text));
    btn.appendChild(h("span", "iem-hold-legend", words.ui("holdLegend")));
    return btn;
  }

  // Delete: a press-and-hold in the mix's More group, through write() like every change.
  function deleteKey(col) {
    var btn = holdFace(h("button", "iem-menu-item iem-hold iem-delete"), words.ui("delete"));
    btn.type = "button";
    btn.disabled = ui.busy;
    btn.title = words.ui("deleteHint");
    btn.setAttribute("aria-label", words.deleteLabel(col.name));
    return holdKey(btn, function () { write(function () { return client.deleteMix(col.guid); }); });
  }

  // Adopt, shown only on a stray: it moves the track, turns its master send off and changes its sends, which can change
  // what a musician hears, so it is a press-and-hold like Delete. Through write() like every change.
  function adoptKey(col) {
    var btn = holdFace(h("button", "iem-menu-item iem-hold iem-adopt"), words.ui("adopt"));
    btn.type = "button";
    btn.disabled = ui.busy;
    btn.title = words.ui("adoptHint");
    btn.setAttribute("aria-label", words.adoptLabel(col.name));
    return holdKey(btn, function () { ui.more = null; write(function () { return client.adopt(col.guid); }); });
  }

  // The output picker of one mix, never shown for a mix with several outputs (read-only: the
  // bridge refuses it too). While it is open the grid is not rebuilt (a refresh, such as a musician moving a fader on
  // Monitor, would close it): the picker guard holds the render gate from its first press or focus until it closes
  // (a choice, or focus leaving), and the rebuild deferred meanwhile then runs once. A choice goes through write().
  function outputPicker(col) {
    var mix = ui.state.mixes.filter(function (m) { return m.guid === col.guid; })[0];
    var info = core.outputPicker(ui.state, mix);
    var names = ui.state.device ? ui.state.device.channels : [];
    var box = h("div", "iem-out-pick");
    var current = mix.outputs.length ? mix.outputs[0] : null;
    // A narrow column cannot show a channel name: the closed picker is a short label (1–2, Mono 3, None) with the
    // real select laid over it, so a touch screen still gets its native list with the full names.
    box.appendChild(h("span", "iem-out-short", words.outputShort(current)));
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
      box.title = words.ui("deviceClosed");
    } else {
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
    }
    if (!current) box.classList.add("is-none");
    box.appendChild(select);
    return box;
  }

  // The More menu of one mix: a small popover under its header, so the sticky header keeps its height.
  var MORE_DOTS = '<svg viewBox="0 0 24 24" aria-hidden="true" focusable="false"><circle cx="5" cy="12" r="2" fill="currentColor"/><circle cx="12" cy="12" r="2" fill="currentColor"/><circle cx="19" cy="12" r="2" fill="currentColor"/></svg>';
  function moreMenu(col) {
    var menu = h("div", "iem-more-menu");
    menu.setAttribute("role", "group");
    menu.setAttribute("aria-label", "More for mix " + col.name);
    var rename = h("button", "iem-menu-item", words.ui("rename"));
    rename.type = "button";
    rename.disabled = ui.busy;
    rename.setAttribute("aria-label", words.renameLabel(col.name));
    rename.addEventListener("click", function () { ui.renaming = { guid: col.guid, value: col.name, focus: true }; ui.more = null; render(); });
    menu.appendChild(rename);
    if (col.stray) {
      menu.appendChild(adoptKey(col));
      menu.appendChild(h("p", "iem-key-note", words.ui("adoptNote")));
    }
    menu.appendChild(deleteKey(col));
    return menu;
  }

  function headerCell(col, last) {
    var th = h("th", "iem-mix" + (col.noOutput ? " is-no-output" : "") + (ui.more === col.guid ? " has-menu" : "") + (last ? " is-last" : ""));
    th.scope = "col";
    if (ui.renaming && ui.renaming.guid === col.guid) {
      th.appendChild(renameBox(col));
      return th;
    }
    th.appendChild(h("span", "iem-mix-name", col.name));
    var bar = h("div", "iem-mix-bar");
    // A mix with no output is silent: while the Outputs row is hidden its header says so.
    if (col.noOutput && !showOutputs()) {
      var none = h("span", "iem-nout", words.ui("noOutShort"));
      none.title = words.outputText(null);
      bar.appendChild(none);
    }
    if (core.canEdit(ui.phase)) {
      var open = ui.more === col.guid;
      var more = h("button", "iem-more");
      more.innerHTML = MORE_DOTS; // a fixed drawn icon, no user text
      more.type = "button";
      more.setAttribute("aria-expanded", open ? "true" : "false");
      more.setAttribute("aria-label", words.moreLabel(open, col.name));
      more.title = words.ui("moreHint");
      more.addEventListener("click", function () { ui.more = open ? null : col.guid; ui.focusMore = col.guid; render(); });
      more.setAttribute("data-more", col.guid);
      bar.appendChild(more);
    }
    th.appendChild(bar);
    if (core.canEdit(ui.phase) && ui.more === col.guid) th.appendChild(moreMenu(col));
    var flags = words.headerFlags(col).filter(function (f) { return f.code !== "no-output"; });
    if (flags.length) {
      var box = h("div", "iem-flags");
      flags.forEach(function (f) { box.appendChild(h("span", "iem-flag", f.text)); });
      th.appendChild(box);
    }
    return th;
  }

  // The Outputs row: one picker under each mix name, in the same column.
  function outputCell(col) {
    var th = h("th", "iem-out-cell" + (col.noOutput ? " is-no-output" : ""));
    th.scope = "col";
    if (core.canEdit(ui.phase) && !col.readOnlyOutput) th.appendChild(outputPicker(col));
    else th.appendChild(h("span", "iem-mix-out", words.outputText(col.output)));
    return th;
  }

  // A cell is a key: one tap switches it on, or off (every send of the pair, no warning). It goes through write(), so a second tap while one is out is ignored (the key is disabled while busy).
  function cellKey(row, col, cell) {
    var btn = h("button", "iem-cell-key");
    btn.type = "button";
    btn.disabled = ui.busy;
    btn.tabIndex = -1; // roving: paint() makes one cell the grid's tab stop
    btn.setAttribute("data-row", row.guid);
    btn.setAttribute("data-mix", col.guid);
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
    var keyed = core.canEdit(ui.phase);
    if (!keyed) td.appendChild(h("span", "lcrr-sr", words.cellLabel(row, col, cell)));
    if (cell) td.className += " is-on" + (cell.muted ? " is-muted" : "");
    if (keyed) td.appendChild(cellKey(row, col, cell));
    if (!cell) return td;
    var inner = h("span", "iem-cell-inner");
    inner.setAttribute("aria-hidden", "true");
    inner.appendChild(h("span", "iem-mark"));
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

  // Under the grid, once per tag on screen: what POST, PRE, MODE and 2× mean (tooltips do not exist on touch).
  function paintLegend(matrix) {
    var modes = [], twice = false;
    matrix.rows.forEach(function (row) {
      row.cells.forEach(function (cell) {
        if (!cell) return;
        if (cell.nonStandard && modes.indexOf(cell.mode) === -1) modes.push(cell.mode);
        if (cell.doubleFeed) twice = true;
      });
    });
    clear(els.legend);
    var items = modes.map(function (m) { return [words.modeTag(m), words.modeLegend(m)]; });
    if (twice) items.push(["2×", words.doubleLegend]);
    items.forEach(function (it) {
      var span = h("span", "iem-legend-item");
      span.appendChild(h("span", "iem-tag", it[0]));
      span.appendChild(document.createTextNode(" " + it[1]));
      els.legend.appendChild(span);
    });
    els.legend.hidden = !items.length;
  }

  // The grid is one tab stop (roving tabindex) with arrow-key travel, and a rebuild puts focus back on the cell that had
  // it: every write repaints the grid, which would otherwise drop a keyboard user at the top of the page.
  function cellKeys() { return els.body.querySelectorAll(".iem-cell-key"); }
  function isCellKey(e) { return !!e && e.classList && e.classList.contains("iem-cell-key"); }
  function findCellKey(pos) {
    var found = null;
    Array.prototype.forEach.call(cellKeys(), function (b) {
      if (b.getAttribute("data-row") === pos.row && b.getAttribute("data-mix") === pos.mix) found = b;
    });
    return found;
  }
  function setTabStop(btn) {
    Array.prototype.forEach.call(cellKeys(), function (b) { b.tabIndex = b === btn ? 0 : -1; });
  }
  function restoreCellFocus() {
    var keys = cellKeys();
    if (!keys.length) return;
    var target = ui.focusCell ? findCellKey(ui.focusCell) : null;
    setTabStop(target || keys[0]);
    var head = els.head.getBoundingClientRect().height; // keep a focused cell clear of the sticky headers
    els.scroll.style.scrollPaddingTop = head + "px";
    els.scroll.style.scrollPaddingLeft = els.body.querySelector("th") ? els.body.querySelector("th").getBoundingClientRect().width + "px" : "0";
    if (target && !ui.busy && document.activeElement !== target) target.focus({ preventScroll: true });
  }
  els.body.addEventListener("focusin", function (e) {
    if (!isCellKey(e.target)) return;
    ui.focusCell = { row: e.target.getAttribute("data-row"), mix: e.target.getAttribute("data-mix") };
    setTabStop(e.target);
  });
  els.body.addEventListener("focusout", function (e) {
    // Focus going to something else ends the memory; the grid being rebuilt under it (no destination) does not.
    if (e.relatedTarget && !isCellKey(e.relatedTarget)) ui.focusCell = null;
  });
  els.body.addEventListener("keydown", function (e) {
    if (!isCellKey(e.target) || e.altKey || e.metaKey) return;
    var td = e.target.closest("td"), tr = td.parentNode, rows = els.body.rows;
    var to = core.gridMove(e.key, tr.sectionRowIndex, td.cellIndex - 1, rows.length, tr.cells.length - 1, e.ctrlKey);
    if (!to) return;
    e.preventDefault();
    var next = rows[to[0]].cells[to[1] + 1].querySelector(".iem-cell-key");
    if (next && !next.disabled) next.focus();
  });

  // The crosshair: the cell under the pointer (or holding focus) washes its row and column, headers included. Only classes
  // change, so the grid is never rebuilt by a hover; a repaint puts the wash back from `ui.hl`.
  function paintCrosshair() {
    Array.prototype.forEach.call(els.scroll.querySelectorAll(".is-hl, .is-hl-head"), function (e) { e.classList.remove("is-hl", "is-hl-head"); });
    var at = ui.hl;
    if (!at || !els.body.rows[at.row]) return;
    var tr = els.body.rows[at.row];
    Array.prototype.forEach.call(tr.cells, function (c, i) { if (i) c.classList.add("is-hl"); });
    tr.cells[0].classList.add("is-hl-head");
    Array.prototype.forEach.call(els.body.rows, function (r) { if (r.cells[at.col]) r.cells[at.col].classList.add("is-hl"); });
    Array.prototype.forEach.call(els.head.rows, function (r) { if (r.cells[at.col]) r.cells[at.col].classList.add("is-hl-head"); });
  }
  function crosshairAt(target) {
    var td = target && target.closest ? target.closest("td") : null;
    var next = td && td.parentNode.parentNode === els.body ? { row: td.parentNode.sectionRowIndex, col: td.cellIndex } : null;
    if (!next && !ui.hl) return;
    if (next && ui.hl && next.row === ui.hl.row && next.col === ui.hl.col) return;
    ui.hl = next;
    paintCrosshair();
  }
  els.body.addEventListener("mouseover", function (e) { crosshairAt(e.target); });
  els.body.addEventListener("mouseleave", function () { if (!els.body.contains(document.activeElement)) crosshairAt(null); });
  els.body.addEventListener("focusin", function (e) { crosshairAt(e.target); });
  els.body.addEventListener("focusout", function () { if (!els.body.matches(":hover")) crosshairAt(null); });

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
    els.filter.hidden = els.scroll.hidden; // no grid, nothing to filter

    // Emptying the grid collapses its scroll box and the browser resets the scroll to 0, so keep where it was and put it back.
    var keep = { left: els.scroll.scrollLeft, top: els.scroll.scrollTop, page: window.pageYOffset || 0 };
    clear(els.head);
    clear(els.body);
    var tr = h("tr");
    var corner = h("th", "iem-corner", words.ui("tracks"));
    corner.scope = "col";
    tr.appendChild(corner);
    matrix.columns.forEach(function (col, i) { tr.appendChild(headerCell(col, i === matrix.columns.length - 1)); });
    els.head.appendChild(tr);
    if (showOutputs()) {
      var out = h("tr", "iem-out-row");
      var oc = h("th", "iem-corner", words.ui("outputsRow"));
      oc.scope = "col";
      out.appendChild(oc);
      matrix.columns.forEach(function (col) { out.appendChild(outputCell(col)); });
      els.head.appendChild(out);
    }
    els.head.style.setProperty("--iem-head1", tr.offsetHeight + "px"); // the Outputs row sticks right under the names

    matrix.rows.forEach(function (row) {
      var r = h("tr", "iem-row" + (row.isFolder ? " is-folder" : ""));
      var th = h("th");
      th.scope = "row";
      if (row.tint) { th.classList.add("is-tinted"); th.style.setProperty("--c", row.tint); }
      var name = h("span", "iem-row-name", row.name);
      name.style.paddingLeft = (0.75 + row.depth * 1.25) + "rem";
      var head = h("div", "iem-row-head");
      head.appendChild(name);
      th.appendChild(head);
      r.appendChild(th);
      row.cells.forEach(function (cell, i) { r.appendChild(dataCell(row, matrix.columns[i], cell)); });
      els.body.appendChild(r);
    });

    paintLegend(matrix);
    fitScroll();
    els.scroll.scrollLeft = keep.left;
    els.scroll.scrollTop = keep.top;
    if ((window.pageYOffset || 0) !== keep.page) window.scrollTo(0, keep.page);
    restoreCellFocus();
    paintCrosshair();
    if (ui.focusMore) {
      var wanted = ui.focusMore;
      ui.focusMore = null;
      Array.prototype.forEach.call(els.head.querySelectorAll("[data-more]"), function (b) { if (b.getAttribute("data-more") === wanted) b.focus(); });
    }
    if (ui.renaming && (ui.renaming.focus || hadFocus)) {
      ui.renaming.focus = false;
      var box = $("iem-rename-input");
      if (box) { box.focus(); box.setSelectionRange(box.value.length, box.value.length); }
    }
  }

  // The More menu closes on Escape (focus goes back to its key) and on a click anywhere outside it.
  document.addEventListener("keydown", function (e) {
    if (e.key !== "Escape" || !ui.more) return;
    ui.focusMore = ui.more; ui.more = null; render();
  });
  document.addEventListener("click", function (e) {
    if (!ui.more || !e.target.closest || e.target.closest(".iem-more-menu") || e.target.closest("[data-more]")) return;
    ui.more = null; render();
  });

  els.filter.addEventListener("input", render);
  setInterval(function () { if (!document.hidden) readState(); }, REFRESH_MS);
  document.addEventListener("visibilitychange", function () { if (!document.hidden) readState(); });

  updateControls();
  applyPhase();
  poller.start();
})();
