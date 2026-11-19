#!/usr/bin/env bash
# Load config/wezterm in a real WezTerm (no window) and fail on Lua errors or
# missing key bindings. CI installs WezTerm first; locally: `bash tests/wezterm-config.sh`.
set -uo pipefail
DOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
command -v wezterm >/dev/null || { echo "wezterm not installed — skipped"; exit 0; }

tmp="$(mktemp -d)"
mkdir -p "$tmp/.config"
ln -s "$DOT/config/wezterm" "$tmp/.config/wezterm"
echo "wezterm: $(wezterm --version)"

# show-keys loads the whole config (wezterm.lua -> config, events, features)
keys=$(HOME="$tmp" XDG_CONFIG_HOME="$tmp/.config" WEZTERM_LOG=warn \
    wezterm show-keys --lua 2>"$tmp/err")
rc=$?
fails=0
if [ $rc -ne 0 ]; then echo "✗ show-keys exited $rc"; fails=1; fi
if grep -qiE 'error|runtime|attempt to|stack traceback' "$tmp/err"; then
    echo "✗ config errors:"; sed 's/^/    /' "$tmp/err" | head -40; fails=1
fi
need() { # label, regex that must appear in the key table
    if printf '%s\n' "$keys" | grep -qE "$2"; then echo "✓ $1"; else
        echo "✗ $1 missing"; fails=1
        printf '%s\n' "$keys" | grep -iE "${3:-LEADER}" | head -8 | sed 's/^/    /'
    fi
}
# Alt+q opens the "leader" key table (features.apply_leader)
need "Alt+q opens the leader table" "key = 'q', mods = 'ALT', action = act.Multiple\\{ \\{ ActivateKeyTable" "'q'"
need "Leader p (projects)"   "key = 'p', mods = 'NONE', action = act.Multiple\\{ \\{ EmitEvent" "leader|'p'"
need "Leader y (copy output)" "key = 'y', mods = 'NONE', action = act.Multiple" "leader|'y'"
need "Leader c (new tab)" "key = 'c', mods = 'NONE', action = act.Multiple\\{ \\{ SpawnTab" "leader|'c'"
need "Leader Space (quick select)" "key = '(phys:)?Space', mods = 'NONE', action = act.Multiple\\{ 'QuickSelect'" "space"
need "Leader Esc (cancel)" "key = 'Escape', mods = 'NONE', action = act.Multiple\\{ 'PopKeyTable'" "escape"
need "Shift+Up (prev command)" "key = 'UpArrow', mods = 'SHIFT'"
need "Ctrl+h (pane/split nav)" "key = 'h', mods = 'CTRL'"
need "Shift+Enter (new line)" "key = 'Enter', mods = 'SHIFT'"
need "Leader w (workspaces)" "key = 'w', mods = 'NONE', action = act.Multiple\\{ \\{ ShowLauncherArgs" "'w'"
if printf '%s' "$keys" | grep -q "mods = '[A-Z|]*LEADER"; then
    echo "✗ a LEADER binding was left outside the leader table"; fails=1
else
    echo "✓ every leader binding is in the leader table"
fi
if printf '%s' "$keys" | grep -q 'Close.*confirm = true'; then
    echo "✗ closing a tab / pane asks for confirmation"; fails=1
else
    echo "✓ tabs and panes close without asking"
fi
rm -rf "$tmp"
[ $fails -eq 0 ] && echo "wezterm config: all good"
exit $fails
