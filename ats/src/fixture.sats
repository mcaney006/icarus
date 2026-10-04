#define STEP_CAPACITY 128
#define FAULT_CAPACITY 16
#define INPUT_CAPACITY 65536

typedef lane = natLt(2)
typedef fault_kind = natLt(10)
typedef step_count = natLte(STEP_CAPACITY)
typedef fault_count = natLte(FAULT_CAPACITY)

datavtype cfg_vt =
  | CFG of (
      matrixptr(double, 4, 4), matrixptr(double, 4, 2), matrixptr(double, 2, 4),
      matrixptr(double, 2, 4), matrixptr(double, 4, 2),
      matrixptr(double, STEP_CAPACITY, 6), arrayptr(double, 4),
      arrayptr(int, FAULT_CAPACITY), arrayptr(fault_kind, FAULT_CAPACITY),
      arrayptr(lane, FAULT_CAPACITY), arrayptr(double, FAULT_CAPACITY),
      step_count, fault_count)

fun load_fixture (path: string): Option_vt(cfg_vt)
fun cfg_free (c: cfg_vt): void
fun cfg_steps (c: !cfg_vt): step_count
