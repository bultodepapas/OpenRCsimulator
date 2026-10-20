# Flight-test comparison

Baseline `tmp/ft-05-pre`, candidate `tmp/ft-05-baseline-final`; tolerance max(0.0, 0.0 × |baseline|).

Card ft-card-v5 → ft-card-v5; commit 078010c76f → 890b94fcd7 (candidate dirty).

## Great Planes Extra 300S .60 — 692 change(s)

Changed values per test: power_step 97, trim_sweep 62, stall_turn 51, stall_turning 50, snap_roll 34, glide_turn 29, engine_cut_climb 26, stall_cross_controlled 25, glide 24, stall_held 23, knife_edge 21, knife_edge_full_rudder 21, climb 17, roll_rate 16, dead_stick_landing 15, go_around 14, spin_inverted 13, inverted_speeds 12, spin 12, stall_power_off 11, modes 11, hands_off 10, landing 10, split_s 10, stall_inverted 8, outside_loop 8, stall_power_on 8, takeoff 7, inverted_turn 6, rudder_step 6, throttle_response 6, vmax 6, immelmann 5, inverted 4, point_roll 4, loop 3, pitch_pull 3, slow_roll 3, turn_60 1.

## Jensen Das Ugly Stik 60 — 0 change(s)

## P-51D Mustang 1/4 — 0 change(s)

## Ventage Jet — 0 change(s)

## Jensen Das Ugly Stik 60 · MAX-55AX — 712 change(s)

Changed values per test: trim_sweep 145, power_step 101, stall_turn 48, stall_turning 37, glide_turn 28, snap_roll 27, engine_cut_climb 24, glide 24, knife_edge_full_rudder 21, stall_held 19, climb 19, stall_cross_controlled 18, knife_edge 16, roll_rate 15, dead_stick_landing 14, spin 13, spin_inverted 13, go_around 12, stall_power_off 11, hands_off 10, modes 10, split_s 10, inverted_speeds 9, landing 9, outside_loop 8, stall_power_on 8, vmax 7, stall_inverted 6, takeoff 6, throttle_response 6, rudder_step 4, inverted 3, loop 3, immelmann 2, inverted_turn 2, pitch_pull 2, point_roll 1, turn_60 1.

## Jensen Das Ugly Stik 60 · MAX-61FX — 679 change(s)

Changed values per test: power_step 99, trim_sweep 67, stall_turning 53, stall_turn 50, snap_roll 33, glide_turn 28, engine_cut_climb 27, stall_cross_controlled 25, glide 24, stall_held 23, knife_edge_full_rudder 20, roll_rate 17, go_around 15, dead_stick_landing 14, knife_edge 14, spin 14, spin_inverted 13, climb 12, stall_power_off 11, stall_power_on 11, inverted_speeds 11, hands_off 10, landing 10, modes 10, split_s 10, outside_loop 8, takeoff 7, stall_inverted 6, inverted_turn 5, throttle_response 5, vmax 5, immelmann 4, inverted 4, rudder_step 4, turn_60 3, loop 2, pitch_pull 2, point_roll 2, slow_roll 1.

## Jensen Das Ugly Stik 60 · FS-64V — 657 change(s)

Changed values per test: power_step 98, stall_turning 53, trim_sweep 53, snap_roll 32, glide_turn 30, engine_cut_climb 26, stall_cross_controlled 25, glide 24, stall_held 23, knife_edge 20, climb 19, knife_edge_full_rudder 18, go_around 16, inverted_speeds 16, point_roll 16, roll_rate 16, dead_stick_landing 15, spin 14, spin_inverted 13, stall_power_off 11, inverted_turn 11, landing 10, modes 10, split_s 10, hands_off 9, stall_inverted 8, outside_loop 8, stall_power_on 8, immelmann 6, inverted 6, takeoff 6, rudder_step 5, slow_roll 5, stall_turn 4, throttle_response 4, vmax 4, loop 3, pitch_pull 2.

## Turbo Lumber Evolution — 0 change(s)

**2740 change(s) beyond tolerance.**

Condensed to headers and per-test counts; the full value-by-value report (232 KB) regenerates with `python3 research/flight-test/compare.py <pre-copy run> <FT-05 run> --rel 0 --abs 0`. The pre-copy run flies the same card (`run.py --app <copy>`) on a copy of `app/` with the pre-NITRO-06 glow files: `physics/glow`, `data/glow`, `sim/trace.gd` and the starter line of `sim/flight_session.gd` from `12c2ac31`.
