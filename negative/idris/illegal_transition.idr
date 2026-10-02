-- EXPECT: Mismatch between
-- Boot to Running has no Legal witness; Engage only connects Ready to Running.
module Neg.Transition
import Icarus.Mode

bad : Controller Boot -> Controller Running
bad c = transition c Engage
