# WezTerm sets ZDOTDIR here; load your own ~/.zshrc, then the shared extras.
[ -f "$HOME/.zshrc" ] && . "$HOME/.zshrc"
[ -f "$HOME/.config/shell/aliases.sh" ] && . "$HOME/.config/shell/aliases.sh"
