#!/usr/bin/env bash
# Record the README videos with VHS (https://github.com/charmbracelet/vhs).
# Usage: demo/record.sh [install|demo]   (default: both). Output: demo/out/*.mp4 and *.gif
set -euo pipefail
cd "$(dirname "$0")/.."
missing=()
for t in vhs ttyd ffmpeg agy claude; do command -v "$t" >/dev/null || missing+=("$t"); done
if ((${#missing[@]})); then
  echo "record: missing ${missing[*]}" >&2
  echo "Windows: winget install -e --id charmbracelet.vhs; winget install -e --id tsl0922.ttyd; winget install -e --id Gyan.FFmpeg   (then open a new terminal)" >&2
  echo "macOS:   brew install vhs        Linux: see https://github.com/charmbracelet/vhs#installation" >&2
  exit 1
fi
mkdir -p demo/out
for v in "${@:-install demo}"; do
  for t in $v; do
    echo "record: $t" >&2
    vhs "demo/$t.tape"
  done
done
ls -lh demo/out
