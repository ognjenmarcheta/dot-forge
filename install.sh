#!/usr/bin/env bash
# Dotfiles installer — macOS and Linux (Ubuntu/Debian).
#
#   git clone git@github.com:ognjenmarcheta/dotfiles.git ~/Github/dotfiles
#   ~/Github/dotfiles/install.sh
#
# Options:
#   --links-only   only link configs + hook the shell (no package installs)
#   --no-nvim      skip installing Neovim plugins
#   -h, --help
#
# Safe to run again: existing configs are moved to ~/.dotfiles-backup/<time>/
# before being replaced by links, and nothing is linked twice.

set -euo pipefail

DOTFILES="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
BIN="$HOME/.local/bin"
BACKUP="$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)"
OS="$(uname -s)"
ARCH="$(uname -m)"
LINKS_ONLY=0
NVIM_PLUGINS=1

for arg in "$@"; do
    case "$arg" in
        --links-only) LINKS_ONLY=1 ;;
        --no-nvim) NVIM_PLUGINS=0 ;;
        -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
        *) echo "unknown option: $arg" >&2; exit 1 ;;
    esac
done

c_info=$'\033[1;34m'; c_ok=$'\033[1;32m'; c_warn=$'\033[1;33m'; c_off=$'\033[0m'
step() { printf '\n%s==> %s%s\n' "$c_info" "$*" "$c_off"; }
ok()   { printf '  %s✓%s %s\n' "$c_ok" "$c_off" "$*"; }
warn() { printf '  %s!%s %s\n' "$c_warn" "$c_off" "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

case "$OS" in
    Darwin|Linux) ;;
    *) echo "Unsupported OS: $OS" >&2; exit 1 ;;
esac

# ---------------------------------------------------------------- packages ---

install_macos_packages() {
    step "Homebrew packages"
    if ! have brew; then
        warn "Homebrew not found — installing it (official installer)"
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        [ -x /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv)"
        [ -x /usr/local/bin/brew ] && eval "$(/usr/local/bin/brew shellenv)"
    fi
    brew bundle --file="$DOTFILES/Brewfile"
    ok "Brewfile installed"
}

apt_install() {
    # install what exists in this Ubuntu/Debian release, skip the rest
    local pkg missing=()
    for pkg in "$@"; do
        if apt-cache show "$pkg" >/dev/null 2>&1; then
            dpkg -s "$pkg" >/dev/null 2>&1 || missing+=("$pkg")
        else
            warn "apt has no package '$pkg' here — skipped"
        fi
    done
    if [ ${#missing[@]} -gt 0 ]; then
        sudo apt-get install -y "${missing[@]}"
    fi
}

# Download the latest GitHub release asset matching a pattern into a temp dir.
gh_release() { # repo  asset-regex  -> prints path of downloaded file
    local repo="$1" pattern="$2" url tmp
    url=$(curl -fsSL "https://api.github.com/repos/$repo/releases/latest" \
        | grep -o '"browser_download_url": *"[^"]*"' | sed 's/.*"\(https[^"]*\)"/\1/' \
        | grep -E "$pattern" | head -n1)
    [ -n "$url" ] || { warn "no release asset for $repo matching $pattern"; return 1; }
    tmp="$(mktemp -d)"
    curl -fsSL -o "$tmp/$(basename "$url")" "$url"
    printf '%s' "$tmp/$(basename "$url")"
}

install_release_bin() { # name repo asset-regex  (binary named <name> inside archive)
    local name="$1" repo="$2" pattern="$3" file dir
    if have "$name"; then ok "$name already installed ($(command -v "$name"))"; return 0; fi
    file=$(gh_release "$repo" "$pattern") || return 0
    dir="$(dirname "$file")"
    case "$file" in
        *.tar.gz|*.tgz) tar -xzf "$file" -C "$dir" ;;
        *.zip) unzip -q -o "$file" -d "$dir" ;;
    esac
    find "$dir" -type f \( -name "$name" -o -name ya \) -perm -u+x -exec install -m 755 {} "$BIN/" \;
    rm -rf "$dir"
    have "$name" && ok "$name installed" || warn "$name could not be installed"
}

install_linux_packages() {
    step "apt packages (asks for your password)"
    if ! have apt-get; then
        warn "not an apt-based distro — install packages yourself, then re-run with --links-only"
        return 0
    fi
    sudo apt-get update -qq
    apt_install git curl unzip build-essential zsh \
        ripgrep fd-find jq btop lazygit fastfetch thefuck \
        ffmpegthumbnailer poppler-utils imagemagick 7zip \
        wl-clipboard libnotify-bin
    # Ubuntu calls fd "fdfind"
    if have fdfind && ! have fd; then ln -sf "$(command -v fdfind)" "$BIN/fd"; ok "fd -> fdfind"; fi

    step "Neovim (0.11.x — what this config is tested with)"
    local nv=""
    have nvim && nv=$(nvim --version | head -n1 | grep -o '[0-9]\+\.[0-9]\+' | head -n1)
    if [ -z "$nv" ]; then
        apt_install neovim
        have nvim && nv=$(nvim --version | head -n1 | grep -o '[0-9]\+\.[0-9]\+' | head -n1)
    fi
    if [ -z "$nv" ] || [ "$(printf '%s\n0.11\n' "$nv" | sort -V | head -n1)" != "0.11" ]; then
        warn "Neovim ${nv:-missing} is older than 0.11 — installing 0.11.6 to ~/.local/opt/nvim"
        mkdir -p "$HOME/.local/opt"
        curl -fsSL "https://github.com/neovim/neovim/releases/download/v0.11.6/nvim-linux-${ARCH/aarch64/arm64}.tar.gz" \
            | tar -xz -C "$HOME/.local/opt"
        ln -sf "$HOME/.local/opt/nvim-linux-${ARCH/aarch64/arm64}/bin/nvim" "$BIN/nvim"
    fi
    ok "nvim $(nvim --version | head -n1 | cut -d' ' -f2)"

    step "CLI tools from their official GitHub releases -> ~/.local/bin"
    local a="$ARCH"
    install_release_bin starship starship/starship  "starship-${a}-unknown-linux-musl\.tar\.gz$"
    install_release_bin zoxide   ajeetdsouza/zoxide "zoxide-.*-${a}-unknown-linux-musl\.tar\.gz$"
    install_release_bin fzf      junegunn/fzf       "fzf-.*-linux_$([ "$a" = x86_64 ] && echo amd64 || echo arm64)\.tar\.gz$"
    install_release_bin yazi     sxyazi/yazi        "yazi-${a}-unknown-linux-musl\.zip$"
    install_release_bin atuin    atuinsh/atuin      "atuin-${a}-unknown-linux-gnu\.tar\.gz$"
    if ! have lazygit; then
        install_release_bin lazygit jesseduffield/lazygit "lazygit_.*_[Ll]inux_$([ "$a" = x86_64 ] && echo x86_64 || echo arm64)\.tar\.gz$"
    fi

    step "WezTerm"
    if have wezterm || (have flatpak && flatpak info org.wezfurlong.wezterm >/dev/null 2>&1); then
        ok "WezTerm already installed"
    elif have flatpak; then
        flatpak install -y flathub org.wezfurlong.wezterm && ok "WezTerm installed (Flatpak)"
    else
        warn "install WezTerm: https://wezterm.org/install/linux.html"
    fi
}

install_claude_code() {
    step "Claude Code (for the \`ai\` command)"
    if have claude || [ -x "$HOME/.local/bin/claude" ]; then
        ok "claude already installed"
    else
        curl -fsSL https://claude.ai/install.sh | bash && ok "claude installed — run \`claude\` once to log in"
    fi
}

# ------------------------------------------------------------------- links ---

link() { # source target
    local src="$1" dst="$2"
    if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
        ok "${dst/#"$HOME"/\~} (already linked)"
        return
    fi
    if [ -e "$dst" ] || [ -L "$dst" ]; then
        mkdir -p "$BACKUP"
        mv "$dst" "$BACKUP/"
        warn "${dst/#"$HOME"/\~} existed — moved to ${BACKUP/#"$HOME"/\~}/"
    fi
    mkdir -p "$(dirname "$dst")"
    ln -s "$src" "$dst"
    ok "${dst/#"$HOME"/\~} -> ${src/#"$HOME"/\~}"
}

link_configs() {
    step "Linking configs into ${CONFIG_HOME/#"$HOME"/\~}"
    local item
    for item in "$DOTFILES"/config/* ; do
        link "$item" "$CONFIG_HOME/$(basename "$item")"
    done
    if [ "$OS" = Darwin ]; then
        for item in "$DOTFILES"/macos/*; do
            link "$item" "$CONFIG_HOME/$(basename "$item")"
        done
    fi
}

link_agent_skills() {
    # crush / devin / goose / kimchi share the skills in ~/.agents/skills
    local skills="$HOME/.agents/skills" s d
    [ -d "$skills" ] || { warn "no ~/.agents/skills — skipping agent skill links"; return 0; }
    step "Linking ~/.agents/skills into crush, devin, goose, kimchi"
    for d in "$CONFIG_HOME/crush/skills" "$CONFIG_HOME/devin/skills" "$CONFIG_HOME/goose/skills" "$CONFIG_HOME/kimchi/harness/skills"; do
        mkdir -p "$d"
        for s in "$skills"/*/; do
            s="${s%/}"
            [ -e "$d/$(basename "$s")" ] || ln -s "$s" "$d/$(basename "$s")"
        done
        ok "${d/#"$HOME"/\~}"
    done
}

hook_shell() {
    step "Hooking the shell setup into your rc files"
    local line='[ -f "$HOME/.config/shell/aliases.sh" ] && . "$HOME/.config/shell/aliases.sh"  # dotfiles'
    local rc
    for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
        # .zshrc only if zsh is around (always on macOS)
        if [ "$rc" = "$HOME/.zshrc" ] && ! have zsh; then continue; fi
        touch "$rc"
        if grep -qF '.config/shell/aliases.sh' "$rc"; then
            ok "${rc/#"$HOME"/\~} (already hooked)"
        else
            printf '\n%s\n' "$line" >> "$rc"
            ok "${rc/#"$HOME"/\~}"
        fi
    done
}

# -------------------------------------------------------------- the rest -----

setup_git_and_gh() {
    step "git / gh"
    if have gh; then
        gh alias set co 'pr checkout' --clobber >/dev/null 2>&1 && ok "gh alias: co = pr checkout" \
            || warn "gh alias not set (run \`gh auth login\` first, then re-run)"
    fi
    ok "global git ignore: ~/.config/git/ignore (git picks it up automatically)"
}

install_nvim_plugins() {
    have nvim || { warn "nvim not found — skipping plugins"; return 0; }
    step "Neovim plugins (versions pinned in lazy-lock.json)"
    nvim --headless "+Lazy! restore" +qa >/dev/null 2>&1 || true
    ok "plugins installed — open nvim once; Mason then installs language servers"
}

main() {
    printf '%sDotfiles%s from %s on %s/%s\n' "$c_info" "$c_off" "${DOTFILES/#"$HOME"/\~}" "$OS" "$ARCH"
    mkdir -p "$BIN"
    export PATH="$BIN:$PATH"

    if [ "$LINKS_ONLY" -eq 0 ]; then
        if [ "$OS" = Darwin ]; then install_macos_packages; else install_linux_packages; fi
        install_claude_code
    fi

    link_configs
    link_agent_skills
    hook_shell
    setup_git_and_gh
    [ "$LINKS_ONLY" -eq 0 ] && [ "$NVIM_PLUGINS" -eq 1 ] && install_nvim_plugins

    step "Done"
    echo "  Open a new terminal (WezTerm). Logins to redo on a new machine:"
    echo "    gh auth login · claude (for \`ai\`) · :Copilot auth in nvim · atuin login (optional)"
    [ -d "$BACKUP" ] && echo "  Replaced configs are in ${BACKUP/#"$HOME"/\~}"
    return 0
}

main
