#!/usr/bin/env bash
# Dotfiles installer — macOS and Linux (Ubuntu/Debian).
#
#   ~/Github/dotfiles/install.sh
#
# Options:
#   --links-only   only link configs + hook the shell (no package installs)
#   --no-nvim      skip installing Neovim plugins
#   --upgrade      also upgrade the installed tools (what `dot upgrade` runs);
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
WHISPER_VERSION="v1.9.5"           # push-to-talk speech-to-text (whisper.cpp, local)
WHISPER_MODEL_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin"
ZSH_PLUGINS="zsh-users/zsh-autosuggestions@v0.7.1 zsh-users/zsh-syntax-highlighting@0.8.0 Aloxaf/fzf-tab@v1.3.0"
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
        *) mv "$file" "$dir/$name"; chmod +x "$dir/$name" ;;   # a bare binary (tealdeer, fx)
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
    # a fresh shell may not have brew on PATH yet even though it's installed
    load_brew() {
        if [ -x /opt/homebrew/bin/brew ]; then eval "$(/opt/homebrew/bin/brew shellenv)"
        elif [ -x /usr/local/bin/brew ]; then eval "$(/usr/local/bin/brew shellenv)"; fi
    }
    have brew || load_brew
    if ! have brew; then
        warn "Homebrew not found — installing it (official installer)"
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        load_brew
    fi
    if [ "$UPGRADE" -eq 1 ]; then brew update && brew upgrade || warn "brew upgrade had problems"; fi
    # Homebrew 7 refuses casks/formulae from third-party taps until they're trusted
    # (AeroSpace: "Refusing to load cask … from untrusted tap")
    if brew trust --help >/dev/null 2>&1; then
        local tap
        for tap in $(sed -n 's/^tap "\([^"]*\)".*/\1/p' "$DOTFILES/Brewfile"); do
            brew trust --tap "$tap" >/dev/null 2>&1 || warn "could not trust tap $tap"
        done
    fi
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
        wl-clipboard libnotify-bin duf gnupg tmux ttyd qrencode
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
    install_release_bin tldr     dbrgn/tealdeer     "tealdeer-linux-${a}-musl$"
    install_release_bin navi     denisidoro/navi    "navi-v.*-${a}-unknown-linux-$([ "$a" = x86_64 ] && echo musl || echo gnu)\.tar\.gz$"
    install_release_bin carapace carapace-sh/carapace-bin "carapace-bin_.*_linux_${go_arch}\.tar\.gz$"
    install_release_bin just     casey/just         "just-.*-${a}-unknown-linux-musl\.tar\.gz$"
    install_release_bin fx       antonmedv/fx       "fx_linux_${go_arch}$"
    install_release_bin xh       ducaale/xh         "xh-v.*-${a}-unknown-linux-musl\.tar\.gz$"
    install_release_bin cloudflared cloudflare/cloudflared "cloudflared-linux-${go_arch}$"   # dot invite links

    step "WezTerm (official apt repository)"
    # The regular build, not the Flatpak: its background session server keeps
    # your tabs alive when the window closes (the Flatpak sandbox can't).
    if [ -f "$BIN/wezterm" ] && grep -q "org.wezfurlong.wezterm" "$BIN/wezterm" 2>/dev/null; then
        rm -f "$BIN/wezterm"; hash -r   # old Flatpak wrapper would hide the real one
    fi
    if dpkg -s wezterm >/dev/null 2>&1 || dpkg -s wezterm-nightly >/dev/null 2>&1; then
        if [ "$UPGRADE" -eq 1 ]; then
            sudo DEBIAN_FRONTEND=noninteractive apt-get $APT_OPTS install --only-upgrade -y wezterm >/dev/null 2>&1 || true
        fi
        ok "$(wezterm --version 2>/dev/null)"
    else
        if [ ! -f /etc/apt/sources.list.d/wezterm.list ]; then
            # https://wezterm.org/install/linux.html
            curl -fsSL https://apt.fury.io/wez/gpg.key | sudo gpg --yes --dearmor -o /usr/share/keyrings/wezterm-fury.gpg
            echo 'deb [signed-by=/usr/share/keyrings/wezterm-fury.gpg] https://apt.fury.io/wez/ * *' \
                | sudo tee /etc/apt/sources.list.d/wezterm.list >/dev/null
            sudo chmod 644 /usr/share/keyrings/wezterm-fury.gpg
            sudo apt-get $APT_OPTS update -qq
        fi
        if sudo DEBIAN_FRONTEND=noninteractive apt-get $APT_OPTS install -y wezterm >/dev/null; then
            hash -r; ok "$(wezterm --version 2>/dev/null) installed"
        else
            warn "WezTerm install failed — see https://wezterm.org/install/linux.html"
        fi
    fi
    wezterm_desktop_entry
    if have flatpak && flatpak info org.wezfurlong.wezterm >/dev/null 2>&1; then
        warn "the WezTerm Flatpak is still installed — open the regular WezTerm from now on;"
        warn "  remove the Flatpak when happy: flatpak uninstall org.wezfurlong.wezterm"
    fi
}

wezterm_desktop_entry() {
    # The app launcher runs `wezterm start`, which never attaches to the session
    # server; our copy of the launcher entry runs `wezterm connect unix` instead.
    # (Turned off by persistent_sessions = false in ~/.config/wezterm/machine.lua.)
    local sys=/usr/share/applications/org.wezfurlong.wezterm.desktop
    local mine="$HOME/.local/share/applications/org.wezfurlong.wezterm.desktop"
    if grep -qs 'persistent_sessions *= *false' "$CONFIG_HOME/wezterm/machine.lua"; then
        if grep -qs 'connect unix' "$mine"; then rm -f "$mine"; ok "launcher: plain WezTerm (sessions off)"; fi
        return 0
    fi
    [ -f "$sys" ] || return 0
    mkdir -p "$(dirname "$mine")"
    sed -E 's|^Exec=wezterm start.*|Exec=wezterm connect unix|' "$sys" > "$mine"
    ok "launcher opens your saved session (wezterm connect unix)"
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

install_zsh_plugins() {
    have zsh || return 0
    step "zsh plugins (autosuggestions, syntax highlighting, fzf-tab)"
    local dir="$HOME/.local/share/zsh-plugins" spec repo tag name
    mkdir -p "$dir"
    for spec in $ZSH_PLUGINS; do
        repo="${spec%@*}"; tag="${spec#*@}"; name="${repo#*/}"
        if [ "$(git -C "$dir/$name" describe --tags --exact-match 2>/dev/null)" = "$tag" ]; then
            ok "$name $tag"; continue
        fi
        rm -rf "${dir:?}/$name"
        if git clone -q --depth 1 --branch "$tag" "https://github.com/$repo.git" "$dir/$name" 2>/dev/null; then
            ok "$name $tag"
        else
            warn "$name download failed"
        fi
    done
}

install_whisper() {
    # Push-to-talk (Alt+V): speech -> text on this machine; nothing is uploaded
    step "Push-to-talk: whisper.cpp $WHISPER_VERSION + speech model (local)"
    if [ "$OS" = Darwin ]; then
        if have whisper-cli; then ok "whisper-cli (Homebrew)"; else warn "whisper-cpp missing — brew bundle"; fi
    else
        local src="$OPT/whisper.cpp" stamp="$OPT/whisper.cpp.version"
        if have whisper-cli && [ "$(cat "$stamp" 2>/dev/null)" = "$WHISPER_VERSION" ]; then
            ok "whisper-cli $WHISPER_VERSION"
        else
            have cmake || apt_install cmake
            [ "$IN_CI" -eq 1 ] || apt_install pipewire-bin      # pw-record (microphone)
            rm -rf "$src"
            mkdir -p "$OPT"
            if git clone -q --depth 1 --branch "$WHISPER_VERSION" https://github.com/ggml-org/whisper.cpp.git "$src" 2>/dev/null \
                && cmake -S "$src" -B "$src/build" -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF \
                    -DWHISPER_BUILD_TESTS=OFF -DWHISPER_BUILD_SERVER=OFF >/dev/null \
                && cmake --build "$src/build" -j "$(nproc 2>/dev/null || echo 4)" --target whisper-cli >/dev/null \
                && install -m 755 "$src/build/bin/whisper-cli" "$BIN/whisper-cli"; then
                echo "$WHISPER_VERSION" > "$stamp"
                hash -r; ok "whisper-cli $WHISPER_VERSION built"
            else
                warn "whisper.cpp build failed — push-to-talk won't work (re-run install.sh)"
            fi
        fi
    fi
    local model="$HOME/.local/share/whisper/ggml-base.bin"
    if [ -s "$model" ]; then
        ok "speech model $(tilde "$model")"
    elif [ "$IN_CI" -eq 1 ]; then
        ok "speech model download skipped in CI"
    else
        mkdir -p "$(dirname "$model")"
        echo "  downloading the speech model (~148 MB, once)…"
        if curl -fL --progress-bar -o "$model.part" "$WHISPER_MODEL_URL" && mv "$model.part" "$model"; then
            ok "speech model $(tilde "$model")"
        else
            rm -f "$model.part"; warn "speech model download failed — re-run install.sh"
        fi
    fi
}

login_shell() {
    if [ "$OS" = Darwin ]; then
        dscl . -read "$HOME" UserShell 2>/dev/null | awk '{print $2}'
    else
        getent passwd "$(id -un)" 2>/dev/null | cut -d: -f7
    fi
}

setup_default_shell() {
    have zsh || return 0
    local zsh_path ans
    zsh_path="$(command -v zsh)"
    case "$(login_shell)" in */zsh) return 0 ;; esac
    [ "$IN_CI" -eq 1 ] && return 0
    step "Default shell"
    if [ ! -t 0 ]; then warn "make zsh your default shell with: chsh -s $zsh_path"; return 0; fi
    printf '  Make zsh your default shell (suggestions as you type, highlighting)? [Y/n] '
    read -r ans || ans=n
    case "$ans" in
        n|N|no|No) ok "keeping $(basename "$(login_shell)")" ;;
        *)
            grep -qx "$zsh_path" /etc/shells 2>/dev/null || echo "$zsh_path" | sudo tee -a /etc/shells >/dev/null
            if chsh -s "$zsh_path"; then
                ok "zsh is your login shell from your next login (WezTerm uses it right away)"
            else
                warn "chsh failed — run: chsh -s $zsh_path"
            fi
            ;;
    esac
}

setup_tools() {
    step "Tool setup"
    if have mise; then
        if [ "$UPGRADE" -eq 1 ]; then mise upgrade -y >/dev/null 2>&1 || true; fi
        # shims put node etc. on PATH for the rest of this run (Neovim plugin builds)
        export PATH="${MISE_DATA_DIR:-$HOME/.local/share/mise}/shims:$PATH"
        if mise install -y >/dev/null 2>&1; then ok "mise: $(mise ls --current 2>/dev/null | awk '{printf "%s@%s ", $1, $2}')"; else warn "mise install failed — run \`mise install\`"; fi
    fi
    if have tldr; then
        if tldr --update >/dev/null 2>&1; then ok "tldr: pages downloaded"; else warn "tldr pages not downloaded — run \`tldr --update\`"; fi
    fi
    if have atuin && [ ! -f "$HOME/.local/share/atuin/history.db" ]; then
        if atuin import auto >/dev/null 2>&1; then ok "atuin: imported your shell history"; else warn "atuin import failed — run \`atuin import auto\`"; fi
    fi
}

setup_claude_hooks() {
    # Claude Code tells WezTerm when it waits for you / finishes (tab ● + toast).
    # Merged into ~/.claude/settings.json; your other settings stay untouched.
    have jq || { warn "jq missing — skipped Claude Code alert hooks"; return 0; }
    step "Claude Code alerts (hooks in ~/.claude/settings.json)"
    local f="$HOME/.claude/settings.json" tmp cmd='$HOME/.config/scripts/agent-notify'
    mkdir -p "$HOME/.claude"
    [ -s "$f" ] || echo '{}' > "$f"
    tmp="$(mktemp)"
    if ! jq --arg c "$cmd" '
        def ours: (.command // "") | test("agent-notify");
        def without_ours: map(.hooks |= map(select(ours | not))) | map(select(.hooks | length > 0));
        def add($state): without_ours + [{hooks: [{type: "command", command: ($c + " " + $state)}]}];
        .hooks = (.hooks // {})
        | .hooks.Notification = ((.hooks.Notification // []) | add("waiting"))
        | .hooks.Stop = ((.hooks.Stop // []) | add("done"))
        | .hooks.UserPromptSubmit = ((.hooks.UserPromptSubmit // []) | add("working"))
    ' "$f" > "$tmp"; then
        rm -f "$tmp"; warn "$(tilde "$f") isn't valid JSON — skipped"; return 0
    fi
    if cmp -s "$tmp" "$f"; then
        rm -f "$tmp"; ok "already set up"
    else
        cp "$f" "$f.dotfiles-bak"
        cat "$tmp" > "$f" && rm -f "$tmp"
        ok "Notification / Stop / UserPromptSubmit -> agent-notify (old file: settings.json.dotfiles-bak)"
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
    local lock="$CONFIG_HOME/nvim/lazy-lock.json" saved
    saved="$(mktemp)"
    cp "$lock" "$saved"
    nvim --headless "+Lazy! restore" +qa >/dev/null 2>&1 || true
    if ! cmp -s "$saved" "$lock"; then
        # A fresh install of all plugins at once can leave one on another
        # commit (seen with LuaSnip on macOS) and rewrite the lockfile. Put the
        # lockfile back and restore again.
        cp "$saved" "$lock"
        nvim --headless "+Lazy! restore" +qa >/dev/null 2>&1 || true
    fi
    if cmp -s "$saved" "$lock"; then
        ok "done — open nvim once; Mason then installs the language servers"
    else
        cp "$saved" "$lock"
        warn "some plugins are not on their lazy-lock.json commits — open nvim and run :PluginsRestore"
    fi
    rm -f "$saved"
}

setup_night_shift() {
    # dot night: run queued Claude Code tasks at 01:30 (systemd user timer on
    # Linux, launchd on macOS). Runs nothing when the queue is empty.
    [ "$IN_CI" -eq 1 ] && return 0
    step "Night shift scheduler (dot night, 01:30)"
    local path_line="$BIN:$HOME/.local/share/mise/shims:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
    if [ "$OS" = Darwin ]; then
        local plist="$HOME/Library/LaunchAgents/software.byteforge.dot-night.plist"
        mkdir -p "$(dirname "$plist")" "$HOME/.local/share/dotfiles/night"
        cat > "$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>software.byteforge.dot-night</string>
  <key>ProgramArguments</key><array><string>$HOME/.config/scripts/dot</string><string>night</string><string>run</string></array>
  <key>EnvironmentVariables</key><dict><key>PATH</key><string>$path_line</string></dict>
  <key>StartCalendarInterval</key><dict><key>Hour</key><integer>1</integer><key>Minute</key><integer>30</integer></dict>
  <key>StandardOutPath</key><string>$HOME/.local/share/dotfiles/night/run.log</string>
  <key>StandardErrorPath</key><string>$HOME/.local/share/dotfiles/night/run.log</string>
</dict></plist>
EOF
        launchctl unload "$plist" 2>/dev/null || true
        launchctl load "$plist" 2>/dev/null && ok "launchd job loaded" || warn "launchctl load failed — log out and in"
        return 0
    fi
    have systemctl || { warn "no systemd — run dot night run yourself (or from cron)"; return 0; }
    local d="$HOME/.config/systemd/user"
    mkdir -p "$d"
    cat > "$d/dot-night.service" <<EOF
[Unit]
Description=dot night: queued Claude Code tasks

[Service]
Type=oneshot
Environment=PATH=$path_line
ExecStart=$HOME/.config/scripts/dot night run
TimeoutStartSec=12h
EOF
    cat > "$d/dot-night.timer" <<'EOF'
[Unit]
Description=dot night at 01:30

[Timer]
OnCalendar=*-*-* 01:30:00
Persistent=false

[Install]
WantedBy=timers.target
EOF
    if systemctl --user daemon-reload 2>/dev/null && systemctl --user enable --now dot-night.timer >/dev/null 2>&1; then
        ok "dot-night.timer on (systemctl --user list-timers)"
    else
        warn "couldn't enable the timer — systemctl --user enable --now dot-night.timer"
    fi
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
        install_zsh_plugins
        install_whisper
        install_claude_code
        setup_tools
        setup_claude_hooks
        setup_night_shift
        setup_git_identity
        setup_default_shell
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
