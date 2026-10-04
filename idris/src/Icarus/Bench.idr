module Icarus.Bench

import Data.Maybe
import Icarus.Fixture
import Icarus.Linear
import Icarus.Mode
import Icarus.Plant
import Icarus.Ring
import System.Clock

%default total

%foreign "scheme:(lambda () (sstats-bytes (statistics)))"
prim__bytesAllocated : PrimIO Int

bytesAllocated : IO Int
bytesAllocated = primIO prim__bytesAllocated

nanos : IO Integer
nanos = toNano <$> clockTime Monotonic

cyclic : Matrix 4 4 Double
cyclic = map (\i => map (\j => if finToNat j == (finToNat i + 1) `mod` 4 then 1.0 else 0.0) range) range

hilbert : Double -> Matrix 4 4 Double
hilbert base = map (\i => map (\j => base / (1.0 + cast (finToNat i + finToNat j))) range) range

iterate : Nat -> (a -> a) -> a -> a
iterate Z _ x = x
iterate (S k) f x = iterate k f (f x)

ringLoop : Nat -> Ring 16 Int -> Int -> Int
ringLoop Z _ acc = acc
ringLoop (S k) r acc = let r' = push (cast k) r in ringLoop k r' ((acc + fromMaybe 0 (peekMaybe r' 3)) `mod` 1000003)

decideLoop : Nat -> Mode -> Int -> Int
decideLoop Z _ acc = acc
decideLoop (S k) m acc =
  let i = natToInteger k
      health = fromMaybe Unsafe (healthOfCode (integerToNat (i `mod` 4)))
      (m' ** _) = decideMode m health (i `mod` 7 == 0) (integerToNat (i `mod` 5)) (integerToNat (i `mod` 3))
  in decideLoop k (if m' == Safe then Ready else m') (acc + cast (modeCode m'))

frameLoop : {n, m, p : Nat} -> Nat -> Fixture n m p -> Integer -> Integer
frameLoop Z _ acc = acc
frameLoop (S k) fx acc =
  let (s, frames) = simulate fx in frameLoop k fx (acc + cast (modeCode s.monitor.mode) + cast (length frames))

timed : String -> Nat -> (() -> IO a) -> IO a
timed name iterations work = do
  before <- bytesAllocated
  start <- nanos
  result <- work ()
  end <- nanos
  after <- bytesAllocated
  putStrLn "idris,\{name},\{show iterations},\{show (end - start)},\{show (after - before)}"
  pure result

export
bench : {n, m, p : Nat} -> Fixture n m p -> Nat -> IO ()
bench fx reps = do
  let vectorOps = 10000000
      matrixOps = 1000000
      seed = the (Vect 4 Double) [1.0e-9, 2.0e-9, 3.0e-9, 4.0e-9]
  sum4 <- timed "vadd4" vectorOps (\_ => pure (iterate vectorOps (`vadd` seed) seed))
  dots <- timed "dot4" vectorOps (\_ => pure (iterate vectorOps (+ dot seed seed) 0.0))
  rotated <- timed "matvec4x4" vectorOps (\_ => pure (iterate vectorOps (matVec cyclic) seed))
  product <- timed "matmul4x4" matrixOps (\_ => pure (iterate matrixOps (`matMul` cyclic) (hilbert 0.25)))
  ring <- timed "ring_push_peek" vectorOps (\_ => pure (ringLoop vectorOps (empty 0) 0))
  modes <- timed "mode_decide" vectorOps (\_ => pure (decideLoop vectorOps Ready 0))
  frames <- timed "frame" (reps * fx.steps) (\_ => pure (frameLoop reps fx 0))
  putStrLn "checksum,\{show (sum sum4 + dots + sum rotated + sum (map sum product))},\{show (cast ring + cast modes + frames)}"
