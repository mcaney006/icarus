#!/usr/bin/env bash
# Runs every negative/ program through its language's checker and requires it to
# FAIL with the documented message. Each program has a well-typed twin under
# ok/ that must succeed, so a failure cannot be an unrelated harness problem.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DETECT="bash $ROOT/tools/detect-toolchains.sh"
fail=0; total=0
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

expect_of() { grep -m1 '^-- EXPECT:\|^(\* EXPECT:\|^// EXPECT:' "$1" | sed 's/^[^:]*EXPECT: *//; s/ *\*)$//'; }

report() { # name status detail
  total=$((total+1))
  if [ "$2" = ok ]; then printf '  %-34s rejected as expected\n' "$1"
  else printf '  %-34s FAIL %s\n' "$1" "$3"; fail=$((fail+1)); fi
}

idris_check() { # stage the program as <module path>.idr beside the library modules
  local mod rel root; mod="$(grep -m1 '^module ' "$1" | awk '{print $2}')"
  rel="$(echo "$mod" | tr . /).idr"; root="$TMP/idris-src-$RANDOM"
  mkdir -p "$root/$(dirname "$rel")"; cp -R "$ROOT/idris/src/Icarus" "$root/Icarus"
  cp "$1" "$root/$rel"
  ( cd "$root" && "$IDRIS" --check --source-dir "$root" --build-dir "$TMP/idris-build" "$root/$rel" 2>&1 )
}

if IDRIS="$($DETECT --path idris2)" && [ -n "$IDRIS" ] && [ -d "$ROOT/negative/idris" ]; then
  echo "[idris] negative programs"
  ( cd "$ROOT/idris" && "$IDRIS" --build icarus.ipkg >/dev/null 2>&1 )
  for f in "$ROOT"/negative/idris/*.idr; do
    n="$(basename "$f" .idr)"; pat="$(expect_of "$f")"
    out="$(idris_check "$f")"; rc=$?
    twin="$(idris_check "$ROOT/negative/idris/ok/$n.idr")"; trc=$?
    if [ $rc -eq 0 ]; then report "idris/$n" bad "compiled but must be rejected"
    elif [ $trc -ne 0 ]; then report "idris/$n" bad "well-typed twin failed: $(echo "$twin" | head -2 | tr '\n' ' ')"
    elif ! echo "$out" | grep -Eq "$pat"; then report "idris/$n" bad "rejected, but message did not match /$pat/"
    else report "idris/$n" ok; fi
  done
else echo "[idris] SKIP"; fi

echo "negative: $total programs, $fail failures"
[ $fail -eq 0 ]
