#!/usr/bin/env bash
# Offline helper tests: Git/GitHub/Ollama/removal commands are isolated mocks.
set -Eeuo pipefail
ROOT=$(cd -- "${BASH_SOURCE[0]%/*}/../.." && pwd -P)
WORK=$(mktemp -d "$ROOT/.test-work.XXXXXX")
trap 'rm -rf -- "$WORK"' EXIT
REAL_BASH=$(command -v bash)
REAL_ENV=$(command -v env)
REAL_MAKE=$(command -v make)
MOCK_PATH="$WORK/bin"
fixture_home="$WORK/home with spaces"
checkout="$ROOT"
checks=0
fail_test() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
equal() { [[ $1 == "$2" ]] || fail_test "$3: expected '$2', got '$1'"; checks=$((checks + 1)); }
contains() { [[ $1 == *"$2"* ]] || fail_test "$3: missing '$2'"; checks=$((checks + 1)); }
absent() { [[ $1 != *"$2"* ]] || fail_test "$3: unexpected '$2'"; checks=$((checks + 1)); }
expect_failure() {
    local expected=$1 output
    shift
    if output=$("$@" 2>&1); then fail_test "expected failure: $expected"; fi
    contains "$output" "$expected" 'clear helper failure'
}
mkdir -p "$MOCK_PATH" "$fixture_home/.local/bin" "$fixture_home/.local/lib/qcheat" \
    "$fixture_home/.local/lib/unrelated" "$WORK/make fixture"
touch "$fixture_home/.local/bin/qcheat" "$fixture_home/.local/bin/ollama" \
    "$fixture_home/.local/bin/mdcat" "$fixture_home/.local/lib/qcheat/docs.sh" \
    "$fixture_home/.local/lib/unrelated/keep" "$WORK/operation"
# Keep shell variables literal in this fixture.
# shellcheck disable=SC2016
printf 'alias q=qcheat\nexport PATH="$HOME/.local/bin:$PATH"\n' > "$fixture_home/.bashrc"
cp "$fixture_home/.bashrc" "$fixture_home/.zshrc"
rc_before=$(cat "$fixture_home/.bashrc")
for name in bash cat dirname; do ln -s "$(command -v "$name")" "$MOCK_PATH/$name"; done
version=$(bash "$ROOT/bin/qcheat" --version)
version=${version#qcheat }

cat > "$WORK/dispatch" <<'MOCK'
#!/usr/bin/env bash
set -eu
name=${0##*/}
{ printf '%s' "$name"; printf ' <%s>' "$@"; printf '\n'; } >> "$TEST_LOG"
case "$name" in
    git)
        case "$1" in
            rev-parse)
                case "$2" in
                    --show-toplevel) printf '%s\n' "$TEST_ROOT" ;;
                    --verify) printf 'head-object\n' ;;
                    --git-path)
                        if [[ ${TEST_OPERATION:-} == "$3" ]]; then
                            printf '%s/operation\n' "$TEST_WORK"
                        else
                            printf '%s/no-operation/%s\n' "$TEST_WORK" "$3"
                        fi
                        ;;
                    *'^{commit}') printf '%s\n' "${TEST_TAG_HEAD:-head-object}" ;;
                    refs/tags/*) printf 'tag-object\n' ;;
                    *) exit 70 ;;
                esac
                ;;
            status) printf '%s' "${TEST_DIRTY:-}" ;;
            ls-files) exit "${TEST_TRACKED_STATUS:-0}" ;;
            remote)
                [[ ${TEST_REMOTE_FAIL:-0} == 0 ]] || exit 71
                printf '%s\n' "${TEST_REMOTE:-https://github.com/cheeezeburgers/qcheat.git}"
                ;;
            show-ref) [[ ${TEST_LOCAL_TAG:-absent} == present ]] ;;
            cat-file)
                [[ ${TEST_TAG_TYPE:-tag} != missing ]] || exit 72
                printf '%s\n' "${TEST_TAG_TYPE:-tag}"
                ;;
            ls-remote)
                [[ ${TEST_REMOTE_CHECK_FAIL:-0} == 0 ]] || exit 73
                case "${TEST_REMOTE_TAG:-absent}" in
                    absent) ;;
                    matching) printf 'tag-object\t%s\nhead-object\t%s^{}\n' "$TEST_REF" "$TEST_REF" ;;
                    object-conflict) printf 'other-object\t%s\nhead-object\t%s^{}\n' "$TEST_REF" "$TEST_REF" ;;
                    commit-conflict) printf 'tag-object\t%s\nother-commit\t%s^{}\n' "$TEST_REF" "$TEST_REF" ;;
                    *) exit 74 ;;
                esac
                ;;
            *) printf 'Unexpected Git command: %s\n' "$*" >&2; exit 75 ;;
        esac
        ;;
    gh)
        case "$1" in
            auth) exit "${TEST_AUTH_STATUS:-0}" ;;
            api)
                [[ ${TEST_API_STATUS:-0} == 0 ]] || exit 76
                if [[ $* == *'/releases?'* ]]; then
                    printf '%s' "${TEST_EXISTING_RELEASE:-}"
                else
                    printf '%s\n' "${TEST_PERMISSION:-true}"
                fi
                ;;
            *) printf 'Unexpected GitHub command: %s\n' "$*" >&2; exit 77 ;;
        esac
        ;;
    ollama)
        case "$1" in
            list)
                [[ ${TEST_LIST_STATUS:-0} == 0 ]] || exit 78
                printf 'NAME ID SIZE MODIFIED\nqwen2.5-coder:3b-instruct base 1GB now\nqwen-cheat-extra:latest other 1GB now\n'
                case "${TEST_MODEL:-present}" in
                    present) printf 'qwen-cheat:latest custom 1GB now\n' ;;
                    bare) printf 'qwen-cheat custom 1GB now\n' ;;
                    absent) ;;
                    *) exit 79 ;;
                esac
                ;;
            rm) [[ $* == 'rm qwen-cheat' ]] || exit 80; exit "${TEST_MODEL_REMOVE_STATUS:-0}" ;;
            *) exit 81 ;;
        esac
        ;;
    rm) exit "${TEST_RM_STATUS:-0}" ;;
    *) exit 82 ;;
esac
MOCK
chmod +x "$WORK/dispatch"
for name in git gh ollama rm; do ln -s "$WORK/dispatch" "$MOCK_PATH/$name"; done
: > "$WORK/log"
release_check() {
    local action=$1
    shift
    "$REAL_ENV" PATH="$MOCK_PATH" HOME="$fixture_home" TEST_ROOT="$checkout" \
        TEST_WORK="$WORK" TEST_LOG="$WORK/log" TEST_REF="refs/tags/v$version" \
        "$@" "$REAL_BASH" "$checkout/dev/release.sh" --dry-run "$action"
}
uninstall_check() {
    local option=$1
    shift
    if [[ -n $option ]]; then
        "$REAL_ENV" PATH="$MOCK_PATH" HOME="$fixture_home" TEST_LOG="$WORK/log" \
            "$@" "$REAL_BASH" "$ROOT/dev/uninstall.sh" "$option"
    else
        "$REAL_ENV" PATH="$MOCK_PATH" HOME="$fixture_home" TEST_LOG="$WORK/log" \
            "$@" "$REAL_BASH" "$ROOT/dev/uninstall.sh"
    fi
}

# Dry Make recipes still run when files happen to share the target names.
for target in install uninstall tag push-tag release; do touch "$WORK/make fixture/$target"; done
recipes=$("$REAL_MAKE" -n -C "$WORK/make fixture" -f "$ROOT/Makefile" install uninstall tag push-tag release)
contains "$recipes" './install.sh' 'canonical installer delegation'
contains "$recipes" 'bash dev/uninstall.sh' 'uninstall delegation'
for action in tag push-tag release; do
    contains "$recipes" "bash dev/release.sh $action" "release delegation: $action"
done
absent "$recipes" jrnl 'no copied project names'
absent "$recipes" development/ 'no copied project paths'
for flag in -h --help; do
    contains "$(bash "$ROOT/dev/release.sh" "$flag")" 'Usage:' 'release help'
    contains "$(uninstall_check "$flag")" 'Usage:' 'uninstall help'
done
for flag in -V --version; do
    equal "$(bash "$ROOT/dev/release.sh" "$flag")" "qcheat $version" 'canonical helper version'
done
expect_failure 'Usage:' release_check invalid
expect_failure 'Usage:' uninstall_check invalid

output=$(release_check tag)
contains "$output" "git tag -a v$version" 'local tag preview'
contains "$output" 'qcheat\ ' 'annotated tag title'
contains "$output" 'No Git or GitHub changes were made.' 'tag dry-run completion'
expect_failure 'already exists; it will not be replaced' release_check tag TEST_LOCAL_TAG=present
expect_failure 'already exists on origin' release_check tag TEST_REMOTE_TAG=matching
expect_failure 'must be clean' release_check tag 'TEST_DIRTY=?? untracked'
expect_failure 'must be clean' release_check push-tag 'TEST_DIRTY=M  staged'
expect_failure 'must be clean' release_check release 'TEST_DIRTY= M unstaged'
expect_failure 'in-progress Git operation' release_check tag TEST_OPERATION=MERGE_HEAD
expect_failure 'must be tracked' release_check tag TEST_TRACKED_STATUS=1
expect_failure 'origin push URL is required' release_check tag TEST_REMOTE_FAIL=1
expect_failure 'exactly one push URL' release_check tag "TEST_REMOTE=$(printf 'https://github.com/one/repo.git\nhttps://github.com/two/repo.git')"
expect_failure 'Cannot check origin tags' release_check tag TEST_REMOTE_CHECK_FAIL=1

output=$(release_check push-tag)
contains "$output" '--no-follow-tags --no-mirror --recurse-submodules=no' 'no unrelated pushes'
contains "$output" "refs/tags/v$version:refs/tags/v$version" 'explicit tag-only refspec'
contains "$output" 'No Git or GitHub changes were made.' 'push dry-run completion'
output=$(release_check push-tag TEST_REMOTE_TAG=matching)
absent "$output" '[DRY] git push' 'matching remote is a no-op'
expect_failure 'Annotated tag' release_check push-tag TEST_TAG_TYPE=missing
expect_failure 'Annotated tag' release_check push-tag TEST_TAG_TYPE=commit
expect_failure 'does not point to HEAD' release_check push-tag TEST_TAG_HEAD=other-commit
expect_failure 'differs from the local tag' release_check push-tag TEST_REMOTE_TAG=object-conflict
expect_failure 'does not point to HEAD' release_check push-tag TEST_REMOTE_TAG=commit-conflict

: > "$WORK/log"
expect_failure 'not on origin; run make push-tag first' release_check release
absent "$(cat "$WORK/log")" 'gh <auth>' 'remote tag required before GitHub access'
output=$(release_check release TEST_REMOTE_TAG=matching GH_REPO=unrelated/repo)
contains "$output" "gh release create v$version" 'release preview'
contains "$output" '--repo github.com/cheeezeburgers/qcheat' 'explicit repository'
contains "$output" "--title qcheat\\ $version --generate-notes" 'release title and notes'
contains "$output" '--verify-tag' 'remote tag verified by gh'
contains "$output" 'No Git or GitHub changes were made.' 'release dry-run completion'
for remote in git@github.com:cheeezeburgers/qcheat.git ssh://git@github.com/cheeezeburgers/qcheat.git; do
    contains "$(release_check release TEST_REMOTE_TAG=matching "TEST_REMOTE=$remote")" \
        '--repo github.com/cheeezeburgers/qcheat' 'SSH origin parsing'
done
expect_failure 'differs from the local tag' release_check release TEST_REMOTE_TAG=object-conflict
expect_failure 'does not point to HEAD' release_check release TEST_REMOTE_TAG=commit-conflict
expect_failure 'GitHub HTTPS or SSH URL' release_check release TEST_REMOTE_TAG=matching TEST_REMOTE=/tmp/fixture-remote
expect_failure 'Authenticate with gh auth login' release_check release TEST_REMOTE_TAG=matching TEST_AUTH_STATUS=1
expect_failure 'Cannot access the release repository' release_check release TEST_REMOTE_TAG=matching TEST_API_STATUS=1
expect_failure 'write permission is required' release_check release TEST_REMOTE_TAG=matching TEST_PERMISSION=false
expect_failure 'already exists; it will not be replaced' release_check release TEST_REMOTE_TAG=matching "TEST_EXISTING_RELEASE=v$version"
rm "$MOCK_PATH/gh"
expect_failure 'gh is required' release_check release
ln -s "$WORK/dispatch" "$MOCK_PATH/gh"
rm "$MOCK_PATH/git"
expect_failure 'git is required' release_check tag
ln -s "$WORK/dispatch" "$MOCK_PATH/git"
log=$(cat "$WORK/log")
for mutation in 'git <tag>' 'git <push>' 'gh <release>'; do
    absent "$log" "$mutation" 'no release mutations invoked'
done

# A copied fixture also checks source validation and paths with spaces.
checkout="$WORK/checkout with spaces"
mkdir -p "$checkout/dev" "$checkout/bin"
cp "$ROOT/dev/release.sh" "$checkout/dev/release.sh"
expect_failure 'version source bin/qcheat is missing' release_check tag
printf 'printf "qcheat invalid\\n"\n' > "$checkout/bin/qcheat"
expect_failure 'Invalid project version' release_check tag
printf 'printf "qcheat 7.8.9a\\n"\n' > "$checkout/bin/qcheat"
contains "$(release_check tag)" 'git tag -a v7.8.9a' 'canonical alpha version in path with spaces'
checkout="$ROOT"

: > "$WORK/log"
output=$(uninstall_check --dry-run)
contains "$output" '[DRY] rm -f --' 'command removal preview'
contains "$output" '[DRY] rm -rf --' 'library removal preview'
contains "$output" '[DRY] ollama rm qwen-cheat' 'custom model removal preview'
contains "$output" 'No uninstall changes were made.' 'uninstall dry-run completion'
log=$(cat "$WORK/log")
absent "$log" 'rm <' 'dry-run does not remove files'
absent "$log" 'ollama <rm>' 'dry-run does not remove models'

# Normal uninstall uses mocked removals, so no installed resources are deleted.
: > "$WORK/log"
output=$(uninstall_check '')
log=$(cat "$WORK/log")
contains "$log" "rm <-f> <--> <$fixture_home/.local/bin/qcheat>" 'only command is removed'
contains "$log" "rm <-rf> <--> <$fixture_home/.local/lib/qcheat>" 'only library is removed'
contains "$log" 'ollama <rm> <qwen-cheat>' 'only installed custom model is removed'
absent "$log" '<qwen2.5-coder:3b-instruct>' 'base model is retained'
absent "$log" '/bin/ollama>' 'Ollama executable is retained'
absent "$log" '/bin/mdcat>' 'mdcat executable is retained'
absent "$log" '/lib/unrelated>' 'unrelated library is retained'
contains "$output" 'aliases and PATH entries may need manual cleanup' 'shell cleanup reminder'
equal "$(cat "$fixture_home/.bashrc")" "$rc_before" 'bash rc untouched'
equal "$(cat "$fixture_home/.zshrc")" "$rc_before" 'zsh rc untouched'
: > "$WORK/log"
uninstall_check '' TEST_MODEL=absent > /dev/null
absent "$(cat "$WORK/log")" 'ollama <rm>' 'absent model and lookalike are skipped'
: > "$WORK/log"
uninstall_check '' TEST_MODEL=bare > /dev/null
contains "$(cat "$WORK/log")" 'ollama <rm> <qwen-cheat>' 'bare custom model name is recognized'
expect_failure 'Could not list Ollama models' uninstall_check '' TEST_LIST_STATUS=1
expect_failure 'Could not remove qwen-cheat' uninstall_check '' TEST_MODEL_REMOVE_STATUS=1
expect_failure 'Could not remove' uninstall_check '' TEST_RM_STATUS=1
expect_failure 'HOME must be an absolute' uninstall_check '' HOME=/

# Missing and dangling installed resources are handled without touching targets.
rm "$fixture_home/.local/bin/qcheat"
rm -rf "$fixture_home/.local/lib/qcheat"
: > "$WORK/log"
uninstall_check '' TEST_MODEL=absent > /dev/null
absent "$(cat "$WORK/log")" 'rm <' 'absent files are a no-op'
ln -s "$fixture_home/missing command" "$fixture_home/.local/bin/qcheat"
ln -s "$fixture_home/.local/lib/unrelated" "$fixture_home/.local/lib/qcheat"
: > "$WORK/log"
uninstall_check '' TEST_MODEL=absent > /dev/null
contains "$(cat "$WORK/log")" "<$fixture_home/.local/bin/qcheat>" 'dangling command symlink handled'
contains "$(cat "$WORK/log")" "<$fixture_home/.local/lib/qcheat>" 'library symlink has no trailing slash'
[[ -e "$fixture_home/.local/lib/unrelated/keep" ]] || fail_test 'symlink target was removed'
checks=$((checks + 1))
rm "$MOCK_PATH/ollama"
contains "$(uninstall_check '' 2>&1)" 'Ollama is unavailable' 'missing Ollama does not fail uninstall'
printf 'PASS: %s helper checks (no real install, uninstall or release actions)\n' "$checks"
