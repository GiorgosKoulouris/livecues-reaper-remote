# 01. Bridge spike: ExtState over the web API, on real REAPER

Status: resolved
Type: prototype

Everything in `../spec.md` assumes a web page can talk to a background Lua script through ExtState. That has never been verified. This spike answers it with throwaway code before any migration starts.

## Questions
1. Does `GET/EXTSTATE/<section>/<key>` return what Lua `SetExtState` wrote? What is the exact reply line, and are tabs/newlines/backslashes escaped?
2. Does `SET/EXTSTATE/<section>/<key>/<value>` reach Lua's `GetExtState` byte-exact (URL-encoded `/`, `;`, `%`, `+`, `|`, newline, tab, UTF-8)?
3. How large can a reply value be (a JSON report), and how large can a request value be (URL length)?
4. What is the round-trip latency (page writes request → Lua answers → page reads)?
5. While Lua blocks the main thread (a long Apply), does the web server still answer, and what does it return?
6. What does `GET/EXTSTATE` return for a key that was never set? (This is how "bridge not running" will be detected.)

## How to run
Files are in `../spike/`.

1. Copy `lcrr-arrange-spike.html` into `%APPDATA%\REAPER\reaper_www_root\`.
2. Copy `LCRR_Arrange_SpikeBridge.lua` anywhere under `%APPDATA%\REAPER\Scripts\`, load it in the Action list (New action → Load ReaScript) and run it. The toolbar/action shows as running, and running it again stops it.
3. Open `http://<host>:<port>/lcrr-arrange-spike.html` in a browser (the desktop first, then the tablet if you can).
4. Press **Run all**. It takes roughly a minute. Press **Copy report** and paste the report into `## Answer` below (or into chat).
5. Stop the script, press **Run all** again, and paste the second, shorter report too. It shows the "bridge not running" behaviour.

Delete both files from REAPER afterwards.

## Answer

### Run 1, 2026-11-07, REAPER on Windows, Chrome 157 on localhost
1. **Reply format:** `EXTSTATE\t<section>\t<key>\t<value>\n`. REAPER **escapes** `\t`, `\n` and `\\` inside the value, so the page must unescape them (the `\\(t|n|\\)` → char mapping). Everything else, including UTF-8 and quotes, comes back as is.
2. **Requests:** `encodeURIComponent` values arrive byte-exact, including `/ ; % + | & # ?`, tab, newline, backslash and emoji.
3. **Size:** replies work up to at least 4 MB, at about 1 MB/s on localhost (64 KB in 157 ms). **Requests are silently truncated with HTTP 200**: a 1000-byte argument arrived as 966 bytes, which points to a ~1024-byte URL limit. So the protocol needs a declared length checked by Lua, and anything large must be sent in chunks. Run 2 pins the exact limit.
4. **Latency:** ~94 ms per round trip (min = median = max, so it's timer-quantized). A single GET takes 16 to 31 ms.
5. **Blocking:** inconclusive. The heartbeat kept advancing during the supposed 3 s block. Run 2 adds Lua timestamps.
6. **Missing key:** HTTP 200 with an empty value, which can't be told apart from an empty value. "Bridge running" must come from a heartbeat that changes.
- **Combined requests:** `SET/EXTSTATE/...;GET/EXTSTATE/...;TRANSPORT` works in one request. The GET in it sees the previous `res`, because Lua hasn't run yet. So the bridge can share the suite poller.
- Not yet tested: a tablet over Wi-Fi.

### Run 2, 2026-11-07, same setup plus a phone (the user reported it "seems ok"; no report pasted)
3. **Request limit, exact:** the limit is on the **encoded URL**. The longest request that arrived intact had a URL path of **1026 chars** (`/_/` included) in both cases: 966 ASCII chars, or 161 `é` (322 bytes, 6 URL chars each). Anything longer is cut at that point with HTTP 200 and no error.
5. **Blocking, explained:** REAPER handles web requests on the **main thread**. The `SET` that triggered a 3 s Lua block took **3064 ms** to answer, because the Lua picked up the request and blocked before REAPER sent the HTTP reply. Every request made during a block (`GET`, `TRANSPORT`, everything) waits until it ends. The heartbeat log confirms it: beat 89 was written at the block's end (`.521`), and nothing was written during it. Run 1's "heartbeat kept ticking" happened only because polling started after the SET returned.

### Consequences for the design (folded into `../spec.md`)
- Keep requests under ~900 encoded URL chars. Each request declares its length, and the bridge refuses a short one. Large payloads (phase 2) are sent in chunks.
- Requests don't carry the project path. Check returns a short **check token**, and the bridge keeps the project path and state-change count for it in memory. Apply sends only the token and the Headroom choice.
- A busy flag is useless while REAPER is blocked, because nothing can read it. The page knows an Apply is running from its own outstanding request. While that request is open, it shows "Applying…" instead of the shared guard's offline state and uses a long timeout. When the request returns (or the next GET answers), the Apply is over.
- Unescape replies (`\t`, `\n`, `\\`). Detect the bridge from the heartbeat changing, never from an empty value.
