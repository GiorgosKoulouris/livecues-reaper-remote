const test = require("node:test");
const assert = require("node:assert");

// The least DOM fader.js touches.
function element() {
  const classes = new Set(), listeners = {};
  return {
    children: [], style: { setProperty() {}, removeProperty() {} }, clientWidth: 244, textContent: "", className: "",
    classList: { add: (c) => classes.add(c), remove: (c) => classes.delete(c), toggle: (c, on) => (on ? classes.add(c) : classes.delete(c)), contains: (c) => classes.has(c) },
    appendChild(c) { this.children.push(c); return c; },
    setAttribute() {},
    addEventListener(type, fn) { listeners[type] = fn; },
    setPointerCapture() {}, releasePointerCapture() {},
    fire(type, ev) { listeners[type](Object.assign({ pointerId: 1, pointerType: "touch", button: 0, clientX: 0, preventDefault() {} }, ev)); }
  };
}
global.document = { createElement: element, createTextNode: () => ({ nodeValue: "" }) };

const fader = require("../www/lcrr/shared/js/fader.js");
const T = { track: 2, y: -1, source: 5 };

function setup(overrides) {
  const h = { sent: [], levels: [], allowed: true };
  h.f = fader.create(Object.assign({
    prefix: "t", getTarget: () => T, check: () => h.allowed,
    send: (c) => { h.sent.push(c); return Promise.resolve(); },
    onLevel: (v) => h.levels.push(v)
  }, overrides));
  h.thumb = h.f.el.children[h.f.el.children.length - 1];
  return h;
}

test("level is null until a read sets it, and a nudge before that does nothing", () => {
  const h = setup();
  assert.strictEqual(h.f.level(), null);
  assert.strictEqual(h.f.nudge(0.5), false);
  assert.deepStrictEqual(h.sent, []);
  h.f.setValue(0.25);
  assert.strictEqual(h.f.level(), 0.25);
});

test("nudge writes through the fader's path, moves the level on screen and reports it", () => {
  const h = setup();
  h.f.setValue(0.25);
  assert.strictEqual(h.f.nudge(0.5), true);
  assert.strictEqual(h.f.level(), 0.5);
  assert.deepStrictEqual(h.levels, [0.5]);
  assert.deepStrictEqual(h.sent, ["SET/TRACK/2/SEND/-1/VOL/0.5"]);
  h.f.cancel();
});

test("a nudge the stale check refuses leaves the level and writes nothing", () => {
  const h = setup();
  h.f.setValue(0.25);
  h.allowed = false;
  assert.strictEqual(h.f.nudge(0.5), false);
  assert.strictEqual(h.f.level(), 0.25);
  assert.deepStrictEqual([h.sent, h.levels], [[], []]);
});

test("a nudge during a drag is refused, and the drag is left alone", () => {
  const h = setup();
  h.f.setValue(0.25);
  h.thumb.fire("pointerdown");
  assert.strictEqual(h.f.active(), true);
  assert.strictEqual(h.f.nudge(0.5), false);
  assert.strictEqual(h.f.active(), true);
  h.f.cancel();
  assert.strictEqual(h.f.active(), false);
});

// bindThumb on its own, as a control other than the level fader uses it.
function bound(start) {
  const h = { el: element(), thumb: element(), value: start, moves: [], calls: [], allowed: true, began: null };
  h.drag = {
    begin: (t, v, travel) => { h.began = [t, v, travel]; return true; },
    move: (dx) => ({ pos: 0.5, value: dx }),
    end: () => h.calls.push("end"), cancel: () => h.calls.push("cancel")
  };
  h.b = fader.bindThumb({ el: h.el, thumb: h.thumb, thumbPx: 44, drag: h.drag, getTarget: () => T, check: () => h.allowed, current: () => h.value, onMove: (r, t) => h.moves.push([r.value, t]) });
  return h;
}

test("bindThumb: press, relative move and release drive the controller", () => {
  const h = bound(0.1);
  h.thumb.fire("pointerdown", { clientX: 100 });
  assert.deepStrictEqual(h.began, [T, 0.1, 200]);
  assert.strictEqual(h.b.dragging(), true);
  assert.strictEqual(h.el.classList.contains("dragging"), true);
  h.thumb.fire("pointermove", { clientX: 130 });
  assert.deepStrictEqual(h.moves, [[30, T]]);
  h.thumb.fire("pointerup");
  assert.deepStrictEqual(h.calls, ["end"]);
  assert.strictEqual(h.b.dragging(), false);
  assert.strictEqual(h.el.classList.contains("dragging"), false);
});

test("bindThumb: no press before a value is known, on a right click, or when the check fails", () => {
  const unknown = bound(null);
  unknown.thumb.fire("pointerdown");
  assert.strictEqual(unknown.began, null);
  const right = bound(0.1);
  right.thumb.fire("pointerdown", { pointerType: "mouse", button: 2 });
  assert.strictEqual(right.began, null);
  const stale = bound(0.1);
  stale.allowed = false;
  stale.thumb.fire("pointerdown");
  assert.strictEqual(stale.began, null);
});

test("bindThumb: a target gone stale mid-drag cancels with no end, and another pointer is ignored", () => {
  const h = bound(0.1);
  h.thumb.fire("pointerdown");
  h.thumb.fire("pointermove", { pointerId: 2, clientX: 50 });
  assert.deepStrictEqual(h.moves, []);
  h.allowed = false;
  h.thumb.fire("pointermove", { clientX: 50 });
  assert.deepStrictEqual(h.calls, ["cancel"]);
  assert.strictEqual(h.b.dragging(), false);
});

test("bindThumb: the browser taking the pointer ends the move; losing capture cancels it", () => {
  const taken = bound(0.1);
  taken.thumb.fire("pointerdown");
  taken.thumb.fire("pointercancel");
  assert.deepStrictEqual(taken.calls, ["end"]);
  const lost = bound(0.1);
  lost.thumb.fire("pointerdown");
  lost.thumb.fire("lostpointercapture");
  assert.deepStrictEqual(lost.calls, ["cancel"]);
});
