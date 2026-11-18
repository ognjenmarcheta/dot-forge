#!/usr/bin/env bash
# Tests for dot night / recall / habits / mode / new, with throwaway repos and
# stand-ins for `claude` and `gh` (nothing leaves the machine).
# shellcheck disable=SC2034,SC2088  # vars are read by the eval in check(); ~ is meant literally
set -uo pipefail
DOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
S="$DOT/config/scripts"
T="$(mktemp -d)"
FB="$T/fakebin"
mkdir -p "$FB" "$T/Github"
cd "$T" || exit 1   # never run the stand-ins inside the dotfiles repo
export HOME="$T" XDG_CONFIG_HOME="$T/.config" XDG_DATA_HOME="$T/.local/share" XDG_CACHE_HOME="$T/.cache" XDG_STATE_HOME="$T/.local/state"
export GIT_CONFIG_GLOBAL="$T/gitconfig" FAKE_LOG="$T/claude.log" ANTHROPIC_API_KEY=sk-ant-must-not-leak
export PATH="$FB:$PATH" DOT_PROJECTS="$T/Github"
unset TERM_PROGRAM
fails=0
pass() { printf '  ✓ %s\n' "$*"; }
fail() { printf '  ✗ %s\n' "$*"; fails=$((fails + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }
py() { python3 "$S/$1" "${@:2}"; }

git config --global user.email me@example.com
git config --global user.name "Test Person"
git config --global init.defaultBranch main

# a repo with an origin
git init -q --bare "$T/origin.git"
git clone -q "$T/origin.git" "$T/Github/app" 2>/dev/null
echo hi > "$T/Github/app/README.md"
echo "SECRET=1" > "$T/Github/app/.env"
echo ".env" > "$T/Github/app/.gitignore"
git -C "$T/Github/app" add README.md .gitignore
git -C "$T/Github/app" commit -qm "chore: init"
git -C "$T/Github/app" push -q origin main
git -C "$T/Github/app" remote set-head origin main

# claude: edits, commits (with the attribution it isn't supposed to add), reports
cat > "$FB/claude" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = auth ]; then printf '{"authMethod":"%s"}\n' "${FAKE_AUTH:-claude.ai}"; exit 0; fi
{ echo "ARGS: $*"; echo "KEY=${ANTHROPIC_API_KEY:-unset}"; echo "PWD=$PWD"; cat; } > "$FAKE_LOG"
case "${FAKE_MODE:-}" in
    limit) printf '{"is_error":true,"result":"Claude usage limit reached. Your limit will reset at 5am."}\n'; exit 1 ;;
    plain) echo "The API said it listens on port 4000."; exit 0 ;;
esac
# only the night shift gets the "edit and commit" act, and only in its worktree
if [ "${DOT_NIGHT:-}" != 1 ] || [[ "$PWD" != */.night/* ]]; then echo '["dclog","kklogs"]'; exit 0; fi
echo fixed >> README.md
git add README.md
git commit -qm "docs: fix readme" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_x"
printf '{"is_error":false,"num_turns":7,"result":"STATUS: READY\\nFixed the README.\\nRan the tests."}\n'
EOF
cat > "$FB/gh" <<'EOF'
#!/usr/bin/env bash
echo "gh $*" >> "$FAKE_LOG.gh"
case "$1 $2" in "pr create") echo "https://github.com/me/app/pull/7" ;; esac
EOF
chmod +x "$FB/claude" "$FB/gh"

echo "dot night"
out=$(cd "$T" && py dot-night "app: fix the readme typo")
id=$(printf '%s' "$out" | sed -n 's/.*queued \([0-9a-z]*\) for.*/\1/p')   # not a tty: no colours
check "queued with an id" '[ -n "$id" ]'
check "listed" 'py dot-night list | grep -q "fix the readme typo"'
out=$(cd "$T/Github/app" && py dot-night "add a changelog")
check "queues for the repo you are in" '[[ "$out" == *"for"*"app"* ]]'
id2=$(printf '%s' "$out" | sed -n 's/.*queued \([0-9a-z]*\) for.*/\1/p')
py dot-night cancel "$id2" >/dev/null
py dot-night run >/dev/null 2>&1
check "API key never reaches claude" 'grep -q "^KEY=unset" "$FAKE_LOG"'
check "runs unattended (dontAsk), push denied" 'grep -q -- "--permission-mode dontAsk" "$FAKE_LOG" && grep -q "Bash(git push\*)" "$FAKE_LOG"'
check "asks for no attribution" 'grep -q "\"commit\": \"\"" "$FAKE_LOG"'
check "runs in a worktree, not your checkout" 'grep -q "^PWD=$T/Github/.night/app-$id" "$FAKE_LOG"'
wt="$T/Github/.night/app-$id"
check "your checkout untouched" '[ -z "$(git -C "$T/Github/app" status --porcelain)" ] && [ "$(git -C "$T/Github/app" rev-parse --abbrev-ref HEAD)" = main ]'
check ".env copied into the worktree" '[ -f "$wt/.env" ]'
check "on a night/ branch" 'git -C "$wt" rev-parse --abbrev-ref HEAD | grep -q "^night/"'
check "AI attribution stripped from commits" '! git -C "$wt" log -1 --format=%B | grep -qiE "co-authored-by|claude-session"'
check "commit message kept" 'git -C "$wt" log -1 --format=%s | grep -q "docs: fix readme"'
check "state ready" 'grep -q "\"state\": \"ready\"" "$XDG_DATA_HOME/dotfiles/night/queue.json"'
check "cancelled task didn't run" 'grep -q "\"state\": \"cancelled\"" "$XDG_DATA_HOME/dotfiles/night/queue.json"'
check "first-prompt line written" 'grep -q "1 ready" "$XDG_DATA_HOME/dotfiles/night/unseen"'
out=$(py dot-night report)
check "report shows the summary and next step" '[[ "$out" == *"Fixed the README"* && "$out" == *"dot night pr $id"* ]]'
check "report seen once" '! py dot-night report | grep -q "Fixed the README"'
py dot-night pr "$id" >/dev/null 2>&1
check "pr pushes the branch" 'git -C "$T/Github/app" ls-remote --heads origin | grep -q night/'
check "draft PR without STATUS line" 'grep -q "pr create --draft" "$FAKE_LOG.gh" && ! grep -q "STATUS:" "$FAKE_LOG.gh"'
check "state pr" 'py dot-night list | grep -q "pull/7"'
py dot-night clean >/dev/null
check "clean removes the worktree" '[ ! -d "$wt" ]'
py dot-night "app: second" >/dev/null
FAKE_MODE=limit py dot-night run >/dev/null 2>&1
check "usage limit → stays queued" 'py dot-night list | grep "second" | grep -q "⏳"'
rm -f "$XDG_CACHE_HOME/dotfiles/claude-auth"   # dot-ai caches a good login for 6 h
: > "$FAKE_LOG"
FAKE_AUTH=apiKey py dot-night run >/dev/null 2>&1
rc=$?
check "won't start without the subscription login" '[ "$rc" -ne 0 ] && ! grep -q "^ARGS: -p" "$FAKE_LOG" && py dot-night list | grep "second" | grep -q "⏳"'
rm -f "$XDG_CACHE_HOME/dotfiles/claude-auth"

echo "dot recall"
R="$XDG_DATA_HOME/dotfiles/recall"
mkdir -p "$R"
printf '%s\n' "{\"t\":\"$(date -u +%FT%TZ)\",\"cwd\":\"$T/Github/app\",\"cmd\":\"pnpm dev\",\"status\":0,\"out\":\"vite\\n  Local:   http://localhost:5173/\"}" > "$R/$(date +%F).jsonl"
printf '%s\n' '{"t":"2020-01-01T00:00:00Z","cwd":"/","cmd":"old","status":0,"out":"old"}' > "$R/2020-01-01.jsonl"
out=$(py dot-recall 5173)
check "finds output text" '[[ "$out" == *"pnpm dev"* && "$out" == *"localhost:5173"* ]]'
check "prunes old days" '[ ! -f "$R/2020-01-01.jsonl" ]'
check "--cmd matches commands only" 'py dot-recall --cmd 5173 >/dev/null; [ $? -eq 1 ]'
check "--here limits to the repo" '(cd "$T/Github/app" && py dot-recall --here 5173 >/dev/null) && ! (mkdir -p "$T/elsewhere" && cd "$T/elsewhere" && py dot-recall --here 5173 >/dev/null 2>&1)'
FAKE_MODE=plain py dot-recall --ai "what port is vite on?" >/dev/null
check "--ai goes through dot-ai (no API key)" 'grep -q "^KEY=unset" "$FAKE_LOG" && grep -q "localhost:5173" "$FAKE_LOG"'
check "--forget" 'py dot-recall --forget >/dev/null && [ ! -d "$R" ]'
if command -v lua5.4 >/dev/null || command -v lua >/dev/null; then
    LUA=$(command -v lua5.4 || command -v lua)
    masked=$(cd "$DOT/config/wezterm" && "$LUA" - <<'EOF'
local function any() return setmetatable({}, {__index=function() return any end, __call=function() return any() end, __concat=function() return "" end}) end
package.loaded.wezterm = setmetatable({home_dir="/tmp/x", GLOBAL={}, target_triple="x86_64-unknown-linux-gnu"}, {__index=function() return any() end})
package.path = "./?.lua;" .. package.path
print(require("features").mask_secrets("GH_TOKEN=ghp_abc123 key sk-ant-xyz https://u:pw@h password: hunter2 keep"))
EOF
)
    check "secrets masked before saving" '[[ "$masked" != *ghp_abc123* && "$masked" != *sk-ant-xyz* && "$masked" != *hunter2* && "$masked" != *":pw@"* && "$masked" == *keep* ]]'
fi

echo "dot habits"
mkdir -p "$T/repo/config/shell" "$T/repo/config/navi/cheats" "$XDG_CONFIG_HOME"
ln -sfn "$T/repo/config/shell" "$XDG_CONFIG_HOME/shell"
ln -sfn "$T/repo/config/navi" "$XDG_CONFIG_HOME/navi"
echo "alias gs='git status --short --branch --ahead-behind'" > "$T/repo/config/shell/aliases.sh"
H="$T/history.tsv"
now=$(date '+%Y-%m-%d %H:%M:%S')
: > "$H"
for _ in 1 2 3 4 5 6 7; do printf '%s\t0\t%s\n' "$now" "docker compose logs -f api | grep ERROR" >> "$H"; done
for _ in 1 2 3 4 5 6 7; do printf '%s\t0\t%s\n' "$now" "git status --short --branch --ahead-behind" >> "$H"; done
for _ in 1 2 3 4 5 6 7; do printf '%s\t0\t%s\n' "$now" "export GH_TOKEN=ghp_0123456789abcdef0123" >> "$H"; done
for _ in 1 2 3 4 5 6 7; do printf '%s\t1\t%s\n' "$now" "pnpm run something-that-always-fails" >> "$H"; done
for a in web api db cache mail jobs pay sync search auth; do printf '%s\t0\t%s\n' "$now" "kubectl --kubeconfig ~/.kube/k3s-arc.yaml logs -n arc $a" >> "$H"; done
export DOT_HABITS_FROM="$H"
check "counts suggestions" '[ "$(py dot-habits --check)" = 2 ]'
in_tty() { # run a command with a terminal (dot habits asks on /dev/tty)
    if [ "$(uname -s)" = Darwin ]; then script -q /dev/null "$@"; else script -qfc "$*" /dev/null; fi
}
in_tty python3 "$S/dot-habits" < <(sleep 1; printf 'y\n'; sleep 0.5; printf 'y\n') > "$T/habits.out" 2>&1 || true
check "aliases written to the repo" 'grep -q "^alias .*docker compose logs -f api | grep ERROR" "$T/repo/config/shell/habits.sh" && grep -q "kubectl --kubeconfig" "$T/repo/config/shell/habits.sh"'
check "skips secrets, failures, existing aliases" '! grep -qE "GH_TOKEN|always-fails|git status" "$T/repo/config/shell/habits.sh"'
check "habits.sh is valid shell" 'bash -n "$T/repo/config/shell/habits.sh"'
check "accepted ones aren't suggested again" '[ "$(py dot-habits --check)" = 0 ]'
unset DOT_HABITS_FROM

echo "dot mode"
mkdir -p "$T/Github/acme-web" && git -C "$T/Github/acme-web" init -q
py dot-work clients --add acme "~/Github/acme-web" --name "Acme Corp" >/dev/null
out=$(TERM_PROGRAM=WezTerm bash "$S/dot-mode" share acme)
var=$(printf '%s' "$out" | grep -ao 'dot_mode=[A-Za-z0-9+/=]*' | head -1 | cut -d= -f2-)
json=$(printf '%s' "$var" | base64 -d)
check "tells WezTerm: share, label, folders" '[[ "$json" == *"\"mode\":\"share\""* && "$json" == *"Acme Corp"* && "$json" == *"acme-web"* ]]'
check "state file while sharing" 'grep -q "mode=share" "$XDG_STATE_HOME/dotfiles/mode"'
check "status" 'bash "$S/dot-mode" status | grep -q "sharing: Acme Corp"'
ZDOTDIR="$T" zsh -c ". '$DOT/config/shell/share.sh'; _dot_share_risky 'cat .env.local'" && pass "guard: cat .env is risky" || fail "guard: cat .env is risky"
ZDOTDIR="$T" zsh -c ". '$DOT/config/shell/share.sh'; ! _dot_share_risky 'cat README.md' && ! _dot_share_risky 'environment-check'" && pass "guard: ordinary commands pass" || fail "guard: ordinary commands pass"
bash "$S/dot-mode" work >/dev/null
check "work ends it" '[ ! -f "$XDG_STATE_HOME/dotfiles/mode" ] && bash "$S/dot-mode" status | grep -q normal'
ZDOTDIR="$T" zsh -c ". '$DOT/config/shell/share.sh'; ! _dot_share_risky 'cat .env'" && pass "guard off when not sharing" || fail "guard off when not sharing"

echo "dot new"
out=$(bash "$S/dot-new" portal --local --dry-run --client acme --title "Acme Portal" 2>&1)
check "dry run plans the kaine-forge steps" '[[ "$out" == *"template:adopt --config template-adoption.json --write"* && "$out" == *"ai:install -- --non-interactive"* && "$out" == *"ai:doctor"* ]]'
check "adoption config" '[[ "$out" == *"\"productName\": \"Acme Portal\""* && "$out" == *"software.byteforge.portal"* && "$out" == *"\"repoSlug\": \"portal\""* ]]'
check "commit without AI attribution" '[[ "$out" == *"chore: adopt Kaine Forge template as Acme Portal"* && "$out" != *"Co-Authored"* ]]'
check "files it under the client" '[[ "$out" == *"clients --add acme ~/Github/portal"* ]]'
check "bad names refused" '! bash "$S/dot-new" "Bad Name" --local --dry-run >/dev/null 2>&1'
check "bad --id refused" '! bash "$S/dot-new" ok --local --dry-run --id "not valid" >/dev/null 2>&1'

[ -n "${KEEP:-}" ] || rm -rf "$T"; echo "T=$T"
echo
if [ "$fails" -eq 0 ]; then echo "features: all good"; else echo "features: $fails failed"; exit 1; fi
