# Push-to-talk: Alt+V, say what you want, press any key. The speech is turned
# into text on this machine (whisper.cpp — no audio leaves the computer) and put
# on the command line as `ai "…"` for you to check and run with Enter; `ai`
# then shows the command and asks before running it. Loaded by aliases.sh.

[ -x "$HOME/.config/scripts/dot-voice" ] || return 0

if [ -n "${ZSH_VERSION:-}" ]; then
    _dot_voice() {
        zle -I                                   # we're about to write to the terminal
        local text
        text="$("$HOME/.config/scripts/dot-voice" listen)"
        if [[ -n "$text" ]]; then
            BUFFER="ai \"${text//\"/\\\"}\""
            CURSOR=${#BUFFER}
        fi
        zle reset-prompt
    }
    zle -N _dot_voice
    bindkey '^[v' _dot_voice                     # Alt+V
elif [ -n "${BASH_VERSION:-}" ]; then
    _dot_voice_bash() {
        local text
        text="$("$HOME/.config/scripts/dot-voice" listen)"
        if [ -n "$text" ]; then
            READLINE_LINE="ai \"${text//\"/\\\"}\""
            READLINE_POINT=${#READLINE_LINE}
        fi
    }
    bind -x '"\ev": _dot_voice_bash' 2>/dev/null
fi
