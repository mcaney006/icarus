module Main

import Data.Vect
import Data.List
import Data.String
import System
import System.File
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
    [_, path] => do
      Right content <- readFile path
        | Left _ => do putStrLn "REJECT unreadable fixture"; exitWith (ExitFailure 3)
      case parseFixture content of
        Left err => do putStrLn ("REJECT " ++ err); exitWith (ExitFailure 3)
        Right (n ** m ** p ** fx) => do
          let (s, frames) = run fx
          report s frames
    _ => do putStrLn "usage: icarus <fixture.icf>"; exitWith (ExitFailure 2)
