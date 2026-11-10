// Snapshots: UI wiring. Talks to the Lua bridge through client.js; the logic is core.js and every sentence comes from
// words.js. DOM is built with textContent only: project names are user data.
(function () {
  "use strict";
  var S = LCRR.shared, N = LCRR.snapshots, wire = N.wire, core = N.core, words = N.words;
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

  // Rebuilt only when the list changed, so a steady 3 s read never touches the rows.
  function renderList(list) {
    els.empty.textContent = words.ui("empty");
    els.empty.hidden = list.length > 0;
    els.list.textContent = "";
    list.forEach(function (s) {
      var li = h("li", "snapshots-row");
      li.appendChild(h("span", "snapshots-row-name", s.name));
      li.appendChild(h("span", "snapshots-row-meta", words.counts(s, savedText(s.saved))));
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
      renderList(list);
    }, function () { ui.listing = false; });
  }

  // The message of a refused save stays until the next attempt.
  els.form.addEventListener("submit", function (ev) {
    ev.preventDefault();
    if (ui.phase !== "ready" || ui.busy) return;
    var names = (ui.list || []).map(function (s) { return s.name; });
    var check = core.checkName(els.name.value, names, function (name) {
      return !wire.tooLong(wire.setRequestCommand(wire.buildRequest("xxxxxxxxxxxx-xxxx", { cmd: "snapshot_save", name: name })));
    });
    if (!check.name) { showMessage(words.error(check)); return; }
    ui.busy = true;
    els.save.disabled = true;
    showMessage("");
    client.save(check.name).then(function (reply) {
      if (reply && reply.status === "ok") els.name.value = "";
      else showMessage(words.error(reply && reply.error));
    }, function (err) { showMessage(words.error(err)); }).then(function () {
      ui.busy = false;
      els.save.disabled = false;
      readList();
    });
  });

  setInterval(function () { if (!document.hidden) { readState(); readList(); } }, REFRESH_MS);
  poller.start();
})();
