const test = require("node:test");
const assert = require("node:assert");
const fs = require("fs");
const os = require("os");
const path = require("path");
const { buildIndexXml, installText, escapeXml, collectFiles, sliceRoots } = require("../scripts/release-lib.js");

const files = [
  { deployed: "lcrr-podium.html", source: "apps/podium/www/lcrr-podium.html" },
  { deployed: "lcrr.html", source: "apps/home/www/lcrr.html" },
  { deployed: "lcrr/shared/js/poll.js", source: "shared/www/lcrr/shared/js/poll.js" }
];
const opts = { version: "1.2.3", files, baseUrl: "https://example.com/raw/tag/", time: "2026-11-07T12:00:00Z", author: "A & B" };

test("buildIndexXml: one suite package, main file first without a file attribute, the rest keep their subfolders", () => {
  const xml = buildIndexXml(opts);
  assert.match(xml, /<index version="1" name="LiveCues ReaperRemote">/);
  assert.strictEqual(xml.match(/<reapack /g).length, 1);
  assert.match(xml, /<reapack name="lcrr\.html" type="webinterface"/);
  assert.match(xml, /<version name="1\.2\.3" author="A &amp; B" time="2026-11-07T12:00:00Z">/);
  const main = xml.indexOf("<source>https://example.com/raw/tag/apps/home/www/lcrr.html</source>");
  const poll = xml.indexOf('<source file="lcrr/shared/js/poll.js">https://example.com/raw/tag/shared/www/lcrr/shared/js/poll.js</source>');
  assert.ok(main > 0 && poll > main);
  assert.match(xml, /<source file="lcrr-podium\.html">/);
});

test("buildIndexXml tolerates a base URL without a trailing slash", () => {
  assert.match(buildIndexXml({ ...opts, baseUrl: "https://example.com/x" }), />https:\/\/example\.com\/x\/apps\/home\/www\/lcrr\.html</);
});

test("buildIndexXml requires the home page", () => {
  assert.throws(() => buildIndexXml({ ...opts, files: files.slice(0, 1) }), /lcrr\.html/);
});

test("escapeXml escapes markup characters", () => {
  assert.strictEqual(escapeXml('a<b>&"c'), "a&lt;b&gt;&amp;&quot;c");
});

test("installText mentions the version, the web root, the folders and the Default interface", () => {
  const t = installText("1.2.3");
  assert.match(t, /1\.2\.3/);
  assert.match(t, /reaper_www_root/);
  assert.match(t, /lcrr\\ folder/);
  assert.match(t, /Default interface/);
});

function tmpRepo(layout) {
  const repo = fs.mkdtempSync(path.join(os.tmpdir(), "lcrr-test-"));
  Object.keys(layout).forEach((p) => {
    fs.mkdirSync(path.dirname(path.join(repo, p)), { recursive: true });
    fs.writeFileSync(path.join(repo, p), layout[p]);
  });
  return repo;
}

test("collectFiles lays shared and every app slice over each other at their deployed paths", () => {
  const repo = tmpRepo({
    "shared/www/lcrr/shared/js/poll.js": "",
    "apps/podium/www/lcrr-podium.html": "",
    "apps/podium/www/lcrr/podium/js/core.js": "",
    "apps/podium/test/core.test.js": "",
    "apps/notes/README.md": ""
  });
  try {
    assert.deepStrictEqual(sliceRoots(repo), ["shared/www", "apps/podium/www"]);
    assert.deepStrictEqual(collectFiles(repo), [
      { deployed: "lcrr-podium.html", source: "apps/podium/www/lcrr-podium.html" },
      { deployed: "lcrr/podium/js/core.js", source: "apps/podium/www/lcrr/podium/js/core.js" },
      { deployed: "lcrr/shared/js/poll.js", source: "shared/www/lcrr/shared/js/poll.js" }
    ]);
  } finally { fs.rmSync(repo, { recursive: true, force: true }); }
});

test("collectFiles refuses two slices shipping the same deployed file", () => {
  const repo = tmpRepo({ "shared/www/lcrr.html": "", "apps/home/www/lcrr.html": "" });
  try { assert.throws(() => collectFiles(repo), /lcrr\.html is in both shared\/www and apps\/home\/www/); }
  finally { fs.rmSync(repo, { recursive: true, force: true }); }
});

test("the real repo's slices collect without clashes and include the home page and Podium", () => {
  const deployed = collectFiles(path.join(__dirname, "..")).map((f) => f.deployed);
  assert.ok(deployed.includes("lcrr.html"));
  assert.ok(deployed.includes("lcrr-podium.html"));
  deployed.forEach((d) => assert.ok(/^lcrr(-[a-z0-9-]+)?\.html$/.test(d) || d.startsWith("lcrr/"), d + " is outside the lcrr namespace"));
});
