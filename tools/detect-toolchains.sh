#!/usr/bin/env bash
# Resolves the four prover toolchains plus python, in a way the Makefile and CI
# can both consume. Detection never installs anything; see TOOLCHAINS.md.
set -u

BREW_BIN="/opt/homebrew/bin"
FSTAR_LOCAL="$HOME/.local/opt/fstar/bin/fstar.exe"

_first() { for c in "$@"; do if [ -n "$c" ] && [ -x "$c" ]; then printf '%s' "$c"; return 0; fi; done; }

resolve() {
  case "$1" in
    idris2)  _first "$(command -v idris2 2>/dev/null)" "$BREW_BIN/idris2" ;;
    patscc)  _first "$(command -v patscc 2>/dev/null)" "$BREW_BIN/patscc" ;;
    patsopt) _first "$(command -v patsopt 2>/dev/null)" "$BREW_BIN/patsopt" ;;
    fstar)   _first "$(command -v fstar.exe 2>/dev/null)" "$FSTAR_LOCAL" ;;
    python3) _first "$(command -v python3 2>/dev/null)" ;;
    lake|lean)
      local elan; elan="$(command -v elan 2>/dev/null || echo "$BREW_BIN/elan")"
      if [ -x "$elan" ]; then "$elan" which "$1" 2>/dev/null; fi ;;
  esac
}

version() {
  local p="$2"
  [ -z "$p" ] && { echo "-"; return; }
  case "$1" in
    idris2)  "$p" --version 2>/dev/null | head -1 ;;
    patscc)  "$p" --version 2>/dev/null | head -1 ;;
    patsopt) "$p" --version 2>/dev/null | head -1 ;;
    fstar)   "$p" --version 2>/dev/null | head -1 ;;
    lake)    "$p" --version 2>/dev/null | head -1 ;;
    lean)    "$p" --version 2>/dev/null | head -1 ;;
    python3) "$p" --version 2>/dev/null | head -1 ;;
  esac
}

TOOLS="lean lake fstar idris2 patscc patsopt python3"

case "${1:-table}" in
  --path)   resolve "$2" ;;
  --write)
    out="tools/.toolchains.env"; : > "$out"
    for t in $TOOLS; do p="$(resolve "$t")"; printf '%s=%s\n' "$(echo "$t"|tr a-z A-Z)" "$p" >> "$out"; done
    echo "wrote $out" ;;
  --require-all)
    miss=0
    for t in lean lake fstar idris2 patscc python3; do
      p="$(resolve "$t")"; [ -z "$p" ] && { echo "MISSING: $t"; miss=1; }
    done
    exit $miss ;;
  table|*)
    printf '%-10s %-8s %s\n' TOOL STATUS VERSION
    for t in $TOOLS; do
      p="$(resolve "$t")"
      if [ -n "$p" ]; then printf '%-10s %-8s %s\n' "$t" "ok" "$(version "$t" "$p")";
      else printf '%-10s %-8s %s\n' "$t" "MISSING" "-"; fi
    done ;;
esac
