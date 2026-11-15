#!/usr/bin/env bash
# Smoke test against the REAL agy. Uses your agy login and model quota (two short turns).
# Run before a release, or after an agy update, to catch stream-json format changes.
# Usage: AGY_E2E=1 tests/e2e.sh
set -uo pipefail
[[ ${AGY_E2E:-} == 1 ]] || { echo "e2e: set AGY_E2E=1 to run against the real agy (uses your quota)" >&2; exit 2; }
command -v "${AGY_BIN:-agy}" >/dev/null || { echo "e2e: agy not found" >&2; exit 127; }

ROOT=$(cd "$(dirname "$0")/.." && pwd)
RUN=$ROOT/skills/agy/scripts/agy-run.sh
T=$(mktemp -d)
trap 'cd /; rm -rf -- "$T"' EXIT
mkdir -p "$T/ws" && echo hello >"$T/ws/a.txt"
export AGY_RUN_DIR=$T/runs AGY_RUN_UPDATE_CHECK=0
fail=0
check() { if "$@"; then echo "ok   $*"; else echo "FAIL $*"; fail=1; fi; }

"$RUN" --perm sandbox --timeout 3m --name e2e --cd "$T/ws" -- \
  "Read a.txt and report its exact content. Read-only." >"$T/out" 2>"$T/err"
rc=$?
r=$(echo "$AGY_RUN_DIR"/*/)
check test "$rc" -eq 0
check grep -qi hello "$T/out"
check grep -q '"event":"result"' "$r/events.ndjson"
check grep -q '"step_type":"tool"' "$r/events.ndjson"
check test -s "$r/conversation"
check test "$(cut -d' ' -f1 "$r/rc")" = 0
conv=$(<"$r/conversation")

# Follow-up in the same conversation must remember the first turn.
"$RUN" --perm sandbox --timeout 3m --name e2e-resume --cd "$T/ws" --conversation "$conv" -- \
  "Without reading any file again: what was the content you reported in your previous turn? One line." >"$T/out2" 2>"$T/err2"
check test "$?" -eq 0
check grep -qi hello "$T/out2"

out=$(NO_COLOR=1 "$ROOT/skills/agy/scripts/agy-top.sh" --once)
check grep -q e2e-resume <<<"$out"
((fail)) && { echo "--- stderr"; cat "$T/err" "$T/err2"; }
exit "$fail"
