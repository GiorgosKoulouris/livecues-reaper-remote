// Suite build helpers, unit-tested: collect the web-root slices, build the ReaPack index and the install note.
// Each slice (shared/www, apps/<app>/www) holds a piece of REAPER's reaper_www_root at its deployed paths;
// install, serve and release lay them over each other (docs/adr/0001).
"use strict";
const fs = require("fs");
const path = require("path");

const MAIN = "lcrr.html";            // the home page; also the ReaPack package's main file
const SUITE = "LiveCues ReaperRemote";

// Slice roots, repo-relative: shared first, then every apps/<app>/www, sorted.
function sliceRoots(repo) {
  const apps = path.join(repo, "apps");
  const roots = ["shared/www"];
  if (fs.existsSync(apps)) {
    fs.readdirSync(apps).sort().forEach((a) => {
      if (fs.existsSync(path.join(apps, a, "www"))) roots.push("apps/" + a + "/www");
    });
  }
  return roots;
}

// Every file of every slice: { deployed: "lcrr/podium/js/core.js", source: "apps/podium/www/lcrr/podium/js/core.js" }.
// Paths use "/" on every platform. Two slices shipping the same deployed path is an error.
function collectFiles(repo) {
  const out = [], seen = {};
  sliceRoots(repo).forEach((root) => {
    (function walk(rel) {
      const dir = path.join(repo, root, rel);
      fs.readdirSync(dir).sort().forEach((name) => {
        const r = rel ? rel + "/" + name : name;
        if (fs.statSync(path.join(dir, name)).isDirectory()) return walk(r);
        if (seen[r]) throw new Error(r + " is in both " + seen[r] + " and " + root);
        seen[r] = root;
        out.push({ deployed: r, source: root + "/" + r });
      });
    })("");
  });
  return out.sort((a, b) => (a.deployed < b.deployed ? -1 : a.deployed > b.deployed ? 1 : 0));
}

function escapeXml(s) {
  return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
}

// One ReaPack package for the whole suite (docs/adr/0002): every file in one <version>, so no two packages
// ever own the same file. Package type "webinterface" installs into REAPER's reaper_www_root; `file` keeps
// the subfolder. baseUrl points at the repo root at a tag or commit; each URL uses the file's repo path.
// UNVERIFIED against a live ReaPack install.
function buildIndexXml(o) {
  const main = o.files.filter((f) => f.deployed === MAIN)[0];
  if (!main) throw new Error("file list must include " + MAIN);
  const base = o.baseUrl.replace(/\/+$/, "") + "/";
  const sources = [main].concat(o.files.filter((f) => f !== main)).map((f) => {
    const url = escapeXml(base + f.source);
    return f === main ? "        <source>" + url + "</source>"
                      : '        <source file="' + escapeXml(f.deployed) + '">' + url + "</source>";
  });
  return [
    '<?xml version="1.0" encoding="utf-8"?>',
    '<index version="1" name="' + SUITE + '">',
    '  <category name="Web Interfaces">',
    '    <reapack name="' + MAIN + '" type="webinterface" desc="' + SUITE + ': remote pages for REAPER (home + all apps)">',
    "      <metadata>",
    "        <description><![CDATA[" + SUITE + " (LCRR): a suite of remote-control pages for REAPER's web interface, usable from a phone, tablet or desktop browser on the same LAN. After installing, choose lcrr.html as the Default interface in Preferences > Control/OSC/web.]]></description>",
    "      </metadata>",
    '      <version name="' + escapeXml(o.version) + '" author="' + escapeXml(o.author || "") + '" time="' + escapeXml(o.time) + '">',
    "        <changelog><![CDATA[" + (o.changelog || "Release " + o.version) + "]]></changelog>",
    sources.join("\n"),
    "      </version>",
    "    </reapack>",
    "  </category>",
    "</index>",
    ""
  ].join("\n");
}

function installText(version) {
  return [
    SUITE + " " + version,
    "",
    "1. In REAPER: Preferences > Control/OSC/web > Add > Web browser interface. Set a port.",
    "2. Click 'User pages...' (opens %APPDATA%\\REAPER\\reaper_www_root).",
    "3. Extract this zip into that folder, keeping its folders: lcrr*.html at the top, the lcrr\\ folder beside them.",
    "4. Re-open the dialog, pick lcrr.html as the 'Default interface', click Apply.",
    "5. Open http://<pc-ip>:<port>/ from a phone, tablet or desktop on the same LAN.",
    "",
    "Trusted LAN only: do not expose the port to the internet.",
    ""
  ].join("\n");
}

module.exports = { sliceRoots, collectFiles, buildIndexXml, installText, escapeXml, MAIN, SUITE };
