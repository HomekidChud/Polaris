#!/usr/bin/env bash
# Build the obfuscated Polaris distribution.
#
# Pipeline:
#   1. prepare_lua51.py  - strips Luau type annotations + expands compound
#      assignments so the Lua 5.1 parser in Prometheus can read the source
#   2. Prometheus (github.com/prometheus-lua/Prometheus) with cfg-final.lua:
#      EncryptStrings, SplitStrings, ConstantArray (all constants, shuffled,
#      rotated), NumbersToExpressions (with representation mutation),
#      AntiTamper, AddVararg, WrapInFunction. Cff and Vmify are deliberately
#      excluded: they emit setfenv/getfenv-based code that cannot run in
#      Roblox Luau.
#   3. The full test suite is run against both the readable source and the
#      obfuscated artifact before anything is published.
#
# Usage: bash build/build.sh   (from the repo root)
set -euo pipefail
LUNE_BIN="${LUNE:-lune}"
cd "$(dirname "$0")/.."

if [ ! -d build/prometheus ]; then
	git clone --depth 1 https://github.com/prometheus-lua/Prometheus.git build/prometheus
fi

python3 build/prepare_lua51.py src/Polaris.luau build/intermediate.lua
(cd build/prometheus && lua5.1 cli.lua --config ../cfg-final.lua --out ../Polaris.obfuscated.lua ../intermediate.lua)

echo "-- verifying readable source"
"$LUNE_BIN" run tests/test.luau src/Polaris.luau | tail -1
echo "-- verifying obfuscated artifact"
cp build/Polaris.obfuscated.lua Polaris.luau
"$LUNE_BIN" run tests/test.luau | tail -1
echo "-- restoring readable source at root for now (git tracks src/)"
cp src/Polaris.luau Polaris.luau
echo "build ok - obfuscated artifact at build/Polaris.obfuscated.lua"
