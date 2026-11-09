# Node + npm are copied from the official image instead of apt-installing Ubuntu's
# npm package (which drags in hundreds of packages). Keep the major version in sync
# with what the suite is tested on.
FROM node:22-bookworm-slim AS node

FROM mcr.microsoft.com/devcontainers/base:ubuntu

# Rarely-changing layers first so the Docker cache survives edits further down.
# Claude Code (installed once; run `claude update` or rebuild with --no-cache to refresh).
USER vscode
RUN curl -fsSL https://claude.ai/install.sh | bash

USER root

COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN ln -s ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
    && ln -s ../lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx

# Tools needed for development:
#  - python3: throwaway static server to smoke-test the page (python3 -m http.server)
#  - jq: inspect REAPER HTTP API responses (curl/ca-certificates are in the base image)
#  - lua5.4, lua-busted, lua-check: the arrange app's Lua (apps/arrange/), run by npm test / npm run check.
#    REAPER embeds Lua 5.4. lua-busted drags in lua5.1 and makes it the default `lua`, so the alternative is
#    pointed at 5.4; busted itself is pinned by apps/arrange/.busted (lua = "lua5.4"), guarded by
#    spec/toolchain_spec.lua. The checks fail the build rather than leave a broken toolchain looking fine.
RUN apt-get update \
    && apt-get install -y --no-install-recommends python3 jq lua5.4 lua-busted lua-check \
    && update-alternatives --set lua-interpreter /usr/bin/lua5.4 \
    && lua5.4 -e 'assert(_VERSION == "Lua 5.4")' \
    && busted --lua=lua5.4 --version >/dev/null \
    && luacheck --version >/dev/null \
    && rm -rf /var/lib/apt/lists/*

USER vscode
