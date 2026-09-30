#!/usr/bin/env bash
# Offline behavior tests; no Ollama inference, package installs or network.
set -Eeuo pipefail

ROOT="$(cd -- "${BASH_SOURCE[0]%/*}/../.." && pwd -P)"
# shellcheck source=lib/docs.sh
source "$ROOT/lib/docs.sh"
QCHEAT_DOCS_DIR="$ROOT/lib"
checks=0
TEST_HOST_PATH="$PATH"

fail_test() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
equal() {
  [[ "$1" == "$2" ]] || fail_test "$3: expected '$2', got '$1'"
  checks=$((checks + 1))
}
contains() {
  [[ "$1" == *"$2"* ]] || fail_test "$3: missing '$2'"
  checks=$((checks + 1))
}
absent() {
  [[ "$1" != *"$2"* ]] || fail_test "$3: unexpected '$2'"
  checks=$((checks + 1))
}
route() {
  local normalized
  normalized="$(printf '%s' "$1" | qcheat_docs_normalize)"
  qcheat_docs_detect "$normalized" || :
}

equal "$(route 'Vim delete to end of line')" vim 'Vim routing'
equal "$(route 'neovim copy current word')" nvim 'Neovim routing'
equal "$(route 'nvim delete current line')" nvim 'nvim routing'
equal "$(route 'git restore a file')" git 'Git routing'
equal "$(route 'gh create pull request')" gh 'gh routing'
equal "$(route 'GitHub CLI create pull request')" gh 'GitHub CLI routing'
equal "$(route 'copy a directory recursively')" cp 'implicit cp routing'
equal "$(route 'move a file')" mv 'implicit mv routing'
equal "$(route 'grep recursive search')" grep 'generic command routing'
equal "$(route 'find files recursively')" find 'find routing'
equal "$(route 'vscode copy a file')" '' 'unsupported editor'
equal "$(route 'vim versus nvim')" '' 'ambiguous editors'
equal "$(route 'cp or mv a file')" '' 'ambiguous commands'
equal "$(route 'copy this idea')" '' 'unconfident question'
equal "$(route 'explain for loops')" '' 'unknown tool'
equal "$(qcheat_docs_git_topic 'git restore a file')" restore 'Git topic'

excerpt="$(printf 'unrelated documentation\n' | qcheat_docs_excerpt 'restore file' fixture)"
equal "$excerpt" '' 'irrelevant text is discarded'
excerpt="$(printf 'USAGE\n  demo restore FILE\nRestore a file safely.\n' |
  qcheat_docs_excerpt 'restore file' fixture)"
contains "$excerpt" 'Source: fixture' 'source attribution'
contains "$excerpt" 'demo restore FILE' 'usage retained'
# No word interpolation into awk, shell eval, or shell command construction.
# shellcheck disable=SC2016
literal='git restore $(exit 89) `exit 90`; "quotes" \\n --help'
equal "$(route "$literal")" git 'literal shell metacharacters'
excerpt="$(awk 'BEGIN { for (i=0; i<24000; i++) {
  printf "restore file %05d ", i; for (j=0; j<300; j++) printf "x"; print ""
} }' | qcheat_docs_excerpt 'restore file' fixture)"
[[ "${#excerpt}" -le 6000 ]] || fail_test 'excerpt exceeds 6000 bytes'
checks=$((checks + 1))
contains "$excerpt" 'restore file' 'bounded lookup retains relevant text'
equal "$excerpt" "$(awk 'BEGIN { for (i=0; i<24000; i++) {
  printf "restore file %05d ", i; for (j=0; j<300; j++) printf "x"; print ""
} }' | qcheat_docs_excerpt 'restore file' fixture)" 'deterministic ranking'
excerpt="$(printf 'r\bre\bestore file\n\033[31mrestore file\033[0m\n' |
  qcheat_docs_excerpt 'restore file' fixture)"
absent "$excerpt" $'\033' 'ANSI cleanup'
absent "$excerpt" $'\b' 'overstrike cleanup'

for flag in -h --help; do
  contains "$(bash "$ROOT/bin/qcheat" "$flag")" 'Usage:' 'CLI help'
  contains "$(bash "$ROOT/install.sh" "$flag")" 'Usage:' 'installer help'
done
for flag in -V --version; do
  equal "$(bash "$ROOT/bin/qcheat" "$flag")" 'qcheat 0.4.0' 'CLI version'
  equal "$(bash "$ROOT/install.sh" "$flag")" 'qcheat 0.4.0' 'installer version'
done

# A useful subset can be run even in a read-only checkout.
if [[ "${1:-}" == --read-only ]]; then
  printf 'PASS: %s read-only checks (fixture/install tests skipped)\n' "$checks"
  exit 0
fi

# All test-created files stay in the repository; a failing test also cleans up.
WORK="$(mktemp -d "$ROOT/.test-work.XXXXXX")"
trap 'rm -rf -- "$WORK"' EXIT
export TEST_WORK="$WORK"
export TEST_LOG="$WORK/commands.log"
export TEST_PROMPT="$WORK/prompt"
export TEST_OS=Linux
export HOME="$WORK/home with spaces"
export SHELL=/bin/bash
mkdir -p "$WORK/bin" "$HOME" "$WORK/package/bin" \
  "$WORK/package/share/vim/vim92/doc" "$WORK/package/share/nvim/runtime/doc" \
  "$WORK/package/share/man/man1"

# An isolated PATH prevents accidental use of host programs or inference.
# Add only the system utilities needed by qcheat, its installer and this suite.
for name in bash cat tr awk sed dirname basename readlink uname mkdir install grep \
  chmod cp mv rm ln gzip touch; do
  ln -s "$(command -v "$name")" "$WORK/bin/$name"
done
REAL_BASH="$(command -v bash)"
REAL_CP="$(command -v cp)"
REAL_MV="$(command -v mv)"

cat > "$WORK/dispatch" <<'MOCK'
#!/usr/bin/env bash
set -eu
name="${0##*/}"
entry="$name"
for arg in "$@"; do entry="$entry <$arg>"; done
printf '%s\n' "$entry" >> "$TEST_LOG"
case "$name" in
  vim)
    [[ "$*" == --version ]] || exit 70
    printf 'VIM - Vi IMproved 9.2 (fixture)\n'
    ;;
  nvim) exit 71 ;; # Runtime discovery must not launch an editor.
  git)
    case "$*" in
      --man-path) printf '%s/package/share/man\n' "$TEST_WORK" ;;
      '--no-pager restore -h')
        if [[ "${TEST_GIT_HELP_FAIL:-0}" == 1 ]]; then
          printf 'git: restore is not a git command\n'
          exit 1
        fi
        printf 'usage: git restore [--staged] <file>\nrestore a file\n'
        exit 129
        ;;
      *) exit 72 ;;
    esac
    ;;
  gh)
    [[ "${GH_NO_UPDATE_NOTIFIER:-}" == 1 && "${GH_TELEMETRY:-}" == 0 &&
       "${GH_PAGER:-}" == cat && "${GH_PROMPT_DISABLED:-}" == 1 ]] || exit 73
    case "$*" in
      'help pr create')
        printf 'Create a pull request.\nUSAGE\n  gh pr create [flags]\n'
        ;;
      *) printf 'unsupported topic\n'; exit 74 ;;
    esac
    ;;
  cp)
    [[ "$*" == --help ]] || exit 75
    printf 'USAGE\n cp -R SOURCE DEST\nCopy directories recursively.\n'
    ;;
  mandoc)
    [[ "$*" == '-T ascii' ]] || exit 76
    cat
    ;;
  man)
    [[ "$1" == -l && "${MANPAGER:-}" == cat && -z "${MANOPT:-}" ]] || exit 77
    cat "$2"
    ;;
  ollama)
    case "$1" in
      --version) printf 'ollama fixture\n' ;;
      list) exit 0 ;;
      pull|create) exit 0 ;;
      run)
        printf '%s' "$3" > "$TEST_PROMPT"
        printf 'fixture answer\n'
        exit "${TEST_OLLAMA_STATUS:-0}"
        ;;
      *) exit 78 ;;
    esac
    ;;
  mdcat)
    [[ "$*" != --version ]] || { printf 'mdcat fixture\n'; exit 0; }
    [[ "$*" == '--local -' ]] || exit 79
    cat
    exit "${TEST_MDCAT_STATUS:-0}"
    ;;
  brew)
    case "$*" in
      --version) printf 'Homebrew fixture\n' ;;
      --prefix) printf '/opt/homebrew\n' ;;
      *) exit 80 ;;
    esac
    ;;
  uname)
    case "$1" in -s) printf '%s\n' "$TEST_OS" ;; -m) printf 'arm64\n' ;; esac
    ;;
  *) exit 81 ;;
esac
MOCK
chmod +x "$WORK/dispatch"
for name in vim nvim git gh cp mandoc man ollama mdcat brew uname; do
  "$REAL_CP" "$WORK/dispatch" "$WORK/package/bin/$name"
  ln -sf "$WORK/package/bin/$name" "$WORK/bin/$name"
done
export PATH="$WORK/bin"
hash -r

cat > "$WORK/package/share/vim/vim92/doc/change.txt" <<'DOC'
Synthetic fixture: editing commands
                                                        *D*
D       Delete the characters until the end of the line; synonym for "d$".
                                                        *y*
y{motion}       Yank the text covered by the motion.
DOC
cat > "$WORK/package/share/vim/vim92/doc/motion.txt" <<'DOC'
Synthetic fixture: text objects
                                                        *iw*
iw      Select the inner word after an operator, without surrounding spaces.
DOC
"$REAL_CP" "$WORK/package/share/vim/vim92/doc/change.txt" "$WORK/package/share/nvim/runtime/doc/change.txt"
"$REAL_CP" "$WORK/package/share/vim/vim92/doc/motion.txt" "$WORK/package/share/nvim/runtime/doc/motion.txt"
cat > "$WORK/package/share/man/man1/git-restore.1" <<'DOC'
Synthetic fixture: installed Git manual
SYNOPSIS
  git restore [--source=tree] [--staged] -- file
Restore a file from the index.
DOC
cat > "$WORK/package/share/man/man1/cp.1" <<'DOC'
Synthetic fixture: BSD copy manual
SYNOPSIS
  cp -R source target
Copy a directory recursively, including subdirectories.
DOC
unset VIMRUNTIME

contains "$(qcheat_docs_lookup 'vim delete to end of line')" 'synonym for "d$"' 'Vim runtime retrieval'
contains "$(qcheat_docs_lookup 'neovim copy current word')" 'inner word' 'Neovim text object'
contains "$(qcheat_docs_lookup 'neovim copy current word')" 'y{motion}' 'Neovim operator'
contains "$(qcheat_docs_lookup 'git restore a file')" '--source=tree' 'matching Git man path'
contains "$(qcheat_docs_lookup 'gh create pull request')" 'gh pr create [flags]' 'gh built-in help'
contains "$(qcheat_docs_lookup 'copy a directory recursively')" 'BSD copy manual' 'local system manual'
absent "$(cat "$TEST_LOG")" 'nvim <' 'no editor startup'

"$REAL_MV" "$WORK/package/share/man/man1/git-restore.1" "$WORK/git-man-saved"
contains "$(qcheat_docs_lookup 'git restore a file')" 'installed git restore -h' 'Git missing man fallback'
equal "$(TEST_GIT_HELP_FAIL=1 qcheat_docs_lookup 'git restore a file' || :)" '' 'Git errors are not documentation'
"$REAL_MV" "$WORK/git-man-saved" "$WORK/package/share/man/man1/git-restore.1"
gzip "$WORK/package/share/man/man1/git-restore.1"
contains "$(qcheat_docs_lookup 'git restore a file')" '--source=tree' 'compressed Git manual'
gzip -d "$WORK/package/share/man/man1/git-restore.1.gz"

"$REAL_MV" "$WORK/package/share/man/man1/cp.1" "$WORK/cp-man-saved"
contains "$(qcheat_docs_lookup 'copy a directory recursively')" 'installed cp --help' 'command help fallback'
"$REAL_MV" "$WORK/cp-man-saved" "$WORK/package/share/man/man1/cp.1"

rm "$WORK/bin/mandoc"
contains "$(qcheat_docs_lookup 'git restore a file')" '--source=tree' 'Linux local-file man mode'
ln -s "$WORK/package/bin/mandoc" "$WORK/bin/mandoc"
equal "$(qcheat_docs_lookup 'gh pr teleport' || :)" '' 'unsupported gh topic'
equal "$(qcheat_docs_lookup 'vim interplanetary frobnication' || :)" '' 'irrelevant editor docs'
rm "$WORK/bin/vim"
equal "$(qcheat_docs_lookup 'vim delete line' || :)" '' 'missing installed program'
ln -s "$WORK/package/bin/vim" "$WORK/bin/vim"
"$REAL_MV" "$WORK/package/share/vim/vim92/doc" "$WORK/vim-doc-saved"
equal "$(qcheat_docs_lookup 'vim delete line' || :)" '' 'missing runtime docs'
mkdir -p "$WORK/custom runtime/doc"
"$REAL_CP" "$WORK/vim-doc-saved/change.txt" "$WORK/custom runtime/doc/change.txt"
VIMRUNTIME="$WORK/custom runtime"
export VIMRUNTIME
contains "$(qcheat_docs_lookup 'vim delete to end of line')" 'synonym for "d$"' 'explicit VIMRUNTIME with spaces'
unset VIMRUNTIME
"$REAL_MV" "$WORK/vim-doc-saved" "$WORK/package/share/vim/vim92/doc"

equal "$("$REAL_BASH" "$ROOT/bin/qcheat" gh create pull request)" 'fixture answer' 'normal CLI output'
prompt="$(cat "$TEST_PROMPT")"
contains "$prompt" 'User question: gh create pull request' 'original question retained'
contains "$prompt" 'OS=Linux, shell=bash, architecture=arm64' 'runtime context retained'
contains "$prompt" 'authoritative reference' 'grounding instruction'
contains "$prompt" 'say so instead of inventing' 'unsupported answer instruction'
equal "$(printf 'neovim copy current word\n' | "$REAL_BASH" "$ROOT/bin/qcheat")" 'fixture answer' 'stdin input'
contains "$(cat "$TEST_PROMPT")" 'inner word' 'stdin grounding'
equal "$("$REAL_BASH" "$ROOT/bin/qcheat" explain for loops)" 'fixture answer' 'Qwen fallback'
equal "$(cat "$TEST_PROMPT")" 'Runtime context: OS=Linux, shell=bash, architecture=arm64.

User question: explain for loops' 'fallback prompt unchanged'
if printf ' \n' | "$REAL_BASH" "$ROOT/bin/qcheat" > /dev/null 2>&1; then
  fail_test 'empty question accepted'
fi
checks=$((checks + 1))
# Deliberately literal payloads must survive into the model prompt untouched.
# shellcheck disable=SC2016
payload='git restore $(touch "$TEST_WORK/executed") `touch "$TEST_WORK/executed"`; touch "$TEST_WORK/executed"'
"$REAL_BASH" "$ROOT/bin/qcheat" "$payload" > /dev/null
contains "$(cat "$TEST_PROMPT")" "$payload" 'literal malicious question preserved'
[[ ! -e "$WORK/executed" ]] || fail_test 'question was executed'
checks=$((checks + 1))
QCHEAT_MODEL=custom-model "$REAL_BASH" "$ROOT/bin/qcheat" explain loops > /dev/null
contains "$(cat "$TEST_LOG")" 'ollama <run> <custom-model>' 'model override'
if TEST_OLLAMA_STATUS=9 "$REAL_BASH" "$ROOT/bin/qcheat" explain loops > /dev/null; then
  fail_test 'Ollama failure swallowed'
fi
if TEST_MDCAT_STATUS=8 "$REAL_BASH" "$ROOT/bin/qcheat" explain loops > /dev/null; then
  fail_test 'renderer failure swallowed'
fi
checks=$((checks + 2))

# Installer fixture tests exercise both OS branches, accepted dry-run prompts,
# real copies of qcheat-owned files, shell PATH/alias handling and repeat installs.
for TEST_OS in Linux Darwin; do
  export TEST_OS
  : > "$TEST_LOG"
  dry="$(printf 'y\ny\n' | "$REAL_BASH" "$ROOT/install.sh" --dry-run)"
  contains "$dry" 'No installation changes were made.' 'dry-run completion'
  contains "$dry" '/.local/lib/qcheat' 'library dry-run'
  [[ ! -e "$HOME/.local" && ! -e "$HOME/.bashrc" ]] || fail_test 'dry-run created files'
  absent "$(cat "$TEST_LOG")" 'ollama <pull>' 'dry-run model download'
  absent "$(cat "$TEST_LOG")" 'ollama <create>' 'dry-run model build'
  checks=$((checks + 1))
done
printf 'y\ny\n' | "$REAL_BASH" "$ROOT/install.sh" > "$WORK/install-output"
[[ -x "$HOME/.local/bin/qcheat" && -r "$HOME/.local/lib/qcheat/docs.sh" &&
   -r "$HOME/.local/lib/qcheat/excerpt.awk" ]] || fail_test 'installed files missing'
checks=$((checks + 1))
contains "$(cat "$HOME/.bashrc")" "alias q='qcheat'" 'optional q alias'
contains "$(cat "$HOME/.bashrc")" 'export PATH=' 'PATH update'
equal "$(cd / && "$HOME/.local/bin/qcheat" gh create pull request)" 'fixture answer' 'installed command outside checkout'
contains "$(cat "$TEST_PROMPT")" 'gh pr create [flags]' 'installed library grounding'
ln -s "$HOME/.local/bin/qcheat" "$WORK/bin/linked-qcheat"
equal "$(linked-qcheat gh create pull request)" 'fixture answer' 'symlinked installed command'
printf 'y\nn\n' | "$REAL_BASH" "$ROOT/install.sh" > "$WORK/reinstall-output"
equal "$(grep -c 'export PATH=' "$HOME/.bashrc")" 1 'repeat install preserves PATH block'
equal "$("$HOME/.local/bin/qcheat" --version)" 'qcheat 0.4.0' 'installed version'
rm "$HOME/.local/lib/qcheat/docs.sh"
equal "$("$HOME/.local/bin/qcheat" explain loops)" 'fixture answer' 'missing library fallback'
printf 'PASS: %s checks\n' "$checks"

# Restore the host utilities for the helper suite's own isolated mocks.
PATH="$TEST_HOST_PATH" "$REAL_BASH" "$ROOT/dev/tests/helpers.sh"
