# E0b3a — compatible downwash and propwash tail laws

2026-10-07 · **Status: implemented and verified; parent E0b3 remains partial.** Stik propwash stays disabled. This step removes the tail-law incompatibility before E0b3b changes geometry, wake edges or reverse flow.

## Change and assumption

The Stik's [E0a2 free-tail law](../../aero-consistency/E0a2a/README.md) separates free-tail slope, elevator effectiveness and wing downwash. The existing P-51 slipstream increment used the older effective-tail law. Combining them would subtract a different free-tail load from the one already in the aircraft model; the loader previously rejected that combination.

For a horizontal tail with `free_slope`, both washed and free evaluations now use:

```text
flow = aircraft air velocity + omega cross arm [+ wash velocity]
effective angle = wrap(atan2(flow.z, flow.x)
                      - downwash_per_cl * wing_CL
                      + elevator_tau * elevator + free_incidence)
CL = existing tail curve(effective angle, free_slope)
increment = washed load - free load
```

Both passes use the same pressure arm, rate contribution and wing CL. `Dynamics` forwards the session's held downwash state to `Slipstream`, as it already does to `Aero`. Standalone `Slipstream.loads(..., downwash_cl=NAN)` resolves instantaneous wing CL. The lower-level `Aero.tail_surface_load`/`tail_surface_increment` helpers have no complete wing state: their documented default `0.0` means **zero wing downwash**; callers evaluating a free-tail model must explicitly supply the intended CL. Legacy P-51 tails ignore this argument and keep their arithmetic order.

Using the same **angular** downwash in the accelerated and free flows is an explicit quasi-steady approximation inherited from E0a2. It is not a resolved interaction between the wing downwash velocity field and propeller jet, and no new flight-fidelity claim is made. No transport state is added. The loader now accepts explicit combined configurations; no aircraft configuration or golden flight changes.

## Evidence

- [Regression test](../../../../app/tests/test_slipstream_downwash.gd), [results](checks.log): **15 checks pass**. Three manufactured rectangular wash pieces exercise the combined laws; their dimensions and wash factors are test inputs, not Stik calibration.
- Across 300 rate/control/stall/held-CL cases, the helper agrees with the existing local-tail contribution to **3.91e-14** absolute component error. Zero added velocity gives exactly zero increment. Free-tail force and rotational work remain passive; this assertion intentionally excludes powered wash, which adds energy.
- Scalar production increments match the tested helper exactly across **900 immersed pieces**. Elevator derivatives use `free_slope * elevator_tau`; powered static fixtures produce differential elevator and opposite rudder authority.
- An actual `FlightSession` with deliberately displaced lag verifies shared held CL through `Dynamics`; the instantaneous alternative differs materially. Missing configuration, stopped propeller and zero wash factors produce exact zero increments. Production Stik data remains unconfigured.
- [Five isolated mutations](mutations.log), [runner](check_mutations.py), all fail assertions: disconnected session lag, ignored held CL, restored old scalar slope, restored old elevator effectiveness, and restored old helper slope. Baseline and restored copies pass; the shared application is never mutated.
- Existing P-51 scalar/oracle regression: **10,001 comparisons pass**. All **16 fleet fingerprints** (four aircraft × four regimes × 960 ticks) remain identical to baseline `cf3c356`; [cost and fingerprint record](cost.json). Skill lint: zero errors, the same 12 existing warnings before/after.
- [Full application suite](suite-summary.log): **107 sections pass**, exit 0, no engine errors; golden flights and trimmed traces pass, with identical states at 30/60/144 FPS. Run on the shared working tree using pinned Godot 4.7.2.

## Cost and enablement limit

The [manufactured combined-model benchmark](bench_combined.gd) runs a real session for five restored batches of 120 ticks per case, initialized at maximum rpm. Labels describe initial flow; each session then evolves. The fixture is not a calibrated Stik. All batches complete without simulation faults.

| Initial condition | Wash off (µs/tick median) | Wash on | Delta |
| --- | ---: | ---: | ---: |
| 15 m/s, alpha 3° | 348.6 | 565.6 | +217.0 |
| 15 m/s, alpha 15° | 358.5 | 562.2 | +203.7 |
| Static, airborne | 322.8 | 487.4 | +164.6 |

These are the [repeat measurements after the suite exited](combined-cost-quiet.log), on the same shared Linux/i5-10500 host; “quiet” means no concurrent suite, not exclusive host access. The [earlier concurrent run](combined-cost.log) measured enabled forward/stall at 525.1/527.1 µs. Both runs exceed the **500 µs/tick budget** in those synthetic cases. Profile the enabled route before E0b3b ships a configuration; do not attribute the overrun solely to test contention. This compatibility step does not close Gate P or establish a performance regression in a default aircraft. Default-fleet before/after measurements and exact fingerprints are retained separately in `cost.json`.

## Scope left for E0b3b

Reduce the [E0b2 neutral polygons](../E0b2/README.md) into bounded runtime pieces, account for the 5 mm tail-reference mismatch, and implement/verify smooth wake edges and reverse-flow fade before enabling Stik wash. Update component benchmark helper calls to supply held CL when adding a combined-model aircraft fixture. E0b4 owns decay/coverage calibration; E0b5 owns transport. Static test authority here does not validate the real airplane or its existing top-hat wake.

## Reproduce

```bash
$(app/get-godot.sh) --headless --path app --script res://tests/test_slipstream_downwash.gd
$(app/get-godot.sh) --headless --path app --script res://tests/test_slipstream_scalar.gd
python3 docs/research/propwash/E0b3a/check_mutations.py
$(app/get-godot.sh) --headless --path app --script "$PWD/docs/research/propwash/E0b3a/bench_combined.gd"
app/test.sh
```

Sources are the existing E0a2 law and repository implementation. The manufactured fixture is provenance-labeled `estimated` and carries no external aerodynamic evidence.
