# Manual testing report: AGY Control Center (0.4.0)

What was checked by hand, on which system, and what was not. Automated tests (`tests/run.sh`, `tests/test-ui.sh`) cover the rest with a mock agy and fake `wt.exe`, `tmux` and `cygpath`.

## Environment

- Windows 11 Home (10.0.26300), Windows Terminal (`WT_SESSION` set), Git for Windows bash 5.2.37 (MINGW64)
- agy 1.5.9, models `gemini-3.8-flash-high` and `claude-sonnet-4-6`
- Date: 2026-11-15

## Verified

| Check | How | Result |
|---|---|---|
| Launcher command | `agy-ui.sh --dry-run` | `wt.exe -w 0 split-pane -V --size 0.4 --title "AGY Control Center" ... -d D:/agy-subagent "C:/Program Files/Git/bin/bash.exe" --login .../agy-top.sh --in D:/agy-subagent ; move-focus previous` |
| Real pane opens | `agy-ui.sh --dir /d/agy-subagent` from Claude Code's Bash tool | exit 0; a dashboard process registered in `.dashboards/` within 10 s; its command line was `/usr/bin/bash --login D:/agy-subagent/skills/agy/scripts/agy-top.sh --in D:/agy-subagent` |
| Launch lock released | after the pane started | `.ui-lock` gone |
| No duplicate pane | second `agy-ui.sh` call | `agy-ui: dashboard already open (pid 1930)`, exit 0, no second pane |
| Dashboard stays up | alive 3 s after start | yes |
| Clean exit | `kill -TERM` on the dashboard | it exited, the pane closed, the `.dashboards/<pid>` file was removed |
| `AGY_RUN_UI=1` with a real worker | `AGY_RUN_UI=1 agy-run.sh --perm sandbox ...` (real agy) | pane opened (dashboard pid 1337), worker exit 0, stdout was only the report, stderr only the usual `agy-run:` lines |
| Dashboard on real agy logs | `agy-top.sh --once` on 4 real runs, one with 1262 event records (Claude model, many text deltas) | steps, tool count (28), tokens (74.4k) and conversation ID shown; 1.8 s cold on Git Bash |
| Real agy smoke test | `AGY_E2E=1 tests/e2e.sh` | all checks pass, including resume with `--conversation` |

## Not verified

- **Focus return.** `move-focus previous` ran without error, but whether focus actually went back to the Claude Code pane was not observed.
- **Keys in a real terminal.** Arrow keys, `enter` with `less`, `r` with typed text, and resize were tested only with keys fed from a file or FIFO, not typed into the pane.
- **Closing the pane window** while a worker started from the dashboard with `r` runs. Such workers use `nohup`, but Windows may still end them when the pane closes.
- **tmux, Linux and macOS.** Only the fake-`tmux` tests ran. CI runs the suite on Linux, macOS and Windows, but no real tmux pane was opened.
- **WSL inside Windows Terminal.** There is no `cygpath` there, so the launcher falls back to printing the manual command; this path was not run.
