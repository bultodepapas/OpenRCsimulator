# AE-01-R1 — per-surface travel integration

2026-10-26. Integrates the useful Workshop controls from [PR #1](https://github.com/bultodepapas/OpenRCsimulator/pull/1), preserving its original commits. The [integration disposition](../../flight-mechanics-stall-hover-knife-edge-2026-10-18.md#integration-disposition-2026-10-26) explains why its experimental aerodynamics and replacement goldens were deferred.

## Contract

Optional aileron, elevator and rudder travel multipliers inherit the global value when absent. Normalization, saved variants, recovery and experiments preserve that absence. Explicit overrides select a new compiler identity; existing builds keep their pins and require Save a copy when crossing identities. Unsupported surfaces and nonfinite/out-of-range values are refused.

The UI uses effective values, resets overrides on a master change, retains undo/redo and disclosure state, and reports compiled throws in degrees. Presets retain global inheritance. The comparison table handles absent defaults without converting null to float. Recovery retains unfinished numeric text separately from the accepted physical recipe.

## Same-tape evidence

The [retained artifacts](../../../../research/aircraft-editor/AE-01-R1/) include the baseline `.orfl`, exact input recipe, compiler-generated candidate, compressed CSVs, unmodified export/replay/comparison reports and a SHA-256 manifest. The solver and stock aircraft data match base `41fb8dae9269e5dce39e2380832e5af206eb271e`; development build metadata has no embedded commit, so this identity is recorded explicitly in the manifest.

The existing flight-log regression generated the Jensen Stik baseline: ticks 0–260 at 240 Hz, with a roll-reversal marker at tick 56 and checkpoint resume at tick 61. Exact replay completed with `solver_changed=false`, 261 rows and no divergence. The candidate changes only the requested aileron factor to 1.2 through `WorkshopCompiler.compile`: compiled throws are 24°/20°/25°. JSON serialization also rounds one `Cldr` quantity at the last few decimal places; stock source data is untouched.

Candidate replay completed with the same solver and input tape. The maximum roll-rate difference was 0.0536777217 rad/s at tick 44; the maximum position-component difference was 0.0183858835 m at tick 260. These are short scripted software response checks, not pilot adaptation, physical measurements, or validation of stall/hover behavior.

Reproduce with the [flight logging workflow](../../../FLIGHT-LOGGING.md), using new output directories:

```sh
evidence=research/aircraft-editor/AE-01-R1
python3 tools/flight_log/flight_log.py export "$evidence/baseline.orfl" --godot "$(app/get-godot.sh)" --out tmp/ae01r1-export
python3 tools/flight_log/flight_log.py replay "$evidence/baseline.orfl" --godot "$(app/get-godot.sh)" --out tmp/ae01r1-exact
python3 tools/flight_log/flight_log.py replay "$evidence/baseline.orfl" --candidate "$evidence/candidate.json" --godot "$(app/get-godot.sh)" --out tmp/ae01r1-candidate
python3 tools/flight_log/flight_log.py compare tmp/ae01r1-export/flight.csv tmp/ae01r1-candidate/flight.csv --out tmp/ae01r1-comparison.json
```

## Verification

Engine: Godot 4.8 beta1, Linux. The existing flight-log regression passed 3,247 checks across six aircraft. Aerodynamic flow, ground effect (51 checks), wing polar (126 checks) and golden-flight (4 checks) suites passed without re-recording goldens. These checks verify the retained production baseline, not the deferred contributor aerodynamic proposal.
