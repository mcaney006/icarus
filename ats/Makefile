SHELL := /bin/bash
.SHELLFLAGS := -o pipefail -c
PATSCC ?= patscc
CFLAGS := -DATS_MEMALLOC_USER -O2 -ffp-contract=off
LIBRARY := src/linear.dats src/pool.dats src/ring.dats src/mode.dats src/alloc_user.c src/io_shim.c
SIMULATOR := src/fixture.dats src/sim.dats
FIXTURE ?= ../fixtures/final_experiment.icf
EXECUTABLES := build/icarus_sim build/icarus_selftest build/icarus_bench

.PHONY: all selftest simulate bench
all: $(EXECUTABLES)

build/icarus_sim: $(SIMULATOR) src/main.dats
build/icarus_selftest: src/selftest.dats
build/icarus_bench: $(SIMULATOR) src/bench.dats

$(EXECUTABLES): $(LIBRARY) $(wildcard src/*.sats)
	@mkdir -p build
	@rm -f $@
	@$(PATSCC) $(CFLAGS) -o $@ $(filter %.dats %.c,$^) -lm 2>&1 | { grep -v "unused during" || true; }
	@echo "[ats] built $@"

selftest: build/icarus_selftest
	@./build/icarus_selftest | tail -1

simulate: build/icarus_sim
	@./build/icarus_sim $(FIXTURE)

bench: build/icarus_bench
	@./build/icarus_bench $(FIXTURE) 20000
