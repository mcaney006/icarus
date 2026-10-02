-- EXPECT: Can't find an implementation|Mismatch|Can't solve
-- Reading index 4 from a Vect 4: the valid indices are 0..3.
module Neg.Index
import Data.Vect

bad : Vect 4 Double -> Double
bad v = index 4 v
