||| Abstract dimensional analysis. A `Dimension` is an exponent vector over four
||| artificial base dimensions; `RateLike` and `AngularRateLike` are derived, so
||| adding an angle to a rate is a type error while `rate * time` is an exact
||| length. No SI units or physical scales are attached to anything here.
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
inv : Dimension -> Dimension
inv (MkDim a b c d) = MkDim (negate a) (negate b) (negate c) (negate d)

public export
dimDiv : Dimension -> Dimension -> Dimension
dimDiv x y = dimMul x (inv y)

public export
data Quantity : Dimension -> Type where
  Q : Double -> Quantity d

public export
raw : Quantity d -> Double
raw (Q x) = x

public export TimeD : Dimension
TimeD = MkDim 1 0 0 0
public export LengthD : Dimension
LengthD = MkDim 0 1 0 0
public export AngleD : Dimension
AngleD = MkDim 0 0 1 0
public export ControlD : Dimension
ControlD = MkDim 0 0 0 1
public export RateD : Dimension
RateD = dimDiv LengthD TimeD
public export AngularRateD : Dimension
AngularRateD = dimDiv AngleD TimeD

public export Time : Type
Time = Quantity TimeD
public export LengthLike : Type
LengthLike = Quantity LengthD
public export RateLike : Type
RateLike = Quantity RateD
public export AngleLike : Type
AngleLike = Quantity AngleD
public export AngularRateLike : Type
AngularRateLike = Quantity AngularRateD
public export ControlLike : Type
ControlLike = Quantity ControlD

||| Addition requires identical dimensions.
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

||| Position-like and angle-like components advance by rate-like times a period.
||| These are rows 0 and 2 of the synthetic A matrix, with the unit algebra
||| checked by the type checker rather than by convention.
public export
advanceLength : LengthLike -> RateLike -> Time -> LengthLike
advanceLength p r dt = qadd p (qmul r dt)

public export
advanceAngle : AngleLike -> AngularRateLike -> Time -> AngleLike
advanceAngle a w dt = qadd a (qmul w dt)

public export
record AbstractState where
  constructor MkState
  pos     : LengthLike
  rate    : RateLike
  angle   : AngleLike
  angRate : AngularRateLike
