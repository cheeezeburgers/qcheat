# Development log

## 0.2.0 — 2026-09-24

Branch: `feature/install-dry-run`

- Added installer `--dry-run`, help, version output, and rejection of unknown arguments before installation begins.
- Preview dependency installation, service startup, model operations, command installation, and optional shell configuration changes without performing them.
- Retained read-only checks and interactive PATH/alias prompts; defer Linux package metadata queries during dry-run to avoid cache/log writes.
- Skip post-install dependency checks in dry-run and let declining the optional alias finish successfully.
- Updated README and synchronized installer/command versions from 0.1.0 to 0.2.0.
- No installer execution, syntax checks, linters, or tests were run, as requested. Runtime behavior remains unverified.
