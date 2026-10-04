module Neg.SafeEscape
import Icarus.Mode

bad : Controller Safe -> Controller Running
bad c = transition c Recover
