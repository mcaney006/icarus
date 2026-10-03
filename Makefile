# icarus top-level orchestration. Each language keeps its own build tool; this
# coordinates them and skips (never silently passes) a missing toolchain.
SHELL := /bin/bash
DETECT := bash tools/detect-toolchains.sh
PY := $(or $(shell bash tools/detect-toolchains.sh --path python3),python3)

.PHONY: bootstrap build test verify simulate crosscheck satcheck experiments benchmark clean ci audit \
        toolchains reference lean idris fstar ats negative fixtures

toolchains:
	@$(DETECT)

fixtures:
	@$(PY) tools/gen_fixtures.py

bootstrap: toolchains fixtures
	@echo "bootstrap complete."

reference:
	@if [ ! -f reference/icarus_ref.py ]; then echo "[ref]   SKIP (not implemented)"; \
	else $(PY) reference/icarus_ref.py --selfcheck; fi

lean:
	@LAKE=$$($(DETECT) --path lake); \
	if [ -z "$$LAKE" ]; then echo "[lean]  SKIP (toolchain missing)"; \
	elif [ ! -f lean/lakefile.toml ]; then echo "[lean]  SKIP (not implemented)"; \
	else echo "[lean]  building"; cd lean && "$$LAKE" build; fi

idris:
	@IDRIS=$$($(DETECT) --path idris2); \
	if [ -z "$$IDRIS" ]; then echo "[idris] SKIP (toolchain missing)"; \
	elif [ ! -f idris/icarus.ipkg ]; then echo "[idris] SKIP (not implemented)"; \
	else echo "[idris] building"; cd idris && "$$IDRIS" --build icarus.ipkg; fi

fstar:
	@FSTAR=$$($(DETECT) --path fstar); \
	if [ -z "$$FSTAR" ]; then echo "[fstar] SKIP (toolchain missing)"; \
	elif [ ! -f fstar/Makefile ]; then echo "[fstar] SKIP (not implemented)"; \
	else echo "[fstar] verifying"; $(MAKE) -C fstar FSTAR="$$FSTAR"; fi

ats:
	@PATSCC=$$($(DETECT) --path patscc); \
	if [ -z "$$PATSCC" ]; then echo "[ats]   SKIP (toolchain missing)"; \
	elif [ ! -f ats/Makefile ]; then echo "[ats]   SKIP (not implemented)"; \
	else echo "[ats]   building"; $(MAKE) -C ats; fi

build: reference lean idris fstar ats

verify: lean fstar idris negative audit
	@echo "verify: provers + type-checkers + negative tests complete."

audit:
	@bash tools/audit-holes.sh

negative:
	@if [ -f negative/run.sh ]; then bash negative/run.sh; else echo "[neg]   SKIP (not implemented)"; fi

simulate:
	@if [ -f ats/Makefile ] && [ -n "$$($(DETECT) --path patscc)" ]; then $(MAKE) -C ats simulate; \
	else echo "[sim] running python reference"; $(PY) reference/icarus_ref.py --fixture fixtures/final_experiment.json --trace; fi

crosscheck:
	@$(PY) tools/crosscheck.py

satcheck:
	@$(PY) tools/satcheck.py

experiments:
	@$(PY) tools/fixed_point_experiment.py

benchmark:
	@if [ -f tools/benchmark.py ]; then $(PY) tools/benchmark.py; else echo "[bench] SKIP (not implemented)"; fi

test: reference crosscheck satcheck
	@echo "test complete."

# Strict gate for CI: every toolchain must be present and every stage must pass.
ci:
	@$(DETECT) --require-all || { echo "CI: a required toolchain is missing"; exit 1; }
	@$(MAKE) bootstrap build verify test

clean:
	@rm -rf dist lean/.lake lean/build idris/build fstar/out fstar/.cache ats/build fstar/driver/*.cm[iox] fstar/driver/*.o
	@find . -name '*.checked' -delete 2>/dev/null; true
	@find . -name '*_dats.c' -o -name '*_sats.c' | xargs rm -f 2>/dev/null; true
	@echo "clean complete."
