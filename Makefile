SHELL := /bin/bash
.SHELLFLAGS := -o pipefail -c
DETECT := bash tools/detect-toolchains.sh
PY := $(or $(shell $(DETECT) --path python3),python3)

define with_tool
@tool=$$($(DETECT) --path $(1)); \
if [ -z "$$tool" ]; then echo "[$(2)] SKIP ($(1) missing)"; else $(3); fi
endef

.PHONY: toolchains fixtures bootstrap reference lean idris fstar ats build verify audit negative simulate \
        selftest crosscheck satcheck experiments benchmark test format ci clean

toolchains:
	@$(DETECT)

fixtures:
	@$(PY) tools/gen_fixtures.py

bootstrap: toolchains fixtures

reference:
	@$(PY) reference/icarus_ref.py --selfcheck

lean:
	$(call with_tool,lake,lean,cd lean && "$$tool" build)

idris:
	$(call with_tool,idris2,idris,cd idris && "$$tool" --build icarus.ipkg)

fstar:
	$(call with_tool,fstar,fstar,$(MAKE) -C fstar FSTAR="$$tool")

ats:
	$(call with_tool,patscc,ats,$(MAKE) -C ats PATSCC="$$tool")

build: reference lean idris fstar ats

verify: lean fstar idris negative audit

audit:
	@bash tools/audit-holes.sh

negative:
	@bash negative/run.sh

simulate:
	$(call with_tool,patscc,ats,$(MAKE) -C ats simulate PATSCC="$$tool")

selftest:
	@if [ -x idris/build/exec/icarus ]; then idris/build/exec/icarus --selftest | tail -1; else echo "[idris] SKIP selftest (not built)"; fi
	@if [ -x ats/build/icarus_selftest ]; then ats/build/icarus_selftest | tail -1; else echo "[ats] SKIP selftest (not built)"; fi

crosscheck:
	@$(PY) tools/crosscheck.py $(STRICT)

satcheck:
	@$(PY) tools/satcheck.py $(STRICT)

experiments:
	@$(PY) tools/fixed_point_experiment.py

benchmark:
	@$(PY) tools/benchmark.py

test: reference selftest crosscheck satcheck

format:
	@git diff --check $$(git hash-object -t tree /dev/null) HEAD
	$(call with_tool,ruff,python,"$$tool" format --check --quiet reference tools && "$$tool" check --quiet reference tools)
	@echo "format: clean"

ci:
	@$(DETECT) --require-all
	@$(MAKE) format bootstrap
	@git diff --exit-code --stat fixtures/
	@$(MAKE) build verify test simulate STRICT=--strict

clean:
	@rm -rf dist lean/.lake idris/build fstar/out ats/build
	@find . \( -name '*.checked' -o -name '*_dats.c' -o -name '*_sats.c' \) -not -path './.git/*' -delete
