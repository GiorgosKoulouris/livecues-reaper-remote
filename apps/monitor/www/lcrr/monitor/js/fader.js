// Monitor: one level fader (DOM and Pointer Events). Drag and write rules are in core.js (createFaderDrag).
// It knows nothing about rows: it writes to the target that getTarget() returns ({ track, y, source }), so the
// source rows and the overall fader (send index 0) use it unchanged.
(function () {
  "use strict";
  var L = window.LCRR = window.LCRR || {}, M = L.monitor = L.monitor || {}, core = M.core;
  var THUMB_PX = 44; // touch target (DESIGN.md); the same number is in monitor.css

  // opts: getTarget() -> { track, y, source } or null; check(target) -> bool (the stale check against the latest
  // poll); send(cmd) -> Promise; onLevel(value) called as the level changes during a drag; label for assistive tech.
  function create(opts) {
    var el = document.createElement("div"), track = document.createElement("div"), mark = document.createElement("span"), thumb = document.createElement("div");
    el.className = "monitor-fader";
    track.className = "monitor-fader-track";
    mark.className = "monitor-fader-mark";
    thumb.className = "monitor-fader-thumb"; // the only element that takes touches (touch-action: none)
    thumb.setAttribute("aria-label", opts.label || "Level");
    mark.style.setProperty("--pos", String(core.faderPos(1)));
    el.appendChild(track); el.appendChild(mark); el.appendChild(thumb);

    var drag = core.createFaderDrag({
      now: function () { return Date.now(); },
      setTimer: function (fn, ms) { return setTimeout(fn, ms); },
      clearTimer: function (h) { clearTimeout(h); },
      send: opts.send,
      check: opts.check,
      gateMs: 50, slopPx: 3
    });
    var level = null, pid = null, startX = 0, dragTarget = null;

    function show() {
      thumb.style.setProperty("--pos", String(core.faderPos(level)));
      thumb.classList.toggle("over", level > core.CAP);
    }
    function finish(how) {
      if (pid === null) return;
      var id = pid;
      pid = null;
      thumb.classList.remove("dragging");
      drag[how]();
      try { thumb.releasePointerCapture(id); } catch (e) { /* already released */ }
    }

    thumb.addEventListener("pointerdown", function (ev) {
      if (pid !== null || level === null) return;
      if (ev.pointerType === "mouse" && ev.button !== 0) return;
      var t = opts.getTarget();
      if (!t || !opts.check(t)) return;
      var travel = el.clientWidth - THUMB_PX;
      if (travel < 1 || !drag.begin(t, level, travel)) return;
      pid = ev.pointerId; startX = ev.clientX; dragTarget = t;
      thumb.classList.add("dragging");
      try { thumb.setPointerCapture(pid); } catch (e) { /* the drag still works while the pointer is over the thumb */ }
      ev.preventDefault();
    });
    thumb.addEventListener("pointermove", function (ev) {
      if (ev.pointerId !== pid) return;
      // The row's source or the mix moved under the drag: end it with no write (never paint or write on another row).
      if (!opts.check(dragTarget)) return finish("cancel");
      var r = drag.move(ev.clientX - startX);
      if (!r) return;
      level = r.value;
      show();
      if (opts.onLevel) opts.onLevel(level);
    });
    thumb.addEventListener("pointerup", function (ev) { if (ev.pointerId === pid) finish("end"); });
    // The browser took the pointer: end the move as a release (the thumb shows the last level written).
    thumb.addEventListener("pointercancel", function (ev) { if (ev.pointerId === pid) finish("end"); });
    thumb.addEventListener("lostpointercapture", function (ev) { if (ev.pointerId === pid) finish("cancel"); });
    // A tap on the track does nothing (no listener); the thumb context menu (long press) must not start a drag.
    thumb.addEventListener("contextmenu", function (ev) { ev.preventDefault(); });

    return {
      el: el,
      // Poll data: ignored while a drag is on, so a reply never moves the thumb under the finger.
      setValue: function (vol) {
        if (drag.active() || vol === level) return;
        level = vol;
        show();
      },
      // The drag ends with no final write (mix closed, offline, row gone).
      cancel: function () { if (pid !== null) finish("cancel"); else drag.cancel(); },
      active: drag.active,
      readToken: drag.readToken,
      canApply: drag.canApply
    };
  }

  M.fader = { create: create };
})();
