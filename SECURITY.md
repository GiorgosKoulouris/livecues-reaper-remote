# Security

## Reporting a vulnerability

Please report security problems privately through [GitHub's vulnerability reporting](https://github.com/GiorgosKoulouris/livecues-reaper-remote/security/advisories/new), not in a public issue. Include the LCRR version, what you did, and what an attacker could gain.

LCRR is maintained by one person, so replies are best-effort. Fixes go into the latest release only.

## What LCRR protects, and what it doesn't

LCRR runs on REAPER's built-in web interface, on a network you trust. It's built for a stage or studio LAN, and these limits are by design:

- Anyone who can reach the page can control REAPER, unless you set a username and password in REAPER's web interface settings.
- REAPER serves the pages over plain HTTP, so traffic on the network isn't encrypted.
- Never expose the web interface port to the internet, including through port forwarding.
- Arrange and IEM Setup rely on Lua scripts running inside REAPER. They can change the open project.

Examples of what we'd like to hear about: a page or script that reaches beyond REAPER and its project, or anything that makes LCRR less safe than REAPER's web interface already is.
