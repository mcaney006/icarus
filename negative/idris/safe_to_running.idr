-- EXPECT: Mismatch between
-- Safe is absorbing: Recover only leaves Degraded, so Safe cannot reach Running.
module Neg.SafeEscape
import Icarus.Mode

bad : Controller Safe -> Controller Running
bad c = transition c Recover
