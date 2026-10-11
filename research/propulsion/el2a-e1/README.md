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
```

`trace_checks.py` verifies complete CSV v8 recordings at a declared duration and
tick rate. It reuses the existing EL2 battery equations and tolerance constants,
and checks finite samples, exact tick sequence, serialized sample times,
configuration identity, initial state, current, voltage, charge and energy.
Its negative fixtures run through `research/test-tools.sh`.

These tools establish numerical and software behavior. They do not identify a
motor, battery or ESC, validate Timber performance, or close Gate P.

See the [evidence report](../../../docs/research/propulsion/EL2a-E1/README.md).
