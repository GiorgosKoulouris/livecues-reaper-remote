// Snapshots: the one press-and-hold key behaviour (Overwrite, Delete and Restore), over core.createPress and the
// page's gate. A plain tap must never act, so there is no click handler. A release is also caught on the document, so a
// hold ends even if the key was replaced. `holdKey(btn, opts)` adds the behaviour to a button; `build(kind, name, opts)`
// makes the whole key (text, HOLD legend, label). `opts`: { gate, onComplete, isBlocked, createHold, doc }; createHold
// and doc default to the page's (LCRR.shared.hold, document) and are injected by tests.
(function (root, factory) {
  var node = typeof module === "object" && module.exports;
  var api = factory(node ? require("./core.js") : root.LCRR.snapshots.core, node ? require("./words.js") : root.LCRR.snapshots.words,
    node ? {} : { createHold: root.LCRR.shared.hold.createHold, doc: root.document });
  if (typeof module === "object" && module.exports) module.exports = api;
  else { var L = root.LCRR = root.LCRR || {}; (L.snapshots = L.snapshots || {}).holdKey = api; }
})(this, function (core, words, defaults) {
  "use strict";
  var HOLD_MS = 1000;
  var DOC_RELEASE = ["pointerup", "pointercancel"];

  function holdKey(btn, opts) {
    var doc = opts.doc || defaults.doc;
    var press = core.createPress({
      holdMs: HOLD_MS, createHold: opts.createHold || defaults.createHold, gate: opts.gate,
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

  // The key itself: `kind` is "overwrite", "delete" or "restore" (its class is snapshots-<kind>).
  function build(kind, name, opts) {
    var doc = opts.doc || defaults.doc;
    function span(cls, text) {
      var el = doc.createElement("span");
      el.className = cls;
      el.textContent = text;
      return el;
    }
    var btn = doc.createElement("button");
    btn.type = "button";
    btn.className = "snapshots-key snapshots-hold snapshots-" + kind;
    btn.appendChild(span("snapshots-hold-text", words.ui(kind)));
    btn.appendChild(span("snapshots-hold-legend", words.ui("holdLegend")));
    btn.title = words.holdLabel(kind, name);
    btn.setAttribute("aria-label", btn.title);
    return holdKey(btn, opts);
  }

  return { holdKey: holdKey, build: build, HOLD_MS: HOLD_MS };
});
