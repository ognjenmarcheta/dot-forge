# Tell the terminal where things are (standard escape codes, ignored elsewhere):
#   OSC 133  prompt / command / output marks — WezTerm uses them to jump
#            between commands (Shift+↑/↓), select a whole output
#            (triple-click), copy the last output (Leader y) and for `ai fix`
#   OSC 7    the current folder — new tabs/splits open where you are (the
#            sandboxed Flatpak WezTerm can't see that on its own)
#   user vars (WezTerm only): dot_prog = what's running now (save points),
#            dot_fail = a command just failed (the window flashes red)
# Loaded by aliases.sh after the prompt (starship) is set up.

[ -n "${DOT_MARKS_LOADED:-}" ] && return 0
DOT_MARKS_LOADED=1

_dot_mark_ran=""

_dot_uservar() { # name value — WezTerm user var (value base64-encoded)
    [ "${TERM_PROGRAM:-}" = WezTerm ] || return 0
    printf '\033]1337;SetUserVar=%s=%s\007' "$1" "$(printf '%s' "$2" | base64 | tr -d '\n')"
}

_dot_osc7() {
    # file://host/path, with the few characters that break a URL escaped
    local p="${PWD//\%/%25}"
    p="${p// /%20}"
    printf '\033]7;file://%s%s\007' "${HOSTNAME:-$(hostname 2>/dev/null)}" "$p"
}

_dot_marks_precmd() {
    local st=$?
    # D = previous output ended (with its exit status), A = prompt starts
    if [ -n "$_dot_mark_ran" ]; then
        printf '\033]133;D;%s\007' "$st"
        _dot_mark_ran=""
        _dot_uservar dot_prog ""
        case "$st" in 0|130|141|148) ;; *) _dot_uservar dot_fail "$st $RANDOM" ;; esac
    fi
    printf '\033]133;A\007'
    _dot_osc7
    return $st
}

_dot_marks_preexec() {
    printf '\033]133;C\007'   # output starts
    _dot_mark_ran=1
    _dot_uservar dot_prog "${1:0:300}"
}

if [ -n "${ZSH_VERSION:-}" ]; then
    autoload -Uz add-zsh-hook
    add-zsh-hook precmd _dot_marks_precmd
    add-zsh-hook preexec _dot_marks_preexec
    # B = prompt ends, typed command starts (zero-width, at the very end)
    case "$PROMPT" in *'133;B'*) ;; *) PROMPT="$PROMPT%{"$'\033]133;B\007'"%}" ;; esac
elif [ -n "${bash_preexec_imported:-}${__bp_imported:-}" ]; then
    precmd_functions=(_dot_marks_precmd "${precmd_functions[@]}")
    preexec_functions+=(_dot_marks_preexec)
    # PS1 is rebuilt on every prompt, so add B after everything else ran
    _dot_marks_ps1() {
        local st=$?
        case "$PS1" in *'133;B'*) ;; *) PS1="$PS1"'\[\033]133;B\007\]' ;; esac
        return $st
    }
    precmd_functions+=(_dot_marks_ps1)
else
    # no bash-preexec: still report the folder
    _dot_osc7_prompt() { local st=$?; _dot_osc7; return $st; }
    if [[ "$(declare -p PROMPT_COMMAND 2>/dev/null)" == "declare -a"* ]]; then
        PROMPT_COMMAND+=(_dot_osc7_prompt)
    else
        PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND;}_dot_osc7_prompt"
    fi
fi
