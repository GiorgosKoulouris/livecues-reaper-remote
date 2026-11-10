const test = require("node:test");
const assert = require("node:assert");
const wire = require("../www/lcrr/iem/js/wire.js");

test("it talks to the IEM section, not Arrange's", () => {
  assert.strictEqual(wire.SECTION, "LCRR_IEM");
  assert.strictEqual(wire.getCommand("res"), "GET/EXTSTATE/LCRR_IEM/res");
});

test("a request declares its own length and percent-encodes values", () => {
  assert.strictEqual(wire.buildRequest("a1", { cmd: "state" }), "a1|9|cmd=state");
  assert.strictEqual(wire.buildRequest("a1", { cmd: "x", name: "a&b" }), "a1|16|cmd=x&name=a%26b");
  assert.strictEqual(wire.setRequestCommand("a1|9|cmd=state"), "SET/EXTSTATE/LCRR_IEM/req/a1%7C9%7Ccmd%3Dstate");
});

test("replies: ExtState line, escapes, id and JSON", () => {
  const text = "EXTSTATE\tLCRR_IEM\tres\tq1|{\"a\":1}\n";
  const value = wire.parseExtState(text, "res");
  assert.deepStrictEqual(wire.parseResult(value), { id: "q1", reply: { a: 1 } });
  assert.strictEqual(wire.unescapeValue("a\\tb\\\\c"), "a\tb\\c");
  assert.strictEqual(wire.parseExtState("TRANSPORT\t1", "res"), null);
  assert.strictEqual(wire.parseResult("q1|{half"), null);
});

test("the heartbeat says running only while it keeps changing", () => {
  let t = 0;
  const beat = wire.createHeartbeat({ staleMs: 1000, now: () => t });
  assert.strictEqual(beat.state(), "unknown");
  beat.update("1");
  assert.strictEqual(beat.state(), "running");
  t = 900; beat.update("2");
  t = 1800; assert.strictEqual(beat.state(), "running");
  t = 2000; beat.update("2");
  t = 2901; assert.strictEqual(beat.state(), "stopped");
  beat.update("");
  assert.strictEqual(beat.state(), "stopped");
});
