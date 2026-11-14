# Changelog

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
