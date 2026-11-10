const test = require("node:test");
const assert = require("node:assert");
const bridgeWire = require("../www/lcrr/shared/js/bridge-wire.js");
const bridgeClient = require("../www/lcrr/shared/js/bridge-client.js");

test("the wire is bound to the section it is created with", () => {
  const a = bridgeWire.create("LCRR_A"), b = bridgeWire.create("LCRR_B");
  assert.strictEqual(a.getCommand("res"), "GET/EXTSTATE/LCRR_A/res");
  assert.strictEqual(b.setRequestCommand("x"), "SET/EXTSTATE/LCRR_B/req/x");
  assert.strictEqual(a.parseExtState("EXTSTATE\tLCRR_A\tres\tq|{}\n", "res"), "q|{}");
  assert.strictEqual(b.parseExtState("EXTSTATE\tLCRR_A\tres\tq|{}\n", "res"), null);
});

function rig(section, bridgeReply) {
  const wire = bridgeWire.create(section);
  const urls = [];
  let t = 0, n = 0, res = "";
  const fetchText = (url) => {
    urls.push(url);
    if (url.indexOf("/_/SET/") === 0) { res = bridgeReply ? "id1|" + JSON.stringify(bridgeReply) : ""; return Promise.resolve(""); }
    return Promise.resolve("EXTSTATE\t" + section + "\tres\t" + res + "\n");
  };
  const { call } = bridgeClient.createTransport({ wire, fetchText, newId: () => "id" + (++n), now: () => t,
    wait: (ms) => { t += ms; return Promise.resolve(); } });
  return { call, urls };
}

test("a call writes to the wire's section and resolves with the reply that carries its id", async () => {
  const { call, urls } = rig("LCRR_X", { status: "ok" });
  assert.deepStrictEqual(await call("ping", {}), { status: "ok" });
  assert.ok(urls[0].indexOf("/_/SET/EXTSTATE/LCRR_X/req/") === 0);
});

test("no reply within the wait rejects with no_reply", async () => {
  const { call } = rig("LCRR_X", null);
  await assert.rejects(call("ping", {}), { code: "no_reply" });
});

test("the browser io fetches text, aborts a request that times out, and makes ids that never repeat", async () => {
  const bc = bridgeClient;
  const aborted = [];
  class Abort { constructor() { this.signal = {}; } abort() { aborted.push(this); } }
  const ok = bc.createBrowserIo({ fetch: (url, init) => Promise.resolve({ ok: true, text: () => Promise.resolve("hi " + url + init.cache) }),
    AbortController: Abort, now: () => 1000 });
  assert.strictEqual(await ok.fetchText("/_/x", 50), "hi /_/xno-store");
  assert.strictEqual(ok.newId(), (1000).toString(36) + "-1");
  assert.strictEqual(ok.newId(), (1000).toString(36) + "-2");
  assert.strictEqual(aborted.length, 0);

  const bad = bc.createBrowserIo({ fetch: () => Promise.resolve({ ok: false, status: 503, text: () => Promise.resolve("") }), AbortController: Abort });
  await assert.rejects(bad.fetchText("/_/x", 50), /HTTP 503/);
  assert.strictEqual(aborted.length, 1);

  const slow = bc.createBrowserIo({ fetch: () => new Promise(() => {}), AbortController: Abort });
  await assert.rejects(slow.fetchText("/_/x", 5), /timeout/);
  assert.strictEqual(aborted.length, 2);

  const none = bc.createBrowserIo({ fetch: () => Promise.resolve({ ok: true, text: () => Promise.resolve("a") }), AbortController: null });
  assert.strictEqual(await none.fetchText("/_/x", 50), "a");
});
