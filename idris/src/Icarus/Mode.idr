module Icarus.Mode

import public Icarus.Codes

%default total

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

public export
record Controller (m : Mode) where
  constructor MkController
  healthyStreak : Nat
  badFrames : Nat

public export
transition : Controller m -> Legal m m' -> Controller m'
transition (MkController h b) _ = MkController h b

public export
startup : Controller Boot -> Controller Ready
startup c = transition (transition (transition c SelfTested) Calibrate) Calibrated

public export
Uninhabited (Legal Safe Running) where
  uninhabited Stay impossible

public export
Uninhabited (Legal Boot Running) where
  uninhabited Stay impossible

public export
Uninhabited (Legal Fault Ready) where
  uninhabited Stay impossible
