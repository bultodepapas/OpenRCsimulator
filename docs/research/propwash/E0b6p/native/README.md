# E0b6p — Complete smooth-wake native experiment

2026-10-07 · **Status: Linux research prototype verified; whole-tick budget and native adoption remain open.**

Follow-up: [whole-tick and native-phase attribution](../attribution/README.md) now separates the remaining costs and defines the next bounded decoding experiment. The measurements below document the original port.

## Result

The [research-only GDExtension](../../../../../research/propwash/e0b6p/native/src/smooth_wake_extension.cpp) evaluates both smooth axial occupancy and the distributed swirl correction. Production code and aircraft data are unchanged. The experiment retains float64 arithmetic, both original five-point quadrature tables, profile/core/edge splits, accumulation order, current RK-stage inputs, horizontal downwash and stopped-source axial transport. It introduces no temporal cache or reduced physics rate.

The Linux build reuses the [locked Gate P toolchain](../../../../../research/native-slipstream/toolchain-lock.json), with `-fno-fast-math` and `-ffp-contract=off`. The kernel accepts a derived model and checks shapes, finiteness and supported domains; it is not a replacement for AircraftData validation. Model dictionaries are decoded on every call. A disposable adapter supplies thrust/torque, reverse fade and held or instantaneous wing CL. Legacy models continue through GDScript. See [third-party notices](../../../../../research/propwash/e0b6p/native/THIRD_PARTY_NOTICES.md).

## Cost and limits

The [interleaved profile](profile.json) alternates complete GDScript/native calls in one process, including adapter, thrust/torque and binding costs: three warm-up pairs, then 32 measured pairs. Active calls fall from **889–1,127.5 µs to 53.5–60.5 µs**. Reverse cutoff stays at 3 µs through the original early return. The [first-run manifest](first-run-evidence.json) identifies this measurement.

The [whole-tick comparison](trajectory-comparison.json) measures five 24-tick batches after warm-up, separately from the 240-tick trajectories. These sequential runs use the shared i5-10500 Linux host; they are not a quiet-target acceptance run.

| Regime, swirl factor 0.4 | GDScript, µs/tick | Native, µs/tick |
| --- | ---: | ---: |
| Forward | 5,869.2 | 738.6 |
| Stall | 5,593.2 | 724.4 |
| Static | 4,992.8 | 720.4 |
| Spin | 5,274.1 | 576.6 |
| Reverse fade | 5,260.0 | 716.0 |
| Reverse off | 605.0 | 423.4 |

The [final reproducer repeat](repeat-trajectory-comparison.json), overlapping the full regression, also retains all 12 exact trajectories. Active native medians are 703–980 µs/tick; the [repeated direct profile](repeat-profile.json) is recorded separately. Across both runs the active range is **0.58–0.98 ms/tick**. Shared-host variation does not change the failed budget conclusion.

**The complete native wake is much faster but does not close the 500 µs/tick budget.** The zero-swirl native rows also remain above 500 µs. Moving the wake evaluator alone therefore does not establish sufficient whole-flight headroom. The next bounded investigation should attribute the remaining complete tick, distinguishing repeated model decoding/binding work from other dynamics, before choosing another optimization. Immutable model preparation may be investigated, but stage-dependent loads, geometry and transport state must remain fresh.

Gate P still requires the owner's decision and release-platform proof before production adoption. This experiment adds no Windows or macOS runtime evidence and does not supersede the earlier GDScript recommendation for the existing production fleet. The Stik remains unconfigured. E0b7 flight calibration and the [E0b6 physical uncertainty audit](../../E0b6/README.md) remain open; numerical equivalence is not flight validation.

## Proof

- [Direct verification](verification.json): 297 complete-load comparisons, including 256 seeded cases across 16 schema-validated geometry variants. Transport probes use zero swirl, as required by the current schema. Both horizontal tail laws, held/default CL, variable density/rpm, reverse fade and stopped residual wash are covered. Of the 297, 296 are byte-exact; one component differs by `4.44e-16`, within the unchanged absolute plus relative `1e-10` criterion. Malformed-input probes start from an accepted finite call before mutating one input.
- [Trajectory comparison](trajectory-comparison.json): all 12 × 240 body/auxiliary boundaries match exactly; continuous arrays are empty in this swirl benchmark. Native routing records 17,028 actual kernel calls, zero fallback calls and zero refusals. The separate transport tests and frame run exercise continuous axial wash.
- [Dense accuracy](accuracy.log): all 41 independent midpoint, refinement, sign and continuity checks pass with loads routed through native. The quadrature criterion remains 0.1% of force/moment norm or `1e-4 N / N m`; no coefficient tuning or tolerance relaxation.
- [Fault injections](mutations.json): zeroed loads, reversed roll moment, discarded stopped residual and discarded transported increments all fail assertions in disposable adapters. The native binary itself is unchanged in these four probes. [Comparator self-tests](comparator-tests.log) additionally reject non-finite values, missing/truncated samples, empty body arrays, duplicate case rosters and fallback-only execution.
- [Fleet fingerprints](fleet.json): all 16 production aircraft/regime fingerprints match the scalar-pass reference over 960 ticks. Production models stay on the legacy GDScript route; no goldens were regenerated.
- [Full regression](suite-summary.log): `app/test.sh` exits 0, with 116 sections and 90 GDScript test programs. Production, axial transport and swirl repeat at 30/60/144 fps; the swirl hash also matches the scalar-pass reference. [Resource validation and scene smoke tests](integration.json) pass with zero errors, no new-file diagnostics and all three scenes passing; 184 existing validator warnings remain. The [manifest](evidence.json) identifies the native binary, research sources, fixture inputs and physics/simulation files by SHA-256; a Git revision alone would omit uncommitted work.

## Reproduce

From the repository root, with a C++ toolchain matching the lock:

```sh
python3 research/propwash/e0b6p/native/build.py --jobs 2
python3 research/propwash/e0b6p/native/test_runner.py
python3 research/propwash/e0b6p/native/run.py --project app --godot "$(app/get-godot.sh)" --library .tools/native-smooth-wake/libopenrc_slipstream.so --output /tmp/e0b6p-native --keep-work
python3 research/propwash/e0b6p/native/check_mutations.py --project app --godot "$(app/get-godot.sh)" --library .tools/native-smooth-wake/libopenrc_slipstream.so --output /tmp/e0b6p-native-mutations.json
```

The runner copies the app, changes only that copy's Dynamics preload, records both routes, rejects engine errors even if Godot exits zero, and compares every sampled component. For the full suite, install the same probe and Dynamics preload in a complete isolated repository, which supplies the sibling research/tools/assets needed by `app/test.sh`. For dense accuracy, change only `test_swirl_accuracy.gd`'s Slipstream preload to the adapter in that copy. All original helper forwards still use GDScript; the six returned load components come from the native evaluator.

Commit message: `E0b6p: verify complete native smooth wake with 297 load cases, exact trajectories and full regression; retain budget gate`
