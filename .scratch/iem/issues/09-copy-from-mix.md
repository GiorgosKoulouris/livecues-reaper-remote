# 09. Create a mix by copying another

Status: ready-for-agent
Blocked by: 07

An optional "copy from" on Create. The new mix receives the same sources with the same levels, pans, mutes and signal points, as one undo step with the creation. The output is not copied.

## Done when

Specs cover the copied fields, the output being left unset, and a source mix that has gone. `npm test` and `npm run check` pass.
