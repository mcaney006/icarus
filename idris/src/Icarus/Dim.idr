module Icarus.Dim

%default total

public export
record Dimension where
  constructor MkDim
  time, len, ang, ctl : Integer

public export
dimMul : Dimension -> Dimension -> Dimension
dimMul (MkDim a b c d) (MkDim e f g h) = MkDim (a + e) (b + f) (c + g) (d + h)

public export
dimInv : Dimension -> Dimension
dimInv (MkDim a b c d) = MkDim (negate a) (negate b) (negate c) (negate d)

public export
dimDiv : Dimension -> Dimension -> Dimension
dimDiv x y = dimMul x (dimInv y)

public export
data Quantity : Dimension -> Type where
  Q : Double -> Quantity d

public export
raw : Quantity d -> Double
raw (Q x) = x

public export
TimeD, LengthD, AngleD, ControlD, RateD, AngularRateD : Dimension
TimeD = MkDim 1 0 0 0
LengthD = MkDim 0 1 0 0
AngleD = MkDim 0 0 1 0
ControlD = MkDim 0 0 0 1
RateD = dimDiv LengthD TimeD
AngularRateD = dimDiv AngleD TimeD

public export
Time, LengthLike, RateLike, AngleLike, AngularRateLike, ControlLike : Type
Time = Quantity TimeD
LengthLike = Quantity LengthD
RateLike = Quantity RateD
AngleLike = Quantity AngleD
AngularRateLike = Quantity AngularRateD
ControlLike = Quantity ControlD

public export
qadd : Quantity d -> Quantity d -> Quantity d
qadd (Q a) (Q b) = Q (a + b)

public export
qsub : Quantity d -> Quantity d -> Quantity d
qsub (Q a) (Q b) = Q (a - b)

public export
qmul : Quantity d1 -> Quantity d2 -> Quantity (dimMul d1 d2)
qmul (Q a) (Q b) = Q (a * b)

public export
qdiv : Quantity d1 -> Quantity d2 -> Quantity (dimDiv d1 d2)
qdiv (Q a) (Q b) = Q (a / b)

public export
advanceLength : LengthLike -> RateLike -> Time -> LengthLike
advanceLength position rate dt = qadd position (qmul rate dt)

public export
advanceAngle : AngleLike -> AngularRateLike -> Time -> AngleLike
advanceAngle angle rate dt = qadd angle (qmul rate dt)

public export
rateOver : LengthLike -> Time -> RateLike
rateOver = qdiv
