#!/usr/bin/env node
// Check that a pushed tag can be published, and write its GitHub Release notes. Run by .github/workflows/release.yml.
//   node scripts/verify-release.js v1.2.3 --repo owner/name [--notes-out notes.md]
"use strict";
const fs = require("fs");
const path = require("path");
const lib = require("./release-lib.js");

const repo = path.join(__dirname, "..");
const argv = process.argv.slice(2);
function arg(name) { const i = argv.indexOf(name); return i >= 0 ? argv[i + 1] : undefined; }
function read(file) { return fs.readFileSync(path.join(repo, file), "utf8"); }

const release = {
  tag: argv[0],
  repo: arg("--repo"),
  version: JSON.parse(read("package.json")).version,
  indexXml: read("index.xml"),
  changelog: read("CHANGELOG.md")
};
if (!release.tag || !release.repo) {
  console.error("usage: node scripts/verify-release.js <tag> --repo owner/name [--notes-out file]");
  process.exit(2);
}
const problems = lib.releaseProblems(release);
if (problems.length) {
  problems.forEach((p) => console.error(p));
  process.exit(1);
}
const out = arg("--notes-out");
if (out) fs.writeFileSync(out, lib.releaseNotes(release));
console.log(release.tag + " is ready to publish");
