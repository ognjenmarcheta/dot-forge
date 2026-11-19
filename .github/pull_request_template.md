## Summary

-

## Why

-

## Risk

- [ ] Changes what `install.sh` or `dot upgrade` does on an existing machine
- [ ] Touches logins, secrets, `dot-ai`, `dot invite` or `dot try`
- [ ] macOS only / Linux only

## Validation

- [ ] `bash tests/lint.sh`
- [ ] `bash tests/work.sh`, `tests/features.sh`, `tests/hello.sh`, `tests/ports.sh`, `tests/wrapped.sh` (as relevant)
- [ ] `tests/doctor.sh` on a real machine
- [ ] Tried on: macOS / Linux

Manual validation notes:

-
