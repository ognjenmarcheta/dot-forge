# shellcheck shell=bash
# Once a day, at your first prompt: what the night shift did (dot night) and,
# once a week, how many shortcut ideas dot habits has. One line each, no waiting
# (the habits count is worked out in the background). Loaded by aliases.sh.

_dot_daily_state="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles"
_dot_daily_data="${XDG_DATA_HOME:-$HOME/.local/share}/dotfiles"

_dot_daily() {
    local st=$? today stamp
    [ -t 1 ] || return $st
    today="$(date +%F)"
    stamp="$_dot_daily_state/daily"
    # night shift results appear as soon as they're there, not just once a day
    if [ -s "$_dot_daily_data/night/unseen" ]; then
        printf '\033[35m%s\033[0m' "$(cat "$_dot_daily_data/night/unseen")"
        : > "$_dot_daily_data/night/unseen"
    fi
    [ "$(cat "$stamp" 2>/dev/null)" = "$today" ] && return $st
    mkdir -p "$_dot_daily_state"
    printf '%s' "$today" > "$stamp"
    # habits: show last week's count, then refresh it in the background
    local hab="$_dot_daily_state/habits-count" n
    n="$(cat "$hab" 2>/dev/null)"
    if [ -n "$n" ] && [ "$n" -gt 0 ] 2>/dev/null; then
        printf '\033[2m💡 %s shortcut idea(s) from what you type most — dot habits\033[0m\n' "$n"
        : > "$hab"
    fi
    if [ -z "$(find "$_dot_daily_state" -maxdepth 1 -name habits-checked -mtime -7 2>/dev/null)" ] && command -v atuin >/dev/null 2>&1; then
        touch "$_dot_daily_state/habits-checked"
        ( "$HOME/.config/scripts/dot" habits --check > "$hab.tmp" 2>/dev/null && mv "$hab.tmp" "$hab" & ) >/dev/null 2>&1
    fi
    return $st
}

if [ -n "${ZSH_VERSION:-}" ]; then
    autoload -Uz add-zsh-hook
    add-zsh-hook precmd _dot_daily
elif [ -n "${bash_preexec_imported:-}${__bp_imported:-}" ]; then
    precmd_functions+=(_dot_daily)
fi
