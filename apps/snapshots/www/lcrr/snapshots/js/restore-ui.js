// Snapshots: the restore's DOM wiring. The ticks (reset at each page load), the press-and-hold Restore key on a row and
// the result note, which stays until the next write (a restore replaces it; a successful Save, Overwrite or Delete
// clears it). Logic is restore.js, sentences are words.js; text is set with textContent only.
(function () {
  "use strict";
  var N = LCRR.snapshots, restore = N.restore, words = N.words, holdKey = N.holdKey;

  var ticks = restore.defaults();
  var ctx = null; // { client, showMessage, gate, isBusy, setBusy } from snapshots.js (one request at a time, page-wide)
  var keys = [];

  function $(id) { return document.getElementById(id); }

  function setNote(text) {
    var el = $("snapshots-note");
    el.textContent = text || "";
    el.hidden = !text;
  }

  function syncKeys() {
    var none = !restore.field(ticks);
    keys.forEach(function (btn) { btn.disabled = none || ctx.isBusy(); });
    // A dimmed Restore key says why, in the line beside the ticks that cause it.
    var note = $("snapshots-ticks-note");
    note.textContent = none ? words.error({ code: "no_ticks" }) : words.ui("tickNote");
    note.classList.toggle("is-warn", none);
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
    if (ctx.isBusy()) return;
    ctx.setBusy(true);
    ctx.showMessage("");
    ctx.client.restore(name, restore.field(ticks)).then(function (reply) {
      var result = restore.readResult(reply);
      if (result) setNote(words.restoreNote(result));
      else ctx.showMessage(words.error(reply && reply.error));
    }, function (err) { ctx.showMessage(words.error(err)); }).then(function () {
      ctx.setBusy(false);
    });
  }

  // Add the Restore key to a row; rows are rebuilt with the list, so the old keys are dropped first (resetKeys).
  function addKey(parent, snapshot) {
    var btn = holdKey.build("restore", snapshot.name, {
      gate: ctx.gate, isBlocked: ctx.isBusy, onComplete: function () { doRestore(snapshot.name); }
    });
    btn.disabled = !restore.field(ticks) || ctx.isBusy();
    keys.push(btn);
    parent.appendChild(btn);
  }

  function resetKeys() { keys = []; }

  function init(given) {
    ctx = given;
    buildTicks($("snapshots-ticks"));
    syncKeys();
  }

  N.restoreUi = { init: init, addKey: addKey, resetKeys: resetKeys, clearNote: function () { setNote(""); }, syncKeys: syncKeys };
})();
