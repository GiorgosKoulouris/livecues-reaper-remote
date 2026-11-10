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
    message: $("snapshots-message"), projectName: $("snapshots-project-name"), controls: $("snapshots-controls")
  };

  var ui = { phase: "connecting", everLive: false, reading: false, projectPath: null };

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
    if (next === "ready" && was !== "ready") readState();
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

  setInterval(function () { if (!document.hidden) readState(); }, REFRESH_MS);
  poller.start();
})();
