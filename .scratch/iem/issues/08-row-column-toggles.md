# 08. Row and column toggles

Status: ready-for-agent
Blocked by: 07

A control per row and per column. Bulk on is one tap; bulk off is press-and-hold. Each is one undo step. Requests carry only the mix or source ID, and the bridge works out the rest. Bulk on leaves existing sends alone.

## Done when

Specs cover both directions on a partly filled row and column. `npm test` and `npm run check` pass.
