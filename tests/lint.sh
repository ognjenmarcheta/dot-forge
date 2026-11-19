#!/usr/bin/env bash
# Static checks for the repo (CI runs this first). Needs: shellcheck, zsh,
# python3; luac / luacheck optional.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

fails=0
run() { # label, command...
    local label="$1"; shift
    if out=$("$@" 2>&1); then
        printf '  ✓ %s\n' "$label"
    else
        printf '  ✗ %s\n%s\n' "$label" "$(printf '%s\n' "$out" | sed 's/^/      /' | head -40)"
        fails=$((fails + 1))
    fi
}

bash_files="install.sh tests/doctor.sh tests/lint.sh tests/wezterm-config.sh config/scripts/dot config/scripts/dot-ai config/scripts/dot-fix config/scripts/dot-lobby config/scripts/dot-voice config/scripts/dot-status tests/work.sh config/scripts/agent-notify config/scripts/check-node-updates.sh config/scripts/dot-mode config/scripts/dot-new config/scripts/dot-invite config/scripts/dot-try tests/features.sh config/scripts/dot-hello config/scripts/dot-tip config/scripts/dot-ports tests/ports.sh tests/wrapped.sh tests/hello.sh tests/find.sh"
shell_files="config/shell/aliases.sh config/shell/ai.sh config/shell/clickable-prompt.sh config/shell/notify.sh config/shell/marks.sh config/shell/fix.sh config/shell/lobby.sh config/shell/voice.sh config/shell/share.sh config/shell/daily.sh config/shell/hello.sh config/shell/bashrc"

echo "Syntax"
for f in $bash_files $shell_files; do run "bash -n $f" bash -n "$f"; done
if command -v zsh >/dev/null; then
    for f in $shell_files config/scripts/herdr-*; do run "zsh -n $f" zsh -n "$f"; done
fi

echo "shellcheck"
if command -v shellcheck >/dev/null; then
    # No zsh support there: the shared shell files are checked as bash, and
    # SC2296 (zsh-only ${(…)} expansions inside zsh branches) is ignored.
    # shellcheck disable=SC2086
    run "install / tests / dot" shellcheck -S warning $bash_files
    # shellcheck disable=SC2086
    run "shared shell files" shellcheck -S error -s bash -e SC2296 $shell_files
else
    echo "  ! shellcheck not installed — skipped"
fi

echo "Lua"
luac=$(command -v luac5.4 || command -v luac5.3 || command -v luac || true)
if [ -n "$luac" ]; then
    for f in config/wezterm/*.lua tests/nvim-smoke.lua $(find config/nvim -name '*.lua'); do
        run "$f" "$luac" -p "$f"
    done
    # a helper used before its `local` definition compiles to a global (nil at runtime)
    for f in config/wezterm/*.lua; do
        stray=$("$luac" -l -p "$f" | grep -oE '[GS]ETTABUP.*_ENV "[A-Za-z_]+"' | grep -oE '"[A-Za-z_]+"' | sort -u \
            | grep -vE '"(string|table|math|os|io|tonumber|tostring|ipairs|pairs|pcall|type|require|utf8|print|error|select|next|unpack)"' || true)
        run "$f: no stray globals" test -z "$stray"
        [ -n "$stray" ] && echo "      $stray"
    done
else
    echo "  ! luac not installed — skipped"
fi

echo "Python"
for py in dot-work dot-night dot-recall dot-habits dot-janitor dot-evolve dot-wrapped dot-calendar dot-find; do
    run "$py parses" python3 -c "import ast,sys; ast.parse(open(sys.argv[1]).read())" "config/scripts/$py"
done

echo "Config files"
run "git config parses" git config -f config/git/config --list
run "mise config.toml" python3 -c "import tomllib,sys; tomllib.load(open('config/mise/config.toml','rb'))"
run "starship.toml" python3 -c "import tomllib; tomllib.load(open('config/starship.toml','rb'))"
run "lazy-lock.json" python3 -c "import json; json.load(open('config/nvim/lazy-lock.json'))"
if python3 -c "import yaml" 2>/dev/null; then
    run "navi config.yaml" python3 -c "import yaml; yaml.safe_load(open('config/navi/config.yaml'))"
    run "lazygit config.yml" python3 -c "import yaml; yaml.safe_load(open('config/lazygit/config.yml'))"
fi

echo "No secrets"
secret_re='(ghp_[A-Za-z0-9]{30,}|gho_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}|sk-ant-[A-Za-z0-9-]{20,}|AKIA[0-9A-Z]{16}|BEGIN (RSA|OPENSSH|EC) PRIVATE KEY|"password": *"[^"]+")'
if git ls-files -z | xargs -0 grep -IEn "$secret_re" 2>/dev/null; then
    echo "  ✗ possible secret committed (see above)"; fails=$((fails + 1))
else
    echo "  ✓ none found"
fi

echo
if [ $fails -eq 0 ]; then echo "lint: all good"; else echo "lint: $fails problem(s)"; fi
[ $fails -eq 0 ]
