#include "share/atspre_staload.hats"
staload "./fixture.sats"
staload "./sim.sats"

implement main0 (argc, argv) =
  if argc >= 2 then let
    val opt = load_fixture(argv[1])
  in
    case+ opt of
    | ~None_vt() => exit(3)
    | ~Some_vt(cfg) => let
        val allocs = run_sim(cfg)
        val () = cfg_free(cfg)
      in
        if allocs = 0L then ()
        else (prerrln! ("icarus_sim: frame loop made ", allocs, " allocator calls"); exit(4))
      end
  end
  else (prerrln! ("usage: icarus_sim <fixture.icf>"); exit(2))
