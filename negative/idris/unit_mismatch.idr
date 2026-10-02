-- EXPECT: Mismatch between
-- Adding an AngleLike to a RateLike: different dimensions have no common qadd.
module Neg.Units
import Icarus.Dim

bad : AngleLike -> RateLike -> AngleLike
bad a r = qadd a r
