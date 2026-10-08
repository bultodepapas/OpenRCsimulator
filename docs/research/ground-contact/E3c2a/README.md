# E3c2a — continuous experimental ground circuit

**Status:** complete — experimental circuit verification; physical and rendered acceptance remain open. **Date:** 2026-10-07. **Owner:** Codex circuit-verification agent.

## Scope and acceptance fixed before final trials

Current Ugly Stik, calm air, flat default runway, propwash off. An offline test pilot must fly from the existing idling runway equilibrium through takeoff, a complete circuit, the E3c1a approach/flare command law, and a stable idle stop. All gains and flight targets are estimated controller choices, not aircraft measurements. Only pilot commands change after initialization; trims stay fixed, and no state reset, teleport, force injection or friction tuning is allowed.

- Hold parked for 1 s; drift <2 mm. Liftoff occurs after this hold, with every wheel at least 0.5 m inside the strip throughout departure.
- Consecutive physics ticks and previous states must agree at every boundary. Run the real session crash detector on the initial and every committed state; refuse crashes, pauses and numerical faults.
- Verify the route from actual motion: net unwrapped heading change 5.8–6.8 rad in magnitude, enclosed horizontal area ≥15,000 m², and cross-track excursion ≥80 m. These are declared test-route requirements, not recommended RC pattern dimensions.
- Require the ordered takeoff, climb, crosswind, downwind, base, final, approach, flare and rollout phases. Crosswind-turn and downwind entry CG heights are at least 10 m. Handoff to E3c1a is 144±0.25 m before the runway center along the incoming direction, at CG height 6±0.5 m, speed 12±0.5 m/s, centerline error ≤1 m, heading and bank errors ≤3°, and vertical speed magnitude ≤1 m/s.
- Every landing wheel/recontact has maximum endpoint undeformed wheel-reference downward velocity ≤1 m/s, including rotational velocity (`v + ω × r`). This is not compression-adjusted tyre-contact velocity; the model does not expose that rate. Every wheel stays ≥0.5 m inside the runway after first landing contact.
- Stop with all wheels compressed and anchored, speed <0.02 m/s and angular speed <0.01 rad/s for 2 s; then hold another 3 s, with drift <2 mm. Throttle remains zero, the engine running at idle.
- Fly both runway headings at 240 Hz. Repeat eastbound at 480 Hz: touchdown east coordinate within 0.5 m, sink within 0.05 m/s; stopping coordinate within 0.75 m, stopping time within 1 s, peak compression within 5 mm. No fourth-order claim across contact/phase switches.
- Preserve a continuous standard v3 trace with the initial sample plus every tick, source identity and an explicit circuit scenario.

This verifies one controller-driven case. Owner handling, independent takeoff/landing measurements, propwash acceptance, rendered circuit acceptance, and PT2 remain open. The existing treeline is visual; this experiment cannot establish obstacle clearance.

## Implementation and results

The offline [pilot and verifier](../../../../research/landing/e3c2a/) use the current Stik through `FlightSession`: solve 15 m/s throttle feedforward and the 12 m/s approach trim before the runway reset, retain the approach trims throughout, hold idle, ramp throttle, and follow a mirrored circuit. Cruise targets are 15 m/s and 24 m CG height; the downwind descent and slower final turn reach the E3c1a entry without changing state. Bank steers the airborne course; rudder feedback damps sideslip and yaw-rate error. Only commands are generated. The existing E3c1a pilot controls approach, flare and idle rollout.

| Case | First touchdown east (m) | Maximum wheel-reference sink (m/s) | Minimum landing runway margin (m) | Stop east (m) | Stop time (s) |
| --- | ---: | ---: | ---: | ---: | ---: |
| 240 Hz east | −48.66538 | 0.393875 | 1.33278 | 44.63427 | 117.25417 |
| 240 Hz west | 48.66538 | 0.393875 | 1.33278 | −44.63427 | 117.25417 |
| 480 Hz east | −48.68322 | 0.393790 | 1.31494 | 44.63362 | 117.03125 |

All three flights complete the ordered circuit without crash, pause, numerical fault or discontinuity; the all-wheel departure margin is 2.90660 m. Maximum post-stop drift is 0.053 mm. Eastbound refinement changes touchdown position by 17.84 mm, stopping position by 0.654 mm, stopping time by 0.223 s, and peak compression by 0.030 mm. The 240 Hz route turns 360.328° and encloses 68,150 m², with 160.075 m maximum lateral excursion.

The [integration report](report.json) and [flight log](flight.log) contain 34 passing checks. The [saved CSV](circuit.csv.gz) has 28,862 rows: tick zero plus every tick through 120.25417 s. Its [independent reader](trace-check.json) verifies timing, metadata, exact aircraft input bytes, the flown route, and parked endpoints. It rejects a missing final row, an initial-only trace and a nonfinite sample. [Disposable source mutations](mutations.json) inject a nonfinite throttle command and rewrite position between boundaries; both fail the named command/continuity assertion with exit 1 and no engine error. These do not claim exhaustive guard mutation coverage. [Static lint](lint.json) has zero errors or warnings. [CLI probes](cli-checks.json) confirm full mode refuses a missing trace and development mode refuses a nonfinite duration (exit 2, no engine error).

The final full circuit, saved-trace checks and source mutations pass in the shared checkout after independent review added the longitudinal final-entry bound. [Source identity](source-identity.json) records the baseline commit and post-run source hashes; concurrent runtime work belongs to its owning tracks.

The [isolated baseline suite](app-test.log) passes (109 GDScript test programs, 137 sections), including golden flights, model contracts, four-aircraft app traces and 30/60/144 fps comparisons. The first attempt timed out at the existing landing test under its 60-second process limit. The retry changed only that limit to 300 seconds in the disposable checkout; all assertions remain intact. [Run summary](app-test-summary.json). The shared `app/test.sh` was not changed. Circuit acceptance was separately rerun against the shared checkout.

During final review, the CR-01b track integrated its previous-state impact snapshot hook. A [focused repeat](concurrent-session-check.json) against those new session/snapshot bytes passes 11 checks, with an exactly identical final state and landing metrics; [report](concurrent-session-report.json), [log](concurrent-session.log). The full three-case evidence remains identified by its earlier source hashes.

## Findings and limits

Early 12 m/s turn trials lost speed under aggressive heading-driven rudder. The final controller uses bank for heading, a higher cruise target, and a longer descent/deceleration segment before handing over to E3c1a. This tuning is model-specific and does not establish a real aircraft's turn radius, recommended circuit geometry or stall margin.

A strict five-second stop assertion initially failed at 480 Hz because repeated float addition gave 4.99999999999988 s. The final driver counts committed ticks for both the two-second stop dwell and three-second hold; no tolerance was widened. Contact and command-phase switches remain nonsmooth, so the refinement result is a bounded comparison, not an RK4 order claim.

## Reproduce

From the repository root, choose a new output directory:

```sh
python3 research/landing/e3c2a/verify.py --out /tmp/e3c2a-proof --mutations
python3 research/landing/e3c2a/check_trace.py docs/research/ground-contact/E3c2a/circuit.csv.gz docs/research/ground-contact/E3c2a/report.json --self-test
```

The wrapper parses the offline scripts, isolates user settings, rejects engine errors and checks process exits. Direct `run.gd --quick` / `--west` runs are explicitly marked development coverage; full acceptance requires east/west 240 Hz, east 480 Hz and a saved trace. This tooling is not wired into the normal app route or every CI run.
