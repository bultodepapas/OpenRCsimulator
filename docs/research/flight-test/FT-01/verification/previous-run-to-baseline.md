# Flight-test comparison

Baseline `previous run (card v2 before the phugoid check, Extra data before 208f0b89)`, candidate `baseline 208f0b89`; tolerance max(0.01, 0.01 × |baseline|).

Card ft-card-v2 → ft-card-v2; commit d2c8bcebbb → 208f0b89d3.

## Great Planes Extra 300S .60 — 21 change(s)

Aircraft data changed between the runs.

| Test | Value | Baseline | Candidate | Change |
| --- | --- | --- | --- | --- |
| landing | validity | skipped | valid | |
| takeoff | validity | skipped | valid | |
| landing | landing.approach_speed_mps | – | 13.66 | added/removed |
| landing | landing.bounced | – | False | added/removed |
| landing | landing.flare_height_m | – | 0.955210391453086 | added/removed |
| landing | landing.max_heading_error_deg | – | 0.9 | added/removed |
| landing | landing.rollout_m | – | 88.3 | added/removed |
| landing | landing.rollout_time_s | – | 11.4 | added/removed |
| landing | landing.touchdown_past_threshold_m | – | 13.1 | added/removed |
| landing | landing.touchdown_pitch_deg | – | 7.2 | added/removed |
| landing | landing.touchdown_sink_mps | – | 0.53 | added/removed |
| landing | landing.touchdown_speed_mps | – | 12.92 | added/removed |
| landing | landing.touchdown_speed_vs | – | 1.23 | added/removed |
| takeoff | takeoff.ground_roll_m | – | 14.5 | added/removed |
| takeoff | takeoff.liftoff_speed_mps | – | 15.27 | added/removed |
| takeoff | takeoff.liftoff_speed_vs | – | 1.45 | added/removed |
| takeoff | takeoff.max_heading_error_deg | – | 2.0 | added/removed |
| takeoff | takeoff.max_rudder_stick | – | 0.17 | added/removed |
| takeoff | takeoff.rotation_attitude_deg | – | 8.0 | added/removed |
| takeoff | takeoff.rudder_free_heading_change_3_s_deg | – | 6.5 | added/removed |
| takeoff | takeoff.time_to_liftoff_s | – | 3.11 | added/removed |

## Jensen Das Ugly Stik 60 — 0 change(s)

## P-51D Mustang 1/4 — 0 change(s)

## Ventage Jet — 0 change(s)

## Jensen Das Ugly Stik 60 · MAX-55AX — 2 change(s)

| Test | Value | Baseline | Candidate | Change |
| --- | --- | --- | --- | --- |
| modes | modes[0.8Vmax].phugoid_period_s | 0.21 | None |  |
| modes | modes[0.8Vmax].phugoid_zeta | 0.965 | None |  |

## Jensen Das Ugly Stik 60 · MAX-61FX — 0 change(s)

## Jensen Das Ugly Stik 60 · FS-64V — 4 change(s)

| Test | Value | Baseline | Candidate | Change |
| --- | --- | --- | --- | --- |
| modes | modes[0.8Vmax].phugoid_period_s | 0.3 | None |  |
| modes | modes[0.8Vmax].phugoid_zeta | 0.963 | None |  |
| modes | modes[start].phugoid_period_s | 0.33 | None |  |
| modes | modes[start].phugoid_zeta | 0.963 | None |  |

## Turbo Lumber Evolution — 0 change(s)

**27 change(s) beyond tolerance.**
