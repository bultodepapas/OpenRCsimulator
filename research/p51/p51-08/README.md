# P51-08: flown envelope of the P-51D 1/4 — bands and sources

2026-10-06. Tests: `app/tests/test_p51_envelope.gd` (airborne, 15 checks, ~32 s), `app/tests/test_p51_ground.gd` (runway, 11 checks, ~20 s), shared pilots in `app/tests/p51_envelope_base.gd`. Report: [docs/research/p51-flight-realism.md](../../../docs/research/p51-flight-realism.md).

Each check flies the real session loop (aero, shaft-balance engine, slipstream, P-factor, gear on the field's grass strip, crash checks) with a simple closed-loop pilot. The bands state what a realistic P-51 1/4 with a DA-120 and a 4-blade 26x12 must do; they are wide where the evidence is weak. Letters refer to the sources table of the report.

| Check | Band | Basis | Result 2026-10-06 |
| --- | --- | --- | --- |
| Flight modes at 1.3 Vs, 25, 40 m/s | short period ζ > 0.3, dutch roll ζ > 0.05, roll τ < 0.3 s, phugoid ζ > −0.05, spiral doubling > 4 s | MIL-F-8785C (Level 3 floor for the spiral); the full-size airplane is a stable fighter (A) | ζ_sp 0.75-0.86, ζ_dr 0.19-0.22, spiral 8.0 / 10.9 / 28.5 s |
| Three-point attitude | 12-15° | gear geometry measured on the three-view | 14.3° |
| Static full-throttle rpm | 4700-5600 | 4-blade 26x12 on a DA-120: 5000-5400 rpm estimate (I, J) | 4952 |
| Idle on the grass strip | < 1.5 m/s after 10 s | 19 N idle thrust vs 16 N rolling resistance: a slow creep, no brakes simulated | 1.07 m/s |
| Takeoff run, no rudder | heading change < −3° in 3 s (left) | torque, swirl, P-factor, gyro on tail-up (manuals: right rudder needed) | −29.9° |
| Takeoff with a rudder pilot | airborne < 10 s; roll 15-60 m; lift-off 1.05-1.5 Vs; right rudder > 20 %; heading < 10°, on the 12 m strip | RC estimate 20-50 m; Top Flite review ~60 ft (smaller model) | 4.1 s, 39 m, 22.8 m/s, 47 %, 7.3°, 3.1 m |
| Maximum level speed | 38-56 m/s, rpm above static | propeller zero thrust at J 0.76-0.81 (I); Top Flite Giant owner ~115 mph (S) | 51.4 m/s at 7082 rpm |
| Climb at 1.4 Vs, full throttle | 5-16 m/s | thrust/weight 1.1 static | 14.0 m/s |
| Idle glide at 1.4 Vs | L/D 4 to min(8.5, clean airframe) | windmilling propeller drag (research synthesis: ~1 kgf, ~2.7° steeper) | 7.1 (clean 8.7), prop 2570 rpm |
| Power-off 1-g stall | 0.85-1.1 Vs; recovery < 80 m | CL_max from F; recovery: stick forward, opposite rudder, α-limited pull-out | 14.6 m/s (Vs 15.7), 72 m |
| Power-on (30 %) stall | slower than power-off; LEFT wing drops > 15°; recovery < 80 m | A (wing drop, snap), RC reports (left wing on early lift-off) | 13.1 m/s, left, 36 m |
| Roll rate, full high-rate aileron, coordinated | grows with speed; 60-250 °/s | throws from L | 99 / 117 / 152 °/s at 20 / 25 / 35 m/s |
| 60° level turn from 30 m/s, full throttle | speed > 1.45 Vs, altitude within 8 m | 2 g sustained with T/W 1.1 | 48.5 m/s, −5.3 m |
| Approach (elevator on speed, throttle on path), exponential flare, wheel landing | touchdown in the first half of the runway, sink < 1.2 m/s | manuals: wheel landings; keep a little power on the approach | 15 m in, 1.04 m/s, one bounce |
| Rollout without brakes | stops within 200 m, heading < 15°, no crash | grass C_rr 0.075 + drag ≈ 0.13 g | 156 m, 3.8° |

What the pilots taught (while tuning them): a 16° attitude at 17 m/s after touchdown stalls the wing on the runway and drops a tip; a hard pull-out after a stall re-stalls the wing (secondary stall); the up trim (+0.41) must be overcome to unload the wing. These are the real model's traps.

Not proven: the bands come from estimates and reports, not from logged flights of a real 1/4-scale P-51. Pilots are scripted, so the tests check the airplane's physics under fixed technique, not its feel (Gate 2).
