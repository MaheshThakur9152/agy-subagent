#!/usr/bin/env bash
# tests/test-ui.sh: test suite for skills/agy/scripts/agy-ui.sh
# Usage: bash tests/test-ui.sh
set -uo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
UI=$ROOT/skills/agy/scripts/agy-ui.sh
TOP=$ROOT/skills/agy/scripts/agy-top.sh
T=$(mktemp -d)
trap 'cd /; rm -rf -- "$T"' EXIT

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
pass=0 fail=0 CUR=
ok() { if "$@"; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "  FAIL [$CUR]: $*"; fi; }
contains() { [[ $1 == *"$2"* ]]; }
eq()       { [[ $1 == "$2" ]]; }

# A fake wt.exe: records NUL-separated argv to $FAKE_ARGV_FILE, exits with ${FAKE_RC:-0}
mkdir -p "$T/fakebin"
cat >"$T/fakebin/wt.exe" <<'FAKE_WT'
#!/usr/bin/env bash
printf '%s\0' "$@" >"${FAKE_ARGV_FILE:-/tmp/wt-argv}"
exit "${FAKE_RC:-0}"
FAKE_WT

# A fake cygpath: -m <path> → W:<path>; -m / → W:/
cat >"$T/fakebin/cygpath" <<'FAKE_CP'
#!/usr/bin/env bash
# Only handle -m flag
shift  # drop -m
arg=$1
if [[ $arg == / ]]; then
  echo "W:/"
else
  echo "W:${arg}"
fi
FAKE_CP

# A fake tmux: records NUL-separated argv
cat >"$T/fakebin/tmux" <<'FAKE_TMUX'
#!/usr/bin/env bash
printf '%s\0' "$@" >"${FAKE_ARGV_FILE:-/tmp/tmux-argv}"
exit "${FAKE_RC:-0}"
FAKE_TMUX

chmod +x "$T/fakebin/wt.exe" "$T/fakebin/cygpath" "$T/fakebin/tmux"

# Directories from real tools we still need
BASH_DIR=$(dirname "$(command -v bash)")
GIT=$(command -v git 2>/dev/null || true)
GIT_DIR=$(dirname "$GIT" 2>/dev/null || echo /usr/bin)

# If git is missing, we skip git-dependent tests
HAS_GIT=0
[[ -n $GIT ]] && HAS_GIT=1

# Build a git wrapper in fakebin so git is reachable in the minimal PATH
if [[ $HAS_GIT -eq 1 ]]; then
  printf '#!/usr/bin/env bash\nexec "%s" "$@"\n' "$GIT" >"$T/fakebin/git"
  chmod +x "$T/fakebin/git"
fi

# timeout wrapper
TIMEOUT_BIN=$(command -v timeout 2>/dev/null || true)
if [[ -n $TIMEOUT_BIN ]]; then
  printf '#!/usr/bin/env bash\nexec "%s" "$@"\n' "$TIMEOUT_BIN" >"$T/fakebin/timeout"
  chmod +x "$T/fakebin/timeout"
fi

# find, mkdir, rm, grep etc. are in /usr/bin or /bin; we include those in PATH.
SAFE_PATH="$T/fakebin:$BASH_DIR:/usr/bin:/bin"

# Base env: unset session vars; each test sets what it needs
_run_ui() {
  # _run_ui [env_overrides] -- [ui_args]
  # Sets RC, OUT, ERR, ARGV_FILE in caller
  ARGV_FILE=$T/argv-$$-$RANDOM
  local env_part=() ui_args=()
  local in_ui=0
  for arg in "$@"; do
    if [[ $arg == -- ]]; then in_ui=1; continue; fi
    if [[ $in_ui -eq 1 ]]; then ui_args+=("$arg"); else env_part+=("$arg"); fi
  done
  local err_f=$T/err-$$-$RANDOM out_f=$T/out-$$-$RANDOM
  RC=0
  env -i \
    PATH="$SAFE_PATH" \
    HOME="$T/home" \
    AGY_RUN_DIR="$AGY_RUN_DIR" \
    BASH="$BASH" \
    "${env_part[@]}" \
    FAKE_ARGV_FILE="$ARGV_FILE" \
    bash "$UI" "${ui_args[@]}" \
    >"$out_f" 2>"$err_f" </dev/null || RC=$?
  OUT=$(<"$out_f"); ERR=$(<"$err_f")
  rm -f "$out_f" "$err_f"
}

_load_argv() {
  ARGS=()
  [[ -f $ARGV_FILE ]] && mapfile -d '' ARGS <"$ARGV_FILE" || true
}

has_arg() {
  local a
  for a in "${ARGS[@]}"; do [[ $a == "$1" ]] && return 0; done
  return 1
}

# Create a minimal git repo for tests
_make_repo() {
  local d=$1
  mkdir -p "$d"
  if [[ $HAS_GIT -eq 1 ]]; then
    git -C "$d" init -q
    git -C "$d" -c user.email=t@t -c user.name=t commit --allow-empty -q -m init
  fi
}

export HOME="$T/home"
mkdir -p "$T/home"

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

AGY_RUN_DIR=$T/runs; export AGY_RUN_DIR

CUR="WT args"
{
  mkdir -p "$T/repo-wt"
  _make_repo "$T/repo-wt"
  rm -rf "$AGY_RUN_DIR/.ui-lock"
  mkdir -p "$AGY_RUN_DIR/.dashboards"
  _run_ui WT_SESSION=x -- --dir "$T/repo-wt"
  _load_argv
  ok eq "$RC" 0
  ok has_arg "-w"
  ok has_arg "0"
  ok has_arg "split-pane"
  ok has_arg "-V"
  ok has_arg "--title"
  ok has_arg "AGY Control Center"
  ok has_arg "-d"
  ok has_arg "--login"
  # wdir should be W:-prefixed
  _found_wdir=0
  for _a in "${ARGS[@]}"; do [[ $_a == W:* && $_a != W:*/agy-top* ]] && { _found_wdir=1; break; }; done
  ok eq "$_found_wdir" "1"
  # wtop should be W:-prefixed and contain agy-top
  _found_wtop=0
  for _a in "${ARGS[@]}"; do [[ $_a == W:*agy-top* ]] && { _found_wtop=1; break; }; done
  ok eq "$_found_wtop" "1"
  ok has_arg "--in"
  ok has_arg ";"
  ok has_arg "move-focus"
  ok has_arg "previous"
}

CUR="WT failure"
{
  rm -f "$ARGV_FILE" 2>/dev/null || true
  rm -rf "$AGY_RUN_DIR/.ui-lock"
  mkdir -p "$AGY_RUN_DIR/.dashboards"
  _run_ui WT_SESSION=x FAKE_RC=5 -- --dir "$T/repo-wt"
  ok eq "$RC" 5
  ok contains "$ERR" "Open the dashboard yourself"
}

CUR="dry-run"
{
  rm -f "$ARGV_FILE" 2>/dev/null || true
  rm -rf "$AGY_RUN_DIR/.ui-lock" 2>/dev/null || true
  mkdir -p "$AGY_RUN_DIR/.dashboards"
  _run_ui WT_SESSION=x -- --dir "$T/repo-wt" --dry-run
  ok eq "$RC" 0
  ok contains "$OUT" "launcher=wt"
  # wt.exe should NOT have been called
  ok test ! -f "$ARGV_FILE"
  # lock should NOT exist
  ok test ! -d "$AGY_RUN_DIR/.ui-lock"
}

CUR="tmux"
{
  rm -f "$ARGV_FILE" 2>/dev/null || true
  rm -rf "$AGY_RUN_DIR/.ui-lock"
  mkdir -p "$AGY_RUN_DIR/.dashboards"
  _run_ui TMUX=x -- --dir "$T/repo-wt"
  _load_argv
  ok eq "$RC" 0
  ok has_arg "split-window"
  ok has_arg "-h"
  ok has_arg "-d"
  ok has_arg "-c"
  _found_c_dir=0
  _prev=""
  for _a in "${ARGS[@]}"; do
    if [[ $_prev == "-c" ]]; then _found_c_dir=1; break; fi
    _prev=$_a
  done
  ok eq "$_found_c_dir" "1"
}

CUR="missing terminal"
{
  rm -rf "$AGY_RUN_DIR/.ui-lock"
  mkdir -p "$AGY_RUN_DIR/.dashboards"
  # neither WT_SESSION nor TMUX
  _run_ui -- --dir "$T/repo-wt"
  ok eq "$RC" 3
  ok contains "$ERR" "no Windows Terminal or tmux session found"
  ok contains "$ERR" "agy-top"
  # lock should be removed
  ok test ! -d "$AGY_RUN_DIR/.ui-lock"
}

CUR="duplicate dashboard"
{
  rm -rf "$AGY_RUN_DIR/.ui-lock"
  rm -f "$ARGV_FILE" 2>/dev/null || true
  mkdir -p "$AGY_RUN_DIR/.dashboards"
  # Start a background process whose name contains agy-top; use a wrapper script
  _dup_script=$T/agy-top-dup.sh
  printf '#!/usr/bin/env bash\nsleep 30\n' >"$_dup_script"
  chmod +x "$_dup_script"
  bash "$_dup_script" &
  _dup_pid=$!
  # Register it as a dashboard pid file
  touch "$AGY_RUN_DIR/.dashboards/$_dup_pid"
  # NOTE: /proc/<pid>/cmdline won't show agy-top since the script is just bash,
  # but if /proc is absent we assume alive=top. If /proc IS present we still need
  # the file to exist and pid to be alive — the check falls back to is_top=1
  # when /proc/<pid>/cmdline is NOT readable (file missing).
  # We simulate this by removing the proc symlink isn't feasible; instead we just
  # rely on the fallback: if no /proc/<pid>/cmdline, is_top=1 (assumed).
  # So this test checks the alive-pid path.
  _run_ui WT_SESSION=x -- --dir "$T/repo-wt"
  ok eq "$RC" 0
  ok contains "$ERR" "already open"
  ok test ! -f "$ARGV_FILE"

  # Now kill it; stale file should be cleaned and launch proceeds
  kill "$_dup_pid" 2>/dev/null || true
  wait "$_dup_pid" 2>/dev/null || true
  rm -f "$ARGV_FILE" 2>/dev/null || true
  rm -rf "$AGY_RUN_DIR/.ui-lock"
  _run_ui WT_SESSION=x -- --dir "$T/repo-wt"
  _load_argv
  ok eq "$RC" 0
  # wt.exe was called (stale file cleaned, launch proceeded)
  ok test -f "$ARGV_FILE"
  # stale dashboard file should be gone
  ok test ! -f "$AGY_RUN_DIR/.dashboards/$_dup_pid"
}

CUR="lock"
{
  rm -f "$ARGV_FILE" 2>/dev/null || true
  mkdir -p "$AGY_RUN_DIR/.dashboards"
  # Create a fresh (young) lock
  mkdir -p "$AGY_RUN_DIR/.ui-lock"
  touch "$AGY_RUN_DIR/.ui-lock"  # make it fresh
  _run_ui WT_SESSION=x -- --dir "$T/repo-wt"
  ok eq "$RC" 0
  # wt.exe should NOT have been called
  ok test ! -f "$ARGV_FILE"
}

CUR="worktree"
if [[ $HAS_GIT -eq 0 ]]; then
  echo "  SKIP [worktree]: git not found"
else
  {
    rm -rf "$AGY_RUN_DIR/.ui-lock"
    mkdir -p "$AGY_RUN_DIR/.dashboards"
    # Create a main repo and a worktree
    _main=$T/main-repo
    _wt=$T/repo-agy-x
    _make_repo "$_main"
    git -C "$_main" worktree add -q -b agy/x "$_wt" 2>/dev/null || {
      echo "  SKIP [worktree]: git worktree add failed"
      CUR=""
    }
    if [[ -n $CUR ]]; then
      _run_ui WT_SESSION=x -- --dir "$_wt" --dry-run
      ok eq "$RC" 0
      ok contains "$OUT" "launcher=wt"
      # The --in value should be the MAIN repo path in W: form
      _found_main=0
      _wmain=$(echo "W:$_main")
      while IFS= read -r _line; do
        if [[ $_line == *"$_wmain"* ]] || [[ $_line == W:*main-repo* ]]; then
          _found_main=1; break
        fi
      done <<<"$OUT"
      ok eq "$_found_main" "1"
    fi
  }
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "Results: $pass passed, $fail failed"
[[ $fail -eq 0 ]] && exit 0 || exit 1
