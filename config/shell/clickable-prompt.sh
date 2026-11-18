# Clickable Starship prompt for WezTerm (bash & zsh).
#
# ~/.config/starship.toml prints placeholders (__CLICKUSER__, __CLICKDIR__,
# __CLICKNODEEDIT__, __CLICKGIT_START__/__CLICKGIT_END__). This file swaps
# them for OSC 8 hyperlinks that ~/.config/wezterm/events.lua handles:
#
#   ↑                  x-cd://parent   -> runs `cd ..` in the shell
#   ~/Github/project   file://<dir>    -> each segment opens that folder in Files
#   user name          https://github.com/<you>
#   nvim icon          x-edit://       -> runs `nvim .` (Node projects only)
#   git branch         https://github.com/<owner>/<repo>/tree/<branch>
#
# Loaded by ~/.config/shell/aliases.sh. Needs `starship` on PATH.

command -v starship >/dev/null 2>&1 || return 0

_cp_esc=$'\e'
_cp_st=$'\a'   # BEL terminator: safe inside bash \[ \] and zsh %{ %}

if [ -n "$ZSH_VERSION" ]; then
    _cp_shell=zsh
    _cp_zw_open='%{'
    _cp_zw_close='%}'
elif [ -n "$BASH_VERSION" ]; then
    _cp_shell=bash
    _cp_zw_open='\['
    _cp_zw_close='\]'
else
    return 0
fi

# GitHub username for the clickable user segment
_cp_gh_user="${GITHUB_USER:-$(git config --global github.user 2>/dev/null)}"
if [ -z "$_cp_gh_user" ] && [ -f "$HOME/.config/gh/hosts.yml" ]; then
    _cp_gh_user=$(sed -n 's/^[[:space:]]*user:[[:space:]]*//p' "$HOME/.config/gh/hosts.yml" | head -n1)
fi

# Percent-encode a path for a file:// URL
_cp_urlencode() {
    local LC_ALL=C s="$1" out="" c hex i
    for (( i = 0; i < ${#s}; i++ )); do
        c="${s:$i:1}"
        case "$c" in
            [a-zA-Z0-9/._~-]) out+="$c" ;;
            *) hex=$(printf '%%%02X' "'$c"); out+="$hex" ;;
        esac
    done
    printf '%s' "$out"
}

# Escape text so the shell's prompt expansion shows it literally
_cp_text() {
    local t="$1"
    if [ "$_cp_shell" = zsh ]; then
        t="${t//\%/%%}"
    else
        t="${t//\\/\\\\}"
    fi
    printf '%s' "$t"
}

_cp_link_open()  { printf '%s' "${_cp_zw_open}${_cp_esc}]8;;$1${_cp_st}${_cp_zw_close}"; }
_cp_link_close() { printf '%s' "${_cp_zw_open}${_cp_esc}]8;;${_cp_st}${_cp_zw_close}"; }
_cp_link()       { printf '%s' "$(_cp_link_open "$1")$(_cp_text "$2")$(_cp_link_close)"; }

# ↑ (cd ..) + breadcrumb where every segment is a link to that folder.
# Mirrors starship's truncation_length = 3 / truncation_symbol = "…/".
_cp_dir() {
    local pwd_="$PWD" out="" rel base prefix acc seg n i start
    local -a parts

    if [ "$pwd_" != "/" ]; then
        out+="$(_cp_link "x-cd://parent" "↑") "
    fi

    if [ "$pwd_" = "$HOME" ]; then
        out+="$(_cp_link "file://$(_cp_urlencode "$HOME")" "~")"
        printf '%s' "$out"; return
    fi

    if [ "${pwd_#"$HOME"/}" != "$pwd_" ]; then
        base="$HOME"; prefix="~"; rel="${pwd_#"$HOME"/}"
    else
        base=""; prefix=""; rel="${pwd_#/}"
        [ -z "$rel" ] && { out+="$(_cp_link "file:///" "/")"; printf '%s' "$out"; return; }
    fi

    # split rel on "/" (works in bash and zsh)
    parts=()
    local IFS=/
    if [ "$_cp_shell" = zsh ]; then
        parts=(${(s:/:)rel})
    else
        read -r -a parts <<< "$rel"
    fi
    unset IFS
    n=${#parts[@]}

    acc="$base"
    start=0
    (( n > 3 )) && start=$(( n - 3 ))

    if (( start > 0 )); then
        out+="…/"
    elif [ -n "$prefix" ]; then
        out+="$(_cp_link "file://$(_cp_urlencode "$HOME")" "~")/"
    else
        out+="$(_cp_link "file:///" "/")"
    fi

    for (( i = 0; i < n; i++ )); do
        if [ "$_cp_shell" = zsh ]; then seg="${parts[$((i + 1))]}"; else seg="${parts[$i]}"; fi
        acc="$acc/$seg"
        (( i < start )) && continue
        out+="$(_cp_link "file://$(_cp_urlencode "$acc")" "$seg")"
        (( i < n - 1 )) && out+="/"
    done
    printf '%s' "$out"
}

_cp_user() {
    if [ -n "$_cp_gh_user" ]; then
        _cp_link "https://github.com/$_cp_gh_user" "$USER"
    else
        _cp_text "$USER"
    fi
}

_cp_git_url() {
    local remote branch path_
    remote=$(git remote get-url origin 2>/dev/null) || return
    branch=$(git branch --show-current 2>/dev/null)
    case "$remote" in
        git@github.com:*)     path_="${remote#git@github.com:}" ;;
        ssh://git@github.com/*) path_="${remote#ssh://git@github.com/}" ;;
        https://github.com/*) path_="${remote#https://github.com/}" ;;
        *) return ;;
    esac
    path_="${path_%.git}"
    if [ -n "$branch" ]; then
        printf 'https://github.com/%s/tree/%s' "$path_" "$branch"
    else
        printf 'https://github.com/%s' "$path_"
    fi
}

# Replace every placeholder in $1 and print the result
_cp_fill() {
    local s="$1" r url
    case "$s" in *__CLICK*) ;; *) printf '%s' "$s"; return ;; esac

    if [[ "$s" == *__CLICKUSER__* ]]; then r="$(_cp_user)"; s="${s//__CLICKUSER__/"$r"}"; fi
    if [[ "$s" == *__CLICKDIR__* ]];  then r="$(_cp_dir)";  s="${s//__CLICKDIR__/"$r"}"; fi
    if [[ "$s" == *__CLICKNODEEDIT__* ]]; then
        r="$(_cp_link "x-edit://nvim" $'\xee\x98\xab')"; s="${s//__CLICKNODEEDIT__/"$r"}"
    fi
    if [[ "$s" == *__CLICKGIT_START__* ]]; then
        url="$(_cp_git_url)"
        if [ -n "$url" ]; then
            r="$(_cp_link_open "$url")"; s="${s//__CLICKGIT_START__/"$r"}"
            r="$(_cp_link_close)";       s="${s//__CLICKGIT_END__/"$r"}"
        else
            s="${s//__CLICKGIT_START__/}"
            s="${s//__CLICKGIT_END__/}"
        fi
    fi
    printf '%s' "$s"
}

if [ "$_cp_shell" = zsh ]; then
    eval "$(starship init zsh)"
    # Starship sets PROMPT/RPROMPT to '$(starship prompt ...)'. Keep those
    # commands and run them through _cp_fill on every redraw.
    _cp_left_cmd="$PROMPT"
    _cp_right_cmd="$RPROMPT"
    _cp_render() {
        if [ "$1" = right ]; then _cp_fill "${(e)_cp_right_cmd}"; else _cp_fill "${(e)_cp_left_cmd}"; fi
    }
    setopt prompt_subst
    PROMPT='$(_cp_render left)'
    RPROMPT='$(_cp_render right)'
else
    eval "$(starship init bash)"

    _cp_visible_width() {
        # drop OSC 8 links and SGR colour codes, then count characters
        printf '%s' "$1" \
            | sed -E "s/${_cp_esc}\\]8;;[^${_cp_st}]*${_cp_st}//g; s/${_cp_esc}\\[[0-9;]*m//g" \
            | { IFS= read -r l; printf '%s' "${#l}"; }
    }

    _cp_bash_precmd() {
        local right w
        # Bash has no RPROMPT: if starship didn't render the right side,
        # draw it ourselves, right-aligned on the prompt line.
        if [[ "$PS1" != *__CLICKGIT_START__* ]]; then
            right=$(starship prompt --right --terminal-width="$COLUMNS" \
                --status="${STARSHIP_CMD_STATUS:-0}" \
                --jobs="$(jobs -p | wc -l)" 2>/dev/null)
            if [ -n "$right" ]; then
                right="$(_cp_fill "$right")"
                local bo='\[' bc='\]'
                right="${right//"$bo"/}"; right="${right//"$bc"/}"   # whole block is zero-width
                w=$(_cp_visible_width "$right")
                # keep starship's leading blank line(s) above the prompt line
                local lead="${PS1%%[!$'\n']*}" rest="${PS1#"${PS1%%[!$'\n']*}"}"
                PS1="${lead}\\[${_cp_esc}7${_cp_esc}[${COLUMNS}C${_cp_esc}[${w}D${right}${_cp_esc}8\\]${rest}"
            fi
        fi
        PS1="$(_cp_fill "$PS1")"
    }

    # Run after starship's own precmd (string or array PROMPT_COMMAND)
    if [[ "$(declare -p PROMPT_COMMAND 2>/dev/null)" == "declare -a"* ]]; then
        PROMPT_COMMAND+=(_cp_bash_precmd)
    else
        PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND;}_cp_bash_precmd"
    fi
fi
