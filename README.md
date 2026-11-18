# dotfiles

Terminal setup for macOS and Linux (Ubuntu): WezTerm, Starship prompt, Neovim
(EcoVim v5), zoxide, fzf, yazi, lazygit, btop, atuin, herdr scripts, OpenCode /
agent skills, and the `ai` command.

## New machine

```bash
git clone https://github.com/ognjenmarcheta/dotfiles.git ~/Github/dotfiles
~/Github/dotfiles/install.sh
```

Then open a new WezTerm window and redo the logins that are deliberately not
stored here: `gh auth login`, `claude` (for `ai`), `:Copilot auth` in Neovim,
and `atuin login` if you use sync.

`install.sh --links-only` skips package installs and only links configs.
Running it again is safe: anything it replaces goes to `~/.dotfiles-backup/<time>/`.

## How it works

| Repo                | Becomes                                   |
| ------------------- | ----------------------------------------- |
| `config/<name>`     | `~/.config/<name>` (symlink)              |
| `macos/<name>`      | `~/.config/<name>` on macOS only          |
| `config/shell/aliases.sh` | sourced from `~/.bashrc` / `~/.zshrc` |

Because configs are symlinks, editing `~/.config/wezterm/config.lua` edits this
repo — commit and push to keep machines in sync.

Packages: Homebrew (`Brewfile`) on macOS; apt + official GitHub releases into
`~/.local/bin` on Linux. Neovim is kept on 0.11.x, which this config is tested with.

## What you get

- **WezTerm**: Alt+q leader (tmux-style tabs/splits), clickable links, title bar
  you can drag on Linux, Ctrl+click links inside nvim/lazygit.
- **Prompt**: Starship with clickable user / path segments / git branch; `↑` = `cd ..`.
- **Shell**: clickable `ls`/`ll`, `z` + Tab menu of frequent folders, `y` = yazi,
  `ai <request>` = shell command from Claude Code, daily Node/pnpm update notice.
- **Neovim**: EcoVim v5 with pinned plugins. Mouse off, plain arrows move,
  multi-cursor on Alt+↑/↓. If plugins drift, Neovim warns — run `:PluginsRestore`.
  Avoid Lazy *Update*/*Sync*.

## Not in this repo (on purpose)

Logins and tokens (`gh/hosts.yml`, Copilot, OpenCode `service.json`, container
registry auth), SSH keys, `~/.gitconfig`, and the contents of `~/.agents/skills`.
