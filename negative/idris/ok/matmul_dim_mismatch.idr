module Neg.MatMulDimsOk
import Icarus.Linear
import Data.Vect

good : Matrix 4 3 Double -> Matrix 3 2 Double -> Matrix 4 2 Double
good a b = matMul a b
