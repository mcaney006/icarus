module Neg.Units
import Icarus.Dim

bad : AngleLike -> RateLike -> AngleLike
bad a r = qadd a r
