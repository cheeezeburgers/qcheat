# Local documentation grounding

Normal questions use a best-effort, read-only documentation lookup before the
existing `ollama run` call. No additional model call, service, downloaded manual,
cache or history is involved. The original question and runtime context are kept.
`mdcat --local -`, model overrides and the CLI options retain their behavior.

## Routing and sources

- Explicit `vim`, `nvim`/`neovim`, `git`, and `gh`/`GitHub CLI` select that tool.
  Conflicting tool names and VS Code questions skip lookup.
- A fixed list of system commands is supported: `cp`, `mv`, `grep`, `find`, `ls`,
  `mkdir`, `rm`, `chmod`, `chown`, `cat`, `head`, `tail`, `sort`, `uniq`, `wc`, `sed`,
  `awk`, and `tar`. Clear copy/move questions about files or directories also
  map to `cp`/`mv`. Unknown or ambiguous questions use the existing Qwen prompt.
- Vim uses `$VIMRUNTIME/doc` when set, otherwise its resolved installation prefix
  and `vim --version` runtime information. Neovim uses the resolved executable's
  `share/nvim/runtime/doc`. Neither editor is started to read configuration or
  execute editor commands. Symlinks are resolved, including Homebrew layouts.
- Editor lookup reads at most three selected help files: `change.txt`,
  `motion.txt`, and one topic file. Exact help tags prioritize common current-word
  and current-line editing questions. Definitions come from installed help text.
- Git selects a built-in topic from a fixed list and reads its manual under the
  installed executable's `git --man-path`. If unavailable, built-in `git <topic>
  -h` usage is used. Configurable Git help viewers, aliases, and external Git
  commands are never dispatched.
- gh uses fixed `gh help` topic arguments, including `gh help pr create` for
  “gh create pull request”. Update notifications, telemetry, prompting and custom
  pagers are disabled for this subprocess. No action or extension is invoked.
- System manuals are located relative to the resolved executable, preserving
  BSD versus GNU installations. `/bin` and `/sbin` use `/usr/share/man`. Manual
  files may be plain text or gzip-compressed. Available `mandoc` renders them
  from stdin; Linux can use `man -l` with its formatted-page cache disabled by
  local-file mode. If unavailable, safe, allowlisted `--help` commands are tried.
  `awk` uses only its manual because its option parsing varies by implementation.

## Bounds and fallback

Search uses the first 2,048 question characters; the full question still reaches
Qwen. Plain-text keyword scoring ranks windows deterministically and removes
terminal formatting. It scores at most 20,000 lines or 1 MiB of source text,
whichever comes first. Up to three excerpts include source labels and context,
with at most 6,000 bytes total and 240 bytes per source line. Excess piped output
is drained so producer exit statuses remain meaningful.

Missing executables, libraries, manuals, renderers, unsupported topics, lookup
errors and unmatched text silently preserve the original Qwen-only prompt. When
excerpts exist, the request tells Qwen that they are authoritative and to state
when they do not support an answer. This is prompt guidance, not a guarantee of
model correctness; there is no second inference or command execution.

All query-derived text stays data. Command names, subcommands and help flags are
allowlisted; questions are never evaluated or sourced. Only qcheat's own library
is sourced, relative to the executable. Retrieval writes no persistent files,
changes no configuration, and never installs anything or elevates permissions.

## Installation and development

`./install.sh` installs the command as before and copies `lib/docs.sh` and
`lib/excerpt.awk` to `~/.local/lib/qcheat/`. Dry-run previews these copies without
creating files. The installed executable locates its library relative to its
resolved path, including when invoked through a symlink or outside the checkout.
For removal, these two qcheat-owned library files can be removed along with the
command; remove their directory when empty.

Run the offline suite with `bash dev/tests/run.sh`. It generates synthetic fixtures
inside a temporary repository directory, mocks Ollama, mdcat and help commands,
tests both installer OS branches, and cleans up on exit. No network, actual model
inference, downloads or changes to the user's shell configuration are required.
`bash dev/tests/run.sh --read-only` runs the subset without fixture creation (older
Bash versions may still need temporary files for the existing help heredocs).
The project uses Bash-native tests; no Bats dependency is required.

Validate syntax with `bash -n` on `bin/qcheat`, `install.sh`, `lib/docs.sh` and
`dev/tests/run.sh`; run ShellCheck on the same files. Both Linux and macOS CI run the
offline suite, including source/install help, versions, argument/stdin prompts,
input safety, documentation bounds, errors, fallback and installer dry-run.

Development notes and session history live in `dev/DEVLOG.md`.

Known limits: natural-language routing and synonym matching are intentionally
small. There is no fuzzy search across all documentation, plugin documentation,
interactive clarification or support for arbitrary gh extensions. Nonstandard
runtime/man layouts (for example some AppImages, wrappers or alternatives
installations) may fall back. Only `.1` and `.1.gz` manuals are located. Very long
lines are shortened; later matches beyond the input budget are not searched.
Help processes are trusted installed programs and have no enforced wall-clock
timeout. No Linux host or actual model inference is required by the local suite;
Linux runtime portability is also exercised in CI.
