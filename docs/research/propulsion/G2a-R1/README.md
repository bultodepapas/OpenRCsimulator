# G2a-R1 — Coupled-stage evaluation parity

2026-10-09 · **Status: software verified; coupled step cost reduced; physical/performance acceptance remains open.**

This evidence step checks that reusing one coupled stage evaluation preserves exact simulation results. The probe uses the same deterministic 240 Hz inputs for each run and records 480 ticks per case. At ticks 0, 1, 120, 240, and 480 it hashes the native flight checkpoint with `var_to_bytes`; that checkpoint includes body and previous state, auxiliary and continuous state, modes, inputs, loads, and aircraft/weather/integrator identity. A rolling SHA-256 covers all 481 checkpoint rows, including the initial row.

Eight cases cover all four catalog aircraft in default split mode, plus the coupled P-51 in calm weather, a repeating gust, seeded OU turbulence with hot-high atmosphere, and the validated transported-wash test fixture. The wash fixture is derived from `test_wash_profile.gd` and remains test-only. The inputs are deterministic probes, not flight validation.

## Reproduce

Run from the repository root with the pinned Godot 4.7 executable. The runner invokes the same external GDScript sequentially against the frozen baseline and working app, then compares every checkpoint and full-trajectory hash.

```sh
python3 docs/research/propulsion/G2a-R1/proof.py \
  --godot "$(app/get-godot.sh)" \
  --baseline /tmp/openrc-stage-baseline \
  --current "$PWD" \
  --out-dir /tmp/openrc-g2a-r1-parity
```

The baseline is the frozen app at `a03503655788b479547da160de024545b4b9e7bb`. On success, `proof.json` records exact parity and all hash pairs; `baseline.json`, `current.json`, and their logs retain the raw probe evidence. A failed flight, missing report, Godot version difference, checkpoint mismatch, or trajectory mismatch exits nonzero.

The probe is in [parity.gd](parity.gd), and the sequential runner and comparison logic are in [proof.py](proof.py). This checks software reproducibility for the G2a stage-cost slice described in [G2a-RK4](../G2a-RK4/README.md); it makes no claim about physical accuracy or runtime cost.

[Proof](proof.json), [baseline raw report](baseline.json) and [candidate raw report](current.json) preserve the measured hashes. The paired run passed all eight cases: 40 checkpoint comparisons plus eight full-trajectory comparisons. The new joint callback computes loads, continuous derivatives and rotor momentum once per RK stage, validates the complete float64 payload, and keeps the existing separate callbacks as its explicit fallback. No physics state or checkpoint layout changes.

The full [app gate](test-gate.json) passes 143 GDScript suites, all-script parsing, float64 guards, 43 joint/coupled checks, existing goldens, seven real-app shaft CLI tests and 30/60/144 FPS checks. Existing estimate notices and shutdown ObjectDB warnings remain, with zero engine errors. [Source manifest](source-manifest.json) identifies the final app/test inputs.

The matched [serial cost comparison](cost.md) observes a 41.8–45.7% reduction in coupled fixture medians, from 1308–1390 to 730–765 µs/step. Shared-host variation remains visible in the untouched split controls; 500 µs acceptance stays open. The complete float64 payload is checked before integration, malformed reset/stage payloads roll back atomically, and no stage-result cache persists beyond the tick.

[Export checks](export-results.json) pass Linux execution and all-platform pack/resource checks. [Source/Linux comparison](native-results.json), using [the existing native comparison tool](../G2a-RK4/native_compare.py), reproduces identical numeric rows for calm, hot-high and combined OU/custom-air flights, with 721 samples per run. Windows/macOS native execution remains outside this software proof.
