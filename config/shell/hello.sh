# shellcheck shell=bash
# The ByteForge card (dot hello) at the first prompt of every new shell — a new
# window, tab or split. Narrow panes get one line; DOT_HELLO=0 turns it off.
# Never in shells that aren't yours to look at: no terminal, Claude Code and
# the night shift (CLAUDECODE / DOT_NIGHT), Neovim's :terminal, dumb terminals.
# Loaded by aliases.sh, before daily.sh, so the morning lines follow the card.

[ -n "${DOT_HELLO_LOADED:-}" ] && return 0
DOT_HELLO_LOADED=1
_dot_hello_done=""

_dot_hello() {
    local st=$?
    [ -n "$_dot_hello_done" ] && return $st
    _dot_hello_done=1
    [ "${DOT_HELLO:-}" = 0 ] && return $st
    [ -t 1 ] || return $st
    [ -n "${CLAUDECODE:-}${DOT_NIGHT:-}${NVIM:-}${INSIDE_EMACS:-}" ] && return $st
    case "${TERM:-dumb}" in dumb|"") return $st ;; esac
    [ -x "$HOME/.config/scripts/dot-hello" ] || return $st
    COLUMNS="${COLUMNS:-}" LINES="${LINES:-}" "$HOME/.config/scripts/dot-hello" --startup
    return $st
}

# first in line, so the card comes before the prompt marks and other hooks' output
if [ -n "${ZSH_VERSION:-}" ]; then
    # shellcheck disable=SC2206,SC2128  # zsh array
    precmd_functions=(_dot_hello $precmd_functions)
elif [ -n "${bash_preexec_imported:-}${__bp_imported:-}" ]; then
    precmd_functions=(_dot_hello "${precmd_functions[@]}")
else
    PROMPT_COMMAND="_dot_hello${PROMPT_COMMAND:+; $PROMPT_COMMAND}"
fi
