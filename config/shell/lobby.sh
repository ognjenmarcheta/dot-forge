# Project lobby: coming back to a repo you haven't opened for a few days shows
# a short card — branch, your PRs, reviews waiting for you, CI, the last things
# you ran there — and (zsh, a moment later) what others pushed meanwhile.
#   DOT_LOBBY_DAYS=3   how long away counts as "a while" (0 = off)
# Visits are kept in ~/.local/share/dotfiles/lobby.tsv. Loaded by aliases.sh.

[ -n "${DOT_LOBBY_LOADED:-}" ] && return 0
DOT_LOBBY_LOADED=1

_dot_lobby_state="${XDG_DATA_HOME:-$HOME/.local/share}/dotfiles/lobby.tsv"
_dot_lobby_root="__none__"
_dot_lobby_touched=0

_dot_lobby_now() { if [ -n "${EPOCHSECONDS:-}" ]; then echo "$EPOCHSECONDS"; else date +%s; fi; }

_dot_lobby_record() { # root epoch
    local dir tmp
    dir="$(dirname "$_dot_lobby_state")"
    mkdir -p "$dir" 2>/dev/null || return 0
    tmp="$_dot_lobby_state.$$"
    { [ -f "$_dot_lobby_state" ] && awk -F'\t' -v r="$1" '$1 != r' "$_dot_lobby_state"; printf '%s\t%s\n' "$1" "$2"; } > "$tmp" \
        && mv -f "$tmp" "$_dot_lobby_state"
    _dot_lobby_touched="$2"
}

_dot_lobby_check() {
    local st=$? root now last
    [ "${DOT_LOBBY_DAYS:-3}" = 0 ] && return $st
    root="$(git rev-parse --show-toplevel 2>/dev/null)"
    now="$(_dot_lobby_now)"
    if [ "$root" != "$_dot_lobby_root" ]; then
        _dot_lobby_root="$root"
        [ -n "$root" ] || return $st
        last="$(awk -F'\t' -v r="$root" '$1 == r {print $2}' "$_dot_lobby_state" 2>/dev/null | tail -n 1)"
        _dot_lobby_record "$root" "$now"
        if [ -n "$last" ] && [ $(( now - last )) -ge $(( ${DOT_LOBBY_DAYS:-3} * 86400 )) ] \
            && [ -x "$HOME/.config/scripts/dot-lobby" ]; then
            if [ -n "${ZSH_VERSION:-}" ] && [[ -o zle ]]; then
                "$HOME/.config/scripts/dot-lobby" card "$root" "$last"
                _dot_lobby_away_start "$root" "$last"
            else
                "$HOME/.config/scripts/dot-lobby" card "$root" "$last" --with-away
            fi
        fi
    elif [ -n "$root" ] && [ $(( now - _dot_lobby_touched )) -ge 600 ]; then
        _dot_lobby_record "$root" "$now"   # still here: keep "last visit" fresh
    fi
    return $st
}

if [ -n "${ZSH_VERSION:-}" ]; then
    zmodload zsh/datetime 2>/dev/null
    typeset -g _dot_lobby_fd=""
    # "while you were away" needs a git fetch — do it in the background and
    # show the line under the prompt when it's ready
    _dot_lobby_away_start() {
        [[ -n "$_dot_lobby_fd" ]] && { zle -F "$_dot_lobby_fd" 2>/dev/null; exec {_dot_lobby_fd}<&- 2>/dev/null; }
        exec {_dot_lobby_fd}< <("$HOME/.config/scripts/dot-lobby" away "$1" "$2" 2>/dev/null)
        zle -F -w "$_dot_lobby_fd" _dot_lobby_away_ready
    }
    _dot_lobby_away_ready() {
        local fd="$1" line=""
        zle -F "$fd"
        IFS= read -r -u "$fd" line
        exec {fd}<&-
        _dot_lobby_fd=""
        [[ -n "$line" ]] || return 0
        zle -M "$line"
        zle -R
    }
    zle -N _dot_lobby_away_ready
    autoload -Uz add-zsh-hook
    add-zsh-hook precmd _dot_lobby_check
elif [ -n "${bash_preexec_imported:-}${__bp_imported:-}" ]; then
    _dot_lobby_away_start() { :; }
    precmd_functions+=(_dot_lobby_check)
fi
