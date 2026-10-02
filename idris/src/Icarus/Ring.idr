||| Fixed-capacity history. The index is the true capacity: `Ring 4 a` stores
||| exactly four slots and its occupied length is a `Fin 5`, so length <= capacity
||| holds by construction. The buffer is a `Vect`, always fully initialised, so no
||| uninitialised slot exists to be read. `peek` additionally demands an erased
||| proof that the requested age is below the occupied length; `peekMaybe` is the
||| runtime-checked equivalent for ages that are not statically known.
module Icarus.Ring

import Data.Vect
import Data.Fin
import public Data.Nat

%default total

public export
data Ring : (cap : Nat) -> Type -> Type where
  MkRing : (buf : Vect (S c) a) -> (next : Fin (S c)) -> (len : Fin (S (S c)))
        -> Ring (S c) a

public export
empty : {c : Nat} -> a -> Ring (S c) a
empty fill = MkRing (replicate (S c) fill) FZ FZ

||| Successor that reports overflow, written by structural recursion so it
||| reduces during type checking (library `strengthen` does not).
public export
succF : {n : Nat} -> Fin n -> Maybe (Fin n)
succF {n = S Z} FZ = Nothing
succF {n = S (S k)} FZ = Just (FS FZ)
succF {n = S k} (FS j) = FS <$> succF j

public export
rotate : {c : Nat} -> Fin (S c) -> Fin (S c)
rotate i = case succF i of
  Just j  => j
  Nothing => FZ

public export
bump : {c : Nat} -> Fin (S (S c)) -> Fin (S (S c))
bump i = case succF i of
  Just j  => j
  Nothing => i

public export
push : {c : Nat} -> a -> Ring (S c) a -> Ring (S c) a
push x (MkRing buf next len) = MkRing (replaceAt next x buf) (rotate next) (bump len)

||| Structural Fin-to-Nat so occupied lengths reduce while type checking.
public export
finNat : Fin n -> Nat
finNat FZ = Z
finNat (FS k) = S (finNat k)

public export
occupied : Ring cap a -> Nat
occupied (MkRing _ _ len) = finNat len

||| Slot holding the element written `age` pushes ago; index arithmetic is taken
||| modulo the capacity, so it is always in range.
slot : {c : Nat} -> Ring (S c) a -> Nat -> a
slot (MkRing buf next _) age =
  index (restrict c (cast (finNat next) + cast (S c) - 1 - cast age)) buf

public export
peek : {c : Nat} -> (r : Ring (S c) a) -> (age : Nat)
    -> {auto 0 ok : LTE (S age) (occupied r)} -> a
peek r age = slot r age

public export
peekMaybe : {c : Nat} -> Ring (S c) a -> Nat -> Maybe a
peekMaybe r age = if age < occupied r then Just (slot r age) else Nothing
