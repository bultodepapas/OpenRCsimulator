# Stage-validation reuse: an experimental optimization

## Verdict

The candidate removes repeated validation of data that has already been checked in the same, uninterrupted Runge–Kutta stage. It preserves every numerical operation, timestep, model, clamp, and existing fault check needed after a callback. Direct edge-case comparisons, sampled stock loads and derivatives, and three complete recorded flight replays matched exactly on this engine and platform. The component reduction is measurable, but the limited headless session measurements are noisy and do **not** establish an application-level speedup. This is an experimental patch for review and further target-hardware testing, not a recommendation to claim an FPS gain or merge on component numbers alone.

## Source and candidate

- Repository baseline commit: `3df2791752fe2c1faad132fcb11febbb0ae788d1`; baseline `app/sim/simulation.gd` SHA-256 `56953f116a293a984cbc5315b9cd97dc156e63cdd98c12fbc041e6df6baaab92`.
- Candidate modifies only that source file; candidate SHA-256 `d6fca823652f3f78957517a6efb20898c8acb0b86e3f125d5a8748ff3ecf6255`. Apply `candidate.patch` from a checkout root; its paths are `a/app/sim/simulation.gd` and `b/app/sim/simulation.gd`.
- Engine: official Godot `4.8.beta2.official.cafc17a19`, executable SHA-256 `34d0599a1f17acc76583610969878065d1b1701615af77271e32201351b9c564`; 240 Hz. Tests used separate source copies with the same minimal audit project configuration, reference GDScript backend, Linux x86-64 on an Intel Xeon Platinum 8573C. No repository source was edited.

## Mechanism and safety boundary

With a nonempty continuous state, `_stage_state_is_valid` first scans the entire packed body-plus-continuous array for finiteness, then allocates a body slice and scans those same 13 body values again in `state_is_valid`. The candidate checks the quaternion norm directly on the already-scanned packed array. It factors the unchanged norm expression into a common helper, preserving the original evaluation order and threshold. Body-only validation gains one helper call; its performance was not separately measured.

A successful `_joint_stage_is_valid` already checks the required loads, continuous derivative, rotor momentum, and optional body derivative. Immediately following that validation, with no intervening callback, the current implementation checks some of those same arrays again. The candidate carries a local `verified_joint` fact across that short interval and skips only the repeated checks. It keeps checks on calculated body derivatives and all split/body-only results. Most importantly, it keeps the original first-stage derivative checks after `model.rotor_momentum`, because that callback can intervene. The fact is local to the call; there is no persistent cache. The optimization assumes the existing read-only evaluator contract, and future maintainers must preserve the no-callback/no-mutation interval or revalidate the response.

## Verification

All accepted invocations use the checked Godot runner and require completion markers. The following are finite software tests, not proofs for all possible states or physical validation:

- `derivative_equivalence.gd` passed **44,025 checks**. It compared 40,000 seeded packed states with continuous sizes 0, 1, 4, and 25, plus 39 explicit nonfinite body entries. Cases included signed zero, NaN, ±infinity, short/long arrays, zero quaternion, values at and just above the quaternion threshold, and quaternion norm overflow. It also exercised invalid/missing/extra joint fields, invalid sizes, and nonfinite loads, rates, momentum and body derivatives at each of the four stage calls. First-stage rotor callbacks deliberately changed a previously returned derivative or body derivative; both implementations rejected the tick with matching state and fault output.
- The same test compared all four returned derivative arrays at the kernel step-policy boundary for 960 synthetic ticks across joint stages with and without supplied body derivatives, split stages, and body-only stages: **3,840 exact array comparisons**, along with the generated stage inputs, joint outputs, committed states, loads and fault results.
- `stock_stage_trace.gd` sampled 120 actual joint-stage evaluations per aircraft, with distinct per-field SHA-256 fingerprints over the byte-encoded arrays. Baseline and candidate matched for loads, continuous derivatives, body derivatives and rotor momentum for the default Stik (continuous width 3), finite-glow Stik (22), and Avanti (6). The latter two supplied body derivatives for all 120 samples.
- For each of the same three aircraft, a 720-tick baseline `.orfl` recording was complete. Exact baseline replay reported `solver_changed=false`; the candidate correctly reported `solver_changed=true`. Every replay compared **721/721 rows without divergence**, including the flight-log reader's exact byte comparisons of state, loads, inputs, aux, continuous state, modes, air, and mass when present. This does not assert equality for all checkpoints, events, conditions, platforms or engines.
- Nine existing tests passed: `test_simulation`, `test_sf_vehicle_model`, `test_sf_contact_substeps`, `test_sf_event_protocol`, `test_sf_event_refinement`, `test_continuous_state`, `test_sf_ground_vehicle_kernel`, `test_heli_startup_kernel`, and `test_sf_generalized_coordinates`. Full CI, rendered runs and physical validation were not performed.

## Measurements

The audit ran alone relative to the cooperating agents and pinned the timing processes to logical CPU 0. It used an editor/debug engine in a shared Linux environment; OS and host activity were uncontrolled. Raw samples, including outliers, are retained. The percentages below are the median of the **paired** `(baseline − candidate) / baseline` percentages; positive numbers mean lower candidate time. They are not ratios of the independently reported medians. No samples were discarded.

| Headless component workload | Baseline median | Candidate median | Median paired reduction | Pair range |
| --- | ---: | ---: | ---: | ---: |
| Packed-state guard, 1 continuous value | 1.986 µs/call | 1.491 µs/call | 27.13% | −44.48% to +35.96% |
| Packed-state guard, 4 continuous values | 2.104 µs/call | 1.704 µs/call | 22.04% | −24.21% to +29.35% |
| Packed-state guard, 25 continuous values | 3.319 µs/call | 2.734 µs/call | 17.59% | −26.75% to +37.61% |
| Synthetic joint-stage kernel | 78.085 µs/tick | 69.973 µs/tick | 11.30% | −4.86% to +22.78% |

Each component workload used 16 alternating AB/BA pairs. Each guard batch contained 6,000 calls; each kernel batch contained 300 ticks and a simple constant synthetic joint evaluator with a supplied body derivative. Its timing is not representative aircraft physics or the complete app.

For the larger workload, a clearly identified copy of the repository's `session_probe.gd` used real `FlightSession._physics_process` and `Simulation._physics_process`, the field and lake, deterministic input and GDScript reference backend. It omitted the scenery collision world, presentation/audio, OS input and rendering. It compared eight alternating process pairs per aircraft, each with 120 warmup and 480 sampled ticks. Every pair had matching typed per-tick fingerprints over the probe's declared state fields and complete requested tick/input counts. Individual per-tick callback timings and reports are retained.

| Headless session | Median of paired changes in each run's tick median | Individual paired changes |
| --- | ---: | --- |
| Default Stik | +2.25% | +2.75, +1.75, +4.99, +4.91, +3.75, +1.21, −2.73, +0.38% |
| Avanti | +0.19% | +1.17, +1.00, +2.30, +5.61, −7.06, −0.63, −8.59, −0.85% |

The variation is too large to infer a reliable benefit in these sessions, particularly Avanti. Session measurement excludes scenery collision and rendered/product observers; native evaluator, full application, 1080p, GPU and owner-hardware performance remain unmeasured. Body-only performance and complete model-extension behavior are likewise not established by these results.

## Failed/aborted attempts, retained separately

- `checks/bench-component-jro7r01f/`: the initial synthetic benchmark reused a mutable body-derivative array. It failed its reset check and has no accepted timing output. The final fixture creates fresh output arrays, and `checks/bench-component-final-g3dtpqn6/` is the successful run.
- `session_timing/checked/stik-00-base-ya541k4n/`: the **unmodified** full-scenery probe emitted missing texture/GLTF parse errors because the sparse checkout intentionally omitted those assets. Godot exited zero, but the checked runner rejected the run. It is not measurement evidence. `session_timing_no_scenery/` is the separate, accepted comparison with the omitted scenery clearly disclosed.
