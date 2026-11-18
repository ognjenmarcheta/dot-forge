#!/usr/bin/env bash
# Tests for dot standup / update / note and the dot-ai subscription guard, with
# throwaway repos and a stand-in `claude` (nothing leaves the machine).
# shellcheck disable=SC2034  # $out is read by the eval in check()
set -uo pipefail
DOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
S="$DOT/config/scripts"
T="$(mktemp -d)"
FB="$T/fakebin"
mkdir -p "$FB"
export HOME="$T" XDG_CONFIG_HOME="$T/.config" XDG_DATA_HOME="$T/.local/share" XDG_CACHE_HOME="$T/.cache"
export DOT_WORK_NO_GH=1 FAKE_LOG="$T/claude.log" ANTHROPIC_API_KEY=sk-ant-must-not-leak
export PATH="$FB:$PATH"
fails=0
pass() { printf '  ✓ %s\n' "$*"; }
fail() { printf '  ✗ %s\n' "$*"; fails=$((fails + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }
work() { python3 "$S/dot-work" "$@"; }

cat > "$FB/claude" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = auth ]; then printf '{"authMethod":"%s"}\n' "${FAKE_AUTH:-claude.ai}"; exit 0; fi
{ echo "ARGS: $*"; echo "KEY=${ANTHROPIC_API_KEY:-unset}"; cat; } > "$FAKE_LOG"
echo "**Yesterday**"
EOF
chmod +x "$FB/claude"

git config --global user.email me@example.com
git config --global user.name "Test Person"
git config --global init.defaultBranch main
repo() { mkdir -p "$1" && git -C "$1" init -q && git -C "$1" remote add origin "$2"; }
commit() { # dir message [author-email]
    echo "$2" >> "$1/log.txt"; git -C "$1" add log.txt
    git -C "$1" -c user.email="${3:-me@example.com}" commit -qm "$2"
}
repo "$T/Github/client-app" git@github.com:Acme/client-app.git
commit "$T/Github/client-app" "Add CSV export"
commit "$T/Github/client-app" "Someone else's work" other@example.com
repo "$T/Github/internal" https://github.com/me/internal.git
commit "$T/Github/internal" "Internal tooling"
mkdir -p "$T/.config/dotfiles"
cat > "$T/.config/dotfiles/clients.toml" <<'EOF'
[acme]
name = "Acme"
repos = ["github.com/acme/*"]
contact = "Marko"
EOF

echo "dot note / clients"
( cd "$T/Github/client-app" && work note "Marko approved the format" >/dev/null )
work note acme "Call on Friday" >/dev/null
check "note filed under the client" 'grep -q "\[client-app\] Marko approved" "$T/.local/share/dotfiles/notes/acme.md"'
check "clients lists the mapping" 'work clients | grep -q "Acme.*client-app"'

echo "dot standup --context"
out=$(work standup --since "1 day ago" --context)
check "has the client repo" '[[ "$out" == *"Add CSV export"* ]]'
check "has internal work" '[[ "$out" == *"Internal tooling"* ]]'
check "skips commits by other people" '[[ "$out" != *"Someone else"* ]]'
check "has notes" '[[ "$out" == *"Marko approved the format"* && "$out" == *"Call on Friday"* ]]'

echo "dot update --context"
out=$(work update acme --since "1 day ago" --context)
check "only that client repos" '[[ "$out" == *"Add CSV export"* && "$out" != *"Internal tooling"* ]]'
out=$(cd "$T/Github/client-app" && work update --since "1 day ago" --context)
check "client inferred from the repo" '[[ "$out" == *"client-app"* ]]'

echo "writing through dot-ai (stand-in claude)"
work standup --since "1 day ago" --no-copy >/dev/null 2>&1
check "report saved" 'ls "$T"/.local/share/dotfiles/reports/*-standup.md >/dev/null 2>&1'
check "API key removed before claude runs" 'grep -q "^KEY=unset" "$FAKE_LOG"'
check "work log passed on stdin" 'grep -q "Add CSV export" "$FAKE_LOG"'
rm -f "$T/.cache/dotfiles/claude-auth"
check "API-key login refused" '! FAKE_AUTH=api_key "$S/dot-ai" --check 2>/dev/null'
rm -f "$T/.cache/dotfiles/claude-auth"
check "subscription login accepted" '"$S/dot-ai" --check'

rm -rf "$T"
echo
if [ $fails -eq 0 ]; then echo "work: all good"; else echo "work: $fails problem(s)"; fi
[ $fails -eq 0 ]
