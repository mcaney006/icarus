module Neg.SafeEscapeOk
import Icarus.Mode

good : Controller Degraded -> Controller Running
good c = transition c Recover
