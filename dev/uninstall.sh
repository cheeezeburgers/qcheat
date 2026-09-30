#!/usr/bin/env bash
# Remove only resources installed for qcheat, leaving shared dependencies alone.
set -Eeuo pipefail

fail() { printf '[ X ] %s\n' "$*" >&2; exit 1; }
warn() { printf '[ ! ] %s\n' "$*" >&2; }
dry_run=false
case "${1:-}" in
    '') [[ $# == 0 ]] || fail 'An empty argument is not supported.' ;;
    --dry-run) [[ $# == 1 ]] || fail 'Use --dry-run by itself.'; dry_run=true ;;
    -h|--help)
        [[ $# == 1 ]] || fail 'Use --help by itself.'
        cat <<'USAGE'
qcheat uninstaller

Usage: bash dev/uninstall.sh [--dry-run]
       bash dev/uninstall.sh --help

Remove ~/.local/bin/qcheat, ~/.local/lib/qcheat and the qwen-cheat Ollama model.
Ollama, mdcat, the base Qwen model and shell configuration are preserved.
USAGE
        exit 0
        ;;
    *) fail 'Usage: bash dev/uninstall.sh [--dry-run|--help]' ;;
esac
[[ ${HOME:-} == /* && $HOME != / ]] || fail 'HOME must be an absolute home-directory path, not /.'
run() {
    if [[ $dry_run == true ]]; then
        printf '[DRY]'; printf ' %q' "$@"; printf '\n'
    else
        "$@"
    fi
}
result=0
command_path="$HOME/.local/bin/qcheat"
library_path="$HOME/.local/lib/qcheat"
if [[ -e $command_path || -L $command_path ]]; then
    run rm -f -- "$command_path" || { warn "Could not remove $command_path"; result=1; }
fi
# No trailing slash: a symlink is removed without following its target.
if [[ -e $library_path || -L $library_path ]]; then
    run rm -rf -- "$library_path" || { warn "Could not remove $library_path"; result=1; }
fi
if command -v ollama >/dev/null 2>&1; then
    if models=$(ollama list); then
        while read -r name _; do
            case "$name" in
                qwen-cheat|qwen-cheat:latest)
                    run ollama rm qwen-cheat || { warn 'Could not remove qwen-cheat; retry with: ollama rm qwen-cheat'; result=1; }
                    break
                    ;;
            esac
        done <<< "$models"
    else
        warn 'Could not list Ollama models; check qwen-cheat manually with: ollama list'
        result=1
    fi
else
    warn 'Ollama is unavailable; skipped the qwen-cheat model check.'
fi
printf '[ ! ] Shell rc files were left unchanged; aliases and PATH entries may need manual cleanup.\n'
if [[ $dry_run == true ]]; then
    printf '[DRY] No uninstall changes were made.\n'
elif [[ $result == 0 ]]; then
    printf '[ OK ] qcheat uninstall completed.\n'
fi
exit "$result"
