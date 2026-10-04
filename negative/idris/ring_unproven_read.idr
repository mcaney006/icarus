module Neg.RingRead
import Icarus.Ring

hist : Ring 4 Int
hist = empty 0

bad : Int
bad = peek hist 0
