# Contributing

This is a personal setup, so changes keep it working on both macOS and
Linux (Ubuntu) and keep logins and per-machine settings out of the repo.

## Working rules

- Start from `main` and work on a focused branch.
- Edit the files in this repo, not copies: configs are symlinked into
  `~/.config`, so editing either edits both.
- Scripts run under macOS `/bin/bash` 3.2 as well as newer bash and zsh.
- Put per-machine values in `config/shell/local.sh`, `config/git/local` or
  `config/wezterm/machine.lua`, never in committed files.

## Branch names

New branches use `KAINE-<issue-number>-<type>-<description>`, or
`KAINE-<type>-<description>` when there is no issue. The type is a
Conventional Commit type (`feat`, `fix`, `docs`, `refactor`, `test`, `ci`,
`chore`, …); type and description are lowercase with hyphens. Automation
branches such as `night/*` and `dependabot/*` keep their own names.

## Checks

Run the tests that cover your change before you open a pull request:

```bash
bash tests/lint.sh
bash tests/work.sh
bash tests/features.sh
bash tests/hello.sh
bash tests/ports.sh
bash tests/wrapped.sh
tests/doctor.sh            # on a machine with the setup installed
```

CI runs all of them plus a fresh install on Linux; `macos.yml` installs on
macOS when the installer or scripts change.

## Pull requests

Pull requests are squash-merged with the PR title as the commit title, so
write the title as the change ("dot upgrade restarts WezTerm's sessions").
Say in the description what changed for someone using the setup and how
you tested it.
