#!/usr/bin/env bash
# agy-ui.sh: open the agy-top.sh dashboard in a split pane (Windows Terminal or tmux).
# Registers a lock so parallel calls are silently ignored.
#
# Usage: agy-ui.sh [--dir DIR] [--dry-run]
#   --dir DIR   repo directory to pass to agy-top.sh --in (default: PWD)
#   --dry-run   print the command that would run; do not execute or touch files
#
# Environment:
#   AGY_RUN_DIR   run-log dir (default ${XDG_STATE_HOME:-$HOME/.local/state}/agy-runs)
#   WT_SESSION    set by Windows Terminal; triggers wt.exe launcher
#   TMUX          set inside a tmux session; triggers tmux launcher
set -uo pipefail
{

# ---------------------------------------------------------------------------
# args
# ---------------------------------------------------------------------------
dir= dry=0
while (($#)); do
  case $1 in
    --dir) (($# >= 2)) || { echo "agy-ui: --dir needs a directory" >&2; exit 2; }; dir=$2; shift ;;
    --dry-run) dry=1 ;;
    -h|--help) sed -n '2,/^set -uo/{/^#/s/^# \{0,1\}//p;}' "$0"; exit 0 ;;
    *) printf 'agy-ui: unknown option %s (agy-ui.sh --help)\n' "$1" >&2; exit 2 ;;
  esac
  shift
done
[[ -n $dir ]] || dir=$PWD

# ---------------------------------------------------------------------------
# 1. Resolve to main repo root
# ---------------------------------------------------------------------------
dir=$(cd -- "$dir" 2>/dev/null && pwd) || { echo "agy-ui: directory not found: $dir" >&2; exit 2; }
_resolve_main() {
  local d=$1 wt_out first
  # Try worktree list to get the main worktree
  if wt_out=$(git -C "$d" worktree list --porcelain 2>/dev/null); then
    first=$(echo "$wt_out" | awk '/^worktree /{print substr($0,10); exit}')
    if [[ -n $first ]]; then
      (cd -- "$first" 2>/dev/null && pwd) && return
    fi
  fi
  # Fallback: show-toplevel
  local top
  if top=$(git -C "$d" rev-parse --show-toplevel 2>/dev/null); then
    (cd -- "$top" 2>/dev/null && pwd) && return
  fi
  # Fallback: DIR itself
  (cd -- "$d" && pwd)
}
dir=$(_resolve_main "$dir")

# ---------------------------------------------------------------------------
# 2. Run dir
# ---------------------------------------------------------------------------
base=${AGY_RUN_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/agy-runs}
if [[ $dry -eq 0 ]]; then
  (umask 077; mkdir -p "$base/.dashboards")
fi

# ---------------------------------------------------------------------------
# 3. Duplicate check
# ---------------------------------------------------------------------------
_check_duplicate() {
  local d f pid
  d=$base/.dashboards
  [[ -d $d ]] || return 0
  for f in "$d"/[0-9]*; do
    [[ -f $f ]] || continue
    pid=${f##*/}
    if kill -0 "$pid" 2>/dev/null; then
      # pid alive; check if it looks like agy-top
      local is_top=1  # assume it is if /proc isn't available
      if [[ -r /proc/$pid/cmdline ]]; then
        local args=()
        mapfile -d '' args </proc/"$pid"/cmdline 2>/dev/null || true
        is_top=0
        local a
        for a in "${args[@]}"; do
          if [[ $a == *agy-top* ]]; then is_top=1; break; fi
        done
      fi
      if [[ $is_top -eq 1 ]]; then
        echo "agy-ui: dashboard already open (pid $pid)" >&2
        return 1  # signal caller to exit 0
      fi
    else
      # dead pid; remove stale file
      rm -f -- "$f"
    fi
  done
  return 0
}
if ! _check_duplicate; then
  exit 0
fi

# ---------------------------------------------------------------------------
# 4. Launch lock
# ---------------------------------------------------------------------------
_take_lock() {
  [[ $dry -eq 1 ]] && return 0
  local lock=$base/.ui-lock
  if mkdir "$lock" 2>/dev/null; then
    return 0
  fi
  # lock exists; check age
  if [[ -n $(find "$lock" -maxdepth 0 -mmin -1 2>/dev/null) ]]; then   # integer -mmin: BSD find too
    # young lock — another runner is active
    exit 0
  fi
  # old lock — remove and retry once
  rm -rf -- "$lock"
  if mkdir "$lock" 2>/dev/null; then
    return 0
  fi
  exit 0
}
_take_lock

# ---------------------------------------------------------------------------
# 5. Path to agy-top.sh
# ---------------------------------------------------------------------------
top=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/agy-top.sh
[[ -f $top ]] || { echo "agy-ui: agy-top.sh not found next to this script ($top)" >&2; exit 2; }

# ---------------------------------------------------------------------------
# 6. Terminal detection & launch
# ---------------------------------------------------------------------------
_remove_lock_on_no_terminal() {
  [[ $dry -eq 1 ]] && return
  rm -rf -- "$base/.ui-lock"
}

if [[ -n ${WT_SESSION:-} ]] && command -v wt.exe &>/dev/null && command -v cygpath &>/dev/null; then
  # --- Windows Terminal ---
  wdir=$(cygpath -m "$dir")
  wtop=$(cygpath -m "$top")
  # Find the Git for Windows bash wrapper
  wbash=
  _gbash=$(cygpath -m /)
  if [[ -f "${_gbash}bin/bash.exe" ]]; then
    wbash="${_gbash}bin/bash.exe"
  else
    wbash=$(cygpath -m "$BASH")
  fi
  cmd_arr=(
    wt.exe -w 0 split-pane -V --size 0.4 --title 'AGY Control Center'
    --suppressApplicationTitle -d "$wdir"
    "$wbash" --login "$wtop" --in "$wdir"
    ';' move-focus previous
  )
  if [[ $dry -eq 1 ]]; then
    echo "launcher=wt"
    printf '%s\n' "${cmd_arr[@]:1}"  # skip wt.exe itself
    exit 0
  fi
  _timeout_cmd=()
  command -v timeout &>/dev/null && _timeout_cmd=(timeout 10)
  MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' \
    "${_timeout_cmd[@]}" "${cmd_arr[@]}" </dev/null >/dev/null 2>/dev/null
  _rc=$?
  if [[ $_rc -ne 0 ]]; then
    printf 'agy-ui: wt.exe failed (rc %d). Open the dashboard yourself: bash "%s" --in "%s"\n' \
      "$_rc" "$top" "$dir" >&2
    exit "$_rc"
  fi
  exit 0

elif [[ -n ${TMUX:-} ]] && command -v tmux &>/dev/null; then
  # --- tmux ---
  cmd_arr=(tmux split-window -h -d -l 40% -c "$dir" "\"$top\" --in \"$dir\"")
  if [[ $dry -eq 1 ]]; then
    echo "launcher=tmux"
    printf '%s\n' "${cmd_arr[@]:1}"
    exit 0
  fi
  "${cmd_arr[@]}"
  _rc=$?
  if [[ $_rc -ne 0 ]]; then
    printf 'agy-ui: tmux failed (rc %d). Open the dashboard yourself: bash "%s" --in "%s"\n' \
      "$_rc" "$top" "$dir" >&2
    exit "$_rc"
  fi
  exit 0

else
  # --- no supported terminal ---
  _remove_lock_on_no_terminal
  printf 'agy-ui: no Windows Terminal or tmux session found. Open the dashboard in another terminal: bash "%s" --in "%s"\n' \
    "$top" "$dir" >&2
  exit 3
fi

}
