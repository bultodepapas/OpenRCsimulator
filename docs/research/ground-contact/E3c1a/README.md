# E3c1a — approach, flare and idle rollout

**Status:** COMPLETE — implementation and verification. **Date:** 2026-10-07. **Owner:** Codex landing-verification agent. Experimental wash-off Stik baseline; E3c1 propwash acceptance, E3c2 circuit and PT2 remain open.

## What changed

A dedicated [test pilot](../../../../app/sim/landing_maneuver.gd) commands the real flight session through its trims, engine, servos, aerodynamics, integrator and gear. It is not offered in menus or enabled during manual flight. The [measurement driver](../../../../app/tests/landing_test_driver.gd) runs the session crash detector at every committed boundary, including the initial/final state. It does not clamp motion, inject forces, cut the engine or change aircraft/surface data.

The maneuver starts at 12 m/s, CG height 6 m, 94 m before the physical end of the default 100 × 12 m strip. It holds heading/cross-track with roll and rudder, controls descent with elevator and approach speed with throttle, then closes throttle below 2 m wheel clearance. The decreasing sink target is `min(0.8, 0.15 + 0.35 × clearance)` m/s. First wheel contact latches rollout; pilot input cancels the airborne elevator trim and retains pitch-rate damping. The engine continues idling throughout rollout and the final hold.

All targets/gains are **estimated test-pilot choices adjusted from trajectories**, not identified airplane properties or recommended real-flight technique. Scope is the current Stik, calm air, flat east/west runway and wash disabled. The pilot's sampled phase belongs to the test driver, outside the integrator/checkpoint contract; a fresh pilot is required for each run.

## Acceptance and results

Criteria fixed before the 240/480 Hz comparison: every wheel and recontact ≤1 m/s downward endpoint speed; all wheel positions stay at least 0.5 m inside the runway after first contact; no hull/gear crash or numerical fault. A stop requires all wheels compressed and anchored, speed <0.02 m/s and angular speed <0.01 rad/s continuously for 2 s. The aircraft must remain stopped afterward, with <2 mm drift, zero throttle and idle RPM. The run continues to 46 s.

| Case | Touchdown position, east (m) | Max contact sink (m/s) | Stop position, east (m) | Stop declared (s) | Minimum wheel/runway margin (m) |
| --- | ---: | ---: | ---: | ---: | ---: |
| East, 240 Hz | −47.5334 | 0.393406 | 45.8088 | 42.3583 | 2.4652 |
| West, 240 Hz | 47.5334 | 0.393406 | −45.8088 | 42.3583 | 2.4652 |
| East, 480 Hz | −47.5081 | 0.393205 | 45.8397 | 42.3458 | 2.4905 |
| West, 480 Hz | 47.5081 | 0.393205 | −45.8397 | 42.3458 | 2.4905 |

Touchdown speed is 10.447–10.448 m/s at 240 Hz; maximum compression is 29.65 mm. No post-touch fully airborne interval occurs. Final stopped dwell exceeds 5.6 s; drift after declaring stop is below 0.03 mm.

Declared refinement budgets: touchdown location ≤0.25 m, contact sink ≤0.05 m/s; stop location ≤0.5 m, stop time ≤0.5 s, peak compression ≤5 mm. Observed differences are **0.02533 m, 0.000202 m/s, 0.03091 m, 0.0125 s and 0.0266 mm**, respectively. These are whole-maneuver event checks, not a claim of fourth-order convergence through contact switching or real-aircraft accuracy.

Two held-out entries (±1 m lateral offset, ±2° initial bank, opposite headings) pass the same landing/stop conditions: sink ≤0.393484 m/s, runway margin ≥2.4392 m, stopped drift <0.053 mm. [Nominal/refinement data](landing-results.json) · [Variations](variations.json). Each file includes every contact event, final state and a decimated trajectory approximately every 0.1 s; all safety/containment checks run at the full physics rate. These files are diagnostic evidence, not replay-complete CSV traces or new goldens.

## Checks that reject plausible false passes

- [28 nominal/refinement checks](landing-tests.txt) and [9 variation checks](variations.txt). A hand-computed rotated contact point verifies position and the `v + ω × r` impact velocity independently of the flight.
- A low initial hull/gear penetration must produce an actual session crash **before tick 1**. Stepping only `sim.step()` would miss it.
- Starting the same approach 15 m later still touches down softly and stops, but crosses the runway end: worst wheel margin **−0.935 m**. The checker rejects it. Rough ground outside the strip must not supply the stopping proof.
- [Four isolated source mutations](mutations.json) fail assertions with a passing unmodified control and no engine errors: remove the flare, omit rotational contact velocity, bypass session crash detection, or move the approach 15 m later. Mutation files live only in disposable copies.
- Read-only Luna Max review caught a wash-status assertion at the wrong dictionary level; the baseline now requires an empty `model.propulsion.slipstream` block. This deliberately rejects any future nonempty wash configuration until reviewed. The review also prompted explicit wheel IDs, idle RPM/throttle and post-stop stability checks.
- Static Godot lint: zero errors, with the same 12 pre-existing warnings before/after and no warnings in the four new scripts. The [full isolated app suite](app-checks.txt) passes 104 GDScript test programs plus model contracts, goldens, trace acceptance, real-app trimmed flight and frame-rate checks. All 37 focused checks also pass [after integration into the shared tree](integration-checks.txt). Exact baseline and source hashes are in [verification](verification.json).

Touchdown means a wheel point crosses from nonpositive to positive compression between ticks. Reported sink is the **larger of its two endpoint downward velocities**, including CG motion and rotation, across all first contacts and recontacts. It is not an interior maximum bound or an independently measured impact speed. The timestep comparison bounds its sampling sensitivity for these cases.

## Development finding

[Earlier 13 m/s and later-flare 12 m/s trials](development-trials.txt) touched down safely but rolled off the strip; rough ground stopped them. Moving the test start alone can also hide off-runway touchdown. The retained controller instead flares earlier, approaches at the bounded 12 m/s condition, and releases airborne elevator trim after contact. Airframe forces and friction were never tuned to make it pass. The final whole-rollout wheel checks reject both early touchdown and late stopping.

## Reproduce

From the repository root:

```bash
GODOT=$(app/get-godot.sh)
"$GODOT" --headless --path app --script res://tests/test_landing_maneuver.gd -- --report=/tmp/landing.json
"$GODOT" --headless --path app --script res://tests/test_landing_variations.gd -- --report=/tmp/landing-variations.json
python3 research/landing/e3c1a/check_mutations.py --godot "$GODOT"
app/test.sh
```

The normal app suite discovers both `test_landing_*.gd` programs. `--quick` on `test_landing_maneuver.gd` runs one 240 Hz eastbound flight plus geometry/crash checks, exclusively to keep mutation trials small; default execution always covers all four nominal/refined flights.

No measured aircraft landing data or owner handling evidence was available. Recheck this maneuver after deliberate physics changes, propwash enablement or revised field/aircraft measurements. It establishes a bounded landing case, not a complete circuit, a general autoland system or flight fidelity.

Suggested commit message:

```text
E3c1a: verify Stik approach, flare and idle rollout through the real session

Proof: 37 focused checks, both headings at 240/480 Hz, offset/bank entries,
a rejected runway-overrun control, four isolated mutations and app/test.sh.
Current wash-off model only; propwash calibration and PT2 stay open.
```
