# Shared interactive shell setup for bash & zsh (macOS and Linux).
# Loaded from ~/.bashrc / ~/.zshrc (install.sh adds the line) and by WezTerm.
# Machine-specific settings and secrets go in ~/.config/shell/local.sh
# (not committed; loaded last).

[ -n "$_SHELL_ALIASES_LOADED" ] && return 0
_SHELL_ALIASES_LOADED=1
_dot_has() { command -v "$1" >/dev/null 2>&1; }

# macOS: some tools (lazygit…) default to ~/Library/Application Support unless
# XDG_CONFIG_HOME is set; point them at ~/.config. (Linux already uses ~/.config.)
if [ "$(uname -s)" = Darwin ] && [ -z "${XDG_CONFIG_HOME:-}" ]; then
    export XDG_CONFIG_HOME="$HOME/.config"
fi

# --- PATH ---------------------------------------------------------------------
# install.sh puts CLI tools in ~/.local/bin (Linux; pinned Neovim on both) and
# uses Homebrew on macOS. ~/.config/shell/bin is an older location.
for _d in "$HOME/.config/shell/bin" "$HOME/.local/bin"; do
    case ":$PATH:" in
        *":$_d:"*) ;;
        *) [ -d "$_d" ] && PATH="$_d:$PATH" ;;
    esac
done
unset _d
if [ -x /opt/homebrew/bin/brew ] && ! _dot_has brew; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
    PATH="$HOME/.local/bin:$PATH"            # keep pinned Neovim ahead of Homebrew
fi
case ":$PATH:" in
    *":$HOME/.config/scripts:"*) ;;
    *) PATH="$PATH:$HOME/.config/scripts" ;;  # dot, herdr-*, check-node-updates.sh
esac
export PATH

export EDITOR="${EDITOR:-nvim}" VISUAL="${VISUAL:-nvim}"

# --- mise: per-project Node / Python / pnpm / uv versions ---------------------
# Reads .nvmrc / .node-version / .python-version too. Global defaults live in
# ~/.config/mise/config.toml.
if _dot_has mise; then
    if [ -n "$ZSH_VERSION" ]; then eval "$(mise activate zsh)"; else eval "$(mise activate bash)"; fi
fi

# --- ls / ll: eza with icons, git status and clickable entries ----------------
# Every entry is an OSC 8 link; WezTerm opens folders in Files/Finder and
# reveals files (see ~/.config/wezterm/events.lua).
if _dot_has eza; then
    alias ls='eza --hyperlink --group-directories-first --icons=auto'
    alias ll='eza -la --hyperlink --group-directories-first --icons=auto --git --time-style=relative'
    alias la='eza -a --hyperlink --group-directories-first --icons=auto'
    alias lt='eza --tree --level=2 --hyperlink --icons=auto --git-ignore'
    alias l='eza --hyperlink --icons=auto'
else
    if ls --hyperlink=auto -d / >/dev/null 2>&1; then
        alias ls='ls --color=auto --hyperlink=auto'
    elif _dot_has gnuls && gnuls --hyperlink=auto -d / >/dev/null 2>&1; then
        alias ls='gnuls --color=auto --hyperlink=auto'   # Ubuntu 25.10+ (uutils ls)
    elif _dot_has gls; then
        alias ls='gls --color=auto --hyperlink=auto'     # macOS (brew coreutils)
    else
        alias ls='ls --color=auto'
    fi
    alias ll='ls -alF'
    alias la='ls -A'
    alias l='ls -CF'
fi

# --- bat: cat with syntax highlighting; colored man pages ---------------------
_dot_bat="$(command -v bat 2>/dev/null || command -v batcat 2>/dev/null)"   # Ubuntu: batcat
if [ -n "$_dot_bat" ]; then
    _dot_has bat || alias bat="$_dot_bat"
    alias cat="$_dot_bat --paging=never --style=plain"
    export MANPAGER="sh -c 'col -bx | $_dot_bat -l man -p'"
    export MANROFFOPT="-c"
fi
unset _dot_bat

# --- fzf: Ctrl+T files, Alt+C folders (Ctrl+R is atuin, below) ----------------
if _dot_has fzf; then
    if _dot_has fd; then
        export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
        export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
        export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --exclude .git'
    fi
    export FZF_DEFAULT_OPTS="--height=60% --layout=reverse --border=rounded --info=inline"
    export FZF_CTRL_T_OPTS="--preview 'bat --color=always --style=numbers --line-range=:300 {} 2>/dev/null || cat {}'"
    export FZF_ALT_C_OPTS="--preview 'eza --tree --level=2 --icons=always --color=always {} 2>/dev/null || ls {}'"
    if [ -n "$ZSH_VERSION" ]; then
        # Needs a terminal: fzf's script saves and restores every option, and
        # restoring `zle` fails without one (CI, `zsh -ic` from a script).
        [[ -o zle && -t 0 ]] && eval "$(fzf --zsh 2>/dev/null)"
    else
        eval "$(fzf --bash 2>/dev/null)"
    fi
fi

# rgf <pattern>: search file contents, preview the hit, Enter opens it in nvim
# at that line.
rgf() {
    if [ $# -eq 0 ]; then echo "usage: rgf <pattern> [rg options]"; return 1; fi
    local hit file line
    hit=$(rg --line-number --no-heading --color=always --smart-case "$@" |
        fzf --ansi --delimiter : \
            --preview 'bat --color=always --style=numbers --highlight-line {2} {1} 2>/dev/null' \
            --preview-window 'right,60%,+{2}+3/3') || return 0
    file=$(printf '%s' "$hit" | cut -d: -f1)
    line=$(printf '%s' "$hit" | cut -d: -f2)
    "${EDITOR:-nvim}" "+$line" "$file"
}

# --- yazi file manager: `y` = open yazi, cd to where you quit it --------------
y() {
    local tmp cwd
    tmp="$(mktemp -t "yazi-cwd.XXXXXX")"
    yazi "$@" --cwd-file="$tmp"
    if cwd="$(command cat -- "$tmp")" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
        builtin cd -- "$cwd"
    fi
    rm -f -- "$tmp"
}

# --- zsh: Tab completion (macOS's stock zsh leaves it off) --------------------
if [ -n "$ZSH_VERSION" ] && ! (( ${+functions[compdef]} )); then
    autoload -Uz compinit && compinit -i
fi

# --- bash: preexec/precmd hooks (needed by atuin and command notifications) ---
# Must load before the prompt so Starship and the hooks below share it.
if [ -n "$BASH_VERSION" ] && [ -f "$HOME/.local/share/bash-preexec/bash-preexec.sh" ]; then
    . "$HOME/.local/share/bash-preexec/bash-preexec.sh"
fi

# --- Starship prompt with clickable user / path / git branch -----------------
export STARSHIP_CONFIG="${STARSHIP_CONFIG:-$HOME/.config/starship.toml}"
export GITHUB_USER="${GITHUB_USER:-ognjenmarcheta}"
[ -f "$HOME/.config/shell/clickable-prompt.sh" ] && . "$HOME/.config/shell/clickable-prompt.sh"

# --- Notification when a long command finishes (WezTerm toast) ----------------
[ -f "$HOME/.config/shell/notify.sh" ] && . "$HOME/.config/shell/notify.sh"

# --- ai: plain-English -> shell command via Claude Code ----------------------
[ -f "$HOME/.config/shell/ai.sh" ] && . "$HOME/.config/shell/ai.sh"

# --- atuin: Ctrl+R searchable, synced shell history ---------------------------
# Up arrow stays plain history. bash needs bash-preexec (loaded above).
if _dot_has atuin; then
    if [ -n "$ZSH_VERSION" ]; then
        [[ -o zle ]] && eval "$(atuin init zsh --disable-up-arrow)"
    elif [ -n "${bash_preexec_imported:-}${__bp_imported:-}" ]; then
        eval "$(atuin init bash --disable-up-arrow)"
    fi
fi

# --- Daily Node/pnpm update notice (cached, never blocks startup) -----------
[ -x "$HOME/.config/scripts/check-node-updates.sh" ] && "$HOME/.config/scripts/check-node-updates.sh"

# --- zoxide (z) — keep last: it hooks the prompt set up above ---------------
if _dot_has zoxide; then
    if [ -n "$ZSH_VERSION" ]; then
        eval "$(zoxide init zsh)"
    elif [ -n "$BASH_VERSION" ]; then
        eval "$(zoxide init bash)"
    fi
    # Fresh database: teach it ~/Github and its projects so `z Github` works
    if [ -z "$(zoxide query --list 2>/dev/null | head -n1)" ] && [ -d "$HOME/Github" ]; then
        zoxide add "$HOME/Github" "$HOME"/Github/*/ 2>/dev/null
    fi
fi

# --- z + Tab: pick from your most-used folders --------------------------------
# `z <Tab>` / `z kai<Tab>` opens a fuzzy menu of zoxide's folders, most used
# first; Enter jumps there. Paths starting with . / ~ complete normally.
# (zsh: zoxide's own `z kai<Space><Tab>` gives the same menu.)
if [ -n "$BASH_VERSION" ] && _dot_has zoxide && declare -F __zoxide_z_complete_helper >/dev/null; then
    _z_recent_complete() {
        [[ ${#COMP_WORDS[@]} -eq $((COMP_CWORD + 1)) ]] || return 0
        local cur="${COMP_WORDS[COMP_CWORD]}"
        local -a words=("${COMP_WORDS[@]:1}")
        if [[ ${#COMP_WORDS[@]} -eq 2 && "$cur" == [./~]* ]]; then
            mapfile -t COMPREPLY < <(compgen -A directory -- "$cur")
            return 0
        fi
        [[ -z "$cur" ]] && words=("${words[@]:0:${#words[@]}-1}")
        if _dot_has fzf; then
            if __zoxide_result="$(command zoxide query --exclude "$PWD" --interactive -- "${words[@]}" 2>/dev/null)"; then
                COMPREPLY=("${__zoxide_result}/")
                bind -x '"\e[0n": __zoxide_z_complete_helper'
                printf '\e[5n' >/dev/tty
            else
                bind '"\e[0n": redraw-current-line'
                printf '\e[5n' >/dev/tty
            fi
        else
            mapfile -t COMPREPLY < <(command zoxide query --exclude "$PWD" --list -- "${words[@]}" 2>/dev/null | head -n 20)
        fi
    }
    complete -F _z_recent_complete -o filenames -- z
fi

# --- Machine-specific overrides (not in git) ---------------------------------
[ -f "$HOME/.config/shell/local.sh" ] && . "$HOME/.config/shell/local.sh"
