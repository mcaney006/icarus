-- EXPECT: Mismatch between
-- Multiplying a 4x3 matrix by a 2x4 matrix: the inner dimensions (3 and 2) differ.
module Neg.MatMulDims
import Icarus.Linear
import Data.Vect

bad : Matrix 4 3 Double -> Matrix 2 4 Double -> Matrix 4 4 Double
bad a b = matMul a b
