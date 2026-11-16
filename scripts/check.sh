#!/usr/bin/env bash
# Runs every automated check that works outside Roblox Studio.
# Requires the tools pinned in rokit.toml (rojo, stylua, lune) on PATH.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "== Format (stylua)"
stylua --check src tests map tools

echo "== Tests (lune)"
lune run tests/run

echo "== Place build and map checks (rojo + lune)"
lune run tools/build
