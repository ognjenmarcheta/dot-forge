# Desktop notification when a command that ran for a while finishes and the
# WezTerm window isn't focused. The shell sets a WezTerm "user var"
# (OSC 1337 SetUserVar); ~/.config/wezterm/events.lua turns it into a toast.
#   DOT_NOTIFY_AFTER=30   seconds before a command counts as long (default 30)
#   DOT_NOTIFY_AFTER=0    turns it off

_dot_cmd_start=""
_dot_cmd_line=""

_dot_notify_preexec() {
    _dot_cmd_start=$SECONDS
    _dot_cmd_line="$1"
}

_dot_notify_precmd() {
    local st=$?                       # exit status of the command that just ran
    [ -n "$_dot_cmd_start" ] || return $st
    local secs=$(( SECONDS - _dot_cmd_start ))
    local min="${DOT_NOTIFY_AFTER:-30}"
    _dot_cmd_start=""
    [ "$min" -gt 0 ] 2>/dev/null || return $st
    [ "$secs" -ge "$min" ] || return $st
    [ "${TERM_PROGRAM:-}" = WezTerm ] || return $st
    case "$_dot_cmd_line" in          # interactive programs: you were there
        nvim*|vim*|vi\ *|lazygit*|yazi*|y|y\ *|btop*|htop*|top|less*|man\ *|ssh\ *|claude*|opencode*|herdr*|tig*|fzf*|tail\ -f*|watch\ *|*\|\ less*)
            return $st ;;
    esac
    local payload
    payload=$(printf '%s\t%s\t%s' "$st" "$secs" "${_dot_cmd_line:0:120}" | base64 | tr -d '\n')
    printf '\033]1337;SetUserVar=%s=%s\007' dot_cmd_done "$payload"
    return $st
}

if [ -n "$ZSH_VERSION" ]; then
    autoload -Uz add-zsh-hook
    add-zsh-hook preexec _dot_notify_preexec
    add-zsh-hook precmd _dot_notify_precmd
    # run first, so it sees the command's real exit status
    precmd_functions=(_dot_notify_precmd ${precmd_functions:#_dot_notify_precmd})
elif [ -n "${bash_preexec_imported:-}${__bp_imported:-}" ]; then
    preexec_functions+=(_dot_notify_preexec)
    precmd_functions=(_dot_notify_precmd "${precmd_functions[@]}")   # first: sees the real $?
fi
