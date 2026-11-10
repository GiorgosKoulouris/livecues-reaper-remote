// Snapshots: UI wiring. Talks to the Lua bridge through client.js; the logic is core.js and every sentence comes from
// words.js. DOM is built with textContent only: project names are user data.
(function () {
  "use strict";
  var S = LCRR.shared, N = LCRR.snapshots, wire = N.wire, core = N.core, words = N.words, restoreUi = N.restoreUi, holdKey = N.holdKey;
  var REFRESH_MS = 3000; // while connected, re-read the project this often (another project may become the active one)

  var conn = S.guard.createConnection({ failuresToOffline: 2, settleMs: 1000 });
  var beat = wire.createHeartbeat({ staleMs: 2500 });
  var poller = S.poll.createPoller({ intervalMs: 500 });
  poller.addCommand(wire.getCommand("heartbeat"));

  var io = S.bridgeClient.createBrowserIo();
  var client = N.client.createClient({ fetchText: io.fetchText, newId: io.newId });

  function $(id) { return document.getElementById(id); }
  var els = {
    chip: $("snapshots-state"), chipText: $("snapshots-state-text"), banner: $("snapshots-banner"),
    message: $("snapshots-message"), projectName: $("snapshots-project-name"), controls: $("snapshots-controls"),
    form: $("snapshots-form"), name: $("snapshots-name"), save: $("snapshots-save"), empty: $("snapshots-empty"),
    list: $("snapshots-list")
  };

  // The page's fixed labels come from words.js too, so the HTML holds no sentences.
  $("snapshots-heading").textContent = words.ui("title");
  $("snapshots-ticks-legend").textContent = words.ui("restore");
  $("snapshots-name-label").textContent = words.ui("name");
  els.save.textContent = words.ui("save");
  els.chipText.textContent = words.chip("connecting");

  var ui = { phase: "connecting", everLive: false, reading: false, projectPath: null, list: null, listing: false, busy: false };

  function showMessage(text) {
    els.message.textContent = text || "";
    els.message.hidden = !text;
  }

  function applyPhase() {
    var was = ui.phase;
    var next = core.connectionPhase(conn.isOffline(), ui.everLive, beat.state());
    ui.phase = next;
    els.chip.setAttribute("data-state", next);
    document.body.setAttribute("data-state", next);
    els.chipText.textContent = words.chip(next);
    els.banner.textContent = words.banner(next);
    els.banner.hidden = !words.banner(next);
    els.controls.hidden = !core.canUse(next); // no bridge, no controls
    if (next === "ready" && was !== "ready") { readState(); readList(); }
  }

  poller.subscribe(function (e) {
    var live = e.ok && !!S.reaper.parseTransport(e.text);
    conn.update(live);
    if (live) { ui.everLive = true; beat.update(wire.parseExtState(e.text, "heartbeat")); }
    applyPhase();
  });

  function readState() {
    if (ui.phase !== "ready" || ui.reading) return;
    ui.reading = true;
    client.state().then(function (reply) {
      ui.reading = false;
      var state = core.readState(reply);
      if (!state) { showMessage(words.error(reply && reply.error)); return; }
      showMessage("");
      ui.projectPath = state.project.path;
      els.projectName.textContent = words.projectName(state.project);
      els.projectName.title = els.projectName.textContent;
    }, function (err) {
      ui.reading = false;
      showMessage(words.error(err));
    });
  }

  function savedText(seconds) {
    var d = new Date(seconds * 1000);
    return isNaN(d.getTime()) ? "" : d.toLocaleDateString(undefined, { month: "short", day: "numeric" }) + " " +
      d.toLocaleTimeString(undefined, { hour: "2-digit", minute: "2-digit" });
  }

  function h(tag, cls, text) {
    var el = document.createElement(tag);
    if (cls) el.className = cls;
    if (text !== undefined) el.textContent = text;
    return el;
  }

  // One request at a time, page-wide: Save, Overwrite, Delete and Restore share this flag. While it is set the Save key
  // and every Restore key are disabled, and Overwrite and Delete ignore a press (isBlocked).
  function isBusy() { return ui.busy; }
  function setBusy(busy) {
    ui.busy = busy;
    els.save.disabled = busy;
    restoreUi.syncKeys();
  }

  // Overwrite and Delete: a hold key (hold-key.js) with the legend, sending once the hold completes.
  function holdButton(kind, name, send) {
    return holdKey.build(kind, name, { gate: gate, isBlocked: isBusy, onComplete: function () { write(send); } });
  }

  // One write at a time; the message of a refusal stays until the next attempt, and the list is read again either way.
  function write(send) {
    if (ui.phase !== "ready" || ui.busy) return;
    setBusy(true);
    showMessage("");
    send().then(function (reply) {
      if (core.clearsNote(reply)) restoreUi.clearNote();
      else showMessage(words.error(reply && reply.error));
    }, function (err) { showMessage(words.error(err)); }).then(function () {
      setBusy(false);
      ui.list = null; // a refused write (not_found) may still have changed what the list should show
      readList();
    });
  }

  // Rebuilt only when the list changed, so a steady 3 s read never touches the rows; never while a hold is down.
  var gate = core.createGate(function () { if (ui.list) renderList(ui.list); });
  function renderList(list) {
    els.empty.textContent = words.ui("empty");
    els.empty.hidden = list.length > 0;
    els.list.textContent = "";
    restoreUi.resetKeys();
    list.forEach(function (s) {
      var li = h("li", "snapshots-row");
      li.appendChild(h("span", "snapshots-row-name", s.name));
      li.appendChild(h("span", "snapshots-row-meta", words.counts(s, savedText(s.saved))));
      var marks = words.marks(s);
      if (marks.length) {
        var tags = h("div", "snapshots-row-marks");
        marks.forEach(function (m) { tags.appendChild(h("span", "snapshots-mark snapshots-mark-" + m.key, m.text)); });
        li.appendChild(tags);
      }
      var keys = h("div", "snapshots-row-keys");
      keys.appendChild(holdButton("overwrite", s.name, function () { return client.overwrite(s.name); }));
      keys.appendChild(holdButton("delete", s.name, function () { return client.remove(s.name); }));
      restoreUi.addKey(keys, s);
      li.appendChild(keys);
      els.list.appendChild(li);
    });
  }

  function readList() {
    if (ui.phase !== "ready" || ui.listing) return;
    ui.listing = true;
    client.snapshots().then(function (reply) {
      ui.listing = false;
      var list = core.readList(reply);
      if (!list) { if (reply && reply.status === "refused") showMessage(words.error(reply.error)); return; }
      if (ui.list && core.sameList(ui.list, list)) return;
      ui.list = list;
      gate.request();
    }, function () { ui.listing = false; });
  }

  // The message of a refused save stays until the next attempt.
  els.form.addEventListener("submit", function (ev) {
    ev.preventDefault();
    if (ui.phase !== "ready" || ui.busy) return;
    var names = (ui.list || []).map(function (s) { return s.name; });
    var check = core.checkName(els.name.value, names, N.client.nameFits);
    if (!check.name) { showMessage(words.error(check)); return; }
    setBusy(true);
    showMessage("");
    client.save(check.name).then(function (reply) {
      if (core.clearsNote(reply)) { els.name.value = ""; restoreUi.clearNote(); }
      else showMessage(words.error(reply && reply.error));
    }, function (err) { showMessage(words.error(err)); }).then(function () {
      setBusy(false);
      readList();
    });
  });

  restoreUi.init({ client: client, showMessage: showMessage, gate: gate, isBusy: isBusy, setBusy: setBusy });

  setInterval(function () { if (!document.hidden) { readState(); readList(); } }, REFRESH_MS);
  poller.start();
})();
