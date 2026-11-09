// Monitor: one level fader (DOM and Pointer Events). Drag and write rules are in core.js (createFaderDrag).
// It knows nothing about rows: it writes to the target that getTarget() returns ({ track, y, source }), so the
// source rows and the master fader (send index 0) use it unchanged. The name and value sit inside the fader.
(function () {
  "use strict";
  var L = window.LCRR = window.LCRR || {}, M = L.monitor = L.monitor || {}, core = M.core;
  var THUMB_PX = 44; // touch target (DESIGN.md); the same number is in monitor.css

  function part(tag, cls) { var e = document.createElement(tag); e.className = cls; return e; }

  // One copy of the name and value text.
  function textLayer(cls) {
    var layer = part("div", cls), name = part("span", "monitor-fader-name"), value = part("span", "monitor-fader-value");
    layer.appendChild(name); layer.appendChild(value);
    return { el: layer, name: name, value: value };
  }

  // opts: getTarget() -> { track, y, source } or null; check(target) -> bool (the stale check against the latest
  // poll); send(cmd) -> Promise; onLevel(value) called as the level changes during a drag; label for assistive tech.
  function create(opts) {
    var el = part("div", "monitor-fader"), fill = part("div", "monitor-fader-fill"), mark = part("span", "monitor-fader-mark"), handle = part("div", "monitor-fader-handle");
    var thumb = part("div", "monitor-fader-thumb"); // the invisible 44px touch area, the only element that takes touches (touch-action: none)
    // The text twice: the second copy is clipped to the handle, so letters stay readable as the handle crosses them.
    var text = textLayer("monitor-fader-text"), onHandle = textLayer("monitor-fader-text on-handle");
    var valueText = document.createTextNode(""), unit = part("span", "lcrr-sr");
    unit.textContent = " dB"; // the screen shows only the number; assistive tech still hears the unit
    text.value.appendChild(valueText); text.value.appendChild(unit);
    onHandle.el.setAttribute("aria-hidden", "true");
    thumb.setAttribute("aria-label", opts.label || "Level");
    mark.style.setProperty("--pos", String(core.faderPos(1)));
    [fill, mark, handle, text.el, onHandle.el, thumb].forEach(function (c) { el.appendChild(c); });

    var drag = core.createFaderDrag({
      now: function () { return Date.now(); },
      setTimer: function (fn, ms) { return setTimeout(fn, ms); },
      clearTimer: function (h) { clearTimeout(h); },
      send: opts.send,
      check: opts.check,
      gateMs: 50, slopPx: 3
    });
    var level = null, pid = null, startX = 0, dragTarget = null;
    var shownName = null, shownValue = null, shownColor = null;

    function show() {
      el.style.setProperty("--pos", String(core.faderPos(level)));
      el.classList.toggle("over", level > core.CAP);
    }
    function finish(how) {
      if (pid === null) return;
      var id = pid;
      pid = null;
      el.classList.remove("dragging");
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
      el.classList.add("dragging");
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
      setName: function (name) {
        if (name === shownName) return;
        shownName = name;
        text.name.textContent = onHandle.name.textContent = name;
      },
      // The level as text, with no unit (core.dbText), or a dash before a level is known.
      setValueText: function (value) {
        if (value === shownValue) return;
        shownValue = value;
        valueText.nodeValue = onHandle.value.textContent = value;
      },
      // The source's track colour tints the fill; none leaves it neutral.
      setColor: function (css) {
        if (css === shownColor) return;
        shownColor = css;
        if (css) el.style.setProperty("--c", css); else el.style.removeProperty("--c");
        el.classList.toggle("tinted", !!css);
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
