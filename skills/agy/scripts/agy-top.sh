#!/usr/bin/env bash
# agy-top.sh: AGY Control Center, a live terminal dashboard of agy-run.sh workers.
# Reads the run log agy-run.sh writes; start it in a second terminal or pane (agy-ui.sh opens one).
# Quitting never stops workers: they are separate processes.
#
# Usage: agy-top.sh [--once] [--all] [--here | --in DIR] [--no-bell]
#   --once     print one frame and exit (no keys, no alternate screen)
#   --all      also show finished runs older than 12 hours
#   --here     only runs in this repo, below it, or in sibling worktrees named <repo>-*
#   --in DIR   same as --here, for the repo that contains DIR
#   --no-bell  do not ring the terminal bell when a worker finishes
#   -h, --help
#
# Keys: up/down or k/j select, enter inspect (full report in $PAGER, default less -R),
#       x stop the selected worker (asks y/n), r resume a finished worker with a follow-up,
#       ? help, q detach (workers keep running)
#
# Environment:
#   AGY_RUN_DIR       run log dir (default ${XDG_STATE_HOME:-$HOME/.local/state}/agy-runs)
#   AGY_RUN_MAX_JOBS  slot limit shown in the header (else the last limit a runner used)
#   NO_COLOR          any value disables color
set -uo pipefail
# Whole body in braces: bash parses it all first, so editing this file while it runs is safe.
{
base=${AGY_RUN_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/agy-runs}
self_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
once=0 all=0 here= bell=1
# repo DIR: absolute repo root of DIR (or DIR itself outside git), in this shell's path style.
repo() { (cd -- "$1" 2>/dev/null && cd -- "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" && pwd); }
while (($#)); do
  case $1 in
    --once) once=1 ;;
    --all|-a) all=1 ;;
    --here) here=$(repo .) ;;
    --in) (($# >= 2)) || { echo "agy-top: --in needs a directory" >&2; exit 2; }; here=$(repo "$2") || { echo "agy-top: no such directory: $2" >&2; exit 2; }; shift ;;
    --no-bell) bell=0 ;;
    -h|--help) sed -n '2,/^set -uo/{/^#/s/^# \{0,1\}//p;}' "$0"; exit 0 ;;
    *) printf 'agy-top: unknown option %s (agy-top.sh --help)\n' "$1" >&2; exit 2 ;;
  esac
  shift
done
# Key source; tests point it at a file.
input=${AGY_TOP_INPUT:-/dev/tty}

if [[ ${LC_ALL:-${LC_CTYPE:-${LANG:-}}} == *[Uu][Tt][Ff]* ]]; then
  SPIN=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏) G_OK=✔ G_BAD=✖ G_WARN=▲ G_TOOL=▸ G_STEP=✓ G_SEL=▌ G_DOT=· G_ELL=… G_PEN=✎ G_Q=◷ G_RES=↻ G_STOP=■ G_INF=∞ HR=─
else
  SPIN=('|' / - '\') G_OK=+ G_BAD=x G_WARN=! G_TOOL='>' G_STEP='*' G_SEL='>' G_DOT='-' G_ELL='~' G_PEN='>' G_Q='.' G_RES='@' G_STOP='#' G_INF='-' HR=-
fi
if [[ -z ${NO_COLOR:-} ]] && { ((!once)) || [[ -t 1 ]]; }; then
  B=$'\e[1m' D=$'\e[2m' X=$'\e[0m' RED=$'\e[31m' GRN=$'\e[32m' YEL=$'\e[33m' CYN=$'\e[36m' MAG=$'\e[35m'
else
  B= D= X= RED= GRN= YEL= CYN= MAG=
fi

re_idx='"step_index":([0-9]+)' re_state='"state":"([A-Z_]+)"' re_type='"step_type":"([a-z_]+)"'
re_tool='"tool_name":"([^"]+)"' re_dur='"duration_seconds":([0-9]+)(\.[0-9])?'
re_tok='^TOK ([0-9]+)$'
re_delta='"text_delta":"(([^"\\]|\\.){0,200})'

# Helpers return in T, not stdout: a $(...) fork per call is ~10ms on Git Bash.
dur() {
  local s=$1
  ((s < 0)) && s=0
  if ((s < 60)); then printf -v T '%ds' "$s"
  elif ((s < 3600)); then printf -v T '%dm%02ds' $((s / 60)) $((s % 60))
  else printf -v T '%dh%02dm' $((s / 3600)) $((s % 3600 / 60)); fi
}
trunc() { local w=$(($2 < 1 ? 0 : $2)); T=$1; ((${#T} > w)) && T=${T:0:w-1}$G_ELL; ((w)) || T=; }
pad() { local w=$(($2 < 0 ? 0 : $2)); trunc "$1" "$w"; printf -v T '%s%*s' "$T" $((w - ${#T})) ''; }
tilde() { T=$1; [[ $T == "$HOME"* ]] && T="~${T#"$HOME"}"; }
jtext() {
  T=${1//\\n/ }; T=${T//\\t/ }; T=${T//\\\"/\"}
  T=${T//\\u0026/"&"}; T=${T//\\u003c/<}; T=${T//\\u003e/>}; T=${T//\\u0027/"'"}   # Go escapes these
  T=${T//\\\\/\\}
}
clock() { printf -v T '%(%H:%M:%S)T' "$1"; }

# alive PID: the runner still runs. /proc (Linux, Git Bash, Cygwin) also rules out a reused PID.
alive() {
  kill -0 "$1" 2>/dev/null || return 1
  [[ -r /proc/$1/cmdline ]] || return 0
  local -a args; local x
  mapfile -d '' args 2>/dev/null </proc/"$1"/cmdline || return 0
  for x in "${args[@]+"${args[@]}"}"; do [[ $x == *agy-run* ]] && return 0; done
  return 1
}

# meta DIR: m_* fields of one run (builtin reads of a small file, no fork).
meta() {
  local k v
  m_name= m_task= m_perm= m_model= m_cwd= m_start=0 m_pid= m_role=
  while IFS='=' read -r k v; do
    case $k in name) m_name=$v ;; task) m_task=$v ;; perm) m_perm=$v ;; model) m_model=$v ;; cwd) m_cwd=$v ;; start) m_start=$v ;; pid) m_pid=$v ;; esac
  done <"$1/meta"
  # Role from the worker prompt contract ("ROLE: Security Auditor ...").
  if [[ $m_task =~ ROLE:[[:space:]]*([A-Za-z][A-Za-z\ ]{0,30}[A-Za-z]) ]]; then
    m_role=${BASH_REMATCH[1]}
    m_role=${m_role%% OBJECTIVE*}; m_role=${m_role%% CONTEXT*}
  fi
}

# status DIR: ST (running queued stopping done blocked timeout hung stopped failed lost), RC, END.
# Finished states never change, so they are cached.
declare -A STC=() RCC=() ENDC=() STOPPING=()
status() {
  local d=$1 rc= end=
  meta "$d"
  if [[ -n ${STC[$d]+x} ]]; then ST=${STC[$d]} RC=${RCC[$d]} END=${ENDC[$d]}; return; fi
  if [[ -f $d/rc ]]; then
    read -r rc end <"$d/rc"
    case $rc in
      0) ST=done; local first=; read -r first 2>/dev/null <"$d/report"; [[ $first == BLOCKED:* ]] && ST=blocked ;;
      3) ST=timeout ;; 124) ST=hung ;; 130|143) ST=stopped ;; *) ST=failed ;;
    esac
    RC=$rc END=${end:-0}
    STC[$d]=$ST RCC[$d]=$RC ENDC[$d]=$END
  elif [[ -n $m_pid ]] && alive "$m_pid"; then
    RC= END=
    if [[ -n ${STOPPING[$d]+x} ]]; then ST=stopping
    elif [[ -e $d/queued ]]; then ST=queued
    else ST=running; fi
  else
    ST=lost RC= END=
  fi
}

# Event stream: "epoch<TAB>name<TAB>kind<TAB>text", capped, sorted only when it changed.
EV=() EVLINES=() EVDIRTY=0
ev() {
  EV+=("$1"$'\t'"$2"$'\t'"$3"$'\t'"$4")
  ((${#EV[@]} > 300)) && EV=("${EV[@]: -200}")
  EVDIRTY=1
}

# load DIR NAME: read only the event records added since the last call (events.ndjson is
# append-only) and keep each run's steps in memory. Each record is cut to 4000 bytes before
# bash sees it: bash reads pipes one byte at a time, and tool output lines can be megabytes.
# bash's read drops a last line without a newline, so a record still being written is read
# on the next call, once complete. New step states become events after the first load;
# history from before the dashboard started has no real times, so it only shows under Steps.
declare -A ACT=() STEPS=() TOK=() NTOOL=() LOADED=() NL=() REC=() ORD=() DELTA=()
# awk (C speed) does the heavy part: cut each record to 4000 bytes, and collapse the stream of
# text deltas (Claude models send hundreds per answer) to the first and the latest per step.
collapse='
  { if (match($0, /"total_tokens":[0-9]+/)) tok = substr($0, RSTART + 15, RLENGTH - 15); $0 = substr($0, 1, 1500) }
  /"state":"ACTIVE","step_type":"agent_response"/ {
    match($0, /"step_index":[0-9]+/); k = substr($0, RSTART, RLENGTH)
    if (k != last) { last = k; print; held = "" } else held = $0
    next
  }
  { held = ""; print }
  END { if (held != "") print held; if (tok != "") print "TOK " tok }'
sentinels=
load() {
  local d=$1 nm=$2 f=$1/events.ndjson line idx state type tool arg t delta now key old
  local from=${NL[$d]:-0} first=0 total s=${sentinels}/${1##*/}
  printf -v now '%(%s)T' -1
  [[ -f $f ]] || { ACT[$d]= STEPS[$d]= NTOOL[$d]=0; LOADED[$d]=1; return 0; }
  # Unchanged since the last read: nothing to do, and no fork (-nt is a builtin test).
  [[ -n ${LOADED[$d]+x} && -n $sentinels && -e $s && ! $f -nt $s ]] && return 0
  [[ -n $sentinels ]] && : >"$s"
  # wc -l counts complete lines only, so a record still being written waits for the next read.
  total=$(wc -l <"$f" 2>/dev/null) || total=0
  total=${total//[^0-9]/}
  ((total > from)) || { LOADED[$d]=1; return 0; }
  if [[ -z ${LOADED[$d]+x} ]]; then
    first=1
    # Long runs: start near the end; count every finished tool once.
    ((total - from > 3000)) && from=$((total - 3000))
    NTOOL[$d]=$(grep -c '"state":"DONE","step_type":"tool"' "$f" 2>/dev/null) || NTOOL[$d]=0
  fi
  while IFS= read -r line; do
    [[ $line =~ $re_tok ]] && { TOK[$d]=${BASH_REMATCH[1]}; continue; }
    local h=${line:0:600}   # regex on a short prefix: msys regex is slow on long strings
    [[ $h =~ $re_idx ]] || continue
    idx=${BASH_REMATCH[1]} state= type= tool= arg= t= delta=
    [[ $h =~ $re_state ]] && state=${BASH_REMATCH[1]}
    [[ $h =~ $re_type ]] && type=${BASH_REMATCH[1]}
    [[ -n $state && -n $type ]] || continue
    [[ $h =~ $re_tool ]] && tool=${BASH_REMATCH[1]}
    [[ $h =~ $re_dur ]] && t=${BASH_REMATCH[1]}${BASH_REMATCH[2]}s
    # First parameter value via string ops (a regex is slow here); \" survives the cut.
    if [[ $line == *'"parameters":{"'* ]]; then
      arg=${line#*'"parameters":{"'}; arg=${arg#*'":"'}
      arg=${arg//'\"'/$'\2'}; arg=${arg%%'"'*}
      jtext "${arg//$'\2'/'\"'}"; arg=${T:0:160}
    fi
    key="$d|$idx"
    old=${REC[$key]-}
    [[ -n $old ]] || ORD[$d]+="$idx "
    if [[ $type == agent_response && $state != DONE ]]; then
      [[ $line =~ $re_delta ]] && { jtext "${BASH_REMATCH[1]}"; DELTA[$d]=$T; }
    fi
    # read collapses empty tab fields, so every field gets a "-" placeholder
    REC[$key]="$state"$'\t'"$type"$'\t'"${tool:--}"$'\t'"${arg:--}"$'\t'"${t:--}"
    # Events: only a step's first record in a new state, never on the first load.
    if ((!first)) && [[ $type == tool && ${old%%$'\t'*} != "$state" ]]; then
      case $state in
        ACTIVE|PENDING|RUNNING) ev "$now" "$nm" run "$G_TOOL $tool  $arg" ;;
        DONE) ev "$now" "$nm" ok "$G_STEP $tool  $arg  $t" ;;
        *) ev "$now" "$nm" bad "$G_BAD $tool  $arg ($state)" ;;
      esac
    fi
    ((!first)) && [[ $type == tool && $state == DONE && ${old%%$'\t'*} != DONE ]] && NTOOL[$d]=$((NTOOL[$d] + 1))
  done < <(tail -n +$((from + 1)) "$f" 2>/dev/null | awk -v n=$((total - from)) "NR > n { exit } $collapse")
  NL[$d]=$total LOADED[$d]=1
  # Keep the last 60 steps; rebuild the Steps list and the current activity.
  local -a ids=(${ORD[$d]-}) keep=()
  if ((${#ids[@]} > 60)); then
    for idx in "${ids[@]:0:${#ids[@]}-60}"; do unset "REC[$d|$idx]"; done
    ids=("${ids[@]: -60}"); ORD[$d]="${ids[*]} "
  fi
  local steps= act= i
  for i in "${ids[@]+"${ids[@]}"}"; do
    IFS=$'\t' read -r state type tool arg t <<<"${REC[$d|$i]}"
    local a=$arg; [[ $a == - ]] && a=
    case $type in
      tool)
        case $state in
          ACTIVE|PENDING|RUNNING) act="$G_TOOL $tool  $a" ;;
          DONE) steps+="ok"$'\t'"$tool"$'\t'"$arg"$'\t'"$t"$'\n'; act= ;;
          *) steps+="bad"$'\t'"$tool"$'\t'"$a ($state)"$'\t'"$t"$'\n'; act= ;;
        esac ;;
      agent_response)
        if [[ $state == DONE ]]; then steps+="think"$'\t'"think"$'\t'"-"$'\t'"$t"$'\n'; act=
        else act="$G_PEN writing: ${DELTA[$d]-}"; fi ;;
    esac
  done
  ACT[$d]=$act STEPS[$d]=$steps
}

# Finished runs never change: their summary line and report preview are read once.
declare -A FIRSTC=() BODYC=()
firstline() {
  local d=$1
  [[ -n ${FIRSTC[$d]+x} ]] || FIRSTC[$d]=$(grep -m1 -v -e '^[[:space:]]*$' -e '^[[:space:]]*#' "$d/report" 2>/dev/null || true)
  T=${FIRSTC[$d]}
}
body() {
  local d=$1
  if [[ -z ${BODYC[$d]+x} ]]; then
    case $ST in
      done|blocked) BODYC[$d]=$(grep -v -e '^[[:space:]]*$' -e '^---$' "$d/report" 2>/dev/null | head -n 40) ;;
      *) BODYC[$d]=$(grep -v -e '^[[:space:]]*$' -e '^agy-run: ' "$d/err" 2>/dev/null | tail -n 6) ;;
    esac
  fi
  T=${BODYC[$d]}
}

# Repo name and branch for the header, refreshed every 10 s.
branch_at=-100 BRANCH= REPO_NAME=
repo_info() {
  local now=$1 root
  ((now - branch_at < 10)) && return
  root=${here:-$(repo .)}
  branch_at=$now REPO_NAME=${root##*/}
  BRANCH=$(git -C "$root" branch --show-current 2>/dev/null || true)
}
slot_max() {
  T=${AGY_RUN_MAX_JOBS:-}
  [[ -n $T ]] || read -r T 2>/dev/null <"$base/.slots/max" || T=
  [[ $T =~ ^[1-9][0-9]*$ ]] || T=
}

kind_glyph() {  # ST -> G (glyph) LBL (label) COL (color)
  case $1 in
    running) G=${SPIN[tick % ${#SPIN[@]}]} LBL=RUNNING COL=$CYN ;;
    queued) G=$G_Q LBL=QUEUED COL=$D ;;
    stopping) G=$G_STOP LBL=STOPPING COL=$YEL ;;
    done) G=$G_OK LBL=DONE COL=$GRN ;;
    blocked) G=$G_WARN LBL=BLOCKED COL=$YEL ;;
    timeout|hung) G=$G_WARN LBL=TIMEOUT COL=$YEL ;;
    stopped) G=$G_STOP LBL=STOPPED COL=$YEL ;;
    lost) G=$G_WARN LBL=LOST COL=$MAG ;;
    *) G=$G_BAD LBL=FAILED COL=$RED ;;
  esac
}

# scan: refresh the run list, statuses and counters; status changes become events.
declare -A PREV=()
scan() {
  local now d entries=() name
  printf -v now '%(%s)T' -1
  RUNS=() BELL=0 n_run=0 n_queue=0 n_ok=0 n_block=0 n_bad=0
  if [[ -d $base ]]; then
    for d in "$base"/*/; do
      d=${d%/}; [[ -f $d/meta ]] || continue
      status "$d"
      [[ -z $here || $m_cwd == "$here" || $m_cwd == "$here"/* || $m_cwd == "$here"-* ]] || continue
      name=${m_name:-${d##*/}}
      local recent=$((all || now - m_start < 43200))
      case $ST in
        running|queued|stopping)
          case $ST in queued) n_queue=$((n_queue + 1)) ;; *) n_run=$((n_run + 1)) ;; esac
          entries+=("0 $m_start $d") ;;
        *)
          [[ ${PREV[$d]:-} == running || ${PREV[$d]:-} == queued || ${PREV[$d]:-} == stopping ]] && BELL=1
          if ((recent)); then
            case $ST in done) n_ok=$((n_ok + 1)) ;; blocked) n_block=$((n_block + 1)) ;; *) n_bad=$((n_bad + 1)) ;; esac
            entries+=("1 $m_start $d")
          fi ;;
      esac
      if [[ ${PREV[$d]:-} != "$ST" ]]; then
        kind_glyph "$ST"
        if [[ -z ${PREV[$d]+x} ]]; then
          # First sight: only the real times on disk (start, end).
          if ((recent)); then
            ev "$m_start" "$name" start "$G_RES started  ${m_perm}${m_model:+ $G_DOT $m_model}"
            [[ -n $END && $END != 0 ]] && ev "$END" "$name" "$ST" "$G $LBL${RC:+  exit $RC}"
          fi
        else
          case $ST in
            running) ev "$now" "$name" start "$G_RES running" ;;
            stopping) ev "$now" "$name" stopping "$G_STOP stop requested" ;;
            queued) ev "$now" "$name" queued "$G_Q queued" ;;
            *) ev "${END:-$now}" "$name" "$ST" "$G $LBL${RC:+  exit $RC}" ;;
          esac
        fi
      fi
      PREV[$d]=$ST
    done
  fi
  ((${#entries[@]})) && mapfile -t RUNS < <(printf '%s\n' "${entries[@]}" | sort -k1,1n -k2,2nr | cut -d' ' -f3-)
}

# reload: steps of running runs, and of each finished run once.
declare -A DONE_LOADED=()
reload() {
  local d
  for d in "${RUNS[@]+"${RUNS[@]}"}"; do
    status "$d"
    if [[ -n ${STC[$d]+x} ]]; then
      [[ -n ${DONE_LOADED[$d]+x} ]] && continue
      DONE_LOADED[$d]=1
    fi
    load "$d" "${m_name:-${d##*/}}"
  done
}

# ---- drawing: every line is cut to W visible columns before color codes are added ----
F=()
rule() { local r; printf -v r '%*s' "$W" ''; F+=("${D}${r// /$HR}${X}"); }
title() { local right=${2:-}; pad "$1" $((W - ${#right} - 1)); F+=("${B}${T}${X} ${D}${right}${X}"); }

draw_header() {
  local now=$1 left=" AGY CONTROL CENTER" right ctx mx
  repo_info "$now"
  dur $((now - started)); right="up $T  "
  clock "$now"; right+=$T
  ctx="   ${REPO_NAME:-?}${BRANCH:+  $G_DOT $BRANCH}"
  pad "$ctx" $((W - ${#left} - ${#right} - 1))
  F+=("${B}${CYN}${left}${X}${B}${T}${X} ${D}${right}${X}")
  slot_max; mx=$T
  local c="${CYN}${SPIN[tick % ${#SPIN[@]}]} $n_run running${X}  ${D}$G_Q $n_queue queued${X}  ${GRN}$G_OK $n_ok done${X}"
  local p="x $n_run running  x $n_queue queued  x $n_ok done"
  ((n_block)) && { c+="  ${YEL}$G_WARN $n_block blocked${X}"; p+="  x $n_block blocked"; }
  c+="  ${RED}$G_BAD $n_bad failed${X}"; p+="  x $n_bad failed"
  local sl="slots $n_run/$mx"; [[ -n $mx ]] || sl="slots $n_run/$G_INF"
  local gap=$((W - 1 - ${#p} - ${#sl})); ((gap < 1)) && gap=1
  local sp; printf -v sp '%*s' "$gap" ''
  F+=(" $c$sp${D}$sl${X}")
}

draw_list() {
  local h=$1 now=$2 i start=0 d el act sel used row
  title " WORKERS" "${#RUNS[@]} shown${here:+ in ${here##*/}}"
  if ((!${#RUNS[@]})); then
    F+=("   No agy workers yet. Start one with agy-run.sh; it shows up here live.")
    for ((i = 1; i < h; i++)); do F+=(""); done
    return
  fi
  ((sel_idx >= h)) && start=$((sel_idx - h + 1))
  local wide=$((W >= 100)) nw=20
  for ((i = start; i < start + h; i++)); do
    if ((i >= ${#RUNS[@]})); then F+=(""); continue; fi
    d=${RUNS[i]}; status "$d"; kind_glyph "$ST"
    if [[ $ST == running || $ST == queued || $ST == stopping ]]; then el=$((now - m_start)); else el=$((END - m_start)); fi
    case $ST in
      running) act=${ACT[$d]:-}; [[ -n $act ]] || { [[ -s $d/events.ndjson ]] && act="thinking…" || act="starting agy…"; } ;;
      queued) act="waiting for a free slot" ;;
      stopping) act="stop requested…" ;;
      lost) act="runner exited without writing a result" ;;
      done|blocked) firstline "$d"; act=$T ;;
      *) body "$d"; act=${T##*$'\n'}; act="exit ${RC:-?}${act:+  $act}" ;;   # last error line
    esac
    sel=' '; ((i == sel_idx)) && sel="${CYN}$G_SEL${X}"
    pad "$LBL" 9; row="$sel${COL}${B}$G $T${X}"
    pad "#${d##*-}" 7; row+="${D}$T${X}"
    pad "${m_name:-${d##*/}}" "$nw"; row+="${B}$T${X} "
    used=$((1 + 2 + 9 + 7 + nw + 1))
    if ((wide)); then pad "${m_role:-${m_model:-$m_perm}}" 22; row+="${D}$T${X}"; used=$((used + 22)); fi
    dur "$el"; pad "$T" 7; row+="$T "; used=$((used + 8))
    trunc "$act" $((W - used)); row+="${COL}$T${X}"
    F+=("$row")
  done
}

draw_detail() {
  local h=$1 now=$2 d i lines=()
  if ((help)); then
    title " KEYS" ""
    lines=("  ↑ ↓  or  k j   select a worker"
      "  enter          inspect: full report (or errors) in ${PAGER:-less -R}"
      "  x              stop the selected worker (asks y/n)"
      "  r              resume a finished worker: send a follow-up in its conversation"
      "  ?              show or hide this help"
      "  q              detach: close the dashboard, workers keep running"
      ""
      "  ${D}Runs: $base${X}")
    for ((i = 0; i < h; i++)); do F+=("${lines[i]-}"); done
    return
  fi
  if ((!${#RUNS[@]})); then title " DETAIL" ""; for ((i = 0; i < h; i++)); do F+=(""); done; return; fi
  d=${RUNS[sel_idx]}; status "$d"; kind_glyph "$ST"
  local conv=; read -r conv 2>/dev/null <"$d/conversation" || true
  title " DETAIL  ${m_name:-${d##*/}}  #${d##*-}" "${conv:+conversation $conv}"
  local lw=$((W - 11)) task
  trunc "${m_task:-?}" $((lw * 2)); task=$T
  lines+=("  ${D}Task${X}     ${task:0:lw}")
  ((${#task} > lw)) && lines+=("           ${task:lw}")
  local nt=${NTOOL[$d]:-0} info
  tilde "$m_cwd"; info="$T $G_DOT ${m_perm}"
  [[ -n $m_model ]] && info+=" $G_DOT $m_model"
  [[ -n $m_role ]] && info+=" $G_DOT $m_role"
  ((nt == 1)) && info+=" $G_DOT 1 tool"; ((nt > 1)) && info+=" $G_DOT $nt tools"
  [[ -n ${TOK[$d]:-} ]] && info+=" $G_DOT $((TOK[$d] / 1000)).$((TOK[$d] % 1000 / 100))k tok"
  trunc "$info" "$lw"; lines+=("  ${D}Where${X}    ${D}$T${X}")
  local el st; if [[ $ST == running || $ST == queued || $ST == stopping ]]; then el=$((now - m_start)); else el=$((END - m_start)); fi
  dur "$el"; local els=$T
  st="${COL}${B}$G $LBL${X}"
  case $ST in
    running) trunc "${ACT[$d]:-thinking…}" $((lw - 22)); st+="  $els  ${CYN}$T${X}" ;;
    queued) st+="  waiting $els for a free slot" ;;
    stopping) st+="  stop requested, waiting for the worker to exit" ;;
    lost) st+="  runner exited without writing a result" ;;
    *) st+="  exit ${RC:-?} after $els" ;;
  esac
  lines+=("  ${D}Status${X}   $st")
  # Recent steps, newest first.
  local -a sl=(); local s kind tool arg t g lbl k=0 nsteps=3
  ((h >= 12)) && nsteps=5
  [[ -n ${STEPS[$d]:-} ]] && mapfile -t sl <<<"${STEPS[$d]%$'\n'}"
  for ((i = ${#sl[@]} - 1; i >= 0 && k < nsteps; i--, k++)); do
    IFS=$'\t' read -r kind tool arg t <<<"${sl[i]}"
    [[ $arg == - ]] && arg=
    [[ $t == - ]] && t=
    case $kind in ok) g="${GRN}$G_STEP${X}" ;; bad) g="${RED}$G_BAD${X}" ;; *) g="${D}$G_DOT${X}" ;; esac
    trunc "$tool" 20; tool=$T; pad "$arg" $((lw - 31)); printf -v t '%6s' "$t"
    lbl='         '; ((k == 0)) && lbl="${D}Steps${X}    "
    lines+=("  $lbl$g ${D}$tool${X}  $T  ${D}$t${X}")
  done
  # Report, blocked question, or error lines.
  local body=() first=1 c=$D
  case $ST in
    running|queued|stopping) ;;
    *) body "$d"; [[ -n $T ]] && mapfile -t body <<<"$T" ;;
  esac
  [[ $ST == blocked ]] && c=$YEL
  [[ $ST == failed || $ST == lost ]] && c=$RED
  local reserve=0
  [[ -n $conv && $ST != running && $ST != queued && $ST != stopping ]] && reserve=1
  for s in "${body[@]+"${body[@]}"}"; do
    ((${#lines[@]} >= h - reserve)) && break
    trunc "$s" "$lw"
    if ((first)); then lines+=("  ${D}Report${X}   ${c}$T${X}"); first=0; else lines+=("           ${c}$T${X}"); fi
  done
  ((reserve)) && lines+=("  ${D}Resume${X}   press r to send a follow-up in this conversation")
  for ((i = 0; i < h; i++)); do ((once && i >= ${#lines[@]})) && break; F+=("${lines[i]-}"); done
}

draw_events() {
  local h=$1 i e ep nm kind text c
  title " EVENTS" "newest first"
  if ((EVDIRTY)); then
    EVLINES=()
    ((${#EV[@]})) && mapfile -t EVLINES < <(printf '%s\n' "${EV[@]}" | sort -t $'\t' -k1,1nr | head -n 50)
    EVDIRTY=0
  fi
  for ((i = 0; i < h; i++)); do
    e=${EVLINES[i]-}
    if [[ -z $e ]]; then
      if ((i == 0)); then F+=("  ${D}No events yet.${X}"); else F+=(""); fi
      continue
    fi
    IFS=$'\t' read -r ep nm kind text <<<"$e"
    case $kind in ok|done) c=$GRN ;; bad|failed|lost) c=$RED ;; blocked|timeout|hung|stopped|stopping) c=$YEL ;; run|start) c=$CYN ;; *) c=$D ;; esac
    clock "$ep"; local tm=$T
    pad "$nm" 18; local nmp=$T
    trunc "$text" $((W - 32))
    F+=("  ${D}$tm${X}  ${B}$nmp${X}  ${c}$T${X}")
  done
}

draw_footer() {
  if [[ -n $CONFIRM ]]; then
    meta "$CONFIRM"; trunc " Stop worker \"$m_name\"? y/n" "$W"; F+=("${YEL}${B}$T${X}")
  elif [[ -n $NOTE ]]; then
    trunc " $NOTE" "$W"; F+=("${YEL}$T${X}")
  else
    F+=("${D} ↑↓ select   enter inspect   x stop   r resume   ? help   q detach${X}")
  fi
}

# frame: compose the screen into F (footer last).
frame() {
  local now i n lh dh eh avail
  printf -v now '%(%s)T' -1
  F=()
  for i in "${!RUNS[@]}"; do [[ ${RUNS[i]} == "$SEL" ]] && sel_idx=$i; done
  n=${#RUNS[@]}
  ((sel_idx >= n)) && sel_idx=$((n ? n - 1 : 0))
  ((n)) && SEL=${RUNS[sel_idx]}
  if ((once)); then
    lh=$((n ? n : 1)) dh=14 eh=${#EV[@]}
    ((eh > 12)) && eh=12; ((eh < 1)) && eh=1
  else
    avail=$((ROWS - 9))
    lh=$((avail * 35 / 100)); ((lh < 3)) && lh=3; ((lh > (n ? n : 1))) && lh=$((n ? n : 1))
    dh=$((avail - lh - 4)); ((dh > 14)) && dh=14; ((dh < 2)) && dh=2
    eh=$((avail - lh - dh)); ((eh < 2)) && eh=2
  fi
  draw_header "$now"; rule
  draw_list "$lh" "$now"; rule
  draw_detail "$dh" "$now"; rule
  draw_events "$eh"
  ((once)) || draw_footer
}

# paint: write only the rows that changed since the last frame; the footer sits on the last row.
PF=() FULL=1
paint() {
  local i out= line last=$((ROWS - 1)) body=$((${#F[@]} - 1))
  for ((i = 0; i < ROWS; i++)); do
    if ((i == last)); then line=${F[body]}
    elif ((i < body)); then line=${F[i]}
    else line=; fi
    if ((FULL)) || [[ ${PF[i]-} != "$line" ]]; then
      out+=$'\e['"$((i + 1))"';1H'"$line"$'\e[K'
      PF[i]=$line
    fi
  done
  FULL=0
  printf '%s' "$out"
}

size() {
  local s; s=$(stty size 2>/dev/null </dev/tty) || s=
  ROWS=${s%% *} COLS=${s##* }
  [[ $ROWS =~ ^[0-9]+$ && $COLS =~ ^[0-9]+$ ]] || { ROWS=${LINES:-40} COLS=${COLUMNS:-100}; }
  ((ROWS < 18)) && ROWS=18
  W=$COLS; ((W > 160)) && W=160; ((W < 50)) && W=50
  FULL=1
}

# resume DIR TEXT: a follow-up in the worker's conversation, started as a new detached runner
# with the same permission mode, directory and model. It appears in the list as "<name>+".
resume() {
  local d=$1 text=$2 conv=
  read -r conv 2>/dev/null <"$d/conversation" || return 1
  [[ -n $conv ]] || return 1
  meta "$d"
  local args=(--perm "${m_perm:-sandbox}" --name "${m_name:0:50}+")
  [[ -n $m_cwd ]] && args+=(--cd "$m_cwd")
  [[ -n $m_model ]] && args+=(--model "$m_model")
  args+=(--conversation "$conv" -- "$text")
  # nohup and no terminal fds: the new worker outlives the dashboard and its pane.
  AGY_RUN_DIR=$base nohup "$self_dir/agy-run.sh" "${args[@]}" </dev/null >/dev/null 2>&1 &
  disown 2>/dev/null || true
}

tick=0 SEL= sel_idx=0 CONFIRM= NOTE= help=0 BELL=0
printf -v started '%(%s)T' -1
size
if ((once)); then
  ROWS=10000; scan; reload; frame
  printf '%s\n' "${F[@]}"
  exit 0
fi

exec {kfd}<"$input" || { printf 'agy-top: cannot read keys from %s\n' "$input" >&2; exit 2; }
# Register for agy-ui.sh's duplicate check; a pending launch lock is done now.
mkdir -p "$base/.dashboards/$$.d" 2>/dev/null && : >"$base/.dashboards/$$" && sentinels=$base/.dashboards/$$.d
rm -rf "$base/.ui-lock" 2>/dev/null
cleanup() { rm -rf "$base/.dashboards/$$" "$base/.dashboards/$$.d" 2>/dev/null; printf '\e[?25h\e[?1049l'; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP
trap size WINCH
printf '\e[?1049h\e[?25l\e[2J'
scan; reload
while :; do
  frame
  paint
  ((BELL && bell)) && printf '\a'
  BELL=0
  key= k2= got=0
  IFS= read -rsn1 -t 0.25 -u "$kfd" key && got=1
  if [[ $key == $'\e' ]]; then IFS= read -rsn2 -t 0.01 -u "$kfd" k2; key+=$k2; fi
  tick=$((tick + 1))
  # Spinner every tick; disk about once a second, or right after a key.
  if ((got || tick % 4 == 0)); then scan; reload; fi
  ((got)) || continue
  NOTE=
  if [[ -n $CONFIRM ]]; then
    if [[ $key == [yY] ]]; then
      meta "$CONFIRM"
      if [[ -n $m_pid ]] && alive "$m_pid" && kill -TERM "$m_pid" 2>/dev/null; then STOPPING[$CONFIRM]=1; fi
    fi
    CONFIRM=; scan; continue
  fi
  n=${#RUNS[@]}
  case $key in
    q|Q) exit 0 ;;
    '?') help=$((!help)) ;;
    $'\e[A'|k) ((n)) && SEL=${RUNS[sel_idx > 0 ? sel_idx - 1 : 0]} ;;
    $'\e[B'|j) ((n)) && SEL=${RUNS[sel_idx + 1 < n ? sel_idx + 1 : sel_idx]} ;;
    x|X) [[ -n $SEL ]] && { status "$SEL"; [[ $ST == running || $ST == queued ]] && CONFIRM=$SEL; } ;;
    r|R)
      [[ -n $SEL ]] || continue
      status "$SEL"
      if [[ $ST == running || $ST == queued || $ST == stopping ]]; then NOTE="Resume works on finished workers; \"$m_name\" is still $ST."; continue; fi
      if [[ ! -s $SEL/conversation ]]; then NOTE="No conversation id for \"$m_name\": it never started, or ran with --output-format."; continue; fi
      printf '\e[%d;1H\e[K%s' "$ROWS" "${YEL}${B} Follow-up for \"$m_name\" (perm $m_perm), enter sends, empty cancels: ${X}"
      printf '\e[?25h'
      line=; IFS= read -r -u "$kfd" line || true
      printf '\e[?25l'
      if [[ -n ${line//[[:space:]]/} ]]; then
        if resume "$SEL" "$line"; then
          NOTE="Resumed \"$m_name\" as \"${m_name:0:50}+\"."
          printf -v now '%(%s)T' -1; ev "$now" "$m_name" start "$G_RES follow-up sent: $line"
        else
          NOTE="Resume failed: no conversation id."
        fi
      fi
      FULL=1 ;;
    '') # enter: inspect
      [[ -n $SEL ]] || continue
      f=$SEL/report; [[ -s $f ]] || f=$SEL/err
      [[ -f $f ]] || continue
      printf '\e[?25h\e[?1049l'
      ${PAGER:-less -R} "$f" </dev/tty
      printf '\e[?1049h\e[?25l'
      FULL=1 ;;
  esac
done
}
