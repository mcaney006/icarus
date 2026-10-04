module Neg.MatMulDims
import Icarus.Linear
import Data.Vect

bad : Matrix 4 3 Double -> Matrix 2 4 Double -> Matrix 4 4 Double
bad a b = matMul a b
