# dotfiles

Terminal setup for macOS and Linux (Ubuntu): WezTerm, Starship prompt, Neovim
(EcoVim v5), zoxide, fzf, atuin, eza, bat, delta, mise, yazi, lazygit, btop,
herdr scripts, OpenCode / agent skills, and the `ai` command.

Day to day: `dot update` (pull + upgrade tools; Neovim plugins stay pinned),
`dot save "msg"` (commit + push your config edits), `dot doctor`, `dot keys`.

## New machine

The repo is private, so log in to GitHub first.

**macOS**
```bash
xcode-select --install                     # git + compilers (wait for it to finish)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
eval "$(/opt/homebrew/bin/brew shellenv)" && brew install gh
gh auth login
gh repo clone ognjenmarcheta/dotfiles ~/Github/dotfiles
~/Github/dotfiles/install.sh
```

**Linux (Ubuntu/Debian)**
```bash
sudo apt install -y git gh
gh auth login
gh repo clone ognjenmarcheta/dotfiles ~/Github/dotfiles
~/Github/dotfiles/install.sh
```

Then open a new WezTerm window and redo the logins that are deliberately not
stored here: `claude` (for `ai`), `:Copilot auth` in Neovim, and `atuin login`
if you use sync.

On a new machine the installer also asks for your git name and email (saved in
`~/.config/git/local`, not committed).

`install.sh --links-only` skips package installs and only links configs;
`--upgrade` also upgrades the tools (that's what `dot update` runs).
Running it again is safe: anything it replaces goes to `~/.dotfiles-backup/<time>/`.

## How it works

| Repo                | Becomes                                   |
| ------------------- | ----------------------------------------- |
| `config/<name>`     | `~/.config/<name>` (symlink)              |
| `macos/<name>`      | `~/.config/<name>` on macOS only          |
| `config/shell/aliases.sh` | sourced from `~/.bashrc` / `~/.zshrc` |
| `config/shell/local.sh`   | per-machine extras, sourced last (not committed) |
| `config/git/local`        | git identity / per-machine git (not committed)   |

Because configs are symlinks, editing `~/.config/wezterm/config.lua` edits this
repo — commit and push to keep machines in sync.

Packages: Homebrew (`Brewfile`) on macOS; apt + official GitHub releases into
`~/.local/bin` on Linux. On both, Neovim is pinned to **0.11.6** (official
release in `~/.local/opt`, linked from `~/.local/bin/nvim`) because the plugin
versions in `config/nvim/lazy-lock.json` are tested with it — Homebrew's and
newer distros' Neovim 0.12 break avante and rainbow-delimiters.

## What you get

`dot keys` prints the full cheat sheet.

- **WezTerm**: Alt+q leader (tmux-style tabs/splits), clickable links, title bar
  you can drag on Linux, Ctrl+click links inside nvim/lazygit. Ctrl+h/j/k/l
  moves between WezTerm panes *and* Neovim splits (Alt+h/j/k/l resizes);
  Leader w / W = switch / new workspace. A toast pops up when a command that
  ran 30s+ finishes while you're in another window (`DOT_NOTIFY_AFTER=0` = off).
- **Prompt**: Starship with clickable user / path segments / git branch; `↑` = `cd ..`.
- **Shell**: `ls`/`ll` via eza (icons, git status, clickable), `cat`/`man` via bat,
  `z` + Tab menu of frequent folders, Ctrl+R = atuin history, Ctrl+T / Alt+C =
  fzf file / folder, `rgf <text>` = search and open the hit in nvim, `y` = yazi.
- **`ai`**: `ai <request>` → a shell command from Claude Code (asks before
  running), `ai explain <cmd>`, `ai fix` (after a command failed).
- **git**: delta diffs (also in lazygit), zdiff3 conflicts, rerere, `git lg`,
  `git recent`, `git undo`.
- **mise**: node LTS, pnpm, uv globally; projects' `.nvmrc` / `mise.toml` win.
- **Neovim**: EcoVim v5 with pinned plugins. Mouse off, plain arrows move,
  multi-cursor on Alt+↑/↓. If plugins drift, Neovim warns — run `:PluginsRestore`.
  Avoid Lazy *Update*/*Sync*.

## CI

`.github/workflows/ci.yml` lints everything, installs from scratch into an empty
home folder, runs `tests/doctor.sh --nvim`, then checks a second run changes
nothing. It uses the self-hosted runner on the workstation (`kaine-ci-linux`,
like kaine-forge and ordina-forge) and falls back to GitHub's runners when that
is down. `macos.yml` does the same on macOS with `/bin/bash` 3.2, only when the
installer changes (macOS minutes are expensive).

## Not in this repo (on purpose)

Logins and tokens (`gh/hosts.yml`, Copilot, OpenCode `service.json`, container
registry auth), SSH keys, `~/.gitconfig`, and the contents of `~/.agents/skills`.
