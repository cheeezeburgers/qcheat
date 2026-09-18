#!/usr/bin/env bash

set -Eeuo pipefail

APP_NAME="qcheat"
VERSION="0.1.0"

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

  ok "Homebrew found: $(brew --version | head -n 1)"

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
    ok "Ollama already installed: $(ollama --version 2>/dev/null | head -n 1 || printf 'version unknown')"
    return
  fi

  info "Installing Ollama..."

  if [[ "$OS" == "macos" ]]; then
    brew install ollama
  else
    command -v curl >/dev/null 2>&1 ||
      die "curl is required to install Ollama on Linux."

    curl -fsSL https://ollama.com/install.sh | sh
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
    ok "mdcat already installed: $(mdcat --version 2>/dev/null | head -n 1 || printf 'version unknown')"
    return
  fi

  info "Installing mdcat..."

  if [[ "$OS" == "macos" ]]; then

    brew install mdcat

  elif command -v brew >/dev/null 2>&1; then

    brew install mdcat

  elif command -v apt-get >/dev/null 2>&1 &&
       apt-cache show mdcat >/dev/null 2>&1; then

    sudo apt-get update
    sudo apt-get install -y mdcat

  elif command -v dnf >/dev/null 2>&1 &&
       dnf info mdcat >/dev/null 2>&1; then

    sudo dnf install -y mdcat

  elif command -v pacman >/dev/null 2>&1 &&
       pacman -Si mdcat >/dev/null 2>&1; then

    sudo pacman -S --needed --noconfirm mdcat

  elif command -v cargo >/dev/null 2>&1; then

    warn "No packaged mdcat was found; Cargo will compile it from source."
    cargo install mdcat --locked

  else

    die "Could not install mdcat automatically. Install mdcat (or Homebrew/Rust Cargo) and re-run ./install.sh."

  fi

  command -v mdcat >/dev/null 2>&1 ||
    die "mdcat installation completed, but 'mdcat' is not on PATH."

  ok "mdcat installed"
}


# ---------------------------------------------------------
# Ollama service
# ---------------------------------------------------------

ensure_ollama_server() {
  if ollama list >/dev/null 2>&1; then
    ok "Ollama service is running"
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
  mkdir -p "$INSTALL_DIR"

  install -m 0755 \
    "$QCHEAT_SOURCE" \
    "$INSTALL_DIR/qcheat"

  ok "Installed command: $INSTALL_DIR/qcheat"
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
    return
  fi

  printf 'Add ~/.local/bin to PATH in %s? [Y/n] ' "$rc_file"
  read -r answer

  case "${answer:-Y}" in
    [Yy]*)

      touch "$rc_file"

      if ! grep -Fq \
        'export PATH="$HOME/.local/bin:$PATH"' \
        "$rc_file"; then

        {
          printf '\n# qcheat\n'
          printf 'export PATH="$HOME/.local/bin:$PATH"\n'
        } >> "$rc_file"

      fi

      ok "Added ~/.local/bin to PATH in $rc_file"
      ;;

    *)
      warn "Skipped PATH change."
      warn "qcheat is installed at $INSTALL_DIR/qcheat."
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

  [[ "${answer:-N}" =~ ^[Yy]$ ]] || return

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

  touch "$rc_file"

  {
    printf '\n# qcheat shortcut\n'
    printf "alias %s='qcheat'\n" "$alias_name"
  } >> "$rc_file"

  ok "Added alias '$alias_name' -> qcheat to $rc_file"
}


# ---------------------------------------------------------
# Install
# ---------------------------------------------------------

install_ollama
install_mdcat
ensure_ollama_server


info "Pulling $BASE_MODEL..."

ollama pull "$BASE_MODEL"

ok "Base model ready: $BASE_MODEL"


info "Building $CUSTOM_MODEL..."

ollama create "$CUSTOM_MODEL" -f "$MODELFILE"

ok "Custom model ready: $CUSTOM_MODEL"


install_qcheat_command

ensure_local_bin_on_path

prompt_for_alias


# ---------------------------------------------------------
# Done
# ---------------------------------------------------------

printf '\n'

ok "qcheat $VERSION installed successfully."

printf '\nTry it with:\n'
printf '  qcheat copy a file\n'
printf '  qcheat vim delete to end of line\n'
printf '  qcheat git create and switch to a new branch\n'

printf '\nIf PATH or an alias was added, open a new shell or source your shell rc file first.\n'
