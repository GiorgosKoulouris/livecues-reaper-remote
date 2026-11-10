#!/usr/bin/env node
// Build the suite release zip and (optionally) the ReaPack index.
//   npm run release -- --base-url https://raw.githubusercontent.com/<user>/<repo>/<tag>
// Writes dist/lcrr-<version>.zip (needs the `zip` CLI; folders kept, extract into reaper_www_root) and, with
// --base-url, index.xml at the repo root. --index-out <path> writes the index elsewhere.
"use strict";
const fs = require("fs");
const path = require("path");
const os = require("os");
const { execFileSync } = require("child_process");
const lib = require("./release-lib.js");

const repo = path.join(__dirname, "..");
const pkg = JSON.parse(fs.readFileSync(path.join(repo, "package.json"), "utf8"));
const argv = process.argv.slice(2);
function arg(name) { const i = argv.indexOf(name); return i >= 0 ? argv[i + 1] : undefined; }
const baseUrl = arg("--base-url");

const files = lib.collectFiles(repo);
const dist = path.join(repo, "dist");
fs.mkdirSync(dist, { recursive: true });
const stage = fs.mkdtempSync(path.join(os.tmpdir(), "lcrr-stage-"));
try {
  files.forEach((f) => {
    const to = path.join(stage, f.deployed);
    fs.mkdirSync(path.dirname(to), { recursive: true });
    fs.copyFileSync(path.join(repo, f.source), to);
  });
  fs.writeFileSync(path.join(stage, "lcrr-INSTALL.txt"), lib.installText(pkg.version));
  const zip = path.join(dist, "lcrr-" + pkg.version + ".zip");
  fs.rmSync(zip, { force: true });
  execFileSync("zip", ["-q", "-r", zip, "."], { cwd: stage });
  console.log("wrote " + path.relative(process.cwd(), zip) + " (" + files.length + " files + install note)");
} finally {
  fs.rmSync(stage, { recursive: true, force: true });
}

if (baseUrl) {
  const notes = lib.changelogFor(fs.readFileSync(path.join(repo, "CHANGELOG.md"), "utf8"), pkg.version);
  if (notes === null) console.warn("warning: CHANGELOG.md has no '## " + pkg.version + "' section; the index says just 'Release " + pkg.version + "'");
  const xml = lib.buildIndexXml({
    version: pkg.version, files: files, luaFiles: lib.collectLuaFiles(repo), changelog: notes, baseUrl: baseUrl,
    time: new Date().toISOString().replace(/\.\d+Z$/, "Z"), author: pkg.author || ""
  });
  const out = arg("--index-out") || path.join(repo, "index.xml");
  fs.writeFileSync(out, xml);
  console.log("wrote " + path.relative(process.cwd(), out));
} else {
  console.log("no --base-url: ReaPack index not written");
}
