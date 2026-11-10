# 10. Adopt a stray mix

Status: ready-for-agent
Blocked by: 04, 07

An `IEM_` track outside the folder shows an **Adopt** button. As one undo step: move it to the end of the folder (creating the folder if needed), turn master send off, apply the shared colour, convert all its sends to post-FX pre-fader. An adopted track with several outputs keeps them, shown read-only.

## Done when

Specs cover adopting with and without an existing folder, sends in each mode, and a track with several outputs. `npm test` and `npm run check` pass.
