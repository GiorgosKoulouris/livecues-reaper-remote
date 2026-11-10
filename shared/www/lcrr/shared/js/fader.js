// LCRR shared: one level fader (DOM and Pointer Events). Drag and write rules are in fader-core.js (createFaderDrag).
// It knows nothing about rows: it writes to the target that getTarget() returns ({ track, y, source }), so the
// source rows and the master fader (send index 0) use it unchanged. The name and value sit inside the fader.
(function (root, factory) {
  var api = factory(root.LCRR && root.LCRR.shared && root.LCRR.shared.faderCore || (typeof require === "function" ? require("./fader-core.js") : null));
  if (typeof module === "object" && module.exports) module.exports = api;
  else { var L = root.LCRR = root.LCRR || {}; (L.shared = L.shared || {}).fader = api; }
})(this, function (core) {
  "use strict";
  var THUMB_PX = 44; // touch target (DESIGN.md); the same number is in the app's CSS

  function part(tag, cls) { var e = document.createElement(tag); e.className = cls; return e; }

  // One copy of the name and value text.
  function textLayer(prefix, cls) {
    var layer = part("div", cls), name = part("span", prefix + "-fader-name"), value = part("span", prefix + "-fader-value");
    layer.appendChild(name); layer.appendChild(value);
    return { el: layer, name: name, value: value };
  }

  // The pointer wiring of one drag, for any control built on createFaderDrag. opts: el (takes class "dragging"), thumb
  // (the only element that takes touches), thumbPx, drag (the controller), getTarget() -> target or null, check(target),
  // current() -> the value on screen or null before one is known, onMove({ pos, value }, target) as the value changes.
  // Returns { dragging(), cancel() }; cancel ends the drag with no final write.
  function bindThumb(opts) {
    var el = opts.el, thumb = opts.thumb, drag = opts.drag;
    var pid = null, startX = 0, dragTarget = null;

    function finish(how) {
      if (pid === null) return;
      var id = pid;
      pid = null;
      el.classList.remove("dragging");
      drag[how]();
      try { thumb.releasePointerCapture(id); } catch (e) { /* already released */ }
    }

    thumb.addEventListener("pointerdown", function (ev) {
      var value = opts.current();
      if (pid !== null || value === null) return;
      if (ev.pointerType === "mouse" && ev.button !== 0) return;
      var t = opts.getTarget();
      if (!t || !opts.check(t)) return;
      var travel = el.clientWidth - opts.thumbPx;
      if (travel < 1 || !drag.begin(t, value, travel)) return;
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
      if (r) opts.onMove(r, dragTarget);
    });
    thumb.addEventListener("pointerup", function (ev) { if (ev.pointerId === pid) finish("end"); });
    // The browser took the pointer: end the move as a release (the thumb shows the last level written).
    thumb.addEventListener("pointercancel", function (ev) { if (ev.pointerId === pid) finish("end"); });
    thumb.addEventListener("lostpointercapture", function (ev) { if (ev.pointerId === pid) finish("cancel"); });
    // A tap on the track does nothing (no listener); the thumb context menu (long press) must not start a drag.
    thumb.addEventListener("contextmenu", function (ev) { ev.preventDefault(); });

    return {
      dragging: function () { return pid !== null; },
      cancel: function () { if (pid !== null) finish("cancel"); else drag.cancel(); }
    };
  }

  // opts: prefix (CSS class prefix; parts are <prefix>-fader, -fader-fill, ...), getTarget() -> { track, y, source } or null; check(target) -> bool (the stale check against the latest
  // poll); send(cmd) -> Promise; onLevel(value) called as the level changes during a drag; label for assistive tech.
  function create(opts) {
    var prefix = opts.prefix;
    var el = part("div", prefix + "-fader"), fill = part("div", prefix + "-fader-fill"), mark = part("span", prefix + "-fader-mark"), handle = part("div", prefix + "-fader-handle");
    var thumb = part("div", prefix + "-fader-thumb"); // the invisible 44px touch area, the only element that takes touches (touch-action: none)
    // The text twice: the second copy is clipped to the handle, so letters stay readable as the handle crosses them.
    var text = textLayer(prefix, prefix + "-fader-text"), onHandle = textLayer(prefix, prefix + "-fader-text on-handle");
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
    var level = null;
    var shownName = null, shownValue = null, shownColor = null;

    function show() {
      el.style.setProperty("--pos", String(core.faderPos(level)));
      el.classList.toggle("over", level > core.CAP);
    }
    var pointer = bindThumb({
      el: el, thumb: thumb, thumbPx: THUMB_PX, drag: drag, getTarget: opts.getTarget, check: opts.check,
      current: function () { return level; },
      onMove: function (r) {
        level = r.value;
        show();
        if (opts.onLevel) opts.onLevel(level);
      }
    });

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
      cancel: pointer.cancel,
      // The level on screen (the last level written while a wheel burst is on), or null before one is known.
      level: function () { return level; },
      // A wheel step to `value` (linear): the same write path as a drag (stale check, one in flight, one `e` after the
      // burst). False when nothing was written: a drag is on, the check fails, or no level is known yet.
      nudge: function (value) {
        if (pointer.dragging() || level === null) return false;
        var t = opts.getTarget();
        if (!t || !drag.nudge(t, value)) return false;
        level = value;
        show();
        if (opts.onLevel) opts.onLevel(level);
        return true;
      },
      // Ends a wheel burst now; true while its `e` is still to go out (createFaderDrag.finishWheel).
      finishWheel: drag.finishWheel,
      active: drag.active,
      readToken: drag.readToken,
      canApply: drag.canApply
    };
  }

  return { create: create, bindThumb: bindThumb };
});
