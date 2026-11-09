const test = require("node:test");
const assert = require("node:assert");
const wire = require("../www/lcrr/arrange/js/wire.js");
const { createClient, APPLY_TIMEOUT_MS } = require("../www/lcrr/arrange/js/client.js");

// A stand-in for REAPER's web API with a bridge behind it: SET writes ExtState, and `bridge` decides what the
// script then does with the request.
function fakeReaper(bridge) {
  const state = { req: "", res: "" };
  const log = [];
  let clock = 0;
  const reaper = {
    log,
    state,
    advance(ms) { clock += ms; },
    now: () => clock,
    wait: (ms) => { clock += ms; return Promise.resolve(); },
    fetchText(url, timeoutMs) {
      log.push({ url, timeoutMs });
      const set = url.match(/^\/_\/SET\/EXTSTATE\/LCRR_ARRANGE\/req\/(.*)$/);
      if (set) {
        state.req = decodeURIComponent(set[1]);
        if (bridge.down) return Promise.reject(new Error("timeout"));
        bridge.on(state);
        return Promise.resolve("");
      }
      if (url === "/_/GET/EXTSTATE/LCRR_ARRANGE/res") {
        if (bridge.getFails && bridge.getFails-- > 0) return Promise.reject(new Error("timeout"));
        const escaped = state.res.replace(/\\/g, "\\\\").replace(/\t/g, "\\t").replace(/\n/g, "\\n");
        return Promise.resolve("EXTSTATE\tLCRR_ARRANGE\tres\t" + escaped + "\n");
      }
      return Promise.reject(new Error("unexpected " + url));
    }
  };
  return reaper;
}

function clientFor(reaper) {
  let n = 0;
  return createClient({ fetchText: reaper.fetchText, newId: () => "id" + (++n), now: reaper.now, wait: reaper.wait });
}

const answer = (reply) => (state) => {
  const id = state.req.split("|")[0];
  state.res = id + "|" + JSON.stringify(reply);
};

test("a call writes the request and returns the reply that carries its id", async () => {
  const reaper = fakeReaper({ on: answer({ status: "ok", verdict: "clean" }) });
  const reply = await clientFor(reaper).call("duplicates", {});
  assert.deepStrictEqual(reply, { status: "ok", verdict: "clean" });
  assert.strictEqual(reaper.state.req, wire.buildRequest("id1", { cmd: "duplicates" }));
});

test("fields reach the bridge intact, awkward names included", async () => {
  const reaper = fakeReaper({ on: answer({ status: "ok" }) });
  await clientFor(reaper).call("check", { name: "A & B | 100%" });
  assert.ok(reaper.state.req.endsWith("cmd=check&name=A%20%26%20B%20%7C%20100%25"));
});

test("a reply with tabs and newlines in it survives REAPER's escaping", async () => {
  const reaper = fakeReaper({ on: answer({ status: "ok", name: "a\tb\nc\\d" }) });
  const reply = await clientFor(reaper).call("x", {});
  assert.strictEqual(reply.name, "a\tb\nc\\d");
});

test("an older reply is not taken for the answer; the call keeps looking", async () => {
  let looks = 0;
  const reaper = fakeReaper({
    on(state) {
      state.res = "someone-else|" + JSON.stringify({ status: "stale" });
      setImmediate(() => {});
    }
  });
  const realFetch = reaper.fetchText;
  reaper.fetchText = (url, ms) => {
    if (url.includes("/res") && ++looks === 3) reaper.state.res = reaper.state.req.split("|")[0] + "|" + JSON.stringify({ status: "ok" });
    return realFetch(url, ms);
  };
  const reply = await clientFor(reaper).call("info", {});
  assert.strictEqual(reply.status, "ok");
  assert.strictEqual(looks, 3);
});

test("a bridge that never answers is no_reply, after the wait", async () => {
  const reaper = fakeReaper({ on() {} });
  await assert.rejects(clientFor(reaper).call("info", {}), (e) => e.code === "no_reply");
  assert.ok(reaper.now() >= 8000);
});

test("a failed read is retried until the deadline", async () => {
  const reaper = fakeReaper({ on: answer({ status: "ok" }), getFails: 3 });
  assert.strictEqual((await clientFor(reaper).call("info", {})).status, "ok");
});

test("REAPER not taking the request is unreachable", async () => {
  const reaper = fakeReaper({ down: true, on() {} });
  await assert.rejects(clientFor(reaper).call("info", {}), (e) => e.code === "unreachable");
});

test("a request that would be cut is never sent", async () => {
  const reaper = fakeReaper({ on: answer({ status: "ok" }) });
  await assert.rejects(clientFor(reaper).call("check", { name: "x".repeat(900) }), (e) => e.code === "request_too_long");
  assert.strictEqual(reaper.log.length, 0);
});

test("the request waits as long as it is told to, and the reads are short", async () => {
  const reaper = fakeReaper({ on: answer({ status: "ok" }) });
  await clientFor(reaper).call("apply", { token: "abc" }, { timeoutMs: APPLY_TIMEOUT_MS });
  assert.strictEqual(reaper.log[0].timeoutMs, 120000);
  assert.strictEqual(reaper.log[1].timeoutMs, 3000);
});
