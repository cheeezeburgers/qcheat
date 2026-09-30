#!/usr/bin/env bash

# Read-only local documentation lookup. All subprocess arguments come from
# fixed allowlists; the question is passed to text processing only as data.

qcheat_docs_normalize() {
  LC_ALL=C tr '[:upper:]' '[:lower:]' |
    LC_ALL=C tr -cs '[:alnum:]_-' ' '
}

qcheat_docs_detect() {
  local words=" $1 " tool='' candidate count=0

  # Do not ground editor questions in unrelated shell documentation.
  case "$words" in
    *' vscode '*|*' vs code '*|*' visual studio code '*) return 1 ;;
  esac

  for candidate in vim nvim git gh; do
    case "$candidate:$words" in
      vim:*' vim '*|nvim:*' nvim '*|nvim:*' neovim '*|git:*' git '*|gh:*' gh '*|gh:*' github cli '*)
        tool="$candidate"
        count=$((count + 1))
        ;;
    esac
  done
  [[ "$count" -le 1 ]] || return 1
  if [[ -n "$tool" ]]; then
    printf '%s\n' "$tool"
    return
  fi

  # Keep the generic set explicit: never execute arbitrary question tokens.
  for candidate in cp mv grep find ls mkdir rm chmod chown cat head tail sort uniq wc sed awk tar; do
    case "$words" in
      *" $candidate "*) tool="$candidate"; count=$((count + 1)) ;;
    esac
  done
  [[ "$count" -le 1 ]] || return 1
  if [[ -n "$tool" ]]; then
    printf '%s\n' "$tool"
    return
  fi

  case "$words" in
    *' copy '*|*' move '*)
      case "$words" in
        *' file '*|*' files '*|*' directory '*|*' directories '*|*' folder '*|*' folders '*)
          case "$words" in
            *' copy '*' move '*|*' move '*' copy '*) return 1 ;;
            *' copy '*) printf 'cp\n' ;;
            *' move '*) printf 'mv\n' ;;
          esac
          return
          ;;
      esac
      ;;
  esac
  return 1
}

# Resolve package-manager symlinks without GNU-only readlink -f or realpath.
qcheat_docs_executable() {
  local path target hops=0
  path="$(command -v "$1")" || return 1
  [[ -f "$path" && -x "$path" ]] || return 1
  while [[ -L "$path" && "$hops" -lt 32 ]]; do
    target="$(readlink "$path")" || return 1
    case "$target" in
      /*) path="$target" ;;
      *) path="${path%/*}/$target" ;;
    esac
    hops=$((hops + 1))
  done
  [[ ! -L "$path" ]] || return 1
  printf '%s/%s\n' "$(cd -- "${path%/*}" && pwd -P)" "${path##*/}"
}

qcheat_docs_excerpt() {
  QCHEAT_DOC_QUERY="$1" QCHEAT_DOC_SOURCE="$2" QCHEAT_DOC_TAGS="${3:-}" \
    LC_ALL=C awk -f "${QCHEAT_DOCS_DIR}/excerpt.awk"
}

qcheat_docs_editor_dir() {
  local tool="$1" executable="$2" prefix version runtime root dir
  prefix="${executable%/*}"
  prefix="${prefix%/*}"
  if [[ "$tool" == nvim ]]; then
    dir="$prefix/share/nvim/runtime/doc"
    [[ -d "$dir" ]] || return 1
    printf '%s\n' "$dir"
    return
  fi

  if [[ -n "${VIMRUNTIME:-}" && -d "$VIMRUNTIME/doc" ]]; then
    printf '%s/doc\n' "$VIMRUNTIME"
    return
  fi
  version="$(LC_ALL=C "$executable" --version)" || return 1
  runtime="$(printf '%s\n' "$version" | awk '
    NR == 1 && $5 ~ /^[0-9]+\.[0-9]+$/ {
      split($5, v, "."); print "vim" v[1] v[2]
    }')"
  [[ -n "$runtime" ]] || return 1
  # Match the literal $VIM label printed by --version.
  # shellcheck disable=SC2016
  root="$(printf '%s\n' "$version" | sed -n 's/.*fall-back for \$VIM: "\([^"]*\)"/\1/p')"
  for dir in "$prefix/share/vim/$runtime/doc" "${root:-$prefix/share/vim}/$runtime/doc"; do
    if [[ -d "$dir" ]]; then
      printf '%s\n' "$dir"
      return
    fi
  done
  return 1
}

qcheat_docs_editor() {
  local tool="$1" executable="$2" query="$3" dir name tags='' words=" $3 "
  local files=()
  dir="$(qcheat_docs_editor_dir "$tool" "$executable")" || return 1

  # Boost exact official help tags for common editing questions. Both the
  # operator and text-object definitions are needed to explain e.g. yiw.
  case "$words" in
    *' current word '*|*' inner word '*|*' word under '*' cursor '*)
      case "$words" in
        *' copy '*|*' yank '*) tags='*iw* *y*' ;;
        *' delete '*) tags='*iw* *d*' ;;
        *' change '*) tags='*iw* *c*' ;;
      esac
      ;;
    *' delete '*' end '*' line '*) tags='*D*' ;;
    *' copy '*' line '*|*' yank '*' line '*) tags='*yy*' ;;
    *' delete '*' line '*) tags='*dd*' ;;
    *' change '*' line '*|*' replace '*' line '*) tags='*cc*' ;;
  esac

  # A small topic shortlist avoids scanning plugins and the entire help tree.
  for name in change motion; do
    [[ ! -r "$dir/$name.txt" ]] || files+=("$dir/$name.txt")
  done
  case "$words" in
    *' window '*|*' split '*|*' buffer '*|*' tab '*) name=windows ;;
    *' search '*|*' pattern '*) name=pattern ;;
    *' map '*|*' mapping '*|*' keymap '*) name=map ;;
    *' option '*|*' set '*) name=options ;;
    *' file '*|*' save '*|*' quit '*) name=editing ;;
    *) name=usr_02 ;;
  esac
  [[ ! -r "$dir/$name.txt" ]] || files+=("$dir/$name.txt")
  [[ "${#files[@]}" -gt 0 ]] || return 1
  QCHEAT_DOC_QUERY="$query" QCHEAT_DOC_SOURCE="$tool runtime help" QCHEAT_DOC_TAGS="$tags" \
    LC_ALL=C awk -f "${QCHEAT_DOCS_DIR}/excerpt.awk" "${files[@]}"
}

qcheat_docs_git_topic() {
  local words=" $1 " candidate
  # Only built-in subcommands, never user aliases or external git-* commands.
  for candidate in restore switch checkout branch status diff add commit log show \
    stash reset clean merge rebase fetch pull push clone init remote tag rm mv config; do
    case "$words" in *" $candidate "*) printf '%s\n' "$candidate"; return ;; esac
  done
  case "$words" in
    *' staged '*|*' changes '*) printf 'diff\n' ;;
    *) printf 'git\n' ;;
  esac
}

# Read one exact man page rather than using MANPATH, which may refer to a
# different installation. mandoc reads stdin without writing formatted caches.
# man-db's local-file mode likewise never creates a cat page.
qcheat_docs_man_file() {
  local path="$1"
  [[ -r "$path" ]] || return 1
  if command -v mandoc >/dev/null 2>&1; then
    case "$path" in
      *.gz) gzip -cd -- "$path" ;;
      *) cat -- "$path" ;;
    esac | mandoc -T ascii
  elif [[ "$(uname -s)" == Linux ]] && command -v man >/dev/null 2>&1; then
    MANPAGER=cat PAGER=cat MANOPT='' MANWIDTH=80 MAN_KEEP_FORMATTING='' \
      GROFF_NO_SGR=1 LC_ALL=C man -l "$path"
  else
    return 1
  fi
}

qcheat_docs_git() {
  local executable="$1" query="$2" topic root page path excerpt='' usage status=0
  topic="$(qcheat_docs_git_topic "$query")"
  root="$("$executable" --man-path)" || root=''
  case "$topic" in git) page=git ;; *) page="git-$topic" ;; esac
  if [[ "$root" == /* ]]; then
    for path in "$root/man1/$page.1" "$root/man1/$page.1.gz"; do
      [[ -r "$path" ]] || continue
      excerpt="$(qcheat_docs_man_file "$path" | qcheat_docs_excerpt "$query" "$path")" || excerpt=''
      [[ -z "$excerpt" ]] || { printf '%s\n' "$excerpt"; return; }
    done
  fi

  # -h is built-in usage, not git help's configurable web/man viewer. Several
  # Git built-ins intentionally return 129 after printing their usage.
  if [[ "$topic" == git ]]; then
    usage="$("$executable" --no-pager -h 2>&1)" || status=$?
  else
    usage="$("$executable" --no-pager "$topic" -h 2>&1)" || status=$?
  fi
  [[ "$status" -eq 0 || "$status" -eq 129 ]] || return 1
  [[ "$usage" == usage:* ]] || return 1
  printf '%s\n' "$usage" | qcheat_docs_excerpt "$query" "installed git $topic -h"
}

qcheat_docs_gh() {
  local executable="$1" query="$2" words=" $2 " group='' action='' candidate
  local args=(help)
  case "$words" in
    *' pull request '*|*' pr '*) group='pr' ;;
    *' issue '*) group=issue ;;
    *' repo '*|*' repository '*) group=repo ;;
    *' release '*) group=release ;;
    *' workflow '*) group=workflow ;;
    *' run '*) group=run ;;
    *' auth '*|*' login '*) group=auth ;;
  esac
  for candidate in create list view status checkout merge close reopen clone fork \
    delete edit download upload enable disable login logout; do
    case "$words" in *" $candidate "*) action="$candidate"; break ;; esac
  done
  [[ -z "$group" ]] || args+=("$group")
  [[ -z "$group" || -z "$action" ]] || args+=("$action")
  # 'help' never dispatches an action or extension. Unsupported combinations
  # are discarded. Disable network notifications, telemetry and prompting.
  GH_PAGER=cat PAGER=cat GH_NO_UPDATE_NOTIFIER=1 GH_NO_EXTENSION_UPDATE_NOTIFIER=1 \
    GH_TELEMETRY=0 DO_NOT_TRACK=1 GH_PROMPT_DISABLED=1 GH_FORCE_TTY='' \
    NO_COLOR=1 CLICOLOR=0 CLICOLOR_FORCE=0 \
    "$executable" "${args[@]}" |
    qcheat_docs_excerpt "$query" "installed gh ${args[*]}"
}

qcheat_docs_system() {
  local tool="$1" executable="$2" query="$3" prefix page path excerpt=''
  prefix="${executable%/*}"
  prefix="${prefix%/*}"
  page="${executable##*/}"
  # /bin and /usr/bin share /usr/share/man. Other prefixes remain isolated,
  # including Homebrew's GNU commands on macOS (e.g. gcp or gnubin/cp).
  case "$executable" in /bin/*|/sbin/*) prefix=/usr ;; esac
  for path in "$prefix/share/man/man1/$page.1" "$prefix/share/man/man1/$page.1.gz"; do
    [[ -r "$path" ]] || continue
    excerpt="$(qcheat_docs_man_file "$path" | qcheat_docs_excerpt "$query" "$path")" || excerpt=''
    [[ -z "$excerpt" ]] || { printf '%s\n' "$excerpt"; return; }
  done

  # These commands reject --help or show help without acting on files. awk
  # implementations disagree on option parsing, so use only its manual.
  case "$tool" in
    cp|mv|grep|find|ls|mkdir|rm|chmod|chown|cat|head|tail|sort|uniq|wc|sed|tar)
      "$executable" --help | qcheat_docs_excerpt "$query" "installed $tool --help"
      ;;
    *) return 1 ;;
  esac
}

qcheat_docs_lookup() (
  # Isolate environment and failures from the CLI. No files are created.
  set -o pipefail
  export LC_ALL=C
  local query tool executable
  QCHEAT_DOCS_DIR="$(cd -- "${BASH_SOURCE[0]%/*}" && pwd -P)" || return 1
  query="$(printf '%s' "${1:0:2048}" | qcheat_docs_normalize)" || return 1
  tool="$(qcheat_docs_detect "$query")" || return 1
  executable="$(qcheat_docs_executable "$tool")" || return 1
  case "$tool" in
    vim|nvim) qcheat_docs_editor "$tool" "$executable" "$query" ;;
    git) qcheat_docs_git "$executable" "$query" ;;
    gh) qcheat_docs_gh "$executable" "$query" ;;
    *) qcheat_docs_system "$tool" "$executable" "$query" ;;
  esac
) 2>/dev/null
