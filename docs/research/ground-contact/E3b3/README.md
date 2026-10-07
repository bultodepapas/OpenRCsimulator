# E3b3 — Takeoff roll against a 1-D model integral

2026-10-07 · **Status: implemented and verified (numerical model). Propeller wash is OFF for the Stik; field validation (VAL-7/PT2) open.** Main-line ROADMAP M2 E3b3; starts from E3b2.

## Run

The Stik starts on the runway threshold (E3b2) at full throttle, hands off at its level-flight trims, on the mown runway (C_rr 0.04 × 2.5). Every anchor releases immediately. It lifts off (all wheels clear) at **t 2.28 s, x 22.3 m, V 20.6 m/s** (about 1.3 × the 15.7 m/s stall speed) at 2.8° pitch, drifting 0.42 m sideways from propeller torque. After lift-off the hands-off airplane climbs steeply on its level-flight trim, which is pilot territory and outside E3b3.

## Independent reference

`_roll_1d` in [`test_takeoff_roll.gd`](../../../../app/tests/test_takeoff_roll.gd) treats the airplane as a point mass along the runway (RK4 at 4.8 kHz). Its forces come from the same model:
- thrust and aero from `Dynamics.loads` at the rest attitude;
- normal load N = W + down-force;
- rolling resistance C_rr·runway·N;
- rpm from the throttle lag (`Propulsion.rpm_step`).

It has no pitch or roll dynamics, no gear compliance, no stiction and no steering. This verifies the 6-DOF integration and ground coupling against a simple integral of the same forces. Thrust, aero and resistance values are shared on purpose, so this is **not** validation of those values (VAL-7, PT2).

| x (m) | 6-DOF V (m/s) | pitch | 1-D, rest attitude | 1-D, 6-DOF pitch history |
| ---: | ---: | ---: | ---: | ---: |
| 1 | 4.325 | −1.61° | 4.324 (0.02 %) | 4.323 (0.06 %) |
| 2 | 6.374 | −1.42° | 6.371 (0.04 %) | 6.373 (0.02 %) |
| 5 | 10.289 | −0.77° | 10.271 (0.17 %) | 10.289 (0.00 %) |
| 10 | 14.390 | +0.16° | 14.296 (0.65 %) | 14.392 (0.01 %) |
| 15 | 17.326 | +0.83° | 17.096 (1.33 %) | 17.330 (0.02 %) |
| 20 | 19.674 | +1.62° | 19.261 (2.10 %) | 19.687 (0.07 %) |

At the fixed rest attitude the 1-D integral needs 23.76 m to reach 20.61 m/s; the 6-DOF lifts off at 22.27 m (−6.3 %).

## Bands and why

- **0.5 % for x ≤ 5 m:** the 6-DOF airplane is still within about 0.8° of its rest attitude.
- **3 % up to 20 m:** the nose unloads and the airplane rotates by 3.2° (elevator trim and airflow). More lift means less rolling resistance, so the 6-DOF roll accelerates faster.
- **Lift-off distance within 10 %** of the 1-D distance to the same speed.
- **Attitude-matched check, 0.2 %:** the same 1-D integral driven by the 6-DOF's recorded pitch reproduces V(x) to **0.07 %**. The fixed-attitude difference is therefore entirely rotation, not a ground-coupling error.

## Proof

- 7 checks, 0 failed.
- **Mutation checks** on scratch copies:
  - Ignoring the runway surface factor fails 5 checks.
  - Rolling resistance 10 % high moves V by about 0.35 %. The rest-attitude bands miss it; the attitude-matched check fails (0.375 % against 0.2 %), so the test resolves a 10 % rolling-resistance error.
- **Full suite:** `app/test.sh` with its own `XDG_DATA_HOME` exits 0 (98 sections, 433 s). [Summary](suite-summary.log).

## Limits and next

- Old hand estimates (4.69 m / 11.3 m/s) are historical and not comparable: they predate the current mass, propeller data and surfaces.
- E0b (propeller wash on the Stik's tail) will change the rotation and the lift-off; rerun this test then.
- The real ground roll and lift-off on the owner's field (cones, video) are VAL-7/PT2 evidence; the estimated C_rr and breakaway are the main uncertainties.
