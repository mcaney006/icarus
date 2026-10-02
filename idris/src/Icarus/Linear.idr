||| Dimension-indexed linear algebra. A matrix product only typechecks when the
||| inner dimensions agree, and the result type carries the outer ones, so the
||| dimension errors the plant could suffer are unrepresentable. Reductions are
||| strict left folds so the floating-point operation order matches the Python
||| reference exactly.
module Icarus.Linear

import Data.Vect

%default total

public export
Matrix : Nat -> Nat -> Type -> Type
Matrix r c a = Vect r (Vect c a)

public export
dot : Num a => Vect n a -> Vect n a -> a
dot xs ys = foldl (+) (fromInteger 0) (zipWith (*) xs ys)

public export
vadd : Num a => Vect n a -> Vect n a -> Vect n a
vadd = zipWith (+)

public export
vsub : Neg a => Vect n a -> Vect n a -> Vect n a
vsub = zipWith (-)

public export
vneg : Neg a => Vect n a -> Vect n a
vneg = map negate

public export
smul : Num a => a -> Vect n a -> Vect n a
smul s = map (s *)

public export
matVec : Num a => Matrix r c a -> Vect c a -> Vect r a
matVec m v = map (\row => dot row v) m

public export
transpose' : {r, c : Nat} -> Matrix r c a -> Matrix c r a
transpose' = transpose

public export
matMul : Num a => {c, p : Nat} -> Matrix r c a -> Matrix c p a -> Matrix r p a
matMul a b = let bt = transpose b in map (\row => map (dot row) bt) a

public export
identity : Num a => {n : Nat} -> Matrix n n a
identity = rows 0 n
  where
    row : Nat -> Nat -> (k : Nat) -> Vect k a
    row i j Z = []
    row i j (S k) = (if i == j then fromInteger 1 else fromInteger 0) :: row i (S j) k
    rows : Nat -> (k : Nat) -> Vect k (Vect n a)
    rows i Z = []
    rows i (S k) = row i 0 n :: rows (S i) k

public export
norm2 : Vect n Double -> Double
norm2 v = sqrt (dot v v)

public export
clampAll : Double -> Vect n Double -> Vect n Double
clampAll lim = map (\x => max (negate lim) (min lim x))
