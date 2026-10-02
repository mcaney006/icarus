||| Runtime checks of the properties the types cannot state. Each check is
||| named so a failure says which invariant broke.
module Icarus.SelfTest

import Data.Vect
import Data.List
import Icarus.Dim
import Icarus.Linear
import Icarus.Mode
import Icarus.Ring
import Icarus.Plant

%default total

check : String -> Bool -> (String, Bool)
check = MkPair

fillTo : Nat -> Ring 4 Int -> Ring 4 Int
fillTo Z r = r
fillTo (S k) r = fillTo k (push (cast (S k)) r)

ring0 : Ring 4 Int
ring0 = empty 0

ring6 : Ring 4 Int
ring6 = push 9 (push 8 (push 7 (push 6 (push 5 (push 4 ring0)))))

ringChecks : List (String, Bool)
ringChecks =
  [ check "ring: empty has length 0" (occupied ring0 == 0)
  , check "ring: length saturates at capacity" (occupied ring6 == 4)
  , check "ring: newest is last push" (peek ring6 0 == 9)
  , check "ring: second newest" (peek ring6 1 {ok = LTESucc (LTESucc LTEZero)} == 8)
  , check "ring: third-newest" (peekMaybe ring6 2 == Just 7)
  , check "ring: oldest retained is capacity-1 back" (peekMaybe ring6 3 == Just 6)
  , check "ring: age at capacity is refused" (peekMaybe ring6 4 == Nothing)
  , check "ring: empty refuses any read" (peekMaybe ring0 0 == Nothing)
  ]

m23 : Matrix 2 3 Int
m23 = [[1, 2, 3], [4, 5, 6]]

m32 : Matrix 3 2 Int
m32 = [[7, 8], [9, 10], [11, 12]]

i3 : Matrix 3 3 Int
i3 = identity

matChecks : List (String, Bool)
matChecks =
  [ check "matrix: 2x3 * 3x2 product" (matMul m23 m32 == [[58, 64], [139, 154]])
  , check "matrix: right identity" (matMul m23 i3 == m23)
  , check "matrix: matVec" (matVec m23 [1, 0, 1] == [4, 10])
  , check "matrix: transpose involution" (transpose' (transpose' m23) == m23)
  , check "matrix: dot" (dot [1, 2, 3] [4, 5, 6] == the Int 32)
  ]

unitChecks : List (String, Bool)
unitChecks =
  [ check "units: length += rate*time" (raw (advanceLength (Q 1.0) (Q 0.5) (Q 0.2)) == 1.1)
  , check "units: angle += angular rate*time" (raw (advanceAngle (Q 0.0) (Q 2.0) (Q 0.25)) == 0.5)
  ]

modeChecks : List (String, Bool)
modeChecks =
  let st1 = fst (decideMode Safe Healthy False 9 9)
      st2 = fst (decideMode Running Unsafe False 0 0)
      st3 = fst (decideMode Degraded Healthy False 2 0)
      st4 = fst (decideMode Degraded Suspect False 0 2)
      st5 = fst (decideMode Ready Unsafe False 0 0)
  in [ check "mode: Safe absorbs" (st1 == Safe)
     , check "mode: Running+Unsafe -> Safe" (st2 == Safe)
     , check "mode: third healthy frame recovers" (st3 == Running)
     , check "mode: repeated bad frames -> Safe" (st4 == Safe)
     , check "mode: Ready always engages" (st5 == Running)
     , check "health: numeric flag dominates" (healthCode (classify (MkFlags True True True True True)) == 3)
     , check "health: two flags degraded" (healthCode (classify (MkFlags True True False False False)) == 2)
     , check "health: none healthy" (healthCode (classify noFlags) == 0)
     ]

export
runSelfTests : List (String, Bool)
runSelfTests = ringChecks ++ matChecks ++ unitChecks ++ modeChecks
