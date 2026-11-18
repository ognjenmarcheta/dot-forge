# shellcheck shell=bash
# While `dot mode share` is on, a command that would print secrets on screen
# (cat .env, printenv, gh auth token, kubectl get secret …) needs a second
# Enter in zsh; bash shows a warning first. Loaded by aliases.sh.

_dot_share_state="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/mode"
_dot_share_re='(^|[;&|[:space:]])((cat|bat|batcat|less|more|head|tail|nvim|vim|code|grep|rg)[[:space:]][^;&|]*(\.env|credentials|\.pem|\.key|id_rsa|id_ed25519|\.netrc|\.npmrc|kubeconfig|k3s-arc\.yaml|service\.json)|printenv|env$|env[[:space:]]*$|export[[:space:]]+-p|set[[:space:]]*$|gh[[:space:]]+auth[[:space:]]+token|kubectl[[:space:]]+get[[:space:]]+secrets?|bw[[:space:]]+get|op[[:space:]]+read|aws[[:space:]]+configure|atuin[[:space:]]+key)'

_dot_share_risky() { [ -f "$_dot_share_state" ] && [[ "$1" =~ $_dot_share_re ]]; }

if [ -n "${ZSH_VERSION:-}" ]; then
    typeset -g _dot_share_armed=""
    _dot_share_accept() {
        if _dot_share_risky "$BUFFER" && [[ "$_dot_share_armed" != "$BUFFER" ]]; then
            _dot_share_armed="$BUFFER"
            zle -M "● sharing your screen: this may print secrets — Enter again to run it anyway"
            return 0
        fi
        _dot_share_armed=""
        zle .accept-line
    }
    zle -N accept-line _dot_share_accept
elif [ -n "${bash_preexec_imported:-}${__bp_imported:-}" ]; then
    _dot_share_preexec() {
        if _dot_share_risky "$1"; then
            printf '\033[1;31m● sharing your screen — this may print secrets (Ctrl+C to stop)\033[0m\n'
            sleep 2
        fi
    }
    preexec_functions+=(_dot_share_preexec)
fi
