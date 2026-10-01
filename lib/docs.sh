#!/usr/bin/env bash

# Read-only local documentation lookup. Help flags are fixed; discovered names
# require installed builtin/core-file validation. The question remains data.

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

# Rank official index references, then resolve literal tags only to core help
# basenames. The tags search field is never interpreted. All reads share the
# existing input budget; unresolved references retain the index as a source.
qcheat_docs_editor_index() {
  local dir="$1" query="$2" name
  local indexes=()
  for name in index quickref; do
    [[ ! -r "$dir/$name.txt" ]] || indexes+=("$dir/$name.txt")
  done
  [[ "${#indexes[@]}" -gt 0 ]] || return 1
  [[ ! -r "$dir/tags" ]] || indexes+=("$dir/tags")
  QCHEAT_DOC_QUERY="$query" QCHEAT_DOC_METADATA="$dir/tags" QCHEAT_DOC_TOPIC="${3:-usr_02}.txt" LC_ALL=C awk '
    function record(    i, rank) {
      if (ref == "") return
      rank = 0
      for (i = 1; i <= count; i++) {
        if (tolower(entry) ~ ("(^|[^a-z0-9_-])" terms[i]))
          rank += terms[i] == "word" || terms[i] == "chang" ? 4 : (terms[i] == "line" ? 2 : 1)
      }
      # Word edits favor operators accepting a motion over line-wide edits.
      if (editing && index(" " query " ", " word ") && index(entry, "{motion}")) rank += 2
      if (rank > score[ref]) {
        if (!(ref in order)) order[ref] = ++total
        score[ref] = rank; origin[ref] = source
        word_match[ref] = tolower(entry) ~ /(^|[^a-z0-9_-])word/
      }
      ref = ""
    }
    BEGIN {
      query = ENVIRON["QCHEAT_DOC_QUERY"]
      editing = query ~ /(^| )(edit|editing|change|delete|copy|yank|replace)( |$)/ &&
        query ~ /(^| )(word|line|character|text)( |$)/
      stop = " a an and are as at be can command current do for from how i in is it me of on or please qcheat the this to use using what with vim nvim neovim "
      n = split(query, words, /[^a-z0-9_-]+/)
      for (i = 1; i <= n && count < 24; i++) {
        if (length(words[i]) > 1 && !index(stop, " " words[i] " ") && !seen[words[i]]++) {
          terms[++count] = words[i]
          if (length(terms[count]) > 4) sub(/s$/, "", terms[count])
        }
      }
      # Editor-only vocabulary, also used by the excerpt scorer.
      if (query ~ /(^| )jump( |$)/) terms[++count] = "move"
      if (query ~ /(^| )edit(ing)?( |$)/) terms[++count] = "chang"
    }
    {
      bytes += length($0) + 1
      if (NR > 20000 || bytes > 1048576) next
      if (FILENAME == ENVIRON["QCHEAT_DOC_METADATA"]) {
        record()
        # Duplicate or unsafe mappings make this reference unresolvable.
        if ($1 in score) {
          if ($2 !~ /^(change|motion|windows|pattern|map|options|editing|usr_02|index|quickref)\.txt$/ ||
              (mapped[$1] != "" && mapped[$1] != $2)) invalid[$1] = 1
          else mapped[$1] = $2
        }
        next
      }
      if (FNR == 1) record()
      if (match($0, /[|][^|[:space:]]+[|]/)) {
        record()
        ref = substr($0, RSTART + 1, RLENGTH - 2)
        # Unqualified editing questions prefer Normal-mode references.
        if (length(ref) > 80 || (ref ~ /^:/ && ENVIRON["QCHEAT_DOC_TOPIC"] != "editing.txt" &&
            query !~ /(^| )(ex|colon|command-line)( |$)/) || (ref ~ /^i_/ && query !~ /(^| )insert( |$)/) ||
            (ref ~ /^v_/ && query !~ /(^| )visual( |$)/)) { ref = ""; next }
        entry = substr($0, RSTART + RLENGTH); continuation = 0
        # The quick-reference contents table combines unrelated columns.
        if (ref ~ /^Q_/ && entry ~ /[|][^|[:space:]]+[|]/) { ref = ""; next }
        source = FILENAME; sub(/^.*\//, "", source)
      } else if (ref != "" && $0 ~ /^[[:space:]]+[^[:space:]]/ && continuation++ < 2) {
        entry = entry " " $0
      } else record()
    }
    END {
      record()
      for (part = 1; part <= 3; part++) {
        best = 0; tag = ""
        for (candidate in score) {
          target = mapped[candidate] != "" ? mapped[candidate] : origin[candidate]
          # Keep unrelated index topics and unsafe metadata out of the result.
          if (invalid[candidate] || (target == "motion.txt" && index(" " query " ", " word ") &&
              !word_match[candidate]) || (target == "windows.txt" &&
              ENVIRON["QCHEAT_DOC_TOPIC"] != "windows.txt") || (editing &&
              target != "change.txt" && target != "motion.txt" && target != "index.txt" &&
              target != "quickref.txt" && target != ENVIRON["QCHEAT_DOC_TOPIC"]) || selected[target]) continue
          if (!used[candidate] && (score[candidate] > best ||
              (score[candidate] == best && best > 0 && order[candidate] < order[tag]))) {
            best = score[candidate]; tag = candidate
          }
        }
        if (tag == "") break
        used[tag] = 1
        target = mapped[tag] != "" ? mapped[tag] : origin[tag]
        selected[target] = 1
        print tag "\t" target "\t" (mapped[tag] != "" ? "*" tag "*" : "|" tag "|")
      }
    }' "${indexes[@]}"
}

qcheat_docs_editor() {
  local tool="$1" executable="$2" query="$3" dir name topic tag boost selected tags='' words=" $3 "
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
  case "$words" in
    *' window '*|*' split '*|*' buffer '*|*' tab '*) name=windows ;;
    *' search '*|*' pattern '*) name=pattern ;;
    *' map '*|*' mapping '*|*' keymap '*) name=map ;;
    *' option '*|*' set '*) name=options ;;
    *' file '*|*' save '*|*' quit '*) name=editing ;;
    *) name=usr_02 ;;
  esac
  topic="$name"
  # Keep established exact operator/text-object matches strongest. Otherwise
  # discover up to three references before filling the conservative shortlist.
  if [[ -z "$tags" ]]; then
    while IFS=$'\t' read -r tag name boost; do
      [[ -n "$tag" && -r "$dir/$name" ]] || continue
      case "$name" in
        change.txt|motion.txt|windows.txt|pattern.txt|map.txt|options.txt|editing.txt|usr_02.txt|index.txt|quickref.txt) ;;
        *) continue ;;
      esac
      tags="$tags $boost"
      selected=" ${files[*]-} "
      case "$selected" in *" $dir/$name "*) continue ;; esac
      [[ "${#files[@]}" -ge 3 ]] || files+=("$dir/$name")
    done < <(qcheat_docs_editor_index "$dir" "$query" "$topic" || :)
  fi

  for name in change motion "$topic"; do
    [[ -r "$dir/$name.txt" ]] || continue
    selected=" ${files[*]-} "
    case "$selected" in *" $dir/$name.txt "*) continue ;; esac
    [[ "${#files[@]}" -ge 3 ]] || files+=("$dir/$name.txt")
  done
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

# Git's verbose index also includes official scripts and non-command guides.
# Intersect it with the builtin enumeration before trusting any topic for -h.
qcheat_docs_git_builtins() (
  set -o pipefail
  local executable="$1"
  LC_ALL=C "$executable" --list-cmds=builtins | LC_ALL=C awk '
    {
      bytes += length($0) + 1
      if (NR > 20000 || bytes > 1048576) { bad = 1; next }
      for (i = 1; i <= NF; i++) {
        if ($i !~ /^[a-z][a-z0-9-]*$/ || length($i) > 64) bad = 1
        if (!seen[$i]++) {
          if (++count > 1024) bad = 1
          if (count <= 1024) names[count] = $i
        }
      }
    }
    END {
      if (bad || !count) exit 1
      for (i = 1; i <= count; i++) printf "%s ", names[i]
      print ""
    }'
)

qcheat_docs_git_discover() (
  set -o pipefail
  local executable="$1" query="$2" builtins
  builtins="$(qcheat_docs_git_builtins "$executable")" || return 1

  LC_ALL=C "$executable" help --all --verbose --no-external-commands --no-aliases |
    QCHEAT_DOC_QUERY="$query" QCHEAT_DOC_BUILTINS="$builtins" LC_ALL=C awk '
    BEGIN {
      n = split(ENVIRON["QCHEAT_DOC_BUILTINS"], names, /[[:space:]]+/)
      for (i = 1; i <= n; i++) builtin[names[i]] = 1
      query = " " ENVIRON["QCHEAT_DOC_QUERY"] " "
      stop = " a an and are as at be can command current do for from how i in is it me of on or please program qcheat the this to tool use using what with git "
      n = split(query, words, /[[:space:]]+/)
      for (i = 1; i <= n && count < 24; i++) {
        word = words[i]
        if (length(word) > 1 && !index(stop, " " word " ") && !seen[word]++) {
          # A plural query can match a singular word in the official index.
          if (length(word) > 4) sub(/s$/, "", word)
          terms[++count] = word
        }
      }
      working = index(query, " unstaged ") || index(query, " working tree ")
      unstage = index(query, " unstage ") || index(query, " unstaging ")
      restore = unstage || index(query, " discard ") || index(query, " discarding ")
      if (working && (index(query, " delete ") || index(query, " remove "))) restore = 1
      if (index(query, " untracked ")) restore = 0
      if (index(query, " delete ")) terms[++count] = "remove"
      if (unstage || index(query, " staged ")) terms[++count] = "index"
      # Here show is an ordinary verb; literal git show / git show HEAD stay direct.
      natural_show = index(query, " changes ") &&
        (working || index(query, " staged ") || index(query, " index "))
    }
    {
      # Always drain the producer, including malformed and oversized indexes.
      bytes += length($0) + 1
      if (NR > 20000 || bytes > 1048576) { bad = 1; next }
      if ($0 !~ /^[[:space:]]/) {
        if ($0 != "") porcelain = ($0 == "Main Porcelain Commands")
        next
      }
      line = $0
      sub(/^[[:space:]]+/, "", line)
      if (line == "") next
      name = line
      sub(/[[:space:]].*$/, "", name)
      if (name !~ /^[a-z][a-z0-9-]*$/ || length(name) > 64 ||
          line !~ /^[^[:space:]]+[[:space:]][[:space:]]+[^[:space:]]/) { bad = 1; next }
      if (!builtin[name]) next
      if (found[name]++) { bad = 1; next }
      sub(/^[^[:space:]]+[[:space:]]+/, "", line)
      description = tolower(line)
      direct = index(query, " " name " ") ? 100 : 0
      if (direct && index(query, " git " name " ")) direct += 100
      if (name == "show" && natural_show) direct = 0
      score = direct
      for (i = 1; i <= count; i++) {
        if (description ~ ("(^|[^a-z0-9_-])" terms[i])) score++
      }
      # Tiny terminology bridge, used only for selecting installed descriptions.
      if (working && index(description, "working tree")) score += 3
      if (restore && index(description, "restore")) score += 2
      if (restore && name == "restore") score += 6
      # Prefer the main Git command category when prose also matches helpers.
      if (score > 0 && porcelain) score++
      if (score > best) { best = score; topic = name; tied = 0 }
      else if (score > 0 && score == best) tied = 1
    }
    END {
      if (bad || !best || tied) exit 1
      print topic
    }'
)

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
  local discovered=0 builtins
  if topic="$(qcheat_docs_git_discover "$executable" "$query")"; then
    discovered=1
  else
    topic="$(qcheat_docs_git_topic "$query")"
  fi
  root="$("$executable" --man-path)" || root=''
  case "$topic" in git) page=git ;; *) page="git-$topic" ;; esac
  if [[ "$root" == /* ]]; then
    for path in "$root/man1/$page.1" "$root/man1/$page.1.gz"; do
      [[ -r "$path" ]] || continue
      excerpt="$(qcheat_docs_man_file "$path" | qcheat_docs_excerpt "$query $topic" "$path")" || excerpt=''
      [[ -z "$excerpt" ]] || { printf '%s\n' "$excerpt"; return; }
    done
  fi

  # A known fallback name may be absent in an older Git. Do not let -h
  # dispatch an alias or external command when that builtin is unavailable.
  if [[ "$topic" != git && "$discovered" -eq 0 ]]; then
    builtins="$(qcheat_docs_git_builtins "$executable")" || return 1
    case " $builtins " in *" $topic "*) ;; *) return 1 ;; esac
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
  printf '%s\n' "$usage" | qcheat_docs_excerpt "$query $topic" "installed git $topic -h"
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
