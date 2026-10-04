module Icarus.Plant

import Data.List
import Icarus.Linear
import public Icarus.Mode
import Icarus.Ring

%default total

public export
measLimit, innovThresh, stateBound, ctrlLimit, degradedCtrl, stuckValue : Double
measLimit = 50.0
ctrlLimit = 1.0
innovThresh = 10.0
stateBound = 1000.0
degradedCtrl = 0.5
stuckValue = 7.0

public export
recoveryFrames, degradedLimit : Nat
recoveryFrames = 3
degradedLimit = 3

public export
frameBudget, nominalFrameCost : Int
frameBudget = 1000
nominalFrameCost = 900

public export
record FaultEvent (p : Nat) where
  constructor MkFault
  step : Nat
  kind : FaultKind
  lane : Fin p
  param : Double

public export
record Plant (n, m, p : Nat) where
  constructor MkPlant
  aMat : Matrix n n Double
  bMat : Matrix n m Double
  cMat : Matrix p n Double
  kGain : Matrix m n Double
  lGain : Matrix n p Double

public export
innovation : Plant n m p -> Vect n Double -> Vect p Double -> Vect p Double
innovation plant xhat y = vsub y (matVec plant.cMat xhat)

public export
observe : Plant n m p -> Vect n Double -> Vect m Double -> Vect p Double -> Vect n Double
observe plant xhat uPrev y =
  vadd (vadd (matVec plant.aMat xhat) (matVec plant.bMat uPrev)) (matVec plant.lGain (innovation plant xhat y))

public export
advance : Plant n m p -> Vect n Double -> Vect m Double -> Vect n Double -> Vect n Double
advance plant x u w = vadd (vadd (matVec plant.aMat x) (matVec plant.bMat u)) w

median3 : Double -> Double -> Double -> Double
median3 a b c = max (min a b) (min (max a b) c)

public export
record Flags where
  constructor MkFlags
  meas, est, timing, ctrlSat, numeric : Bool

bits : Flags -> List Bool
bits f = [f.meas, f.est, f.timing, f.ctrlSat, f.numeric]

public export
noFlags : Flags
noFlags = MkFlags False False False False False

public export
flagMask : Flags -> Nat
flagMask = foldr (\set, rest => (if set then 1 else 0) + 2 * rest) 0 . bits

public export
classify : Flags -> Health
classify f = if f.numeric then Unsafe else case length (filter id (bits f)) of
  0 => Healthy
  1 => Suspect
  _ => Degraded

public export
decideMode : (m : Mode) -> Health -> (miss : Bool) -> (healthy, bad : Nat) -> (m' : Mode ** Legal m m')
decideMode Ready _ _ _ _ = (Running ** Engage)
decideMode Running Unsafe _ _ _ = (Safe ** RunUnsafe)
decideMode Running Degraded _ _ _ = (Degraded ** Degrade)
decideMode Running _ miss _ _ = if miss then (Degraded ** Degrade) else (Running ** Stay)
decideMode Degraded Unsafe _ _ _ = (Safe ** DegUnsafe)
decideMode Degraded Healthy _ healthy _ = if healthy + 1 >= recoveryFrames then (Running ** Recover) else (Degraded ** Stay)
decideMode Degraded _ _ _ bad = if bad + 1 >= degradedLimit then (Safe ** DegUnsafe) else (Degraded ** Stay)
decideMode m _ _ _ _ = (m ** Stay)

public export
record Monitor where
  constructor MkMonitor
  mode : Mode
  healthy : Nat
  bad : Nat

public export
initial : Monitor
initial = MkMonitor Ready 0 0

public export
next : (s : Monitor) -> Health -> (miss : Bool) -> (s' : Monitor ** Legal s.mode s'.mode)
next s health miss =
  let (mode ** legal) = decideMode s.mode health miss s.healthy s.bad
      healthy = if health == Healthy then S s.healthy else 0
      bad = case (s.mode, mode) of
              (Running, Degraded) => 0
              (Degraded, Degraded) => if health == Healthy then s.bad else S s.bad
              _ => s.bad
  in (MkMonitor mode healthy bad ** legal)

public export
record Frame where
  constructor MkFrame
  mode : Mode
  health : Health
  mask : Nat

public export
record Sim (n, m, p : Nat) where
  constructor MkSim
  x, xhat : Vect n Double
  uPrev : Vect m Double
  lastMeas : Vect p Double
  monitor : Monitor
  history : Ring 4 Health

public export
start : {n, m, p : Nat} -> Vect n Double -> Sim n m p
start x0 = MkSim x0 (replicate n 0.0) (replicate m 0.0) (replicate p 0.0) initial (empty Healthy)

acquire : {p : Nat} -> (clean, held : Vect p Double) -> List (FaultEvent p) -> (Vect p Double, Bool)
acquire clean held events =
  let (first, second, third, struck) = foldl inject (clean, clean, clean, False) events
  in (zipWith3 median3 first second third, struck)
  where
    Channels : Type
    Channels = (Vect p Double, Vect p Double, Vect p Double, Bool)

    inject : Channels -> FaultEvent p -> Channels
    inject (c0, c1, c2, struck) e = case e.kind of
      BiasedMeasurement => (updateAt e.lane (+ e.param) c0, c1, c2, True)
      StuckChannel => (replaceAt e.lane stuckValue c0, c1, c2, True)
      OutOfRange => (replaceAt e.lane e.param c0, c1, c2, True)
      MeasurementDropout =>
        let hold = replaceAt e.lane (index e.lane held) in (hold c0, hold c1, hold c2, True)
      _ => (c0, c1, c2, struck)

public export
frame : {n, m, p : Nat} -> Plant n m p -> List (FaultEvent p) -> (k : Nat)
     -> (w : Vect n Double) -> (v : Vect p Double) -> Sim n m p -> (Sim n m p, Frame)
frame plant faults k w v s =
  let events = filter ((== k) . (.step)) faults
      present = \kind => any ((== kind) . (.kind)) events
      mode = s.monitor.mode
      (voted, channelFault) = acquire (vadd (matVec plant.cMat s.x) v) s.lastMeas events
      stale = present StaleMeasurement
      sample = if stale then s.lastMeas else voted
      y = clampAll measLimit sample
      xhat = observe plant s.xhat s.uPrev y
      overrun = (.param) <$> Data.List.find ((== TimingOverrun) . (.kind)) events
      miss = maybe False (\ticks => nominalFrameCost + cast ticks > frameBudget) overrun
      active = mode == Running || mode == Degraded
      limit = if mode == Degraded then degradedCtrl else ctrlLimit
      raw = vneg (matVec plant.kGain xhat)
      u = if active then clampAll limit raw else map (const 0.0) raw
      flags = MkFlags (channelFault || stale || exceeds measLimit sample)
                      (norm2 (innovation plant s.xhat y) > innovThresh || present EstimatorDisagreement)
                      miss
                      (active && (exceeds limit raw || present ControlSaturation))
                      (any (\z => not (abs z <= stateBound)) xhat || present NumericSaturation)
      health = classify flags
      (monitor ** _) = next s.monitor health miss
  in (MkSim (advance plant s.x u w) xhat u y monitor (push health s.history), MkFrame mode health (flagMask flags))
