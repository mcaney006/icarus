-- EXPECT: Can't find an implementation for
-- Reading the newest element of an empty history needs 0 < occupied, which is false.
module Neg.RingRead
import Icarus.Ring

hist : Ring 4 Int
hist = empty 0

bad : Int
bad = peek hist 0
