module Icarus.Ring

import public Data.Fin
import public Data.Nat
import Data.Maybe
import Data.Vect

%default total

public export
data Ring : (cap : Nat) -> Type -> Type where
  MkRing : (buf : Vect (S c) a) -> (head : Fin (S c)) -> (len : Fin (S (S c))) -> Ring (S c) a

public export
next : {n : Nat} -> Fin n -> Maybe (Fin n)
next {n = S Z} FZ = Nothing
next {n = S (S _)} FZ = Just (FS FZ)
next {n = S _} (FS j) = FS <$> next j

public export
wrapping : {n : Nat} -> Fin (S n) -> Fin (S n)
wrapping i = case next i of
  Just j => j
  Nothing => FZ

public export
saturating : {n : Nat} -> Fin n -> Fin n
saturating i = case next i of
  Just j => j
  Nothing => i

public export
empty : {c : Nat} -> a -> Ring (S c) a
empty fill = MkRing (replicate (S c) fill) FZ FZ

public export
push : {c : Nat} -> a -> Ring (S c) a -> Ring (S c) a
push x (MkRing buf head len) = MkRing (replaceAt head x buf) (wrapping head) (saturating len)

public export
occupied : Ring cap a -> Nat
occupied (MkRing _ _ len) = finToNat len

slot : {c : Nat} -> Ring (S c) a -> Nat -> a
slot (MkRing buf head _) age = index (restrict c (natToInteger (finToNat head + c) - natToInteger age)) buf

public export
peek : {c : Nat} -> (r : Ring (S c) a) -> (age : Nat) -> {auto 0 written : LTE (S age) (occupied r)} -> a
peek r age = slot r age

public export
peekMaybe : {c : Nat} -> Ring (S c) a -> Nat -> Maybe a
peekMaybe r age = toMaybe (age < occupied r) (slot r age)
