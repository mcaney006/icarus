#!/usr/bin/env bash
# Scans implementation sources for constructs that silently weaken a proof or a
# type-level guarantee. Each hit must be matched by an entry in tools/holes.allow.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
ALLOW="tools/holes.allow"
declare -a RULES=(
  'lean|*.lean|\bsorry\b|sorry'
  'lean|*.lean|\badmit\b|admit'
  'lean|*.lean|^\s*axiom\b|axiom'
  'lean|*.lean|native_decide|native_decide'
  'lean|*.lean|\bunsafe\b|unsafe'
  'fstar|*.fst|\badmit\b|admit'
  'fstar|*.fst|\bassume\b|assume'
  'fstar|*.fst|\bmagic\b|magic'
  'fstar|*.fst|\bunsafe_coerce\b|unsafe_coerce'
  'fstar|*.fst|--admit_smt_queries|admit_smt_queries'
  'idris|*.idr|believe_me|believe_me'
  'idris|*.idr|assert_total|assert_total'
  'idris|*.idr|assert_smaller|assert_smaller'
  'idris|*.idr|idris_crash|idris_crash'
  'idris|*.idr|^\s*partial\b|partial'
  'ats|*.dats|\$UN|$UN'
  'ats|*.dats|\$extfcall|$extfcall'
  'ats|*.dats|\$extval|$extval'
  'ats|*.dats|castvwtp|castvwtp'
  'ats|*.dats|\bprval\s+\(\)\s*=\s*\$|prval-cast'
)
allowed() { # file pattern-label
  [ -f "$ALLOW" ] || return 1
  grep -v '^#' "$ALLOW" | while IFS='|' read -r f p _; do
    case "$1" in $f) [ "$2" = "$p" ] && echo yes;; esac
  done | grep -q yes
}
hits=0; bad=0
for rule in "${RULES[@]}"; do
  IFS='|' read -r lang glob rx label <<<"$rule"
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    case "$f" in negative/*|*/build/*|*/.lake/*|*/out/*|*.checked) continue;; esac
    if grep -nE "$rx" "$f" >/dev/null 2>&1; then
      hits=$((hits+1))
      if allowed "$f" "$label"; then printf '  allowed   %-30s %s\n' "$f" "$label"
      else printf '  FORBIDDEN %-30s %s\n' "$f" "$label"; grep -nE "$rx" "$f" | head -3; bad=$((bad+1)); fi
    fi
  done < <(git ls-files "$lang/**/$glob" "$lang/$glob" 2>/dev/null | sort -u)
done
echo "audit-holes: $hits constructs found, $bad not allow-listed"
[ "$bad" -eq 0 ]
