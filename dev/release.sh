#!/usr/bin/env bash
# Maintainer commands behind make tag/push-tag/release; installation stays in install.sh.
set -Eeuo pipefail

fail() { printf '[ X ] %s\n' "$*" >&2; exit 1; }
usage() {
    cat <<'USAGE'
qcheat release helper

Usage: bash dev/release.sh [--dry-run] tag|push-tag|release
       bash dev/release.sh --help|--version

  tag         Create the current version's local annotated tag
  push-tag    Push only that tag to origin
  release     Create a GitHub release for the already-pushed tag
  --dry-run   Validate and show the action without changing Git or GitHub
USAGE
}
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
read_version() {
    local version_output
    [[ -f "$root/bin/qcheat" ]] || fail 'Canonical version source bin/qcheat is missing.'
    version_output=$(bash "$root/bin/qcheat" --version) || fail 'Cannot read the canonical version from bin/qcheat.'
    [[ $version_output =~ ^qcheat\ ([0-9]+\.[0-9]+\.[0-9]+[ab]?)$ ]] || fail "Invalid project version: $version_output"
    version=${BASH_REMATCH[1]}
}
case "${1:-}" in
    -h|--help) [[ $# == 1 ]] || fail 'Use --help by itself.'; usage; exit 0 ;;
    -V|--version) [[ $# == 1 ]] || fail 'Use --version by itself.'; read_version; printf 'qcheat %s\n' "$version"; exit 0 ;;
esac
dry_run=false
if [[ ${1:-} == --dry-run ]]; then dry_run=true; shift; fi
(( $# == 1 )) && [[ $1 == tag || $1 == push-tag || $1 == release ]] || fail 'Usage: bash dev/release.sh [--dry-run] tag|push-tag|release'
action=$1
run() {
    if [[ $dry_run == true ]]; then
        printf '[DRY]'; printf ' %q' "$@"; printf '\n'
    else
        "$@"
    fi
}
finish() {
    if [[ $dry_run == true ]]; then
        printf '[DRY] Validation completed. No Git or GitHub changes were made.\n'
    else
        printf '[ OK ] %s\n' "$*"
    fi
}
command -v git >/dev/null 2>&1 || fail 'git is required.'
if [[ $action == release ]]; then
    command -v gh >/dev/null 2>&1 || fail 'gh is required; install GitHub CLI and authenticate with gh auth login.'
fi
cd -- "$root"
[[ $(git rev-parse --show-toplevel) == "$root" ]] || fail 'Run from a complete qcheat Git checkout.'
head=$(git rev-parse --verify 'HEAD^{commit}') || fail 'HEAD must contain a commit.'
status=$(git status --porcelain --untracked-files=all --ignore-submodules=none)
[[ -z $status ]] || fail 'Working tree must be clean, including staged and untracked files; commit or move changes first.'
for state in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD rebase-merge rebase-apply sequencer BISECT_LOG; do
    [[ ! -e $(git rev-parse --git-path "$state") ]] || fail "Finish the in-progress Git operation ($state) first."
done
git ls-files --error-unmatch bin/qcheat >/dev/null || fail 'The canonical version source bin/qcheat must be tracked.'
read_version
tag=v$version
ref=refs/tags/$tag

# Use one explicit destination for both Git and gh, regardless of GH_REPO or
# gh's default repository. Refuse ambiguous multi-destination push settings.
remote=$(git remote get-url --push --all origin) || fail 'An origin push URL is required.'
[[ -n $remote && $remote != *$'\n'* ]] || fail 'origin must have exactly one push URL.'
read_remote_tag() {
    local remote_tags object name
    remote_object=''
    remote_commit=''
    remote_tags=$(git ls-remote --tags -- "$remote" "$ref" "$ref^{}") || fail 'Cannot check origin tags; no changes were made.'
    while read -r object name; do
        [[ -n $object ]] || continue
        case "$name" in
            "$ref") remote_object=$object ;;
            "$ref^{}") remote_commit=$object ;;
        esac
    done <<< "$remote_tags"
}
matching_remote_tag() {
    [[ $remote_object == "$tag_object" ]] || fail "Remote tag $tag differs from the local tag."
    [[ $remote_commit == "$head" ]] || fail "Remote tag $tag does not point to HEAD."
}

if [[ $action == tag ]]; then
    if git show-ref --verify --quiet "$ref"; then
        fail "Tag $tag already exists; it will not be replaced."
    fi
    read_remote_tag
    [[ -z $remote_object && -z $remote_commit ]] || fail "Tag $tag already exists on origin; it will not be replaced."
    run git tag -a "$tag" -m "qcheat $version" "$head"
    finish "Created local annotated tag $tag. Nothing pushed."
    exit 0
fi

# Publish only an existing annotated tag made for this exact commit.
[[ $(git cat-file -t "$ref" 2>/dev/null) == tag ]] || fail "Annotated tag $tag is required; run make tag first."
[[ $(git rev-parse "$ref^{commit}") == "$head" ]] || fail "Tag $tag does not point to HEAD."
tag_object=$(git rev-parse "$ref")
read_remote_tag

if [[ $action == push-tag ]]; then
    if [[ -n $remote_object || -n $remote_commit ]]; then
        matching_remote_tag
        finish "Tag $tag already matches origin. Nothing pushed."
        exit 0
    fi
    # Explicit refspec and disabled follow-tags/mirroring prevent unrelated pushes.
    run git push --no-follow-tags --no-mirror --recurse-submodules=no -- "$remote" "$ref:$ref" || fail 'Tag push failed.'
    finish "Published tag $tag to origin."
    exit 0
fi

[[ -n $remote_object ]] || fail "Tag $tag is not on origin; run make push-tag first."
matching_remote_tag
case "$remote" in
    https://*) repository=${remote#https://} ;;
    git@*:*) repository=${remote#git@}; repository=${repository/:/\/} ;;
    ssh://git@*) repository=${remote#ssh://git@} ;;
    *) fail 'origin must use a GitHub HTTPS or SSH URL.' ;;
esac
repository=${repository%.git}
[[ $repository =~ ^([a-zA-Z0-9.-]+)/([a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+)$ ]] || fail 'Cannot determine the GitHub host and repository from origin.'
host=${BASH_REMATCH[1]}
repo=${BASH_REMATCH[2]}
gh auth status --hostname "$host" >/dev/null || fail "Authenticate with gh auth login --hostname $host first."
permission=$(gh api --hostname "$host" "repos/$repo" --jq '.permissions.push') || fail 'Cannot access the release repository.'
[[ $permission == true ]] || fail 'GitHub write permission is required to release.'
# Listing successfully distinguishes absence from auth/network failures, and
# includes drafts. Paginate so older releases are checked too.
existing=$(gh api --hostname "$host" --paginate "repos/$repo/releases?per_page=100" \
    --jq ".[] | select(.tag_name == \"$tag\") | .tag_name") || fail 'Cannot check existing releases; no changes were made.'
[[ -z $existing ]] || fail "GitHub release $tag already exists; it will not be replaced."
run gh release create "$tag" --repo "$repository" --verify-tag \
    --title "qcheat $version" --generate-notes || fail "Release creation failed. Tag $tag remains on origin; inspect GitHub before retrying."
finish "Created GitHub release qcheat $version."
