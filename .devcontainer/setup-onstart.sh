#!/bin/bash
# Runs on every container start. Keep it fast: the suite has no npm dependencies,
# so there is deliberately no `npm install` here.
git config --global --add safe.directory /workspace
