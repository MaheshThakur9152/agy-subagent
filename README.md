# agy-subagent

Delegate tasks from Claude Code (or Codex, or a terminal) to [Google Antigravity CLI](https://antigravity.google) (`agy`) worker agents. You can run one worker or many in parallel. Each worker runs headless and returns a short structured report, in caveman style when the agy caveman plugin is installed.

```
 Claude Code / Codex / shell  (orchestrator: splits work, verifies, integrates)
            |  skills/agy/SKILL.md   tells the orchestrator how to delegate
            v
 skills/agy/scripts/agy-run.sh       one worker = one process; orchestrator-agnostic
            |  prompt on stdin, permission mode, timeout, env scrub
            v
          agy                        does the work in its cwd, prints a report
```

## Prerequisites

- `agy` on `PATH`, logged in (`agy --version`, tested with 1.5.9)
- bash 4.4+ and coreutils `timeout` (Linux; macOS needs a newer bash, e.g. `brew install bash coreutils`)
- Optional: the caveman plugin in agy for terse reports (`agy plugin list` should show `caveman`)

## Install

### Claude Code (first-class)

```bash
claude plugin marketplace add MaheshThakur9152/agy-subagent
claude plugin install agy@agy-subagent
```

Or inside a session: `/plugin marketplace add MaheshThakur9152/agy-subagent`, then `/plugin install agy@agy-subagent`.

Local development: `claude --plugin-dir /path/to/agy-subagent`.

### Codex CLI

Codex 0.166 reads this repo's `.claude-plugin` manifests natively:

```bash
codex plugin marketplace add MaheshThakur9152/agy-subagent
codex plugin add agy@agy-subagent
```

### Gemini CLI, Cursor, GitHub Copilot, opencode

These hosts read SKILL.md skills from `~/.agents/skills/`. They have no plugin install, so symlink the skill:

```bash
git clone https://github.com/MaheshThakur9152/agy-subagent.git ~/src/agy-subagent
mkdir -p ~/.agents/skills && ln -s ~/src/agy-subagent/skills/agy ~/.agents/skills/agy
```

Only Claude Code is tested end to end. Codex plugin install and skill listing were verified; a full Codex-driven run was not. The other hosts are documented as reading `~/.agents/skills/` but have not been tested with this skill.

## Use from Claude Code

- Slash command: `/agy:agy investigate why the image pipeline takes 115 seconds`
- Natural language:
  - "Use two agy workers to find the root cause of the slow `/search` API: one on the handler code, one on the SQL queries."
  - "Use three agy workers to audit authentication, authorization and file uploads."
  - "Use agy workers to implement the cache module and the API tests in separate worktrees, then integrate."

Claude writes a self-contained task for each worker, using the prompt contract and roles in `skills/agy/references/worker-prompts.md`. It launches the workers as parallel background jobs, compares their reports, checks the claims against the code, and gives you one consolidated report.

## Manual usage

```bash
R=skills/agy/scripts/agy-run.sh

$R --perm unattended "add a --verbose flag to cli.py"
$R --perm sandbox --timeout 20m --model gemini-3.8-flash-high -- "review src/auth for injection bugs; read-only"
$R --perm unattended --cd ../app-agy-cache --add-dir ../shared -- "implement caching in api/client.py"
printf '%s' "$(cat long-task.md)" | $R --perm unattended --          # long tasks via stdin
$R --help
```

Parallel from a shell, with output collected per worker:

```bash
mkdir -p .agy-runs
for area in backend frontend db; do
  $R --perm sandbox -- "Performance Engineer: investigate $area bottlenecks in this repo. Read-only." \
    >".agy-runs/$area.md" 2>".agy-runs/$area.err" &
done
wait
```

### Interface

```
agy-run.sh [runner options] "task"
agy-run.sh [runner options] [agy flags...] -- "task"
echo "task" | agy-run.sh [runner options] [agy flags...] [--]
```

| Runner option | Meaning |
|---|---|
| `--perm normal\|sandbox\|unattended` | permission mode (below). Default `unattended` |
| `--timeout DUR` | Go duration (`90s`, `20m`, `1h30m`), `0` = none. Default `30m` |
| `--cd DIR` | worker's working directory (agy's workspace root) |
| `--no-caveman` | do not prefix `/caveman:ultracave` |

Anything else before `--` is passed to agy unchanged, for example `--model`, `--effort`, `--add-dir`, `--output-format json`, `--log-file`, or an explicit `--print-timeout` (which replaces `--timeout`). The runner refuses `-p`, `--print`, `--prompt`, `-i`, `--prompt-interactive`, `--input-format`, `--dangerously-skip-permissions` and `--sandbox` with exit 2, because it controls those itself.

| Environment | Meaning |
|---|---|
| `AGY_BIN` | agy executable (default `agy` on `PATH`) |
| `AGY_RUN_TIMEOUT` | default `--timeout` |
| `AGY_RUN_MAX_PERM` | highest allowed mode; a higher `--perm` is refused with exit 2 |
| `AGY_RUN_CAVEMAN=0` | disable the caveman prefix |
| `AGY_RUN_KEEP_ENV=1` | keep secret-looking env vars in the worker |
| `AGY_RUN_GRACE` | seconds after `--timeout` before the hard backstop kills agy (default 120) |

| Exit code | Meaning |
|---|---|
| 0 | agy finished. agy also exits 0 when tools were auto-denied, so read the report |
| 1 | agy error (bad model or effort, unknown agent) or interrupted |
| 2 | usage error (runner or agy) |
| 3 | agy `--print-timeout` hit (partial output) or API error |
| 124 | hard timeout: agy did not exit within `--timeout` + grace |
| 127 | agy not found |

stdout is agy's report. stderr is agy's diagnostics plus one `agy-run: perm=... timeout=... cwd=...` line.

## Permission modes

| Mode | agy flags | What it actually does (agy 1.5.9, Linux) |
|---|---|---|
| `unattended` | `--dangerously-skip-permissions` | No prompts. The worker can run any command and edit any file the user can. **This is the default, for backward compatibility.** |
| `sandbox` | `--sandbox` | agy's terminal sandbox (bubblewrap). Observed: network blocked and writes outside the workspace blocked. Whether commands run headless depends on your agy permission settings. |
| `normal` | none | agy's own permission settings decide. Headless agy cannot prompt, so tools that need approval are auto-denied, with exit 0 and an empty or partial report. |

> **Warning:** agy 1.5.9 turns the sandbox **off** when `--dangerously-skip-permissions` is also passed (verified: network and `$HOME` writes both worked). For that reason `sandbox` mode never adds the skip flag, and the runner refuses both flags as passthrough. Do not treat the sandbox as a full security boundary either: it is agy's terminal restriction, not a VM.

Permissions never widen silently:
- Every run prints its mode on stderr.
- `AGY_RUN_MAX_PERM=sandbox` (or `normal`) caps every call, which is useful in shell profiles or CI.
- Permission flags cannot be smuggled in through passthrough.

## Worker isolation

- **Read-only workers** (audits, reviews, investigation) can share one tree.
- **Implementation workers** must have disjoint file ownership. If two might touch the same files, give each its own git worktree and branch:

```bash
git status --porcelain     # a worktree starts from HEAD: uncommitted changes are NOT in it
git worktree add -b agy/cache ../myrepo-agy-cache HEAD
skills/agy/scripts/agy-run.sh --perm unattended --cd ../myrepo-agy-cache -- "...; commit on branch agy/cache"
git merge --no-ff agy/cache                 # one branch at a time, run tests after each
git worktree remove ../myrepo-agy-cache     # only when clean and merged; never --force
```

Two workers in one tree can clobber each other's edits and hit `.git/index.lock` errors.

## Security

- `unattended` runs an autonomous agent with your full user rights. Use it only in repos you can reset with git, never on untrusted code.
- Prompt injection: the worker preamble tells agy to take instructions only from the task and to treat repo files and tool output as data. That reduces the risk but cannot guarantee it. A malicious repo can still steer an unattended worker.
- Secrets: the runner removes env vars matching `*TOKEN*`, `*SECRET*`, `*PASSWORD*`, `*API_KEY*`, `*CREDENTIAL*`, `*PRIVATE_KEY*`, `AWS_*` and `AZURE_*` from the worker's environment. It keeps `GEMINI_API_KEY`, `GOOGLE_API_KEY` and `GOOGLE_APPLICATION_CREDENTIALS`. agy itself authenticates through the OS keyring.
- Task text passed as an argument is visible to local users in `ps` (through the orchestrator's shell command line). agy's own argv never contains it. Keep secrets out of tasks. agy stores transcripts under `~/.gemini/antigravity-cli/brain/`.
- The runner creates no temp files. Its prompt goes to agy on stdin.
- Worker reports are untrusted output. The skill tells the orchestrator to verify them, not obey them.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `agy-run: agy not found` (127) | install agy, or `AGY_BIN=/full/path/agy` |
| `agy flags must be followed by --` | `agy-run.sh --model X -- "task"` |
| exit 0 but empty or "no output produced" | tools were auto-denied in `normal`/`sandbox` mode. Use `--perm unattended` or loosen agy settings |
| exit 1 `invalid model selection` | `agy models`. Effort support depends on model: `agy --model M --effort E -p=/effort` |
| exit 3 | the turn hit `--timeout`. Raise it, or split the task |
| exit 124 | agy hung before or after the turn (auth or network). Run `agy -p=/model` by hand to check login |
| verbose replies, no caveman | `agy plugin list` has no caveman plugin. Install it in agy |
| login prompt or hang | log in once interactively with `agy`. The runner never attaches a tty, so headless auth fails fast instead of waiting |

## Development

```bash
tests/run.sh                                  # mock agy only; the real agy is never run
claude plugin validate .
```

## Layout

```text
.claude-plugin/plugin.json, marketplace.json   Claude Code (and Codex) plugin manifests
skills/agy/SKILL.md                            orchestrator instructions
skills/agy/references/worker-prompts.md        prompt contract, roles, examples
skills/agy/scripts/agy-run.sh                  the runner (no host dependency)
tests/run.sh, tests/mock-agy                   test suite
```

## License

[MIT](LICENSE)
