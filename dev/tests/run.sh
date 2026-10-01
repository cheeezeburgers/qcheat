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
[[ "$(printf '%s\n' "$excerpt" | awk '/^\[Source:/ { n++ } END { print n+0 }')" -le 3 ]] ||
  fail_test 'excerpt count exceeds three'
checks=$((checks + 1))
equal "$(awk 'BEGIN { for (i=0; i<20000; i++) print "unrelated";
  print "restore file LINE_BUDGET_SENTINEL" }' |
  qcheat_docs_excerpt 'restore file' fixture)" '' 'source line budget'
equal "$(awk 'BEGIN { for (i=0; i<5000; i++) {
  for (j=0; j<220; j++) printf "x"; print ""
} print "restore file BYTE_BUDGET_SENTINEL" }' |
  qcheat_docs_excerpt 'restore file' fixture)" '' 'source byte budget'
long_line="$(awk 'BEGIN { printf "restore file "; for (i=0; i<1000; i++) printf "x";
  print " LINE_TRUNCATION_SENTINEL" }' | qcheat_docs_excerpt 'restore file' fixture)"
contains "$long_line" '[truncated]' 'long source lines shortened'
absent "$long_line" 'LINE_TRUNCATION_SENTINEL' 'long source lines do not leak suffix'
[[ "$(printf '%s\n' "$long_line" | awk '!/^\[Source:/ { if (length > n) n=length }
  END { print n+0 }')" -le 240 ]] || fail_test 'source line exceeds 240 bytes'
checks=$((checks + 1))
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
  equal "$(bash "$ROOT/bin/qcheat" "$flag")" 'qcheat 0.5.0beta' 'CLI version'
  equal "$(bash "$ROOT/install.sh" "$flag")" 'qcheat 0.5.0beta' 'installer version'
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
      --list-cmds=builtins)
        [[ "${TEST_GIT_INDEX:-valid}" != builtin-error ]] || exit 1
        if [[ "${TEST_GIT_INDEX:-valid}" == no-restore ]]; then
          printf 'add checkout--worker clean diff reset show status submodule--helper switch\n'
        else
          printf 'add checkout--worker clean diff reset restore show status submodule--helper switch\n'
        fi
        ;;
      'help --all --verbose --no-external-commands --no-aliases')
        case "${TEST_GIT_INDEX:-valid}" in
          unsupported|no-restore) printf 'error: unknown option no-aliases\n' >&2; exit 129 ;;
          error) printf 'index unavailable\n' >&2; exit 1 ;;
          malformed)
            printf 'Available commands:\n   restore;touch  Restore working tree files\n'
            ;;
          ambiguous)
            printf 'Available commands:\n   restore  Alter workspace files\n   reset  Alter workspace files\n'
            ;;
          empty) printf 'Available commands:\n' ;;
          oversized)
            awk 'BEGIN { print "Available commands:";
              for (i=0; i<20001; i++) print "   restore  Restore working tree files" }'
            ;;
          *)
            cat <<'INDEX'
Available commands:
Main Porcelain Commands
   add       Add file contents to the index
   clean     Remove untracked files from the working tree
   diff      Show changes between commits, commit and working tree, etc
   reset     Reset current HEAD to the specified state
   restore   Restore working tree files
   show      Show various types of objects
   status    Show the working tree status
   switch    Switch branches
   obliterate  Restore working tree files and delete unstaged changes
   annihilate  Remove untracked files
   gui       Interactive staged changes interface
   gitk      Display staged changes history
   attributes  Define file properties
INDEX
            ;;
        esac
        ;;
      '--no-pager -h')
        printf 'usage: git command [args]\nGit commands and common tasks.\n'
        ;;
      '--no-pager clean -h'|'--no-pager diff -h'|'--no-pager reset -h'|'--no-pager show -h'|'--no-pager switch -h')
        [[ "${TEST_GIT_HELP_FAIL:-0}" != 1 ]] || exit 1
        printf 'usage: git %s [options]\n' "$2"
        case "$2" in
          clean) printf 'Remove untracked files from the working tree.\n' ;;
          diff) printf 'Show staged changes in the index.\n' ;;
          reset) printf 'Unstage files and reset the index.\n' ;;
          show) printf 'Show HEAD objects.\n' ;;
          switch) printf 'Switch branch.\n' ;;
        esac
        exit 129
        ;;
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
                                                        *c*
c{motion}       Change and edit the word selected by a motion.
                                                        *cw*
cw      Change a word and edit its text.
DOC
cat > "$WORK/package/share/vim/vim92/doc/motion.txt" <<'DOC'
Synthetic fixture: text objects
                                                        *iw*
iw      Select the inner word after an operator, without surrounding spaces.
                                                        *f*
f{char} Jump to a word character in the current line.
                                                        *w*
w       Move the cursor N words forward.
DOC
"$REAL_CP" "$WORK/package/share/vim/vim92/doc/change.txt" "$WORK/package/share/nvim/runtime/doc/change.txt"
"$REAL_CP" "$WORK/package/share/vim/vim92/doc/motion.txt" "$WORK/package/share/nvim/runtime/doc/motion.txt"
cat > "$WORK/package/share/man/man1/git-restore.1" <<'DOC'
Synthetic fixture: installed Git manual
SYNOPSIS
  git restore [--source=tree] [--staged] -- file
Restore a file from the index.
DOC
cat > "$WORK/package/share/man/man1/git-clean.1" <<'DOC'
Synthetic fixture: CLEAN_MANUAL
SYNOPSIS
  git clean [options]
Remove untracked files from the working tree.
DOC
cat > "$WORK/package/share/man/man1/git-diff.1" <<'DOC'
Synthetic fixture: DIFF_MANUAL
SYNOPSIS
  git diff [--cached]
Show staged changes in the index and unstaged working tree changes.
DOC
cat > "$WORK/package/share/man/man1/git-reset.1" <<'DOC'
Synthetic fixture: RESET_MANUAL
SYNOPSIS
  git reset [--mixed] HEAD
Unstage files and reset the index.
DOC
cat > "$WORK/package/share/man/man1/git-show.1" <<'DOC'
Synthetic fixture: SHOW_MANUAL
SYNOPSIS
  git show HEAD
Show various types of objects and HEAD.
DOC
cat > "$WORK/package/share/man/man1/git-switch.1" <<'DOC'
Synthetic fixture: SWITCH_MANUAL
SYNOPSIS
  git switch branch
Switch branches.
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

# Installed command indexes are discovery data: builtins are intersected with
# the safe verbose index before any exact manual or built-in help dispatch.
: > "$TEST_LOG"
documentation="$(qcheat_docs_lookup 'git delete unstaged changes')"
contains "$documentation" 'git-restore.1' 'unstaged deletion selects restore manual'
absent "$documentation" 'git-diff.1' 'unstaged deletion avoids old generic diff route'
contains "$(cat "$TEST_LOG")" 'git <--list-cmds=builtins>' 'installed Git builtins are queried'
contains "$(cat "$TEST_LOG")" 'git <help> <--all> <--verbose> <--no-external-commands> <--no-aliases>' 'safe installed Git index flags'
contains "$(qcheat_docs_lookup 'git discard unstaged changes')" 'git-restore.1' 'unstaged discard selects restore'
documentation="$(qcheat_docs_lookup 'git unstage files')"
[[ "$documentation" == *git-restore.1* || "$documentation" == *git-reset.1* ]] ||
  fail_test 'unstage question lacks restore/reset documentation'
checks=$((checks + 1))
contains "$(qcheat_docs_lookup 'git remove untracked files')" 'CLEAN_MANUAL' 'untracked removal selects clean'
contains "$(qcheat_docs_lookup 'git delete untracked files')" 'CLEAN_MANUAL' 'delete alone does not imply restore'
contains "$(qcheat_docs_lookup 'git discard untracked files')" 'CLEAN_MANUAL' 'untracked discard avoids working-tree restore'
contains "$(qcheat_docs_lookup 'git show staged changes')" 'DIFF_MANUAL' 'staged changes select diff'
contains "$(qcheat_docs_lookup 'git show HEAD')" 'SHOW_MANUAL' 'explicit Git subcommand stays direct'
contains "$(qcheat_docs_lookup 'git switch branch')" 'SWITCH_MANUAL' 'explicit switch stays direct'
for failure in unsupported error builtin-error malformed empty oversized; do
  documentation="$(TEST_GIT_INDEX="$failure" qcheat_docs_lookup 'git delete unstaged changes')"
  contains "$documentation" 'DIFF_MANUAL' "Git index $failure retains conservative fallback"
done
equal "$(TEST_GIT_INDEX=ambiguous qcheat_docs_lookup 'git alter workspace' || :)" '' 'ambiguous Git discovery falls back without unrelated excerpts'
equal "$(qcheat_docs_lookup 'git interplanetary frobnicate' || :)" '' 'Git no-candidate fallback is quiet'
# Tempting aliases, external programs and guides are excluded even if listed.
for excluded in obliterate annihilate gui gitk attributes; do
  printf 'SYNOPSIS\n  git %s\nUnsafe files staged changes untracked EXCLUDED_GIT_MARKER\n' "$excluded" > "$WORK/package/share/man/man1/git-$excluded.1"
done
: > "$TEST_LOG"
for question in 'git obliterate files' 'git annihilate untracked files' \
  'git gui staged changes' 'git gitk staged changes' 'git attributes files'; do
  absent "$(qcheat_docs_lookup "$question" || :)" 'EXCLUDED_GIT_MARKER' 'Git excluded command never selects a manual'
done
for excluded in obliterate annihilate gui gitk attributes; do
  absent "$(cat "$TEST_LOG")" "git <--no-pager> <$excluded>" "Git excluded $excluded is never dispatched"
done

# Official editor indexes can point to fixed core help files through tags.
# Unknown index refs also keep the index text useful without launching an editor.
cat > "$WORK/package/share/vim/vim92/doc/index.txt" <<'DOC'
Synthetic fixture: *index.txt*
|i_CTRL-W|       jump to a word in current line and edit in Insert mode.
|w|     cursor N words forward.
|c|     change Nmove text.
|!|     filter Nmove text through filter command.
|''|    cursor before latest jump first nonblank line.
|Q_sc|  Scrolling |Q_ce| Ex: Command-line editing.
|ziggurat|      Ziggurat navigation INDEX_DISCOVERY_MARKER.
|searchorb|     Orbital transfer.
|escape|       Malicious traversal question.
|absolute|     Malicious absolute question.
|plugin|       Malicious plugin question.
DOC
cat > "$WORK/package/share/vim/vim92/doc/quickref.txt" <<'DOC'
Synthetic fixture: *quickref.txt*
|cw|    change word.
|!|     filter the lines moved.
|quokka|       Quokka reference QUICKREF_DISCOVERY_MARKER.
DOC
{
  printf 'f\tmotion.txt\t/*f*\nw\tmotion.txt\t/*w*\n'
  printf 'i_CTRL-W\tchange.txt\t/*i_CTRL-W*\n'
  printf 'c\tchange.txt\t/*c*\ncw\tchange.txt\t/*cw*\n'
  printf 'searchorb\tpattern.txt\t/*searchorb*\n'
  printf 'escape\t../../../../../escaped-doc.txt\t/execute-anything/\n'
  printf 'absolute\t%s/escaped-doc.txt\t/execute-anything/\n' "$WORK"
  printf 'plugin\tplugin.txt\t/execute-anything/\n'
} > "$WORK/package/share/vim/vim92/doc/tags"
cat > "$WORK/package/share/vim/vim92/doc/pattern.txt" <<'DOC'
*searchorb*     Regex syntax HELP_TAG_RESOLUTION_MARKER.
DOC
cat > "$WORK/package/share/vim/vim92/doc/starting.txt" <<'DOC'
Jump to a word in current line and edit SHELL_LAUNCH_MANUAL_MARKER.
DOC
printf 'Malicious traversal absolute plugin question UNSAFE_HELP_MARKER\n' > "$WORK/escaped-doc.txt"
"$REAL_CP" "$WORK/escaped-doc.txt" "$WORK/package/share/vim/vim92/doc/plugin.txt"
for name in index.txt quickref.txt tags plugin.txt pattern.txt starting.txt; do
  "$REAL_CP" "$WORK/package/share/vim/vim92/doc/$name" "$WORK/package/share/nvim/runtime/doc/$name"
done
for editor in vim nvim; do
  if [[ "$editor" == vim ]]; then editor_doc="$WORK/package/share/vim/vim92/doc";
  else editor_doc="$WORK/package/share/nvim/runtime/doc"; fi
  absent "$(qcheat_docs_editor_index "$editor_doc" "$editor jump to a word in current line and edit")" 'i_CTRL-W' "$editor unqualified question prefers Normal mode"
  contains "$(qcheat_docs_lookup "$editor ziggurat navigation")" 'index.txt' "$editor uses installed index"
  contains "$(qcheat_docs_lookup "$editor quokka reference")" 'quickref.txt' "$editor uses installed quickref"
  contains "$(qcheat_docs_lookup "$editor orbital transfer")" 'HELP_TAG_RESOLUTION_MARKER' "$editor resolves official index tag metadata"
  documentation="$(qcheat_docs_lookup "$editor jump to a word in current line and edit")"
  contains "$documentation" 'motion.txt' "$editor natural-language question retrieves motions"
  contains "$documentation" 'change.txt' "$editor natural-language question retrieves changes"
  absent "$documentation" 'SHELL_LAUNCH_MANUAL_MARKER' "$editor motion question is not shell-launch help"
  [[ "${#documentation}" -le 6000 ]] || fail_test "$editor output exceeds 6000 bytes"
  [[ "$(printf '%s\n' "$documentation" | awk '/^\[Source:/ { n++ } END { print n+0 }')" -le 3 ]] ||
    fail_test "$editor index discovery exceeds three excerpts"
  checks=$((checks + 2))
  for attack in traversal absolute plugin; do
    absent "$(qcheat_docs_lookup "$editor malicious $attack question" || :)" 'UNSAFE_HELP_MARKER' "$editor rejects unsafe tag $attack file"
  done
  for name in index.txt quickref.txt; do
    "$REAL_MV" "$editor_doc/$name" "$WORK/$editor-$name-saved"
  done
  contains "$(qcheat_docs_lookup "$editor delete to end of line")" 'synonym for "d$"' "$editor missing indexes keep existing fallback"
  for name in index.txt quickref.txt; do
    "$REAL_MV" "$WORK/$editor-$name-saved" "$editor_doc/$name"
  done
done
absent "$(cat "$TEST_LOG")" 'nvim <' 'index discovery never launches Neovim'
equal "$(awk '/^vim / && $0 != "vim <--version>"' "$TEST_LOG")" '' 'index discovery never starts interactive Vim'

"$REAL_MV" "$WORK/package/share/man/man1/git-restore.1" "$WORK/git-man-saved"
contains "$(qcheat_docs_lookup 'git restore a file')" 'installed git restore -h' 'Git missing man fallback'
contains "$(qcheat_docs_lookup 'git delete unstaged changes')" 'installed git restore -h' 'Git discovered command retains missing-man fallback'
equal "$(TEST_GIT_HELP_FAIL=1 qcheat_docs_lookup 'git restore a file' || :)" '' 'Git errors are not documentation'
equal "$(TEST_GIT_HELP_FAIL=1 qcheat_docs_lookup 'git delete unstaged changes' || :)" '' 'Git missing relevant documentation stays quiet'
: > "$TEST_LOG"
equal "$(TEST_GIT_INDEX=no-restore qcheat_docs_lookup 'git restore a file' || :)" '' 'Git missing builtin and manual stay quiet'
absent "$(cat "$TEST_LOG")" 'git <--no-pager> <restore> <-h>' 'unsupported builtin never dispatches a Git alias or external command'
: > "$TEST_LOG"
equal "$(TEST_GIT_INDEX=builtin-error qcheat_docs_lookup 'git restore a file' || :)" '' 'Git unavailable builtins and missing manual stay quiet'
absent "$(cat "$TEST_LOG")" 'git <--no-pager> <restore> <-h>' 'uncertain builtins are never dispatched'
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
equal "$("$HOME/.local/bin/qcheat" --version)" 'qcheat 0.5.0beta' 'installed version'
rm "$HOME/.local/lib/qcheat/docs.sh"
equal "$("$HOME/.local/bin/qcheat" explain loops)" 'fixture answer' 'missing library fallback'
printf 'PASS: %s checks\n' "$checks"

# Restore the host utilities for the helper suite's own isolated mocks.
PATH="$TEST_HOST_PATH" "$REAL_BASH" "$ROOT/dev/tests/helpers.sh"
