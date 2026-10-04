module Neg.RingReadOk
import Icarus.Ring

hist : Ring 4 Int
hist = push 7 (empty 0)

good : Int
good = peek hist 0
