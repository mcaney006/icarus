module Neg.UnitsOk
import Icarus.Dim

good : AngleLike -> AngularRateLike -> Time -> AngleLike
good a w dt = advanceAngle a w dt
