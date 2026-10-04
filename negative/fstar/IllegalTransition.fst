module IllegalTransition
open Icarus.Mode

let bad (s:st{s.mode = Safe}) : s':st{legal s.mode s'.mode} =
  { mode = Running; healthy = 0; bad = 0 }
