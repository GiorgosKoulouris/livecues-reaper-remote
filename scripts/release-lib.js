// Suite build helpers, unit-tested: collect the web-root slices, build the ReaPack index and the install note.
// Each slice (shared/www, apps/<app>/www) holds a piece of REAPER's reaper_www_root at its deployed paths;
// install, serve and release lay them over each other (docs/adr/0001).
"use strict";
const fs = require("fs");
const path = require("path");

const MAIN = "lcrr.html";            // the home page; also the ReaPack package's main file
const SUITE = "LiveCues ReaperRemote";
const INDEX_NAME = "LCRR";          // ReaPack index name: scripts install under Scripts/<index name>/<category>/
const CATEGORY = "Remote";          // the package's one category (a package has exactly one)

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

// Lua of every reaper slice (shared/reaper and apps/<app>/reaper), each holding Scripts/LCRR/<part>/...:
// { deployed: "arrange/lib/log.lua", source: "apps/arrange/reaper/Scripts/LCRR/arrange/lib/log.lua" }.
// deployed is relative to Scripts/LCRR, so <part> folders stay siblings (scripts find shared/ through "..").
function collectLuaFiles(repo) {
  const roots = ["shared/reaper"];
  const apps = path.join(repo, "apps");
  if (fs.existsSync(apps)) fs.readdirSync(apps).sort().forEach((a) => roots.push("apps/" + a + "/reaper"));
  const out = [], seen = {};
  roots.forEach((root) => {
    const base = root + "/Scripts/LCRR";
    if (!fs.existsSync(path.join(repo, base))) return;
    (function walk(rel) {
      const dir = path.join(repo, base, rel);
      fs.readdirSync(dir).sort().forEach((name) => {
        const r = rel ? rel + "/" + name : name;
        if (fs.statSync(path.join(dir, name)).isDirectory()) return walk(r);
        if (seen[r]) throw new Error(r + " is in both " + seen[r] + " and " + root);
        seen[r] = root;
        out.push({ deployed: r, source: base + "/" + r });
      });
    })("");
  });
  return out.sort((a, b) => (a.deployed < b.deployed ? -1 : a.deployed > b.deployed ? 1 : 0));
}

// The notes under a "## <version> ..." heading of CHANGELOG.md, trimmed, up to the next "## " heading.
// null if that version has no section.
function changelogFor(markdown, version) {
  const lines = markdown.split(/\r?\n/);
  const head = lines.findIndex((l) => l.indexOf("## " + version) === 0 && /^(\s|\(|$)/.test(l.slice(3 + version.length)));
  if (head < 0) return null;
  let end = lines.findIndex((l, i) => i > head && /^## /.test(l));
  if (end < 0) end = lines.length;
  return lines.slice(head + 1, end).join("\n").trim();
}

const CHANGELOG_HEADING = /^## ((\d+)\.(\d+)\.(\d+)(?:-beta(\d+))?) \(\d{4}-\d{2}-\d{2}\)$/;

// Everything wrong with the layout of CHANGELOG.md, as messages; [] when it is sound. `version` is the package version.
function changelogProblems(markdown, version) {
  const problems = [];
  const sections = [];
  markdown.split(/\r?\n/).forEach((line) => {
    if (/^## /.test(line)) {
      const m = CHANGELOG_HEADING.exec(line);
      if (!m) problems.push("malformed heading, expected '## <version> (YYYY-MM-DD)': " + line);
      sections.push({
        line: line,
        version: m ? m[1] : null,
        rank: m ? [+m[2], +m[3], +m[4], m[5] === undefined ? Infinity : +m[5]] : null,
        hasNotes: false
      });
    } else if (sections.length && /^- /.test(line)) {
      sections[sections.length - 1].hasNotes = true;
    }
  });
  if (!sections.length) return problems.concat("CHANGELOG.md has no version sections");
  if (sections[0].version !== version) problems.push("the top section must be the package version " + version + ": " + sections[0].line);
  sections.filter((s) => !s.hasNotes).forEach((s) => problems.push("section has no notes: " + s.line));
  const valid = sections.filter((s) => s.version);
  valid.slice(1).forEach((s, i) => {
    const before = valid[i].rank;
    const diff = before.map((n, j) => n - s.rank[j]).find((d) => d !== 0 && !Number.isNaN(d));
    if (!(diff > 0)) problems.push("sections out of order, newest version first: " + s.line);
  });
  valid.filter((s) => s.version.indexOf("-") >= 0).forEach((s) => {
    const base = s.version.replace(/-.*$/, "");
    if (valid.some((o) => o.version === base)) problems.push("collapse the betas into the stable section " + base + ": " + s.line);
  });
  return problems;
}

// Everything wrong with publishing `tag` of `repo` ("owner/name"), as messages; [] when it can go out. Guards the tag
// workflow (scripts/verify-release.js): the tag names this version, the changelog has its notes, and every file URL in
// the committed index points at this tag of this repo, so ReaPack never gets a dead or foreign link.
function releaseProblems(o) {
  const problems = [];
  if (o.tag !== "v" + o.version) problems.push("tag " + o.tag + " does not match package.json version " + o.version);
  if (!changelogFor(o.changelog, o.version)) problems.push("CHANGELOG.md has no notes for " + o.version);
  if (o.indexXml.indexOf('<version name="' + o.version + '"') < 0) problems.push("index.xml does not list version " + o.version);
  const prefix = "https://raw.githubusercontent.com/" + o.repo + "/" + o.tag + "/";
  const urls = [];
  o.indexXml.replace(/<source[^>]*>([^<]+)<\/source>/g, (_, url) => urls.push(url));
  if (!urls.length) problems.push("index.xml has no source URLs");
  urls.filter((u) => u.indexOf(prefix) !== 0).forEach((u) => problems.push("index.xml URL is not under " + prefix + ": " + u));
  return problems;
}

// The body of the GitHub Release: the changelog section, then how to install or update through ReaPack.
function releaseNotes(o) {
  const url = "https://raw.githubusercontent.com/" + o.repo + "/main/index.xml";
  const pre = /-/.test(o.version);
  return [
    changelogFor(o.changelog, o.version),
    "",
    "## Install or update",
    "",
    "In REAPER, go to **Extensions > ReaPack > Import repositories...** and paste:",
    "",
    "```",
    url,
    "```",
    ""
  ].concat(pre ? ["This is a beta: in **Extensions > ReaPack > Manage repositories**, open the LCRR entry and enable **Show pre-releases**.", ""] : [])
    .concat(["Already installed? Run **Extensions > ReaPack > Synchronize packages**, then restart REAPER.", ""]).join("\n");
}

function escapeXml(s) {
  return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
}

// One ReaPack package for the whole suite (docs/adr/0002): every file in one <version>, so no two packages
// ever own the same file. Package type "webinterface" installs into REAPER's reaper_www_root; `file` keeps
// the subfolder. baseUrl points at the repo root at a tag or commit; each URL uses the file's repo path.
// Lua (o.luaFiles) rides along as per-source type="script". UNVERIFIED against a live ReaPack install.
function buildIndexXml(o) {
  const main = o.files.filter((f) => f.deployed === MAIN)[0];
  if (!main) throw new Error("file list must include " + MAIN);
  const base = o.baseUrl.replace(/\/+$/, "") + "/";
  const luaSources = (o.luaFiles || []).map((f) => {
    // Entry scripts (LCRR_<App>_<Verb>.lua directly in a <part> folder) register as actions; lib/ and shared/ do not.
    const entry = /^[^/]+\/LCRR_[^/]+\.lua$/.test(f.deployed);
    return '        <source type="script"' + (entry ? ' main="main"' : "") + ' file="' + escapeXml(f.deployed) + '">' +
      escapeXml(base + f.source) + "</source>";
  });
  const sources = [main].concat(o.files.filter((f) => f !== main)).map((f) => {
    const url = escapeXml(base + f.source);
    return f === main ? "        <source>" + url + "</source>"
                      : '        <source file="' + escapeXml(f.deployed) + '">' + url + "</source>";
  });
  return [
    '<?xml version="1.0" encoding="utf-8"?>',
    '<index version="1" name="' + INDEX_NAME + '">',
    '  <category name="' + CATEGORY + '">',
    '    <reapack name="' + MAIN + '" type="webinterface" desc="' + SUITE + ': remote pages for REAPER (home + all apps)">',
    "      <metadata>",
    "        <description><![CDATA[" + SUITE + " (LCRR): a suite of remote-control pages for REAPER's web interface, usable from a phone, tablet or desktop browser on the same LAN. After installing, choose lcrr.html as the Default interface in Preferences > Control/OSC/web.]]></description>",
    "      </metadata>",
    '      <version name="' + escapeXml(o.version) + '" author="' + escapeXml(o.author || "") + '" time="' + escapeXml(o.time) + '">',
    "        <changelog><![CDATA[" + String(o.changelog || "Release " + o.version).replace(/\]\]>/g, "]]]]><![CDATA[>") + "]]></changelog>",
    sources.concat(luaSources).join("\n"),
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

module.exports = { sliceRoots, collectFiles, collectLuaFiles, changelogFor, changelogProblems, releaseProblems, releaseNotes, buildIndexXml, installText, escapeXml, MAIN, SUITE, INDEX_NAME, CATEGORY };
