# Installation video. Record from the repo root: vhs demo/install.tape
# Uses a throwaway Claude config (CLAUDE_CONFIG_DIR), so your real setup is not touched.
# It installs from GitHub: push first, or the video shows the last pushed version.

Output demo/out/install.mp4
Output demo/out/install.gif

# Windows: VHS cannot start Git Bash directly, so it starts PowerShell and opens Git Bash inside
# (hidden). macOS/Linux: use Set Shell "bash" and drop the first hidden Type/Enter/Sleep lines.
Set Shell "powershell"
Set FontSize 22
Set Width 1400
Set Height 820
Set Padding 28
Set Theme "Catppuccin Mocha"
Set TypingSpeed 40ms
Set WindowBar Colorful

Hide
Type "& 'C:\Program Files\Git\bin\bash.exe' --login -i"
Enter
Sleep 3s
Type "cd /d/agy-subagent"
Enter
Type "export CLAUDE_CONFIG_DIR=$(mktemp -d) PS1='\[\e[36m\]$\[\e[0m\] ' && clear"
Enter
Sleep 1s
Show

Type "# 1. agy (Antigravity CLI) installed and logged in"
Enter
Sleep 600ms
Type "agy --version"
Enter
Sleep 2s

Type "# 2. add the marketplace, install the plugin"
Enter
Sleep 600ms
Type "claude plugin marketplace add MaheshThakur9152/agy-subagent"
Enter
Sleep 12s
Type "claude plugin install agy@agy-subagent"
Enter
Sleep 10s
Type "claude plugin details agy@agy-subagent"
Enter
Sleep 4s

Type "# 3. restart Claude Code, then ask:"
Enter
Type "#    /agy:agy find out why /search is slow"
Enter
Type "#    or: use three agy workers to audit auth, uploads and SQL"
Enter
Sleep 4s
