# 0001: Restore guards only mutes under writing automation, and reports automated values

## Context

A snapshot stores every value, automated or not, so a restore writes values that may sit under an envelope. The spike (suite `CONTEXT.md`) measured what a ReaScript write does there. `D_VOL` and `D_PAN` on a track and `D_VOL`, `D_PAN` and `B_MUTE` on a send added no points to any envelope in any mode. A track's `B_MUTE` added points to an existing Mute envelope in Touch, Write and Latch (own mode or global override), and in no other mode. Send mute envelopes were not measured.

## Decision

- Only mutes are guarded. A track's mute is skipped when it has a Mute envelope and its own `GetTrackAutomationMode` or `GetGlobalAutomationOverride` is 2, 3 or 4. A send's mute follows the same rule with the send's own `I_AUTOMODE` (-1 follows the track), as a precaution. Trim, Read, Latch Preview, override bypass and a track with no Mute envelope write normally. Levels, pans and everything else are always written.
- A send's envelope pointer always exists, so a send "has a Mute envelope" when `CountEnvelopePoints` > 0. An existing but empty send Mute envelope cannot be told from none, and is written.
- The guard covers tracks, the Master and sends. Hardware outputs are not guarded or counted: the spike did not look at their envelopes.
- The reply counts the written track and send volume, pan and mute values with active automation (the envelope exists, points > 0, `ACTIVE` is "1") as `automated`, and the skipped mutes as `muted_skipped`. Skipped mutes are not part of `skipped`, which is only what is gone from the project. A skipped mute is not counted as automated, since it is not written.
- The decision is made in the plan, before the undo block opens. A restore whose writes are all skipped mutes opens no undo block.
- The logic is the headless core `lib/core/automation.lua`, read-only; `snapshot_restore` asks it per value.

## Consequences

- Write mode recording envelopes from playing is the engineer's own setting and is not guarded.
- The note on the page says both counts in words (`words.js`), so a skipped mute is never silent.
- Send mute, send pan and width envelopes are for the live test (issue 10); if send mutes are found safe, the send rule can be dropped without touching the rest.
