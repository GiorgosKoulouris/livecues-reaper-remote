const test = require("node:test");
const assert = require("node:assert");
const fs = require("fs");
const os = require("os");
const path = require("path");
const { buildIndexXml, installText, escapeXml, collectFiles, collectLuaFiles, sliceRoots, changelogFor, releaseProblems, releaseNotes } = require("../scripts/release-lib.js");

const files = [
  { deployed: "lcrr-podium.html", source: "apps/podium/www/lcrr-podium.html" },
  { deployed: "lcrr.html", source: "apps/home/www/lcrr.html" },
  { deployed: "lcrr/shared/js/poll.js", source: "shared/www/lcrr/shared/js/poll.js" }
];
const opts = { version: "1.2.3", files, baseUrl: "https://example.com/raw/tag/", time: "2026-11-07T12:00:00Z", author: "A & B" };

test("buildIndexXml: one suite package, main file first without a file attribute, the rest keep their subfolders", () => {
  const xml = buildIndexXml(opts);
  assert.match(xml, /<index version="1" name="LCRR">/);
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

const lua = [
  { deployed: "arrange/LCRR_Arrange_Bridge.lua", source: "apps/arrange/reaper/Scripts/LCRR/arrange/LCRR_Arrange_Bridge.lua" },
  { deployed: "arrange/lib/paths.lua", source: "apps/arrange/reaper/Scripts/LCRR/arrange/lib/paths.lua" },
  { deployed: "shared/bridge/json.lua", source: "shared/reaper/Scripts/LCRR/shared/bridge/json.lua" }
];

test("buildIndexXml: Lua files are type=script sources keeping <part>/ subpaths; entry scripts register as actions", () => {
  const xml = buildIndexXml({ ...opts, luaFiles: lua });
  assert.strictEqual(xml.match(/<reapack /g).length, 1);
  assert.match(xml, /<source type="script" main="main" file="arrange\/LCRR_Arrange_Bridge\.lua">https:\/\/example\.com\/raw\/tag\/apps\/arrange\/reaper\/Scripts\/LCRR\/arrange\/LCRR_Arrange_Bridge\.lua<\/source>/);
  assert.match(xml, /<source type="script" file="arrange\/lib\/paths\.lua">/);
  assert.match(xml, /<source type="script" file="shared\/bridge\/json\.lua">/);
  assert.doesNotMatch(xml, /type="script" main="main" file="arrange\/lib/);
});

test("buildIndexXml without Lua files has no script sources", () => {
  assert.doesNotMatch(buildIndexXml(opts), /type="script"/);
});

test("collectLuaFiles reads Scripts/LCRR/<part>/ of every reaper slice and refuses clashes", () => {
  const repo = tmpRepo({
    "shared/reaper/Scripts/LCRR/shared/bridge/json.lua": "",
    "apps/arrange/reaper/Scripts/LCRR/arrange/LCRR_Arrange_Bridge.lua": "",
    "apps/arrange/reaper/Scripts/LCRR/arrange/lib/log.lua": "",
    "apps/arrange/spec/log_spec.lua": "",
    "apps/podium/www/lcrr-podium.html": ""
  });
  try {
    assert.deepStrictEqual(collectLuaFiles(repo).map((f) => f.deployed),
      ["arrange/LCRR_Arrange_Bridge.lua", "arrange/lib/log.lua", "shared/bridge/json.lua"]);
    assert.strictEqual(collectLuaFiles(repo)[0].source, "apps/arrange/reaper/Scripts/LCRR/arrange/LCRR_Arrange_Bridge.lua");
  } finally { fs.rmSync(repo, { recursive: true, force: true }); }
  const bad = tmpRepo({ "shared/reaper/Scripts/LCRR/x/a.lua": "", "apps/a/reaper/Scripts/LCRR/x/a.lua": "" });
  try { assert.throws(() => collectLuaFiles(bad), /x\/a\.lua is in both/); }
  finally { fs.rmSync(bad, { recursive: true, force: true }); }
});

test("the real repo's Lua slices collect and include the Arrange and IEM bridges and the shared runner", () => {
  const d = collectLuaFiles(path.join(__dirname, "..")).map((f) => f.deployed);
  ["arrange/LCRR_Arrange_Bridge.lua", "iem/LCRR_IEM_Bridge.lua", "shared/bridge/runner.lua"].forEach((x) => assert.ok(d.includes(x), x));
});

const CL = "# Changelog\n\n## 1.1.0 (2026-11-20)\n\n- Added thing\n  - detail\n- Fixed other (abc123)\n\n## 1.0.0 (2026-11-10)\n\n- First\n\n## 2026-11-01\n\n- Old\n";

test("changelogFor returns the notes under the version's heading, up to the next heading", () => {
  assert.strictEqual(changelogFor(CL, "1.1.0"), "- Added thing\n  - detail\n- Fixed other (abc123)");
  assert.strictEqual(changelogFor(CL, "1.0.0"), "- First");
});

test("changelogFor: a pre-release uses its base version's section", () => {
  assert.strictEqual(changelogFor(CL, "1.1.0-beta1"), "- Added thing\n  - detail\n- Fixed other (abc123)");
});

test("changelogFor: an exact pre-release heading wins over the base version", () => {
  const md = "## 1.1.0-beta1\n\n- beta note\n\n## 1.1.0\n\n- final note\n";
  assert.strictEqual(changelogFor(md, "1.1.0-beta1"), "- beta note");
});

test("changelogFor: no section for the version gives null; 1.1 does not match 1.1.0", () => {
  assert.strictEqual(changelogFor(CL, "2.0.0"), null);
  assert.strictEqual(changelogFor("## 1.1.0\n\n- x\n", "1.1"), null);
});

test("buildIndexXml puts the changelog in a CDATA block, safe against a closing marker", () => {
  const xml = buildIndexXml({ ...opts, changelog: "- a ]]> b" });
  assert.match(xml, /<changelog><!\[CDATA\[- a \]\]\]\]><!\[CDATA\[> b\]\]><\/changelog>/);
});

const REPO = "owner/repo";
const TAG = "v1.2.3-beta1";
const goodIndex = '<version name="1.2.3-beta1" author="A" time="T">\n' +
  '<source>https://raw.githubusercontent.com/owner/repo/v1.2.3-beta1/apps/home/www/lcrr.html</source>\n' +
  '<source file="lcrr/x.js">https://raw.githubusercontent.com/owner/repo/v1.2.3-beta1/shared/www/lcrr/x.js</source>\n</version>';
const goodRelease = { tag: TAG, repo: REPO, version: "1.2.3-beta1", indexXml: goodIndex, changelog: "# Changelog\n\n## 1.2.3-beta1 (2026-01-01)\n\n- A change\n" };

test("releaseProblems: a matching tag, version, changelog and index has no problems", () => {
  assert.deepStrictEqual(releaseProblems(goodRelease), []);
});

test("releaseProblems: a tag that is not v<version> is a problem", () => {
  assert.match(releaseProblems({ ...goodRelease, tag: "v9.9.9" }).join("\n"), /v9\.9\.9.*1\.2\.3-beta1/);
});

test("releaseProblems: a missing or empty changelog section is a problem", () => {
  assert.match(releaseProblems({ ...goodRelease, changelog: "# Changelog\n" }).join("\n"), /CHANGELOG/);
  assert.match(releaseProblems({ ...goodRelease, changelog: "## 1.2.3-beta1\n\n## 1.0.0\n- old\n" }).join("\n"), /CHANGELOG/);
});

test("releaseProblems: an index for another version is a problem", () => {
  assert.match(releaseProblems({ ...goodRelease, indexXml: goodIndex.replace('name="1.2.3-beta1"', 'name="1.2.2"') }).join("\n"), /index\.xml.*1\.2\.3-beta1/);
});

test("releaseProblems: an index with no sources, or a source off this tag or repo, is a problem", () => {
  assert.match(releaseProblems({ ...goodRelease, indexXml: '<version name="1.2.3-beta1"></version>' }).join("\n"), /no source/);
  assert.match(releaseProblems({ ...goodRelease, indexXml: goodIndex.replace("/v1.2.3-beta1/shared", "/dev/shared") }).join("\n"), /\/dev\/shared/);
  assert.match(releaseProblems({ ...goodRelease, indexXml: goodIndex.replace("owner/repo/v1.2.3-beta1/apps", "owner/old/v1.2.3-beta1/apps") }).join("\n"), /owner\/old/);
});

test("releaseNotes: a pre-release has its changelog, the main import URL and the pre-release step", () => {
  const notes = releaseNotes(goodRelease);
  assert.match(notes, /- A change/);
  assert.match(notes, /https:\/\/raw\.githubusercontent\.com\/owner\/repo\/main\/index\.xml/);
  assert.match(notes, /Show pre-releases/);
});

test("releaseNotes: a stable release has no pre-release step", () => {
  const notes = releaseNotes({ ...goodRelease, version: "1.2.3", changelog: "## 1.2.3 (2026-01-01)\n\n- Stable\n" });
  assert.match(notes, /- Stable/);
  assert.doesNotMatch(notes, /pre-release/i);
});
