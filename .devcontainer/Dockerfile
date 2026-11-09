FROM tcop-claude:latest

USER root

# Tools needed for development of Podium Remote:
#  - nodejs/npm: JS syntax checks, linting and unit tests for the browser code
#  - python3: throwaway static server to smoke-test the page (python3 -m http.server)
#  - curl/jq: poke at the REAPER HTTP API and inspect responses
RUN apt-get update \
    && apt-get install -y --no-install-recommends nodejs npm python3 curl jq ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Mount points for the fast docker volumes (see docker-compose.yml). Pre-creating
# them owned by vscode makes Docker seed the new volumes with correct ownership.
RUN mkdir -p /workspace/node_modules /home/vscode/.npm \
    && chown -R vscode:vscode /workspace/node_modules /home/vscode/.npm

USER vscode
