#!/usr/bin/env node
// Local smoke-test server: serves all slices laid over each other, like REAPER's reaper_www_root.
//   npm run serve [-- --port 8081]
// REAPER is not reachable from here, so /_/ requests return 503 and the pages show their offline state.
// Never use 8080 in the devcontainer (it shadows REAPER on the host; see README).
"use strict";
const http = require("http");
const fs = require("fs");
const path = require("path");
const lib = require("./release-lib.js");

const repo = path.join(__dirname, "..");
const argv = process.argv.slice(2);
const port = Number(argv[argv.indexOf("--port") + 1]) || 8081;
const TYPES = { ".html": "text/html; charset=utf-8", ".css": "text/css", ".js": "text/javascript", ".svg": "image/svg+xml", ".png": "image/png", ".txt": "text/plain" };

http.createServer((req, res) => {
  const url = decodeURIComponent(req.url.split("?")[0]);
  if (url.startsWith("/_/")) { res.writeHead(503); return res.end(); }
  const want = url === "/" ? lib.MAIN : url.replace(/^\/+/, "");
  // Re-read the slices per request so new files show up without a restart.
  const hit = lib.collectFiles(repo).filter((f) => f.deployed === want)[0];
  if (!hit) { res.writeHead(404); return res.end("not found"); }
  res.writeHead(200, { "Content-Type": TYPES[path.extname(want)] || "application/octet-stream", "Cache-Control": "no-store" });
  fs.createReadStream(path.join(repo, hit.source)).pipe(res);
}).listen(port, () => console.log("serving the LCRR slices on http://localhost:" + port + "/"));
