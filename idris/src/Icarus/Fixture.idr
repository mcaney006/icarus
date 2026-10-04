module Icarus.Fixture

import Data.Bits
import Data.List
import Data.String
import Icarus.Linear
import Icarus.Plant

%default total

public export
record Fixture (n, m, p : Nat) where
  constructor MkFixture
  plant : Plant n m p
  x0 : Vect n Double
  steps : Nat
  disturbance : List (Vect n Double)
  noise : List (Vect p Double)
  faults : List (FaultEvent p)

Record : Type
Record = (String, List Integer)

descale : Integer -> Double
descale i = fromInteger i / 1.0e9

exactVect : (n : Nat) -> List a -> Maybe (Vect n a)
exactVect Z [] = Just []
exactVect (S k) (x :: xs) = (x ::) <$> exactVect k xs
exactVect _ _ = Nothing

exactMatrix : (r, c : Nat) -> List a -> Maybe (Matrix r c a)
exactMatrix Z _ [] = Just []
exactMatrix Z _ _ = Nothing
exactMatrix (S r) c xs = let (row, rest) = splitAt c xs in [| exactVect c row :: exactMatrix r c rest |]

fnv : Int -> Char -> Int
fnv hash ch = ((hash `xor` ord ch) * 16777619) .&. 0xFFFFFFFF

fnvLine : Int -> String -> Int
fnvLine hash line = fnv (foldl fnv hash (unpack line)) '\n'

orReject : String -> Maybe a -> Either String a
orReject reason = maybe (Left reason) Right

parseRecord : String -> Either String (Maybe Record)
parseRecord line = case words line of
  [] => Right Nothing
  tag :: payload =>
    if "#" `isPrefixOf` tag then Right Nothing
    else Just . (tag,) <$> orReject "non-integer payload on line tagged \{tag}" (traverse parseInteger payload)

records : List String -> Either String (List Record)
records = go 0x811C9DC5 [<]
  where
    go : Int -> SnocList Record -> List String -> Either String (List Record)
    go _ _ [] = Left "missing Z checksum line"
    go hash acc (line :: rest) = case words line of
      ["Z", digest] => do
        z <- orReject "malformed checksum" (parseInteger {a = Integer} digest)
        if z == cast hash then Right (acc <>> []) else Left "checksum mismatch"
      _ => parseRecord line >>= \parsed => go (fnvLine hash line) (maybe acc (acc :<) parsed) rest

field : String -> List Record -> Either String (List Integer)
field tag = orReject "missing \{tag} record" . lookup tag

natural : Integer -> Either String Nat
natural i = if i < 0 then Left "negative dimension" else Right (fromInteger i)

indexed : (width : Nat) -> String -> List Record -> Either String (List (List Integer))
indexed width tag = go 0 . filter ((== tag) . fst)
  where
    go : Integer -> List Record -> Either String (List (List Integer))
    go _ [] = Right []
    go i ((_, k :: row) :: more) =
      if k /= i then Left "\{tag} records out of order"
      else if length row /= width then Left "\{tag} record has wrong width"
      else (row ::) <$> go (i + 1) more
    go _ _ = Left "\{tag} record empty"

fault : (p : Nat) -> List Integer -> Either String (FaultEvent p)
fault p [step, kind, lane, param] = do
  step <- natural step
  kind <- orReject "unknown fault kind" (if kind < 0 then Nothing else faultOfCode (fromInteger kind))
  lane <- natural lane >>= \l => orReject "fault channel out of range" (natToFin l p)
  pure (MkFault step kind lane (descale param))
fault _ _ = Left "malformed F record"

export
parseFixture : String -> Either String (n : Nat ** m : Nat ** p : Nat ** Fixture n m p)
parseFixture content = do
  rs <- records (lines content)
  [n, m, p, steps] <- traverse natural !(field "D" rs)
    | _ => Left "malformed D record"
  let matrix : (r, c : Nat) -> String -> Either String (Matrix r c Double)
      matrix r c tag = field tag rs >>= orReject "\{tag} shape" . exactMatrix r c . map descale
      series : (width : Nat) -> String -> Either String (List (Vect width Double))
      series width tag = indexed width tag rs >>= orReject "\{tag} shape" . traverse (exactVect width . map descale)
  plant <- [| MkPlant (matrix n n "A") (matrix n m "B") (matrix p n "C") (matrix m n "K") (matrix n p "L") |]
  x0 <- field "X" rs >>= orReject "X shape" . exactVect n . map descale
  disturbance <- series n "W"
  noise <- series p "V"
  faults <- traverse (fault p . snd) (filter ((== "F") . fst) rs)
  if length disturbance /= steps || length noise /= steps
    then Left "step count disagrees with W/V records"
    else if any ((>= steps) . (.step)) faults
      then Left "fault step lies outside the run"
      else Right (n ** m ** p ** MkFixture plant x0 steps disturbance noise faults)

export
simulate : {n, m, p : Nat} -> Fixture n m p -> (Sim n m p, List Frame)
simulate fx = go 0 fx.disturbance fx.noise (start fx.x0) [<]
  where
    go : Nat -> List (Vect n Double) -> List (Vect p Double) -> Sim n m p -> SnocList Frame -> (Sim n m p, List Frame)
    go k (w :: ws) (v :: vs) s acc = let (s', entry) = frame fx.plant fx.faults k w v s in go (S k) ws vs s' (acc :< entry)
    go _ _ _ s acc = (s, acc <>> [])
