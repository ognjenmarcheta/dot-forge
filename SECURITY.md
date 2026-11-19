# Security Policy

## Reporting a vulnerability

Do not open an issue with exploit details. Email `contact@byteforge.software`
with `SECURITY` in the subject and include:

- the affected script or config (for example `config/scripts/dot-try`)
- what an attacker can do
- steps to reproduce
- a suggested fix, if you have one

Expect a first reply within 3 business days.

## What counts

- Scripts that run with your login or on other machines: `install.sh`,
  `dot upgrade`, `dot invite` (ttyd), `dot try` (Docker sandbox), the night
  shift (systemd / launchd), and agent hooks.
- Anything that could leak a secret into the repo, a log, a shared screen
  (share mode) or a prompt sent to an AI tool.
- `dot-ai` accepting a login other than the Claude subscription login.

## Rules this repo keeps

- Logins, tokens and SSH keys are never committed. `.gitignore` lists the
  files tools write them to; per-machine settings live in files that are not
  committed (`config/git/local`, `config/shell/local.sh`,
  `config/wezterm/machine.lua`).
- Every AI feature goes through `config/scripts/dot-ai`, which removes
  API-key variables and refuses to run on any other login (`dot-ai --check`).
- Shell history sent to an AI tool has secrets filtered out first.
- `dot invite` serves only on a random secret path; `dot try` runs as a
  non-root user without capabilities or the Docker socket. CI checks both
  for real.
- If a secret is ever committed, rotate it at once; removing the commit is
  not enough.
