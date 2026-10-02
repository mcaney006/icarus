#!/usr/bin/env bash
# Creates the dedicated opam switch used to compile F*-extracted OCaml. The F*
# release links against a prebuilt runtime built with OCaml 5.3.0, and native
# OCaml libraries only link with the exact compiler that built them, so a
# separate 5.3.0 switch is required. Nothing here touches any existing switch.
set -euo pipefail
SW=icarus-fstar
if opam switch list --short 2>/dev/null | grep -qx "$SW"; then echo "switch $SW exists"; else
  opam switch create "$SW" ocaml-base-compiler.5.3.0 --yes
fi
opam install --switch="$SW" --yes batteries pprint ppx_deriving ppx_deriving_yojson stdint yojson zarith
echo "switch $SW ready"
