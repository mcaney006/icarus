module Main

import Data.Vect
import Data.List
import Data.String
import System
import System.File
import System.Clock
import Icarus.Linear
import Icarus.Mode
import Icarus.Ring
import Icarus.Plant
import Icarus.Fixture
import Icarus.SelfTest

%default total

zeros : (k : Nat) -> Vect k Double
zeros k = replicate k 0.0

run : {n, m, p : Nat} -> Fixture n m p -> (Sim n m p, List Frame)
run fx = go fx.dist fx.noise 0 start []
  where
    start : Sim n m p
    start = MkSim fx.x0 (zeros n) (zeros m) (zeros p) Ready 0 0 (empty Healthy)
    go : List (Vect n Double) -> List (Vect p Double) -> Nat -> Sim n m p -> List Frame
      -> (Sim n m p, List Frame)
    go (w :: ws) (v :: vs) k s acc =
      let (s', fr) = frame fx.plant 1.0 fx.faults k w v s
      in go ws vs (S k) s' (fr :: acc)
    go _ _ _ s acc = (s, reverse acc)

line : String -> List Int -> String
line tag xs = tag ++ " " ++ unwords (map show xs)

scaled : Double -> Integer
scaled v = cast (floor (v * 1.0e9 + 0.5))

report : Sim n m p -> List Frame -> IO ()
report s frames = do
  putStrLn (line "M" (map (modeCode . mode) frames ++ [modeCode s.mode]))
  putStrLn (line "H" (map (healthCode . health) frames))
  putStrLn (line "G" (map mask frames))
  putStrLn ("X " ++ unwords (map (show . scaled) (toList s.x)))

-- ------------------------------------------------------------- benchmark ---
-- Same operations as ats/src/bench.dats. Loops feed each result into the next
-- iteration so no call is loop-invariant, and every result reaches the checksum.

%foreign "scheme:(lambda () (sstats-bytes (statistics)))"
prim__bytesAllocated : PrimIO Int

bytesAllocated : IO Int
bytesAllocated = primIO prim__bytesAllocated

nanos : IO Integer
nanos = toNano <$> clockTime Monotonic

perm : Matrix 4 4 Double
perm = map (\i => map (\j => if finToNat j == (finToNat i + 1) `mod` 4 then 1.0 else 0.0) range) range

hilbert : Double -> Matrix 4 4 Double
hilbert base = map (\i => map (\j => base / (1.0 + cast (finToNat i + finToNat j))) range) range

loopVadd : Nat -> Vect 4 Double -> Vect 4 Double -> Vect 4 Double
loopVadd Z a _ = a
loopVadd (S k) a b = loopVadd k (vadd a b) b

loopDot : Nat -> Double -> Vect 4 Double -> Double
loopDot Z acc _ = acc
loopDot (S k) acc v = loopDot k (acc + dot v v) v

loopMatVec : Nat -> Matrix 4 4 Double -> Vect 4 Double -> Vect 4 Double
loopMatVec Z _ v = v
loopMatVec (S k) m v = loopMatVec k m (matVec m v)

loopMatMul : Nat -> Matrix 4 4 Double -> Matrix 4 4 Double -> Matrix 4 4 Double
loopMatMul Z a _ = a
loopMatMul (S k) a b = loopMatMul k (matMul a b) b

loopRing : Nat -> Ring 16 Int -> Int -> Int
loopRing Z _ acc = acc
loopRing (S k) r acc =
  let r' = push (cast k) r
  in loopRing k r' ((acc + fromMaybe 0 (peekMaybe r' 3)) `mod` 1000003)

modeOf : Int -> Icarus.Mode.Mode
modeOf 3 = Ready
modeOf 4 = Running
modeOf 5 = Degraded
modeOf _ = Safe

healthOf : Integer -> Health
healthOf 0 = Healthy
healthOf 1 = Suspect
healthOf 2 = DegradedH
healthOf _ = Unsafe

loopDecide : Nat -> Icarus.Mode.Mode -> Int -> Int
loopDecide Z _ acc = acc
loopDecide (S k) m acc =
  let i = natToInteger k
      (m' ** _) = decideMode m (healthOf (i `mod` 4)) (i `mod` 7 == 0)
                    (integerToNat (i `mod` 5)) (integerToNat (i `mod` 3))
      next = if modeCode m' == 6 then Ready else m'
  in loopDecide k next (acc + modeCode m')

loopFrames : {n, m, p : Nat} -> Nat -> Fixture n m p -> Integer -> IO Integer
loopFrames Z _ acc = pure acc
loopFrames (S k) fx acc = do
  let (s, frs) = run fx
  loopFrames k fx (acc + cast (modeCode s.mode) + cast (length frs))

timed : String -> Nat -> (() -> IO a) -> IO a
timed name iters act = do
  a0 <- bytesAllocated
  t0 <- nanos
  r <- act ()
  t1 <- nanos
  a1 <- bytesAllocated
  putStrLn ("idris," ++ name ++ "," ++ show iters ++ "," ++ show (t1 - t0) ++ "," ++ show (a1 - a0))
  pure r

bench : {n, m, p : Nat} -> Fixture n m p -> Nat -> IO ()
bench fx reps = do
  let nv = 10000000
      nm = 1000000
      a = [1.0e-9, 2.0e-9, 3.0e-9, 4.0e-9]
  va <- timed "vadd4" nv (\_ => pure (loopVadd nv a a))
  d <- timed "dot4" nv (\_ => pure (loopDot nv 0.0 a))
  mv <- timed "matvec4x4" nv (\_ => pure (loopMatVec nv perm a))
  mm <- timed "matmul4x4" nm (\_ => pure (loopMatMul nm (hilbert 0.25) perm))
  rs <- timed "ring_push_peek" nv (\_ => pure (loopRing nv (empty 0) 0))
  ms <- timed "mode_decide" nv (\_ => pure (loopDecide nv Ready 0))
  fs <- timed "frame" (reps * fx.steps) (\_ => loopFrames reps fx 0)
  putStrLn ("checksum," ++ show (sum va + d + sum mv + sum (map sum mm)) ++ "," ++ show (cast rs + cast ms + fs))

||| Totality ends at the file-system boundary: `readFile` is a library primitive
||| that loops to EOF. Every function above and in Icarus.* is total.
partial
main : IO ()
main = do
  args <- getArgs
  case args of
    [_, "--selftest"] => do
      let results = runSelfTests
          failed = filter (not . snd) results
      traverse_ (\(name, ok) => putStrLn ((if ok then "PASS " else "FAIL ") ++ name)) results
      if null failed then putStrLn ("selftest: " ++ show (length results) ++ " checks passed")
        else do putStrLn ("selftest: " ++ show (length failed) ++ " FAILED"); exitWith (ExitFailure 1)
    [_, "--bench", path, reps] => do
      Right content <- readFile path
        | Left _ => do putStrLn "REJECT unreadable fixture"; exitWith (ExitFailure 3)
      case parseFixture content of
        Left err => do putStrLn ("REJECT " ++ err); exitWith (ExitFailure 3)
        Right (n ** m ** p ** fx) => bench fx (stringToNatOrZ reps)
    [_, path] => do
      Right content <- readFile path
        | Left _ => do putStrLn "REJECT unreadable fixture"; exitWith (ExitFailure 3)
      case parseFixture content of
        Left err => do putStrLn ("REJECT " ++ err); exitWith (ExitFailure 3)
        Right (n ** m ** p ** fx) => do
          let (s, frames) = run fx
          report s frames
    _ => do putStrLn "usage: icarus <fixture.icf>"; exitWith (ExitFailure 2)
