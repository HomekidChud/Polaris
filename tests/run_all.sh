#!/usr/bin/env bash
# Run every test file against one Polaris build.  Usage: bash tests/run_all.sh [path/to/Polaris.luau]
set -uo pipefail
cd "$(dirname "$0")/.."
LUNE_BIN="${LUNE:-lune}"
TARGET="${1:-src/Polaris.luau}"
fail=0
for f in tests/test.luau tests/test_v2_*.luau tests/test_v3_*.luau; do
	out=$(timeout 180 "$LUNE_BIN" run "$f" "$TARGET" 2>&1)
	code=$?
	line=$(printf '%s\n' "$out" | grep -E "[0-9]+ passed, [0-9]+ failed" | tail -1)
	printf '%-34s %s\n' "$(basename "$f")" "${line:-NO RESULT}"
	if [ $code -ne 0 ] || ! printf '%s' "$line" | grep -q " 0 failed"; then
		fail=1
		printf '%s\n' "$out" | grep -E "FAIL" | head -10
	fi
done
exit $fail
