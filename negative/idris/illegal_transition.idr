module Neg.Transition
import Icarus.Mode

bad : Controller Boot -> Controller Running
bad c = transition c Engage
