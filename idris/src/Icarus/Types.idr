module Icarus.Types

%default total

public export
data Mode = Boot | SelfTest | Calibrating | Ready | Running | Degraded | Safe | Fault

namespace Health
  public export
  data Health = Healthy | Suspect | Degraded | Unsafe

public export
data FaultKind
  = MeasurementDropout | StaleMeasurement | BiasedMeasurement | StuckChannel
  | OutOfRange | TimingOverrun | NumericSaturation | CorruptFixture
  | EstimatorDisagreement | ControlSaturation
