#!/usr/bin/env bash
# Test suite for skills/agy/scripts/agy-run.sh. Uses tests/mock-agy; the real agy is never run.
# Usage: tests/run.sh
set -uo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
RUN=$ROOT/skills/agy/scripts/agy-run.sh
T=$(mktemp -d)
trap 'cd /; rm -rf -- "$T"' EXIT
mkdir -p "$T/bin" "$T/home" "$T/ws a"
cp "$ROOT/tests/mock-agy" "$T/bin/agy"
# git and curl through wrappers so PATH can stay minimal; the bash/timeout dirs cover Homebrew on macOS.
GIT=$(command -v git || true) CURL=$(command -v curl || true)
[[ -z $GIT ]] || printf '#!/usr/bin/env bash\nexec "%s" "$@"\n' "$GIT" >"$T/bin/git"
[[ -z $CURL ]] || printf '#!/usr/bin/env bash\nexec "%s" "$@"\n' "$CURL" >"$T/bin/curl"
chmod +x "$T/bin/"*
SAFE_PATH="$T/bin:$(dirname "$(command -v bash)"):$(dirname "$(command -v timeout || echo /usr/bin/x)"):/usr/bin:/bin"
export PATH=$SAFE_PATH HOME="$T/home" AGY_BIN="$T/bin/agy" AGY_RUN_UPDATE_CHECK=0 LC_ALL=C
unset WT_SESSION TMUX AGY_RUN_UI
unset AGY_RUN_TIMEOUT AGY_RUN_MAX_PERM AGY_RUN_CAVEMAN AGY_RUN_KEEP_ENV AGY_RUN_GRACE AGY_RUN_LOG AGY_RUN_DIR AGY_RUN_MAX_JOBS
# Guard: the only reachable agy must be the mock.
[[ $(type -ap agy) == "$T/bin/agy" ]] \
  || { echo "FATAL: a real agy is reachable on PATH; refusing to run" >&2; exit 99; }
# Outside any git repo, so the runner's git footer appears only where a test asks for it.
cd "$T"

pass=0 fail=0 n=0
ok() { if "$@"; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "  FAIL [$CUR]: $*"; fi; }
# run NAME [args...]: run the runner with a fresh MOCK_DIR; sets RC, OUT, ERR, A (argv array), IN (stdin)
run() {
  n=$((n + 1)); export MOCK_DIR=$T/m$n AGY_RUN_DIR=${RUNDIR:-$T/m$n/runs}; mkdir -p "$MOCK_DIR"
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
waitdead() { local i; for ((i = 0; i < 40; i++)); do kill -0 "$1" 2>/dev/null || return 0; sleep 0.05; done; }
waitfile() { local i; for ((i = 0; i < 100; i++)); do [[ -s $1 ]] && return 0; sleep 0.05; done; return 1; }

t_basic() {
  run "do x"
  ok eq "$RC" 0
  ok eq "$OUT" mock-stdout
  ok contains "$IN" $'TASK:\ndo x'
  ok contains "${IN:0:20}" "/caveman:ultracave "
  ok has --sandbox; ok hasnt --dangerously-skip-permissions
  ok has --print-timeout
  ok has 30m
  ok hasnt -p
  ok contains "$ERR" "perm=sandbox (default"
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
t_dash_inside_task_no_split() { run "fix a -- b"; ok eq "$RC" 0; ok contains "$IN" "fix a -- b"; ok eq "${#A[@]}" 5; }
t_task_starting_with_dash() { run -- "-v is broken"; ok eq "$RC" 0; ok contains "$IN" $'TASK:\n-v is broken'; }
t_flags_without_separator() { run --model m "task"; ok eq "$RC" 2; ok notran; ok contains "$ERR" "followed by --"; }
t_stdin_task() {
  n=$((n + 1)); export MOCK_DIR=$T/m$n AGY_RUN_DIR=${RUNDIR:-$T/m$n/runs}; mkdir -p "$MOCK_DIR"
  printf 'from\nstdin' | "$RUN" --model m -- >"$MOCK_DIR/out" 2>"$MOCK_DIR/err"; RC=$?; load
  ok eq "$RC" 0; ok contains "$IN" $'TASK:\nfrom\nstdin'
}
t_large_task() {
  # Over the 128 KiB single-argument limit: must go through stdin.
  n=$((n + 1)); export MOCK_DIR=$T/m$n AGY_RUN_DIR=${RUNDIR:-$T/m$n/runs}; mkdir -p "$MOCK_DIR"
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
  n=$((n + 1)); export MOCK_DIR=$T/m$n AGY_RUN_DIR=${RUNDIR:-$T/m$n/runs}; mkdir -p "$MOCK_DIR"
  AGY_RUN_LOG=0 MOCK_SLEEP=30 "$RUN" --timeout 0 "x" >/dev/null 2>&1 </dev/null & local p=$!
  waitfile "$MOCK_DIR/child"
  ok eq "$p" "$(<"$MOCK_DIR/pid")"
  kill -TERM "$p"; wait "$p"; RC=$?
  ok eq "$RC" 143
  ok contains "$(<"$MOCK_DIR/sig")" TERM
  waitdead "$(<"$MOCK_DIR/child")"; ok dead "$(<"$MOCK_DIR/child")"
}
t_sigint_with_backstop() {
  n=$((n + 1)); export MOCK_DIR=$T/m$n AGY_RUN_DIR=${RUNDIR:-$T/m$n/runs}; mkdir -p "$MOCK_DIR"
  # set -m: non-job-control background jobs start with SIGINT ignored.
  set -m
  MOCK_SLEEP=30 "$RUN" "x" >/dev/null 2>&1 </dev/null & local p=$!
  set +m
  waitfile "$MOCK_DIR/child"
  kill -INT "$p"; wait "$p"; RC=$?
  ok test "$RC" -ne 0
  ok contains "$(cat "$MOCK_DIR/sig" 2>/dev/null)" INT
  waitdead "$(<"$MOCK_DIR/child")"; ok dead "$(<"$MOCK_DIR/child")"; ok dead "$(<"$MOCK_DIR/pid")"
}
t_group_kill() {
  # Simulates an orchestrator killing the whole background job (process group).
  n=$((n + 1)); export MOCK_DIR=$T/m$n AGY_RUN_DIR=${RUNDIR:-$T/m$n/runs}; mkdir -p "$MOCK_DIR"
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
  GH_TOKEN=s3cret1 MY_API_KEY=s3cret2 AWS_SECRET_ACCESS_KEY=s3cret3 DATABASE_URL=postgres://u:s3cret4@h REDIS_URL=redis://:s3cret5@h SENTRY_DSN=s3cret6 OPENAI_KEY=s3cret7 GEMINI_API_KEY=keep1 FOO=keep2 run "x"
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
lastrun() { local d; for d in "$AGY_RUN_DIR"/*/; do R=${d%/}; done; }
t_runlog() {
  run --name "backend perf" --model gm1 -- "do x"
  ok eq "$RC" 0; ok eq "$OUT" mock-stdout
  ok has --output-format; ok has stream-json
  lastrun
  ok grep -qx "name=backend perf" "$R/meta"; ok grep -qx "model=gm1" "$R/meta"; ok grep -qx "perm=sandbox" "$R/meta"
  ok grep -q '"event":"init"' "$R/events.ndjson"
  ok eq "$(<"$R/report")" mock-stdout
  ok test "$(cut -d' ' -f1 "$R/rc")" = 0
  ok contains "$ERR" "log=$R"
  MOCK_EXIT=3 run "x"; lastrun; ok eq "$RC" 3; ok test "$(cut -d' ' -f1 "$R/rc")" = 3
}
t_runlog_off() {
  AGY_RUN_LOG=0 run "x"; ok eq "$RC" 0; ok hasnt stream-json; ok test -z "$(ls "$AGY_RUN_DIR" 2>/dev/null)"
  RUNDIR=/dev/null/nope run "x"; ok eq "$RC" 0; ok hasnt stream-json; ok contains "$ERR" "without it"
}
t_stream_unescape() {
  MOCK_RESPONSE='l1\n\"q\" back\\\\n tab\tendé \/x\n' run "x"
  ok eq "$OUT" $'l1\n"q" back\\\\n tab\tendé /x'
  MOCK_NO_RESULT=1 MOCK_RESPONSE='partial\n' run "x"; ok eq "$OUT" partial
}
t_output_format_passthrough() {
  run --output-format json -- "x"; ok eq "$OUT" mock-stdout; ok eq "$(grep -c stream-json < <(printf '%s\n' "${A[@]}"))" 0
  lastrun; ok eq "$(<"$R/report")" mock-stdout
}
t_top() {
  local TOP=$ROOT/skills/agy/scripts/agy-top.sh RUNDIR=$T/top
  run --name finished-one -- "x"
  MOCK_EXIT=1 MOCK_STDERR="invalid model selection" run --name broken -- "y"
  local dir=$AGY_RUN_DIR
  n=$((n + 1)); export MOCK_DIR=$T/m$n; mkdir -p "$MOCK_DIR"
  MOCK_SLEEP=30 "$RUN" --name live-one -- "z" >/dev/null 2>&1 </dev/null & local p=$!
  waitfile "$MOCK_DIR/child"; sleep 0.3
  local o; o=$(AGY_RUN_DIR=$dir NO_COLOR=1 COLUMNS=120 "$TOP" --once)
  kill -TERM "$p"; wait "$p" 2>/dev/null
  ok contains "$o" "1 running"; ok contains "$o" "1 done"; ok contains "$o" "1 failed"
  ok contains "$o" "RUNNING"; ok contains "$o" live-one; ok contains "$o" "run_command  npm test"
  ok contains "$o" "DONE"; ok contains "$o" finished-one
  ok contains "$o" "FAILED"; ok contains "$o" "exit 1"; ok contains "$o" "invalid model selection"
  ok test "$(printf '%s\n' "$o" | grep -n " RUNNING " | head -n1 | cut -d: -f1)" -lt "$(printf '%s\n' "$o" | grep -n " DONE " | head -n1 | cut -d: -f1)"
  ok test "$(awk '{ if (length($0) > m) m = length($0) } END { print m }' <<<"$o")" -le 120
  ok contains "$(AGY_RUN_DIR=$T/empty "$TOP" --once)" "No agy workers yet"
  AGY_RUN_DIR=$dir "$TOP" --bogus >/dev/null 2>&1; ok eq "$?" 2
}

TOP=$ROOT/skills/agy/scripts/agy-top.sh
FIX=$ROOT/tests/fixtures/agy-1.5.9-stream.ndjson
# bg NAME VAR [env...] -- args: start the runner in the background with its own MOCK_DIR; pid in VAR.
bg() {
  local _v=$1; shift
  n=$((n + 1)); export MOCK_DIR=$T/m$n; mkdir -p "$MOCK_DIR"
  env "$@" >"$MOCK_DIR/out" 2>"$MOCK_DIR/err" </dev/null &
  printf -v "$_v" '%s' "$!"
}
t_fixture_real_format() {
  MOCK_FIXTURE=$FIX run --name fx -- "x"
  ok eq "$RC" 0
  ok eq "${OUT%%$'\n'*}" "### Investigated"
  ok contains "$OUT" "∅ (read-only)."
  ok contains "$OUT" "### Remaining risks"
  ok contains "$ERR" "conversation=3477ae0f-4968-4662-bd9e-72dd1e134991"
  lastrun; ok grep -qx 3477ae0f-4968-4662-bd9e-72dd1e134991 "$R/conversation"
  local o; o=$(AGY_RUN_DIR=$AGY_RUN_DIR NO_COLOR=1 COLUMNS=120 "$TOP" --once)
  ok contains "$o" "run_command  Get-ChildItem -Force"; ok contains "$o" "20.5k tok"; ok contains "$o" "1 tool"
  ok contains "$o" "Directory files + count via PowerShell"
}
t_emoji() {
  LC_ALL=C.UTF-8 MOCK_RESPONSE='hi \ud83d\ude00 \u00e9 \\ud83d\n' run "x"
  ok eq "$OUT" 'hi 😀 é \ud83d'
}
t_blocked() {
  run "x"; ok contains "$IN" 'BLOCKED: <one question>'
  MOCK_RESPONSE='BLOCKED: which database, postgres or sqlite?\n' run --name bq -- "x"
  local o; o=$(AGY_RUN_DIR=$AGY_RUN_DIR NO_COLOR=1 "$TOP" --once)
  ok contains "$o" "BLOCKED"; ok contains "$o" "1 blocked"; ok contains "$o" "which database"
}
t_git_footer() {
  [[ -x $T/bin/git ]] || { echo "  skip: no git"; return; }
  local r=$T/repo
  mkdir -p "$r" && git -C "$r" init -q && git -C "$r" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  echo old >"$r/old.txt"
  MOCK_TOUCH=$r/new.txt run --cd "$r" -- "x"
  ok contains "$OUT" "Git changes in this directory since the worker started"
  ok contains "$OUT" " new file: new.txt"
  ok test "$(grep -c 'old.txt' <<<"$OUT")" -eq 0
  lastrun; ok contains "$(<"$R/report")" " new file: new.txt"
  run --cd "$r" -- "x"; ok contains "$OUT" $'includes changes by anything else working here):\nnone'
  run --cd "$r" --output-format json -- "x"; ok eq "$OUT" mock-stdout
  run "x"; ok eq "$OUT" mock-stdout   # not a repo: no footer
}
t_job_slots() {
  local d=$T/slots a b s=$SECONDS o
  bg a AGY_RUN_DIR="$d" AGY_RUN_MAX_JOBS=1 MOCK_SLEEP=30 "$RUN" --name first -- "a"
  local ma=$MOCK_DIR; waitfile "$ma/child"
  bg b AGY_RUN_DIR="$d" AGY_RUN_MAX_JOBS=1 "$RUN" --name second -- "b"
  local mb=$MOCK_DIR
  local i; for ((i = 0; i < 100; i++)); do compgen -G "$d/*/queued" >/dev/null && break; sleep 0.05; done
  ok test -n "$(compgen -G "$d/*/queued")"
  ok notran_in "$mb"
  o=$(AGY_RUN_DIR=$d NO_COLOR=1 "$TOP" --once)
  ok contains "$o" "QUEUED"; ok contains "$o" "1 queued"; ok contains "$o" "1 running"
  kill -TERM "$a"; wait "$a" 2>/dev/null
  wait "$b"; ok eq "$?" 0
  ok contains "$(<"$mb/err")" "waiting for a free slot"
  ok test -z "$(compgen -G "$d/*/queued")"
  ok lt $((SECONDS - s)) 15
  ok test ! -e "$d/.slots/1"
  # a slot left by a dead owner is reclaimed
  mkdir -p "$d/.slots/1"; echo 999999 >"$d/.slots/1/pid"
  AGY_RUN_MAX_JOBS=1 RUNDIR=$d run "x"; ok eq "$RC" 0
  AGY_RUN_MAX_JOBS=x run "x"; ok eq "$RC" 2
}
notran_in() { [[ ! -f $1/argv ]]; }
t_update_notice() {
  local d=$T/upd; mkdir -p "$d"
  echo 99.0.0 >"$d/.latest-version"; : >"$d/.update-checked"
  AGY_RUN_UPDATE_CHECK=1 RUNDIR=$d run "x"; ok contains "$ERR" "agy-subagent 99.0.0 is available"; ok contains "$ERR" "claude plugin update agy@agy-subagent"
  echo 0.0.1 >"$d/.latest-version"
  AGY_RUN_UPDATE_CHECK=1 RUNDIR=$d run "x"; ok test "$(grep -c 'is available' <<<"$ERR")" -eq 0
  AGY_RUN_UPDATE_CHECK=0 RUNDIR=$d run "x"; ok test "$(grep -c 'is available' <<<"$ERR")" -eq 0
  # stale stamp: background fetch refreshes the cached version
  command -v curl >/dev/null || { echo "  skip: no curl"; return; }
  printf '{\n  "name": "agy",\n  "version": "7.1.0"\n}\n' >"$T/remote.json"
  touch -d '2 days ago' "$d/.update-checked" 2>/dev/null || touch -t 200001010000 "$d/.update-checked"
  local u=$T/remote.json; command -v cygpath >/dev/null && u=/$(cygpath -m "$u")   # Windows curl wants C:/...
  AGY_RUN_UPDATE_CHECK=1 AGY_RUN_UPDATE_URL="file://$u" RUNDIR=$d run "x"
  local i; for ((i = 0; i < 100; i++)); do [[ $(<"$d/.latest-version") == 7.1.0 ]] && break; sleep 0.05; done
  ok eq "$(<"$d/.latest-version")" 7.1.0
}
t_top_interactive() {
  local d=$T/ti p o
  bg p AGY_RUN_DIR="$d" MOCK_SLEEP=30 "$RUN" --name live -- "z"
  local m=$MOCK_DIR; waitfile "$m/child"
  printf 'jkxyq' >"$T/keys"
  timeout 20 env AGY_RUN_DIR="$d" AGY_TOP_INPUT="$T/keys" NO_COLOR=1 COLUMNS=100 LINES=30 "$TOP" >"$T/top.out" 2>&1
  ok eq "$?" 0
  ok contains "$(<"$T/top.out")" 'Stop worker "live"? y/n'
  wait "$p"; ok eq "$?" 143
  o=$(AGY_RUN_DIR=$d NO_COLOR=1 "$TOP" --once); ok contains "$o" "STOPPED"; ok contains "$o" "exit 143"
  AGY_TOP_INPUT=$T/missing timeout 5 "$TOP" >/dev/null 2>&1; ok eq "$?" 2
}
t_top_here() {
  local d=$T/here
  RUNDIR=$d run --cd "$T/ws a" --name in-ws -- "x"
  RUNDIR=$d run --cd "$T/home" --name in-home -- "y"
  local o; o=$(cd "$T/ws a" && AGY_RUN_DIR=$d NO_COLOR=1 "$TOP" --once --here)
  ok contains "$o" in-ws; ok test "$(grep -c in-home <<<"$o")" -eq 0
  o=$(AGY_RUN_DIR=$d NO_COLOR=1 "$TOP" --once --in "$T/home"); ok contains "$o" in-home; ok test "$(grep -c in-ws <<<"$o")" -eq 0
  "$TOP" --once --in "$T/nope" >/dev/null 2>&1; ok eq "$?" 2
}

t_big_tool_output() {
  # 3 MB of tool output in one line: bash must never read it byte by byte.
  local s=$SECONDS o
  MOCK_BIG=3000000 run --name big -- "x"
  ok eq "$RC" 0; ok eq "$OUT" mock-stdout
  ok lt $((SECONDS - s)) 8
  lastrun; ok test "$(wc -c <"$R/events.ndjson")" -gt 3000000
  s=$SECONDS
  o=$(AGY_RUN_DIR=$AGY_RUN_DIR NO_COLOR=1 COLUMNS=100 "$TOP" --once)
  ok lt $((SECONDS - s)) 5
  ok contains "$o" "view_file  big.log"
}
t_stop_queued() {
  local d=$T/sq a b
  bg a AGY_RUN_DIR="$d" AGY_RUN_MAX_JOBS=1 MOCK_SLEEP=30 "$RUN" -- "a"
  waitfile "$MOCK_DIR/child"
  bg b AGY_RUN_DIR="$d" AGY_RUN_MAX_JOBS=1 "$RUN" --name waiting -- "b"
  local i q=; for ((i = 0; i < 100; i++)); do q=$(compgen -G "$d/*/queued") && break; sleep 0.05; done
  ok test -n "$q"
  kill -TERM "$b"; wait "$b"; ok eq "$?" 143
  ok test ! -e "$q"
  ok eq "$(cut -d' ' -f1 "${q%/queued}/rc")" 143
  o=$(AGY_RUN_DIR=$d NO_COLOR=1 "$TOP" --once); ok contains "$o" "STOPPED"; ok contains "$o" "exit 143"
  kill -TERM "$a"; wait "$a" 2>/dev/null
}
t_slot_pid_reused() {
  [[ -r /proc/$$/cmdline ]] || { echo "  skip: no /proc"; return; }
  local d=$T/reuse; mkdir -p "$d/.slots/1"
  sleep 30 & local other=$!
  echo "$other" >"$d/.slots/1/pid"   # alive, but not an agy runner
  local s=$SECONDS
  AGY_RUN_MAX_JOBS=1 RUNDIR=$d run "x"
  ok eq "$RC" 0; ok lt $((SECONDS - s)) 5
  kill "$other" 2>/dev/null; wait "$other" 2>/dev/null
}
t_top_counts_and_prefix() {
  local d=$T/cp
  RUNDIR=$d run --cd "$T/ws a" --name recent -- "x"
  RUNDIR=$d run --cd "$T/ws a" --name ancient -- "x"
  lastrun; sed -i "s/^start=.*/start=1000/" "$R/meta"
  local o; o=$(AGY_RUN_DIR=$d NO_COLOR=1 "$TOP" --once)
  ok contains "$o" "1 done"; ok test "$(grep -c ancient <<<"$o")" -eq 0
  o=$(AGY_RUN_DIR=$d NO_COLOR=1 "$TOP" --once --all); ok contains "$o" "2 done"; ok contains "$o" ancient
  local p=$T/pfx; mkdir -p "$p/app" "$p/apple" "$p/app-agy-x"
  RUNDIR=$p/runs run --cd "$p/app" --name in-app -- "x"
  RUNDIR=$p/runs run --cd "$p/apple" --name in-apple -- "x"
  RUNDIR=$p/runs run --cd "$p/app-agy-x" --name in-worktree -- "x"
  o=$(AGY_RUN_DIR=$p/runs NO_COLOR=1 "$TOP" --once --in "$p/app")
  ok contains "$o" in-app; ok contains "$o" in-worktree; ok test "$(grep -c in-apple <<<"$o")" -eq 0
}

# --- AGY Control Center ---
# top_keys DIR KEYS [env...]: run the interactive dashboard with KEYS as input; output in $T/top.out.
top_keys() {
  local d=$1 keys=$2; shift 2
  printf '%b' "$keys" >"$T/keys"
  timeout 30 env "$@" AGY_RUN_DIR="$d" AGY_TOP_INPUT="$T/keys" NO_COLOR=1 COLUMNS=120 LINES=40 "$TOP" >"$T/top.out" 2>&1
}
t_cc_render() {
  [[ -x $T/bin/git ]] || { echo "  skip: no git"; return; }
  local r=$T/ccrepo d=$T/ccruns o
  mkdir -p "$r" && git -C "$r" init -q -b feature-x 2>/dev/null || { git -C "$r" init -q && git -C "$r" checkout -q -b feature-x; }
  git -C "$r" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  RUNDIR=$d run --cd "$r" --name auditor --model gm1 -- "ROLE: Security Auditor OBJECTIVE: find bugs in src/auth"
  MOCK_RESPONSE='BLOCKED: postgres or sqlite?\n' RUNDIR=$d run --cd "$r" --name asker -- "x"
  MOCK_EXIT=1 MOCK_STDERR="invalid model selection" RUNDIR=$d run --cd "$r" --name crasher -- "x"
  o=$(cd "$r" && AGY_RUN_DIR=$d AGY_RUN_MAX_JOBS=3 NO_COLOR=1 COLUMNS=120 "$TOP" --once --here)
  ok contains "$o" "AGY CONTROL CENTER"; ok contains "$o" "ccrepo"; ok contains "$o" "feature-x"
  ok contains "$o" "slots 0/3"
  ok contains "$o" " WORKERS"; ok contains "$o" " DETAIL"; ok contains "$o" " EVENTS"
  ok contains "$o" "1 done"; ok contains "$o" "1 blocked"; ok contains "$o" "1 failed"
  ok contains "$o" "Security Auditor"; ok contains "$o" "BLOCKED"; ok contains "$o" "postgres or sqlite?"
  ok contains "$o" "exit 1  invalid model selection"
  ok contains "$o" "conversation c1"
  ok test "$(awk '{ if (length($0) > m) m = length($0) } END { print m }' <<<"$o")" -le 120
}
t_cc_keys() {
  local d=$T/cck o
  RUNDIR=$d run --name first -- "a"
  RUNDIR=$d run --name second -- "b"
  # newest first: "second" is selected; j moves to "first"; ? shows help; x on a finished run does nothing
  top_keys "$d" 'j?xq'
  ok eq "$?" 0
  o=$(<"$T/top.out")
  ok contains "$o" "DETAIL  second"; ok contains "$o" "DETAIL  first"
  ok contains "$o" " KEYS"; ok contains "$o" "q              detach"
  ok test "$(grep -c 'Stop worker' <<<"$o")" -eq 0
  ok test -z "$(compgen -G "$d/.dashboards/[0-9]*")"   # registry cleaned on exit
}
t_cc_stop_cancel_and_detach() {
  local d=$T/ccd p o
  bg p AGY_RUN_DIR="$d" MOCK_SLEEP=30 "$RUN" --name keeper -- "z"
  local m=$MOCK_DIR; waitfile "$m/child"
  top_keys "$d" 'xnq'      # ask to stop, answer no, detach
  ok eq "$?" 0
  ok contains "$(<"$T/top.out")" 'Stop worker "keeper"? y/n'
  ok alive "$p"            # neither "n" nor quitting stopped the worker
  kill -TERM "$p"; wait "$p" 2>/dev/null
}
t_cc_resume() {
  local d=$T/ccr i o
  RUNDIR=$d run --name origin --model gm2 -- "first task"
  top_keys "$d" 'rplease also check reset.py\nq'
  ok eq "$?" 0
  ok contains "$(<"$T/top.out")" 'Resumed "origin"'
  local r=; for ((i = 0; i < 100; i++)); do r=$(grep -l '^name=origin+$' "$d"/*/meta 2>/dev/null) && [[ -f ${r%/meta}/rc ]] && break; sleep 0.1; done
  ok test -n "$r"
  ok grep -qx 'task=please also check reset.py' "$r"
  ok grep -qx 'model=gm2' "$r"
  # finished-only: resume on a running worker only explains
  local p; bg p AGY_RUN_DIR="$d" MOCK_SLEEP=30 "$RUN" --name busy -- "z"
  waitfile "$MOCK_DIR/child"
  top_keys "$d" 'rq'
  ok contains "$(<"$T/top.out")" "Resume works on finished workers"
  kill -TERM "$p"; wait "$p" 2>/dev/null
}
t_cc_queue_transition() {
  local d=$T/ccq a b
  bg a AGY_RUN_DIR="$d" AGY_RUN_MAX_JOBS=1 MOCK_SLEEP=30 "$RUN" --name holder -- "a"
  waitfile "$MOCK_DIR/child"
  bg b AGY_RUN_DIR="$d" AGY_RUN_MAX_JOBS=1 MOCK_SLEEP=3 "$RUN" --name waiter -- "b"
  local i; for ((i = 0; i < 100; i++)); do compgen -G "$d/*/queued" >/dev/null && break; sleep 0.05; done
  # keys arrive through a FIFO, so the dashboard keeps running while the queue moves
  rm -f "$T/kf"; mkfifo "$T/kf" || { echo "  skip: no mkfifo"; kill "$a" "$b"; return; }
  ( exec 7>"$T/kf"; sleep 2; kill -TERM "$a"; sleep 3; printf q >&7 ) &
  local feeder=$!
  timeout 30 env AGY_RUN_DIR="$d" AGY_TOP_INPUT="$T/kf" NO_COLOR=1 COLUMNS=120 LINES=40 "$TOP" >"$T/top.out" 2>&1
  ok eq "$?" 0
  wait "$feeder"; wait "$a" 2>/dev/null; wait "$b" 2>/dev/null
  local o; o=$(<"$T/top.out")
  ok contains "$o" "QUEUED"; ok contains "$o" "waiting for a free slot"
  ok contains "$o" "@ running"        # queued -> running observed live
  ok contains "$o" "STOPPED"          # the holder
}
t_cc_large_and_partial_events() {
  local d=$T/ccl s=$SECONDS o
  RUNDIR=$d run --name big -- "x"
  lastrun
  # 5000 streamed text deltas (as Claude models send) plus a half-written record at the end
  {
    for ((i = 0; i < 5000; i++)); do printf '{"event":"step_update","step_update":{"step_index":9,"state":"ACTIVE","step_type":"agent_response","text_delta":"w%d "}}\n' "$i"; done
    printf '{"event":"step_update","step_update":{"step_index":10,"state":"DONE","step_type":"tool","tool_name":"grep_search","duration_seconds":0.3,"tool_info":{"name":"grep_search","parameters":{"Query":"needle"}}}}\n'
    printf '{"event":"step_update","step_update":{"step_index":11,"sta'
  } >>"$R/events.ndjson"
  s=$SECONDS
  o=$(AGY_RUN_DIR=$d NO_COLOR=1 COLUMNS=120 "$TOP" --once)
  ok lt $((SECONDS - s)) 6
  ok contains "$o" "grep_search  needle"
  ok contains "$o" "2 tools"
}
t_cc_ui_hook() {
  # AGY_RUN_UI=1 without Windows Terminal or tmux: one instruction on stderr, worker runs, stdout clean
  AGY_RUN_UI=1 run --name ui -- "x"
  ok eq "$RC" 0; ok eq "$OUT" mock-stdout
  ok contains "$ERR" "no Windows Terminal or tmux session found"; ok contains "$ERR" "agy-top.sh"
  # with a (fake) Windows Terminal: the launcher builds the split-pane command, stdout stays clean
  printf '#!/usr/bin/env bash\nprintf "%%s\\0" "$@" >"$WT_ARGS"\n' >"$T/bin/wt.exe"; chmod +x "$T/bin/wt.exe"
  printf '#!/usr/bin/env bash\n[[ $1 == -m ]] && shift; printf "W:%%s\\n" "${1%%/}"\n' >"$T/bin/cygpath"; chmod +x "$T/bin/cygpath"
  WT_SESSION=x WT_ARGS=$T/wtargs AGY_RUN_UI=1 RUNDIR=$T/uib run --name ui2 -- "x"
  ok eq "$RC" 0; ok eq "$OUT" mock-stdout
  local -a w=(); mapfile -d '' w <"$T/wtargs" 2>/dev/null
  ok contains "${w[*]}" "split-pane"; ok contains "${w[*]}" "AGY Control Center"; ok contains "${w[*]}" "move-focus previous"
  # a second runner while the launch lock is fresh does not open a second pane
  rm -f "$T/wtargs"
  WT_SESSION=x WT_ARGS=$T/wtargs AGY_RUN_UI=1 RUNDIR=$T/uib run --name ui3 -- "x"
  ok test ! -e "$T/wtargs"
  rm -f "$T/bin/wt.exe" "$T/bin/cygpath"
  # default stays off
  WT_SESSION=x run "x"; ok test "$(grep -c 'agy-ui' <<<"$ERR")" -eq 0
}
t_ui_launcher_suite() {
  local out; out=$(bash "$ROOT/tests/test-ui.sh" 2>&1); local rc=$?
  ok eq "$rc" 0
  [[ $rc == 0 ]] || printf '%s\n' "$out" | grep -i fail | head -n 10
}

for CUR in $(declare -F | awk '$3 ~ /^t_/ {print $3}'); do
  before=$fail; "$CUR"; ((fail == before)) && echo "ok   $CUR" || echo "FAIL $CUR"
done
echo "passed=$pass failed=$fail"
((fail == 0))
