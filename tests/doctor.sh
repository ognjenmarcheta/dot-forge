#!/usr/bin/env bash
# Check that this machine matches the dotfiles (also what CI runs).
#   tests/doctor.sh          links, tools, shells, prompt, git config
#   tests/doctor.sh --nvim   + start Neovim headless and fail on errors
# Works with macOS's bash 3.2.

set -uo pipefail

DOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
OS="$(uname -s)"
RUN_NVIM=0
[ "${1:-}" = "--nvim" ] && RUN_NVIM=1

fails=0
warns=0
c_ok=$'\033[1;32m'; c_bad=$'\033[1;31m'; c_warn=$'\033[1;33m'; c_h=$'\033[1;34m'; c_off=$'\033[0m'
ok()   { printf '  %s✓%s %s\n' "$c_ok" "$c_off" "$*"; }
bad()  { printf '  %s✗%s %s\n' "$c_bad" "$c_off" "$*"; fails=$((fails + 1)); }
warn() { printf '  %s!%s %s\n' "$c_warn" "$c_off" "$*"; warns=$((warns + 1)); }
head_() { printf '\n%s%s%s\n' "$c_h" "$*" "$c_off"; }
have() { command -v "$1" >/dev/null 2>&1; }

# Tools may live in ~/.local/bin (Linux) — make sure we see what the shell sees.
export PATH="$HOME/.local/bin:$PATH"
[ -x /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv)" && export PATH="$HOME/.local/bin:$PATH"

head_ "Config links (~/.config -> repo)"
for item in "$DOT"/config/*; do
    name="$(basename "$item")"
    if [ -L "$CONFIG_HOME/$name" ] && [ "$(readlink "$CONFIG_HOME/$name")" = "$item" ]; then
        ok "$name"
    else
        bad "$name is not linked to the repo (run install.sh)"
    fi
done
if [ "$OS" = Darwin ]; then
    for item in "$DOT"/macos/*; do
        name="$(basename "$item")"
        if [ "$(readlink "$CONFIG_HOME/$name" 2>/dev/null)" = "$item" ]; then ok "$name (macOS)"; else bad "$name (macOS) not linked"; fi
    done
fi

head_ "Shell hook"
for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    [ "$rc" = "$HOME/.zshrc" ] && ! have zsh && continue
    if grep -qF '.config/shell/aliases.sh' "$rc" 2>/dev/null; then ok "$(basename "$rc")"; else bad "$(basename "$rc") doesn't load ~/.config/shell/aliases.sh"; fi
done

head_ "Tools"
for t in git starship zoxide fzf yazi atuin mise eza delta rg lazygit opencode nvim; do
    if have "$t"; then ok "$t"; else bad "$t missing"; fi
done
if have bat || have batcat; then ok "bat"; else bad "bat missing"; fi
if have fd || have fdfind; then ok "fd"; else bad "fd missing"; fi
nv="$(nvim --version 2>/dev/null | sed -n 1p)"
case "$nv" in
    "NVIM v0.11."*) ok "$nv (pinned)" ;;
    *) bad "Neovim must be 0.11.x for the pinned plugins, found: ${nv:-none}" ;;
esac
if [ -f "$HOME/.local/share/bash-preexec/bash-preexec.sh" ]; then ok "bash-preexec"; else bad "bash-preexec missing (atuin + notifications in bash)"; fi
for t in tldr navi carapace just fx xh jq; do
    if have "$t"; then ok "$t"; else bad "$t missing"; fi
done
have claude || warn "claude (Claude Code) not installed — \`ai\` won't work"
if have zsh; then
    for plug in zsh-autosuggestions zsh-syntax-highlighting fzf-tab; do
        if [ -d "$HOME/.local/share/zsh-plugins/$plug" ]; then ok "zsh: $plug"; else bad "zsh: $plug missing"; fi
    done
fi
if have whisper-cli; then ok "whisper-cli (push-to-talk)"; else warn "whisper-cli missing — Alt+V push-to-talk off (run install.sh)"; fi
if [ -s "$HOME/.local/share/whisper/ggml-base.bin" ]; then ok "speech model"; else warn "speech model missing — Alt+V push-to-talk off"; fi
if [ -x "$HOME/.config/scripts/dot-ai" ] && have claude; then
    if "$HOME/.config/scripts/dot-ai" --check 2>/dev/null; then ok "AI features use your Claude subscription"
    else warn "Claude Code isn't on your subscription login — AI features off (dot-ai --check)"; fi
fi
if [ -f "${XDG_DATA_HOME:-$HOME/.local/share}/atuin/session" ]; then ok "atuin history sync on"; else warn "history not synced between machines — run: dot sync-history"; fi
if [ "$OS" = Linux ] && [ -z "${CI:-}" ]; then
    if [ -x /usr/bin/wezterm ]; then ok "WezTerm (regular build — sessions survive closing the window)"
    else warn "WezTerm isn't the regular build (Flatpak?) — re-run install.sh"; fi
fi
if grep -q agent-notify "$HOME/.claude/settings.json" 2>/dev/null; then ok "Claude Code alert hooks"; else warn "Claude Code alert hooks not set up (run install.sh)"; fi
if [ -z "${CI:-}" ]; then
    if [ "$OS" = Darwin ]; then
        if launchctl list 2>/dev/null | grep -q software.byteforge.dot-night; then ok "night shift runs at 01:30 (launchd)"
        else warn "night shift scheduler off — re-run install.sh (dot night run works by hand)"; fi
    elif have systemctl; then
        if systemctl --user is-enabled dot-night.timer >/dev/null 2>&1; then ok "night shift runs at 01:30 (systemd timer)"
        else warn "night shift timer off — re-run install.sh (dot night run works by hand)"; fi
    fi
fi

head_ "git"
if [ "$(git config --get core.pager)" = delta ]; then ok "git uses delta"; else bad "git config not picked up (core.pager)"; fi
if git config --get user.email >/dev/null; then ok "identity: $(git config --get user.name) <$(git config --get user.email)>"; else warn "no git identity — put it in ~/.config/git/local"; fi

# Run an interactive shell, collect stderr minus job-control noise (no tty in CI).
shell_check() { # shell  script
    local sh="$1" script="$2" err
    # (also: bash 3.2's readline prints ESC[?1034h, atuin's `stty -g` needs a tty)
    err=$(TERM=xterm-256color "$sh" -ic "$script" 2>&1 >/dev/null </dev/null \
        | sed $'s/\033\\[?1034h//g' \
        | grep -vE "job control|cannot set terminal process group|Inappropriate ioctl|no job control|stty: stdin isn't a terminal|^$" || true)
    printf '%s' "$err"
}

head_ "bash"
err=$(shell_check bash 'true')
if [ -z "$err" ]; then ok "starts without errors"; else bad "errors on start:"; printf '%s\n' "$err" | sed 's/^/      /' | head -10; fi
if TERM=xterm-256color bash -ic '
    if [ -n "${precmd_functions+x}" ]; then for f in "${precmd_functions[@]}"; do $f; done; else eval "$PROMPT_COMMAND"; fi
    [[ "$PS1" == *"x-cd://parent"* || "$PWD" == / ]]' </dev/null >/dev/null 2>&1; then
    ok "clickable prompt renders"
else
    bad "prompt has no clickable links"
fi
for f in z y ai rgf _dot_marks_precmd _dot_fix_precmd _dot_lobby_check _dot_daily; do
    if TERM=xterm-256color bash -ic "type $f" </dev/null >/dev/null 2>&1; then ok "$f"; else bad "$f not defined in bash"; fi
done

if have zsh; then
    head_ "zsh"
    err=$(shell_check zsh 'true')
    if [ -z "$err" ]; then ok "starts without errors"; else bad "errors on start:"; printf '%s\n' "$err" | sed 's/^/      /' | head -10; fi
    if TERM=xterm-256color zsh -ic 'for f in $precmd_functions; do $f; done; [[ "$(_cp_render left)" == *x-cd://parent* || "$PWD" == / ]]' </dev/null >/dev/null 2>&1; then
        ok "clickable prompt renders"
    else
        bad "prompt has no clickable links"
    fi
    for f in z y ai rgf _dot_marks_precmd _dot_fix_precmd _dot_lobby_check _dot_daily _dot_share_accept; do
        if TERM=xterm-256color zsh -ic "whence -w $f" </dev/null >/dev/null 2>&1; then ok "$f"; else bad "$f not defined in zsh"; fi
    done
fi

if [ "$RUN_NVIM" -eq 1 ]; then
    head_ "Neovim (headless start)"
    out=$(cd "$(mktemp -d)" && nvim --headless --cmd "luafile $DOT/tests/nvim-smoke.lua" 2>&1)
    rc=$?
    printf '%s\n' "$out" | sed 's/^/      /'
    if [ $rc -eq 0 ]; then ok "Neovim starts cleanly"; else bad "Neovim smoke test failed (exit $rc)"; fi
fi

printf '\n'
if [ $fails -eq 0 ]; then
    printf '%sAll good%s (%d warnings)\n' "$c_ok" "$c_off" "$warns"
else
    printf '%s%d problem(s)%s, %d warning(s)\n' "$c_bad" "$fails" "$c_off" "$warns"
fi
[ $fails -eq 0 ]
