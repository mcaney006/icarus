# ATS runtime. Counting allocator (ATS_MEMALLOC_USER) lets the simulator verify
# that no allocation happens between the first and last frame.
SHELL := /bin/bash
PATSCC ?= patscc
CFLAGS := -DATS_MEMALLOC_USER -O2 -ffp-contract=off
LIB := src/linear.dats src/pool.dats src/ring.dats src/mode.dats
RUNTIME := src/alloc_user.c src/io_shim.c
FIXTURE ?= ../fixtures/final_experiment.icf

.PHONY: all selftest simulate bench
all: build/icarus_sim build/icarus_selftest build/icarus_bench

build/icarus_sim: $(LIB) src/fixture.dats src/sim.dats src/main.dats $(RUNTIME) $(wildcard src/*.sats)
	@mkdir -p build
	@$(PATSCC) $(CFLAGS) -o $@ $(LIB) src/fixture.dats src/sim.dats src/main.dats $(RUNTIME) -lm 2>&1 | grep -v "unused during" || true
	@test -x $@ && echo "[ats] built $@"

build/icarus_selftest: $(LIB) src/selftest.dats $(RUNTIME) $(wildcard src/*.sats)
	@mkdir -p build
	@$(PATSCC) $(CFLAGS) -o $@ $(LIB) src/selftest.dats $(RUNTIME) -lm 2>&1 | grep -v "unused during" || true
	@test -x $@ && echo "[ats] built $@"

build/icarus_bench: $(LIB) src/fixture.dats src/sim.dats src/bench.dats $(RUNTIME) $(wildcard src/*.sats)
	@mkdir -p build
	@$(PATSCC) $(CFLAGS) -o $@ $(LIB) src/fixture.dats src/sim.dats src/bench.dats $(RUNTIME) -lm 2>&1 | grep -v "unused during" || true
	@test -x $@ && echo "[ats] built $@"

selftest: build/icarus_selftest
	@set -o pipefail; ./build/icarus_selftest | tail -1

simulate: build/icarus_sim
	@./build/icarus_sim $(FIXTURE)

bench: build/icarus_bench
	@./build/icarus_bench $(FIXTURE) 20000
