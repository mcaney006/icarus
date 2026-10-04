#!/usr/bin/env bash
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DETECT="bash $ROOT/tools/detect-toolchains.sh"
SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT
total=0
failures=0

expected() { awk -F'\t' -v key="$1" '$1 == key { print $2; exit }' "$ROOT/negative/expected"; }

report() {
  total=$((total + 1))
  if [ -z "$2" ]; then printf '  %-34s rejected as expected\n' "$1"
  else printf '  %-34s FAIL %s\n' "$1" "$2"; failures=$((failures + 1)); fi
}

first_lines() { head -2 | tr '\n' ' '; }

verdict() {
  local key="$1" rejected_rc="$2" output="$3" twin_rc="$4" twin_output="$5" pattern
  pattern="$(expected "$key")"
  if [ -z "$pattern" ]; then report "$key" "no expected message in negative/expected"
  elif [ "$rejected_rc" -eq 0 ]; then report "$key" "accepted but must be rejected"
  elif [ "$twin_rc" -ne 0 ]; then report "$key" "well-typed twin failed: $(first_lines <<<"$twin_output")"
  elif ! grep -Eq "$pattern" <<<"$output"; then report "$key" "rejected, but message did not match /$pattern/: $(first_lines <<<"$output")"
  else report "$key" ""; fi
}

suite() {
  local lang="$1" extension="$2" checker="$3" program name output rc twin trc
  echo "[$lang] negative programs"
  for program in "$ROOT/negative/$lang"/*."$extension"; do
    name="$(basename "$program" ".$extension")"
    output="$("$checker" "$program")"; rc=$?
    twin="$("$checker" "$ROOT/negative/$lang/ok/$name.$extension")"; trc=$?
    verdict "$lang/$name" "$rc" "$output" "$trc" "$twin"
  done
}

idris_check() {
  local module relative root
  module="$(awk '/^module / { print $2; exit }' "$1")"
  relative="${module//.//}.idr"
  root="$SCRATCH/idris-$RANDOM"
  mkdir -p "$root/$(dirname "$relative")"
  cp -R "$ROOT/idris/src/Icarus" "$root/Icarus"
  cp "$1" "$root/$relative"
  (cd "$root" && "$IDRIS" --check --source-dir "$root" --build-dir "$SCRATCH/idris-build" "$root/$relative" 2>&1)
}

fstar_check() {
  local work="$SCRATCH/fstar-$RANDOM"
  mkdir -p "$work/cache" "$work/src"
  cp "$ROOT"/fstar/out/cache/*.checked "$work/cache/"
  cp "$1" "$work/src/"
  (cd "$work" && "$FSTAR" --include "$ROOT/fstar/src" --include "$work/src" --cache_checked_modules \
    --cache_dir "$work/cache" "$work/src/$(basename "$1")" 2>&1)
}

fstar_budget_mutation() {
  local work="$SCRATCH/mutation" output rc
  mkdir -p "$work/cache"
  sed 's/| Estimate -> 220/| Estimate -> 400/' "$ROOT/fstar/src/Icarus.Timing.fst" >"$work/Icarus.Timing.fst"
  cmp -s "$work/Icarus.Timing.fst" "$ROOT/fstar/src/Icarus.Timing.fst" && { report fstar/budget_overflow "mutation did not apply"; return; }
  output="$(cd "$work" && "$FSTAR" --cache_dir "$work/cache" "$work/Icarus.Timing.fst" 2>&1)"; rc=$?
  verdict fstar/budget_overflow "$rc" "$output" 0 ""
}

ats_check() {
  local work="$SCRATCH/ats-$RANDOM"
  mkdir -p "$work"
  cp "$ROOT"/ats/src/*.sats "$work/"
  cp "$1" "$work/"
  (cd "$work" && "$PATSCC" -tcats "$(basename "$1")" 2>&1)
}

lean_check() { (cd "$ROOT/lean" && "$LAKE" env lean "$1" 2>&1); }

if IDRIS="$($DETECT --path idris2)" && [ -n "$IDRIS" ]; then
  (cd "$ROOT/idris" && "$IDRIS" --build icarus.ipkg >/dev/null 2>&1)
  suite idris idr idris_check
else echo "[idris] SKIP"; fi

if FSTAR="$($DETECT --path fstar)" && [ -n "$FSTAR" ] && [ -d "$ROOT/fstar/out/cache" ]; then
  suite fstar fst fstar_check
  fstar_budget_mutation
else echo "[fstar] SKIP (toolchain or fstar/out/cache missing; run make -C fstar)"; fi

if PATSCC="$($DETECT --path patscc)" && [ -n "$PATSCC" ]; then
  suite ats dats ats_check
else echo "[ats] SKIP"; fi

if LAKE="$($DETECT --path lake)" && [ -n "$LAKE" ]; then
  (cd "$ROOT/lean" && "$LAKE" build >/dev/null 2>&1)
  suite lean lean lean_check
else echo "[lean] SKIP"; fi

echo "negative: $total programs, $failures failures"
[ "$failures" -eq 0 ]
