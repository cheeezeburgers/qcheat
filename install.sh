#!/usr/bin/env bash

set -Eeuo pipefail

APP_NAME="qcheat"
VERSION="0.2.0"
DRY_RUN=false

# Write the literal variables to the user's shell configuration.
# shellcheck disable=SC2016
PATH_LINE='export PATH="$HOME/.local/bin:$PATH"'

usage() {
  cat <<'EOF'
qcheat installer

Usage:
  ./install.sh [options]

Options:
  --dry-run       Show what would be done without making changes
  -h, --help      Show this help
  -V, --version   Show version
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=true
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -V|--version)
      printf '%s %s\n' "$APP_NAME" "$VERSION"
      exit 0
      ;;
    *)
      printf 'Unknown option: %s\n\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac

  shift
done

BASE_MODEL="qwen2.5-coder:3b-instruct"
CUSTOM_MODEL="qwen-cheat"

INSTALL_DIR="${HOME}/.local/bin"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MODELFILE="${SCRIPT_DIR}/Modelfile"
QCHEAT_SOURCE="${SCRIPT_DIR}/bin/qcheat"

if [[ -t 1 ]]; then
  GREEN='\033[32m'
  RED='\033[31m'
  YELLOW='\033[33m'
  RESET='\033[0m'
else
  GREEN=''
  RED=''
  YELLOW=''
  RESET=''
fi

ok() {
  printf '%b[ OK ]%b %s\n' "$GREEN" "$RESET" "$*"
}

fail() {
  printf '%b[ X ]%b %s\n' "$RED" "$RESET" "$*" >&2
}

warn() {
  printf '%b[ ! ]%b %s\n' "$YELLOW" "$RESET" "$*"
}

info() {
  printf '[ .. ] %s\n' "$*"
}

die() {
  fail "$*"
  exit 1
}

run() {
  if [[ "$DRY_RUN" == true ]]; then
    printf '[DRY]'
    printf ' %q' "$@"
    printf '\n'
  else
    "$@"
  fi
}

append_block() {
  local file="$1"
  local content="$2"

  if [[ "$DRY_RUN" == true ]]; then
    printf '[DRY] append to %s:\n%s\n' "$file" "$content"
  else
    printf '\n%s\n' "$content" >> "$file"
  fi
}

trap 'fail "Installation stopped near line ${LINENO}."' ERR

[[ -f "$MODELFILE" ]] ||
  die "Modelfile not found: $MODELFILE"

[[ -f "$QCHEAT_SOURCE" ]] ||
  die "qcheat executable not found: $QCHEAT_SOURCE"


# ---------------------------------------------------------
# OS
# ---------------------------------------------------------

case "$(uname -s)" in
  Darwin)
    OS="macos"
    ok "Operating system: macOS"
    ;;

  Linux)
    OS="linux"
    ok "Operating system: Linux"
    ;;

  *)
    die "Unsupported operating system: $(uname -s). qcheat currently supports macOS and Linux."
    ;;
esac


# ---------------------------------------------------------
# Homebrew on macOS
# ---------------------------------------------------------

if [[ "$OS" == "macos" ]]; then
  if ! command -v brew >/dev/null 2>&1; then
    die "Homebrew is required on macOS. Install Homebrew, then run ./install.sh again."
  fi

  brew_version="$(brew --version)"
  ok "Homebrew found: ${brew_version%%$'\n'*}"

  if [[ "$(uname -m)" == "arm64" &&
        "$(brew --prefix)" == "/usr/local"* ]]; then
    warn "This looks like Intel/Rosetta Homebrew on Apple Silicon."
    warn "Packages may compile from source. Native Homebrew normally uses /opt/homebrew."
  fi
fi


# ---------------------------------------------------------
# Ollama
# ---------------------------------------------------------

install_ollama() {
  if command -v ollama >/dev/null 2>&1; then
    ollama_version="$(ollama --version 2>/dev/null || true)"

    if [[ -n "$ollama_version" ]]; then
      ok "Ollama already installed: ${ollama_version%%$'\n'*}"
    else
      ok "Ollama already installed: version unknown"
    fi

    return
  fi

  info "Installing Ollama..."

  if [[ "$OS" == "macos" ]]; then
    run brew install ollama
  else
    command -v curl >/dev/null 2>&1 ||
      die "curl is required to install Ollama on Linux."

    if [[ "$DRY_RUN" == true ]]; then
      printf '[DRY] curl -fsSL https://ollama.com/install.sh | sh\n'
    else
      curl -fsSL https://ollama.com/install.sh | sh
    fi
  fi

  if [[ "$DRY_RUN" == true ]]; then
    return
  fi

  command -v ollama >/dev/null 2>&1 ||
    die "Ollama installation completed, but 'ollama' is not on PATH."

  ok "Ollama installed"
}


# ---------------------------------------------------------
# mdcat
# ---------------------------------------------------------

install_mdcat() {
  if command -v mdcat >/dev/null 2>&1; then
    mdcat_version="$(mdcat --version 2>/dev/null || true)"

    if [[ -n "$mdcat_version" ]]; then
      ok "mdcat already installed: ${mdcat_version%%$'\n'*}"
    else
      ok "mdcat already installed: version unknown"
    fi

    return
  fi

  info "Installing mdcat..."

  if [[ "$DRY_RUN" == true && "$OS" == "linux" ]] &&
     ! command -v brew >/dev/null 2>&1; then
    info "Package availability will be checked during installation; preview assumes the first available package manager provides mdcat."
  fi

  if [[ "$OS" == "macos" ]]; then

    run brew install mdcat

  elif command -v brew >/dev/null 2>&1; then

    run brew install mdcat

  elif command -v apt-get >/dev/null 2>&1 &&
       { [[ "$DRY_RUN" == true ]] || apt-cache show mdcat >/dev/null 2>&1; }; then

    run sudo apt-get update
    run sudo apt-get install -y mdcat

  elif command -v dnf >/dev/null 2>&1 &&
       { [[ "$DRY_RUN" == true ]] || dnf info mdcat >/dev/null 2>&1; }; then

    run sudo dnf install -y mdcat

  elif command -v pacman >/dev/null 2>&1 &&
       { [[ "$DRY_RUN" == true ]] || pacman -Si mdcat >/dev/null 2>&1; }; then

    run sudo pacman -S --needed --noconfirm mdcat

  elif command -v cargo >/dev/null 2>&1; then

    warn "No packaged mdcat was found; Cargo will compile it from source."
    run cargo install mdcat --locked

  else

    die "Could not install mdcat automatically. Install mdcat (or Homebrew/Rust Cargo) and re-run ./install.sh."

  fi

  if [[ "$DRY_RUN" == true ]]; then
    return
  fi

  command -v mdcat >/dev/null 2>&1 ||
    die "mdcat installation completed, but 'mdcat' is not on PATH."

  ok "mdcat installed"
}


# ---------------------------------------------------------
# Ollama service
# ---------------------------------------------------------

ensure_ollama_server() {
  if command -v ollama >/dev/null 2>&1 &&
     ollama list >/dev/null 2>&1; then
    ok "Ollama service is running"
    return
  fi

  if [[ "$DRY_RUN" == true ]]; then
    printf '[DRY] start Ollama service if necessary\n'
    return
  fi

  info "Starting Ollama service..."

  if [[ "$OS" == "macos" ]] &&
     brew list --formula ollama >/dev/null 2>&1; then

    brew services start ollama >/dev/null

  elif [[ "$OS" == "linux" ]] &&
       command -v systemctl >/dev/null 2>&1 &&
       systemctl list-unit-files ollama.service >/dev/null 2>&1; then

    sudo systemctl enable --now ollama >/dev/null

  else

    nohup ollama serve \
      >"${TMPDIR:-/tmp}/qcheat-ollama.log" 2>&1 &

  fi

  for _ in {1..20}; do
    if ollama list >/dev/null 2>&1; then
      ok "Ollama service is running"
      return
    fi

    sleep 1
  done

  die "Ollama did not start. Try 'ollama serve' manually, then re-run ./install.sh."
}


# ---------------------------------------------------------
# qcheat executable
# ---------------------------------------------------------

install_qcheat_command() {
  run mkdir -p "$INSTALL_DIR"

  run install -m 0755 \
    "$QCHEAT_SOURCE" \
    "$INSTALL_DIR/qcheat"

  if [[ "$DRY_RUN" == true ]]; then
    info "Would install command: $INSTALL_DIR/qcheat"
  else
    ok "Installed command: $INSTALL_DIR/qcheat"
  fi
}


# ---------------------------------------------------------
# Shell rc
# ---------------------------------------------------------

detect_rc_file() {
  case "$(basename "${SHELL:-}")" in
    zsh)
      printf '%s\n' "$HOME/.zshrc"
      ;;

    bash)
      printf '%s\n' "$HOME/.bashrc"
      ;;

    *)
      printf '%s\n' ""
      ;;
  esac
}


# ---------------------------------------------------------
# ~/.local/bin PATH
# ---------------------------------------------------------

ensure_local_bin_on_path() {
  case ":$PATH:" in
    *":$INSTALL_DIR:"*)
      ok "$INSTALL_DIR is already on PATH"
      return
      ;;
  esac

  local rc_file
  rc_file="$(detect_rc_file)"

  warn "$INSTALL_DIR is not currently on PATH."

  if [[ -z "$rc_file" ]]; then
    warn "Unknown shell '${SHELL:-unknown}'. Add $INSTALL_DIR to PATH manually."
    printf '  %s\n' "$PATH_LINE"
    return
  fi

  printf 'Add ~/.local/bin to PATH in %s? [Y/n] ' "$rc_file"
  read -r answer

  case "${answer:-Y}" in
    [Yy]*)

      if ! grep -Fq \
        "$PATH_LINE" \
        "$rc_file" 2>/dev/null; then

        append_block "$rc_file" "# qcheat
$PATH_LINE"

        if [[ "$DRY_RUN" == true ]]; then
          info "Would add ~/.local/bin to PATH in $rc_file"
        else
          ok "Added ~/.local/bin to PATH in $rc_file"
        fi
      else
        ok "PATH entry already present in $rc_file"
      fi
      ;;

    *)
      warn "Skipped PATH change."
      if [[ "$DRY_RUN" == true ]]; then
        info "qcheat would be installed at $INSTALL_DIR/qcheat."
      else
        warn "qcheat is installed at $INSTALL_DIR/qcheat."
      fi
      ;;
  esac
}


# ---------------------------------------------------------
# Optional short alias
# ---------------------------------------------------------

name_in_rc() {
  local name="$1"
  local rc_file="$2"

  [[ -f "$rc_file" ]] || return 1

  grep -Eq \
    "^[[:space:]]*alias[[:space:]]+${name}=|^[[:space:]]*${name}[[:space:]]*\\(\\)[[:space:]]*\\{" \
    "$rc_file"
}


name_is_used() {
  local name="$1"
  local rc_file="$2"

  if command -v "$name" >/dev/null 2>&1; then
    return 0
  fi

  name_in_rc "$name" "$rc_file"
}


prompt_for_alias() {
  local rc_file
  rc_file="$(detect_rc_file)"

  if [[ -z "$rc_file" ]]; then
    warn "Skipping optional alias: only zsh and bash rc files are handled automatically."
    return
  fi

  printf "Add a shorter alias for qcheat (default: q)? [y/N] "
  read -r answer

  [[ "${answer:-N}" =~ ^[Yy]$ ]] || return 0

  local alias_name="q"

  while true; do

    if [[ ! "$alias_name" =~ ^[A-Za-z_][A-Za-z0-9_-]*$ ]]; then

      warn "Alias names may contain letters, numbers, '_' and '-', and must not start with a number."

    elif [[ "$alias_name" == "qcheat" ]]; then

      warn "'qcheat' is already the installed command. Choose another shortcut."

    elif name_is_used "$alias_name" "$rc_file"; then

      warn "'$alias_name' already appears to be used as a command, alias, or function."

    else

      break

    fi

    printf "Enter a different alias (blank to skip): "
    read -r alias_name

    if [[ -z "$alias_name" ]]; then
      warn "Skipped alias."
      return
    fi

  done

  append_block "$rc_file" \
"# qcheat shortcut
alias ${alias_name}='qcheat'"

  if [[ "$DRY_RUN" == true ]]; then
    info "Would add alias '$alias_name' -> qcheat to $rc_file"
  else
    ok "Added alias '$alias_name' -> qcheat to $rc_file"
  fi
}


# ---------------------------------------------------------
# Install
# ---------------------------------------------------------

install_ollama
install_mdcat
ensure_ollama_server


info "Pulling $BASE_MODEL..."

run ollama pull "$BASE_MODEL"

if [[ "$DRY_RUN" == true ]]; then
  info "Would prepare base model: $BASE_MODEL"
else
  ok "Base model ready: $BASE_MODEL"
fi


info "Building $CUSTOM_MODEL..."

run ollama create "$CUSTOM_MODEL" -f "$MODELFILE"

if [[ "$DRY_RUN" == true ]]; then
  info "Would build custom model: $CUSTOM_MODEL"
else
  ok "Custom model ready: $CUSTOM_MODEL"
fi


install_qcheat_command

ensure_local_bin_on_path

prompt_for_alias


# ---------------------------------------------------------
# Done
# ---------------------------------------------------------

printf '\n'

if [[ "$DRY_RUN" == true ]]; then
  printf '[DRY] Dry run completed. No installation changes were made.\n'
else
  ok "qcheat $VERSION installed successfully."

  printf '\nTry it with:\n'
  printf '  qcheat copy a file\n'
  printf '  qcheat vim delete to end of line\n'
  printf '  qcheat git create and switch to a new branch\n'

  printf '\nIf PATH or an alias was added, open a new shell or source your shell rc file first.\n'
fi
