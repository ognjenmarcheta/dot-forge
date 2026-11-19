#!/usr/bin/env bash
# Tests for the startup card (dot hello), dot tip and the agent log, in a
# throwaway home folder with stand-ins (nothing leaves the machine).
# shellcheck disable=SC2034  # vars are read by the eval in check()
set -u   # no pipefail: `… | grep -q` checks would fail on SIGPIPE
DOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
S="$DOT/config/scripts"
T="$(cd "$(mktemp -d)" && pwd -P)"
FB="$T/fakebin"
mkdir -p "$FB" "$T/Github"
cd "$T" || exit 1
export HOME="$T" XDG_CONFIG_HOME="$T/.config" XDG_DATA_HOME="$T/.local/share" XDG_CACHE_HOME="$T/.cache" XDG_STATE_HOME="$T/.local/state"
export GIT_CONFIG_GLOBAL="$T/gitconfig" PATH="$FB:$PATH" DOT_PROJECTS="$T/Github"
export DOT_HELLO_NO_REFRESH=1 COLUMNS=110 LINES=40 TERM=xterm-256color COLORTERM=truecolor SHELL=/bin/zsh
unset TERM_PROGRAM NO_COLOR DOT_HELLO DOT_MACHINE_COLOR SSH_CONNECTION CLAUDECODE DOT_CALENDAR_ICS
fails=0
pass() { printf '  ✓ %s\n' "$*"; }
fail() { printf '  ✗ %s\n' "$*"; fails=$((fails + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }
plain() { sed $'s/\033\\[[0-9;]*m//g'; }
hello() { bash "$S/dot-hello" "$@"; }
C="$XDG_CACHE_HOME/dotfiles"

git config --global user.email me@example.com
git config --global user.name "Test Person"
git config --global init.defaultBranch main
# no real desktop notifications from agent-notify
printf '#!/bin/sh\necho "$*" >> "%s/notified"\n' "$T" > "$FB/notify-send"
cp "$FB/notify-send" "$FB/terminal-notifier"
chmod +x "$FB/notify-send" "$FB/terminal-notifier"

echo "logo"
check "byteforge.logo is what make-logo.py draws" 'python3 "$DOT/config/hello/make-logo.py" | cmp -s - "$DOT/config/hello/byteforge.logo"'
check "every logo line is the same width" 'python3 -c "import re,sys; w={len(re.sub(r\"\\{[a-z0-9]+\\}\",\"\",l.rstrip(\"\\n\"))) for l in open(sys.argv[1], encoding=\"utf-8\")}; sys.exit(len(w) != 1)" "$DOT/config/hello/byteforge.logo"'

echo "the card"
out=$(hello show)
p=$(printf '%s' "$out" | plain)
check "logo, user@host, OS, uptime, disk" '[[ "$p" == *"▄████▀"* && "$p" == *"@"* && "$p" == *"OS "* && "$p" == *"Up "* && "$p" == *"GB free"* ]]'
check "truecolor" '[[ "$out" == *$'"'"'\033[38;2;'"'"'* ]]'
check "shows quickly (< 1 s)" 's=$(date +%s); hello show >/dev/null; [ $(( $(date +%s) - s )) -le 1 ]'
check "NO_COLOR = no escapes at all" '! NO_COLOR=1 hello show | grep -q $'"'"'\033'"'"''
check "the slow facts are cached" '[ -s "$C/hello/static" ]'
check "help" 'hello --help | grep -q "dot fetch"'

echo "sizes"
check "narrow pane → one line" '[ "$(COLUMNS=60 hello --startup | wc -l | tr -d " ")" = 1 ]'
check "tiny pane → nothing" '[ -z "$(COLUMNS=30 hello --startup)" ]'
check "DOT_HELLO=compact → one line" '[ "$(DOT_HELLO=compact hello --startup | wc -l | tr -d " ")" = 1 ]'
check "dot hello always shows the full card" '[ "$(COLUMNS=60 hello show | wc -l | tr -d " ")" -gt 5 ]'

echo "colours"
git init -q "$T/Github/app"
expected=$(python3 -c '
p = ["#f5a97f", "#a6da95", "#8aadf4", "#c6a0f6", "#f5bde6", "#eed49f", "#8bd5ca", "#ed8796", "#91d7e3", "#f0c6c6"]
h = 0
for ch in "app": h = (h * 31 + ord(ch)) % 2147483647
c = p[h % 10]
print("\033[38;2;%d;%d;%dm" % (int(c[1:3], 16), int(c[3:5], 16), int(c[5:7], 16)))')
out=$(cd "$T/Github/app" && hello show)
check "in a repo: Project + the WezTerm project colour" '[[ "$(printf "%s" "$out" | plain)" == *"Project app"* && "$out" == *"$expected"* ]]'
mkdir -p "$XDG_CONFIG_HOME/wezterm"
echo 'return { project_colors = { ["app"] = "#123456" }, night = false }' > "$XDG_CONFIG_HOME/wezterm/machine.lua"
check "machine.lua project_colors wins" '(cd "$T/Github/app" && hello show) | grep -q $'"'"'\033\[38;2;18;52;86m'"'"''
check "DOT_MACHINE_COLOR outside a repo" 'DOT_MACHINE_COLOR="#102030" hello show | grep -q $'"'"'\033\[38;2;16;32;48m'"'"''
day=$(DOT_MACHINE_COLOR="#8ea6c6" hello show | head -n 10)
echo 'return { night_hours = { 0, 24 } }' > "$XDG_CONFIG_HOME/wezterm/machine.lua"
night=$(DOT_MACHINE_COLOR="#8ea6c6" hello show | head -n 10)
check "night: the lower half glows (other colours, same top)" '[ "$day" != "$night" ] && [ "$(printf "%s\n" "$day" | sed -n 2p)" = "$(printf "%s\n" "$night" | sed -n 2p)" ]'
rm -f "$XDG_CONFIG_HOME/wezterm/machine.lua"

echo "what's going on"
mkdir -p "$C/agents" "$XDG_DATA_HOME/dotfiles/night"
printf 'waiting\tapp\t1\n' > "$C/agents/s1"
printf 'working\tapi\t1\n' > "$C/agents/s2"
printf '[\n  {"id": "a1", "state": "ready"},\n  {"id": "a2", "state": "queued"}\n]\n' > "$XDG_DATA_HOME/dotfiles/night/queue.json"
echo up > "$C/ci-runner"
p=$(hello show | plain)
check "agents waiting / working" '[[ "$p" == *"● 1 waiting · ⟳ 1 working"* ]]'
check "night shift ready / queued" '[[ "$p" == *"1 ready — dot night report · 1 queued"* ]]'
check "CI runner" '[[ "$p" == *"runner up"* ]]'
git init -q --bare "$T/origin.git"
git clone -q "$T/origin.git" "$T/Github/web" 2>/dev/null
(cd "$T/Github/web" && echo a > a && git add a && git commit -qm one && git push -q origin main 2>/dev/null && echo b > b && git add b && git commit -qm two)
DOT_HELLO_NO_REFRESH='' hello --refresh
check "refresh counts commits on no remote" '[ "$(cat "$C/hello/unpushed")" = "$(printf "1\t1")" ]'
check "card: commits not pushed" 'hello show | plain | grep -q "1 commit in 1 repo not pushed"'
printf '%s\t%s\t%s\n' "$(( $(date +%s) + 600 ))" "14:30" "Acme weekly" > "$C/hello/next-meeting"
check "next meeting, with minutes to go" 'hello show | plain | grep -Eq "📅 14:30 Acme weekly in (9|10) min"'
printf '%s\t%s\t%s\n' "$(( $(date +%s) - 7200 ))" "08:00" "Old" > "$C/hello/next-meeting"
check "a meeting long over isn't shown" '! hello show | plain | grep -q "Old"'

echo "first window of the day"
rm -f "$XDG_STATE_HOME/dotfiles/hello-day"
printf '%s\n%s\n' "$(date +%F)" "🎬 yesterday · 6h · 3 projects" > "$C/hello/credits"
check "yesterday's credits on the first card" 'hello show | plain | grep -q "🎬 yesterday · 6h"'
check "…and not on the next one" '! hello show | plain | grep -q "🎬 yesterday"'

echo "share mode"
mkdir -p "$XDG_STATE_HOME/dotfiles"
printf 'mode=share\nlabel=Acme Corp\nclient=acme\n' > "$XDG_STATE_HOME/dotfiles/mode"
p=$(hello show | plain)
check "SHARING shown, agents / night / git / meetings hidden" '[[ "$p" == *"SHARING · Acme Corp"* && "$p" != *"waiting"* && "$p" != *"ready"* && "$p" != *"not pushed"* && "$p" != *"Acme weekly"* ]]'
mkdir -p "$XDG_CONFIG_HOME/dotfiles/logos"
printf '  ACME  \n ~~~~~~ \n' > "$XDG_CONFIG_HOME/dotfiles/logos/acme.txt"
check "the client's logo instead of the anvil" 'p=$(hello show | plain); [[ "$p" == *"ACME"* && "$p" != *"▄████▀"* ]]'
rm -f "$XDG_STATE_HOME/dotfiles/mode"

echo "setup checklist"
p=$(hello show | plain)
check "logins still to do are listed" '[[ "$p" == *"setup:"*"GitHub CLI login"*"dot hello setup"* ]]'
mkdir -p "$XDG_CONFIG_HOME/gh" "$XDG_DATA_HOME/atuin"
echo "    user: me" > "$XDG_CONFIG_HOME/gh/hosts.yml"
touch "$XDG_DATA_HOME/atuin/session"
p=$(hello setup | plain)
check "dot hello setup: ✓ done, ✗ with the fix" '[[ "$p" == *"✓ GitHub CLI login"* && "$p" == *"✓ History sync"* && "$p" == *"✗ Claude Code login"*"claude, then /login"* ]]'
hello setup --dismiss >/dev/null
check "--dismiss hides the line" '! hello show | plain | grep -q "setup:"'

echo "shell hook"
check "no terminal (scripts, agents, CI) → no card" '[ -z "$(bash -c ". \"$DOT/config/shell/hello.sh\"; _dot_hello")" ]'
check "keeps the exit status for the next prompt hooks" 'bash -c ". \"$DOT/config/shell/hello.sh\"; (exit 3); _dot_hello; [ \$? = 3 ]"'
if command -v zsh >/dev/null 2>&1; then
    check "zsh: runs before the other prompt hooks" 'zsh -fc "precmd_functions=(other); . \"$DOT/config/shell/hello.sh\"; [[ \${precmd_functions[1]} == _dot_hello ]]"'
fi

echo "dot tip"
cat > "$T/tips.tsv" <<'EOF'
# test tips
recall	^dot recall	use dot recall
night	^dot night	use dot night
keys	-	press Leader Space
EOF
printf '#!/bin/sh\n[ "$1" = uuid ] && { echo x; exit 0; }\necho "dot recall 5173"\necho "ls"\n' > "$FB/atuin"
chmod +x "$FB/atuin"
export DOT_TIPS="$T/tips.tsv"
bash "$S/dot-tip" --refresh
check "a feature you've used counts as known" 'grep -qx recall "$C/hello/tips-used" && ! grep -qx night "$C/hello/tips-used"'
t1=$(bash "$S/dot-tip")
check "today's tip is one you haven't used" '[[ "$t1" == *"use dot night"* || "$t1" == *"Leader Space"* ]] && [[ "$t1" != *"recall"* ]]'
check "same tip all day" '[ "$(bash "$S/dot-tip")" = "$t1" ]'
t2=$(bash "$S/dot-tip" next)
check "next: a different one" '[ "$t2" != "$t1" ] && [[ "$t2" != *"recall"* ]]'
check "the card shows today's tip" 'hello show | plain | grep -qF "${t2#💡 }"'
all=$(bash "$S/dot-tip" all)   # (not `| grep -q`: pipefail + SIGPIPE)
check "all: ✓ on the ones you use" '[[ "$all" == *"✓ use dot recall"* ]]'
check "the real tips file parses (3 fields, unique ids)" '[ -z "$(grep -v "^#" "$DOT/config/hello/tips.tsv" | awk -F"\t" "NF != 3")" ] && [ -z "$(grep -v "^#" "$DOT/config/hello/tips.tsv" | cut -f1 | sort | uniq -d)" ]'
unset DOT_TIPS

echo "agent log"
printf '{"session_id":"abc-123","prompt":"fix the tests"}' | (cd "$T/Github/app" && bash "$S/agent-notify" working) >/dev/null
check "one line per hook in agents.log" 'grep -q "	working	app	abc-123$" "$XDG_DATA_HOME/dotfiles/agents.log"'
check "per-session state for the card" '[ "$(cut -f1,2 "$C/agents/abc-123")" = "$(printf "working\tapp")" ]'
printf '{"session_id":"../evil","message":"x"}' | bash "$S/agent-notify" waiting >/dev/null
check "a session id with / doesn't escape the folder" '[ ! -e "$C/evil" ] && [ ! -e "$C/agents/../evil" ]'

[ -n "${KEEP:-}" ] || rm -rf "$T"
echo
if [ "$fails" -eq 0 ]; then echo "hello: all good"; else echo "hello: $fails failed"; exit 1; fi
