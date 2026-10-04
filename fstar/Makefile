FSTAR ?= fstar.exe
OPAM_SWITCH ?= icarus-fstar
FSTAR_HOME ?= $(HOME)/.local/opt/fstar
MODULES := Health Mode Sat Vote Counter Timing Ring Wire Decide SatCheck AbstractCost CostReport
EXTRACT := Health Mode Wire Decide Sat SatCheck Timing AbstractCost CostReport
EXECUTABLES := icarus_decide icarus_sat icarus_cost
icarus_decide_MODULES := Health Mode Wire Decide
icarus_sat_MODULES := Wire Sat SatCheck
icarus_cost_MODULES := Timing AbstractCost Wire CostReport
CACHE := out/cache
FLAGS := --include src --cache_checked_modules --cache_dir $(CACHE)
OCAMLOPT := opam exec --switch=$(OPAM_SWITCH) -- env OCAMLPATH=$(FSTAR_HOME)/lib \
  ocamlfind ocamlopt -w -8 -package fstar.lib -linkpkg -I out/ml

.PHONY: all verify extract build
all: build

verify:
	@mkdir -p $(CACHE) out/log
	@for m in $(MODULES); do \
	  if $(FSTAR) $(FLAGS) src/Icarus.$$m.fst > out/log/$$m.log 2>&1; then echo "[fstar] verified Icarus.$$m"; \
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
	@$(foreach exe,$(EXECUTABLES),$(OCAMLOPT) $($(exe)_MODULES:%=out/ml/Icarus_%.ml) driver/$(exe).ml -o out/$(exe) &&) true
	@echo "[fstar] built $(EXECUTABLES:%=out/%)"
