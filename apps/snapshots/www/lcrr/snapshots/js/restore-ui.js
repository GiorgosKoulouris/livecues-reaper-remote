// Snapshots: the restore's DOM wiring. The ticks (reset at each page load), the press-and-hold Restore key on a row and
// the result note, which stays until the next write. Logic is restore.js, sentences are words.js; text is set with
// textContent only.
(function () {
  "use strict";
  var S = LCRR.shared, N = LCRR.snapshots, restore = N.restore, words = N.words;
  var HOLD_MS = 1000;
  var RELEASE = ["pointerup", "pointercancel"];

  var ticks = restore.defaults();
  var ctx = null; // { client, showMessage } from snapshots.js
  var busy = false;
  var keys = [];

  function $(id) { return document.getElementById(id); }

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

  // A press-and-hold key (LCRR.shared.hold). No click handler on purpose: a plain tap must never act.
  function holdKey(btn, onComplete) {
    var down = false;
    function finish() {
      if (!down) return;
      down = false;
      RELEASE.forEach(function (n) { document.removeEventListener(n, release); });
      btn.classList.remove("holding");
    }
    var hold = S.hold.createHold({ holdMs: HOLD_MS, onCancel: finish, onComplete: function () { finish(); onComplete(); } });
    function release() { hold.cancel(); finish(); }
    function start() {
      if (btn.disabled || down) return;
      down = true;
      btn.classList.add("holding");
      RELEASE.forEach(function (n) { document.addEventListener(n, release); });
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
  }

  // Add the Restore key to a row; rows are rebuilt with the list, so the old keys are dropped first (resetKeys).
  function addKey(parent, snapshot) {
    var btn = document.createElement("button");
    btn.type = "button";
    btn.className = "snapshots-key snapshots-hold";
    btn.textContent = words.ui("restore");
    btn.disabled = !restore.field(ticks) || busy;
    holdKey(btn, function () { doRestore(snapshot.name); });
    keys.push(btn);
    parent.appendChild(btn);
  }

  function resetKeys() { keys = []; }

  function init(given) {
    ctx = given;
    buildTicks($("snapshots-ticks"));
    $("snapshots-ticks-note").textContent = words.ui("tickNote");
  }

  N.restoreUi = { init: init, addKey: addKey, resetKeys: resetKeys };
})();
