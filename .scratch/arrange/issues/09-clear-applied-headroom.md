# 09. Offer to clear the Headroom just applied

Status: done
Type: task
Blocked by: 07

Spec: `../spec.md`, "Phase 2", Headroom in the page. ADR-0007 stands.

## What to build
- After an Apply that actually applied Headroom (answer `apply` and a non-zero Headroom), the Run result offers "Clear the Headroom just applied". It sends the clear-Headroom edit for that Arrangement, revision-checked and undoable. Never automatic.

## Acceptance
- Node test on the reply → offer logic (no offer for `zero`, `cancelled`, or all-zero Headroom).

## Host check
- On `podium-dummy` (Arrangement `This` had +300 s on Outro): Check → Apply with Headroom → clear → the sidecar shows 0, and a second Check shows no Headroom question. This also covers HANDOFF's still-open "Headroom Apply through the page" check.

## Comments

Implemented in 7c27f38.
