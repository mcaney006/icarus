#!/usr/bin/env bash
set -u
cd "$(dirname "$0")/.."

RULES=(
  'lean|lean|\bsorry\b|sorry'
  'lean|lean|\badmit\b|admit'
  'lean|lean|^\s*axiom\b|axiom'
  'lean|lean|native_decide|native_decide'
  'lean|lean|\bunsafe\b|unsafe'
  'fstar|fst|\badmit\b|admit'
  'fstar|fst|\bassume\b|assume'
  'fstar|fst|\bmagic\b|magic'
  'fstar|fst|\bunsafe_coerce\b|unsafe_coerce'
  'fstar|fst|--admit_smt_queries|admit_smt_queries'
  'idris|idr|believe_me|believe_me'
  'idris|idr|assert_total|assert_total'
  'idris|idr|assert_smaller|assert_smaller'
  'idris|idr|idris_crash|idris_crash'
  'idris|idr|^\s*partial\b|partial'
  'ats|dats|\$UN|$UN'
  'ats|dats|\$extfcall|$extfcall'
  'ats|dats|\$extval|$extval'
  'ats|dats|castvwtp|castvwtp'
  'ats|dats|\bprval\s+\(\)\s*=\s*\$|prval-cast'
)

allowed() { awk -F'|' -v file="$1" -v label="$2" '$1 == file && $2 == label { found = 1 } END { exit !found }' tools/holes.allow; }

hits=0
forbidden=0
for rule in "${RULES[@]}"; do
  IFS='|' read -r tree extension pattern label <<<"$rule"
  while IFS= read -r file; do
    grep -qE -e "$pattern" "$file" || continue
    hits=$((hits + 1))
    if allowed "$file" "$label"; then
      printf '  allowed   %-30s %s\n' "$file" "$label"
    else
      printf '  FORBIDDEN %-30s %s\n' "$file" "$label"
      grep -nE -e "$pattern" "$file" | head -3
      forbidden=$((forbidden + 1))
    fi
  done < <(git ls-files "$tree/*.$extension" "$tree/**/*.$extension" | sort -u)
done
echo "audit-holes: $hits constructs found, $forbidden not allow-listed"
[ "$forbidden" -eq 0 ]
