// Snapshots: the restore's DOM wiring. The ticks (reset at each page load), the press-and-hold Restore key on a row and
// the result note, which stays until the next write (a restore replaces it; a successful Save, Overwrite or Delete clears it). Logic is restore.js, sentences are words.js; text is set with
// textContent only.
(function () {
  "use strict";
  var S = LCRR.shared, N = LCRR.snapshots, restore = N.restore, words = N.words, holdKey = N.holdKey.holdKey;

  var ticks = restore.defaults();
  var ctx = null; // { client, showMessage, gate } from snapshots.js
  var busy = false;
  var keys = [];

  function $(id) { return document.getElementById(id); }

  function span(cls, text) {
    var el = document.createElement("span");
    el.className = cls;
    el.textContent = text;
    return el;
  }

  function setNote(text) {
    var el = $("snapshots-note");
    el.textContent = text || "";
    el.hidden = !text;
  }

  function syncKeys() {
    var none = !restore.field(ticks);
    keys.forEach(function (btn) { btn.disabled = none || busy; });
  }

  // The tick boxes, built once.
  function buildTicks(box) {
    restore.TICKS.forEach(function (t) {
      var label = document.createElement("label");
      label.className = "snapshots-tick";
      var input = document.createElement("input");
      input.type = "checkbox";
      input.checked = ticks[t.key];
      input.addEventListener("change", function () { ticks[t.key] = input.checked; syncKeys(); });
      var span = document.createElement("span");
      span.textContent = words.tick(t.key);
      label.appendChild(input);
      label.appendChild(span);
      box.appendChild(label);
    });
  }

  function doRestore(name) {
    if (busy) return;
    busy = true;
    syncKeys();
    ctx.showMessage("");
    ctx.client.restore(name, restore.field(ticks)).then(function (reply) {
      var result = restore.readResult(reply);
      if (result) setNote(words.restoreNote(result));
      else ctx.showMessage(words.error(reply && reply.error));
    }, function (err) { ctx.showMessage(words.error(err)); }).then(function () {
      busy = false;
      syncKeys();
    });
  }

  // Add the Restore key to a row; rows are rebuilt with the list, so the old keys are dropped first (resetKeys).
  function addKey(parent, snapshot) {
    var btn = document.createElement("button");
    btn.type = "button";
    btn.className = "snapshots-key snapshots-hold";
    btn.appendChild(span("snapshots-hold-text", words.ui("restore")));
    btn.appendChild(span("snapshots-hold-legend", words.ui("holdLegend")));
    btn.title = words.holdLabel("restore", snapshot.name);
    btn.setAttribute("aria-label", btn.title);
    btn.disabled = !restore.field(ticks) || busy;
    holdKey(btn, { gate: ctx.gate, createHold: S.hold.createHold, doc: document, onComplete: function () { doRestore(snapshot.name); } });
    keys.push(btn);
    parent.appendChild(btn);
  }

  function resetKeys() { keys = []; }

  function init(given) {
    ctx = given;
    buildTicks($("snapshots-ticks"));
    $("snapshots-ticks-note").textContent = words.ui("tickNote");
  }

  N.restoreUi = { init: init, addKey: addKey, resetKeys: resetKeys, clearNote: setNote };
})();
