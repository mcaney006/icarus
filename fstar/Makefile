# Verify every module, extract the executable path to OCaml, and link it against
# the F* runtime in the dedicated opam switch (see ../tools/setup-ocaml-switch.sh).
FSTAR ?= fstar.exe
OPAM_SWITCH ?= icarus-fstar
FSTAR_HOME ?= $(HOME)/.local/opt/fstar
MODULES := Health Mode Sat Vote Counter Timing Ring Wire Decide SatCheck
EXTRACT := Health Mode Wire Decide Sat SatCheck
DECIDE_ML := Health Mode Wire Decide
SAT_ML := Wire Sat SatCheck
CACHE := out/cache
FLAGS := --include src --cache_checked_modules --cache_dir $(CACHE)

.PHONY: all verify extract build
all: build

verify:
	@mkdir -p $(CACHE) out/log
	@for m in $(MODULES); do \
	  if $(FSTAR) $(FLAGS) src/Icarus.$$m.fst > out/log/$$m.log 2>&1; then \
	    echo "[fstar] verified Icarus.$$m"; \
	  else cat out/log/$$m.log; echo "[fstar] FAILED Icarus.$$m"; exit 1; fi; \
	done

extract: verify
	@mkdir -p out/ml
	@for m in $(EXTRACT); do \
	  $(FSTAR) --include src --cache_dir $(CACHE) --already_cached '*' --odir out/ml \
	    --codegen OCaml --extract_module Icarus.$$m src/Icarus.$$m.fst > out/log/x$$m.log 2>&1 \
	    || { cat out/log/x$$m.log; exit 1; }; \
	done

build: extract
	@opam exec --switch=$(OPAM_SWITCH) -- sh -c \
	  'OCAMLPATH=$(FSTAR_HOME)/lib:$$OCAMLPATH ocamlfind ocamlopt -package fstar.lib -linkpkg \
	   -I out/ml $(DECIDE_ML:%=out/ml/Icarus_%.ml) driver/driver.ml -o out/icarus_decide && \
	   OCAMLPATH=$(FSTAR_HOME)/lib:$$OCAMLPATH ocamlfind ocamlopt -package fstar.lib -linkpkg \
	   -I out/ml $(SAT_ML:%=out/ml/Icarus_%.ml) driver/driver_sat.ml -o out/icarus_sat'
	@echo "[fstar] built out/icarus_decide out/icarus_sat"
