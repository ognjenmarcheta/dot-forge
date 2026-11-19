# Self-healing typos: after a command fails with an obvious mistake, a dim
# suggestion shows under the prompt a moment later — press Ctrl+G (or F1) to put
# it on the command line (it never runs by itself). Claude's fastest model, through your
# subscription (dot-ai). Loaded by aliases.sh.
#   DOT_FIX=0   turn it off
# zsh: the suggestion appears on its own. bash: press Ctrl+G (or F1) after a failure.
# Ctrl+G because F1 needs Fn on a MacBook and on 60% keyboards with no F-row.

[ -n "${DOT_FIX_LOADED:-}" ] && return 0
DOT_FIX_LOADED=1

_dot_fix_cmd=""
_dot_fix_failed=""
_dot_fix_status=0
_dot_fix_last=0
_dot_fix_suggestion=""

# Not worth asking about: interrupted / suspended, interactive programs, and
# commands whose non-zero exit is just an answer (grep found nothing, …).
_dot_fix_skip() { # cmd status
    case "$2" in 0|130|131|141|143|146|148) return 0 ;; esac
    case "$1" in
        ai|ai\ *|dot\ *|claude*|opencode*|nvim*|vim*|vi\ *|lazygit*|yazi*|y|y\ *|less*|man\ *|ssh\ *|\
        grep\ *|rg\ *|test\ *|\[*|diff\ *|cmp\ *|false|true|exit*|*\|*|sudo\ *|watch\ *|tail\ -f*)
            return 0 ;;
    esac
    [ "${DOT_FIX:-1}" = 0 ] && return 0
    [ -x "$HOME/.config/scripts/dot-fix" ] || return 0
    return 1
}

# Ask WezTerm for the visible screen (it writes it to a private file).
_dot_fix_screen_request() {
    [ "${TERM_PROGRAM:-}" = WezTerm ] || return 0
    local dir="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles" f
    mkdir -p "$dir" 2>/dev/null && chmod 700 "$dir" 2>/dev/null
    f="$dir/ai-ctx-$$-$RANDOM"
    printf '\033]1337;SetUserVar=%s=%s\007' dot_ai_ctx "$(printf '%s' "$f" | base64 | tr -d '\n')" >/dev/tty
    printf '%s' "$f"
}

if [ -n "${ZSH_VERSION:-}" ]; then
    zmodload zsh/datetime 2>/dev/null
    typeset -g _dot_fix_fd=""

    _dot_fix_preexec() { _dot_fix_cmd="$1"; _dot_fix_suggestion=""; }

    _dot_fix_precmd() {
        local st=$? cmd="$_dot_fix_cmd"
        _dot_fix_cmd=""
        [[ -n "$cmd" ]] || return $st
        _dot_fix_skip "$cmd" "$st" && return $st
        [[ -o zle ]] || return $st
        (( EPOCHSECONDS - _dot_fix_last < 10 )) && return $st   # don't hammer it
        _dot_fix_last=$EPOCHSECONDS
        if [[ -n "$_dot_fix_fd" ]]; then                          # an older one still running
            zle -F "$_dot_fix_fd" 2>/dev/null; exec {_dot_fix_fd}<&- 2>/dev/null
        fi
        local f; f="$(_dot_fix_screen_request)"
        exec {_dot_fix_fd}< <("$HOME/.config/scripts/dot-fix" "$cmd" "$st" "$f" 2>/dev/null)
        zle -F -w "$_dot_fix_fd" _dot_fix_ready
        return $st
    }

    _dot_fix_ready() {
        local fd="$1" line=""
        zle -F "$fd"
        IFS= read -r -u "$fd" line
        exec {fd}<&-
        _dot_fix_fd=""
        [[ -n "$line" ]] || return 0
        _dot_fix_suggestion="$line"
        zle -M "💡 $line   (Ctrl+G to use it)"
        zle -R
    }
    zle -N _dot_fix_ready

    _dot_fix_accept() {
        [[ -n "$_dot_fix_suggestion" ]] || return 0
        BUFFER="$_dot_fix_suggestion"
        CURSOR=${#BUFFER}
        _dot_fix_suggestion=""
        zle -M ""
    }
    zle -N _dot_fix_accept
    bindkey '^[OP' _dot_fix_accept    # F1
    bindkey '^[[11~' _dot_fix_accept  # F1 (some terminals)
    # Ctrl+G: bound in aliases.sh (shared with ai and navi)

    autoload -Uz add-zsh-hook
    add-zsh-hook preexec _dot_fix_preexec
    add-zsh-hook precmd _dot_fix_precmd
    precmd_functions=(_dot_fix_precmd ${precmd_functions:#_dot_fix_precmd})   # first: real $?
elif [ -n "${bash_preexec_imported:-}${__bp_imported:-}" ]; then
    _dot_fix_preexec() { _dot_fix_cmd="$1"; }
    _dot_fix_precmd() {
        local st=$?
        _dot_fix_failed=""
        if [ -n "$_dot_fix_cmd" ] && ! _dot_fix_skip "$_dot_fix_cmd" "$st"; then
            _dot_fix_failed="$_dot_fix_cmd"; _dot_fix_status=$st
        fi
        _dot_fix_cmd=""
        return $st
    }
    # Ctrl+G / F1: ask now (takes a second or two) and put the fix on the command line
    _dot_fix_accept_bash() {
        [ -n "$_dot_fix_failed" ] || return 0
        printf '\033[2m… asking Claude for a fix\033[0m\r' >/dev/tty
        local fix
        fix="$("$HOME/.config/scripts/dot-fix" "$_dot_fix_failed" "$_dot_fix_status" "$(_dot_fix_screen_request)" 2>/dev/null)"
        printf '\033[2K' >/dev/tty
        if [ -n "$fix" ]; then READLINE_LINE="$fix"; READLINE_POINT=${#fix}; fi
    }
    preexec_functions+=(_dot_fix_preexec)
    precmd_functions=(_dot_fix_precmd "${precmd_functions[@]}")
    bind -x '"\eOP": _dot_fix_accept_bash' 2>/dev/null
    bind -x '"\e[11~": _dot_fix_accept_bash' 2>/dev/null
fi
