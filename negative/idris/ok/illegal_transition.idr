module Neg.TransitionOk
import Icarus.Mode

good : Controller Boot -> Controller Running
good c = transition (startup c) Engage
