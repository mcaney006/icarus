#!/usr/bin/env bash
set -euo pipefail
switch=icarus-fstar
opam switch list --short 2>/dev/null | grep -qx "$switch" || opam switch create "$switch" ocaml-base-compiler.5.3.0 --yes
opam install --switch="$switch" --yes batteries pprint ppx_deriving ppx_deriving_yojson stdint yojson zarith
echo "switch $switch ready"
