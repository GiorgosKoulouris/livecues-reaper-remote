const test = require("node:test");
const assert = require("node:assert");
const wire = require("../www/lcrr/arrange/js/wire.js");

test("a request declares the length of its body, and percent-encodes every value", () => {
  const raw = wire.buildRequest("a1", { cmd: "check", name: "Verse & Chorus = 100%" });
  const [id, length, body] = [raw.slice(0, 2), raw.split("|")[1], raw.split("|").slice(2).join("|")];
  assert.strictEqual(id, "a1");
  assert.strictEqual(body, "cmd=check&name=Verse%20%26%20Chorus%20%3D%20100%25");
  assert.strictEqual(Number(length), body.length);
});

test("a request leaves out fields that are undefined, and has an empty body for none", () => {
  assert.strictEqual(wire.buildRequest("a1", { cmd: "info", replace: undefined }), "a1|8|cmd=info");
  assert.strictEqual(wire.buildRequest("a1", {}), "a1|0|");
});

test("a non-ASCII name stays ASCII on the wire, so its length is its character count", () => {
  const raw = wire.buildRequest("a1", { name: "Café \u{1F3B5}" });
  assert.ok(/^[\x20-\x7e]+$/.test(raw));
  assert.strictEqual(Number(raw.split("|")[1]), raw.split("|").slice(2).join("|").length);
});

test("the SET command carries the whole request, encoded once more for the URL", () => {
  const raw = wire.buildRequest("a1", { cmd: "info" });
  assert.strictEqual(wire.setRequestCommand(raw), "SET/EXTSTATE/LCRR_ARRANGE/req/" + encodeURIComponent(raw));
  assert.strictEqual(wire.getCommand("res"), "GET/EXTSTATE/LCRR_ARRANGE/res");
});

test("a request URL over about 900 characters is too long, because REAPER cuts at 1026 without saying so", () => {
  assert.strictEqual(wire.tooLong(wire.setRequestCommand(wire.buildRequest("a1", { cmd: "check", name: "x".repeat(50) }))), false);
  assert.strictEqual(wire.tooLong(wire.setRequestCommand(wire.buildRequest("a1", { cmd: "check", name: "x".repeat(900) }))), true);
  // Every character that needs escaping is counted after it has been escaped, twice (each "&" is five characters in the URL).
  assert.strictEqual(wire.tooLong(wire.setRequestCommand(wire.buildRequest("a1", { cmd: "check", name: "&".repeat(200) }))), true);
});

test("REAPER's escapes in a replied value are undone", () => {
  assert.strictEqual(wire.unescapeValue("a\\tb\\nc\\\\d"), "a\tb\nc\\d");
  assert.strictEqual(wire.unescapeValue('{"a":"x\\\\ty"}'), '{"a":"x\\ty"}');
});

test("an EXTSTATE line is found inside a combined reply", () => {
  const text = "TRANSPORT\t0\t1.5\t0\n" + "EXTSTATE\tLCRR_ARRANGE\theartbeat\t42\n";
  assert.strictEqual(wire.parseExtState(text, "heartbeat"), "42");
  assert.strictEqual(wire.parseExtState(text, "res"), null);
});

test("an unset key is an empty value, with or without its trailing tab", () => {
  assert.strictEqual(wire.parseExtState("EXTSTATE\tLCRR_ARRANGE\tres\t\n", "res"), "");
  assert.strictEqual(wire.parseExtState("EXTSTATE\tLCRR_ARRANGE\tres\n", "res"), "");
});

test("another section's key is not ours", () => {
  assert.strictEqual(wire.parseExtState("EXTSTATE\tOTHER\tres\tx\n", "res"), null);
});

test("a result is its id and its JSON", () => {
  assert.deepStrictEqual(wire.parseResult('q1|{"status":"ok","name":"a|b"}'), { id: "q1", reply: { status: "ok", name: "a|b" } });
});

test("anything that is not id|json is no result yet", () => {
  assert.strictEqual(wire.parseResult(""), null);
  assert.strictEqual(wire.parseResult(null), null);
  assert.strictEqual(wire.parseResult("q1|{half"), null);
  assert.strictEqual(wire.parseResult("{}"), null);
  assert.strictEqual(wire.parseResult("|{}"), null);
});

test("the heartbeat says nothing until a reply has carried it", () => {
  const hb = wire.createHeartbeat({ now: () => 0 });
  assert.strictEqual(hb.state(), "unknown");
  hb.update(null);
  assert.strictEqual(hb.state(), "unknown");
});

test("an empty heartbeat means the bridge is not running", () => {
  const hb = wire.createHeartbeat({ now: () => 0 });
  hb.update("");
  assert.strictEqual(hb.state(), "stopped");
});

test("a heartbeat that keeps changing is running, and one that stops is not", () => {
  let t = 0;
  const hb = wire.createHeartbeat({ now: () => t, staleMs: 2500 });
  hb.update("1");
  assert.strictEqual(hb.state(), "running");
  t = 2000; hb.update("2");
  t = 4000;
  assert.strictEqual(hb.state(), "running");
  hb.update("2");
  t = 4400;
  assert.strictEqual(hb.state(), "running");
  t = 4600;
  assert.strictEqual(hb.state(), "stopped");
  t = 5000; hb.update("3");
  assert.strictEqual(hb.state(), "running");
});

test("touch restarts the clock, for after a long action when nothing could beat", () => {
  let t = 0;
  const hb = wire.createHeartbeat({ now: () => t, staleMs: 2500 });
  hb.update("7");
  t = 30000;
  assert.strictEqual(hb.state(), "stopped");
  hb.touch();
  assert.strictEqual(hb.state(), "running");
});
