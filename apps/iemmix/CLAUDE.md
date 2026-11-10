# IEM Mix

The engineer's page for balancing every in-ear mix at once: `lcrr-iemmix.html`. Read `CONTEXT.md` here, the suite `CONTEXT.md` (web API facts) and `.scratch/iemmix/spec.md` before changing behaviour.

Suite rules in `/CLAUDE.md` apply: work on `dev`, never `main`; **no Claude/Anthropic/AI co-author, trailer or attribution** in commits, docs or comments.

- Page only for now: no Lua, no `reaper/` slice. Reads and writes go through REAPER's web API. (Snapshots will use IEM Setup's bridge, later.)
- Pure logic in `www/lcrr/iemmix/js/core.js` (`LCRR.iemmix.core`) with tests in `test/`; DOM wiring in `iemmix.js`. IDs and classes use `iemmix-`. Shared look from `lcrr/shared/css/`; `DESIGN.md` is the design system.
- The mix listing rule and `dbText` are shared (`LCRR.shared.reaper`); `core.js` adds only this page's fields on top. The track and send parsers started as Monitor's and carry more (the track's `muted`, the send's `pan`).
- Every write goes through `canEdit` and `writeAllowed` (the shared fader's `check`); a control on a panel row registers its hold in `ref.parts[field]`. The level fader is `LCRR.shared.fader` (CSS `iemmix-fader*`); mute is `createMuteWriter`; pan is built in `iemmix.js` on the shared `createFaderDrag` and `fader.bindThumb`, with `core.js`'s `setPanCommand`, `panValue` and `panPos` injected (CSS `iemmix-pan*`).
- The wheel step is pure logic in `www/lcrr/iemmix/js/wheel.js` (`LCRR.iemmix.wheel.decide`), loaded after `core.js`; it writes through the shared fader's `nudge`, never around it. Level only, not pan.
