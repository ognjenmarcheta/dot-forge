# Shared interactive shell setup for bash & zsh.
# Loaded automatically by WezTerm (see ~/.config/shell/bashrc and
# ~/.config/shell/zsh/.zshrc). Safe to also source from ~/.bashrc / ~/.zshrc.

[ -n "$_SHELL_ALIASES_LOADED" ] && return 0
_SHELL_ALIASES_LOADED=1

# --- PATH ---------------------------------------------------------------------
# install.sh puts CLI tools (starship, zoxide, fzf, yazi, …) in ~/.local/bin on
# Linux and uses Homebrew on macOS. ~/.config/shell/bin is an older location.
for _d in "$HOME/.config/shell/bin" "$HOME/.local/bin"; do
    case ":$PATH:" in
        *":$_d:"*) ;;
        *) [ -d "$_d" ] && PATH="$_d:$PATH" ;;
    esac
done
unset _d
if [ -x /opt/homebrew/bin/brew ] && ! command -v brew >/dev/null 2>&1; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
fi
export PATH

# herdr-* helper scripts and check-node-updates.sh (ported from the Mac)
case ":$PATH:" in
    *":$HOME/.config/scripts:"*) ;;
    *) PATH="$PATH:$HOME/.config/scripts"; export PATH ;;
esac

# --- Clickable ls / ll -------------------------------------------------------
# ls prints every entry as an OSC 8 hyperlink (file://host/path). WezTerm's
# open-uri handler (~/.config/wezterm/events.lua) opens folders in Files and
# reveals files in Files. "auto" = only when printing to a terminal.
if ls --hyperlink=auto -d / >/dev/null 2>&1; then
    alias ls='ls --color=auto --hyperlink=auto'
elif command -v gls >/dev/null 2>&1; then
    # macOS: BSD ls has no hyperlinks; GNU ls comes from `brew install coreutils`
    alias ls='gls --color=auto --hyperlink=auto'
else
    alias ls='ls --color=auto'
fi
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'

# --- Starship prompt with clickable user / path / git branch -----------------
export STARSHIP_CONFIG="${STARSHIP_CONFIG:-$HOME/.config/starship.toml}"
export GITHUB_USER="${GITHUB_USER:-ognjenmarcheta}"   # from your Mac gh config
[ -f "$HOME/.config/shell/clickable-prompt.sh" ] && . "$HOME/.config/shell/clickable-prompt.sh"

# --- Daily Node/pnpm update notice (cached, never blocks startup) -----------
[ -x "$HOME/.config/scripts/check-node-updates.sh" ] && "$HOME/.config/scripts/check-node-updates.sh"

# --- yazi file manager: `y` = open yazi, cd to where you quit it -----------
y() {
    local tmp cwd
    tmp="$(mktemp -t "yazi-cwd.XXXXXX")"
    yazi "$@" --cwd-file="$tmp"
    if cwd="$(command cat -- "$tmp")" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
        builtin cd -- "$cwd"
    fi
    rm -f -- "$tmp"
}

# --- ai: plain-English -> shell command via Claude Code ----------------------
[ -f "$HOME/.config/shell/ai.sh" ] && . "$HOME/.config/shell/ai.sh"

# --- zoxide (z) — keep last: it hooks the prompt set up above --------------------------------------------------------------
if command -v zoxide >/dev/null 2>&1; then
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
# `z <Tab>` or `z kai<Tab>` opens a fuzzy menu (fzf) of the folders zoxide
# knows, most used first and filtered by what you typed; Enter jumps there.
# Paths starting with . / ~ still get normal folder completion.
# Without fzf it falls back to a plain list of matching folders.
# (zsh: zoxide's own `z kai<Space><Tab>` gives the same menu.)
if [ -n "$BASH_VERSION" ] && command -v zoxide >/dev/null 2>&1 && declare -F __zoxide_z_complete_helper >/dev/null; then
    _z_recent_complete() {
        # only when the cursor is at the end of the line
        [[ ${#COMP_WORDS[@]} -eq $((COMP_CWORD + 1)) ]] || return 0
        local cur="${COMP_WORDS[COMP_CWORD]}"
        local -a words=("${COMP_WORDS[@]:1}")
        if [[ ${#COMP_WORDS[@]} -eq 2 && "$cur" == [./~]* ]]; then
            mapfile -t COMPREPLY < <(compgen -A directory -- "$cur")
            return 0
        fi
        [[ -z "$cur" ]] && words=("${words[@]:0:${#words[@]}-1}")
        if command -v fzf >/dev/null 2>&1; then
            if __zoxide_result="$(command zoxide query --exclude "$PWD" --interactive -- "${words[@]}" 2>/dev/null)"; then
                COMPREPLY=("${__zoxide_result}/")
                bind -x '"\e[0n": __zoxide_z_complete_helper'   # puts `z <dir>` on the line and runs it
                printf '\e[5n' >/dev/tty
            else
                bind '"\e[0n": redraw-current-line'             # cancelled: redraw the prompt
                printf '\e[5n' >/dev/tty
            fi
        else
            mapfile -t COMPREPLY < <(command zoxide query --exclude "$PWD" --list -- "${words[@]}" 2>/dev/null | head -n 20)
        fi
    }
    complete -F _z_recent_complete -o filenames -- z
fi
