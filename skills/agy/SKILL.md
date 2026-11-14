---
name: agy
description: Delegate work to Antigravity CLI (agy) subagent worker agents. Use when the user says "agy", "use agy", "run agy", "antigravity", or asks to offload or parallelize tasks to agy subagents. Runs agy headless with --dangerously-skip-permissions and caveman-style replies. Spawn as many agy workers in parallel as the job needs.
---

# agy subagent worker

agy = Google Antigravity CLI. Claude orchestrates; agy subagents execute and report back.

## Run one subagent worker

```bash
"${CLAUDE_PLUGIN_ROOT}/skills/agy/scripts/agy-run.sh" "<task>"
```

Extra agy flags go before `--`:

```bash
"${CLAUDE_PLUGIN_ROOT}/skills/agy/scripts/agy-run.sh" --model <model> --effort high --add-dir ../other -- "<task>"
```

The script always passes `--dangerously-skip-permissions` and starts the prompt with agy's `/caveman:ultracave` skill plus an obey preamble. Never drop those. Needs the caveman plugin installed in agy (`agy plugin list`).

## Many parallel subagents

- No limit on worker count. Split the job into independent tasks, one per subagent.
- Launch each worker as its own Bash call with `run_in_background: true`, all in one message. You get notified as each exits; read its output then.
- Workers sharing files can clobber each other. Give each worker distinct files, or a distinct `git worktree` via `--add-dir` / `cd`.
- Long tasks: add `--print-timeout 30m` (or similar) so a hung worker ends.

## Writing the task

agy subagents have no memory of this conversation. Each task must be self-contained:
- goal, exact file paths, constraints, done condition
- what to report back

## After

Review each subagent's report and diff (`git diff`) before telling the user it is done. agy ran with all permissions auto-approved, so check for unexpected changes.
