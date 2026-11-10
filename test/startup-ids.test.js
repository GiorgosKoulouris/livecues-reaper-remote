// install.ps1 and shared/startup/hook.lua both manage marked lines in Scripts/__startup.lua. They must recognise each
// other's lines (uninstall and reinstall in either tool), so both match on the bridge id, never on the marker's suffix.
// No PowerShell in the devcontainer: this reads install.ps1 as text.
const test = require("node:test");
const assert = require("node:assert");
const fs = require("fs");
const path = require("path");

const repo = path.join(__dirname, "..");
const ps = fs.readFileSync(path.join(repo, "scripts", "install.ps1"), "utf8");
const lua = fs.readFileSync(path.join(repo, "shared", "reaper", "Scripts", "LCRR", "shared", "startup", "hook.lua"), "utf8");

test("install.ps1 and hook.lua know the same bridge ids and scripts", () => {
  const psBridges = [...ps.matchAll(/Id = '([^']+)';[^}]*?Script = '([^']+)'/g)].map((m) => m[1] + " " + m[2]);
  const luaBridges = [...lua.matchAll(/id = "([^"]+)", script = "([^"]+)"/g)].map((m) => m[1] + " " + m[2]);
  assert.ok(psBridges.length >= 2, "install.ps1 bridges not found");
  assert.deepStrictEqual(psBridges, luaBridges);
});

test("install.ps1 removes startup lines by bridge id, not by its own marker text", () => {
  const filter = ps.split("\n").filter((l) => l.includes("-notlike") && l.includes("$bridge."));
  assert.strictEqual(filter.length, 1);
  assert.match(filter[0], /\$bridge\.Id/);
  assert.doesNotMatch(filter[0], /\$bridge\.Marker/);
});
