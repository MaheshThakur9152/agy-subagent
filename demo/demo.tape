# Demo video: three real agy workers (2 slots, so one queues) watched in the AGY Control Center.
# Record from the repo root: vhs demo/demo.tape
# Uses your agy login and quota (three short read-only tasks). Runs go to a temp AGY_RUN_DIR.
# Length depends on how fast agy answers; raise the long Sleep if the workers are still running.

Output demo/out/demo.mp4
Output demo/out/demo.gif

# Windows: VHS cannot start Git Bash directly, so it starts PowerShell and opens Git Bash inside
# (hidden). macOS/Linux: use Set Shell "bash" and drop the first hidden Type/Enter/Sleep lines.
Set Shell "powershell"
Set FontSize 18
Set Width 1600
Set Height 960
Set Padding 24
Set Theme "Catppuccin Mocha"
Set TypingSpeed 30ms
Set WindowBar Colorful

Hide
Type "& 'C:\Program Files\Git\bin\bash.exe' --login -i"
Enter
Sleep 3s
Type "cd /d/agy-subagent"
Enter
Type "export AGY_RUN_DIR=$(mktemp -d) AGY_RUN_MAX_JOBS=2 AGY_RUN_UPDATE_CHECK=0 R=skills/agy/scripts/agy-run.sh PS1='\[\e[36m\]$\[\e[0m\] ' && clear"
Enter
Sleep 1s
Show

Type "# three read-only agy workers, at most 2 at once"
Enter
Sleep 500ms
Type `$R --perm sandbox --name runner-review --model gemini-3.8-flash-medium -- "ROLE: Code Reviewer. Read skills/agy/scripts/agy-ui.sh and name its 2 riskiest lines. Read-only. Be brief." >/dev/null 2>&1 &`
Enter
Sleep 400ms
Type `$R --perm sandbox --name tests-map --model gemini-3.8-flash-medium -- "ROLE: Architecture Analyst. List the test files under tests/ and what each covers, one line each. Read-only." >/dev/null 2>&1 &`
Enter
Sleep 400ms
Type `$R --perm sandbox --name version-check --model gemini-3.8-flash-medium -- "ROLE: Architecture Analyst. Check that the version in .claude-plugin/plugin.json matches the newest CHANGELOG.md heading. Read-only. One line." >/dev/null 2>&1 &`
Enter
Sleep 2s

Type "skills/agy/scripts/agy-top.sh"
Enter
Sleep 25s
Down
Sleep 3s
Down
Sleep 3s
Type "?"
Sleep 4s
Type "?"
Sleep 2s
Up
Up
Wait+Screen@300s /3 done/
Sleep 4s
Type "q"
Sleep 1s

Type "# the dashboard detached; reports are in the run log"
Enter
Type "head -n 12 $AGY_RUN_DIR/*/report"
Enter
Sleep 6s
