#!/usr/bin/env bash
# Dotfiles installer — macOS and Linux (Ubuntu/Debian).
#
#   ~/Github/dotfiles/install.sh
#
# Options:
#   --links-only   only link configs + hook the shell (no package installs)
#   --no-nvim      skip installing Neovim plugins
#   -h, --help
#
# Safe to run again: existing configs are moved to ~/.dotfiles-backup/<time>/
# before being replaced by links, and nothing is linked twice.
# Works with macOS's stock bash 3.2.

set -euo pipefail

DOTFILES="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
BIN="$HOME/.local/bin"
OPT="$HOME/.local/opt"
BACKUP="$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)"
OS="${DOTFILES_OS:-$(uname -s)}"   # DOTFILES_OS: override for testing only
ARCH="$(uname -m)"
NVIM_VERSION="0.11.6"              # the Neovim this config is tested with
LINKS_ONLY=0
NVIM_PLUGINS=1

for arg in "$@"; do
    case "$arg" in
        --links-only) LINKS_ONLY=1 ;;
        --no-nvim) NVIM_PLUGINS=0 ;;
        -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
        *) echo "unknown option: $arg" >&2; exit 1 ;;
    esac
done

c_info=$'\033[1;34m'; c_ok=$'\033[1;32m'; c_warn=$'\033[1;33m'; c_off=$'\033[0m'
step() { printf '\n%s==> %s%s\n' "$c_info" "$*" "$c_off"; }
ok()   { printf '  %s✓%s %s\n' "$c_ok" "$c_off" "$*"; }
warn() { printf '  %s!%s %s\n' "$c_warn" "$c_off" "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }
tilde() { case "$1" in "$HOME"/*|"$HOME") printf '~%s' "${1#"$HOME"}" ;; *) printf '%s' "$1" ;; esac; }
nvim_version() { nvim --version 2>/dev/null | sed -n 1p || true; }   # e.g. "NVIM v0.11.6"

case "$OS" in
    Darwin|Linux) ;;
    *) echo "Unsupported OS: $OS" >&2; exit 1 ;;
esac

# ------------------------------------------------------------------- links ---

link() { # source target
    local src="$1" dst="$2"
    if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
        ok "$(tilde "$dst") (already linked)"
        return 0
    fi
    if [ -e "$dst" ] || [ -L "$dst" ]; then
        mkdir -p "$BACKUP"
        mv "$dst" "$BACKUP/"
        warn "$(tilde "$dst") existed — moved to $(tilde "$BACKUP")/"
    fi
    mkdir -p "$(dirname "$dst")"
    ln -s "$src" "$dst"
    ok "$(tilde "$dst") -> $(tilde "$src")"
}

link_configs() {
    step "Linking configs into $(tilde "$CONFIG_HOME")"
    local item
    for item in "$DOTFILES"/config/*; do
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
    local skills="$HOME/.agents/skills" s d n=0
    for s in "$skills"/*/; do [ -d "$s" ] && n=$((n + 1)); done
    if [ "$n" -eq 0 ]; then warn "no skills in ~/.agents/skills — skipping agent skill links"; return 0; fi
    step "Linking $n skills from ~/.agents/skills into crush, devin, goose, kimchi"
    for d in "$CONFIG_HOME/crush/skills" "$CONFIG_HOME/devin/skills" "$CONFIG_HOME/goose/skills" "$CONFIG_HOME/kimchi/harness/skills"; do
        mkdir -p "$d"
        for s in "$skills"/*/; do
            [ -d "$s" ] || continue
            s="${s%/}"
            [ -e "$d/$(basename "$s")" ] || ln -s "$s" "$d/$(basename "$s")"
        done
        ok "$(tilde "$d")"
    done
}

hook_shell() {
    step "Hooking the shell setup into your rc files"
    local line='[ -f "$HOME/.config/shell/aliases.sh" ] && . "$HOME/.config/shell/aliases.sh"  # dotfiles'
    local rc
    for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
        if [ "$rc" = "$HOME/.zshrc" ] && ! have zsh; then continue; fi
        touch "$rc"
        if grep -qF '.config/shell/aliases.sh' "$rc"; then
            ok "$(tilde "$rc") (already hooked)"
        else
            printf '\n%s\n' "$line" >> "$rc"
            ok "$(tilde "$rc")"
        fi
    done
    if [ "$OS" = Darwin ]; then
        # macOS bash login shells read ~/.bash_profile, not ~/.bashrc
        touch "$HOME/.bash_profile"
        grep -qF '.bashrc' "$HOME/.bash_profile" \
            || printf '\n[ -f "$HOME/.bashrc" ] && . "$HOME/.bashrc"  # dotfiles\n' >> "$HOME/.bash_profile"
    fi
}

# ---------------------------------------------------------------- packages ---

# Download the latest GitHub release asset matching a regex; print the file path.
gh_release() { # repo  asset-regex
    local repo="$1" pattern="$2" url tmp
    url=$(curl -fsSL "https://api.github.com/repos/$repo/releases/latest" \
        | grep -o '"browser_download_url": *"[^"]*"' | sed 's/.*"\(https[^"]*\)"/\1/' \
        | grep -E "$pattern" | head -n1 || true)
    if [ -z "$url" ]; then warn "no release asset for $repo matching $pattern"; return 1; fi
    tmp="$(mktemp -d)"
    curl -fsSL -o "$tmp/$(basename "$url")" "$url"
    printf '%s' "$tmp/$(basename "$url")"
}

install_release_bin() { # name repo asset-regex  (binary named <name> inside the archive)
    local name="$1" repo="$2" pattern="$3" file dir
    if have "$name"; then ok "$name already installed ($(tilde "$(command -v "$name")"))"; return 0; fi
    file=$(gh_release "$repo" "$pattern") || return 0
    dir="$(dirname "$file")"
    case "$file" in
        *.tar.gz|*.tgz) tar -xzf "$file" -C "$dir" ;;
        *.zip) unzip -q -o "$file" -d "$dir" ;;
    esac
    find "$dir" -type f \( -name "$name" -o -name ya \) -perm -u+x -exec install -m 755 {} "$BIN/" \;
    rm -rf "$dir"
    if have "$name"; then ok "$name installed"; else warn "$name could not be installed"; fi
}

install_neovim() {
    step "Neovim $NVIM_VERSION (the version this config is tested with)"
    local current=""
    have nvim && current="$(nvim_version)"
    case "$current" in
        "NVIM v${NVIM_VERSION%.*}."*) ok "$current ($(tilde "$(command -v nvim)"))"; return 0 ;;
        "") ;;
        *) warn "found $current — installing $NVIM_VERSION into ~/.local (takes priority on PATH)" ;;
    esac
    local platform
    case "$OS-$ARCH" in
        Linux-x86_64)  platform=linux-x86_64 ;;
        Linux-aarch64) platform=linux-arm64 ;;
        Darwin-arm64)  platform=macos-arm64 ;;
        Darwin-x86_64) platform=macos-x86_64 ;;
        *) warn "no Neovim build for $OS/$ARCH"; return 0 ;;
    esac
    mkdir -p "$OPT"
    rm -rf "$OPT/nvim-$platform"
    curl -fsSL "https://github.com/neovim/neovim/releases/download/v$NVIM_VERSION/nvim-$platform.tar.gz" \
        | tar -xz -C "$OPT"
    ln -sf "$OPT/nvim-$platform/bin/nvim" "$BIN/nvim"
    hash -r
    ok "$("$BIN/nvim" --version | sed -n 1p) -> $(tilde "$BIN/nvim")"
}

install_macos_packages() {
    step "Xcode command line tools"
    if xcode-select -p >/dev/null 2>&1; then
        ok "installed"
    else
        xcode-select --install || true
        warn "finish the Xcode tools install in the window that opened, then run this script again"
        exit 1
    fi

    step "Homebrew packages"
    if ! have brew; then
        warn "Homebrew not found — installing it (official installer)"
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi
    [ -x /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv)"
    [ -x /usr/local/bin/brew ] && eval "$(/usr/local/bin/brew shellenv)"
    if brew bundle --file="$DOTFILES/Brewfile"; then
        ok "Brewfile installed"
    else
        warn "some Brewfile entries failed (see above) — the rest is installed; re-run later"
    fi
    export PATH="$BIN:$PATH"   # keep ~/.local/bin (pinned nvim) ahead of Homebrew
}

apt_install() {
    # install what exists in this Ubuntu/Debian release, skip the rest
    local pkg
    local missing=""
    for pkg in "$@"; do
        if apt-cache show "$pkg" >/dev/null 2>&1; then
            dpkg -s "$pkg" >/dev/null 2>&1 || missing="$missing $pkg"
        else
            warn "apt has no package '$pkg' here — skipped"
        fi
    done
    if [ -n "$missing" ]; then
        # shellcheck disable=SC2086
        sudo apt-get install -y $missing
    fi
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
    have node || apt_install nodejs npm    # Mason language servers, Copilot, mcphub
    if have fdfind && ! have fd; then ln -sf "$(command -v fdfind)" "$BIN/fd"; ok "fd -> fdfind"; fi

    step "CLI tools from their official GitHub releases -> ~/.local/bin"
    local a="$ARCH" go_arch
    if [ "$a" = x86_64 ]; then go_arch=amd64; else go_arch=arm64; fi
    install_release_bin starship starship/starship  "starship-${a}-unknown-linux-musl\.tar\.gz$"
    install_release_bin zoxide   ajeetdsouza/zoxide "zoxide-.*-${a}-unknown-linux-musl\.tar\.gz$"
    install_release_bin fzf      junegunn/fzf       "fzf-.*-linux_${go_arch}\.tar\.gz$"
    install_release_bin yazi     sxyazi/yazi        "yazi-${a}-unknown-linux-musl\.zip$"
    install_release_bin atuin    atuinsh/atuin      "atuin-${a}-unknown-linux-musl\.tar\.gz$"
    install_release_bin opencode sst/opencode       "opencode-linux-$([ "$a" = x86_64 ] && echo x64 || echo arm64)\.tar\.gz$"   # glibc build (the musl one needs musl's loader)
    install_release_bin lazygit  jesseduffield/lazygit "lazygit_.*_[Ll]inux_$([ "$a" = x86_64 ] && echo x86_64 || echo arm64)\.tar\.gz$"

    step "WezTerm"
    if have wezterm || { have flatpak && flatpak info org.wezfurlong.wezterm >/dev/null 2>&1; }; then
        ok "WezTerm already installed"
    elif have flatpak; then
        if flatpak install -y flathub org.wezfurlong.wezterm; then ok "WezTerm installed (Flatpak)"; else warn "WezTerm Flatpak install failed"; fi
    else
        warn "install WezTerm: https://wezterm.org/install/linux.html"
    fi
}

install_claude_code() {
    step "Claude Code (for the \`ai\` command)"
    if have claude || [ -x "$HOME/.local/bin/claude" ]; then
        ok "claude already installed"
    elif curl -fsSL https://claude.ai/install.sh | bash; then
        ok "claude installed — run \`claude\` once to log in"
    else
        warn "Claude Code install failed — see https://docs.claude.com/en/docs/claude-code"
    fi
}

# -------------------------------------------------------------- the rest -----

setup_gh() {
    have gh || return 0
    step "GitHub CLI"
    if gh alias set co 'pr checkout' --clobber >/dev/null 2>&1; then
        ok "gh alias: co = pr checkout"
    else
        warn "gh alias not set — run \`gh auth login\`, then this script again"
    fi
}

install_nvim_plugins() {
    have nvim || { warn "nvim not found — skipping plugins"; return 0; }
    step "Neovim plugins (versions pinned in lazy-lock.json; takes a few minutes)"
    nvim --headless "+Lazy! restore" +qa >/dev/null 2>&1 || true
    ok "done — open nvim once; Mason then installs the language servers"
}

main() {
    printf '%sDotfiles%s from %s on %s/%s\n' "$c_info" "$c_off" "$(tilde "$DOTFILES")" "$OS" "$ARCH"
    mkdir -p "$BIN"
    export PATH="$BIN:$PATH"

    # Link first: replaced configs (and any tools that lived inside them, e.g.
    # the old ~/.config/shell/bin) move to the backup before tools are checked.
    link_configs
    link_agent_skills
    hook_shell

    if [ "$LINKS_ONLY" -eq 0 ]; then
        if [ "$OS" = Darwin ]; then install_macos_packages; else install_linux_packages; fi
        install_neovim
        install_claude_code
        setup_gh
        [ "$NVIM_PLUGINS" -eq 1 ] && install_nvim_plugins
    fi

    step "Done"
    echo "  Open a new terminal (WezTerm). Logins to redo on a new machine:"
    echo "    gh auth login · claude (for \`ai\`) · :Copilot auth in nvim · atuin login (optional)"
    if [ -d "$BACKUP" ]; then echo "  Replaced configs are in $(tilde "$BACKUP")"; fi
    return 0
}

main
