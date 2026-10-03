# Toolchains

icarus pins four provers plus Python. `make toolchains` (or
`bash tools/detect-toolchains.sh`) prints the live status table; `--require-all`
is the strict gate CI uses.

| Toolchain | Pinned / minimum | How this machine obtained it | Invoked as |
|-----------|------------------|------------------------------|------------|
| Lean 4    | `leanprover/lean4:v4.34.1` (Lake 5.0.0) | `brew install elan-init` → `elan default stable` | `elan which lake`/`lean`; pinned by `lean/lean-toolchain` |
| F\*       | `2026.09.27` (Darwin_arm64) | prebuilt release tarball → `~/.local/opt/fstar` | `~/.local/opt/fstar/bin/fstar.exe` |
| Idris 2   | `0.8.0`          | `brew install idris2` | `idris2` |
| ATS2 / Postiats | `0.4.2`    | `brew install ats2-postiats` | `patsopt`, `patscc` |
| Python    | 3.9+; numpy for fixture generation and the experiment (tested 3.14.7 with numpy 2.5.3; reference and cross-check also on 3.9.6) | Homebrew | first `python3` on `PATH` that imports numpy, else `/opt/homebrew/bin/python3` |
| OCaml     | `5.3.0` in opam switch `icarus-fstar` | `brew install opam`, then `bash tools/setup-ocaml-switch.sh` | `opam exec --switch=icarus-fstar` (F\* extraction only) |

## Notes

- **F\* bundles its own Z3** (4.8.5 / 4.13.3 / 4.15.3 under
  `lib/fstar/`); no separate Z3 is required and the system Z3 version is
  irrelevant to verification.
- **ATS `patscc`** is a wrapper around the system C compiler, so
  `patscc --version` reports clang; the ATS version comes from `patsopt
  --version` (0.4.2).
- Nothing here is installed into the repo or the global shell profile. The F\*
  tarball lives under `~/.local/opt`; the detection script finds it there or on
  `PATH`.
- Floating dependencies are avoided: Lean is pinned by `lean-toolchain`, F\* by
  an exact release tag, the Homebrew formulas by the versions above.

## Reproducing from scratch

```sh
brew install idris2 ats2-postiats elan-init
elan default stable            # installs leanprover/lean4:v4.34.1
curl -sL -o /tmp/fstar.tgz \
  https://github.com/FStarLang/FStar/releases/download/v2026.09.27/fstar-v2026.09.27-Darwin-arm64.tar.gz
mkdir -p ~/.local/opt && tar xzf /tmp/fstar.tgz -C ~/.local/opt/
brew install opam && opam init --bare --yes && bash tools/setup-ocaml-switch.sh
python3 -m pip install numpy      # only fixture generation and the experiment need it
bash tools/detect-toolchains.sh   # expect all 'ok'
make ci
```

`.github/workflows/ci.yml` runs the same steps on a macOS arm64 runner.
