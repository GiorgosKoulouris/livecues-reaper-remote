const test = require("node:test");
const assert = require("node:assert");
const client = require("../www/lcrr/snapshots/js/client.js");

function rig(handler) {
  const urls = [];
  let t = 0, n = 0;
  const c = client.createClient({
    fetchText: (url) => { urls.push(url); return handler(url, urls); },
    newId: () => "id" + (++n),
    now: () => t,
    wait: (ms) => { t += ms; return Promise.resolve(); }
  });
  return { c, urls };
}

test("state() writes the request to the Snapshots section, then reads the reply that carries its id", async () => {
  const { c, urls } = rig((url, seen) => {
    if (url.indexOf("/_/SET/") === 0) return Promise.resolve("");
    const stale = seen.filter((u) => u.indexOf("GET/") !== -1).length < 2;
    return Promise.resolve("EXTSTATE\tLCRR_SNAPSHOTS\tres\t" + (stale ? "old|{}" : 'id1|{"status":"ok","command":"state"}') + "\n");
  });
  const reply = await c.state();
  assert.strictEqual(reply.command, "state");
  assert.ok(urls[0].startsWith("/_/SET/EXTSTATE/LCRR_SNAPSHOTS/req/id1"), urls[0]);
  assert.ok(decodeURIComponent(urls[0]).endsWith("|cmd=state"));
});

test("a request REAPER does not take rejects as unreachable; one nobody answers as no_reply", async () => {
  await assert.rejects(rig(() => Promise.reject(new Error("x"))).c.state(), { code: "unreachable" });
  await assert.rejects(rig((url) => Promise.resolve(url.indexOf("SET") !== -1 ? "" : "EXTSTATE\tLCRR_SNAPSHOTS\tres\t\n")).c.state(), { code: "no_reply" });
});
