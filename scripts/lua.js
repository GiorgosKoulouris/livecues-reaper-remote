#!/usr/bin/env node
// Run the Lua toolchain over every app that carries one: busted where apps/<app>/.busted exists, luacheck where
// apps/<app>/.luacheckrc exists, each from inside the app folder (their configs use app-relative paths).
//   node scripts/lua.js test    -> busted
//   node scripts/lua.js check   -> luacheck
// A missing tool is an error, not a skip: a green run must never hide untested Lua. Use the devcontainer.
"use strict";
const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");

const TOOLS = {
  test: { config: ".busted", cmd: "busted", args: ["-o", "utfTerminal"] },
  check: { config: ".luacheckrc", cmd: "luacheck", args: ["."] }
};

// Repo-relative app folders holding the given config file, sorted.
function luaApps(repo, config) {
  const apps = path.join(repo, "apps");
  if (!fs.existsSync(apps)) return [];
  return fs.readdirSync(apps).sort()
    .filter((a) => fs.existsSync(path.join(apps, a, config)))
    .map((a) => "apps/" + a);
}

function run(repo, mode) {
  const tool = TOOLS[mode];
  if (!tool) throw new Error("usage: node scripts/lua.js test|check");
  const apps = luaApps(repo, tool.config);
  if (!apps.length) return 0;
  for (const app of apps) {
    console.log("\n" + tool.cmd + ": " + app);
    const r = spawnSync(tool.cmd, tool.args, { cwd: path.join(repo, app), stdio: "inherit" });
    if (r.error && r.error.code === "ENOENT") {
      console.error("\n" + tool.cmd + " not found. " + app + " has Lua that must be " + (mode === "test" ? "tested" : "linted") +
        ". Run this in the devcontainer, which installs lua5.4, busted and luacheck.");
      return 1;
    }
    if (r.error) throw r.error;
    if (r.status !== 0) return r.status || 1;
  }
  return 0;
}

if (require.main === module) process.exitCode = run(path.join(__dirname, ".."), process.argv[2]);

module.exports = { luaApps, run, TOOLS };
