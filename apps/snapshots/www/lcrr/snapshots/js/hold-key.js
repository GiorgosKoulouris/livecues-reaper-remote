// Snapshots: the one press-and-hold key behaviour (Overwrite, Delete and Restore), over core.createPress and the
// page's gate. A plain tap must never act, so there is no click handler. A release is also caught on the document, so a
// hold ends even if the key was replaced. `opts`: { gate, createHold, doc, isBlocked, onComplete }.
(function (root, factory) {
  var api = factory(typeof module === "object" && module.exports ? require("./core.js") : root.LCRR.snapshots.core);
  if (typeof module === "object" && module.exports) module.exports = api;
  else { var L = root.LCRR = root.LCRR || {}; (L.snapshots = L.snapshots || {}).holdKey = api; }
})(this, function (core) {
  "use strict";
  var HOLD_MS = 1000;
  var DOC_RELEASE = ["pointerup", "pointercancel"];

  function holdKey(btn, opts) {
    var doc = opts.doc;
    var press = core.createPress({
      holdMs: HOLD_MS, createHold: opts.createHold, gate: opts.gate,
      onComplete: function () { btn.classList.remove("holding"); stopDocument(); opts.onComplete(); }
    });
    function stopDocument() { DOC_RELEASE.forEach(function (n) { doc.removeEventListener(n, release); }); }
    function release() { press.up(); btn.classList.remove("holding"); stopDocument(); }
    function start() {
      if (btn.disabled || (opts.isBlocked && opts.isBlocked()) || press.isDown()) return;
      btn.classList.add("holding");
      DOC_RELEASE.forEach(function (n) { doc.addEventListener(n, release); });
      press.down();
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

  return { holdKey: holdKey, HOLD_MS: HOLD_MS };
});
