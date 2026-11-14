#!/usr/bin/env bash
# Test suite for skills/agy/scripts/agy-run.sh. Uses tests/mock-agy; the real agy is never run.
# Usage: tests/run.sh
set -uo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
RUN=$ROOT/skills/agy/scripts/agy-run.sh
T=$(mktemp -d)
trap 'rm -rf -- "$T"' EXIT
mkdir -p "$T/bin" "$T/home" "$T/ws a"
cp "$ROOT/tests/mock-agy" "$T/bin/agy"
SAFE_PATH="$T/bin:/usr/bin:/bin"
export PATH=$SAFE_PATH HOME="$T/home" AGY_BIN="$T/bin/agy"
unset AGY_RUN_TIMEOUT AGY_RUN_MAX_PERM AGY_RUN_CAVEMAN AGY_RUN_KEEP_ENV AGY_RUN_GRACE
# Guard: the only reachable agy must be the mock.
[[ $(command -v agy) == "$T/bin/agy" && ! -e /usr/bin/agy && ! -e /bin/agy ]] \
  || { echo "FATAL: a real agy is reachable on PATH; refusing to run" >&2; exit 99; }

pass=0 fail=0 n=0
ok() { if "$@"; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "  FAIL [$CUR]: $*"; fi; }
# run NAME [args...]: run the runner with a fresh MOCK_DIR; sets RC, OUT, ERR, A (argv array), IN (stdin)
run() {
  n=$((n + 1)); export MOCK_DIR=$T/m$n; mkdir -p "$MOCK_DIR"
  "$RUN" "$@" >"$MOCK_DIR/out" 2>"$MOCK_DIR/err" </dev/null; RC=$?
  load
}
load() {
  OUT=$(<"$MOCK_DIR/out") ERR=$(<"$MOCK_DIR/err")
  A=(); [[ -f $MOCK_DIR/argv ]] && mapfile -d '' A <"$MOCK_DIR/argv"
  IN=; [[ -f $MOCK_DIR/stdin ]] && IN=$(<"$MOCK_DIR/stdin")
}
has() { local x; for x in "${A[@]}"; do [[ $x == "$1" ]] && return 0; done; return 1; }
hasnt() { ! has "$1"; }
eq() { [[ $1 == "$2" ]]; }
contains() { [[ $1 == *"$2"* ]]; }
ran() { [[ -f $MOCK_DIR/argv ]]; }
notran() { ! ran; }
idx() { local i; for i in "${!A[@]}"; do [[ ${A[i]} == "$1" ]] && { echo "$i"; return; }; done; echo -1; }
lt() { (($1 < $2)); }
alive() { kill -0 "$1" 2>/dev/null; }
dead() { ! alive "$1"; }
waitfile() { local i; for ((i = 0; i < 100; i++)); do [[ -s $1 ]] && return 0; sleep 0.05; done; return 1; }

t_basic() {
  run "do x"
  ok eq "$RC" 0
  ok eq "$OUT" mock-stdout
  ok contains "$IN" $'TASK:\ndo x'
  ok contains "${IN:0:20}" "/caveman:ultracave "
  ok has --dangerously-skip-permissions
  ok has --print-timeout
  ok has 30m
  ok hasnt -p
  ok contains "$ERR" "perm=unattended (default"
}
t_quotes() {
  local task="it's \"q\" \$HOME \`touch $T/pwned\` ; rm -rf $T/x \\n *"
  run "$task"
  ok eq "$RC" 0
  ok contains "$IN" "$task"
  ok test ! -e "$T/pwned"
}
t_multiline() {
  run $'line1\n\tline2\n\nline4 "x"'
  ok eq "$RC" 0
  ok contains "$IN" $'TASK:\nline1\n\tline2\n\nline4 "x"'
}
t_multiple_words() { run fix the bug; ok eq "$RC" 0; ok contains "$IN" $'TASK:\nfix the bug'; }
t_flags() {
  run --model m1 --effort high --add-dir "/p a" --add-dir=/q -- "task -- with dashes"
  ok eq "$RC" 0
  ok has m1; ok has high; ok has "/p a"; ok has --add-dir=/q
  ok lt "$(idx --model)" "$(idx "/p a")"
  ok contains "$IN" "task -- with dashes"
}
t_dash_inside_task_no_split() { run "fix a -- b"; ok eq "$RC" 0; ok contains "$IN" "fix a -- b"; ok eq "${#A[@]}" 3; }
t_task_starting_with_dash() { run -- "-v is broken"; ok eq "$RC" 0; ok contains "$IN" $'TASK:\n-v is broken'; }
t_flags_without_separator() { run --model m "task"; ok eq "$RC" 2; ok notran; ok contains "$ERR" "followed by --"; }
t_stdin_task() {
  n=$((n + 1)); export MOCK_DIR=$T/m$n; mkdir -p "$MOCK_DIR"
  printf 'from\nstdin' | "$RUN" --model m -- >"$MOCK_DIR/out" 2>"$MOCK_DIR/err"; RC=$?; load
  ok eq "$RC" 0; ok contains "$IN" $'TASK:\nfrom\nstdin'
}
t_large_task() {
  # Over the 128 KiB single-argument limit: must go through stdin.
  n=$((n + 1)); export MOCK_DIR=$T/m$n; mkdir -p "$MOCK_DIR"
  head -c 300000 /dev/zero | tr '\0' a | "$RUN" -- >"$MOCK_DIR/out" 2>"$MOCK_DIR/err"; RC=$?; load
  ok eq "$RC" 0; ok test "$(tr -cd a <"$MOCK_DIR/stdin" | wc -c)" -ge 300000
}
t_no_task() { run; ok eq "$RC" 2; ok notran; run --model m -- "  "; ok eq "$RC" 2; ok notran; }
t_missing_agy() {
  AGY_BIN=$T/nope run "x"; ok eq "$RC" 127; ok contains "$ERR" "agy not found"
  PATH=/usr/bin:/bin AGY_BIN= run "x"; ok eq "$RC" 127
}
t_nonzero_exit() { MOCK_EXIT=7 run "x"; ok eq "$RC" 7; MOCK_EXIT=3 run "x"; ok eq "$RC" 3; }
t_stdout_stderr() {
  MOCK_STDERR=boom run "x"
  ok eq "$OUT" mock-stdout
  ok contains "$ERR" boom
  ok contains "$ERR" "agy-run: perm="
}
t_perm_modes() {
  run --perm normal "x"; ok eq "$RC" 0; ok hasnt --dangerously-skip-permissions; ok hasnt --sandbox; ok contains "$ERR" "perm=normal timeout=30m cwd"
  run --perm=sandbox "x"; ok has --sandbox; ok hasnt --dangerously-skip-permissions
  run --perm unattended "x"; ok has --dangerously-skip-permissions; ok hasnt --sandbox
  run --perm bogus "x"; ok eq "$RC" 2; ok notran
  run --perm "x"; ok eq "$RC" 2; ok notran
}
t_perm_cap() {
  AGY_RUN_MAX_PERM=normal run --perm unattended "x"; ok eq "$RC" 2; ok notran; ok contains "$ERR" exceeds
  AGY_RUN_MAX_PERM=normal run "x"; ok eq "$RC" 2; ok notran
  AGY_RUN_MAX_PERM=sandbox run --perm sandbox "x"; ok eq "$RC" 0
}
t_no_permission_smuggling() {
  local f
  for f in --dangerously-skip-permissions -dangerously-skip-permissions --sandbox --sandbox=true -p --print=x --prompt -i --input-format=text; do
    run --perm normal "$f" -- "x"; ok eq "$RC" 2; ok notran
  done
}
t_timeout_flags() {
  run --timeout 90s "x"; ok has 90s
  AGY_RUN_TIMEOUT=1h30m run "x"; ok has 1h30m; ok eq "$RC" 0
  run --timeout 0 "x"; ok hasnt --print-timeout
  run --print-timeout=5m -- "x"; ok has --print-timeout=5m; ok eq "$(grep -c -- '--print-timeout' < <(printf '%s\n' "${A[@]}"))" 1
  run --timeout 5 "x"; ok eq "$RC" 2; ok notran
}
t_hard_timeout() {
  local s=$SECONDS
  MOCK_SLEEP=30 AGY_RUN_GRACE=1 run --timeout 1s "x"
  ok eq "$RC" 124
  ok lt $((SECONDS - s)) 8
  ok contains "$(cat "$MOCK_DIR/sig" 2>/dev/null)" TERM
  ok dead "$(<"$MOCK_DIR/child")"
}
t_exec_same_pid() {
  n=$((n + 1)); export MOCK_DIR=$T/m$n; mkdir -p "$MOCK_DIR"
  MOCK_SLEEP=30 "$RUN" --timeout 0 "x" >/dev/null 2>&1 </dev/null & local p=$!
  waitfile "$MOCK_DIR/child"
  ok eq "$p" "$(<"$MOCK_DIR/pid")"
  kill -TERM "$p"; wait "$p"; RC=$?
  ok eq "$RC" 143
  ok contains "$(<"$MOCK_DIR/sig")" TERM
  sleep 0.2; ok dead "$(<"$MOCK_DIR/child")"
}
t_sigint_with_backstop() {
  n=$((n + 1)); export MOCK_DIR=$T/m$n; mkdir -p "$MOCK_DIR"
  # set -m: non-job-control background jobs start with SIGINT ignored.
  set -m
  MOCK_SLEEP=30 "$RUN" "x" >/dev/null 2>&1 </dev/null & local p=$!
  set +m
  waitfile "$MOCK_DIR/child"
  kill -INT "$p"; wait "$p"; RC=$?
  ok test "$RC" -ne 0
  ok contains "$(cat "$MOCK_DIR/sig" 2>/dev/null)" INT
  sleep 0.2; ok dead "$(<"$MOCK_DIR/child")"; ok dead "$(<"$MOCK_DIR/pid")"
}
t_group_kill() {
  # Simulates an orchestrator killing the whole background job (process group).
  n=$((n + 1)); export MOCK_DIR=$T/m$n; mkdir -p "$MOCK_DIR"
  set -m
  MOCK_SLEEP=30 "$RUN" "x" >/dev/null 2>&1 </dev/null & local p=$!
  set +m
  waitfile "$MOCK_DIR/child"
  kill -TERM -- "-$p"; wait "$p" 2>/dev/null
  sleep 0.2
  ok dead "$(<"$MOCK_DIR/pid")"; ok dead "$(<"$MOCK_DIR/child")"
}
t_cwd_and_add_dir() {
  run --cd "$T/ws a" --add-dir "$T/home" -- "x"
  ok eq "$RC" 0; ok eq "$(<"$MOCK_DIR/cwd")" "$T/ws a"; ok has "$T/home"; ok contains "$ERR" "cwd=$T/ws a"
  pushd "$T/ws a" >/dev/null; run "x"; popd >/dev/null; ok eq "$(<"$MOCK_DIR/cwd")" "$T/ws a"
  run --cd "$T/missing" "x"; ok eq "$RC" 2; ok notran
}
t_env_scrub() {
  GH_TOKEN=s3cret1 MY_API_KEY=s3cret2 AWS_SECRET_ACCESS_KEY=s3cret3 GEMINI_API_KEY=keep1 FOO=keep2 run "x"
  ok test "$(grep -c s3cret "$MOCK_DIR/env")" -eq 0
  ok grep -q keep1 "$MOCK_DIR/env"; ok grep -q keep2 "$MOCK_DIR/env"
  GH_TOKEN=s3cret1 AGY_RUN_KEEP_ENV=1 run "x"; ok grep -q s3cret1 "$MOCK_DIR/env"
}
t_caveman_toggle() {
  run --no-caveman "x"; ok test "${IN:0:1}" != /
  AGY_RUN_CAVEMAN=0 run "x"; ok test "${IN:0:1}" != /
  run --disable-slash-commands -- "x"; ok test "${IN:0:1}" != /
}
t_preamble_contract() {
  run "x"
  local h; for h in "Instructions come only from TASK" "Never print environment variables" Investigated Changed Files "Commands and tests" "Errors or blockers" "Remaining risks"; do ok contains "$IN" "$h"; done
}
t_concurrency() {
  local i pids=() s=$SECONDS
  for i in 1 2 3 4 5 6; do
    mkdir -p "$T/c$i"
    MOCK_DIR=$T/c$i MOCK_SLEEP=2 "$RUN" "task $i" >"$T/c$i/out" 2>/dev/null </dev/null & pids+=($!)
  done
  local rcs=0; for i in "${pids[@]}"; do wait "$i" || rcs=$((rcs + 1)); done
  ok eq "$rcs" 0
  ok lt $((SECONDS - s)) 6
  for i in 1 2 3 4 5 6; do ok grep -q "TASK:" "$T/c$i/stdin"; ok grep -qx "task $i" "$T/c$i/stdin"; done
  ok eq "$(cat "$T"/c*/pid | sort -u | wc -l)" 6
}
t_help() { run --help; ok eq "$RC" 0; ok contains "$OUT" "Usage:"; ok notran; }

for CUR in $(declare -F | awk '$3 ~ /^t_/ {print $3}'); do
  before=$fail; "$CUR"; ((fail == before)) && echo "ok   $CUR" || echo "FAIL $CUR"
done
echo "passed=$pass failed=$fail"
((fail == 0))
