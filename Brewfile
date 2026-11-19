# macOS packages for install.sh (brew bundle). This file is Ruby, so GUI apps
# are skipped in CI (`CI=true`), where they'd only slow the run down.

tap "nikitabobko/tap"

# terminal + shell
cask "wezterm" unless ENV["CI"]
cask "font-jetbrains-mono-nerd-font" unless ENV["CI"]   # icons in other terminals / editors (WezTerm has its own)
cask "font-victor-mono-nerd-font" unless ENV["CI"]      # cursive italics in WezTerm
brew "starship"
brew "zoxide"
brew "fzf"
brew "atuin"
brew "coreutils"        # gls: clickable `ls` links
brew "git"
brew "gh"
brew "jq"
brew "mise"             # node / pnpm / python versions (config/mise)
brew "eza"              # ls with icons, git status, clickable entries
brew "bat"              # cat / man pages with syntax highlighting
brew "git-delta"        # nicer git diffs (git + lazygit pager)
brew "tealdeer"         # `tldr tar`: short examples instead of man pages
brew "navi"             # Ctrl+G: saved commands with blanks to fill in
brew "carapace"         # Tab completion for hundreds of CLIs
brew "just"             # per-project task runner (justfile)
brew "fx"               # JSON viewer
brew "xh"               # friendlier curl for APIs
brew "whisper.cpp"      # push-to-talk: speech to text on this machine
brew "sox"              # microphone recording for push-to-talk

# editor + friends
# (Neovim itself is NOT from Homebrew: Homebrew ships 0.12, this config is
#  pinned to 0.11 — install.sh puts Neovim 0.11.6 in ~/.local/bin.)
brew "node"              # Mason language servers, Copilot, mcphub
brew "ripgrep"
brew "fd"
brew "lazygit"
brew "yazi"
brew "ffmpegthumbnailer" # yazi video previews
brew "poppler"           # yazi PDF previews
brew "imagemagick"
brew "sevenzip"

# AI coding agents
brew "opencode"          # OpenCode CLI (used by the opencode.nvim plugin)

# misc CLI
brew "btop"
brew "dust"             # what is using disk space
brew "duf"              # disk usage overview
brew "fastfetch"
brew "thefuck"
brew "vhs"
brew "terminal-notifier" # herdr script notifications
brew "tmux"             # dot invite: the shared pane (viewers attach read-only)
brew "ttyd"             # dot invite: the pane in a browser
brew "cloudflared"      # dot invite: temporary public link (no account needed)
brew "qrencode"         # QR codes in the terminal (dot invite)
brew "caddy"            # dot name: https://NAME.localhost → a local port

# window manager
cask "nikitabobko/tap/aerospace" unless ENV["CI"]
