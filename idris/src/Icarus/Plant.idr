||| Typed executable model of the abstract plant, observer, controller, health
||| monitor, fault injection and frame loop. State dimension `n`, control
||| dimension `m` and measurement dimension `p` are indices on every record that
||| mentions them, so an estimator built for (n, p) cannot be handed a
||| measurement or covariance of the wrong size. Mode decisions return a
||| `Legal from to` witness: a branch that tried an illegal transition would not
||| typecheck. Operation order mirrors reference/icarus_ref.py exactly.
module Icarus.Plant

import Data.Vect
import Data.Fin
import Data.List
import Icarus.Linear
import Icarus.Mode
import Icarus.Ring

%default total

-- ---------------------------------------------------------------- constants --

public export measLimit : Double
measLimit = 50.0
public export innovThresh : Double
innovThresh = 10.0
public export stateBound : Double
stateBound = 1000.0
public export degradedCtrl : Double
degradedCtrl = 0.5
public export stuckValue : Double
stuckValue = 7.0
public export recoveryFrames : Nat
recoveryFrames = 3
public export degradedLimit : Nat
degradedLimit = 3
public export frameBudget : Int
frameBudget = 1000
public export stageSum : Int
stageSum = 900

-- ------------------------------------------------------------------- typed ---

public export
data Health = Healthy | Suspect | DegradedH | Unsafe

public export
healthCode : Health -> Int
healthCode Healthy = 0
healthCode Suspect = 1
healthCode DegradedH = 2
healthCode Unsafe = 3

public export
data FaultKind
  = MeasurementDropout | StaleMeasurement | BiasedMeasurement | StuckChannel
  | OutOfRange | TimingOverrun | NumericSaturation | CorruptFixture
  | EstimatorDisagreement | ControlSaturation

public export
faultOfCode : Int -> Maybe FaultKind
faultOfCode 0 = Just MeasurementDropout
faultOfCode 1 = Just StaleMeasurement
faultOfCode 2 = Just BiasedMeasurement
faultOfCode 3 = Just StuckChannel
faultOfCode 4 = Just OutOfRange
faultOfCode 5 = Just TimingOverrun
faultOfCode 6 = Just NumericSaturation
faultOfCode 7 = Just CorruptFixture
faultOfCode 8 = Just EstimatorDisagreement
faultOfCode 9 = Just ControlSaturation
faultOfCode _ = Nothing

||| A fault targets a measurement component, so its channel is a `Fin p`.
public export
record FaultEvent (p : Nat) where
  constructor MkFault
  step  : Nat
  kind  : FaultKind
  chan  : Fin p
  param : Double

||| The linear plant. Every matrix carries its own dimensions.
public export
record Plant (n, m, p : Nat) where
  constructor MkPlant
  aMat : Matrix n n Double
  bMat : Matrix n m Double
  cMat : Matrix p n Double
  kGain : Matrix m n Double
  lGain : Matrix n p Double

||| An estimator is only definable for a plant, and `observe` only accepts a
||| `Vect p` measurement and `Vect m` control for that same plant.
public export
observe : Plant n m p -> (xhat : Vect n Double) -> (uPrev : Vect m Double)
       -> (y : Vect p Double) -> Vect n Double
observe pl xhat uPrev y =
  let innov = vsub y (matVec pl.cMat xhat)
  in vadd (vadd (matVec pl.aMat xhat) (matVec pl.bMat uPrev)) (matVec pl.lGain innov)

public export
innovation : Plant n m p -> Vect n Double -> Vect p Double -> Vect p Double
innovation pl xhat y = vsub y (matVec pl.cMat xhat)

public export
advancePlant : Plant n m p -> Vect n Double -> Vect m Double -> Vect n Double -> Vect n Double
advancePlant pl x u w = vadd (vadd (matVec pl.aMat x) (matVec pl.bMat u)) w

median3 : Double -> Double -> Double -> Double
median3 a b c = max (min a b) (min (max a b) c)

-- -------------------------------------------------------------- flag masks ---

public export
record Flags where
  constructor MkFlags
  meas, est, timing, ctrlSat, numeric : Bool

public export
noFlags : Flags
noFlags = MkFlags False False False False False

public export
flagMask : Flags -> Int
flagMask f = b f.meas 1 + b f.est 2 + b f.timing 4 + b f.ctrlSat 8 + b f.numeric 16
  where b : Bool -> Int -> Int
        b True v = v
        b False _ = 0

flagCount : Flags -> Int
flagCount f = c f.meas + c f.est + c f.timing + c f.ctrlSat + c f.numeric
  where c : Bool -> Int
        c True = 1
        c False = 0

public export
classify : Flags -> Health
classify f =
  if f.numeric then Unsafe
  else if flagCount f >= 2 then DegradedH
  else if flagCount f == 1 then Suspect
  else Healthy

-- ----------------------------------------------------------- mode decision ---

||| The next mode together with a proof it is a legal successor. Totality plus
||| the `Legal` index make this the only place transitions are chosen.
public export
decideMode : (m : Mode) -> Health -> (miss : Bool) -> (healthyStreak, badFrames : Nat)
          -> (m' : Mode ** Legal m m')
decideMode Ready _ _ _ _ = (Running ** Engage)
decideMode Running h miss _ _ =
  case h of
    Unsafe => (Safe ** RunUnsafe)
    DegradedH => (Degraded ** Degrade)
    _ => if miss then (Degraded ** Degrade) else (Running ** Stay)
decideMode Degraded h _ hs bad =
  case h of
    Unsafe => (Safe ** DegUnsafe)
    Healthy => if hs + 1 >= recoveryFrames then (Running ** Recover) else (Degraded ** Stay)
    _ => if bad + 1 >= degradedLimit then (Safe ** DegUnsafe) else (Degraded ** Stay)
decideMode m _ _ _ _ = (m ** Stay)

-- ------------------------------------------------------------------ frames ---

public export
record Frame where
  constructor MkFrame
  mode   : Mode
  health : Health
  mask   : Int

public export
record Sim (n, m, p : Nat) where
  constructor MkSim
  x, xhat   : Vect n Double
  uPrev     : Vect m Double
  lastMeas  : Vect p Double
  mode      : Mode
  healthy   : Nat
  bad       : Nat
  history   : Ring 4 Health

faultsAt : Nat -> List (FaultEvent p) -> List (FaultEvent p)
faultsAt k = filter (\f => f.step == k)

hasKind : (FaultKind -> Bool) -> List (FaultEvent p) -> Bool
hasKind pr = any (\f => pr f.kind)

isStale, isOverrun, isNumSat, isEstDis, isCtrlSat : FaultKind -> Bool
isStale StaleMeasurement = True
isStale _ = False
isOverrun TimingOverrun = True
isOverrun _ = False
isNumSat NumericSaturation = True
isNumSat _ = False
isEstDis EstimatorDisagreement = True
isEstDis _ = False
isCtrlSat ControlSaturation = True
isCtrlSat _ = False

overrunTicks : List (FaultEvent p) -> Maybe Int
overrunTicks fs = case Data.List.find (\f => isOverrun f.kind) fs of
  Nothing => Nothing
  Just f  => Just (cast f.param)

||| Apply the redundant-channel faults to channel 0, then vote per component.
voteChannels : {p : Nat} -> Vect p Double -> Vect p Double -> List (FaultEvent p)
            -> (Vect p Double, Bool)
voteChannels base lastMeas fs =
  let (ch0, flagged) = foldl applyF (base, False) fs
      -- channels 1 and 2 stay healthy except for dropout, which hits all three
      (ch1, ch2) = foldl applyAll (base, base) fs
      voted = zipWith3 median3 ch0 ch1 ch2
  in (voted, flagged)
  where
    applyF : (Vect p Double, Bool) -> FaultEvent p -> (Vect p Double, Bool)
    applyF (v, fl) f = case f.kind of
      BiasedMeasurement => (updateAt f.chan (+ f.param) v, True)
      StuckChannel      => (replaceAt f.chan stuckValue v, True)
      OutOfRange        => (replaceAt f.chan f.param v, True)
      MeasurementDropout => (replaceAt f.chan (index f.chan lastMeas) v, True)
      _ => (v, fl)
    applyAll : (Vect p Double, Vect p Double) -> FaultEvent p -> (Vect p Double, Vect p Double)
    applyAll (u, w) f = case f.kind of
      MeasurementDropout => (replaceAt f.chan (index f.chan lastMeas) u,
                             replaceAt f.chan (index f.chan lastMeas) w)
      _ => (u, w)

||| One frame of the Acquire..Record schedule. Returns the next simulator state
||| and the frame record.
public export
frame : {n, m, p : Nat} -> Plant n m p -> Double -> List (FaultEvent p)
     -> (k : Nat) -> (w : Vect n Double) -> (v : Vect p Double) -> Sim n m p
     -> (Sim n m p, Frame)
frame pl ctrlLimit allFaults k w v s =
  let fs = faultsAt k allFaults
      -- Acquire
      base = vadd (matVec pl.cMat s.x) v
      (voted, faultFlag) = voteChannels base s.lastMeas fs
      stale = hasKind isStale fs
      yRaw = if stale then s.lastMeas else voted
      -- Normalize
      yClamped = clampAll measLimit yRaw
      outOfBand = any (\z => abs z > measLimit + 1.0e-12) yRaw
      measFlag = faultFlag || stale || outOfBand
      -- Estimate
      innov = innovation pl s.xhat yClamped
      estFlag = norm2 innov > innovThresh || hasKind isEstDis fs
      xhat' = observe pl s.xhat s.uPrev yClamped
      -- timing
      cost = maybe stageSum (stageSum +) (overrunTicks fs)
      miss = isJust (overrunTicks fs) && cost > frameBudget
      -- Control
      active = case s.mode of { Running => True; Degraded => True; _ => False }
      lim = case s.mode of { Degraded => degradedCtrl; _ => ctrlLimit }
      raw = vneg (matVec pl.kGain xhat')
      u = if active then clampAll lim raw else map (const 0.0) raw
      satFlag = active && (any (\z => abs z > lim + 1.0e-12) raw || hasKind isCtrlSat fs)
      -- Validate
      numFlag = any (\z => not (abs z <= stateBound)) xhat' || hasKind isNumSat fs
      flags = MkFlags measFlag estFlag miss satFlag numFlag
      health = classify flags
      -- Decide
      (mode' ** _) = decideMode s.mode health miss s.healthy s.bad
      healthy' = case health of { Healthy => S s.healthy; _ => 0 }
      bad' = case (s.mode, mode') of
               (Running, Degraded) => 0
               (Degraded, Degraded) => (case health of { Healthy => s.bad; _ => S s.bad })
               _ => s.bad
      x' = advancePlant pl s.x u w
  in ( MkSim x' xhat' u yClamped mode' healthy' bad' (push health s.history)
     , MkFrame s.mode health (flagMask flags) )
