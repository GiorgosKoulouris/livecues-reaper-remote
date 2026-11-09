#!/bin/bash
# Runs on every container start. Idempotent and fast when nothing changed.
git config --global --add safe.directory /workspace

# Fast volumes may be root-owned if created before the image pre-created the mount points.
for d in /workspace/node_modules /home/vscode/.npm; do
  [ -w "$d" ] || sudo -n chown -R vscode:vscode "$d" 2>/dev/null || echo "warning: $d not writable"
done

# Install JS deps (into the node_modules volume) once a package.json exists.
if [ -f /workspace/package.json ]; then
  (cd /workspace && npm install --no-audit --no-fund)
fi
