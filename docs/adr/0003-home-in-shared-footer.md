# 0003. Home lives in a shared sticky footer, the same in every app

Date: 2026-11-07. Status: accepted.

## Context

Every app needs a way back to the home page. Podium's header is one tight sticky row of transport controls, and a stray tap there must not disrupt a show. Future apps may not have Podium's tab bar, so a placement tied to one app's layout would not carry over.

## Decision

- Every app page ends with the shared suite footer (`.lcrr-footer` in `lcrr/shared/css/base.css`): sticky at the bottom, slim (44 px, which is also the Home tap target), holding only a Home link to `lcrr.html`.
- Home is a plain tap, not a hold: it changes the page, not REAPER's transport, and Back undoes a mistake.
- The home page has no footer.
- Rejected: in the app's header (next to transport controls); the end of Podium's tab bar (not every app has one); a floating corner button (covers list rows); a footer at the end of the page (in a long list, Home would be out of reach).

## Consequences

- Every app gives up a 44 px strip at the bottom of the screen.
- A suite version or other suite items could join the footer later; for now it holds Home only.
