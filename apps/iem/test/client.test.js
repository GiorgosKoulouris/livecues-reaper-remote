const test = require("node:test");
const assert = require("node:assert");
const client = require("../www/lcrr/iem/js/client.js");

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

test("cell sends the pair by GUID and the wanted state", async () => {
  const { c, urls } = rig(() => Promise.resolve(""));
  await c.cell("{K}", "{A}", true).catch(() => {});
  const url = decodeURIComponent(urls[0]);
  assert.ok(/cmd=cell/.test(url) && /source=%7BK%7D/.test(url) && /mix=%7BA%7D/.test(url) && /on=1/.test(url), url);
  await c.cell("{K}", "{A}", false).catch(() => {});
  assert.ok(/on=0/.test(decodeURIComponent(urls.filter((u) => u.indexOf("SET/") !== -1).pop())));
});

test("row and column send only the ID and the wanted state", async () => {
  const { c, urls } = rig(() => Promise.resolve(""));
  await c.row("{K}", true).catch(() => {});
  let url = decodeURIComponent(urls[0]);
  assert.ok(/cmd=row/.test(url) && /source=%7BK%7D/.test(url) && /on=1/.test(url) && !/mix=/.test(url), url);
  await c.column("{A}", false).catch(() => {});
  url = decodeURIComponent(urls.filter((u) => u.indexOf("SET/") !== -1).pop());
  assert.ok(/cmd=column/.test(url) && /mix=%7BA%7D/.test(url) && /on=0/.test(url) && !/source=/.test(url), url);
});

test("state() writes the request, then reads the reply that carries its id", async () => {
  const { c, urls } = rig((url, seen) => {
    if (url.indexOf("/_/SET/") === 0) return Promise.resolve("");
    const stale = seen.filter((u) => u.indexOf("GET/") !== -1).length < 2;
    return Promise.resolve("EXTSTATE\tLCRR_IEM\tres\t" + (stale ? "old|{}" : 'id1|{"status":"ok","command":"state"}') + "\n");
  });
  const reply = await c.state();
  assert.strictEqual(reply.command, "state");
  assert.ok(urls[0].startsWith("/_/SET/EXTSTATE/LCRR_IEM/req/id1"));
});

test("a request REAPER does not take rejects as unreachable; one nobody answers as no_reply", async () => {
  await assert.rejects(rig(() => Promise.reject(new Error("x"))).c.state(), { code: "unreachable" });
  await assert.rejects(rig((url) => Promise.resolve(url.indexOf("SET") !== -1 ? "" : "EXTSTATE\tLCRR_IEM\tres\t\n")).c.state(), { code: "no_reply" });
});

test("a request too long to send is refused before it goes out", async () => {
  const { c, urls } = rig(() => Promise.resolve(""));
  await assert.rejects(c.call("state", { pad: "x".repeat(1000) }), { code: "request_too_long" });
  assert.strictEqual(urls.length, 0);
});

function sentRequest(urls) { return decodeURIComponent(urls[0].split("/req/")[1]); }

test("each write sends its command with its fields, by GUID, and stays short", async () => {
  const cases = [
    [(c) => c.create("Lead & Keys"), "cmd=create&name=Lead%20%26%20Keys"],
    [(c) => c.create("Bass", "{AB-1}"), "cmd=create&name=Bass&copy=%7BAB-1%7D"],
    [(c) => c.rename("{AB-1}", "Bass"), "cmd=rename&guid=%7BAB-1%7D&name=Bass"],
    [(c) => c.colour("ff8000"), "cmd=colour&colour=ff8000"],
    [(c) => c.moveToEnd("{AB-1}"), "cmd=move_to_end&guid=%7BAB-1%7D"],
    [(c) => c.deleteMix("{AB-1}"), "cmd=delete&guid=%7BAB-1%7D"],
    [(c) => c.adopt("{AB-1}"), "cmd=adopt&guid=%7BAB-1%7D"],
    [(c) => c.createCue(), "cmd=cue"]
  ];
  for (const [call, body] of cases) {
    const { c, urls } = rig((url) => Promise.resolve(url.indexOf("/_/SET/") === 0 ? "" : 'EXTSTATE\tLCRR_IEM\tres\tid1|{"status":"ok"}\n'));
    const reply = await call(c);
    assert.strictEqual(reply.status, "ok");
    assert.ok(sentRequest(urls).endsWith("|" + body), sentRequest(urls));
    assert.ok(urls[0].length < 300);
  }
});

test("a name too long for the request is refused before it goes out", async () => {
  const { c, urls } = rig(() => Promise.resolve(""));
  await assert.rejects(c.create("x".repeat(900)), { code: "request_too_long" });
  assert.strictEqual(urls.length, 0);
});

test("setting, replacing and clearing an output send the channel, mono flag and GUID", async () => {
  const cases = [
    [(c) => c.setOutput("{AB-1}", { channel: 2, mono: true }), "cmd=output&guid=%7BAB-1%7D&channel=2&mono=1"],
    [(c) => c.setOutput("{AB-1}", { channel: 0, mono: false }), "cmd=output&guid=%7BAB-1%7D&channel=0&mono=0"],
    [(c) => c.setOutput("{AB-1}", { none: true }), "cmd=output&guid=%7BAB-1%7D&channel=none"]
  ];
  for (const [call, body] of cases) {
    const { c, urls } = rig((url) => Promise.resolve(url.indexOf("/_/SET/") === 0 ? "" : 'EXTSTATE\tLCRR_IEM\tres\tid1|{"status":"ok"}\n'));
    await call(c);
    assert.ok(sentRequest(urls).endsWith("|" + body), sentRequest(urls));
  }
});
