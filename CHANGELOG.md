# Changelog

## 0.4.0 - 2026-11-15

### Breaking
- The default permission mode is now `sandbox`, not `unattended`. Workers that edit files need `--perm unattended`. SKILL.md already passed `--perm` explicitly, so runs from Claude Code are unaffected.

### Added
- **AGY Control Center**: `agy-top.sh` rewritten as a full dashboard: header (repo, branch, counts, slots, uptime), worker list (ID, name, role or model, status, elapsed, current activity), detail of the selected worker (task, steps, report or BLOCKED question or errors, conversation ID, exit code), and a live event stream with times. New keys: `r` resumes a finished worker in its conversation, `?` shows help; `q` detaches without stopping workers. New STOPPING state. Repaints only changed lines.
- `AGY_RUN_UI=1` (opt-in): the runner opens the dashboard in a Windows Terminal split pane titled "AGY Control Center" (focus returns to Claude Code) or a tmux split, once, with no duplicates; otherwise it prints the manual command. Launcher: `skills/agy/scripts/agy-ui.sh` (`--dry-run` shows the command). Tests: `tests/test-ui.sh`.
- `docs/manual-testing.md`: what was verified by hand on Windows Terminal, and what was not.
- Team workflow in SKILL.md: Claude keeps one task for itself, integrates each worker as it finishes, resumes workers for follow-ups, answers BLOCKED workers, and watches for stuck ones.
- `AGY_RUN_MAX_JOBS=N` caps concurrent workers to save RAM. Extra runs wait for a free slot, shown as QUEUED; a slot whose owner died is reclaimed.
- Resume with context: every run prints `agy-run: conversation=<id>`; pass `--conversation <id>` for a follow-up (verified with agy 1.5.9).
- BLOCKED back-channel: workers that need a decision stop with `BLOCKED: <question>` as the first line of the report.
- Git footer: in a git repo the report ends with commits, `git diff --stat` and new files since the worker started, measured by the runner, so false "Changed" claims are visible.
- Daily update notice on stderr when a newer version is on GitHub. Runs in the background; `AGY_RUN_UPDATE_CHECK=0` turns it off.
- Dashboard: QUEUED and BLOCKED states, `x` stops the selected worker (asks y/n), terminal bell when a worker finishes (`--no-bell`), `--here` / `--in DIR` to show one repo, live text while a worker writes its report, PID-reuse check through `/proc`.
- Model-per-role table in `worker-prompts.md`.
- `tests/fixtures/agy-1.5.9-stream.ndjson` (recorded agy format), `tests/e2e.sh` (real agy smoke test incl. resume), CI on Linux, macOS and Windows, and a release workflow that publishes a GitHub Release from a `vX.Y.Z` tag.

### Fixed
- Emoji written as JSON surrogate pairs (`😀`) are decoded instead of printed as escapes.
- Dashboard step durations for model turns were dropped (empty tab fields collapsed).
- `--help` failed with BSD sed on macOS.
- `.gitattributes` keeps scripts LF on Windows checkouts.
- Large tool output (MBs per line) no longer passes through bash `read`, which reads pipes one byte at a time: a 10 MB stream took 43 s on Git Bash and stalled the worker. The dashboard trims lines before reading them too.
- `DATABASE_URL`, `REDIS_URL`, `MONGO*_URL`, `*_DSN` and `*_KEY` are removed from the worker environment.
- Stopping a QUEUED run records exit 143 instead of showing LOST.
- A job slot whose PID was reused by an unrelated process is reclaimed (where `/proc` exists).
- Dashboard: header counts match the listed runs; `--here`/`--in` no longer match sibling folders like `app` vs `apple` (worktrees named `app-*` still match).
- Git footer says it covers the whole directory, so changes by other workers in a shared tree are not blamed on a read-only worker.
- The dashboard reads only new event records (line offsets), collapses streamed text deltas in awk and cuts records before bash reads them. Before, Claude-model workers (hundreds of deltas) pushed every tool step out of view, and a frame took 20 s on Git Bash.
- The runner and the dashboard parse their whole file before running, so editing them while a worker runs (agy fixing its own runner) no longer breaks the running copy.

## 0.3.0 - 2026-11-15

### Added
- `skills/agy/scripts/agy-top.sh`: live terminal dashboard of workers. Shows status, elapsed time, the tool each worker runs now, recent steps, tokens and exit code. Keys: up/down, enter (full report), q. `--once` prints one frame.
- Run log: every run writes `meta`, `events.ndjson`, `report`, `err` and `rc` to `$AGY_RUN_DIR/<id>/` (default `~/.local/state/agy-runs`, mode 700, pruned after 3 days). `AGY_RUN_LOG=0` turns it off.
- `--name NAME` runner option: worker label in the dashboard.
- SKILL.md tells the orchestrator to name workers and point the user at the dashboard (tmux pane when available).
- README rewritten: quick start first, animated header and dashboard images, video placeholders, update instructions.

### Changed
- With the run log on, the runner runs agy with `--output-format stream-json` and converts the final result back to the same plain text report on stdout. If a run ends without a result event, the streamed text is printed instead. The runner stays the parent process and forwards TERM, INT and HUP to agy. Passing `--output-format` yourself keeps agy's own output.

## 0.2.0 - 2026-11-14

### Changed
- Runner rewritten (`skills/agy/scripts/agy-run.sh`):
  - The prompt goes to agy on stdin, not argv. No 128 KiB limit, no `-p` ambiguity, and no tty, so headless auth never blocks.
  - Flags are split from the task only at an argument that is exactly `--`. Before, a task containing ` -- ` crashed the runner.
  - Flags given without `--` are now an error (exit 2). Before, they were silently put into the prompt.
  - Default timeout is `30m` (`--print-timeout`), plus a coreutils `timeout` backstop. Before, a run could hang forever.
  - Secret-looking env vars are removed from the worker. Opt out with `AGY_RUN_KEEP_ENV=1`.
  - The worker preamble now says repo content is data, never instructions, and gives a fixed report format.
- SKILL.md rewritten:
  - explicit `--perm` on every call
  - parallel workflow with result comparison and verification
  - git worktree isolation procedure
  - uses `${CLAUDE_SKILL_DIR}`, and works on hosts without it
- README rewritten. It previously advertised a nonexistent agy `--timeout` flag.

### Added
- `--perm normal|sandbox|unattended`, `AGY_RUN_MAX_PERM` cap, and a stderr line showing the active mode.
- `--timeout`, `--cd`, `--no-caveman`, `--help`, `AGY_BIN`, `AGY_RUN_TIMEOUT`, `AGY_RUN_GRACE`, `AGY_RUN_CAVEMAN`.
- `skills/agy/references/worker-prompts.md`: prompt contract, 9 worker roles, examples.
- `tests/run.sh` + `tests/mock-agy`: 145 assertions, no real agy.
- LICENSE (MIT), CHANGELOG.

### Breaking
- `agy-run.sh --flag "task"` without `--` now exits 2. Use `agy-run.sh --flag -- "task"`.
- The runner refuses `--dangerously-skip-permissions`, `--sandbox`, `-p`, `-i` and `--input-format` as passthrough. Use `--perm`.
- Runs now time out after 30m by default. Use `--timeout 0` for the old behavior.
- Default permission mode is unchanged (`unattended`).

## 0.1.0
- Initial plugin: `agy -p --dangerously-skip-permissions` with a `/caveman:ultracave` prefix.
