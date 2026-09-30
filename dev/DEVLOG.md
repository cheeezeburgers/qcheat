# Development log

## 0.3.1 — 2026-09-30

Branch: `fix/dev-test-paths`

- Adjusted the relocated `dev/tests/run.sh` to find the repository root two
  levels above its directory; updated both platform CI jobs and development
  documentation to use the new test path and log location.
- Bumped the canonical CLI version from 0.3.0 to 0.3.1 and synchronized test
  expectations; the installer still reads the version from the CLI.
- Reviewed the Modelfile without changing it. Recommended explicit precedence
  for supplied local documentation over examples and built-in knowledge, an
  insufficient-documentation rule, and explicit Neovim scope.
- Validation: all 84 offline checks, Bash syntax, ShellCheck and whitespace
  checks passed locally on macOS; no model inference or Linux-host run.

## 0.3.0 — 2026-09-30

Branch: `feature/local-official-doc-grounding`

- Added deterministic local documentation routing and bounded excerpts for Vim,
  Neovim, Git, gh and allowlisted system commands, with the original Qwen-only
  prompt as the quiet fallback. Retained Ollama, model selection and mdcat output.
- Installed the separate Bash/AWK lookup library under `~/.local/lib/qcheat`,
  preserved installer dry-run and shell prompts, and made the CLI version the
  installer's canonical version source (0.2.0 → 0.3.0).
- Added offline Bash fixture tests and Linux/macOS CI coverage, including input
  safety, runtime discovery, help/manual failures, installed paths and dry-run.
- Documented routing, bounds, installation and limitations in
  `docs/local-documentation.md`; kept the existing README unchanged as required.
- Validated Bash syntax, ShellCheck, the offline suite, and read-only retrieval
  against installed macOS tools. No actual Ollama inference or Linux-host run;
  unusual installation layouts and unmatched topics deliberately fall back.

## 0.2.0 — 2026-09-24

Branch: `feature/install-dry-run`

- Added installer `--dry-run`, help, version output, and rejection of unknown arguments before installation begins.
- Preview dependency installation, service startup, model operations, command installation, and optional shell configuration changes without performing them.
- Retained read-only checks and interactive PATH/alias prompts; defer Linux package metadata queries during dry-run to avoid cache/log writes.
- Skip post-install dependency checks in dry-run and let declining the optional alias finish successfully.
- Updated README and synchronized installer/command versions from 0.1.0 to 0.2.0.
- No installer execution, syntax checks, linters, or tests were run, as requested. Runtime behavior remains unverified.
