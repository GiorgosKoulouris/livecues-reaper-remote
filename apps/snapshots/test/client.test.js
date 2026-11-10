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

test("snapshots() and save(name) send their commands; only the name travels with a save", async () => {
  async function sent(call) {
    const { c, urls } = rig((url, seen) => {
      if (url.indexOf("/_/SET/") === 0) return Promise.resolve("");
      return Promise.resolve("EXTSTATE\tLCRR_SNAPSHOTS\tres\tid1|{\"status\":\"ok\"}\n");
    });
    await call(c);
    return decodeURIComponent(urls[0]);
  }
  assert.ok((await sent((c) => c.snapshots())).endsWith("|cmd=snapshots"));
  assert.ok((await sent((c) => c.save("Verse & Chorus"))).endsWith("|cmd=snapshot_save&name=Verse%20%26%20Chorus"));
});

test("overwrite(name) saves with overwrite=1 and remove(name) sends snapshot_delete", async () => {
  async function sent(call) {
    const { c, urls } = rig((url) => Promise.resolve(url.indexOf("/_/SET/") === 0 ? "" : "EXTSTATE\tLCRR_SNAPSHOTS\tres\tid1|{\"status\":\"ok\"}\n"));
    await call(c);
    return decodeURIComponent(urls[0]);
  }
  assert.ok((await sent((c) => c.overwrite("Verse"))).endsWith("|cmd=snapshot_save&name=Verse&overwrite=1"));
  assert.ok((await sent((c) => c.remove("Verse"))).endsWith("|cmd=snapshot_delete&name=Verse"));
});

// A name must fit every request it is later sent in, not only Save.
const wire = require("../www/lcrr/snapshots/js/wire.js");
const core = require("../www/lcrr/snapshots/js/core.js");
const realId = "mhx7k2q9-1234567"; // a base-36 clock, "-", a counter: as long as the page makes them
function requestsFor(name) {
  return [
    { cmd: "snapshot_save", name },
    { cmd: "snapshot_save", name, overwrite: 1 },
    { cmd: "snapshot_restore", name, ticks: "LPMSREFI" }
  ].map((f) => wire.setRequestCommand(wire.buildRequest(realId, f)));
}
function longestAccepted(unit) {
  let name = "";
  while (core.checkName(name + unit, [], client.nameFits).name) name += unit;
  return name;
}

test("the longest name the check accepts saves, overwrites and restores with every tick", () => {
  ["a", "\u{1F600}"].forEach((unit) => {
    const name = longestAccepted(unit);
    assert.ok(name.length > 0);
    requestsFor(name).forEach((cmd) => assert.ok(!wire.tooLong(cmd), cmd.length + " is over the limit"));
  });
});

test("one more character than the longest accepted name is refused", () => {
  ["\u{1F600}", "é", "a"].forEach((unit) => {
    const name = longestAccepted(unit);
    assert.deepStrictEqual(core.checkName(name + unit, [], client.nameFits), { code: "name_too_long" });
  });
});

test("forty emoji are refused at Save", () => {
  assert.deepStrictEqual(core.checkName("\u{1F600}".repeat(40), [], client.nameFits), { code: "name_too_long" });
});
