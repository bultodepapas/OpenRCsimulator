# EL2a-E1 — electric runway and maneuver qualification

**Status:** executable software qualification tools; synthetic fixtures only.

`verify_runway.py` copies an app into a fresh output directory, imports it with
pinned Godot 4.7.2, requires all 177 runway checks, injects two real startup
defects, restores the original bytes, and repeats the positive control. Engine
errors are failures even when Godot exits zero. The source app is never mutated.

```sh
python3 research/propulsion/el2a-e1/verify_runway.py \
  --app app --godot "$(app/get-godot.sh)" --out /tmp/el2a-e1-runway-new
python3 research/propulsion/el2a-e1/test_trace_checks.py
python3 research/propulsion/el2a-e1/verify_envelope.py \
  --app app --godot "$(app/get-godot.sh)" --out /tmp/el2a-e1-envelope-new
```

`verify_envelope.py` imports a fresh app copy and runs `envelope.gd` for both
synthetic packs at 240/480 Hz: 8 s takeoff, 20 s accelerated stall/recovery and
46 s landing. It requires all twelve cases, checks every CSV sample with the
independent electrical verifier, scores explicit maneuver outcomes, and compares
coarse/fine event metrics against fixed software regression bands. The result
is 106,572 checked samples per platform. It records the driver/verifier hashes
and all copied app `.gd`/`.json`/`project.godot` hashes, and retains per-case JSON,
CSV and engine logs. Large CSVs remain generated artifacts; report JSON stores
their SHA-256 fingerprints.

The landing pilot uses its existing parameters with a declared +2 m approach
start-position shift. Stall entry is a power-off accelerated pull-up from
1.4 times the model's estimated one-g stall speed, not a quasi-static one-g
stall-speed measurement. Recovery requires positive alpha to cross model `a2`,
then unloading and powered recovery with a stable terminal interval.

`trace_checks.py` verifies complete CSV v8 recordings at a declared duration and
tick rate. It reuses the existing EL2 battery equations and tolerance constants,
and checks finite samples, exact tick sequence, serialized sample times,
configuration identity, initial state, current, voltage, charge and energy.
Its negative fixtures run through `research/test-tools.sh`.

These tools establish numerical and software behavior. They do not identify a
motor, battery or ESC, validate Timber performance, or close Gate P.

See the [evidence report](../../../docs/research/propulsion/EL2a-E1/README.md).
