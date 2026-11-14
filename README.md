# agy-claude-plugin

Claude Code plugin with one skill, `agy`: Claude delegates tasks to [Antigravity CLI](https://antigravity.google) (`agy`) worker agents.

- agy runs headless (`agy -p`) with `--dangerously-skip-permissions`, always.
- agy is told to follow Claude's task exactly and reply in caveman style (terse, no filler).
- Claude can launch any number of agy workers in parallel (background Bash calls).

## Install

```
/plugin marketplace add MaheshThakur9152/agy-claude-plugin
/plugin install agy@agy-claude-plugin
```

Requires `agy` on `PATH`.

## Use

Ask Claude: "use agy to ..." or "split this across 4 agy agents".

Manual:

```bash
skills/agy/scripts/agy-run.sh "add a --verbose flag to cli.py"
skills/agy/scripts/agy-run.sh --model <model> -- "write tests for utils.py"
```

## Warning

`--dangerously-skip-permissions` lets agy run any command and edit any file without asking. Use in repos you can reset (git), not on sensitive machines.
