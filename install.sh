#!/usr/bin/env bash
# Dotfiles installer — macOS and Linux (Ubuntu/Debian).
#
#   ~/Github/dotfiles/install.sh
#
# Options:
#   --links-only   only link configs + hook the shell (no package installs)
#   --no-nvim      skip installing Neovim plugins
#   --upgrade      also upgrade the installed tools (what `dot update` runs);
#                  Neovim and its plugins stay on their pinned versions
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
BASH_PREEXEC_VERSION="0.7.0"
LINKS_ONLY=0
NVIM_PLUGINS=1
UPGRADE=0
IN_CI=0
case "${CI:-}" in true|1) IN_CI=1 ;; esac   # GitHub Actions: no GUI apps, no logins

for arg in "$@"; do
    case "$arg" in
        --links-only) LINKS_ONLY=1 ;;
        --no-nvim) NVIM_PLUGINS=0 ;;
        --upgrade) UPGRADE=1 ;;
        -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
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
    if have zsh && [ "$OS" = Linux ] && ! grep -qF skip_global_compinit "$HOME/.zshenv" 2>/dev/null; then
        # Ubuntu's /etc/zsh/zshrc runs its own compinit first (twice the work, and it
        # stops to ask about "insecure directories"); aliases.sh runs `compinit -i`.
        printf 'skip_global_compinit=1  # dotfiles\n' >> "$HOME/.zshenv"
    fi
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
    local auth=()
    [ -n "${GITHUB_TOKEN:-}" ] && auth=(-H "Authorization: Bearer $GITHUB_TOKEN")
    url=$(curl -fsSL ${auth[@]+"${auth[@]}"} "https://api.github.com/repos/$repo/releases/latest" \
        | grep -o '"browser_download_url": *"[^"]*"' | sed 's/.*"\(https[^"]*\)"/\1/' \
        | grep -E "$pattern" | head -n1 || true)
    if [ -z "$url" ]; then warn "no release asset for $repo matching $pattern"; return 1; fi
    tmp="$(mktemp -d)"
    curl -fsSL -o "$tmp/$(basename "$url")" "$url"
    printf '%s' "$tmp/$(basename "$url")"
}

install_release_bin() { # name repo asset-regex  (binary named <name> inside the archive)
    local name="$1" repo="$2" pattern="$3" file dir
    if have "$name"; then
        # --upgrade refreshes only the copies this script put in ~/.local/bin
        if [ "$UPGRADE" -eq 0 ] || [ "$(command -v "$name")" != "$BIN/$name" ]; then
            ok "$name already installed ($(tilde "$(command -v "$name")"))"; return 0
        fi
    fi
    file=$(gh_release "$repo" "$pattern") || return 0
    dir="$(dirname "$file")"
    case "$file" in
        *.tar.gz|*.tgz) tar -xzf "$file" -C "$dir" ;;
        *.zip) unzip -q -o "$file" -d "$dir" ;;
    esac
    find "$dir" -type f \( -name "$name" -o -name ya \) -perm -u+x -exec install -m 755 {} "$BIN/" \;
    rm -rf "$dir"
    hash -r
    if have "$name"; then ok "$name installed ($("$name" --version 2>/dev/null | sed -n 1p))"; else warn "$name could not be installed"; fi
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
    if [ "$UPGRADE" -eq 1 ]; then brew update && brew upgrade || warn "brew upgrade had problems"; fi
    if brew bundle --file="$DOTFILES/Brewfile"; then
        ok "Brewfile installed"
    else
        warn "some Brewfile entries failed (see above) — the rest is installed; re-run later"
    fi
    export PATH="$BIN:$PATH"   # keep ~/.local/bin (pinned nvim) ahead of Homebrew
}

# a stalled mirror connection is retried instead of hanging the install
APT_OPTS="-o Acquire::Retries=5 -o Acquire::http::Timeout=30 -o Acquire::https::Timeout=30"

apt_install() {
    # install what exists in this Ubuntu/Debian release, skip the rest
    # (--upgrade: also upgrade the ones already installed — only these, not the whole system)
    local pkg
    local missing=""
    local present=""
    for pkg in "$@"; do
        if apt-cache show "$pkg" >/dev/null 2>&1; then
            if dpkg -s "$pkg" >/dev/null 2>&1; then present="$present $pkg"; else missing="$missing $pkg"; fi
        else
            warn "apt has no package '$pkg' here — skipped"
        fi
    done
    if [ -n "$missing" ]; then
        # shellcheck disable=SC2086
        sudo DEBIAN_FRONTEND=noninteractive apt-get $APT_OPTS install -y $missing
    fi
    if [ "$UPGRADE" -eq 1 ] && [ -n "$present" ]; then
        # shellcheck disable=SC2086
        sudo DEBIAN_FRONTEND=noninteractive apt-get $APT_OPTS install --only-upgrade -y $present || warn "apt upgrade had problems"
    fi
}

install_linux_packages() {
    step "apt packages (asks for your password)"
    if ! have apt-get; then
        warn "not an apt-based distro — install packages yourself, then re-run with --links-only"
        return 0
    fi
    sudo apt-get $APT_OPTS update -qq
    apt_install git curl unzip build-essential zsh \
        ripgrep fd-find jq btop lazygit fastfetch thefuck \
        wl-clipboard libnotify-bin duf
    # yazi previews: big (ghostscript, ffmpeg libs…), and nothing to test in CI
    [ "$IN_CI" -eq 1 ] || apt_install ffmpegthumbnailer poppler-utils imagemagick 7zip
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
    install_release_bin eza      eza-community/eza  "eza_${a}-unknown-linux-$([ "$a" = x86_64 ] && echo musl || echo gnu)\.tar\.gz$"
    install_release_bin bat      sharkdp/bat        "bat-v.*-${a}-unknown-linux-musl\.tar\.gz$"
    install_release_bin delta    dandavison/delta   "delta-.*-${a}-unknown-linux-musl\.tar\.gz$"
    install_release_bin dust     bootandy/dust      "dust-v.*-${a}-unknown-linux-musl\.tar\.gz$"
    install_release_bin mise     jdx/mise           "mise-v.*-linux-$([ "$a" = x86_64 ] && echo x64 || echo arm64)-musl\.tar\.gz$"

    [ "$IN_CI" -eq 1 ] && return 0
    step "WezTerm"
    if have wezterm || { have flatpak && flatpak info org.wezfurlong.wezterm >/dev/null 2>&1; }; then
        ok "WezTerm already installed"
    elif have flatpak; then
        if flatpak install -y flathub org.wezfurlong.wezterm; then ok "WezTerm installed (Flatpak)"; else warn "WezTerm Flatpak install failed"; fi
    else
        warn "install WezTerm: https://wezterm.org/install/linux.html"
    fi
    # `wezterm` command for the Flatpak build: smart-splits.nvim calls
    # `wezterm cli` to move from a Neovim split into the next WezTerm pane.
    if ! have wezterm && have flatpak && flatpak info org.wezfurlong.wezterm >/dev/null 2>&1; then
        printf '#!/bin/sh\nexec flatpak run --command=wezterm org.wezfurlong.wezterm "$@"\n' > "$BIN/wezterm"
        chmod +x "$BIN/wezterm"
        ok "$(tilde "$BIN/wezterm") -> the WezTerm Flatpak"
    fi
}

install_claude_code() {
    [ "$IN_CI" -eq 1 ] && return 0
    step "Claude Code (for the \`ai\` command)"
    if have claude || [ -x "$HOME/.local/bin/claude" ]; then
        if [ "$UPGRADE" -eq 1 ]; then claude update >/dev/null 2>&1 && ok "claude updated" || warn "claude update failed"; fi
        ok "claude already installed"
    elif curl -fsSL https://claude.ai/install.sh | bash; then
        ok "claude installed — run \`claude\` once to log in"
    else
        warn "Claude Code install failed — see https://docs.claude.com/en/docs/claude-code"
    fi
}

# -------------------------------------------------------------- the rest -----

install_bash_preexec() {
    # lets atuin and the long-command notifications hook into bash (zsh has this built in)
    local dir="$HOME/.local/share/bash-preexec" file="$HOME/.local/share/bash-preexec/bash-preexec.sh"
    if grep -q "bash-preexec.sh" "$file" 2>/dev/null && [ "$UPGRADE" -eq 0 ]; then return 0; fi
    step "bash-preexec $BASH_PREEXEC_VERSION"
    mkdir -p "$dir"
    if curl -fsSL -o "$file.tmp" "https://raw.githubusercontent.com/rcaloras/bash-preexec/$BASH_PREEXEC_VERSION/bash-preexec.sh"; then
        mv "$file.tmp" "$file"; ok "$(tilde "$file")"
    else
        rm -f "$file.tmp"; warn "bash-preexec download failed — atuin and notifications stay off in bash"
    fi
}

setup_tools() {
    step "Tool setup"
    if have mise; then
        if [ "$UPGRADE" -eq 1 ]; then mise upgrade -y >/dev/null 2>&1 || true; fi
        # shims put node etc. on PATH for the rest of this run (Neovim plugin builds)
        export PATH="${MISE_DATA_DIR:-$HOME/.local/share/mise}/shims:$PATH"
        if mise install -y >/dev/null 2>&1; then ok "mise: $(mise ls --current 2>/dev/null | awk '{printf "%s@%s ", $1, $2}')"; else warn "mise install failed — run \`mise install\`"; fi
    fi
    if have atuin && [ ! -f "$HOME/.local/share/atuin/history.db" ]; then
        if atuin import auto >/dev/null 2>&1; then ok "atuin: imported your shell history"; else warn "atuin import failed — run \`atuin import auto\`"; fi
    fi
}

setup_git_identity() {
    # Name/email live in ~/.config/git/local (not committed); ask once on a new machine.
    if git config --get user.email >/dev/null 2>&1; then return 0; fi
    if [ "$IN_CI" -eq 1 ] || [ ! -t 0 ]; then warn "no git identity — add it to ~/.config/git/local"; return 0; fi
    step "git identity (saved to ~/.config/git/local, not committed)"
    local name email
    printf '  Name:  '; read -r name || return 0
    printf '  Email: '; read -r email || return 0
    if [ -n "$name" ] && [ -n "$email" ]; then
        git config -f "$CONFIG_HOME/git/local" user.name "$name"
        git config -f "$CONFIG_HOME/git/local" user.email "$email"
        ok "$name <$email>"
    else
        warn "skipped — add it later to ~/.config/git/local"
    fi
}

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
        install_bash_preexec
        install_claude_code
        setup_tools
        setup_git_identity
        setup_gh
        have zsh && ! grep -qF '.config/shell/aliases.sh' "$HOME/.zshrc" 2>/dev/null && hook_shell   # zsh was just installed
        [ "$NVIM_PLUGINS" -eq 1 ] && install_nvim_plugins
    fi

    step "Done"
    if [ "$UPGRADE" -eq 1 ]; then
        echo "  Upgraded. Neovim and its plugins stayed pinned (see :PluginsRestore)."
        return 0
    fi
    echo "  Open a new terminal (WezTerm). Logins to redo on a new machine:"
    echo "    gh auth login · claude (for \`ai\`) · :Copilot auth in nvim · atuin login (optional)"
    if [ -d "$BACKUP" ]; then echo "  Replaced configs are in $(tilde "$BACKUP")"; fi
    return 0
}

main
