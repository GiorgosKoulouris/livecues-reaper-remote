#!/usr/bin/env node
// Syntax-check every browser script in every slice, plus the scripts in this folder; then luacheck every app with
// a .luacheckrc (scripts/lua.js).
"use strict";
const fs = require("fs");
const path = require("path");
const { execFileSync } = require("child_process");
const lib = require("./release-lib.js");

const repo = path.join(__dirname, "..");
const targets = lib.collectFiles(repo).filter((f) => f.source.endsWith(".js")).map((f) => f.source)
  .concat(fs.readdirSync(__dirname).filter((f) => f.endsWith(".js")).map((f) => "scripts/" + f));
targets.forEach((t) => execFileSync(process.execPath, ["--check", path.join(repo, t)], { stdio: "inherit" }));
console.log("syntax ok: " + targets.length + " files");
process.exitCode = require("./lua.js").run(repo, "check");
