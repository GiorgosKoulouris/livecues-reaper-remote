const test = require("node:test");
const assert = require("node:assert");
const fs = require("fs");
const os = require("os");
const path = require("path");
const { luaApps, run, TOOLS } = require("../scripts/lua.js");

function tmpRepo(files) {
  const repo = fs.mkdtempSync(path.join(os.tmpdir(), "lcrr-lua-"));
  files.forEach((p) => {
    fs.mkdirSync(path.dirname(path.join(repo, p)), { recursive: true });
    fs.writeFileSync(path.join(repo, p), "");
  });
  return repo;
}

test("luaApps finds only the apps carrying the given config, sorted", () => {
  const repo = tmpRepo(["apps/zeta/.busted", "apps/arrange/.busted", "apps/arrange/.luacheckrc", "apps/podium/www/x.html"]);
  assert.deepStrictEqual(luaApps(repo, ".busted"), ["apps/arrange", "apps/zeta"]);
  assert.deepStrictEqual(luaApps(repo, ".luacheckrc"), ["apps/arrange"]);
});

test("luaApps and run are a no-op for a repo without Lua apps", () => {
  const repo = tmpRepo(["apps/podium/www/x.html"]);
  assert.deepStrictEqual(luaApps(repo, ".busted"), []);
  assert.strictEqual(run(repo, "test"), 0);
});

test("run fails, not skips, when the tool is missing", () => {
  const repo = tmpRepo(["apps/arrange/.busted"]);
  const saved = TOOLS.test.cmd;
  TOOLS.test.cmd = "lcrr-no-such-tool";
  const err = console.error, log = console.log;
  console.error = console.log = () => {};
  try { assert.strictEqual(run(repo, "test"), 1); }
  finally { TOOLS.test.cmd = saved; console.error = err; console.log = log; }
});

test("run rejects an unknown mode", () => {
  assert.throws(() => run(tmpRepo([]), "deploy"), /usage/);
});
