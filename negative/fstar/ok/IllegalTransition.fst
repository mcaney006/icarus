module IllegalTransition
open Icarus.Mode

let good (s:st{s.mode = Safe}) : s':st{legal s.mode s'.mode} =
  { mode = Safe; healthy = 0; bad = 0 }
