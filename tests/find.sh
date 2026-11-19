#!/usr/bin/env bash
# Tests for dot find and z "…" (find a project by what it is), with throwaway
# repos, a stand-in embedder (no model download) and a stand-in zoxide.
# shellcheck disable=SC2016,SC2034  # check() evals its test strings (and reads the vars)
set -uo pipefail
DOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
S="$DOT/config/scripts"
T="$(cd "$(mktemp -d)" && pwd -P)"
FB="$T/fakebin"
mkdir -p "$FB" "$T/Github" "$T/.config/dotfiles"
cd "$T" || exit 1
export HOME="$T" XDG_CONFIG_HOME="$T/.config" XDG_CACHE_HOME="$T/.cache" XDG_STATE_HOME="$T/.local/state"
export GIT_CONFIG_GLOBAL="$T/gitconfig" PATH="$FB:$PATH" DOT_PROJECTS="$T/Github" DOT_FIND_NO_PICK=1
export FAKE_EMBED_LOG="$T/embed.log"
unset DOT_FIND_MODEL
fails=0
pass() { printf '  ✓ %s\n' "$*"; }
fail() { printf '  ✗ %s\n' "$*"; fails=$((fails + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }
find_() { python3 "$S/dot-find" "$@"; }

git config --global user.email me@example.com
git config --global user.name "Test Person"
git config --global init.defaultBranch main

repo() { # name readme [commit subject]
    git init -q "$T/Github/$1"
    printf '%s\n' "$2" > "$T/Github/$1/README.md"
    git -C "$T/Github/$1" add README.md
    git -C "$T/Github/$1" commit -qm "${3:-chore: init}"
}
repo mo "# Mo
A calm Mandarin workspace: dictionary lookup, handwriting practice, spaced review and graded reading."
repo salvage "# Salvage
Data recovery for Windows and Linux. Quick scan recovers deleted files." "feat: deep scan for NTFS"
repo portal "# Portal
Customer portal: invoices, billing history and payment methods." "fix(billing): round VAT per line"
repo infra "# Infra
Terraform for the servers."
git -C "$T/Github/portal" remote add origin git@github.com:acme-corp/portal.git
git -C "$T/Github/salvage" worktree add -q -b deep-scan "$T/Github/salvage-deep" 2>/dev/null
cat > "$T/.config/dotfiles/clients.toml" <<'EOF'
[acme]
name = "Acme Corp"
repos = ["github.com/acme-corp/*"]
EOF

# stand-in embedder: bag of words over a few "meanings" (chinese ~ mandarin,
# recover ~ undelete…), so meaning can find what keywords can't
cat > "$FB/fake-embed" <<'EOF'
#!/usr/bin/env python3
import json, os, re, sys
req = json.load(sys.stdin)
with open(os.environ["FAKE_EMBED_LOG"], "a") as f:
    f.write(f"{req['kind']} {len(req['texts'])}\n")
if os.environ.get("FAKE_EMBED_FAIL"):
    sys.exit(1)
groups = [["mandarin", "chinese", "hanzi", "language", "dictionary"],
          ["recovery", "recover", "undelete", "deleted", "rescue"],
          ["billing", "invoice", "invoices", "payment", "money"],
          ["terraform", "servers", "cloud", "infrastructure"]]
out = []
for t in req["texts"]:
    ws = re.findall(r"[a-z]+", t.lower())
    v = [sum(w in g for w in ws) + 0.01 for g in groups]
    out.append(v)
json.dump(out, sys.stdout)
EOF
chmod +x "$FB/fake-embed"
export DOT_FIND_EMBED_CMD="$FB/fake-embed"

echo "dot find"
out=$(find_ --index)
check "--index reads every repo and the worktree" '[[ "$out" == "indexed 5 projects — meaning"* ]]'
check "…embedding passages once" 'grep -q "^passage " "$FAKE_EMBED_LOG"'
: > "$FAKE_EMBED_LOG"
find_ --index >/dev/null
check "nothing changed → nothing embedded again" '! grep -q "^passage" "$FAKE_EMBED_LOG"'

out=$(find_ "data recovery")
check "keywords: data recovery → salvage first, marked" '[[ "$(printf "%s" "$out" | head -1)" == *"→"*salvage* ]]'
check "…with the line that matched" '[[ "$out" == *"Data recovery for Windows"* ]]'
out=$(find_ "chinese learning")
check "meaning: chinese → the Mandarin app (no shared keyword)" '[[ "$(printf "%s" "$out" | head -1)" == *mo* ]]'
out=$(find_ "acme")
check "client from clients.toml: acme → portal" '[[ "$(printf "%s" "$out" | head -1)" == *portal* ]]'
check "…and says so" '[[ "$out" == *"client: Acme Corp"* ]]'
out=$(find_ "deep scan")
check "worktree by its branch: deep scan → a salvage checkout" '[[ "$(printf "%s" "$out" | head -1)" == *salvage* ]]'

path=$(find_ --cd "undelete files" 2>"$T/err")
check "--cd prints the folder" '[ "$path" = "$T/Github/salvage" ]'
check "…and where it went on stderr" 'grep -q "→ ~/Github/salvage" "$T/err"'

: > "$FAKE_EMBED_LOG"
git -C "$T/Github/infra" commit -q --allow-empty -m "feat: add the staging cluster"
find_ --index >/dev/null
check "a new commit → only that repo is read again" '[ "$(grep "^passage" "$FAKE_EMBED_LOG" | wc -l | tr -d " ")" = 1 ]'

out=$(FAKE_EMBED_FAIL=1 DOT_FIND_MODEL=other find_ --index 2>&1)
check "embedder fails → keywords only, said once" '[[ "$out" == *"keywords only"* ]]'
out=$(DOT_FIND_MODEL=other find_ "billing")
check "…and searching still works" '[[ "$(printf "%s" "$out" | head -1)" == *portal* ]]'
out=$(DOT_FIND_EMBED=0 find_ --status)
check "--status lists the projects" '[[ "$out" == *"keywords only"* && "$out" == *portal* ]]'
check "no repos → exit 1" '! DOT_PROJECTS="$T/none" XDG_CACHE_HOME="$T/c2" DOT_FIND_EMBED=0 find_ --cd "x y" 2>/dev/null'
find_ --index >/dev/null   # back to the stand-in model

echo "z \"…\" in bash and zsh"
mkdir -p "$T/.config"
ln -s "$S" "$T/.config/scripts"
# stand-in zoxide: knows only ~/Github/infra; `z` from its init just cd's
cat > "$FB/zoxide" <<'EOF'
#!/usr/bin/env bash
case "$1" in
    query) shift; for a in "$@"; do case "$a" in --*|-) ;; *infra*) echo "$HOME/Github/infra"; exit 0 ;; esac; done; exit 1 ;;
esac
EOF
chmod +x "$FB/zoxide"
block="$(sed -n '/^# --- z by meaning/,/^# --- zsh: syntax highlighting/p' "$DOT/config/shell/aliases.sh")"
cat > "$T/zrun.sh" <<EOF
_dot_has() { command -v "\$1" >/dev/null 2>&1; }
__zoxide_z() { if [ -d "\$1" ]; then cd "\$1"; else cd "\$(zoxide query -- "\$@")" || return 1; fi; }
z() { __zoxide_z "\$@"; }
$block
cd "$T"
z "\$@" 2>/dev/null && pwd
EOF
for sh in bash zsh; do
    command -v "$sh" >/dev/null || { echo "  - $sh not installed, skipped"; continue; }
    out=$("$sh" "$T/zrun.sh" the mandarin app)
    check "$sh: z the mandarin app → mo" '[ "$out" = "$T/Github/mo" ]'
    out=$("$sh" "$T/zrun.sh" "billing for acme")
    check "$sh: z \"billing for acme\" → portal" '[ "$out" = "$T/Github/portal" ]'
    out=$("$sh" "$T/zrun.sh" infra)
    check "$sh: one word → zoxide as before" '[ "$out" = "$T/Github/infra" ]'
    out=$("$sh" "$T/zrun.sh" infra stuff)
    check "$sh: words zoxide matches → zoxide wins" '[ "$out" = "$T/Github/infra" ]'
    out=$("$sh" "$T/zrun.sh" "$T/Github/salvage")
    check "$sh: a path → straight to zoxide" '[ "$out" = "$T/Github/salvage" ]'
done

[ -n "${KEEP:-}" ] || rm -rf "$T"
echo
if [ "$fails" -eq 0 ]; then echo "find: all good"; else echo "find: $fails failed"; exit 1; fi
