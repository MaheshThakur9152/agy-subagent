#!/usr/bin/env bash
# Run one agy worker headless: permissions always skipped, agy's /caveman:ultracave skill on, obeys Claude's task.
# Usage: agy-run.sh [extra agy flags...] -- "task"   (or just: agy-run.sh "task")
set -euo pipefail
command -v agy >/dev/null || { echo "agy not found on PATH" >&2; exit 127; }

flags=()
if [[ " $* " == *" -- "* ]]; then
  while [[ $1 != "--" ]]; do flags+=("$1"); shift; done
  shift
fi
task="$*"
[[ -n $task ]] || { echo "usage: agy-run.sh [agy flags] -- \"task\"" >&2; exit 2; }

preamble='You are a worker agent. Claude (the orchestrator) gives you a task. Do exactly that task, nothing more. Do not ask questions; make reasonable choices and finish. End with a short report: what changed (file paths), what you ran, what failed.'

exec agy --dangerously-skip-permissions "${flags[@]}" -p "/caveman:ultracave $preamble

TASK:
$task"
