||| The controller lifecycle as an indexed family. `Legal from to` has one
||| constructor per allowed transition, so a transition not listed (Boot to
||| Running, Safe to Running, Fault to Ready, ...) has no inhabitant and any
||| program that needs one is rejected by the type checker. `Controller m` is a
||| value only constructible in mode `m`.
module Icarus.Mode

%default total

public export
data Mode = Boot | SelfTest | Calibrating | Ready | Running | Degraded | Safe | Fault

public export
Eq Mode where
  Boot == Boot = True
  SelfTest == SelfTest = True
  Calibrating == Calibrating = True
  Ready == Ready = True
  Running == Running = True
  Degraded == Degraded = True
  Safe == Safe = True
  Fault == Fault = True
  _ == _ = False

public export
modeCode : Mode -> Int
modeCode Boot = 0
modeCode SelfTest = 1
modeCode Calibrating = 2
modeCode Ready = 3
modeCode Running = 4
modeCode Degraded = 5
modeCode Safe = 6
modeCode Fault = 7

public export
data Legal : Mode -> Mode -> Type where
  Stay       : Legal m m
  SelfTested : Legal Boot SelfTest
  Calibrate  : Legal SelfTest Calibrating
  Calibrated : Legal Calibrating Ready
  Engage     : Legal Ready Running
  Degrade    : Legal Running Degraded
  Recover    : Legal Degraded Running
  RunUnsafe  : Legal Running Safe
  DegUnsafe  : Legal Degraded Safe
  ReadySafe  : Legal Ready Safe
  BootFault  : Legal Boot Fault
  TestFault  : Legal SelfTest Fault
  CalFault   : Legal Calibrating Fault

||| A controller in mode `m`. The payload is the monitor state; the point is that
||| the index cannot be forged.
public export
record Controller (m : Mode) where
  constructor MkController
  healthyStreak : Nat
  badFrames     : Nat

public export
transition : Controller m -> Legal m m' -> Controller m'
transition (MkController h b) _ = MkController h b

||| Full cold start, expressed as a chain of legal transitions. There is no
||| shorter well-typed path from Boot to Running.
public export
startup : Controller Boot -> Controller Ready
startup c = transition (transition (transition c SelfTested) Calibrate) Calibrated

||| Safe is absorbing: nothing leaves it except itself.
public export
Uninhabited (Legal Safe Running) where
  uninhabited Stay impossible

public export
Uninhabited (Legal Boot Running) where
  uninhabited Stay impossible

public export
Uninhabited (Legal Fault Ready) where
  uninhabited Stay impossible
