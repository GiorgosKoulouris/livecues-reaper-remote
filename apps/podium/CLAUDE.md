# Podium

The stage transport and cue list, `lcrr-podium.html`. Before changing behaviour, read `apps/podium/CONTEXT.md` and the ADRs in `apps/podium/docs/adr/`; product intent is in `apps/podium/PRODUCT.md`.

- Product principle 1 overrides convenience: a stray touch must never start, cut or stop playback, or record. Anything new that acts on the transport needs a guard (hold, cooldown) and, if it reverses an earlier decision, an ADR here.
- Pure logic goes in `www/lcrr/podium/js/core.js` with tests in `test/`; DOM wiring in `podium.js`. Anything not Podium-specific belongs in `shared/` (see `shared/CLAUDE.md`).
- IDs and classes use the `podium-` prefix. Shared look comes from `lcrr/shared/css/`; `DESIGN.md` at the root is the design system.
- Design critique snapshots: `apps/podium/.impeccable/critique/` (historical; paths inside them predate the restructure).
