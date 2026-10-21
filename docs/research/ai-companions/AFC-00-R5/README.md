# AFC-00-R5: observation airdata candidate

**Date:** 2026-10-21  
**Status:** runtime observation helper integrated; bitwise parity and focused regressions pass. Timing evidence is limited to one method-level microbenchmark.

This work tests whether companion observations can preserve `airspeed_m_s` while avoiding construction of the full `Air.compute()` result and a second same-time wind query. The original arithmetic and paired-flight sections below are historical research-stage evidence: at that stage the candidate was external and no application source was changed. The runtime integration and its separate evidence are recorded below; the original [`verification.json`](verification.json) remains the pre-integration receipt.

## Consumer audit and candidate

The production path is [`Manager._before_step()`](../../../../app/ai/companions/manager.gd#L132) → [`Agent.observation()`](../../../../app/ai/companions/agent.gd#L125) → `Manager._after_step()` → `Agent.prepare()` → the production pilot. [`CircuitController.command()`](../../../../app/ai/companions/circuit_controller.gd#L149) is the only production consumer of the snapshot's `airspeed_m_s`; it reads that value when finite and falls back to the state-and-wind norm when it is absent or invalid. The pilot also needs the snapshot state and wind. The candidate therefore keeps the key and its scalar value contract.

Companion pilot, clearance, and encounter tests ([pilot](../../../../app/tests/test_companions_pilot.gd), [clearance](../../../../app/tests/test_companions_clearance.gd), [encounters](../../../../app/tests/test_companions_encounters.gd)) construct their own snapshots and exercise the controller contract. Research pilot and encounter probes also construct their own snapshots directly. They do not consume `Agent.observation()` output. The paired probe below exercises the actual manager, agent preparation path, and production pilot together.

The proposed `Agent.observation()` substitution is:

```gdscript
var state: PackedFloat64Array = session.sim.state.duplicate()
var wind: PackedFloat64Array = session.wind_at(session.sim.time())
var airspeed: float = ObservationAirdataCandidate.airspeed_m_s(state, wind)
return {id = "companion-%d" % slot_id, slot = slot_id, state = state, airspeed_m_s = airspeed,
    wind_ned = wind, ...}
```

The helper copies `Air.compute()`'s scalar conjugate-quaternion rotation and preserves the same parenthesization through the `u`, `v`, and `w` subtractions. It calls the existing `Math3D.sqrt_()` wrapper. It does not replace that arithmetic with `q_rotate()` or a different vector norm. This avoids computing the unconsumed `v_air`, `alpha`, `beta`, and `qbar` outputs, the density query needed only for `qbar`, and the second wind sample. The helper duplicates physics arithmetic, so a future runtime promotion must keep an explicit bit-parity regression against `Air.compute()`.

## Evidence

The arithmetic probe compared the candidate scalar to `Air.compute(state, wind, 1.225).V` over 521 cases: 512 varied state/wind combinations, three zero or co-moving edges, and six signed-zero input cases built from explicit IEEE-754 bytes. All 521 results matched bitwise. The packed-float test distinguished positive and negative zero.

The flight probe ran paired baseline and candidate branches for one and three companions. Each branch advanced 1,200 ticks (five simulated seconds at 240 Hz) with `WindConfig.GENTLE_PRACTICE`, including its seeded turbulence and gust beginning at three seconds. The only branch difference was how the observation dictionary was formed. Both branches used the same production manager, agent preparation, pilot, aircraft, field, collision inventory, and lake fixture.

Every pair matched its player tick/input fingerprints, each companion's tick-state/input/applied-command fingerprints, complete observation fingerprints, full pilot-return fingerprints, and sampled wind fingerprints. Candidate airspeed matched both `Air.compute()` and `FlightSession.air_data()` bitwise for 300 observations in the one-companion run and 900 in the three-companion run. The repeated same-time wind queries matched at all 300 and 900 observations. The runs recorded 120 and 360 observations at or after the configured gust delay.

The flight probe's original `complete` flag did not itself require exact roster and per-slot row counts. A separate reducer therefore checked those counts from the retained raw fingerprints: all four branches had the requested roster size, 1,200 player ticks, 1,200 agent ticks per slot, and exactly 300 observations, pilot returns, and wind samples per slot. Those count gates are recorded in [verification.json](verification.json). Source hashes before and after each paired run were unchanged.

The probe collected no timings. This evidence establishes bounded software behavior parity for the stated short fixture; it does not establish a speedup, broad companion qualification, rendered-frame performance, or physical validity.

## Runtime integration and validation

`Agent.observation()` now duplicates the state once, samples wind once, computes `airspeed_m_s` with the tested scalar helper (its source hash is recorded in the runtime receipt), and reuses that wind array for `wind_ned`. It preserves every observation field. The helper keeps the authoritative `Air.compute()` operation grouping and calls the same `Math3D.sqrt_()` wrapper; it does not substitute `q_rotate()`.

The focused production test compares actual `Agent.observation()` dictionaries against the former `session.air_data()` construction on admitted sessions. It checks 521 bitwise airspeed cases, including signed-zero inputs, then verifies complete 1,200-tick sessions for one and three companions. Those runs produced exactly 300 observation batches, 300 byte-equal observations per agent, zero mismatches, and 120 post-gust samples per agent. The manager itself exercised the connected before/after-step callbacks. The manager regression passed 53 checks, recording passed 156 including a complete 260-tick parity capture, and profile validation passed 37. All four checked-runner invocations completed with exit 0 and zero Godot error/warning diagnostics.

The supporting ABBA measurement is retained separately in [the timing receipt](checks/observation-abba-20261021/receipt.json). It measured 240 paired rounds, 480 blocks per arm, and 1,024 calls per block on one frozen post-gust state. Mean block averages were 23.735 µs/call for production and 16.796 µs/call for the candidate; the median paired candidate/baseline ratio was 0.703. The reported p50/p95/p99 describe block means, not individual calls. This is a single-host, single-state observation-method microbenchmark; it does not establish a full-callback, manager, rendered-frame, flight, or fleet speedup. The runtime source copies, run reports, logs, hashes, and exact parity counts are indexed in the [runtime verification receipt](checks/observation-runtime-20261021/verification.json).

The source snapshots used for runtime validation are retained under [`sources/runtime-20261021/`](sources/runtime-20261021/). The focused test also gives all setup/admission failures a complete result schema so a broken fixture reports failed gates rather than aborting while formatting results.

A separate [current Main integration run](checks/main-shell-20261021/verification.json) exercises the observation change together with the crash presentation context through Home, live flight, Pause, restart, removal and fleet capture. All 49 shell checks pass with zero engine errors and three existing vegetation-wind material warnings. The run uses headless rendering and Dummy audio; it does not qualify native visuals, playback or frame cost.

## Artifacts

- [Verification and source/asset hash index](verification.json)
- [521-case arithmetic report](checks/airdata-arithmetic-v2.json)
- [Eight-tick runtime smoke](checks/flight-runtime-smoke-8.json)
- [Full 1,200-tick paired fingerprints](checks/flight-parity-1200-raw.json)
- [ABBA observation microbenchmark receipt and raw samples](checks/observation-abba-20261021/README.md)
- [Runtime parity and regression reports](checks/observation-runtime-20261021/verification.json)
- [Research candidate helper](sources/observation_airdata_candidate.gd)
- [Arithmetic probe source](sources/observation_airdata_probe.gd)
- [Paired flight probe source](sources/observation_flight_probe.gd)
