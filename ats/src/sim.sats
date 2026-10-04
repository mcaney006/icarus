staload "./fixture.sats"

fun run_sim (cfg: !cfg_vt): lint

fun sim_bench (cfg: !cfg_vt, reps: int): @(lint, lint)
