||| ICF 2 reader (spec/ICF.md). The header dimensions are read at runtime and
||| every matrix and vector is rebuilt at exactly those indices, so a fixture
||| whose shape disagrees with its own header is rejected, never coerced. The
||| FNV-1a checksum covers every byte before the `Z` line; a missing or wrong
||| checksum is the CorruptFixture fault.
module Icarus.Fixture

import Data.Vect
import Data.Fin
import Data.List
import Data.String
import Data.Bits
import Icarus.Linear
import Icarus.Plant

%default total

public export
record Fixture (n, m, p : Nat) where
  constructor MkFixture
  plant  : Plant n m p
  x0     : Vect n Double
  steps  : Nat
  dist   : List (Vect n Double)
  noise  : List (Vect p Double)
  faults : List (FaultEvent p)

scale : Integer -> Double
scale i = fromInteger i / 1.0e9

exactVect : {0 a : Type} -> (n : Nat) -> List a -> Maybe (Vect n a)
exactVect Z [] = Just []
exactVect (S k) (x :: xs) = (x ::) <$> exactVect k xs
exactVect _ _ = Nothing

exactMatrix : {0 a : Type} -> (r, c : Nat) -> List a -> Maybe (Matrix r c a)
exactMatrix Z c [] = Just []
exactMatrix Z c (_ :: _) = Nothing
exactMatrix (S r) c xs =
  let (row, rest) = splitAt c xs
  in do v <- exactVect c row
        mtx <- exactMatrix r c rest
        pure (v :: mtx)

fnvStep : Int -> Char -> Int
fnvStep h ch = ((h `xor` ord ch) * 16777619) .&. 0xFFFFFFFF

fnvLine : Int -> String -> Int
fnvLine h line = fnvStep (foldl fnvStep h (unpack line)) '\n'

Rec : Type
Rec = (String, List Integer)

parseRec : String -> Either String (Maybe Rec)
parseRec line =
  case words line of
    [] => Right Nothing
    (tag :: rest) =>
      if isPrefixOf "#" tag then Right Nothing
      else case the (Maybe (List Integer)) (traverse parseInteger rest) of
             Just ns => Right (Just (tag, ns))
             Nothing => Left ("non-integer payload on line tagged " ++ tag)

||| Returns the parsed records and rejects on checksum failure.
readRecs : List String -> Either String (List Rec)
readRecs ls = go ls 0x811C9DC5 []
  where
    go : List String -> Int -> List Rec -> Either String (List Rec)
    go [] _ _ = Left "missing Z checksum line"
    go (l :: rest) h acc =
      case words l of
        ("Z" :: [v]) =>
          case parseInteger {a=Integer} v of
            Nothing => Left "malformed checksum"
            Just z => if z == cast h then Right (reverse acc)
                      else Left "checksum mismatch"
        _ => case parseRec l of
               Left e => Left e
               Right Nothing => go rest (fnvLine h l) acc
               Right (Just r) => go rest (fnvLine h l) (r :: acc)

field : String -> List Rec -> Either String (List Integer)
field t rs = case lookup t rs of
  Nothing => Left ("missing " ++ t ++ " record")
  Just v => Right v

natOf : Integer -> Either String Nat
natOf i = if i < 0 then Left "negative dimension" else Right (fromInteger i)

orBad : {0 a : Type} -> String -> Maybe a -> Either String a
orBad msg Nothing = Left msg
orBad _ (Just x) = Right x

indexed : (width : Nat) -> String -> List Rec -> Either String (List (List Integer))
indexed width t rs = go 0 (filter (\r => fst r == t) rs)
  where
    go : Integer -> List Rec -> Either String (List (List Integer))
    go _ [] = Right []
    go i ((_, k :: rest) :: more) =
      if k /= i then Left (t ++ " records out of order")
      else if length rest /= width then Left (t ++ " record has wrong width")
      else map (rest ::) (go (i + 1) more)
    go _ _ = Left (t ++ " record empty")

faultOf : (p : Nat) -> List Integer -> Either String (FaultEvent p)
faultOf p [s, kc, ch, par] = do
  st <- natOf s
  kind <- orBad "unknown fault kind" (faultOfCode (cast kc))
  c <- natOf ch
  fin <- orBad "fault channel out of range" (natToFin c p)
  pure (MkFault st kind fin (scale par))
faultOf _ _ = Left "malformed F record"

export
parseFixture : String -> Either String (n : Nat ** m : Nat ** p : Nat ** Fixture n m p)
parseFixture content = do
  rs <- readRecs (lines content)
  dd <- field "D" rs
  case dd of
    [dn, dm, dp, ds] => do
      n <- natOf dn
      m <- natOf dm
      p <- natOf dp
      steps <- natOf ds
      a <- field "A" rs >>= orBad "A shape" . exactMatrix n n . map scale
      b <- field "B" rs >>= orBad "B shape" . exactMatrix n m . map scale
      c <- field "C" rs >>= orBad "C shape" . exactMatrix p n . map scale
      k <- field "K" rs >>= orBad "K shape" . exactMatrix m n . map scale
      l <- field "L" rs >>= orBad "L shape" . exactMatrix n p . map scale
      x0 <- field "X" rs >>= orBad "X shape" . exactVect n . map scale
      ws <- indexed n "W" rs
      vs <- indexed p "V" rs
      dist <- orBad "W shape" (traverse (exactVect n . map scale) ws)
      noise <- orBad "V shape" (traverse (exactVect p . map scale) vs)
      fs <- traverse (faultOf p) (map snd (filter (\r => fst r == "F") rs))
      if length dist /= steps || length noise /= steps
         then Left "step count disagrees with W/V records"
         else Right (n ** m ** p ** MkFixture (MkPlant a b c k l) x0 steps dist noise fs)
    _ => Left "malformed D record"
