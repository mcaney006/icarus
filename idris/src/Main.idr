module Main

import Data.List
import Data.String
import Data.Vect
import Icarus.Bench
import Icarus.Fixture
import Icarus.Mode
import Icarus.Plant
import Icarus.SelfTest
import System
import System.File

%default total

line : Show a => String -> List a -> String
line tag values = unwords (tag :: map show values)

scaled : Double -> Integer
scaled v = cast (floor (v * 1.0e9 + 0.5))

report : (Sim n m p, List Frame) -> IO ()
report (s, frames) = do
  putStrLn (line "M" (map (modeCode . (.mode)) frames ++ [modeCode s.monitor.mode]))
  putStrLn (line "H" (map (healthCode . (.health)) frames))
  putStrLn (line "G" (map (.mask) frames))
  putStrLn (line "X" (map scaled (toList s.x)))

reject : String -> IO ()
reject reason = putStrLn "REJECT \{reason}" >> exitWith (ExitFailure 3)

partial
withFixture : String -> ({n, m, p : Nat} -> Fixture n m p -> IO ()) -> IO ()
withFixture path continue = do
  Right content <- readFile path
    | Left _ => reject "unreadable fixture"
  case parseFixture content of
    Left reason => reject reason
    Right (_ ** _ ** _ ** fx) => continue fx

selftest : IO ()
selftest = do
  for_ runSelfTests $ \(name, ok) => putStrLn "\{the String (if ok then "PASS" else "FAIL")} \{name}"
  case failures of
    [] => putStrLn "selftest: \{show (length runSelfTests)} checks passed"
    _ => putStrLn "selftest: \{show (length failures)} FAILED" >> exitWith (ExitFailure 1)
  where
    failures : List Check
    failures = filter (not . snd) runSelfTests

partial
main : IO ()
main = case !getArgs of
  [_, "--selftest"] => selftest
  [_, "--bench", path, reps] => withFixture path (\fx => bench fx (stringToNatOrZ reps))
  [_, path] => withFixture path (report . simulate)
  _ => putStrLn "usage: icarus <fixture.icf>" >> exitWith (ExitFailure 2)
