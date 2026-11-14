# agy-subagent

**AGY Subagent Skill for Claude Code**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![Claude Code Plugin](https://img.shields.io/badge/Claude%20Code-Plugin-purple.svg)](https://claude.ai/code)
[![Antigravity CLI](https://img.shields.io/badge/Antigravity-CLI-orange.svg)](https://antigravity.google)

A Claude Code plugin and skill that allows Claude to orchestrate [Google Antigravity CLI (`agy`)](https://antigravity.google) as autonomous, headless subagent workers. Offload heavy coding tasks, run large refactors, or fan out work across multiple parallel `agy` agents without prompt interruptions.

---

## Key Features

- **Autonomous Subagent Execution**: Spawns `agy` in headless print mode (`agy -p`) with `--dangerously-skip-permissions` to work autonomously without blocking for tool approvals.
- **Ultra-Dense Token Efficiency**: Automatically runs subagents with `/caveman:ultracave`, cutting conversational fluff and returning concise, high-density reports back into Claude's context.
- **Effortless Parallelism**: Claude can spin up multiple `agy` subagents in parallel background bash jobs to work concurrently across files or worktrees.
- **Drop-in Claude Code Skill**: Exposes `/agy:agy <task>` and enables Claude to naturally detect and delegate tasks to `agy` workers.
- **Configurable Flags**: Pass custom flags (e.g., `--model`, `--effort`, `--timeout`) straight to `agy` before tasks.

---

## Prerequisites

1. **Claude Code** installed and configured.
2. **Antigravity CLI (`agy`)** installed and available on your system `PATH`:
   ```bash
   command -v agy
   ```
3. *(Recommended)* **caveman plugin for agy** to enable ultra-dense reports:
   ```bash
   agy plugin install caveman
   ```

---

## Installation

### Via Claude Code Plugin Marketplace

Run these commands inside Claude Code:

```text
/plugin marketplace add MaheshThakur9152/agy-subagent
/plugin install agy@agy-subagent
```

### Local / Development Setup

Clone the repository directly into your plugin directory or link it:

```bash
git clone https://github.com/MaheshThakur9152/agy-subagent.git
```

Load it into your Claude Code session using `/plugin install ./agy-subagent`.

---

## Usage

### 1. From Claude Code

Invoke the skill directly using the slash command or natural conversation:

```text
/agy:agy refactor src/auth.ts to support token refresh rotation
```

Or ask Claude naturally:
- *"Use agy to write unit tests for utils/date.ts"*
- *"Spawn 3 agy subagents to audit the packages/ modules in parallel"*
- *"Delegate the migration script generation to an agy subagent"*

### 2. Manual CLI Invocation

You can also run the underlying runner script directly in your terminal:

```bash
# Basic usage
skills/agy/scripts/agy-run.sh "add a --verbose flag to cli.py"

# Pass custom agy flags before `--`
skills/agy/scripts/agy-run.sh --model gemini-2.5-pro --effort high -- "implement caching in api/client.py"
```

---

## Parallel Subagents & Best Practices

Claude can run any number of `agy` workers simultaneously in the background.

```
       ┌───────────────────────────────┐
       │     Claude (Orchestrator)     │
       └───┬──────────────┬──────────┬─┘
           │              │          │
   (Background)   (Background)  (Background)
           ▼              ▼          ▼
    ┌─────────────┐┌─────────────┐┌─────────────┐
    │ agy worker  ││ agy worker  ││ agy worker  │
    │   (Job 1)   ││   (Job 2)   ││   (Job 3)   │
    └─────────────┘└─────────────┘└─────────────┘
```

When parallelizing:
- **Avoid clobbering**: Ensure each subagent operates on isolated files, or assign each subagent its own `git worktree` using `--add-dir` or separate working directories.
- **Self-contained prompts**: `agy` subagents run as clean, independent processes with no memory of Claude's chat history. Include target file paths, constraints, and success criteria in the task.
- **Review before finalize**: Always review `git diff` after subagents complete their jobs before committing changes.

---

## Safety & Security

> [!WARNING]
> This plugin executes `agy` with `--dangerously-skip-permissions` so that subagents can run unattended without halting for interactive confirmation.
>
> - Only run in repositories managed by version control (`git`) where changes can be reverted.
> - Do not run in untrusted or sensitive environments without isolation.

---

## Project Structure

```text
agy-subagent/
├── .claude-plugin/
│   ├── marketplace.json     # Claude Code marketplace registry definition
│   └── plugin.json          # Plugin metadata & repository link
├── skills/
│   └── agy/
│       ├── SKILL.md         # Skill definition for Claude Code
│       └── scripts/
│           └── agy-run.sh   # Subagent runner script (headless + caveman)
└── README.md
```

---

## License

[MIT](LICENSE) © [MaheshThakur9152](https://github.com/MaheshThakur9152)
