#!/usr/bin/env bash
set -u

BREW_BIN="/opt/homebrew/bin"
FSTAR_LOCAL="$HOME/.local/opt/fstar/bin/fstar.exe"
TOOLS=(lean lake fstar idris2 patscc patsopt python3 ruff)
REQUIRED=(lean lake fstar idris2 patscc python3 ruff)

first_executable() {
  local candidate
  for candidate in "$@"; do
    if [ -n "$candidate" ] && [ -x "$candidate" ]; then printf '%s' "$candidate"; return 0; fi
  done
  return 1
}

resolve() {
  case "$1" in
    idris2|patscc|patsopt|ruff) first_executable "$(command -v "$1" 2>/dev/null)" "$BREW_BIN/$1" ;;
    fstar) first_executable "$(command -v fstar.exe 2>/dev/null)" "$FSTAR_LOCAL" ;;
    python3)
      local candidate
      for candidate in "$(command -v python3 2>/dev/null)" "$BREW_BIN/python3"; do
        if [ -n "$candidate" ] && [ -x "$candidate" ] && "$candidate" -c 'import numpy' 2>/dev/null; then
          printf '%s' "$candidate"; return 0
        fi
      done
      return 1 ;;
    lake|lean)
      local elan
      elan="$(first_executable "$(command -v elan 2>/dev/null)" "$BREW_BIN/elan")" && "$elan" which "$1" 2>/dev/null ;;
  esac
}

version() {
  case "$1" in
    python3) "$2" -c 'import sys, numpy; print("Python", sys.version.split()[0], "numpy", numpy.__version__)' ;;
    *) "$2" --version 2>/dev/null | head -1 ;;
  esac
}

case "${1:-table}" in
  --path) resolve "$2" ;;
  --write)
    for tool in "${TOOLS[@]}"; do printf '%s=%s\n' "$(tr '[:lower:]' '[:upper:]' <<<"$tool")" "$(resolve "$tool")"; done >tools/.toolchains.env
    echo "wrote tools/.toolchains.env" ;;
  --require-all)
    missing=0
    for tool in "${REQUIRED[@]}"; do
      [ -n "$(resolve "$tool")" ] || { echo "MISSING: $tool"; missing=1; }
    done
    exit "$missing" ;;
  *)
    printf '%-10s %-8s %s\n' TOOL STATUS VERSION
    for tool in "${TOOLS[@]}"; do
      if path="$(resolve "$tool")" && [ -n "$path" ]; then printf '%-10s %-8s %s\n' "$tool" ok "$(version "$tool" "$path")"
      else printf '%-10s %-8s %s\n' "$tool" MISSING -; fi
    done ;;
esac
