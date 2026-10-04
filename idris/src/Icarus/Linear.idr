module Icarus.Linear

import public Data.Vect

%default total

public export
Matrix : Nat -> Nat -> Type -> Type
Matrix r c a = Vect r (Vect c a)

public export
dot : Num a => Vect n a -> Vect n a -> a
dot xs ys = foldl (+) 0 (zipWith (*) xs ys)

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
matVec : Num a => Matrix r c a -> Vect c a -> Vect r a
matVec m v = map (`dot` v) m

public export
matMul : Num a => {p : Nat} -> Matrix r c a -> Matrix c p a -> Matrix r p a
matMul a b = map (\row => map (dot row) (transpose b)) a

public export
identity : Num a => {n : Nat} -> Matrix n n a
identity = map (\i => map (\j => if i == j then 1 else 0) range) range

public export
norm2 : Vect n Double -> Double
norm2 v = sqrt (dot v v)

public export
clampAll : Double -> Vect n Double -> Vect n Double
clampAll limit = map (max (negate limit) . min limit)

public export
exceeds : Double -> Vect n Double -> Bool
exceeds limit = any (\x => abs x > limit + 1.0e-12)
