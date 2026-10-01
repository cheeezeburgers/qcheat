# Development log

## 0.5.0beta — 2026-10-01

Branch: `feature/smarter-grounding`

- Discover Git topics from the installed verbose command index, intersected with
  validated builtins; preserve explicit commands and distinguish working-tree
  restores, untracked cleanup and staged diffs with small contextual vocabulary.
  Keep conservative manual fallback and require builtin proof before fallback
  `-h`, including on older Git installations.
- Discover Vim/Neovim references from installed index/quickref entries and resolve
  literal tags only to core help basenames. Prefer word motions and change
  operators for natural editing questions; preserve exact-tag and topic fallback,
  three-file/excerpt limits, input/output budgets and quiet lookup failure.
- Add 70 offline regression checks for routing, excluded aliases/scripts, index
  failures, safe tag resolution, missing documentation and resource limits.
  Update local-documentation notes and bump the canonical CLI version from
  0.4.1 to 0.5.0beta; preserve README and the separately edited Modelfile.
- Validation: Bash syntax, ShellCheck, the offline suite, `make test`, `make lint`,
  `make check` and whitespace checks passed on macOS with Bash 3.2; all 260 checks
  passed (154 routing/CLI checks and 106 helper checks). Read-only checks against
  installed Git, Vim and Neovim confirmed the important natural-language routes.
- No live installation/uninstallation, network, model inference, release or Git
  history/push action was performed. No Linux-host validation was run locally;
  natural-language selection remains a bounded best-effort heuristic.

## 0.4.1 — 2026-10-01

Branch: `fix/makefile-help`

- Made `help` the default Make goal and documented all targets with `##`
  descriptions. Added installer dry-run, offline tests, ShellCheck, combined
  validation and VHS demo targets; kept existing install/uninstall/release
  delegation and the existing `dev/demo.tape` output path.
- Split the accidental `esacaction=$1` into separate statements, preserving the
  surrounding local argument-validation edits in `dev/release.sh`.
- Bumped the canonical version from 0.4.0 to 0.4.1 and synchronized test
  expectations. Expanded helper checks for Make help, delegation and validation;
  handled macOS Make's leading whitespace in `MAKEFILE_LIST`.
- Validation: `make help`, `make lint`, `make test`, `make check`, Bash syntax,
  ShellCheck and whitespace checks passed on macOS; 190 offline checks passed
  (84 existing checks and 106 helper checks). README remained unchanged.
- No live install/uninstall, tag/push/release or VHS demo was run. Existing
  offline fixtures and non-mutating recipe previews cover those delegates;
  actual demo regeneration and Linux-host validation remain manual.

## 0.4.0 — 2026-10-01

Branch: `feature/makefile`

- Adapted the copied Makefile and `dev/release.sh` for qcheat, retaining
  `./install.sh` as the canonical installer and `bin/qcheat` as the canonical
  version source (0.3.1 → 0.4.0).
- Added scoped uninstall of the command, installed lookup library and custom
  `qwen-cheat` model; shared dependencies, base models and shell rc files remain.
  Missing resources are skipped; model/server errors are reported for retry.
- Kept annotated `v<version>` tags, clean-checkout and remote conflict checks,
  explicit tag-only pushes, GitHub authentication/permission checks and generated
  release notes. Release creation now requires an already-pushed matching tag.
  Added helper help/version output and non-mutating release/uninstall dry-runs.
- Added 88 Bash helper checks with isolated Git/GitHub/Ollama/removal mocks and
  Make recipe previews; integrated them into the existing offline suite and
  Linux/macOS CI syntax checks. All 172 offline checks, Bash syntax, ShellCheck
  and whitespace checks passed locally on macOS. README is unchanged.
- Live installation/uninstallation, tag creation/pushing and GitHub release
  creation were deliberately not exercised; shell aliases/PATH cleanup is manual.
  No Linux-host validation was performed.

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
