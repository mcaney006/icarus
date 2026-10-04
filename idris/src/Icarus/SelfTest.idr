module Icarus.SelfTest

import Data.List
import Icarus.Dim
import Icarus.Linear
import Icarus.Mode
import Icarus.Ring
import Icarus.Plant

%default total

public export
Check : Type
Check = (String, Bool)

ring0 : Ring 4 Int
ring0 = empty 0

ring6 : Ring 4 Int
ring6 = foldr push ring0 (the (List Int) [9, 8, 7, 6, 5, 4])

ringChecks : List Check
ringChecks =
  [ ("ring: empty has length 0", occupied ring0 == 0)
  , ("ring: length saturates at capacity", occupied ring6 == 4)
  , ("ring: newest is last push", peek ring6 0 == 9)
  , ("ring: second newest", peek ring6 1 == 8)
  , ("ring: third-newest", peekMaybe ring6 2 == Just 7)
  , ("ring: oldest retained is capacity-1 back", peekMaybe ring6 3 == Just 6)
  , ("ring: age at capacity is refused", peekMaybe ring6 4 == Nothing)
  , ("ring: empty refuses any read", peekMaybe ring0 0 == Nothing)
  ]

m23 : Matrix 2 3 Int
m23 = [[1, 2, 3], [4, 5, 6]]

m32 : Matrix 3 2 Int
m32 = [[7, 8], [9, 10], [11, 12]]

matrixChecks : List Check
matrixChecks =
  [ ("matrix: 2x3 * 3x2 product", matMul m23 m32 == [[58, 64], [139, 154]])
  , ("matrix: right identity", matMul m23 identity == m23)
  , ("matrix: matVec", matVec m23 [1, 0, 1] == [4, 10])
  , ("matrix: transpose involution", transpose (transpose m23) == m23)
  , ("matrix: dot", dot [1, 2, 3] [4, 5, 6] == the Int 32)
  ]

unitChecks : List Check
unitChecks =
  [ ("units: length += rate*time", raw (advanceLength (Q 1.0) (Q 0.5) (Q 0.2)) == 1.1)
  , ("units: angle += angular rate*time", raw (advanceAngle (Q 0.0) (Q 2.0) (Q 0.25)) == 0.5)
  , ("units: rate = length / time", raw (rateOver (Q 3.0) (Q 2.0)) == 1.5)
  ]

decided : Mode -> Health -> (healthy, bad : Nat) -> Mode
decided m h healthy bad = fst (decideMode m h False healthy bad)

modeChecks : List Check
modeChecks =
  [ ("mode: Safe absorbs", decided Safe Healthy 9 9 == Safe)
  , ("mode: Running+Unsafe -> Safe", decided Running Unsafe 0 0 == Safe)
  , ("mode: third healthy frame recovers", decided Degraded Healthy 2 0 == Running)
  , ("mode: repeated bad frames -> Safe", decided Degraded Suspect 0 2 == Safe)
  , ("mode: Ready always engages", decided Ready Unsafe 0 0 == Running)
  , ("health: numeric flag dominates", classify (MkFlags True True True True True) == Unsafe)
  , ("health: two flags degraded", classify (MkFlags True True False False False) == Degraded)
  , ("health: none healthy", classify noFlags == Healthy)
  ]

export
runSelfTests : List Check
runSelfTests = ringChecks ++ matrixChecks ++ unitChecks ++ modeChecks
