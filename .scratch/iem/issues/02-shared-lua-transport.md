# 02. Move Arrange's bridge transport into shared Lua

Status: ready-for-agent
Blocked by: none

Move the generic bridge modules (JSON, request parsing, runner loop) out of `apps/arrange/reaper/Scripts/LCRR/arrange/lib/bridge/` so a second bridge can use them. Arrange's behaviour must not change.

## Notes

- `service.lua` is Arrange-specific and stays. Tokens stay unless IEM Setup turns out to need them.
- The suite defines a reaper slice as only `Scripts/LCRR/<app>/`. A shared slice extends that, so amend suite ADR-0001 and the `CONTEXT.md` term, and teach `scripts/install.ps1` about it (including `-Link` and uninstall).
- Arrange finds `lib/` beside each script through `get_action_context()`, and `spec/layout_spec.lua` guards it. Decide how scripts reach the shared folder and update the guard to match.

## Done when

- `npm test` and `npm run check` pass with every dialog transcript and the bridge contract fixture unchanged.
- The install script's new part is noted as unverified in `CONTEXT.md` until run on Windows.
