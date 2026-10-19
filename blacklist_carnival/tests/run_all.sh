#!/usr/bin/env bash
# Runs every automated check. Requires: lua5.4, lua-sql-mysql, lua-dkjson,
# a MySQL/MariaDB test database (see tests/README.md), Node 18+ (for NUI tests).
set -euo pipefail
cd "$(dirname "$0")/.."
echo "== Static checks";        lua5.4 tests/static_checks.lua
echo "== Server integration";   lua5.4 tests/server_spec.lua
echo "== NUI typecheck + tests"; (cd web && npx tsc -b --noEmit && npx vitest run)
