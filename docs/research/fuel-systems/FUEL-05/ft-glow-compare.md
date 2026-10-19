# Flight-test comparison

Baseline `ft-base`, candidate `ft-cand`; tolerance max(0.01, 0.01 × |baseline|).

Card ft-card-v4 → ft-card-v4; commit  → .

## Jensen Das Ugly Stik 60 · MAX-55AX — 655 change(s)

Aircraft data changed between the runs.

| Test | Value | Baseline | Candidate | Change |
| --- | --- | --- | --- | --- |
| trim_sweep | validity | valid | not valid | |
| aero_sweep | aero_sweep.knife_edge_side_force_margin | 0.726 | 0.689 | -0.037 (-5.1 %) |
| aero_sweep | aero_sweep.trim_alpha_deg | 1.49 | 1.67 | +0.18 (+12.1 %) |
| aero_sweep | aero_sweep[alpha_05].cm | -0.0287 | -0.0688 | -0.0401 (-139.7 %) |
| aero_sweep | aero_sweep[alpha_05].cm_local | -0.0354 | -0.0755 | -0.0401 (-113.3 %) |
| aero_sweep | aero_sweep[alpha_05].cm_oracle | -0.0287 | -0.0688 | -0.0401 (-139.7 %) |
| aero_sweep | aero_sweep[alpha_10].cm | -0.073 | -0.1436 | -0.0706 (-96.7 %) |
| aero_sweep | aero_sweep[alpha_10].cm_local | -0.0835 | -0.1542 | -0.0707 (-84.7 %) |
| aero_sweep | aero_sweep[alpha_10].cm_oracle | -0.0633 | -0.134 | -0.0707 (-111.7 %) |
| aero_sweep | aero_sweep[alpha_15].cm | -0.2707 | -0.3338 | -0.0631 (-23.3 %) |
| aero_sweep | aero_sweep[alpha_15].cm_local | -0.2707 | -0.3338 | -0.0631 (-23.3 %) |
| aero_sweep | aero_sweep[alpha_15].cm_oracle | -0.1359 | -0.2014 | -0.0655 (-48.2 %) |
| aero_sweep | aero_sweep[alpha_20].cm | -0.2572 | -0.3014 | -0.0442 (-17.2 %) |
| aero_sweep | aero_sweep[alpha_20].cm_local | -0.2572 | -0.3014 | -0.0442 (-17.2 %) |
| aero_sweep | aero_sweep[alpha_20].cm_oracle | -0.2148 | -0.2485 | -0.0337 (-15.7 %) |
| aero_sweep | aero_sweep[alpha_30].cm | -0.1991 | -0.2577 | -0.0586 (-29.4 %) |
| aero_sweep | aero_sweep[alpha_30].cm_local | -0.1991 | -0.2577 | -0.0586 (-29.4 %) |
| aero_sweep | aero_sweep[alpha_30].cm_oracle | -0.3062 | -0.3553 | -0.0491 (-16.0 %) |
| aero_sweep | aero_sweep[alpha_m05].cm | 0.0088 | 0.0319 | +0.0231 (+262.5 %) |
| aero_sweep | aero_sweep[alpha_m05].cm_local | 0.0325 | 0.0556 | +0.0231 (+71.1 %) |
| aero_sweep | aero_sweep[alpha_m05].cm_oracle | 0.0088 | 0.0319 | +0.0231 (+262.5 %) |
| aero_sweep | aero_sweep[alpha_m10].cm | 0.043 | 0.0981 | +0.0551 (+128.1 %) |
| aero_sweep | aero_sweep[alpha_m10].cm_local | 0.052 | 0.1072 | +0.0552 (+106.2 %) |
| aero_sweep | aero_sweep[alpha_m10].cm_oracle | 0.0123 | 0.0674 | +0.0551 (+448.0 %) |
| climb | climb.best.path_angle_deg | 63.5 | 57.2 | -6.3 (-9.9 %) |
| climb | climb.best.pitch_deg | 65.2 | 58.5 | -6.7 (-10.3 %) |
| climb | climb.best.rpm | 11374 | 11490 | +116 (+1.0 %) |
| climb | climb.best.speed_mps | 17.91 | 18.46 | +0.55 (+3.1 %) |
| climb | climb.best.vertical_speed_mps | 16.23 | 15.65 | -0.58 (-3.6 %) |
| climb | climb[1.3Vs].rpm | 11053 | 10824 | -229 (-2.1 %) |
| climb | climb[1.3Vs].speed_mps | 16.05 | 14.51 | -1.54 (-9.6 %) |
| climb | climb[1.3Vs].vertical_speed_mps | 15.47 | 13.95 | -1.52 (-9.8 %) |
| climb | climb[1.6Vs].path_angle_deg | 90.0 | 75.4 | -14.6 (-16.2 %) |
| climb | climb[1.6Vs].pitch_deg | 72.9 | 69.9 | -3 (-4.1 %) |
| climb | climb[1.6Vs].rpm | 11098 | 10959 | -139 (-1.3 %) |
| climb | climb[1.6Vs].speed_mps | 16.32 | 15.4 | -0.92 (-5.6 %) |
| climb | climb[1.6Vs].vertical_speed_mps | 15.6 | 14.42 | -1.18 (-7.6 %) |
| climb | climb[2.0Vs].path_angle_deg | 63.5 | 57.2 | -6.3 (-9.9 %) |
| climb | climb[2.0Vs].pitch_deg | 65.2 | 58.5 | -6.7 (-10.3 %) |
| climb | climb[2.0Vs].rpm | 11374 | 11490 | +116 (+1.0 %) |
| climb | climb[2.0Vs].speed_mps | 17.91 | 18.46 | +0.55 (+3.1 %) |
| climb | climb[2.0Vs].vertical_speed_mps | 16.23 | 15.65 | -0.58 (-3.6 %) |
| dead_stick_landing | dead_stick_landing.approach_max_speed_mps | 15.43 | 15.09 | -0.34 (-2.2 %) |
| dead_stick_landing | dead_stick_landing.approach_min_speed_mps | 12.99 | 13.19 | +0.2 (+1.5 %) |
| dead_stick_landing | dead_stick_landing.flare_height_m | 1.7 | 1.75 | +0.05 (+2.9 %) |
| dead_stick_landing | dead_stick_landing.glide_sink_mps | 1.7 | 1.75 | +0.05 (+2.9 %) |
| dead_stick_landing | dead_stick_landing.glide_speed_mps | 12.67 | 13.01 | +0.34 (+2.7 %) |
| dead_stick_landing | dead_stick_landing.touchdown_past_aim_m | 12.6 | 12.8 | +0.2 (+1.6 %) |
| dead_stick_landing | dead_stick_landing.touchdown_pitch_deg | 2.5 | 2.7 | +0.2 (+8.0 %) |
| dead_stick_landing | dead_stick_landing.touchdown_speed_mps | 12.98 | 13.19 | +0.21 (+1.6 %) |
| engine_cut_climb | engine_cut_climb[delay_1s].alpha_margin_to_stall_deg | 1.5 | 2.3 | +0.8 (+53.3 %) |
| engine_cut_climb | engine_cut_climb[delay_1s].climb_pitch_at_cut_deg | 68.5 | 64.2 | -4.3 (-6.3 %) |
| engine_cut_climb | engine_cut_climb[delay_1s].climb_speed_mps | 14.51 | 14.9 | +0.39 (+2.7 %) |
| engine_cut_climb | engine_cut_climb[delay_1s].glide_speed_mps | 12.69 | 13.03 | +0.34 (+2.7 %) |
| engine_cut_climb | engine_cut_climb[delay_1s].height_change_10_s_m | 3.0 | 1.9 | -1.1 (-36.7 %) |
| engine_cut_climb | engine_cut_climb[delay_1s].height_gained_after_cut_m | 23.9 | 23.2 | -0.7 (-2.9 %) |
| engine_cut_climb | engine_cut_climb[delay_1s].max_alpha_deg | 10.6 | 9.8 | -0.8 (-7.5 %) |
| engine_cut_climb | engine_cut_climb[delay_1s].min_speed_mps | 7.22 | 7.71 | +0.49 (+6.8 %) |
| engine_cut_climb | engine_cut_climb[delay_1s].min_speed_vs | 0.8 | 0.83 | +0.03 (+3.7 %) |
| engine_cut_climb | engine_cut_climb[delay_1s].rpm_10_s_after_cut | 3948 | 4049 | +101 (+2.6 %) |
| engine_cut_climb | engine_cut_climb[delay_1s].speed_after_reaction_mps | 13.7 | 13.85 | +0.15 (+1.1 %) |
| engine_cut_climb | engine_cut_climb[delay_2s].alpha_margin_to_stall_deg | -101.7 | -72.3 | +29.4 (+28.9 %) |
| engine_cut_climb | engine_cut_climb[delay_2s].climb_pitch_at_cut_deg | 68.5 | 64.2 | -4.3 (-6.3 %) |
| engine_cut_climb | engine_cut_climb[delay_2s].climb_speed_mps | 14.51 | 14.9 | +0.39 (+2.7 %) |
| engine_cut_climb | engine_cut_climb[delay_2s].glide_speed_mps | 12.69 | 13.03 | +0.34 (+2.7 %) |
| engine_cut_climb | engine_cut_climb[delay_2s].height_change_10_s_m | -83.8 | -97.9 | -14.1 (-16.8 %) |
| engine_cut_climb | engine_cut_climb[delay_2s].height_gained_after_cut_m | 26.8 | 26.2 | -0.6 (-2.2 %) |
| engine_cut_climb | engine_cut_climb[delay_2s].max_alpha_deg | 113.8 | 84.5 | -29.3 (-25.7 %) |
| engine_cut_climb | engine_cut_climb[delay_2s].min_speed_mps | 2.25 | 2.91 | +0.66 (+29.3 %) |
| engine_cut_climb | engine_cut_climb[delay_2s].min_speed_vs | 0.25 | 0.31 | +0.06 (+24.0 %) |
| engine_cut_climb | engine_cut_climb[delay_2s].rpm_10_s_after_cut | 6199 | 7506 | +1307 (+21.1 %) |
| engine_cut_climb | engine_cut_climb[delay_2s].speed_after_reaction_mps | 5.15 | 5.61 | +0.46 (+8.9 %) |
| engine_cut_climb | engine_cut_climb[delay_2s].time_below_1_2vs_s | 2.98 | 2.74 | -0.24 (-8.1 %) |
| glide | glide.best.path_angle_deg | 0.7 | 0.4 | -0.3 (-42.9 %) |
| glide | glide.best.pitch_deg | 7.5 | 7.2 | -0.3 (-4.0 %) |
| glide | glide.best.rpm | 5089 | 5186 | +97 (+1.9 %) |
| glide | glide.best.speed_mps | 11.79 | 12.11 | +0.32 (+2.7 %) |
| glide | glide.best.vertical_speed_mps | 0.15 | 0.08 | -0.07 (-46.7 %) |
| glide | glide[1.3Vs].path_angle_deg | 0.7 | 0.4 | -0.3 (-42.9 %) |
| glide | glide[1.3Vs].pitch_deg | 7.5 | 7.2 | -0.3 (-4.0 %) |
| glide | glide[1.3Vs].rpm | 5089 | 5186 | +97 (+1.9 %) |
| glide | glide[1.3Vs].speed_mps | 11.79 | 12.11 | +0.32 (+2.7 %) |
| glide | glide[1.3Vs].vertical_speed_mps | 0.15 | 0.08 | -0.07 (-46.7 %) |
| glide | glide[1.6Vs].glide_ratio | – | 251.72 | added/removed |
| glide | glide[1.6Vs].path_angle_deg | 0.1 | -0.2 | -0.3 (-300.0 %) |
| glide | glide[1.6Vs].pitch_deg | 4.1 | 3.8 | -0.3 (-7.3 %) |
| glide | glide[1.6Vs].rpm | 5945 | 6069 | +124 (+2.1 %) |
| glide | glide[1.6Vs].speed_mps | 14.5 | 14.89 | +0.39 (+2.7 %) |
| glide | glide[1.6Vs].vertical_speed_mps | 0.03 | -0.06 | -0.09 (-300.0 %) |
| glide | glide[2.0Vs].glide_ratio | 28.17 | 22.96 | -5.21 (-18.5 %) |
| glide | glide[2.0Vs].path_angle_deg | -2.0 | -2.5 | -0.5 (-25.0 %) |
| glide | glide[2.0Vs].pitch_deg | 0.1 | -0.4 | -0.5 (-500.0 %) |
| glide | glide[2.0Vs].rpm | 7105 | 7248 | +143 (+2.0 %) |
| glide | glide[2.0Vs].speed_mps | 18.12 | 18.61 | +0.49 (+2.7 %) |
| glide | glide[2.0Vs].vertical_speed_mps | -0.64 | -0.81 | -0.17 (-26.6 %) |
| glide_turn | glide_turn.least_height_lost_180_m | 11.4 | 12.2 | +0.8 (+7.0 %) |
| glide_turn | glide_turn[30deg].height_lost_180_m | 12.4 | 13.2 | +0.8 (+6.5 %) |
| glide_turn | glide_turn[30deg].height_lost_360_m | 25.0 | 26.5 | +1.5 (+6.0 %) |
| glide_turn | glide_turn[30deg].radius_m | 27.0 | 28.5 | +1.5 (+5.6 %) |
| glide_turn | glide_turn[30deg].speed_in_turn_mps | 12.57 | 12.92 | +0.35 (+2.8 %) |
| glide_turn | glide_turn[30deg].speed_target_mps | 12.66 | 13.01 | +0.35 (+2.8 %) |
| glide_turn | glide_turn[30deg].straight_sink_mps | 0.79 | 1.02 | +0.23 (+29.1 %) |
| glide_turn | glide_turn[30deg].time_to_180_s | 6.93 | 7.15 | +0.22 (+3.2 %) |
| glide_turn | glide_turn[30deg].time_to_360_s | 13.67 | 14.08 | +0.41 (+3.0 %) |
| glide_turn | glide_turn[30deg].turn_sink_mps | 1.87 | 1.92 | +0.05 (+2.7 %) |
| glide_turn | glide_turn[45deg].height_lost_180_m | 11.4 | 12.2 | +0.8 (+7.0 %) |
| glide_turn | glide_turn[45deg].height_lost_360_m | 21.5 | 22.9 | +1.4 (+6.5 %) |
| glide_turn | glide_turn[45deg].radius_m | 18.5 | 19.6 | +1.1 (+5.9 %) |
| glide_turn | glide_turn[45deg].speed_in_turn_mps | 13.61 | 14.01 | +0.4 (+2.9 %) |
| glide_turn | glide_turn[45deg].speed_target_mps | 14.02 | 14.39 | +0.37 (+2.6 %) |
| glide_turn | glide_turn[45deg].straight_sink_mps | 1.37 | 1.64 | +0.27 (+19.7 %) |
| glide_turn | glide_turn[45deg].time_to_180_s | 4.71 | 4.85 | +0.14 (+3.0 %) |
| glide_turn | glide_turn[45deg].time_to_360_s | 8.98 | 9.25 | +0.27 (+3.0 %) |
| glide_turn | glide_turn[45deg].turn_sink_mps | 2.37 | 2.43 | +0.06 (+2.5 %) |
| glide_turn | glide_turn[60deg].height_lost_180_m | 15.3 | 16.3 | +1 (+6.5 %) |
| glide_turn | glide_turn[60deg].height_lost_360_m | 26.1 | 27.7 | +1.6 (+6.1 %) |
| glide_turn | glide_turn[60deg].radius_m | 15.9 | 16.8 | +0.9 (+5.7 %) |
| glide_turn | glide_turn[60deg].speed_in_turn_mps | 16.25 | 16.71 | +0.46 (+2.8 %) |
| glide_turn | glide_turn[60deg].speed_target_mps | 16.67 | 17.12 | +0.45 (+2.7 %) |
| glide_turn | glide_turn[60deg].straight_sink_mps | 2.52 | 2.64 | +0.12 (+4.8 %) |
| glide_turn | glide_turn[60deg].time_to_180_s | 3.6 | 3.68 | +0.08 (+2.2 %) |
| glide_turn | glide_turn[60deg].time_to_360_s | 6.67 | 6.83 | +0.16 (+2.4 %) |
| glide_turn | glide_turn[60deg].turn_sink_mps | 3.48 | 3.59 | +0.11 (+3.2 %) |
| go_around | go_around[fast].climb_rate_after_15_m_mps | 17.21 | 16.89 | -0.32 (-1.9 %) |
| go_around | go_around[fast].max_bank_deg | 1.6 | 1.5 | -0.1 (-6.3 %) |
| go_around | go_around[slow].climb_rate_after_15_m_mps | 13.3 | 13.15 | -0.15 (-1.1 %) |
| go_around | go_around[slow].max_heading_error_deg | 0.8 | 0.7 | -0.1 (-12.5 %) |
| go_around | go_around[slow].time_to_15_m_s | 2.17 | 2.2 | +0.03 (+1.4 %) |
| hands_off | hands_off.bank_10_s_deg | 1.7 | 8.1 | +6.4 (+376.5 %) |
| hands_off | hands_off.bank_30_s_deg | 4.3 | 9.9 | +5.6 (+130.2 %) |
| hands_off | hands_off.bank_after_aileron_pulse_deg | 12.9 | 13.4 | +0.5 (+3.9 %) |
| hands_off | hands_off.heading_change_10_s_deg | 24.9 | 34.2 | +9.3 (+37.3 %) |
| hands_off | hands_off.heading_change_30_s_deg | 72.5 | 124.9 | +52.4 (+72.3 %) |
| hands_off | hands_off.height_change_10_s_m | 2.8 | -4.91 | -7.71 (-275.4 %) |
| hands_off | hands_off.height_change_30_s_m | -4.56 | -5.65 | -1.09 (-23.9 %) |
| hands_off | hands_off.phugoid_period_s | None | 13.54 |  |
| hands_off | hands_off.speed_change_10_s_mps | 1.14 | 2.42 | +1.28 (+112.3 %) |
| hands_off | hands_off.speed_change_30_s_mps | 0.41 | 0.24 | -0.17 (-41.5 %) |
| immelmann | immelmann.exit_bank_deg | -0.2 | -0.3 | -0.1 (-50.0 %) |
| immelmann | immelmann.half_loop_time_s | 2.4 | 2.67 | +0.27 (+11.2 %) |
| immelmann | immelmann.half_roll_time_s | 0.71 | 0.72 | +0.01 (+1.4 %) |
| immelmann | immelmann.heading_error_deg | -3.8 | -3.3 | +0.5 (+13.2 %) |
| immelmann | immelmann.height_gain_m | 37.9 | 42.4 | +4.5 (+11.9 %) |
| immelmann | immelmann.max_load_factor_g | 4.36 | 3.93 | -0.43 (-9.9 %) |
| immelmann | immelmann.max_sideslip_deg | 4.2 | 4.1 | -0.1 (-2.4 %) |
| immelmann | immelmann.top_speed_mps | 27.57 | 27.1 | -0.47 (-1.7 %) |
| immelmann | immelmann.top_speed_vs | 3.04 | 2.91 | -0.13 (-4.3 %) |
| inverted | inverted.alpha_deg | -3.4 | -3.5 | -0.1 (-2.9 %) |
| inverted | inverted.elevator_servo | -0.019 | -0.066 | -0.047 (-247.4 %) |
| inverted | inverted.elevator_stick | -0.019 | -0.066 | -0.047 (-247.4 %) |
| inverted | inverted.throttle | 0.29 | 0.276 | -0.014 (-4.8 %) |
| inverted | inverted.vertical_speed_mps | 0.04 | 0.02 | -0.02 (-50.0 %) |
| inverted_speeds | inverted_speeds[0.6Vmax].alpha_deg | -3.4 | -3.5 | -0.1 (-2.9 %) |
| inverted_speeds | inverted_speeds[0.6Vmax].elevator_servo | -0.019 | -0.066 | -0.047 (-247.4 %) |
| inverted_speeds | inverted_speeds[0.6Vmax].elevator_stick | -0.019 | -0.066 | -0.047 (-247.4 %) |
| inverted_speeds | inverted_speeds[0.6Vmax].throttle | 0.29 | 0.276 | -0.014 (-4.8 %) |
| inverted_speeds | inverted_speeds[0.6Vmax].vertical_speed_mps | 0.04 | 0.02 | -0.02 (-50.0 %) |
| inverted_speeds | inverted_speeds[0.8Vmax].elevator_servo | -0.011 | -0.037 | -0.026 (-236.4 %) |
| inverted_speeds | inverted_speeds[0.8Vmax].elevator_stick | -0.011 | -0.037 | -0.026 (-236.4 %) |
| inverted_speeds | inverted_speeds[0.8Vmax].throttle | 0.583 | 0.571 | -0.012 (-2.1 %) |
| inverted_speeds | inverted_speeds[start].alpha_deg | -4.1 | -4.3 | -0.2 (-4.9 %) |
| inverted_speeds | inverted_speeds[start].elevator_servo | -0.024 | -0.089 | -0.065 (-270.8 %) |
| inverted_speeds | inverted_speeds[start].elevator_stick | -0.024 | -0.089 | -0.065 (-270.8 %) |
| inverted_speeds | inverted_speeds[start].throttle | 0.214 | 0.198 | -0.016 (-7.5 %) |
| inverted_speeds | inverted_speeds[start].vertical_speed_mps | 0.03 | -0.02 | -0.05 (-166.7 %) |
| inverted_turn | inverted_turn[left].alpha_deg | -4.2 | -4.4 | -0.2 (-4.8 %) |
| inverted_turn | inverted_turn[left].elevator_stick | -0.084 | -0.151 | -0.067 (-79.8 %) |
| inverted_turn | inverted_turn[left].throttle | 0.327 | 0.308 | -0.019 (-5.8 %) |
| inverted_turn | inverted_turn[left].vertical_speed_mps | 0.02 | 0.0 | -0.02 (-100.0 %) |
| inverted_turn | inverted_turn[right].alpha_deg | -4.2 | -4.4 | -0.2 (-4.8 %) |
| inverted_turn | inverted_turn[right].elevator_stick | -0.068 | -0.135 | -0.067 (-98.5 %) |
| inverted_turn | inverted_turn[right].throttle | 0.33 | 0.312 | -0.018 (-5.5 %) |
| knife_edge | knife_edge[left_100pct].aileron_stick | -0.163 | -0.177 | -0.014 (-8.6 %) |
| knife_edge | knife_edge[left_100pct].height_change_10_s_m | -6.9 | -7.6 | -0.7 (-10.1 %) |
| knife_edge | knife_edge[left_100pct].pitch_attitude_deg | 7.9 | 8.7 | +0.8 (+10.1 %) |
| knife_edge | knife_edge[left_100pct].rudder_stick | 0.185 | 0.242 | +0.057 (+30.8 %) |
| knife_edge | knife_edge[left_100pct].sideslip_deg | -8.1 | -8.9 | -0.8 (-9.9 %) |
| knife_edge | knife_edge[left_50pct].height_change_10_s_m | -60.1 | -74.0 | -13.9 (-23.1 %) |
| knife_edge | knife_edge[left_50pct].pitch_attitude_deg | 5.3 | 2.2 | -3.1 (-58.5 %) |
| knife_edge | knife_edge[left_50pct].speed_after_5_s_mps | 31.34 | 32.2 | +0.86 (+2.7 %) |
| knife_edge | knife_edge[left_50pct].speed_end_mps | 35.35 | 36.34 | +0.99 (+2.8 %) |
| knife_edge | knife_edge[left_50pct].vertical_speed_mps | -9.15 | -11.16 | -2.01 (-22.0 %) |
| knife_edge | knife_edge[right_100pct].aileron_stick | 0.203 | 0.217 | +0.014 (+6.9 %) |
| knife_edge | knife_edge[right_100pct].height_change_10_s_m | -6.7 | -7.4 | -0.7 (-10.4 %) |
| knife_edge | knife_edge[right_100pct].pitch_attitude_deg | 7.7 | 8.5 | +0.8 (+10.4 %) |
| knife_edge | knife_edge[right_100pct].rudder_stick | -0.149 | -0.206 | -0.057 (-38.3 %) |
| knife_edge | knife_edge[right_100pct].sideslip_deg | 7.9 | 8.7 | +0.8 (+10.1 %) |
| knife_edge | knife_edge[right_100pct].vertical_speed_mps | -0.09 | -0.11 | -0.02 (-22.2 %) |
| knife_edge | knife_edge[right_50pct].height_change_10_s_m | -64.7 | -75.7 | -11 (-17.0 %) |
| knife_edge | knife_edge[right_50pct].pitch_attitude_deg | 4.5 | 2.1 | -2.4 (-53.3 %) |
| knife_edge | knife_edge[right_50pct].speed_after_5_s_mps | 31.79 | 32.49 | +0.7 (+2.2 %) |
| knife_edge | knife_edge[right_50pct].speed_end_mps | 35.42 | 36.23 | +0.81 (+2.3 %) |
| knife_edge | knife_edge[right_50pct].vertical_speed_mps | -9.66 | -11.19 | -1.53 (-15.8 %) |
| knife_edge_full_rudder | knife_edge_full_rudder[left_100pct].height_change_10_s_m | 9.5 | -4.7 | -14.2 (-149.5 %) |
| knife_edge_full_rudder | knife_edge_full_rudder[left_100pct].pitch_attitude_deg | 25.3 | 21.8 | -3.5 (-13.8 %) |
| knife_edge_full_rudder | knife_edge_full_rudder[left_100pct].speed_after_5_s_mps | 36.71 | 37.08 | +0.37 (+1.0 %) |
| knife_edge_full_rudder | knife_edge_full_rudder[left_100pct].speed_end_mps | 35.43 | 36.32 | +0.89 (+2.5 %) |
| knife_edge_full_rudder | knife_edge_full_rudder[left_100pct].vertical_speed_mps | 2.83 | 0.75 | -2.08 (-73.5 %) |
| knife_edge_full_rudder | knife_edge_full_rudder[left_50pct].height_change_10_s_m | -89.8 | -96.8 | -7 (-7.8 %) |
| knife_edge_full_rudder | knife_edge_full_rudder[left_50pct].pitch_attitude_deg | 0.7 | -0.8 | -1.5 (-214.3 %) |
| knife_edge_full_rudder | knife_edge_full_rudder[left_50pct].speed_after_5_s_mps | 33.95 | 34.33 | +0.38 (+1.1 %) |
| knife_edge_full_rudder | knife_edge_full_rudder[left_50pct].speed_end_mps | 36.46 | 37.08 | +0.62 (+1.7 %) |
| knife_edge_full_rudder | knife_edge_full_rudder[left_50pct].vertical_speed_mps | -12.35 | -13.33 | -0.98 (-7.9 %) |
| knife_edge_full_rudder | knife_edge_full_rudder[right_100pct].height_change_10_s_m | 17.3 | 2.1 | -15.2 (-87.9 %) |
| knife_edge_full_rudder | knife_edge_full_rudder[right_100pct].pitch_attitude_deg | 26.6 | 22.9 | -3.7 (-13.9 %) |
| knife_edge_full_rudder | knife_edge_full_rudder[right_100pct].speed_after_5_s_mps | 36.25 | 36.67 | +0.42 (+1.2 %) |
| knife_edge_full_rudder | knife_edge_full_rudder[right_100pct].speed_end_mps | 34.95 | 35.89 | +0.94 (+2.7 %) |
| knife_edge_full_rudder | knife_edge_full_rudder[right_100pct].vertical_speed_mps | 3.62 | 1.46 | -2.16 (-59.7 %) |
| knife_edge_full_rudder | knife_edge_full_rudder[right_50pct].height_change_10_s_m | -84.5 | -92.0 | -7.5 (-8.9 %) |
| knife_edge_full_rudder | knife_edge_full_rudder[right_50pct].pitch_attitude_deg | 1.4 | -0.1 | -1.5 (-107.1 %) |
| knife_edge_full_rudder | knife_edge_full_rudder[right_50pct].speed_after_5_s_mps | 33.57 | 33.99 | +0.42 (+1.3 %) |
| knife_edge_full_rudder | knife_edge_full_rudder[right_50pct].speed_end_mps | 36.17 | 36.79 | +0.62 (+1.7 %) |
| knife_edge_full_rudder | knife_edge_full_rudder[right_50pct].vertical_speed_mps | -11.84 | -12.84 | -1 (-8.4 %) |
| landing | landing.approach_speed_mps | 11.79 | 12.1 | +0.31 (+2.6 %) |
| landing | landing.flare_height_m | 0.824117143225668 | 0.846370784784982 | +0.02225 (+2.7 %) |
| landing | landing.rollout_m | 95.2 | 91.1 | -4.1 (-4.3 %) |
| landing | landing.rollout_time_s | 8.55 | 8.03 | -0.52 (-6.1 %) |
| landing | landing.touchdown_past_threshold_m | 47.0 | 46.2 | -0.8 (-1.7 %) |
| landing | landing.touchdown_pitch_deg | 0.1 | 0.3 | +0.2 (+200.0 %) |
| landing | landing.touchdown_sink_mps | 0.44 | 0.43 | -0.01 (-2.3 %) |
| landing | landing.touchdown_speed_vs | 2.15 | 2.1 | -0.05 (-2.3 %) |
| loop | loop.heading_change_deg | 0.5 | 0.7 | +0.2 (+40.0 %) |
| loop | loop.height_change_m | 13.5 | 15.4 | +1.9 (+14.1 %) |
| loop | loop.loop_height_m | 41.5 | 45.8 | +4.3 (+10.4 %) |
| loop | loop.loop_time_s | 3.73 | 4.11 | +0.38 (+10.2 %) |
| loop | loop.max_load_factor_g | 11.07 | 10.24 | -0.83 (-7.5 %) |
| loop | loop.max_sideslip_deg | 3.2 | 2.6 | -0.6 (-18.8 %) |
| loop | loop.min_speed_mps | 26.9 | 26.39 | -0.51 (-1.9 %) |
| modes | modes[0.8Vmax].dutch_roll_hz | 1.083 | 1.192 | +0.109 (+10.1 %) |
| modes | modes[0.8Vmax].dutch_roll_zeta | 0.35 | 0.325 | -0.025 (-7.1 %) |
| modes | modes[0.8Vmax].short_period_hz | 0.04 | 0.052 | +0.012 (+30.0 %) |
| modes | modes[0.8Vmax].short_period_zeta | 2.118 | 1.533 | -0.585 (-27.6 %) |
| modes | modes[0.8Vmax].spiral_time_to_half_s | 14.1 | 22.7 | +8.6 (+61.0 %) |
| modes | modes[start].dutch_roll_hz | 0.72 | 0.789 | +0.069 (+9.6 %) |
| modes | modes[start].dutch_roll_zeta | 0.344 | 0.324 | -0.02 (-5.8 %) |
| modes | modes[start].phugoid_period_s | 16.13 | 12.47 | -3.66 (-22.7 %) |
| modes | modes[start].phugoid_zeta | 0.875 | 0.625 | -0.25 (-28.6 %) |
| modes | modes[start].short_period_hz | 2.999 | 2.208 | -0.791 (-26.4 %) |
| modes | modes[start].short_period_zeta | 0.966 | 0.906 | -0.06 (-6.2 %) |
| modes | modes[start].spiral_time_to_half_s | 11.6 | 21.6 | +10 (+86.2 %) |
| outside_loop | outside_loop.heading_change_deg | 6.1 | 6.9 | +0.8 (+13.1 %) |
| outside_loop | outside_loop.height_change_m | -10.6 | -14.5 | -3.9 (-36.8 %) |
| outside_loop | outside_loop.loop_depth_m | 45.0 | 52.9 | +7.9 (+17.6 %) |
| outside_loop | outside_loop.loop_time_s | 5.29 | 5.8 | +0.51 (+9.6 %) |
| outside_loop | outside_loop.max_sideslip_deg | 6.6 | 5.0 | -1.6 (-24.2 %) |
| outside_loop | outside_loop.max_speed_mps | 28.32 | 29.83 | +1.51 (+5.3 %) |
| outside_loop | outside_loop.min_load_factor_g | -4.62 | -4.38 | +0.24 (+5.2 %) |
| outside_loop | outside_loop.min_speed_mps | 20.41 | 21.05 | +0.64 (+3.1 %) |
| pitch_pull | pitch_pull[0.8Vmax].load_factor_at_cl_max | 11.79 | 11.18 | -0.61 (-5.2 %) |
| pitch_pull | pitch_pull[0.8Vmax].peak_alpha_deg | 22.3 | 18.7 | -3.6 (-16.1 %) |
| pitch_pull | pitch_pull[0.8Vmax].peak_load_factor_g | 10.42 | 9.72 | -0.7 (-6.7 %) |
| pitch_pull | pitch_pull[0.8Vmax].peak_pitch_rate_dps | 265.4 | 213.0 | -52.4 (-19.7 %) |
| pitch_pull | pitch_pull[start].load_factor_at_cl_max | 4.87 | 4.61 | -0.26 (-5.3 %) |
| pitch_pull | pitch_pull[start].peak_alpha_deg | 23.1 | 19.8 | -3.3 (-14.3 %) |
| pitch_pull | pitch_pull[start].peak_load_factor_g | 4.3 | 4.01 | -0.29 (-6.7 %) |
| pitch_pull | pitch_pull[start].peak_pitch_rate_dps | 160.8 | 128.2 | -32.6 (-20.3 %) |
| point_roll | point_roll[left].heading_change_deg | 2.3 | 3.2 | +0.9 (+39.1 %) |
| point_roll | point_roll[left].height_change_m | -0.4 | -0.5 | -0.1 (-25.0 %) |
| point_roll | point_roll[left].max_height_deviation_m | 1.4 | 2.0 | +0.6 (+42.9 %) |
| point_roll | point_roll[left].max_sideslip_deg | 10.2 | 11.3 | +1.1 (+10.8 %) |
| point_roll | point_roll[left].over_rotation_point_1_deg | -1.6 | -1.3 | +0.3 (+18.8 %) |
| point_roll | point_roll[left].over_rotation_point_2_deg | 0.5 | 1.0 | +0.5 (+100.0 %) |
| point_roll | point_roll[left].over_rotation_point_3_deg | 1.7 | 2.0 | +0.3 (+17.6 %) |
| point_roll | point_roll[left].over_rotation_point_4_deg | 3.4 | 3.7 | +0.3 (+8.8 %) |
| point_roll | point_roll[left].peak_push_stick | 0.031 | 0.075 | +0.044 (+141.9 %) |
| point_roll | point_roll[left].peak_rudder_stick | 0.233 | 0.301 | +0.068 (+29.2 %) |
| point_roll | point_roll[left].point_1_elevator_stick | -0.005 | -0.027 | -0.022 (-440.0 %) |
| point_roll | point_roll[left].point_1_rudder_stick | 0.197 | 0.258 | +0.061 (+31.0 %) |
| point_roll | point_roll[left].point_2_elevator_stick | -0.023 | -0.071 | -0.048 (-208.7 %) |
| point_roll | point_roll[left].point_3_elevator_stick | -0.007 | -0.03 | -0.023 (-328.6 %) |
| point_roll | point_roll[left].point_3_rudder_stick | -0.188 | -0.257 | -0.069 (-36.7 %) |
| point_roll | point_roll[right].exit_bank_deg | -0.8 | -0.9 | -0.1 (-12.5 %) |
| point_roll | point_roll[right].heading_change_deg | -2.3 | -3.2 | -0.9 (-39.1 %) |
| point_roll | point_roll[right].height_change_m | 0.0 | -0.1 | -0.1 |
| point_roll | point_roll[right].max_height_deviation_m | 1.1 | 1.8 | +0.7 (+63.6 %) |
| point_roll | point_roll[right].max_sideslip_deg | 10.9 | 12.1 | +1.2 (+11.0 %) |
| point_roll | point_roll[right].over_rotation_point_1_deg | 0.1 | 0.2 | +0.1 (+100.0 %) |
| point_roll | point_roll[right].over_rotation_point_2_deg | -0.2 | 0.1 | +0.3 (+150.0 %) |
| point_roll | point_roll[right].over_rotation_point_3_deg | 4.2 | 4.5 | +0.3 (+7.1 %) |
| point_roll | point_roll[right].over_rotation_point_4_deg | 3.1 | 3.4 | +0.3 (+9.7 %) |
| point_roll | point_roll[right].peak_push_stick | 0.033 | 0.078 | +0.045 (+136.4 %) |
| point_roll | point_roll[right].peak_rudder_stick | 0.245 | 0.309 | +0.064 (+26.1 %) |
| point_roll | point_roll[right].point_1_elevator_stick | -0.007 | -0.03 | -0.023 (-328.6 %) |
| point_roll | point_roll[right].point_1_rudder_stick | -0.184 | -0.245 | -0.061 (-33.2 %) |
| point_roll | point_roll[right].point_2_elevator_stick | -0.023 | -0.071 | -0.048 (-208.7 %) |
| point_roll | point_roll[right].point_3_elevator_stick | -0.006 | -0.026 | -0.02 (-333.3 %) |
| point_roll | point_roll[right].point_3_rudder_stick | 0.196 | 0.265 | +0.069 (+35.2 %) |
| roll_rate | roll_rate[0.8Vmax_left].height_change_m | -5.9 | -8.4 | -2.5 (-42.4 %) |
| roll_rate | roll_rate[0.8Vmax_left].max_sideslip_deg | 9.2 | 9.1 | -0.1 (-1.1 %) |
| roll_rate | roll_rate[0.8Vmax_left].time_to_360_s | 1.6 | 1.58 | -0.02 (-1.3 %) |
| roll_rate | roll_rate[0.8Vmax_right].height_change_m | -5.6 | -7.7 | -2.1 (-37.5 %) |
| roll_rate | roll_rate[0.8Vmax_right].max_roll_rate_dps | 256.5 | 262.2 | +5.7 (+2.2 %) |
| roll_rate | roll_rate[0.8Vmax_right].max_sideslip_deg | 8.7 | 8.2 | -0.5 (-5.7 %) |
| roll_rate | roll_rate[0.8Vmax_right].time_to_360_s | 1.58 | 1.53 | -0.05 (-3.2 %) |
| roll_rate | roll_rate[1.3Vs_left].height_change_m | -27.5 | -32.6 | -5.1 (-18.5 %) |
| roll_rate | roll_rate[1.3Vs_left].max_roll_rate_dps | 165.4 | 167.4 | +2 (+1.2 %) |
| roll_rate | roll_rate[1.3Vs_left].max_sideslip_deg | 13.4 | 13.6 | +0.2 (+1.5 %) |
| roll_rate | roll_rate[1.3Vs_left].speed_mps | 11.79 | 12.1 | +0.31 (+2.6 %) |
| roll_rate | roll_rate[1.3Vs_left].time_to_360_s | 2.96 | 3.04 | +0.08 (+2.7 %) |
| roll_rate | roll_rate[1.3Vs_right].height_change_m | -25.0 | -27.9 | -2.9 (-11.6 %) |
| roll_rate | roll_rate[1.3Vs_right].max_roll_rate_dps | 174.4 | 189.0 | +14.6 (+8.4 %) |
| roll_rate | roll_rate[1.3Vs_right].speed_mps | 11.79 | 12.1 | +0.31 (+2.6 %) |
| roll_rate | roll_rate[start_left].height_change_m | -16.8 | -20.2 | -3.4 (-20.2 %) |
| roll_rate | roll_rate[start_right].height_change_m | -16.1 | -18.5 | -2.4 (-14.9 %) |
| roll_rate | roll_rate[start_right].max_roll_rate_dps | 188.4 | 190.4 | +2 (+1.1 %) |
| roll_rate | roll_rate[start_right].max_sideslip_deg | 10.6 | 10.3 | -0.3 (-2.8 %) |
| roll_rate | roll_rate[start_right].time_to_360_s | 2.3 | 2.25 | -0.05 (-2.2 %) |
| rudder_step | rudder_step[left].bank_after_2_75_s_deg | -152.5 | -160.6 | -8.1 (-5.3 %) |
| rudder_step | rudder_step[left].max_sideslip_deg | 26.4 | 26.0 | -0.4 (-1.5 %) |
| rudder_step | rudder_step[left].peak_yaw_rate_dps | 109.7 | 108.4 | -1.3 (-1.2 %) |
| rudder_step | rudder_step[left].pitch_change_deg | -64.3 | -67.4 | -3.1 (-4.8 %) |
| rudder_step | rudder_step[right].bank_after_2_75_s_deg | 147.4 | 154.0 | +6.6 (+4.5 %) |
| rudder_step | rudder_step[right].max_sideslip_deg | 27.0 | 26.5 | -0.5 (-1.9 %) |
| rudder_step | rudder_step[right].peak_yaw_rate_dps | 109.6 | 108.0 | -1.6 (-1.5 %) |
| rudder_step | rudder_step[right].pitch_change_deg | -65.4 | -68.0 | -2.6 (-4.0 %) |
| slow_roll | slow_roll[left].exit_bank_deg | 0.4 | 0.3 | -0.1 (-25.0 %) |
| slow_roll | slow_roll[left].heading_change_deg | 4.2 | 4.8 | +0.6 (+14.3 %) |
| slow_roll | slow_roll[left].height_change_m | -0.8 | -1.2 | -0.4 (-50.0 %) |
| slow_roll | slow_roll[left].max_height_deviation_m | 1.0 | 1.5 | +0.5 (+50.0 %) |
| slow_roll | slow_roll[left].max_sideslip_deg | 9.6 | 10.2 | +0.6 (+6.2 %) |
| slow_roll | slow_roll[left].peak_push_stick | 0.032 | 0.075 | +0.043 (+134.4 %) |
| slow_roll | slow_roll[left].peak_rudder_stick | 0.23 | 0.3 | +0.07 (+30.4 %) |
| slow_roll | slow_roll[right].exit_bank_deg | -0.2 | -0.1 | +0.1 (+50.0 %) |
| slow_roll | slow_roll[right].heading_change_deg | -3.9 | -4.5 | -0.6 (-15.4 %) |
| slow_roll | slow_roll[right].height_change_m | -0.5 | -0.9 | -0.4 (-80.0 %) |
| slow_roll | slow_roll[right].max_height_deviation_m | 0.8 | 1.3 | +0.5 (+62.5 %) |
| slow_roll | slow_roll[right].max_sideslip_deg | 9.7 | 10.9 | +1.2 (+12.4 %) |
| slow_roll | slow_roll[right].peak_push_stick | 0.032 | 0.074 | +0.042 (+131.2 %) |
| slow_roll | slow_roll[right].peak_rudder_stick | 0.243 | 0.314 | +0.071 (+29.2 %) |
| snap_roll | snap_roll[left].alpha_before_45_deg_of_roll_deg | 24.3 | 22.1 | -2.2 (-9.1 %) |
| snap_roll | snap_roll[left].entry_speed_mps | 14.51 | 14.9 | +0.39 (+2.7 %) |
| snap_roll | snap_roll[left].exit_bank_deg | 0.3 | 0.4 | +0.1 (+33.3 %) |
| snap_roll | snap_roll[left].heading_change_at_stop_deg | -18.9 | -7.7 | +11.2 (+59.3 %) |
| snap_roll | snap_roll[left].height_lost_m | 44.0 | 53.1 | +9.1 (+20.7 %) |
| snap_roll | snap_roll[left].max_alpha_deg | 24.3 | 23.5 | -0.8 (-3.3 %) |
| snap_roll | snap_roll[left].mean_roll_rate_dps | 166.2 | 187.2 | +21 (+12.6 %) |
| snap_roll | snap_roll[left].mean_yaw_rate_dps | 68.4 | 73.3 | +4.9 (+7.2 %) |
| snap_roll | snap_roll[left].peak_load_factor_g | 3.49 | 3.78 | +0.29 (+8.3 %) |
| snap_roll | snap_roll[left].peak_roll_rate_dps | 274.5 | 289.9 | +15.4 (+5.6 %) |
| snap_roll | snap_roll[left].stop_after_deg | 459.8 | 498.9 | +39.1 (+8.5 %) |
| snap_roll | snap_roll[left].stop_error_deg | 99.8 | 138.9 | +39.1 (+39.2 %) |
| snap_roll | snap_roll[left].time_to_level_s | 1.87 | 2.13 | +0.26 (+13.9 %) |
| snap_roll | snap_roll[left].time_to_release_s | 1.96 | 1.74 | -0.22 (-11.2 %) |
| snap_roll | snap_roll[left].yaw_to_roll_ratio | 0.411 | 0.391 | -0.02 (-4.9 %) |
| snap_roll | snap_roll[right].alpha_before_45_deg_of_roll_deg | 24.4 | 22.3 | -2.1 (-8.6 %) |
| snap_roll | snap_roll[right].autorotation_short_of_finish_deg | 70.4 | 0.0 | -70.4 (-100.0 %) |
| snap_roll | snap_roll[right].entry_speed_mps | 14.51 | 14.9 | +0.39 (+2.7 %) |
| snap_roll | snap_roll[right].exit_bank_deg | 0.1 | 0.2 | +0.1 (+100.0 %) |
| snap_roll | snap_roll[right].heading_change_at_stop_deg | 11.0 | 8.6 | -2.4 (-21.8 %) |
| snap_roll | snap_roll[right].height_lost_m | 26.5 | 24.5 | -2 (-7.5 %) |
| snap_roll | snap_roll[right].mean_roll_rate_dps | 162.0 | 177.0 | +15 (+9.3 %) |
| snap_roll | snap_roll[right].mean_yaw_rate_dps | 76.7 | 77.6 | +0.9 (+1.2 %) |
| snap_roll | snap_roll[right].peak_load_factor_g | 2.53 | 2.39 | -0.14 (-5.5 %) |
| snap_roll | snap_roll[right].peak_roll_rate_dps | 283.8 | 295.7 | +11.9 (+4.2 %) |
| snap_roll | snap_roll[right].release_after_deg | 289.6 | 320.8 | +31.2 (+10.8 %) |
| snap_roll | snap_roll[right].release_reason | autorotation ended | finish point |  |
| snap_roll | snap_roll[right].stop_after_deg | 342.2 | 386.3 | +44.1 (+12.9 %) |
| snap_roll | snap_roll[right].stop_error_deg | -17.8 | 26.3 | +44.1 (+247.8 %) |
| snap_roll | snap_roll[right].time_to_level_s | 1.51 | 1.64 | +0.13 (+8.6 %) |
| snap_roll | snap_roll[right].time_to_release_s | 1.79 | 1.81 | +0.02 (+1.1 %) |
| snap_roll | snap_roll[right].yaw_to_roll_ratio | 0.474 | 0.438 | -0.036 (-7.6 %) |
| spin | spin[left].height_lost_per_turn_m | 25.1 | 21.8 | -3.3 (-13.1 %) |
| spin | spin[left].max_alpha_deg | 28.0 | 27.7 | -0.3 (-1.1 %) |
| spin | spin[left].recovery_turns | 0.16 | 0.22 | +0.06 (+37.5 %) |
| spin | spin[left].steady_turn_time_s | 1.27 | 1.09 | -0.18 (-14.2 %) |
| spin | spin[left].total_height_lost_m | 116.3 | 123.3 | +7 (+6.0 %) |
| spin | spin[left].turns_in_6_s | 3.02 | 3.62 | +0.6 (+19.9 %) |
| spin | spin[right].height_lost_per_turn_m | 28.0 | 23.2 | -4.8 (-17.1 %) |
| spin | spin[right].max_alpha_deg | 28.2 | 27.1 | -1.1 (-3.9 %) |
| spin | spin[right].recovery_time_s | 0.58 | 0.32 | -0.26 (-44.8 %) |
| spin | spin[right].recovery_turns | 0.2 | 0.32 | +0.12 (+60.0 %) |
| spin | spin[right].steady_turn_time_s | 1.27 | 1.04 | -0.23 (-18.1 %) |
| spin | spin[right].total_height_lost_m | 135.8 | 126.2 | -9.6 (-7.1 %) |
| spin | spin[right].turns_in_6_s | 2.91 | 3.58 | +0.67 (+23.0 %) |
| spin_inverted | spin_inverted[left].height_lost_per_turn_m | 27.9 | 35.9 | +8 (+28.7 %) |
| spin_inverted | spin_inverted[left].min_alpha_deg | -21.7 | -15.3 | +6.4 (+29.5 %) |
| spin_inverted | spin_inverted[left].recovery_time_s | 0.28 | 0.43 | +0.15 (+53.6 %) |
| spin_inverted | spin_inverted[left].recovery_turns | 0.18 | 0.15 | -0.03 (-16.7 %) |
| spin_inverted | spin_inverted[left].steady_turn_time_s | 1.0 | 1.12 | +0.12 (+12.0 %) |
| spin_inverted | spin_inverted[left].total_height_lost_m | 185.3 | 195.0 | +9.7 (+5.2 %) |
| spin_inverted | spin_inverted[left].turns_in_6_s | 4.29 | 4.11 | -0.18 (-4.2 %) |
| spin_inverted | spin_inverted[right].height_lost_per_turn_m | 27.3 | 36.1 | +8.8 (+32.2 %) |
| spin_inverted | spin_inverted[right].min_alpha_deg | -23.3 | -19.2 | +4.1 (+17.6 %) |
| spin_inverted | spin_inverted[right].recovery_time_s | 0.28 | 0.25 | -0.03 (-10.7 %) |
| spin_inverted | spin_inverted[right].recovery_turns | 0.18 | 0.11 | -0.07 (-38.9 %) |
| spin_inverted | spin_inverted[right].steady_turn_time_s | 1.0 | 1.17 | +0.17 (+17.0 %) |
| spin_inverted | spin_inverted[right].total_height_lost_m | 174.1 | 176.8 | +2.7 (+1.6 %) |
| spin_inverted | spin_inverted[right].turns_in_6_s | 4.04 | 3.64 | -0.4 (-9.9 %) |
| split_s | split_s.exit_bank_deg | 0.0 | 0.2 | +0.2 |
| split_s | split_s.exit_speed_mps | 26.34 | 27.23 | +0.89 (+3.4 %) |
| split_s | split_s.heading_error_deg | -3.8 | -0.6 | +3.2 (+84.2 %) |
| split_s | split_s.height_lost_m | 32.6 | 36.3 | +3.7 (+11.3 %) |
| split_s | split_s.height_lost_to_level_m | 32.4 | 36.2 | +3.8 (+11.7 %) |
| split_s | split_s.max_load_factor_g | 5.85 | 5.55 | -0.3 (-5.1 %) |
| split_s | split_s.max_sideslip_deg | 8.7 | 8.3 | -0.4 (-4.6 %) |
| split_s | split_s.max_speed_mps | 26.57 | 27.51 | +0.94 (+3.5 %) |
| split_s | split_s.time_to_level_s | 3.74 | 3.85 | +0.11 (+2.9 %) |
| stall_cross_controlled | stall_cross_controlled[left].altitude_lost_m | 21.4 | 19.8 | -1.6 (-7.5 %) |
| stall_cross_controlled | stall_cross_controlled[left].entry_speed_mps | 13.09 | 13.45 | +0.36 (+2.8 %) |
| stall_cross_controlled | stall_cross_controlled[left].max_bank_in_recovery_deg | 92.5 | 90.7 | -1.8 (-1.9 %) |
| stall_cross_controlled | stall_cross_controlled[left].recovery_time_s | 2.63 | 2.53 | -0.1 (-3.8 %) |
| stall_cross_controlled | stall_cross_controlled[left].roll_off_in_1_s_deg | -52.4 | -50.3 | +2.1 (+4.0 %) |
| stall_cross_controlled | stall_cross_controlled[left].stall_alpha_deg | 17.8 | 17.5 | -0.3 (-1.7 %) |
| stall_cross_controlled | stall_cross_controlled[left].stall_speed_mps | 10.04 | 10.46 | +0.42 (+4.2 %) |
| stall_cross_controlled | stall_cross_controlled[left].stall_speed_vs | 1.108 | 1.124 | +0.016 (+1.4 %) |
| stall_cross_controlled | stall_cross_controlled[right].altitude_lost_m | 18.5 | 16.7 | -1.8 (-9.7 %) |
| stall_cross_controlled | stall_cross_controlled[right].entry_speed_mps | 13.09 | 13.45 | +0.36 (+2.8 %) |
| stall_cross_controlled | stall_cross_controlled[right].max_bank_in_recovery_deg | 89.7 | 87.3 | -2.4 (-2.7 %) |
| stall_cross_controlled | stall_cross_controlled[right].recovery_time_s | 2.47 | 2.4 | -0.07 (-2.8 %) |
| stall_cross_controlled | stall_cross_controlled[right].roll_off_in_1_s_deg | 49.4 | 47.2 | -2.2 (-4.5 %) |
| stall_cross_controlled | stall_cross_controlled[right].stall_alpha_deg | 18.2 | 17.9 | -0.3 (-1.6 %) |
| stall_cross_controlled | stall_cross_controlled[right].stall_speed_mps | 10.09 | 10.5 | +0.41 (+4.1 %) |
| stall_cross_controlled | stall_cross_controlled[right].stall_speed_vs | 1.113 | 1.128 | +0.015 (+1.3 %) |
| stall_held | stall_held[controls_neutral].break_kind | – | wing drop or sink | added/removed |
| stall_held | stall_held[controls_neutral].heading_change_held_deg | – | -661.1 | added/removed |
| stall_held | stall_held[controls_neutral].height_lost_held_m | – | 46.3 | added/removed |
| stall_held | stall_held[controls_neutral].height_lost_to_recovery_m | – | 46.4 | added/removed |
| stall_held | stall_held[controls_neutral].max_bank_held_deg | – | 108.1 | added/removed |
| stall_held | stall_held[controls_neutral].max_rotation_rate_dps | – | 341.6 | added/removed |
| stall_held | stall_held[controls_neutral].outcome | – | wing drop | added/removed |
| stall_held | stall_held[controls_neutral].recovery_time_s | – | None | added/removed |
| stall_held | stall_held[controls_neutral].rotation_rate_last_2_s_dps | – | 46.3 | added/removed |
| stall_held | stall_held[controls_neutral].stall_speed_mps | – | 9.56 | added/removed |
| stall_held | stall_held[wings_level].break_kind | – | wing drop or sink | added/removed |
| stall_held | stall_held[wings_level].heading_change_held_deg | – | -597.1 | added/removed |
| stall_held | stall_held[wings_level].height_lost_held_m | – | 41.3 | added/removed |
| stall_held | stall_held[wings_level].height_lost_to_recovery_m | – | 41.4 | added/removed |
| stall_held | stall_held[wings_level].max_bank_held_deg | – | 179.0 | added/removed |
| stall_held | stall_held[wings_level].max_rotation_rate_dps | – | 256.9 | added/removed |
| stall_held | stall_held[wings_level].outcome | – | wing drop | added/removed |
| stall_held | stall_held[wings_level].recovery_time_s | – | None | added/removed |
| stall_held | stall_held[wings_level].rotation_rate_last_2_s_dps | – | 34.1 | added/removed |
| stall_held | stall_held[wings_level].stall_speed_mps | – | 9.56 | added/removed |
| stall_inverted | stall_inverted.ratio_to_upright_vs | 1.186 | 1.2 | +0.014 (+1.2 %) |
| stall_inverted | stall_inverted.stall_speed_mps | 10.75 | 11.17 | +0.42 (+3.9 %) |
| stall_power_on | stall_power_on.altitude_lost_m | 13.5 | 11.3 | -2.2 (-16.3 %) |
| stall_power_on | stall_power_on.bank_in_first_second_deg | -87.2 | -81.8 | +5.4 (+6.2 %) |
| stall_power_on | stall_power_on.deceleration_before_break_mps2 | 1.26 | 1.21 | -0.05 (-4.0 %) |
| stall_power_on | stall_power_on.max_bank_in_recovery_deg | 87.2 | 81.8 | -5.4 (-6.2 %) |
| stall_power_on | stall_power_on.ratio_to_cl_max_estimate | 0.814 | 0.848 | +0.034 (+4.2 %) |
| stall_power_on | stall_power_on.recovery_time_s | 2.93 | 2.76 | -0.17 (-5.8 %) |
| stall_power_on | stall_power_on.stall_alpha_deg | 17.2 | 17.0 | -0.2 (-1.2 %) |
| stall_power_on | stall_power_on.stall_speed_mps | 7.38 | 7.9 | +0.52 (+7.0 %) |
| stall_turn | stall_turn[left_0.35Vs].exit_speed_mps | 29.7 | 31.1 | +1.4 (+4.7 %) |
| stall_turn | stall_turn[left_0.35Vs].height_gain_to_kick_m | 77.2 | 78.8 | +1.6 (+2.1 %) |
| stall_turn | stall_turn[left_0.35Vs].height_lost_top_to_level_m | 78.1 | 85.0 | +6.9 (+8.8 %) |
| stall_turn | stall_turn[left_0.35Vs].kick_speed_mps | 3.17 | 3.24 | +0.07 (+2.2 %) |
| stall_turn | stall_turn[left_0.35Vs].kick_speed_target_mps | 3.17 | 3.26 | +0.09 (+2.8 %) |
| stall_turn | stall_turn[left_0.35Vs].min_forward_speed_mps | -6.11 | -6.35 | -0.24 (-3.9 %) |
| stall_turn | stall_turn[left_0.35Vs].pitch_during_pivot_deg | 159.8 | 157.2 | -2.6 (-1.6 %) |
| stall_turn | stall_turn[left_0.35Vs].pivot_radius_m | 5.1 | 4.69 | -0.41 (-8.0 %) |
| stall_turn | stall_turn[left_0.35Vs].pivot_radius_spans | 3.35 | 3.08 | -0.27 (-8.1 %) |
| stall_turn | stall_turn[left_0.35Vs].pivot_time_s | 3.47 | 3.24 | -0.23 (-6.6 %) |
| stall_turn | stall_turn[left_0.35Vs].torque_off_deg | 232.1 | 123.1 | -109 (-47.0 %) |
| stall_turn | stall_turn[left_0.35Vs].up_line_time_s | 3.4 | 3.35 | -0.05 (-1.5 %) |
| stall_turn | stall_turn[left_0.6Vs].height_gain_to_kick_m | 76.0 | 77.5 | +1.5 (+2.0 %) |
| stall_turn | stall_turn[left_0.6Vs].kick_speed_mps | 5.43 | 5.57 | +0.14 (+2.6 %) |
| stall_turn | stall_turn[left_0.6Vs].kick_speed_target_mps | 5.44 | 5.59 | +0.15 (+2.8 %) |
| stall_turn | stall_turn[left_0.6Vs].min_forward_speed_mps | -4.57 | -4.63 | -0.06 (-1.3 %) |
| stall_turn | stall_turn[left_0.6Vs].pitch_during_pivot_deg | 29.6 | 49.5 | +19.9 (+67.2 %) |
| stall_turn | stall_turn[left_0.6Vs].pivot_radius_m | 4.76 | 3.48 | -1.28 (-26.9 %) |
| stall_turn | stall_turn[left_0.6Vs].pivot_radius_spans | 3.12 | 2.28 | -0.84 (-26.9 %) |
| stall_turn | stall_turn[left_0.6Vs].pivot_time_s | 3.4 | 3.09 | -0.31 (-9.1 %) |
| stall_turn | stall_turn[left_0.6Vs].torque_off_deg | 156.6 | 129.8 | -26.8 (-17.1 %) |
| stall_turn | stall_turn[left_0.6Vs].up_line_time_s | 3.1 | 3.05 | -0.05 (-1.6 %) |
| stall_turn | stall_turn[right_0.35Vs].height_gain_to_kick_m | 77.2 | 78.8 | +1.6 (+2.1 %) |
| stall_turn | stall_turn[right_0.35Vs].height_lost_top_to_level_m | 71.1 | 72.7 | +1.6 (+2.3 %) |
| stall_turn | stall_turn[right_0.35Vs].kick_speed_mps | 3.17 | 3.24 | +0.07 (+2.2 %) |
| stall_turn | stall_turn[right_0.35Vs].kick_speed_target_mps | 3.17 | 3.26 | +0.09 (+2.8 %) |
| stall_turn | stall_turn[right_0.35Vs].min_forward_speed_mps | -6.48 | -6.84 | -0.36 (-5.6 %) |
| stall_turn | stall_turn[right_0.35Vs].pitch_during_pivot_deg | 58.8 | 101.3 | +42.5 (+72.3 %) |
| stall_turn | stall_turn[right_0.35Vs].pivot_radius_m | 2.48 | 1.71 | -0.77 (-31.0 %) |
| stall_turn | stall_turn[right_0.35Vs].pivot_radius_spans | 1.63 | 1.12 | -0.51 (-31.3 %) |
| stall_turn | stall_turn[right_0.35Vs].pivot_time_s | 3.04 | 2.9 | -0.14 (-4.6 %) |
| stall_turn | stall_turn[right_0.35Vs].torque_off_deg | 134.7 | 130.0 | -4.7 (-3.5 %) |
| stall_turn | stall_turn[right_0.35Vs].up_line_time_s | 3.4 | 3.35 | -0.05 (-1.5 %) |
| stall_turn | stall_turn[right_0.6Vs].height_gain_to_kick_m | 76.0 | 77.5 | +1.5 (+2.0 %) |
| stall_turn | stall_turn[right_0.6Vs].height_lost_top_to_level_m | 152.8 | 161.5 | +8.7 (+5.7 %) |
| stall_turn | stall_turn[right_0.6Vs].kick_speed_mps | 5.43 | 5.57 | +0.14 (+2.6 %) |
| stall_turn | stall_turn[right_0.6Vs].kick_speed_target_mps | 5.44 | 5.59 | +0.15 (+2.8 %) |
| stall_turn | stall_turn[right_0.6Vs].min_forward_speed_mps | -3.91 | -4.02 | -0.11 (-2.8 %) |
| stall_turn | stall_turn[right_0.6Vs].pitch_during_pivot_deg | 87.5 | 119.8 | +32.3 (+36.9 %) |
| stall_turn | stall_turn[right_0.6Vs].pivot_radius_m | 43.17 | 44.91 | +1.74 (+4.0 %) |
| stall_turn | stall_turn[right_0.6Vs].pivot_radius_spans | 28.33 | 29.47 | +1.14 (+4.0 %) |
| stall_turn | stall_turn[right_0.6Vs].torque_off_deg | 145.1 | 131.3 | -13.8 (-9.5 %) |
| stall_turn | stall_turn[right_0.6Vs].up_line_time_s | 3.1 | 3.05 | -0.05 (-1.6 %) |
| stall_turning | stall_turning[30_left].altitude_lost_m | 26.2 | 23.3 | -2.9 (-11.1 %) |
| stall_turning | stall_turning[30_left].entry_speed_mps | 13.64 | 14.01 | +0.37 (+2.7 %) |
| stall_turning | stall_turning[30_left].max_bank_in_recovery_deg | 114.6 | 108.6 | -6 (-5.2 %) |
| stall_turning | stall_turning[30_left].ratio_to_vs_root_n | 1.043 | 1.057 | +0.014 (+1.3 %) |
| stall_turning | stall_turning[30_left].recovery_time_s | 2.79 | 2.62 | -0.17 (-6.1 %) |
| stall_turning | stall_turning[30_left].roll_off_in_1_s_deg | -64.4 | -58.3 | +6.1 (+9.5 %) |
| stall_turning | stall_turning[30_left].stall_alpha_deg | 17.2 | 16.8 | -0.4 (-2.3 %) |
| stall_turning | stall_turning[30_left].stall_speed_mps | 10.16 | 10.58 | +0.42 (+4.1 %) |
| stall_turning | stall_turning[30_left].stall_speed_vs | 1.121 | 1.137 | +0.016 (+1.4 %) |
| stall_turning | stall_turning[30_right].altitude_lost_m | 21.5 | 20.0 | -1.5 (-7.0 %) |
| stall_turning | stall_turning[30_right].entry_speed_mps | 13.64 | 14.01 | +0.37 (+2.7 %) |
| stall_turning | stall_turning[30_right].max_bank_in_recovery_deg | 106.9 | 102.4 | -4.5 (-4.2 %) |
| stall_turning | stall_turning[30_right].ratio_to_vs_root_n | 1.04 | 1.053 | +0.013 (+1.2 %) |
| stall_turning | stall_turning[30_right].recovery_time_s | 2.55 | 2.47 | -0.08 (-3.1 %) |
| stall_turning | stall_turning[30_right].roll_off_in_1_s_deg | 56.9 | 51.9 | -5 (-8.8 %) |
| stall_turning | stall_turning[30_right].stall_alpha_deg | 17.3 | 16.8 | -0.5 (-2.9 %) |
| stall_turning | stall_turning[30_right].stall_speed_mps | 10.13 | 10.54 | +0.41 (+4.0 %) |
| stall_turning | stall_turning[30_right].stall_speed_vs | 1.118 | 1.132 | +0.014 (+1.3 %) |
| stall_turning | stall_turning[45_left].altitude_lost_m | 25.0 | 23.3 | -1.7 (-6.8 %) |
| stall_turning | stall_turning[45_left].entry_speed_mps | 15.09 | 15.5 | +0.41 (+2.7 %) |
| stall_turning | stall_turning[45_left].max_bank_in_recovery_deg | 133.1 | 126.2 | -6.9 (-5.2 %) |
| stall_turning | stall_turning[45_left].ratio_to_vs_root_n | 1.049 | 1.063 | +0.014 (+1.3 %) |
| stall_turning | stall_turning[45_left].recovery_time_s | 2.47 | 2.41 | -0.06 (-2.4 %) |
| stall_turning | stall_turning[45_left].roll_off_in_1_s_deg | -67.7 | -61.1 | +6.6 (+9.7 %) |
| stall_turning | stall_turning[45_left].stall_alpha_deg | 16.8 | 16.3 | -0.5 (-3.0 %) |
| stall_turning | stall_turning[45_left].stall_speed_mps | 11.31 | 11.77 | +0.46 (+4.1 %) |
| stall_turning | stall_turning[45_left].stall_speed_vs | 1.248 | 1.264 | +0.016 (+1.3 %) |
| stall_turning | stall_turning[45_right].altitude_lost_m | 19.3 | 16.6 | -2.7 (-14.0 %) |
| stall_turning | stall_turning[45_right].entry_speed_mps | 15.09 | 15.5 | +0.41 (+2.7 %) |
| stall_turning | stall_turning[45_right].max_bank_in_recovery_deg | 119.1 | 112.0 | -7.1 (-6.0 %) |
| stall_turning | stall_turning[45_right].ratio_to_vs_root_n | 1.044 | 1.058 | +0.014 (+1.3 %) |
| stall_turning | stall_turning[45_right].recovery_time_s | 2.23 | 2.16 | -0.07 (-3.1 %) |
| stall_turning | stall_turning[45_right].roll_off_in_1_s_deg | 54.0 | 47.0 | -7 (-13.0 %) |
| stall_turning | stall_turning[45_right].stall_alpha_deg | 16.6 | 16.1 | -0.5 (-3.0 %) |
| stall_turning | stall_turning[45_right].stall_speed_mps | 11.25 | 11.71 | +0.46 (+4.1 %) |
| stall_turning | stall_turning[45_right].stall_speed_vs | 1.241 | 1.258 | +0.017 (+1.4 %) |
| takeoff | takeoff.ground_roll_m | 16.6 | 17.3 | +0.7 (+4.2 %) |
| takeoff | takeoff.liftoff_speed_mps | 15.65 | 16.0 | +0.35 (+2.2 %) |
| takeoff | takeoff.rudder_free_heading_change_3_s_deg | 0.4 | 0.2 | -0.2 (-50.0 %) |
| takeoff | takeoff.time_to_liftoff_s | 3.94 | 4.0 | +0.06 (+1.5 %) |
| throttle_response | throttle_response.rpm_idle_end | 8917 | 9018 | +101 (+1.1 %) |
| throttle_response | throttle_response.speed_gain_in_6_s_mps | 17.26 | 17.05 | -0.21 (-1.2 %) |
| throttle_response | throttle_response.spool_up_10_90_s | 3.463 | 3.533 | +0.07 (+2.0 %) |
| trim_sweep | trim_sweep.cruise_throttle_at_start_speed | 0.101 | None |  |
| trim_sweep | trim_sweep.first_untrimmable_mps | 37.0 | 11.0 | -26 (-70.3 %) |
| trim_sweep | trim_sweep.points | 22 | 1 | -21 (-95.5 %) |
| trim_sweep | trim_sweep.slowest_trim_mps | 15.0 | 10.0 | -5 (-33.3 %) |
| trim_sweep | trim_sweep[x0.50].alpha_deg | – | 11.22 | added/removed |
| trim_sweep | trim_sweep[x0.50].rpm | – | 4540 | added/removed |
| trim_sweep | trim_sweep[x0.50].speed_mps | – | 10.0 | added/removed |
| trim_sweep | trim_sweep[x0.50].stick_pitch | – | 0.492 | added/removed |
| trim_sweep | trim_sweep[x0.50].throttle | – | 0.001 | added/removed |
| trim_sweep | trim_sweep[x0.75].alpha_deg | 3.68 | – | added/removed |
| trim_sweep | trim_sweep[x0.75].rpm | 6122 | – | added/removed |
| trim_sweep | trim_sweep[x0.75].speed_mps | 15.0 | – | added/removed |
| trim_sweep | trim_sweep[x0.75].stick_pitch | 0.073 | – | added/removed |
| trim_sweep | trim_sweep[x0.75].throttle | 0.001 | – | added/removed |
| trim_sweep | trim_sweep[x0.80].alpha_deg | 3.08 | – | added/removed |
| trim_sweep | trim_sweep[x0.80].rpm | 6508 | – | added/removed |
| trim_sweep | trim_sweep[x0.80].speed_mps | 16.0 | – | added/removed |
| trim_sweep | trim_sweep[x0.80].stick_pitch | 0.062 | – | added/removed |
| trim_sweep | trim_sweep[x0.80].throttle | 0.015 | – | added/removed |
| trim_sweep | trim_sweep[x0.85].alpha_deg | 2.58 | – | added/removed |
| trim_sweep | trim_sweep[x0.85].rpm | 6901 | – | added/removed |
| trim_sweep | trim_sweep[x0.85].speed_mps | 17.0 | – | added/removed |
| trim_sweep | trim_sweep[x0.85].stick_pitch | 0.054 | – | added/removed |
| trim_sweep | trim_sweep[x0.85].throttle | 0.029 | – | added/removed |
| trim_sweep | trim_sweep[x0.90].alpha_deg | 2.15 | – | added/removed |
| trim_sweep | trim_sweep[x0.90].rpm | 7299 | – | added/removed |
| trim_sweep | trim_sweep[x0.90].speed_mps | 18.0 | – | added/removed |
| trim_sweep | trim_sweep[x0.90].stick_pitch | 0.047 | – | added/removed |
| trim_sweep | trim_sweep[x0.90].throttle | 0.051 | – | added/removed |
| trim_sweep | trim_sweep[x0.95].alpha_deg | 1.8 | – | added/removed |
| trim_sweep | trim_sweep[x0.95].rpm | 7701 | – | added/removed |
| trim_sweep | trim_sweep[x0.95].speed_mps | 19.0 | – | added/removed |
| trim_sweep | trim_sweep[x0.95].stick_pitch | 0.041 | – | added/removed |
| trim_sweep | trim_sweep[x0.95].throttle | 0.076 | – | added/removed |
| trim_sweep | trim_sweep[x1.00].alpha_deg | 1.49 | – | added/removed |
| trim_sweep | trim_sweep[x1.00].rpm | 8106 | – | added/removed |
| trim_sweep | trim_sweep[x1.00].speed_mps | 20.0 | – | added/removed |
| trim_sweep | trim_sweep[x1.00].stick_pitch | 0.037 | – | added/removed |
| trim_sweep | trim_sweep[x1.00].throttle | 0.101 | – | added/removed |
| trim_sweep | trim_sweep[x1.05].alpha_deg | 1.23 | – | added/removed |
| trim_sweep | trim_sweep[x1.05].rpm | 8513 | – | added/removed |
| trim_sweep | trim_sweep[x1.05].speed_mps | 21.0 | – | added/removed |
| trim_sweep | trim_sweep[x1.05].stick_pitch | 0.033 | – | added/removed |
| trim_sweep | trim_sweep[x1.05].throttle | 0.127 | – | added/removed |
| trim_sweep | trim_sweep[x1.10].alpha_deg | 1.0 | – | added/removed |
| trim_sweep | trim_sweep[x1.10].rpm | 8921 | – | added/removed |
| trim_sweep | trim_sweep[x1.10].speed_mps | 22.0 | – | added/removed |
| trim_sweep | trim_sweep[x1.10].stick_pitch | 0.029 | – | added/removed |
| trim_sweep | trim_sweep[x1.10].throttle | 0.153 | – | added/removed |
| trim_sweep | trim_sweep[x1.15].alpha_deg | 0.81 | – | added/removed |
| trim_sweep | trim_sweep[x1.15].rpm | 9331 | – | added/removed |
| trim_sweep | trim_sweep[x1.15].speed_mps | 23.0 | – | added/removed |
| trim_sweep | trim_sweep[x1.15].stick_pitch | 0.027 | – | added/removed |
| trim_sweep | trim_sweep[x1.15].throttle | 0.178 | – | added/removed |
| trim_sweep | trim_sweep[x1.20].alpha_deg | 0.63 | – | added/removed |
| trim_sweep | trim_sweep[x1.20].rpm | 9741 | – | added/removed |
| trim_sweep | trim_sweep[x1.20].speed_mps | 24.0 | – | added/removed |
| trim_sweep | trim_sweep[x1.20].stick_pitch | 0.024 | – | added/removed |
| trim_sweep | trim_sweep[x1.20].throttle | 0.203 | – | added/removed |
| trim_sweep | trim_sweep[x1.25].alpha_deg | 0.48 | – | added/removed |
| trim_sweep | trim_sweep[x1.25].rpm | 10152 | – | added/removed |
| trim_sweep | trim_sweep[x1.25].speed_mps | 25.0 | – | added/removed |
| trim_sweep | trim_sweep[x1.25].stick_pitch | 0.022 | – | added/removed |
| trim_sweep | trim_sweep[x1.25].throttle | 0.233 | – | added/removed |
| trim_sweep | trim_sweep[x1.30].alpha_deg | 0.34 | – | added/removed |
| trim_sweep | trim_sweep[x1.30].rpm | 10563 | – | added/removed |
| trim_sweep | trim_sweep[x1.30].speed_mps | 26.0 | – | added/removed |
| trim_sweep | trim_sweep[x1.30].stick_pitch | 0.02 | – | added/removed |
| trim_sweep | trim_sweep[x1.30].throttle | 0.272 | – | added/removed |
| trim_sweep | trim_sweep[x1.35].alpha_deg | 0.22 | – | added/removed |
| trim_sweep | trim_sweep[x1.35].rpm | 10975 | – | added/removed |
| trim_sweep | trim_sweep[x1.35].speed_mps | 27.0 | – | added/removed |
| trim_sweep | trim_sweep[x1.35].stick_pitch | 0.019 | – | added/removed |
| trim_sweep | trim_sweep[x1.35].throttle | 0.312 | – | added/removed |
| trim_sweep | trim_sweep[x1.40].alpha_deg | 0.11 | – | added/removed |
| trim_sweep | trim_sweep[x1.40].rpm | 11387 | – | added/removed |
| trim_sweep | trim_sweep[x1.40].speed_mps | 28.0 | – | added/removed |
| trim_sweep | trim_sweep[x1.40].stick_pitch | 0.017 | – | added/removed |
| trim_sweep | trim_sweep[x1.40].throttle | 0.352 | – | added/removed |
| trim_sweep | trim_sweep[x1.45].alpha_deg | 0.02 | – | added/removed |
| trim_sweep | trim_sweep[x1.45].rpm | 11799 | – | added/removed |
| trim_sweep | trim_sweep[x1.45].speed_mps | 29.0 | – | added/removed |
| trim_sweep | trim_sweep[x1.45].stick_pitch | 0.016 | – | added/removed |
| trim_sweep | trim_sweep[x1.45].throttle | 0.393 | – | added/removed |
| trim_sweep | trim_sweep[x1.50].alpha_deg | -0.07 | – | added/removed |
| trim_sweep | trim_sweep[x1.50].rpm | 12211 | – | added/removed |
| trim_sweep | trim_sweep[x1.50].speed_mps | 30.0 | – | added/removed |
| trim_sweep | trim_sweep[x1.50].stick_pitch | 0.015 | – | added/removed |
| trim_sweep | trim_sweep[x1.50].throttle | 0.435 | – | added/removed |
| trim_sweep | trim_sweep[x1.55].alpha_deg | -0.15 | – | added/removed |
| trim_sweep | trim_sweep[x1.55].rpm | 12623 | – | added/removed |
| trim_sweep | trim_sweep[x1.55].speed_mps | 31.0 | – | added/removed |
| trim_sweep | trim_sweep[x1.55].stick_pitch | 0.014 | – | added/removed |
| trim_sweep | trim_sweep[x1.55].throttle | 0.477 | – | added/removed |
| trim_sweep | trim_sweep[x1.60].alpha_deg | -0.22 | – | added/removed |
| trim_sweep | trim_sweep[x1.60].rpm | 13036 | – | added/removed |
| trim_sweep | trim_sweep[x1.60].speed_mps | 32.0 | – | added/removed |
| trim_sweep | trim_sweep[x1.60].stick_pitch | 0.013 | – | added/removed |
| trim_sweep | trim_sweep[x1.60].throttle | 0.521 | – | added/removed |
| trim_sweep | trim_sweep[x1.65].alpha_deg | -0.29 | – | added/removed |
| trim_sweep | trim_sweep[x1.65].rpm | 13448 | – | added/removed |
| trim_sweep | trim_sweep[x1.65].speed_mps | 33.0 | – | added/removed |
| trim_sweep | trim_sweep[x1.65].stick_pitch | 0.012 | – | added/removed |
| trim_sweep | trim_sweep[x1.65].throttle | 0.583 | – | added/removed |
| trim_sweep | trim_sweep[x1.70].alpha_deg | -0.35 | – | added/removed |
| trim_sweep | trim_sweep[x1.70].rpm | 13861 | – | added/removed |
| trim_sweep | trim_sweep[x1.70].speed_mps | 34.0 | – | added/removed |
| trim_sweep | trim_sweep[x1.70].stick_pitch | 0.012 | – | added/removed |
| trim_sweep | trim_sweep[x1.70].throttle | 0.647 | – | added/removed |
| trim_sweep | trim_sweep[x1.75].alpha_deg | -0.4 | – | added/removed |
| trim_sweep | trim_sweep[x1.75].rpm | 14273 | – | added/removed |
| trim_sweep | trim_sweep[x1.75].speed_mps | 35.0 | – | added/removed |
| trim_sweep | trim_sweep[x1.75].stick_pitch | 0.011 | – | added/removed |
| trim_sweep | trim_sweep[x1.75].throttle | 0.714 | – | added/removed |
| trim_sweep | trim_sweep[x1.80].alpha_deg | -0.45 | – | added/removed |
| trim_sweep | trim_sweep[x1.80].rpm | 14686 | – | added/removed |
| trim_sweep | trim_sweep[x1.80].speed_mps | 36.0 | – | added/removed |
| trim_sweep | trim_sweep[x1.80].stick_pitch | 0.01 | – | added/removed |
| trim_sweep | trim_sweep[x1.80].throttle | 0.783 | – | added/removed |
| turn_60 | turn_60[left].vertical_speed_mps | -0.06 | -0.07 | -0.01 (-16.7 %) |
| vmax | vmax.height_error_end_m | 0.38 | 0.33 | -0.05 (-13.2 %) |
| vmax | vmax.height_error_run_m | 0.41 | 0.63 | +0.22 (+53.7 %) |
| vmax | vmax.initial_acceleration_mps2 | 3.48 | 3.35 | -0.13 (-3.7 %) |
| vmax | vmax.time_plus_10_mps_s | 2.28 | 2.36 | +0.08 (+3.5 %) |
| vmax | vmax.time_plus_5_mps_s | 1.28 | 1.31 | +0.03 (+2.3 %) |
| vmax | vmax.time_to_90_percent_s | 5.5 | 5.75 | +0.25 (+4.5 %) |

## Jensen Das Ugly Stik 60 · MAX-61FX — 495 change(s)

Aircraft data changed between the runs.

| Test | Value | Baseline | Candidate | Change |
| --- | --- | --- | --- | --- |
| aero_sweep | aero_sweep.knife_edge_side_force_margin | 0.633 | 0.603 | -0.03 (-4.7 %) |
| aero_sweep | aero_sweep.trim_alpha_deg | 1.77 | 1.96 | +0.19 (+10.7 %) |
| aero_sweep | aero_sweep[alpha_05].cm | -0.0287 | -0.0653 | -0.0366 (-127.5 %) |
| aero_sweep | aero_sweep[alpha_05].cm_local | -0.0354 | -0.0719 | -0.0365 (-103.1 %) |
| aero_sweep | aero_sweep[alpha_05].cm_oracle | -0.0287 | -0.0653 | -0.0366 (-127.5 %) |
| aero_sweep | aero_sweep[alpha_10].cm | -0.073 | -0.1379 | -0.0649 (-88.9 %) |
| aero_sweep | aero_sweep[alpha_10].cm_local | -0.0835 | -0.1485 | -0.065 (-77.8 %) |
| aero_sweep | aero_sweep[alpha_10].cm_oracle | -0.0633 | -0.1283 | -0.065 (-102.7 %) |
| aero_sweep | aero_sweep[alpha_15].cm | -0.2707 | -0.3289 | -0.0582 (-21.5 %) |
| aero_sweep | aero_sweep[alpha_15].cm_local | -0.2707 | -0.3289 | -0.0582 (-21.5 %) |
| aero_sweep | aero_sweep[alpha_15].cm_oracle | -0.1359 | -0.1962 | -0.0603 (-44.4 %) |
| aero_sweep | aero_sweep[alpha_20].cm | -0.2572 | -0.2975 | -0.0403 (-15.7 %) |
| aero_sweep | aero_sweep[alpha_20].cm_local | -0.2572 | -0.2975 | -0.0403 (-15.7 %) |
| aero_sweep | aero_sweep[alpha_20].cm_oracle | -0.2148 | -0.2454 | -0.0306 (-14.2 %) |
| aero_sweep | aero_sweep[alpha_30].cm | -0.1991 | -0.2524 | -0.0533 (-26.8 %) |
| aero_sweep | aero_sweep[alpha_30].cm_local | -0.1991 | -0.2524 | -0.0533 (-26.8 %) |
| aero_sweep | aero_sweep[alpha_30].cm_oracle | -0.3062 | -0.3509 | -0.0447 (-14.6 %) |
| aero_sweep | aero_sweep[alpha_m05].cm | 0.0088 | 0.0301 | +0.0213 (+242.0 %) |
| aero_sweep | aero_sweep[alpha_m05].cm_local | 0.0325 | 0.0538 | +0.0213 (+65.5 %) |
| aero_sweep | aero_sweep[alpha_m05].cm_oracle | 0.0088 | 0.0301 | +0.0213 (+242.0 %) |
| aero_sweep | aero_sweep[alpha_m10].cm | 0.043 | 0.0933 | +0.0503 (+117.0 %) |
| aero_sweep | aero_sweep[alpha_m10].cm_local | 0.052 | 0.1024 | +0.0504 (+96.9 %) |
| aero_sweep | aero_sweep[alpha_m10].cm_oracle | 0.0123 | 0.0626 | +0.0503 (+408.9 %) |
| climb | climb.best.pitch_deg | 74.5 | 72.1 | -2.4 (-3.2 %) |
| climb | climb.best.speed_mps | 21.61 | 20.94 | -0.67 (-3.1 %) |
| climb | climb.best.vertical_speed_mps | 20.9 | 19.99 | -0.91 (-4.4 %) |
| climb | climb[1.3Vs].rpm | 14355 | 14186 | -169 (-1.2 %) |
| climb | climb[1.3Vs].speed_mps | 21.61 | 20.64 | -0.97 (-4.5 %) |
| climb | climb[1.3Vs].vertical_speed_mps | 20.89 | 19.95 | -0.94 (-4.5 %) |
| climb | climb[1.6Vs].rpm | 14355 | 14186 | -169 (-1.2 %) |
| climb | climb[1.6Vs].speed_mps | 21.61 | 20.65 | -0.96 (-4.4 %) |
| climb | climb[1.6Vs].vertical_speed_mps | 20.89 | 19.95 | -0.94 (-4.5 %) |
| climb | climb[2.0Vs].pitch_deg | 74.5 | 72.1 | -2.4 (-3.2 %) |
| climb | climb[2.0Vs].speed_mps | 21.61 | 20.94 | -0.67 (-3.1 %) |
| climb | climb[2.0Vs].vertical_speed_mps | 20.9 | 19.99 | -0.91 (-4.4 %) |
| dead_stick_landing | dead_stick_landing.approach_max_speed_mps | 19.67 | 20.15 | +0.48 (+2.4 %) |
| dead_stick_landing | dead_stick_landing.approach_min_speed_mps | 14.18 | 14.55 | +0.37 (+2.6 %) |
| dead_stick_landing | dead_stick_landing.flare_height_m | 2.0 | 2.06 | +0.06 (+3.0 %) |
| dead_stick_landing | dead_stick_landing.glide_sink_mps | 2.0 | 2.06 | +0.06 (+3.0 %) |
| dead_stick_landing | dead_stick_landing.glide_speed_mps | 13.25 | 13.57 | +0.32 (+2.4 %) |
| dead_stick_landing | dead_stick_landing.rollout_m | 65.4 | 64.7 | -0.7 (-1.1 %) |
| dead_stick_landing | dead_stick_landing.touchdown_past_aim_m | 21.7 | 23.4 | +1.7 (+7.8 %) |
| dead_stick_landing | dead_stick_landing.touchdown_past_threshold_m | 31.7 | 33.4 | +1.7 (+5.4 %) |
| dead_stick_landing | dead_stick_landing.touchdown_pitch_deg | 2.1 | 2.2 | +0.1 (+4.8 %) |
| dead_stick_landing | dead_stick_landing.touchdown_speed_mps | 14.17 | 14.55 | +0.38 (+2.7 %) |
| engine_cut_climb | engine_cut_climb[delay_1s].alpha_margin_to_stall_deg | -11.7 | -8.7 | +3 (+25.6 %) |
| engine_cut_climb | engine_cut_climb[delay_1s].climb_speed_mps | 15.21 | 15.59 | +0.38 (+2.5 %) |
| engine_cut_climb | engine_cut_climb[delay_1s].glide_speed_mps | 13.31 | 13.64 | +0.33 (+2.5 %) |
| engine_cut_climb | engine_cut_climb[delay_1s].height_change_10_s_m | -93.1 | -101.8 | -8.7 (-9.3 %) |
| engine_cut_climb | engine_cut_climb[delay_1s].height_gained_after_cut_m | 28.3 | 27.9 | -0.4 (-1.4 %) |
| engine_cut_climb | engine_cut_climb[delay_1s].max_alpha_deg | 23.8 | 20.8 | -3 (-12.6 %) |
| engine_cut_climb | engine_cut_climb[delay_1s].min_speed_mps | 6.69 | 6.51 | -0.18 (-2.7 %) |
| engine_cut_climb | engine_cut_climb[delay_1s].min_speed_vs | 0.7 | 0.67 | -0.03 (-4.3 %) |
| engine_cut_climb | engine_cut_climb[delay_1s].rpm_10_s_after_cut | 6912 | 8515 | +1603 (+23.2 %) |
| engine_cut_climb | engine_cut_climb[delay_1s].speed_after_reaction_mps | 15.01 | 14.71 | -0.3 (-2.0 %) |
| engine_cut_climb | engine_cut_climb[delay_1s].speed_at_cut_mps | 23.46 | 23.08 | -0.38 (-1.6 %) |
| engine_cut_climb | engine_cut_climb[delay_1s].time_below_1_2vs_s | 2.08 | 2.21 | +0.13 (+6.2 %) |
| engine_cut_climb | engine_cut_climb[delay_2s].alpha_margin_to_stall_deg | -112.7 | -108.6 | +4.1 (+3.6 %) |
| engine_cut_climb | engine_cut_climb[delay_2s].climb_speed_mps | 15.21 | 15.59 | +0.38 (+2.5 %) |
| engine_cut_climb | engine_cut_climb[delay_2s].glide_speed_mps | 13.31 | 13.64 | +0.33 (+2.5 %) |
| engine_cut_climb | engine_cut_climb[delay_2s].height_change_10_s_m | -78.5 | -86.9 | -8.4 (-10.7 %) |
| engine_cut_climb | engine_cut_climb[delay_2s].height_gained_after_cut_m | 31.4 | 30.5 | -0.9 (-2.9 %) |
| engine_cut_climb | engine_cut_climb[delay_2s].max_alpha_deg | 124.8 | 120.8 | -4 (-3.2 %) |
| engine_cut_climb | engine_cut_climb[delay_2s].min_speed_mps | 1.4 | 1.5 | +0.1 (+7.1 %) |
| engine_cut_climb | engine_cut_climb[delay_2s].rpm_10_s_after_cut | 7326 | 7991 | +665 (+9.1 %) |
| engine_cut_climb | engine_cut_climb[delay_2s].speed_after_reaction_mps | 6.01 | 5.75 | -0.26 (-4.3 %) |
| engine_cut_climb | engine_cut_climb[delay_2s].speed_at_cut_mps | 23.46 | 23.08 | -0.38 (-1.6 %) |
| engine_cut_climb | engine_cut_climb[delay_2s].time_below_1_2vs_s | 3.22 | 3.1 | -0.12 (-3.7 %) |
| glide | glide.best.path_angle_deg | 3.9 | 3.5 | -0.4 (-10.3 %) |
| glide | glide.best.pitch_deg | 10.5 | 10.2 | -0.3 (-2.9 %) |
| glide | glide.best.rpm | 6557 | 6668 | +111 (+1.7 %) |
| glide | glide.best.speed_mps | 12.41 | 12.71 | +0.3 (+2.4 %) |
| glide | glide.best.vertical_speed_mps | 0.84 | 0.77 | -0.07 (-8.3 %) |
| glide | glide[1.3Vs].path_angle_deg | 3.9 | 3.5 | -0.4 (-10.3 %) |
| glide | glide[1.3Vs].pitch_deg | 10.5 | 10.2 | -0.3 (-2.9 %) |
| glide | glide[1.3Vs].rpm | 6557 | 6668 | +111 (+1.7 %) |
| glide | glide[1.3Vs].speed_mps | 12.41 | 12.71 | +0.3 (+2.4 %) |
| glide | glide[1.3Vs].vertical_speed_mps | 0.84 | 0.77 | -0.07 (-8.3 %) |
| glide | glide[1.6Vs].path_angle_deg | 3.1 | 2.6 | -0.5 (-16.1 %) |
| glide | glide[1.6Vs].pitch_deg | 7.1 | 6.6 | -0.5 (-7.0 %) |
| glide | glide[1.6Vs].rpm | 7536 | 7662 | +126 (+1.7 %) |
| glide | glide[1.6Vs].speed_mps | 15.23 | 15.61 | +0.38 (+2.5 %) |
| glide | glide[1.6Vs].vertical_speed_mps | 0.82 | 0.71 | -0.11 (-13.4 %) |
| glide | glide[2.0Vs].glide_ratio | – | 204.65 | added/removed |
| glide | glide[2.0Vs].path_angle_deg | 0.2 | -0.3 | -0.5 (-250.0 %) |
| glide | glide[2.0Vs].pitch_deg | 2.3 | 1.8 | -0.5 (-21.7 %) |
| glide | glide[2.0Vs].rpm | 8822 | 8983 | +161 (+1.8 %) |
| glide | glide[2.0Vs].speed_mps | 19.02 | 19.48 | +0.46 (+2.4 %) |
| glide | glide[2.0Vs].vertical_speed_mps | 0.08 | -0.1 | -0.18 (-225.0 %) |
| glide_turn | glide_turn.least_height_lost_180_m | 12.3 | 13.2 | +0.9 (+7.3 %) |
| glide_turn | glide_turn[30deg].height_lost_180_m | 13.9 | 14.6 | +0.7 (+5.0 %) |
| glide_turn | glide_turn[30deg].height_lost_360_m | 29.3 | 30.8 | +1.5 (+5.1 %) |
| glide_turn | glide_turn[30deg].radius_m | 29.6 | 31.0 | +1.4 (+4.7 %) |
| glide_turn | glide_turn[30deg].speed_in_turn_mps | 13.17 | 13.5 | +0.33 (+2.5 %) |
| glide_turn | glide_turn[30deg].speed_target_mps | 13.28 | 13.61 | +0.33 (+2.5 %) |
| glide_turn | glide_turn[30deg].straight_sink_mps | -0.09 | -0.12 | -0.03 (-33.3 %) |
| glide_turn | glide_turn[30deg].time_to_180_s | 6.96 | 7.12 | +0.16 (+2.3 %) |
| glide_turn | glide_turn[30deg].time_to_360_s | 14.02 | 14.34 | +0.32 (+2.3 %) |
| glide_turn | glide_turn[30deg].turn_sink_mps | 2.18 | 2.25 | +0.07 (+3.2 %) |
| glide_turn | glide_turn[45deg].height_lost_180_m | 12.3 | 13.2 | +0.9 (+7.3 %) |
| glide_turn | glide_turn[45deg].height_lost_360_m | 24.6 | 26.2 | +1.6 (+6.5 %) |
| glide_turn | glide_turn[45deg].radius_m | 19.8 | 20.9 | +1.1 (+5.6 %) |
| glide_turn | glide_turn[45deg].speed_in_turn_mps | 14.07 | 14.49 | +0.42 (+3.0 %) |
| glide_turn | glide_turn[45deg].speed_target_mps | 14.7 | 15.06 | +0.36 (+2.4 %) |
| glide_turn | glide_turn[45deg].straight_sink_mps | 0.47 | 0.76 | +0.29 (+61.7 %) |
| glide_turn | glide_turn[45deg].time_to_180_s | 4.73 | 4.88 | +0.15 (+3.2 %) |
| glide_turn | glide_turn[45deg].time_to_360_s | 9.15 | 9.42 | +0.27 (+3.0 %) |
| glide_turn | glide_turn[45deg].turn_sink_mps | 2.81 | 2.87 | +0.06 (+2.1 %) |
| glide_turn | glide_turn[60deg].height_lost_180_m | 16.5 | 17.9 | +1.4 (+8.5 %) |
| glide_turn | glide_turn[60deg].height_lost_360_m | 29.3 | 31.4 | +2.1 (+7.2 %) |
| glide_turn | glide_turn[60deg].radius_m | 16.7 | 17.8 | +1.1 (+6.6 %) |
| glide_turn | glide_turn[60deg].speed_in_turn_mps | 16.67 | 17.21 | +0.54 (+3.2 %) |
| glide_turn | glide_turn[60deg].speed_target_mps | 17.48 | 17.91 | +0.43 (+2.5 %) |
| glide_turn | glide_turn[60deg].straight_sink_mps | 1.84 | 2.27 | +0.43 (+23.4 %) |
| glide_turn | glide_turn[60deg].time_to_180_s | 3.66 | 3.76 | +0.1 (+2.7 %) |
| glide_turn | glide_turn[60deg].time_to_360_s | 6.82 | 7.02 | +0.2 (+2.9 %) |
| glide_turn | glide_turn[60deg].turn_sink_mps | 4.04 | 4.13 | +0.09 (+2.2 %) |
| go_around | go_around[fast].climb_rate_after_15_m_mps | 20.6 | 20.37 | -0.23 (-1.1 %) |
| go_around | go_around[fast].max_bank_deg | 1.8 | 1.7 | -0.1 (-5.6 %) |
| go_around | go_around[fast].max_heading_error_deg | 0.9 | 0.8 | -0.1 (-11.1 %) |
| go_around | go_around[fast].time_to_15_m_s | 1.44 | 1.48 | +0.04 (+2.8 %) |
| go_around | go_around[slow].max_bank_deg | 1.7 | 1.8 | +0.1 (+5.9 %) |
| go_around | go_around[slow].max_heading_error_deg | 1.0 | 0.8 | -0.2 (-20.0 %) |
| go_around | go_around[slow].time_to_15_m_s | 1.63 | 1.67 | +0.04 (+2.5 %) |
| hands_off | hands_off.bank_10_s_deg | 2.4 | 8.1 | +5.7 (+237.5 %) |
| hands_off | hands_off.bank_30_s_deg | 5.0 | 10.2 | +5.2 (+104.0 %) |
| hands_off | hands_off.heading_change_10_s_deg | 26.4 | 34.5 | +8.1 (+30.7 %) |
| hands_off | hands_off.heading_change_30_s_deg | 80.8 | 127.8 | +47 (+58.2 %) |
| hands_off | hands_off.height_change_10_s_m | 1.13 | -5.25 | -6.38 (-564.6 %) |
| hands_off | hands_off.phugoid_period_s | None | 13.65 |  |
| hands_off | hands_off.speed_change_10_s_mps | 1.41 | 2.39 | +0.98 (+69.5 %) |
| hands_off | hands_off.speed_change_30_s_mps | 0.63 | 0.34 | -0.29 (-46.0 %) |
| immelmann | immelmann.half_loop_time_s | 2.49 | 2.75 | +0.26 (+10.4 %) |
| immelmann | immelmann.half_roll_time_s | 0.69 | 0.7 | +0.01 (+1.4 %) |
| immelmann | immelmann.heading_error_deg | -4.1 | -3.5 | +0.6 (+14.6 %) |
| immelmann | immelmann.height_gain_m | 39.2 | 43.6 | +4.4 (+11.2 %) |
| immelmann | immelmann.max_load_factor_g | 4.38 | 3.99 | -0.39 (-8.9 %) |
| immelmann | immelmann.max_sideslip_deg | 4.1 | 3.9 | -0.2 (-4.9 %) |
| immelmann | immelmann.top_speed_mps | 28.39 | 28.01 | -0.38 (-1.3 %) |
| immelmann | immelmann.top_speed_vs | 2.99 | 2.88 | -0.11 (-3.7 %) |
| inverted | inverted.alpha_deg | -3.7 | -3.8 | -0.1 (-2.7 %) |
| inverted | inverted.elevator_servo | -0.021 | -0.071 | -0.05 (-238.1 %) |
| inverted | inverted.elevator_stick | -0.021 | -0.071 | -0.05 (-238.1 %) |
| inverted | inverted.vertical_speed_mps | 0.04 | 0.01 | -0.03 (-75.0 %) |
| inverted_speeds | inverted_speeds[0.6Vmax].alpha_deg | -3.7 | -3.8 | -0.1 (-2.7 %) |
| inverted_speeds | inverted_speeds[0.6Vmax].elevator_servo | -0.021 | -0.071 | -0.05 (-238.1 %) |
| inverted_speeds | inverted_speeds[0.6Vmax].elevator_stick | -0.021 | -0.071 | -0.05 (-238.1 %) |
| inverted_speeds | inverted_speeds[0.6Vmax].vertical_speed_mps | 0.04 | 0.01 | -0.03 (-75.0 %) |
| inverted_speeds | inverted_speeds[0.8Vmax].alpha_deg | -2.6 | -2.7 | -0.1 (-3.8 %) |
| inverted_speeds | inverted_speeds[0.8Vmax].elevator_servo | -0.012 | -0.041 | -0.029 (-241.7 %) |
| inverted_speeds | inverted_speeds[0.8Vmax].elevator_stick | -0.012 | -0.041 | -0.029 (-241.7 %) |
| inverted_speeds | inverted_speeds[start].alpha_deg | -4.4 | -4.6 | -0.2 (-4.5 %) |
| inverted_speeds | inverted_speeds[start].elevator_servo | -0.026 | -0.091 | -0.065 (-250.0 %) |
| inverted_speeds | inverted_speeds[start].elevator_stick | -0.026 | -0.091 | -0.065 (-250.0 %) |
| inverted_speeds | inverted_speeds[start].vertical_speed_mps | 0.03 | -0.02 | -0.05 (-166.7 %) |
| inverted_turn | inverted_turn[left].alpha_deg | -4.6 | -4.8 | -0.2 (-4.3 %) |
| inverted_turn | inverted_turn[left].elevator_stick | -0.091 | -0.162 | -0.071 (-78.0 %) |
| inverted_turn | inverted_turn[left].vertical_speed_mps | 0.02 | -0.01 | -0.03 (-150.0 %) |
| inverted_turn | inverted_turn[right].alpha_deg | -4.6 | -4.8 | -0.2 (-4.3 %) |
| inverted_turn | inverted_turn[right].elevator_stick | -0.071 | -0.141 | -0.07 (-98.6 %) |
| inverted_turn | inverted_turn[right].vertical_speed_mps | 0.02 | 0.0 | -0.02 (-100.0 %) |
| knife_edge | knife_edge[left_100pct].aileron_stick | -0.183 | -0.196 | -0.013 (-7.1 %) |
| knife_edge | knife_edge[left_100pct].height_change_10_s_m | -7.6 | -8.3 | -0.7 (-9.2 %) |
| knife_edge | knife_edge[left_100pct].pitch_attitude_deg | 8.7 | 9.4 | +0.7 (+8.0 %) |
| knife_edge | knife_edge[left_100pct].rudder_stick | 0.203 | 0.258 | +0.055 (+27.1 %) |
| knife_edge | knife_edge[left_100pct].sideslip_deg | -9.0 | -9.7 | -0.7 (-7.8 %) |
| knife_edge | knife_edge[left_100pct].vertical_speed_mps | -0.13 | -0.16 | -0.03 (-23.1 %) |
| knife_edge | knife_edge[left_50pct].height_change_10_s_m | -76.6 | -89.1 | -12.5 (-16.3 %) |
| knife_edge | knife_edge[left_50pct].pitch_attitude_deg | 3.0 | 0.5 | -2.5 (-83.3 %) |
| knife_edge | knife_edge[left_50pct].speed_after_5_s_mps | 33.98 | 34.66 | +0.68 (+2.0 %) |
| knife_edge | knife_edge[left_50pct].speed_end_mps | 37.38 | 38.11 | +0.73 (+2.0 %) |
| knife_edge | knife_edge[left_50pct].vertical_speed_mps | -11.19 | -12.85 | -1.66 (-14.8 %) |
| knife_edge | knife_edge[right_100pct].aileron_stick | 0.221 | 0.234 | +0.013 (+5.9 %) |
| knife_edge | knife_edge[right_100pct].height_change_10_s_m | -7.4 | -8.1 | -0.7 (-9.5 %) |
| knife_edge | knife_edge[right_100pct].pitch_attitude_deg | 8.5 | 9.2 | +0.7 (+8.2 %) |
| knife_edge | knife_edge[right_100pct].rudder_stick | -0.168 | -0.221 | -0.053 (-31.5 %) |
| knife_edge | knife_edge[right_100pct].sideslip_deg | 8.7 | 9.5 | +0.8 (+9.2 %) |
| knife_edge | knife_edge[right_100pct].vertical_speed_mps | -0.13 | -0.17 | -0.04 (-30.8 %) |
| knife_edge | knife_edge[right_50pct].height_change_10_s_m | -78.0 | -88.9 | -10.9 (-14.0 %) |
| knife_edge | knife_edge[right_50pct].pitch_attitude_deg | 3.0 | 0.7 | -2.3 (-76.7 %) |
| knife_edge | knife_edge[right_50pct].speed_after_5_s_mps | 34.19 | 34.74 | +0.55 (+1.6 %) |
| knife_edge | knife_edge[right_50pct].speed_end_mps | 37.26 | 37.93 | +0.67 (+1.8 %) |
| knife_edge | knife_edge[right_50pct].vertical_speed_mps | -11.18 | -12.64 | -1.46 (-13.1 %) |
| knife_edge_full_rudder | knife_edge_full_rudder[left_100pct].height_change_10_s_m | -13.7 | -26.7 | -13 (-94.9 %) |
| knife_edge_full_rudder | knife_edge_full_rudder[left_100pct].pitch_attitude_deg | 20.0 | 17.0 | -3 (-15.0 %) |
| knife_edge_full_rudder | knife_edge_full_rudder[left_100pct].speed_end_mps | 37.65 | 38.31 | +0.66 (+1.8 %) |
| knife_edge_full_rudder | knife_edge_full_rudder[left_100pct].vertical_speed_mps | -0.54 | -2.49 | -1.95 (-361.1 %) |
| knife_edge_full_rudder | knife_edge_full_rudder[left_50pct].height_change_10_s_m | -98.5 | -105.7 | -7.2 (-7.3 %) |
| knife_edge_full_rudder | knife_edge_full_rudder[left_50pct].pitch_attitude_deg | 0.0 | -1.6 | -1.6 |
| knife_edge_full_rudder | knife_edge_full_rudder[left_50pct].speed_end_mps | 38.08 | 38.59 | +0.51 (+1.3 %) |
| knife_edge_full_rudder | knife_edge_full_rudder[left_50pct].vertical_speed_mps | -13.36 | -14.4 | -1.04 (-7.8 %) |
| knife_edge_full_rudder | knife_edge_full_rudder[right_100pct].height_change_10_s_m | -3.4 | -17.7 | -14.3 (-420.6 %) |
| knife_edge_full_rudder | knife_edge_full_rudder[right_100pct].pitch_attitude_deg | 21.8 | 18.5 | -3.3 (-15.1 %) |
| knife_edge_full_rudder | knife_edge_full_rudder[right_100pct].speed_end_mps | 37.18 | 37.89 | +0.71 (+1.9 %) |
| knife_edge_full_rudder | knife_edge_full_rudder[right_100pct].vertical_speed_mps | 0.62 | -1.46 | -2.08 (-335.5 %) |
| knife_edge_full_rudder | knife_edge_full_rudder[right_50pct].height_change_10_s_m | -91.9 | -99.8 | -7.9 (-8.6 %) |
| knife_edge_full_rudder | knife_edge_full_rudder[right_50pct].pitch_attitude_deg | 0.8 | -0.8 | -1.6 (-200.0 %) |
| knife_edge_full_rudder | knife_edge_full_rudder[right_50pct].speed_end_mps | 37.75 | 38.3 | +0.55 (+1.5 %) |
| knife_edge_full_rudder | knife_edge_full_rudder[right_50pct].vertical_speed_mps | -12.7 | -13.79 | -1.09 (-8.6 %) |
| landing | landing.approach_speed_mps | 12.36 | 12.66 | +0.3 (+2.4 %) |
| landing | landing.flare_height_m | 0.864321775054442 | 0.885565678203695 | +0.02124 (+2.5 %) |
| landing | landing.max_heading_error_deg | 0.4 | 0.3 | -0.1 (-25.0 %) |
| landing | landing.rollout_m | 117.0 | 107.1 | -9.9 (-8.5 %) |
| landing | landing.rollout_time_s | 10.3 | 9.21 | -1.09 (-10.6 %) |
| landing | landing.touchdown_past_threshold_m | 58.2 | 57.6 | -0.6 (-1.0 %) |
| landing | landing.touchdown_pitch_deg | -0.2 | 0.0 | +0.2 (+100.0 %) |
| landing | landing.touchdown_sink_mps | 0.44 | 0.43 | -0.01 (-2.3 %) |
| landing | landing.touchdown_speed_vs | 2.36 | 2.31 | -0.05 (-2.1 %) |
| loop | loop.heading_change_deg | 0.9 | 1.1 | +0.2 (+22.2 %) |
| loop | loop.height_change_m | 13.3 | 15.1 | +1.8 (+13.5 %) |
| loop | loop.loop_height_m | 42.9 | 47.2 | +4.3 (+10.0 %) |
| loop | loop.loop_time_s | 3.86 | 4.22 | +0.36 (+9.3 %) |
| loop | loop.max_load_factor_g | 10.9 | 10.14 | -0.76 (-7.0 %) |
| loop | loop.max_sideslip_deg | 3.8 | 3.1 | -0.7 (-18.4 %) |
| loop | loop.min_speed_mps | 27.5 | 27.09 | -0.41 (-1.5 %) |
| modes | modes[0.8Vmax].dutch_roll_hz | – | 1.077 | added/removed |
| modes | modes[0.8Vmax].dutch_roll_zeta | – | 0.308 | added/removed |
| modes | modes[0.8Vmax].phugoid_period_s | – | None | added/removed |
| modes | modes[0.8Vmax].phugoid_zeta | – | None | added/removed |
| modes | modes[0.8Vmax].roll_time_constant_s | – | 0.025 | added/removed |
| modes | modes[0.8Vmax].short_period_hz | – | 0.054 | added/removed |
| modes | modes[0.8Vmax].short_period_zeta | – | 1.468 | added/removed |
| modes | modes[0.8Vmax].speed_mps | – | 30.49 | added/removed |
| modes | modes[0.8Vmax].spiral_time_to_double_s | – | None | added/removed |
| modes | modes[0.8Vmax].spiral_time_to_half_s | – | 21.1 | added/removed |
| modes | modes[start].dutch_roll_hz | 0.674 | 0.731 | +0.057 (+8.5 %) |
| modes | modes[start].dutch_roll_zeta | 0.326 | 0.308 | -0.018 (-5.5 %) |
| modes | modes[start].phugoid_period_s | 15.45 | 12.31 | -3.14 (-20.3 %) |
| modes | modes[start].phugoid_zeta | 0.84 | 0.623 | -0.217 (-25.8 %) |
| modes | modes[start].short_period_hz | 1.526 | 1.789 | +0.263 (+17.2 %) |
| modes | modes[start].short_period_zeta | 1.085 | 0.881 | -0.204 (-18.8 %) |
| modes | modes[start].spiral_time_to_half_s | 12.1 | 20.8 | +8.7 (+71.9 %) |
| outside_loop | outside_loop.heading_change_deg | 5.5 | 7.7 | +2.2 (+40.0 %) |
| outside_loop | outside_loop.height_change_m | -10.3 | -14.1 | -3.8 (-36.9 %) |
| outside_loop | outside_loop.loop_depth_m | 46.4 | 54.4 | +8 (+17.2 %) |
| outside_loop | outside_loop.loop_time_s | 5.37 | 5.92 | +0.55 (+10.2 %) |
| outside_loop | outside_loop.max_sideslip_deg | 7.3 | 5.6 | -1.7 (-23.3 %) |
| outside_loop | outside_loop.max_speed_mps | 28.75 | 30.02 | +1.27 (+4.4 %) |
| outside_loop | outside_loop.min_load_factor_g | -4.55 | -4.26 | +0.29 (+6.4 %) |
| pitch_pull | pitch_pull[0.8Vmax].load_factor_at_cl_max | 10.27 | 9.79 | -0.48 (-4.7 %) |
| pitch_pull | pitch_pull[0.8Vmax].peak_alpha_deg | 23.0 | 19.8 | -3.2 (-13.9 %) |
| pitch_pull | pitch_pull[0.8Vmax].peak_load_factor_g | 9.08 | 8.55 | -0.53 (-5.8 %) |
| pitch_pull | pitch_pull[0.8Vmax].peak_pitch_rate_dps | 244.7 | 201.9 | -42.8 (-17.5 %) |
| pitch_pull | pitch_pull[start].load_factor_at_cl_max | 4.42 | 4.21 | -0.21 (-4.8 %) |
| pitch_pull | pitch_pull[start].peak_alpha_deg | 23.7 | 21.1 | -2.6 (-11.0 %) |
| pitch_pull | pitch_pull[start].peak_load_factor_g | 3.9 | 3.68 | -0.22 (-5.6 %) |
| pitch_pull | pitch_pull[start].peak_pitch_rate_dps | 150.3 | 123.2 | -27.1 (-18.0 %) |
| point_roll | point_roll[left].exit_bank_deg | 1.0 | 1.1 | +0.1 (+10.0 %) |
| point_roll | point_roll[left].heading_change_deg | 2.5 | 3.5 | +1 (+40.0 %) |
| point_roll | point_roll[left].height_change_m | -0.3 | -0.4 | -0.1 (-33.3 %) |
| point_roll | point_roll[left].max_height_deviation_m | 1.4 | 2.1 | +0.7 (+50.0 %) |
| point_roll | point_roll[left].max_sideslip_deg | 11.1 | 12.1 | +1 (+9.0 %) |
| point_roll | point_roll[left].over_rotation_point_1_deg | -1.7 | -1.4 | +0.3 (+17.6 %) |
| point_roll | point_roll[left].over_rotation_point_2_deg | 0.4 | 1.1 | +0.7 (+175.0 %) |
| point_roll | point_roll[left].over_rotation_point_3_deg | 1.9 | 2.3 | +0.4 (+21.1 %) |
| point_roll | point_roll[left].over_rotation_point_4_deg | 3.5 | 4.0 | +0.5 (+14.3 %) |
| point_roll | point_roll[left].peak_push_stick | 0.036 | 0.08 | +0.044 (+122.2 %) |
| point_roll | point_roll[left].peak_rudder_stick | 0.246 | 0.312 | +0.066 (+26.8 %) |
| point_roll | point_roll[left].point_1_elevator_stick | -0.006 | -0.029 | -0.023 (-383.3 %) |
| point_roll | point_roll[left].point_1_rudder_stick | 0.216 | 0.274 | +0.058 (+26.9 %) |
| point_roll | point_roll[left].point_2_elevator_stick | -0.026 | -0.075 | -0.049 (-188.5 %) |
| point_roll | point_roll[left].point_3_elevator_stick | -0.009 | -0.032 | -0.023 (-255.6 %) |
| point_roll | point_roll[left].point_3_rudder_stick | -0.207 | -0.274 | -0.067 (-32.4 %) |
| point_roll | point_roll[right].exit_bank_deg | -0.8 | -0.9 | -0.1 (-12.5 %) |
| point_roll | point_roll[right].heading_change_deg | -2.6 | -3.5 | -0.9 (-34.6 %) |
| point_roll | point_roll[right].height_change_m | 0.1 | 0.0 | -0.1 (-100.0 %) |
| point_roll | point_roll[right].max_height_deviation_m | 1.2 | 1.8 | +0.6 (+50.0 %) |
| point_roll | point_roll[right].max_sideslip_deg | 11.8 | 12.9 | +1.1 (+9.3 %) |
| point_roll | point_roll[right].over_rotation_point_1_deg | 0.3 | 0.2 | -0.1 (-33.3 %) |
| point_roll | point_roll[right].over_rotation_point_2_deg | -0.3 | 0.1 | +0.4 (+133.3 %) |
| point_roll | point_roll[right].over_rotation_point_3_deg | 4.3 | 4.7 | +0.4 (+9.3 %) |
| point_roll | point_roll[right].over_rotation_point_4_deg | 3.4 | 3.8 | +0.4 (+11.8 %) |
| point_roll | point_roll[right].peak_push_stick | 0.038 | 0.083 | +0.045 (+118.4 %) |
| point_roll | point_roll[right].peak_rudder_stick | 0.257 | 0.318 | +0.061 (+23.7 %) |
| point_roll | point_roll[right].point_1_elevator_stick | -0.008 | -0.032 | -0.024 (-300.0 %) |
| point_roll | point_roll[right].point_1_rudder_stick | -0.2 | -0.257 | -0.057 (-28.5 %) |
| point_roll | point_roll[right].point_2_elevator_stick | -0.026 | -0.074 | -0.048 (-184.6 %) |
| point_roll | point_roll[right].point_3_elevator_stick | -0.006 | -0.027 | -0.021 (-350.0 %) |
| point_roll | point_roll[right].point_3_rudder_stick | 0.215 | 0.282 | +0.067 (+31.2 %) |
| roll_rate | roll_rate[0.8Vmax_left].height_change_m | -6.4 | -9.2 | -2.8 (-43.7 %) |
| roll_rate | roll_rate[0.8Vmax_left].max_sideslip_deg | 9.3 | 9.4 | +0.1 (+1.1 %) |
| roll_rate | roll_rate[0.8Vmax_right].height_change_m | -6.2 | -8.2 | -2 (-32.3 %) |
| roll_rate | roll_rate[0.8Vmax_right].max_roll_rate_dps | 254.4 | 258.9 | +4.5 (+1.8 %) |
| roll_rate | roll_rate[0.8Vmax_right].max_sideslip_deg | 8.9 | 8.5 | -0.4 (-4.5 %) |
| roll_rate | roll_rate[0.8Vmax_right].time_to_360_s | 1.6 | 1.57 | -0.03 (-1.9 %) |
| roll_rate | roll_rate[1.3Vs_left].height_change_m | -17.5 | -22.3 | -4.8 (-27.4 %) |
| roll_rate | roll_rate[1.3Vs_left].max_roll_rate_dps | 183.3 | 176.2 | -7.1 (-3.9 %) |
| roll_rate | roll_rate[1.3Vs_left].max_sideslip_deg | 11.5 | 11.7 | +0.2 (+1.7 %) |
| roll_rate | roll_rate[1.3Vs_left].speed_mps | 12.36 | 12.66 | +0.3 (+2.4 %) |
| roll_rate | roll_rate[1.3Vs_left].time_to_360_s | 2.35 | 2.45 | +0.1 (+4.3 %) |
| roll_rate | roll_rate[1.3Vs_right].height_change_m | -16.7 | -19.7 | -3 (-18.0 %) |
| roll_rate | roll_rate[1.3Vs_right].max_roll_rate_dps | 192.8 | 190.2 | -2.6 (-1.3 %) |
| roll_rate | roll_rate[1.3Vs_right].speed_mps | 12.36 | 12.66 | +0.3 (+2.4 %) |
| roll_rate | roll_rate[start_left].height_change_m | -17.7 | -21.6 | -3.9 (-22.0 %) |
| roll_rate | roll_rate[start_left].max_roll_rate_dps | 182.7 | 177.9 | -4.8 (-2.6 %) |
| roll_rate | roll_rate[start_left].time_to_360_s | 2.37 | 2.41 | +0.04 (+1.7 %) |
| roll_rate | roll_rate[start_right].height_change_m | -16.9 | -19.1 | -2.2 (-13.0 %) |
| roll_rate | roll_rate[start_right].max_sideslip_deg | 10.9 | 10.7 | -0.2 (-1.8 %) |
| rudder_step | rudder_step[left].bank_after_2_75_s_deg | -145.5 | -153.2 | -7.7 (-5.3 %) |
| rudder_step | rudder_step[left].max_sideslip_deg | 26.4 | 26.1 | -0.3 (-1.1 %) |
| rudder_step | rudder_step[left].pitch_change_deg | -63.4 | -66.0 | -2.6 (-4.1 %) |
| rudder_step | rudder_step[right].bank_after_2_75_s_deg | 136.9 | 142.3 | +5.4 (+3.9 %) |
| rudder_step | rudder_step[right].max_sideslip_deg | 27.2 | 26.7 | -0.5 (-1.8 %) |
| rudder_step | rudder_step[right].peak_yaw_rate_dps | 104.0 | 102.8 | -1.2 (-1.2 %) |
| rudder_step | rudder_step[right].pitch_change_deg | -63.7 | -66.0 | -2.3 (-3.6 %) |
| slow_roll | slow_roll[left].exit_bank_deg | 0.4 | 0.2 | -0.2 (-50.0 %) |
| slow_roll | slow_roll[left].heading_change_deg | 4.3 | 4.9 | +0.6 (+14.0 %) |
| slow_roll | slow_roll[left].height_change_m | -0.7 | -1.1 | -0.4 (-57.1 %) |
| slow_roll | slow_roll[left].max_height_deviation_m | 0.9 | 1.4 | +0.5 (+55.6 %) |
| slow_roll | slow_roll[left].max_sideslip_deg | 10.5 | 11.1 | +0.6 (+5.7 %) |
| slow_roll | slow_roll[left].peak_push_stick | 0.038 | 0.08 | +0.042 (+110.5 %) |
| slow_roll | slow_roll[left].peak_rudder_stick | 0.244 | 0.31 | +0.066 (+27.0 %) |
| slow_roll | slow_roll[right].exit_bank_deg | -0.1 | 0.0 | +0.1 (+100.0 %) |
| slow_roll | slow_roll[right].heading_change_deg | -4.0 | -4.6 | -0.6 (-15.0 %) |
| slow_roll | slow_roll[right].height_change_m | -0.4 | -0.8 | -0.4 (-100.0 %) |
| slow_roll | slow_roll[right].max_height_deviation_m | 0.8 | 1.2 | +0.4 (+50.0 %) |
| slow_roll | slow_roll[right].max_sideslip_deg | 10.5 | 11.6 | +1.1 (+10.5 %) |
| slow_roll | slow_roll[right].peak_push_stick | 0.037 | 0.079 | +0.042 (+113.5 %) |
| slow_roll | slow_roll[right].peak_rudder_stick | 0.256 | 0.324 | +0.068 (+26.6 %) |
| snap_roll | snap_roll[left].alpha_before_45_deg_of_roll_deg | 24.1 | 22.0 | -2.1 (-8.7 %) |
| snap_roll | snap_roll[left].autorotation_short_of_finish_deg | 43.2 | 0.0 | -43.2 (-100.0 %) |
| snap_roll | snap_roll[left].entry_speed_mps | 15.21 | 15.59 | +0.38 (+2.5 %) |
| snap_roll | snap_roll[left].exit_bank_deg | 0.1 | 0.3 | +0.2 (+200.0 %) |
| snap_roll | snap_roll[left].heading_change_at_stop_deg | -27.1 | -1.2 | +25.9 (+95.6 %) |
| snap_roll | snap_roll[left].height_lost_m | 17.8 | 55.4 | +37.6 (+211.2 %) |
| snap_roll | snap_roll[left].max_alpha_deg | 24.1 | 23.3 | -0.8 (-3.3 %) |
| snap_roll | snap_roll[left].mean_roll_rate_dps | 202.8 | 227.6 | +24.8 (+12.2 %) |
| snap_roll | snap_roll[left].mean_yaw_rate_dps | 64.1 | 78.5 | +14.4 (+22.5 %) |
| snap_roll | snap_roll[left].peak_load_factor_g | 3.37 | 3.5 | +0.13 (+3.9 %) |
| snap_roll | snap_roll[left].peak_roll_rate_dps | 347.4 | 377.3 | +29.9 (+8.6 %) |
| snap_roll | snap_roll[left].release_after_deg | 316.8 | 329.1 | +12.3 (+3.9 %) |
| snap_roll | snap_roll[left].release_reason | autorotation ended | finish point |  |
| snap_roll | snap_roll[left].stop_after_deg | 403.9 | 543.5 | +139.6 (+34.6 %) |
| snap_roll | snap_roll[left].stop_error_deg | 43.9 | 183.5 | +139.6 (+318.0 %) |
| snap_roll | snap_roll[left].time_to_level_s | 1.52 | 2.0 | +0.48 (+31.6 %) |
| snap_roll | snap_roll[left].time_to_release_s | 1.56 | 1.45 | -0.11 (-7.1 %) |
| snap_roll | snap_roll[left].yaw_to_roll_ratio | 0.316 | 0.345 | +0.029 (+9.2 %) |
| snap_roll | snap_roll[right].alpha_before_45_deg_of_roll_deg | 24.5 | 22.4 | -2.1 (-8.6 %) |
| snap_roll | snap_roll[right].autorotation_short_of_finish_deg | 95.2 | 71.9 | -23.3 (-24.5 %) |
| snap_roll | snap_roll[right].entry_speed_mps | 15.21 | 15.59 | +0.38 (+2.5 %) |
| snap_roll | snap_roll[right].exit_bank_deg | 0.2 | 0.1 | -0.1 (-50.0 %) |
| snap_roll | snap_roll[right].heading_change_at_stop_deg | 12.7 | 14.3 | +1.6 (+12.6 %) |
| snap_roll | snap_roll[right].height_lost_m | 25.4 | 20.3 | -5.1 (-20.1 %) |
| snap_roll | snap_roll[right].max_alpha_deg | 25.3 | 25.9 | +0.6 (+2.4 %) |
| snap_roll | snap_roll[right].mean_roll_rate_dps | 189.7 | 216.0 | +26.3 (+13.9 %) |
| snap_roll | snap_roll[right].mean_yaw_rate_dps | 90.1 | 99.3 | +9.2 (+10.2 %) |
| snap_roll | snap_roll[right].peak_roll_rate_dps | 361.7 | 389.3 | +27.6 (+7.6 %) |
| snap_roll | snap_roll[right].release_after_deg | 264.8 | 288.1 | +23.3 (+8.8 %) |
| snap_roll | snap_roll[right].stop_after_deg | 330.3 | 348.6 | +18.3 (+5.5 %) |
| snap_roll | snap_roll[right].stop_error_deg | -29.7 | -11.4 | +18.3 (+61.6 %) |
| snap_roll | snap_roll[right].time_to_level_s | 1.4 | 1.52 | +0.12 (+8.6 %) |
| snap_roll | snap_roll[right].time_to_release_s | 1.4 | 1.33 | -0.07 (-5.0 %) |
| snap_roll | snap_roll[right].yaw_to_roll_ratio | 0.475 | 0.46 | -0.015 (-3.2 %) |
| spin | spin[left].height_lost_per_turn_m | 28.2 | 23.5 | -4.7 (-16.7 %) |
| spin | spin[left].recovery_time_s | 0.31 | 0.38 | +0.07 (+22.6 %) |
| spin | spin[left].recovery_turns | 0.25 | 0.36 | +0.11 (+44.0 %) |
| spin | spin[left].steady_turn_time_s | 1.36 | 1.2 | -0.16 (-11.8 %) |
| spin | spin[left].total_height_lost_m | 128.6 | 123.0 | -5.6 (-4.4 %) |
| spin | spin[left].turns_in_6_s | 2.69 | 3.2 | +0.51 (+19.0 %) |
| spin | spin[right].height_lost_per_turn_m | 30.6 | 25.4 | -5.2 (-17.0 %) |
| spin | spin[right].max_alpha_deg | 29.2 | 27.3 | -1.9 (-6.5 %) |
| spin | spin[right].recovery_time_s | 0.31 | 0.48 | +0.17 (+54.8 %) |
| spin | spin[right].recovery_turns | 0.28 | 0.64 | +0.36 (+128.6 %) |
| spin | spin[right].steady_turn_time_s | 1.32 | 1.13 | -0.19 (-14.4 %) |
| spin | spin[right].total_height_lost_m | 138.5 | 139.9 | +1.4 (+1.0 %) |
| spin | spin[right].turns_in_6_s | 2.7 | 3.2 | +0.5 (+18.5 %) |
| spin_inverted | spin_inverted[left].height_lost_per_turn_m | 27.8 | 31.4 | +3.6 (+12.9 %) |
| spin_inverted | spin_inverted[left].min_alpha_deg | -22.1 | -17.4 | +4.7 (+21.3 %) |
| spin_inverted | spin_inverted[left].recovery_time_s | 0.27 | 0.25 | -0.02 (-7.4 %) |
| spin_inverted | spin_inverted[left].recovery_turns | 0.18 | 0.14 | -0.04 (-22.2 %) |
| spin_inverted | spin_inverted[left].steady_turn_time_s | 0.97 | 0.99 | +0.02 (+2.1 %) |
| spin_inverted | spin_inverted[left].total_height_lost_m | 172.1 | 193.6 | +21.5 (+12.5 %) |
| spin_inverted | spin_inverted[left].turns_in_6_s | 4.28 | 4.49 | +0.21 (+4.9 %) |
| spin_inverted | spin_inverted[right].height_lost_per_turn_m | 27.0 | 30.9 | +3.9 (+14.4 %) |
| spin_inverted | spin_inverted[right].min_alpha_deg | -24.1 | -21.2 | +2.9 (+12.0 %) |
| spin_inverted | spin_inverted[right].recovery_time_s | 0.3 | 0.26 | -0.04 (-13.3 %) |
| spin_inverted | spin_inverted[right].recovery_turns | 0.2 | 0.16 | -0.04 (-20.0 %) |
| spin_inverted | spin_inverted[right].steady_turn_time_s | 0.99 | 1.03 | +0.04 (+4.0 %) |
| spin_inverted | spin_inverted[right].total_height_lost_m | 197.8 | 184.6 | -13.2 (-6.7 %) |
| split_s | split_s.exit_bank_deg | 0.2 | 0.1 | -0.1 (-50.0 %) |
| split_s | split_s.exit_speed_mps | 27.52 | 28.37 | +0.85 (+3.1 %) |
| split_s | split_s.half_roll_time_s | 1.18 | 1.16 | -0.02 (-1.7 %) |
| split_s | split_s.heading_error_deg | -3.4 | -0.7 | +2.7 (+79.4 %) |
| split_s | split_s.height_lost_m | 35.0 | 38.7 | +3.7 (+10.6 %) |
| split_s | split_s.height_lost_to_level_m | 34.8 | 38.5 | +3.7 (+10.6 %) |
| split_s | split_s.max_load_factor_g | 5.89 | 5.59 | -0.3 (-5.1 %) |
| split_s | split_s.max_sideslip_deg | 8.7 | 8.4 | -0.3 (-3.4 %) |
| split_s | split_s.max_speed_mps | 27.75 | 28.63 | +0.88 (+3.2 %) |
| split_s | split_s.time_to_level_s | 3.8 | 3.89 | +0.09 (+2.4 %) |
| stall_inverted | stall_inverted.altitude_lost_m | 19.0 | 19.5 | +0.5 (+2.6 %) |
| stall_inverted | stall_inverted.ratio_to_upright_vs | 1.205 | 1.222 | +0.017 (+1.4 %) |
| stall_inverted | stall_inverted.recovery_time_s | 2.35 | 2.39 | +0.04 (+1.7 %) |
| stall_inverted | stall_inverted.roll_off_in_1_s_deg | -111.0 | -113.4 | -2.4 (-2.2 %) |
| stall_inverted | stall_inverted.stall_speed_mps | 11.46 | 11.91 | +0.45 (+3.9 %) |
| stall_power_on | stall_power_on.altitude_lost_m | 2.3 | 1.0 | -1.3 (-56.5 %) |
| stall_power_on | stall_power_on.bank_in_first_second_deg | -89.7 | -84.6 | +5.1 (+5.7 %) |
| stall_power_on | stall_power_on.deceleration_before_break_mps2 | 1.25 | 1.04 | -0.21 (-16.8 %) |
| stall_power_on | stall_power_on.max_bank_in_recovery_deg | 89.7 | 84.6 | -5.1 (-5.7 %) |
| stall_power_on | stall_power_on.ratio_to_cl_max_estimate | 0.672 | 0.693 | +0.021 (+3.1 %) |
| stall_power_on | stall_power_on.recovery_time_s | 2.75 | 2.57 | -0.18 (-6.5 %) |
| stall_power_on | stall_power_on.stall_alpha_deg | 15.9 | 15.4 | -0.5 (-3.1 %) |
| stall_power_on | stall_power_on.stall_speed_mps | 6.39 | 6.75 | +0.36 (+5.6 %) |
| stall_turn | stall_turn[left_0.35Vs].exit_speed_mps | 29.95 | 30.36 | +0.41 (+1.4 %) |
| stall_turn | stall_turn[left_0.35Vs].height_gain_to_kick_m | 83.8 | 84.9 | +1.1 (+1.3 %) |
| stall_turn | stall_turn[left_0.35Vs].height_lost_top_to_level_m | 73.1 | 74.8 | +1.7 (+2.3 %) |
| stall_turn | stall_turn[left_0.35Vs].kick_speed_mps | 3.31 | 3.39 | +0.08 (+2.4 %) |
| stall_turn | stall_turn[left_0.35Vs].kick_speed_target_mps | 3.33 | 3.41 | +0.08 (+2.4 %) |
| stall_turn | stall_turn[left_0.35Vs].min_forward_speed_mps | -4.17 | -4.01 | +0.16 (+3.8 %) |
| stall_turn | stall_turn[left_0.35Vs].pitch_during_pivot_deg | 38.6 | 55.9 | +17.3 (+44.8 %) |
| stall_turn | stall_turn[left_0.35Vs].pivot_radius_m | 6.96 | 6.5 | -0.46 (-6.6 %) |
| stall_turn | stall_turn[left_0.35Vs].pivot_radius_spans | 4.57 | 4.27 | -0.3 (-6.6 %) |
| stall_turn | stall_turn[left_0.35Vs].pivot_time_s | 3.75 | 3.53 | -0.22 (-5.9 %) |
| stall_turn | stall_turn[left_0.35Vs].torque_off_deg | 227.1 | 220.9 | -6.2 (-2.7 %) |
| stall_turn | stall_turn[left_0.35Vs].up_line_time_s | 3.73 | 3.67 | -0.06 (-1.6 %) |
| stall_turn | stall_turn[left_0.6Vs].exit_speed_mps | 26.91 | 28.18 | +1.27 (+4.7 %) |
| stall_turn | stall_turn[left_0.6Vs].height_gain_to_kick_m | 82.2 | 83.3 | +1.1 (+1.3 %) |
| stall_turn | stall_turn[left_0.6Vs].height_lost_top_to_level_m | 58.7 | 62.4 | +3.7 (+6.3 %) |
| stall_turn | stall_turn[left_0.6Vs].kick_speed_mps | 5.7 | 5.82 | +0.12 (+2.1 %) |
| stall_turn | stall_turn[left_0.6Vs].kick_speed_target_mps | 5.7 | 5.85 | +0.15 (+2.6 %) |
| stall_turn | stall_turn[left_0.6Vs].min_forward_speed_mps | -1.76 | -1.58 | +0.18 (+10.2 %) |
| stall_turn | stall_turn[left_0.6Vs].pitch_during_pivot_deg | 83.3 | 86.5 | +3.2 (+3.8 %) |
| stall_turn | stall_turn[left_0.6Vs].pivot_radius_m | 10.86 | 9.98 | -0.88 (-8.1 %) |
| stall_turn | stall_turn[left_0.6Vs].pivot_radius_spans | 7.13 | 6.55 | -0.58 (-8.1 %) |
| stall_turn | stall_turn[left_0.6Vs].pivot_time_s | 4.12 | 3.85 | -0.27 (-6.6 %) |
| stall_turn | stall_turn[left_0.6Vs].torque_off_deg | 351.6 | 336.0 | -15.6 (-4.4 %) |
| stall_turn | stall_turn[left_0.6Vs].up_line_time_s | 3.38 | 3.31 | -0.07 (-2.1 %) |
| stall_turn | stall_turn[right_0.35Vs].exit_speed_mps | 36.37 | 36.86 | +0.49 (+1.3 %) |
| stall_turn | stall_turn[right_0.35Vs].height_gain_to_kick_m | 83.8 | 84.9 | +1.1 (+1.3 %) |
| stall_turn | stall_turn[right_0.35Vs].height_lost_top_to_level_m | 144.4 | 161.8 | +17.4 (+12.0 %) |
| stall_turn | stall_turn[right_0.35Vs].kick_speed_mps | 3.31 | 3.39 | +0.08 (+2.4 %) |
| stall_turn | stall_turn[right_0.35Vs].kick_speed_target_mps | 3.33 | 3.41 | +0.08 (+2.4 %) |
| stall_turn | stall_turn[right_0.35Vs].min_forward_speed_mps | -4.02 | -3.9 | +0.12 (+3.0 %) |
| stall_turn | stall_turn[right_0.35Vs].pitch_during_pivot_deg | 77.8 | 44.9 | -32.9 (-42.3 %) |
| stall_turn | stall_turn[right_0.35Vs].pivot_radius_m | 42.36 | 39.64 | -2.72 (-6.4 %) |
| stall_turn | stall_turn[right_0.35Vs].pivot_radius_spans | 27.8 | 26.01 | -1.79 (-6.4 %) |
| stall_turn | stall_turn[right_0.35Vs].up_line_time_s | 3.73 | 3.67 | -0.06 (-1.6 %) |
| stall_turn | stall_turn[right_0.6Vs].height_gain_to_kick_m | 82.2 | 83.3 | +1.1 (+1.3 %) |
| stall_turn | stall_turn[right_0.6Vs].height_lost_top_to_level_m | 143.7 | 153.6 | +9.9 (+6.9 %) |
| stall_turn | stall_turn[right_0.6Vs].kick_speed_mps | 5.7 | 5.82 | +0.12 (+2.1 %) |
| stall_turn | stall_turn[right_0.6Vs].kick_speed_target_mps | 5.7 | 5.85 | +0.15 (+2.6 %) |
| stall_turn | stall_turn[right_0.6Vs].min_forward_speed_mps | -1.25 | -1.02 | +0.23 (+18.4 %) |
| stall_turn | stall_turn[right_0.6Vs].pitch_during_pivot_deg | 23.4 | 31.0 | +7.6 (+32.5 %) |
| stall_turn | stall_turn[right_0.6Vs].pivot_radius_m | 46.26 | 47.87 | +1.61 (+3.5 %) |
| stall_turn | stall_turn[right_0.6Vs].pivot_radius_spans | 30.36 | 31.41 | +1.05 (+3.5 %) |
| stall_turn | stall_turn[right_0.6Vs].torque_off_deg | 194.0 | 182.3 | -11.7 (-6.0 %) |
| stall_turn | stall_turn[right_0.6Vs].up_line_time_s | 3.38 | 3.31 | -0.07 (-2.1 %) |
| takeoff | takeoff.ground_roll_m | 15.8 | 17.0 | +1.2 (+7.6 %) |
| takeoff | takeoff.liftoff_speed_mps | 16.94 | 17.55 | +0.61 (+3.6 %) |
| takeoff | takeoff.liftoff_speed_vs | 1.78 | 1.8 | +0.02 (+1.1 %) |
| takeoff | takeoff.rudder_free_heading_change_3_s_deg | -0.2 | -0.6 | -0.4 (-200.0 %) |
| takeoff | takeoff.time_to_liftoff_s | 3.66 | 3.75 | +0.09 (+2.5 %) |
| throttle_response | throttle_response.spool_up_10_90_s | 2.663 | 2.746 | +0.083 (+3.1 %) |
| trim_sweep | trim_sweep[x1.00].alpha_deg | 1.77 | 1.96 | +0.19 (+10.7 %) |
| trim_sweep | trim_sweep[x1.00].stick_pitch | 0.041 | 0.108 | +0.067 (+163.4 %) |
| trim_sweep | trim_sweep[x1.05].alpha_deg | 1.49 | 1.65 | +0.16 (+10.7 %) |
| trim_sweep | trim_sweep[x1.05].stick_pitch | 0.036 | 0.097 | +0.061 (+169.4 %) |
| trim_sweep | trim_sweep[x1.10].alpha_deg | 1.24 | 1.39 | +0.15 (+12.1 %) |
| trim_sweep | trim_sweep[x1.10].stick_pitch | 0.033 | 0.088 | +0.055 (+166.7 %) |
| trim_sweep | trim_sweep[x1.15].alpha_deg | 1.02 | 1.16 | +0.14 (+13.7 %) |
| trim_sweep | trim_sweep[x1.15].stick_pitch | 0.03 | 0.08 | +0.05 (+166.7 %) |
| trim_sweep | trim_sweep[x1.20].alpha_deg | 0.83 | 0.95 | +0.12 (+14.5 %) |
| trim_sweep | trim_sweep[x1.20].stick_pitch | 0.027 | 0.073 | +0.046 (+170.4 %) |
| trim_sweep | trim_sweep[x1.25].alpha_deg | 0.66 | 0.77 | +0.11 (+16.7 %) |
| trim_sweep | trim_sweep[x1.25].stick_pitch | 0.025 | 0.067 | +0.042 (+168.0 %) |
| trim_sweep | trim_sweep[x1.30].alpha_deg | 0.51 | 0.62 | +0.11 (+21.6 %) |
| trim_sweep | trim_sweep[x1.30].stick_pitch | 0.023 | 0.062 | +0.039 (+169.6 %) |
| trim_sweep | trim_sweep[x1.35].alpha_deg | 0.38 | 0.48 | +0.1 (+26.3 %) |
| trim_sweep | trim_sweep[x1.35].stick_pitch | 0.021 | 0.057 | +0.036 (+171.4 %) |
| trim_sweep | trim_sweep[x1.40].alpha_deg | 0.26 | 0.35 | +0.09 (+34.6 %) |
| trim_sweep | trim_sweep[x1.40].stick_pitch | 0.019 | 0.053 | +0.034 (+178.9 %) |
| trim_sweep | trim_sweep[x1.45].alpha_deg | 0.15 | 0.24 | +0.09 (+60.0 %) |
| trim_sweep | trim_sweep[x1.45].stick_pitch | 0.018 | 0.05 | +0.032 (+177.8 %) |
| trim_sweep | trim_sweep[x1.50].alpha_deg | 0.05 | 0.13 | +0.08 (+160.0 %) |
| trim_sweep | trim_sweep[x1.50].stick_pitch | 0.017 | 0.046 | +0.029 (+170.6 %) |
| trim_sweep | trim_sweep[x1.55].alpha_deg | -0.03 | 0.04 | +0.07 (+233.3 %) |
| trim_sweep | trim_sweep[x1.55].stick_pitch | 0.015 | 0.043 | +0.028 (+186.7 %) |
| trim_sweep | trim_sweep[x1.60].alpha_deg | -0.11 | -0.04 | +0.07 (+63.6 %) |
| trim_sweep | trim_sweep[x1.60].stick_pitch | 0.014 | 0.04 | +0.026 (+185.7 %) |
| trim_sweep | trim_sweep[x1.65].alpha_deg | -0.19 | -0.12 | +0.07 (+36.8 %) |
| trim_sweep | trim_sweep[x1.65].stick_pitch | 0.014 | 0.038 | +0.024 (+171.4 %) |
| trim_sweep | trim_sweep[x1.70].alpha_deg | -0.25 | -0.19 | +0.06 (+24.0 %) |
| trim_sweep | trim_sweep[x1.70].stick_pitch | 0.013 | 0.036 | +0.023 (+176.9 %) |
| trim_sweep | trim_sweep[x1.75].alpha_deg | -0.31 | -0.25 | +0.06 (+19.4 %) |
| trim_sweep | trim_sweep[x1.75].stick_pitch | 0.012 | 0.034 | +0.022 (+183.3 %) |
| trim_sweep | trim_sweep[x1.80].alpha_deg | -0.37 | -0.31 | +0.06 (+16.2 %) |
| trim_sweep | trim_sweep[x1.80].stick_pitch | 0.011 | 0.032 | +0.021 (+190.9 %) |
| trim_sweep | trim_sweep[x1.85].alpha_deg | -0.42 | -0.37 | +0.05 (+11.9 %) |
| trim_sweep | trim_sweep[x1.85].stick_pitch | 0.011 | 0.03 | +0.019 (+172.7 %) |
| turn_60 | turn_60[right].vertical_speed_mps | -0.03 | -0.04 | -0.01 (-33.3 %) |
| vmax | vmax.height_error_end_m | 0.36 | 0.45 | +0.09 (+25.0 %) |
| vmax | vmax.height_error_run_m | 0.37 | 0.64 | +0.27 (+73.0 %) |
| vmax | vmax.initial_acceleration_mps2 | 4.1 | 3.98 | -0.12 (-2.9 %) |
| vmax | vmax.time_plus_10_mps_s | 2.0 | 2.06 | +0.06 (+3.0 %) |
| vmax | vmax.time_plus_5_mps_s | 1.15 | 1.17 | +0.02 (+1.7 %) |
| vmax | vmax.time_to_90_percent_s | 4.22 | 4.42 | +0.2 (+4.7 %) |

## Jensen Das Ugly Stik 60 · FS-64V — 335 change(s)

Aircraft data changed between the runs.

| Test | Value | Baseline | Candidate | Change |
| --- | --- | --- | --- | --- |
| stall_inverted | validity | valid | not valid | |
| aero_sweep | aero_sweep.trim_alpha_deg | 1.46 | 1.51 | +0.05 (+3.4 %) |
| aero_sweep | aero_sweep[alpha_05].cm | -0.0287 | -0.0553 | -0.0266 (-92.7 %) |
| aero_sweep | aero_sweep[alpha_05].cm_local | -0.0354 | -0.062 | -0.0266 (-75.1 %) |
| aero_sweep | aero_sweep[alpha_05].cm_oracle | -0.0287 | -0.0553 | -0.0266 (-92.7 %) |
| aero_sweep | aero_sweep[alpha_10].cm | -0.073 | -0.1195 | -0.0465 (-63.7 %) |
| aero_sweep | aero_sweep[alpha_10].cm_local | -0.0835 | -0.1301 | -0.0466 (-55.8 %) |
| aero_sweep | aero_sweep[alpha_10].cm_oracle | -0.0633 | -0.1099 | -0.0466 (-73.6 %) |
| aero_sweep | aero_sweep[alpha_15].cm | -0.2707 | -0.3121 | -0.0414 (-15.3 %) |
| aero_sweep | aero_sweep[alpha_15].cm_local | -0.2707 | -0.3121 | -0.0414 (-15.3 %) |
| aero_sweep | aero_sweep[alpha_15].cm_oracle | -0.1359 | -0.1789 | -0.043 (-31.6 %) |
| aero_sweep | aero_sweep[alpha_20].cm | -0.2572 | -0.2866 | -0.0294 (-11.4 %) |
| aero_sweep | aero_sweep[alpha_20].cm_local | -0.2572 | -0.2866 | -0.0294 (-11.4 %) |
| aero_sweep | aero_sweep[alpha_20].cm_oracle | -0.2148 | -0.2373 | -0.0225 (-10.5 %) |
| aero_sweep | aero_sweep[alpha_30].cm | -0.1991 | -0.238 | -0.0389 (-19.5 %) |
| aero_sweep | aero_sweep[alpha_30].cm_local | -0.1991 | -0.238 | -0.0389 (-19.5 %) |
| aero_sweep | aero_sweep[alpha_30].cm_oracle | -0.3062 | -0.3389 | -0.0327 (-10.7 %) |
| aero_sweep | aero_sweep[alpha_m05].cm | 0.0088 | 0.024 | +0.0152 (+172.7 %) |
| aero_sweep | aero_sweep[alpha_m05].cm_local | 0.0325 | 0.0476 | +0.0151 (+46.5 %) |
| aero_sweep | aero_sweep[alpha_m05].cm_oracle | 0.0088 | 0.024 | +0.0152 (+172.7 %) |
| aero_sweep | aero_sweep[alpha_m10].cm | 0.043 | 0.0795 | +0.0365 (+84.9 %) |
| aero_sweep | aero_sweep[alpha_m10].cm_local | 0.052 | 0.0886 | +0.0366 (+70.4 %) |
| aero_sweep | aero_sweep[alpha_m10].cm_oracle | 0.0123 | 0.0488 | +0.0365 (+296.7 %) |
| climb | climb.best.path_angle_deg | 81.4 | 74.9 | -6.5 (-8.0 %) |
| climb | climb.best.speed_mps | 15.17 | 14.98 | -0.19 (-1.3 %) |
| climb | climb.best.vertical_speed_mps | 14.26 | 14.01 | -0.25 (-1.8 %) |
| climb | climb[1.3Vs].speed_mps | 14.69 | 14.37 | -0.32 (-2.2 %) |
| climb | climb[1.3Vs].vertical_speed_mps | 14.14 | 13.84 | -0.3 (-2.1 %) |
| climb | climb[1.6Vs].path_angle_deg | 81.4 | 74.9 | -6.5 (-8.0 %) |
| climb | climb[1.6Vs].speed_mps | 15.17 | 14.98 | -0.19 (-1.3 %) |
| climb | climb[1.6Vs].vertical_speed_mps | 14.26 | 14.01 | -0.25 (-1.8 %) |
| climb | climb[2.0Vs].path_angle_deg | 52.1 | 50.5 | -1.6 (-3.1 %) |
| climb | climb[2.0Vs].pitch_deg | 52.1 | 50.7 | -1.4 (-2.7 %) |
| climb | climb[2.0Vs].vertical_speed_mps | 14.23 | 14.0 | -0.23 (-1.6 %) |
| dead_stick_landing | dead_stick_landing.flare_height_m | 2.82 | 2.85 | +0.03 (+1.1 %) |
| dead_stick_landing | dead_stick_landing.glide_sink_mps | 2.82 | 2.85 | +0.03 (+1.1 %) |
| dead_stick_landing | dead_stick_landing.touchdown_sink_mps | 0.73 | 0.74 | +0.01 (+1.4 %) |
| engine_cut_climb | engine_cut_climb[delay_1s].alpha_margin_to_stall_deg | 3.0 | 3.2 | +0.2 (+6.7 %) |
| engine_cut_climb | engine_cut_climb[delay_1s].climb_pitch_at_cut_deg | 53.8 | 53.1 | -0.7 (-1.3 %) |
| engine_cut_climb | engine_cut_climb[delay_1s].height_change_10_s_m | -7.8 | -8.2 | -0.4 (-5.1 %) |
| engine_cut_climb | engine_cut_climb[delay_1s].height_gained_after_cut_m | 18.0 | 17.8 | -0.2 (-1.1 %) |
| engine_cut_climb | engine_cut_climb[delay_1s].max_alpha_deg | 9.2 | 9.0 | -0.2 (-2.2 %) |
| engine_cut_climb | engine_cut_climb[delay_1s].min_speed_vs | 0.94 | 0.95 | +0.01 (+1.1 %) |
| engine_cut_climb | engine_cut_climb[delay_1s].time_below_1_2vs_s | 1.56 | 1.58 | +0.02 (+1.3 %) |
| engine_cut_climb | engine_cut_climb[delay_2s].alpha_margin_to_stall_deg | -40.5 | -32.1 | +8.4 (+20.7 %) |
| engine_cut_climb | engine_cut_climb[delay_2s].climb_pitch_at_cut_deg | 53.8 | 53.1 | -0.7 (-1.3 %) |
| engine_cut_climb | engine_cut_climb[delay_2s].height_change_10_s_m | -85.6 | -90.7 | -5.1 (-6.0 %) |
| engine_cut_climb | engine_cut_climb[delay_2s].max_alpha_deg | 52.6 | 44.2 | -8.4 (-16.0 %) |
| engine_cut_climb | engine_cut_climb[delay_2s].min_speed_mps | 4.15 | 4.33 | +0.18 (+4.3 %) |
| engine_cut_climb | engine_cut_climb[delay_2s].min_speed_vs | 0.46 | 0.48 | +0.02 (+4.3 %) |
| engine_cut_climb | engine_cut_climb[delay_2s].rpm_10_s_after_cut | 6647 | 7082 | +435 (+6.5 %) |
| engine_cut_climb | engine_cut_climb[delay_2s].speed_after_reaction_mps | 6.06 | 6.16 | +0.1 (+1.7 %) |
| engine_cut_climb | engine_cut_climb[delay_2s].time_below_1_2vs_s | 2.65 | 2.58 | -0.07 (-2.6 %) |
| glide | glide.best.path_angle_deg | 5.0 | 4.8 | -0.2 (-4.0 %) |
| glide | glide.best.vertical_speed_mps | 1.01 | 0.99 | -0.02 (-2.0 %) |
| glide | glide[1.3Vs].path_angle_deg | 5.0 | 4.8 | -0.2 (-4.0 %) |
| glide | glide[1.3Vs].vertical_speed_mps | 1.01 | 0.99 | -0.02 (-2.0 %) |
| glide | glide[1.6Vs].path_angle_deg | 3.2 | 3.1 | -0.1 (-3.1 %) |
| glide | glide[1.6Vs].pitch_deg | 7.2 | 7.1 | -0.1 (-1.4 %) |
| glide | glide[1.6Vs].vertical_speed_mps | 0.82 | 0.78 | -0.04 (-4.9 %) |
| glide | glide[2.0Vs].glide_ratio | 75.13 | 60.61 | -14.52 (-19.3 %) |
| glide | glide[2.0Vs].path_angle_deg | -0.8 | -0.9 | -0.1 (-12.5 %) |
| glide | glide[2.0Vs].pitch_deg | 1.3 | 1.2 | -0.1 (-7.7 %) |
| glide | glide[2.0Vs].vertical_speed_mps | -0.24 | -0.3 | -0.06 (-25.0 %) |
| glide_turn | glide_turn.least_height_lost_180_m | 15.0 | 15.4 | +0.4 (+2.7 %) |
| glide_turn | glide_turn[30deg].height_lost_180_m | 16.9 | 17.1 | +0.2 (+1.2 %) |
| glide_turn | glide_turn[30deg].height_lost_360_m | 36.5 | 36.9 | +0.4 (+1.1 %) |
| glide_turn | glide_turn[30deg].radius_m | 26.1 | 26.4 | +0.3 (+1.1 %) |
| glide_turn | glide_turn[30deg].straight_sink_mps | 0.8 | 0.81 | +0.01 (+1.3 %) |
| glide_turn | glide_turn[45deg].height_lost_180_m | 15.0 | 15.4 | +0.4 (+2.7 %) |
| glide_turn | glide_turn[45deg].height_lost_360_m | 30.2 | 30.9 | +0.7 (+2.3 %) |
| glide_turn | glide_turn[45deg].radius_m | 17.6 | 17.9 | +0.3 (+1.7 %) |
| glide_turn | glide_turn[45deg].straight_sink_mps | 1.41 | 1.43 | +0.02 (+1.4 %) |
| glide_turn | glide_turn[45deg].turn_sink_mps | 3.64 | 3.69 | +0.05 (+1.4 %) |
| glide_turn | glide_turn[60deg].height_lost_180_m | 19.5 | 20.4 | +0.9 (+4.6 %) |
| glide_turn | glide_turn[60deg].height_lost_360_m | 36.3 | 37.8 | +1.5 (+4.1 %) |
| glide_turn | glide_turn[60deg].radius_m | 15.4 | 15.8 | +0.4 (+2.6 %) |
| glide_turn | glide_turn[60deg].speed_in_turn_mps | 15.72 | 15.95 | +0.23 (+1.5 %) |
| glide_turn | glide_turn[60deg].straight_sink_mps | 2.89 | 3.22 | +0.33 (+11.4 %) |
| glide_turn | glide_turn[60deg].time_to_180_s | 3.52 | 3.57 | +0.05 (+1.4 %) |
| glide_turn | glide_turn[60deg].time_to_360_s | 6.6 | 6.68 | +0.08 (+1.2 %) |
| glide_turn | glide_turn[60deg].turn_sink_mps | 5.49 | 5.58 | +0.09 (+1.6 %) |
| go_around | go_around[fast].max_bank_deg | 1.5 | 1.4 | -0.1 (-6.7 %) |
| go_around | go_around[fast].max_heading_error_deg | 1.3 | 1.2 | -0.1 (-7.7 %) |
| go_around | go_around[fast].time_to_15_m_s | 1.85 | 1.82 | -0.03 (-1.6 %) |
| go_around | go_around[slow].max_heading_error_deg | 1.4 | 1.3 | -0.1 (-7.1 %) |
| hands_off | hands_off.bank_10_s_deg | -0.7 | 4.9 | +5.6 (+800.0 %) |
| hands_off | hands_off.bank_30_s_deg | 4.7 | 14.0 | +9.3 (+197.9 %) |
| hands_off | hands_off.bank_after_aileron_pulse_deg | 15.4 | 14.9 | -0.5 (-3.2 %) |
| hands_off | hands_off.heading_change_10_s_deg | 22.0 | 28.7 | +6.7 (+30.5 %) |
| hands_off | hands_off.heading_change_30_s_deg | 50.6 | 117.9 | +67.3 (+133.0 %) |
| hands_off | hands_off.height_change_10_s_m | 10.09 | 2.98 | -7.11 (-70.5 %) |
| hands_off | hands_off.height_change_30_s_m | -0.11 | -17.71 | -17.6 (-16000.0 %) |
| hands_off | hands_off.speed_change_10_s_mps | 0.26 | 1.07 | +0.81 (+311.5 %) |
| hands_off | hands_off.speed_change_30_s_mps | 0.51 | 1.41 | +0.9 (+176.5 %) |
| immelmann | immelmann.half_loop_time_s | 2.63 | 2.73 | +0.1 (+3.8 %) |
| immelmann | immelmann.heading_error_deg | -12.8 | -11.6 | +1.2 (+9.4 %) |
| immelmann | immelmann.height_gain_m | 26.2 | 27.7 | +1.5 (+5.7 %) |
| immelmann | immelmann.max_sideslip_deg | 9.0 | 8.9 | -0.1 (-1.1 %) |
| inverted | inverted.elevator_servo | -0.024 | -0.064 | -0.04 (-166.7 %) |
| inverted | inverted.elevator_stick | -0.024 | -0.064 | -0.04 (-166.7 %) |
| inverted | inverted.throttle | 0.277 | 0.22 | -0.057 (-20.6 %) |
| inverted | inverted.vertical_speed_mps | 0.03 | 0.01 | -0.02 (-66.7 %) |
| inverted_speeds | inverted_speeds[0.6Vmax].elevator_servo | -0.032 | -0.087 | -0.055 (-171.9 %) |
| inverted_speeds | inverted_speeds[0.6Vmax].elevator_stick | -0.032 | -0.087 | -0.055 (-171.9 %) |
| inverted_speeds | inverted_speeds[0.6Vmax].throttle | 0.127 | 0.081 | -0.046 (-36.2 %) |
| inverted_speeds | inverted_speeds[0.6Vmax].vertical_speed_mps | -0.03 | 0.06 | +0.09 (+300.0 %) |
| inverted_speeds | inverted_speeds[0.8Vmax].elevator_servo | -0.021 | -0.053 | -0.032 (-152.4 %) |
| inverted_speeds | inverted_speeds[0.8Vmax].elevator_stick | -0.021 | -0.053 | -0.032 (-152.4 %) |
| inverted_speeds | inverted_speeds[0.8Vmax].throttle | 0.405 | 0.352 | -0.053 (-13.1 %) |
| inverted_speeds | inverted_speeds[start].elevator_servo | -0.024 | -0.064 | -0.04 (-166.7 %) |
| inverted_speeds | inverted_speeds[start].elevator_stick | -0.024 | -0.064 | -0.04 (-166.7 %) |
| inverted_speeds | inverted_speeds[start].throttle | 0.277 | 0.22 | -0.057 (-20.6 %) |
| inverted_speeds | inverted_speeds[start].vertical_speed_mps | 0.03 | 0.01 | -0.02 (-66.7 %) |
| inverted_turn | inverted_turn[left].alpha_deg | -5.2 | -5.3 | -0.1 (-1.9 %) |
| inverted_turn | inverted_turn[left].elevator_stick | -0.122 | -0.179 | -0.057 (-46.7 %) |
| inverted_turn | inverted_turn[left].throttle | 0.341 | 0.267 | -0.074 (-21.7 %) |
| inverted_turn | inverted_turn[left].vertical_speed_mps | 0.0 | -0.03 | -0.03 |
| inverted_turn | inverted_turn[right].elevator_stick | -0.08 | -0.136 | -0.056 (-70.0 %) |
| inverted_turn | inverted_turn[right].throttle | 0.345 | 0.273 | -0.072 (-20.9 %) |
| inverted_turn | inverted_turn[right].vertical_speed_mps | 0.01 | -0.01 | -0.02 (-200.0 %) |
| knife_edge | knife_edge[left_50pct].pitch_attitude_deg | -22.8 | -22.4 | +0.4 (+1.8 %) |
| knife_edge | knife_edge[right_50pct].pitch_attitude_deg | -21.8 | -21.4 | +0.4 (+1.8 %) |
| knife_edge_full_rudder | knife_edge_full_rudder[left_100pct].pitch_attitude_deg | -15.4 | -15.2 | +0.2 (+1.3 %) |
| knife_edge_full_rudder | knife_edge_full_rudder[left_50pct].pitch_attitude_deg | -23.5 | -23.0 | +0.5 (+2.1 %) |
| knife_edge_full_rudder | knife_edge_full_rudder[right_100pct].pitch_attitude_deg | -13.7 | -13.5 | +0.2 (+1.5 %) |
| knife_edge_full_rudder | knife_edge_full_rudder[right_50pct].pitch_attitude_deg | -22.1 | -21.7 | +0.4 (+1.8 %) |
| landing | landing.rollout_m | 125.3 | 119.3 | -6 (-4.8 %) |
| landing | landing.rollout_time_s | 12.55 | 11.87 | -0.68 (-5.4 %) |
| landing | landing.touchdown_pitch_deg | 0.1 | 0.2 | +0.1 (+100.0 %) |
| landing | landing.touchdown_sink_mps | 0.44 | 0.43 | -0.01 (-2.3 %) |
| loop | loop.heading_change_deg | -7.8 | -6.5 | +1.3 (+16.7 %) |
| loop | loop.height_change_m | 9.9 | 10.4 | +0.5 (+5.1 %) |
| loop | loop.loop_height_m | 31.1 | 32.5 | +1.4 (+4.5 %) |
| loop | loop.loop_time_s | 4.0 | 4.13 | +0.13 (+3.2 %) |
| loop | loop.max_load_factor_g | 7.94 | 7.85 | -0.09 (-1.1 %) |
| loop | loop.max_sideslip_deg | 8.3 | 7.5 | -0.8 (-9.6 %) |
| modes | modes[0.8Vmax].dutch_roll_hz | 0.792 | 0.852 | +0.06 (+7.6 %) |
| modes | modes[0.8Vmax].dutch_roll_zeta | 0.35 | 0.338 | -0.012 (-3.4 %) |
| modes | modes[0.8Vmax].short_period_hz | 0.054 | 0.067 | +0.013 (+24.1 %) |
| modes | modes[0.8Vmax].short_period_zeta | 2.007 | 1.597 | -0.41 (-20.4 %) |
| modes | modes[0.8Vmax].spiral_time_to_half_s | 11.9 | 17.2 | +5.3 (+44.5 %) |
| modes | modes[start].dutch_roll_hz | 0.724 | 0.779 | +0.055 (+7.6 %) |
| modes | modes[start].short_period_hz | 0.061 | 0.074 | +0.013 (+21.3 %) |
| modes | modes[start].short_period_zeta | 1.631 | 1.304 | -0.327 (-20.0 %) |
| modes | modes[start].spiral_time_to_half_s | 11.6 | 17.3 | +5.7 (+49.1 %) |
| outside_loop | outside_loop.heading_change_deg | 4.3 | 2.3 | -2 (-46.5 %) |
| outside_loop | outside_loop.height_change_m | -9.1 | -11.9 | -2.8 (-30.8 %) |
| outside_loop | outside_loop.loop_depth_m | 40.3 | 43.7 | +3.4 (+8.4 %) |
| outside_loop | outside_loop.loop_time_s | 5.98 | 5.79 | -0.19 (-3.2 %) |
| outside_loop | outside_loop.max_sideslip_deg | 9.7 | 9.1 | -0.6 (-6.2 %) |
| outside_loop | outside_loop.max_speed_mps | 23.45 | 25.6 | +2.15 (+9.2 %) |
| outside_loop | outside_loop.min_load_factor_g | -3.47 | -3.84 | -0.37 (-10.7 %) |
| outside_loop | outside_loop.min_speed_mps | 16.31 | 17.77 | +1.46 (+9.0 %) |
| pitch_pull | pitch_pull[0.8Vmax].load_factor_at_cl_max | 6.0 | 5.93 | -0.07 (-1.2 %) |
| pitch_pull | pitch_pull[0.8Vmax].peak_alpha_deg | 22.8 | 20.4 | -2.4 (-10.5 %) |
| pitch_pull | pitch_pull[0.8Vmax].peak_load_factor_g | 5.26 | 5.14 | -0.12 (-2.3 %) |
| pitch_pull | pitch_pull[0.8Vmax].peak_pitch_rate_dps | 179.7 | 157.8 | -21.9 (-12.2 %) |
| pitch_pull | pitch_pull[start].load_factor_at_cl_max | 4.92 | 4.86 | -0.06 (-1.2 %) |
| pitch_pull | pitch_pull[start].peak_alpha_deg | 23.0 | 20.7 | -2.3 (-10.0 %) |
| pitch_pull | pitch_pull[start].peak_load_factor_g | 4.32 | 4.22 | -0.1 (-2.3 %) |
| pitch_pull | pitch_pull[start].peak_pitch_rate_dps | 159.9 | 140.2 | -19.7 (-12.3 %) |
| point_roll | point_roll[left].heading_change_deg | 3.3 | 3.7 | +0.4 (+12.1 %) |
| point_roll | point_roll[left].height_change_m | -3.0 | -3.2 | -0.2 (-6.7 %) |
| point_roll | point_roll[left].max_height_deviation_m | 6.8 | 6.9 | +0.1 (+1.5 %) |
| point_roll | point_roll[left].max_sideslip_deg | 20.1 | 19.7 | -0.4 (-2.0 %) |
| point_roll | point_roll[left].over_rotation_point_1_deg | 0.2 | 1.1 | +0.9 (+450.0 %) |
| point_roll | point_roll[left].over_rotation_point_2_deg | 5.2 | 7.2 | +2 (+38.5 %) |
| point_roll | point_roll[left].over_rotation_point_3_deg | 4.1 | 3.6 | -0.5 (-12.2 %) |
| point_roll | point_roll[left].over_rotation_point_4_deg | 4.8 | 4.6 | -0.2 (-4.2 %) |
| point_roll | point_roll[left].peak_push_stick | 0.112 | 0.19 | +0.078 (+69.6 %) |
| point_roll | point_roll[left].peak_rudder_stick | 0.781 | 0.803 | +0.022 (+2.8 %) |
| point_roll | point_roll[left].point_1_elevator_stick | -0.021 | -0.046 | -0.025 (-119.0 %) |
| point_roll | point_roll[left].point_1_rudder_stick | 0.638 | 0.611 | -0.027 (-4.2 %) |
| point_roll | point_roll[left].point_2_elevator_stick | -0.036 | -0.093 | -0.057 (-158.3 %) |
| point_roll | point_roll[left].point_2_rudder_stick | 0.068 | 0.049 | -0.019 (-27.9 %) |
| point_roll | point_roll[left].point_3_elevator_stick | -0.033 | -0.066 | -0.033 (-100.0 %) |
| point_roll | point_roll[left].point_3_rudder_stick | -0.635 | -0.648 | -0.013 (-2.0 %) |
| point_roll | point_roll[right].aileron_saturated_fraction | 0.19 | 0.18 | -0.01 (-5.3 %) |
| point_roll | point_roll[right].exit_bank_deg | -0.8 | -0.9 | -0.1 (-12.5 %) |
| point_roll | point_roll[right].heading_change_deg | -3.1 | -3.5 | -0.4 (-12.9 %) |
| point_roll | point_roll[right].height_change_m | -2.6 | -2.9 | -0.3 (-11.5 %) |
| point_roll | point_roll[right].max_height_deviation_m | 6.4 | 6.3 | -0.1 (-1.6 %) |
| point_roll | point_roll[right].max_sideslip_deg | 19.5 | 19.1 | -0.4 (-2.1 %) |
| point_roll | point_roll[right].over_rotation_point_1_deg | -0.1 | 0.9 | +1 (+1000.0 %) |
| point_roll | point_roll[right].over_rotation_point_2_deg | 2.1 | 3.7 | +1.6 (+76.2 %) |
| point_roll | point_roll[right].over_rotation_point_3_deg | 2.9 | 2.8 | -0.1 (-3.4 %) |
| point_roll | point_roll[right].over_rotation_point_4_deg | 3.6 | 3.5 | -0.1 (-2.8 %) |
| point_roll | point_roll[right].peak_push_stick | 0.106 | 0.179 | +0.073 (+68.9 %) |
| point_roll | point_roll[right].peak_rudder_stick | 0.74 | 0.75 | +0.01 (+1.4 %) |
| point_roll | point_roll[right].point_1_elevator_stick | -0.024 | -0.05 | -0.026 (-108.3 %) |
| point_roll | point_roll[right].point_1_rudder_stick | -0.619 | -0.595 | +0.024 (+3.9 %) |
| point_roll | point_roll[right].point_2_elevator_stick | -0.046 | -0.101 | -0.055 (-119.6 %) |
| point_roll | point_roll[right].point_2_rudder_stick | -0.07 | -0.053 | +0.017 (+24.3 %) |
| point_roll | point_roll[right].point_3_elevator_stick | -0.031 | -0.063 | -0.032 (-103.2 %) |
| point_roll | point_roll[right].point_3_rudder_stick | 0.575 | 0.594 | +0.019 (+3.3 %) |
| roll_rate | roll_rate[0.8Vmax_left].height_change_m | -13.5 | -16.0 | -2.5 (-18.5 %) |
| roll_rate | roll_rate[0.8Vmax_left].max_roll_rate_dps | 190.6 | 188.5 | -2.1 (-1.1 %) |
| roll_rate | roll_rate[0.8Vmax_right].height_change_m | -13.2 | -14.6 | -1.4 (-10.6 %) |
| roll_rate | roll_rate[0.8Vmax_right].max_roll_rate_dps | 196.8 | 200.6 | +3.8 (+1.9 %) |
| roll_rate | roll_rate[0.8Vmax_right].max_sideslip_deg | 10.0 | 9.7 | -0.3 (-3.0 %) |
| roll_rate | roll_rate[0.8Vmax_right].time_to_360_s | 2.15 | 2.1 | -0.05 (-2.3 %) |
| roll_rate | roll_rate[1.3Vs_left].height_change_m | -20.5 | -23.2 | -2.7 (-13.2 %) |
| roll_rate | roll_rate[1.3Vs_right].height_change_m | -18.6 | -19.8 | -1.2 (-6.5 %) |
| roll_rate | roll_rate[1.3Vs_right].max_roll_rate_dps | 178.8 | 181.7 | +2.9 (+1.6 %) |
| roll_rate | roll_rate[1.3Vs_right].max_sideslip_deg | 11.0 | 10.7 | -0.3 (-2.7 %) |
| roll_rate | roll_rate[1.3Vs_right].time_to_360_s | 2.51 | 2.44 | -0.07 (-2.8 %) |
| roll_rate | roll_rate[start_left].height_change_m | -16.8 | -19.5 | -2.7 (-16.1 %) |
| roll_rate | roll_rate[start_left].max_roll_rate_dps | 178.6 | 176.6 | -2 (-1.1 %) |
| roll_rate | roll_rate[start_right].height_change_m | -15.9 | -17.3 | -1.4 (-8.8 %) |
| roll_rate | roll_rate[start_right].max_roll_rate_dps | 186.6 | 189.6 | +3 (+1.6 %) |
| roll_rate | roll_rate[start_right].max_sideslip_deg | 10.5 | 10.2 | -0.3 (-2.9 %) |
| roll_rate | roll_rate[start_right].time_to_360_s | 2.33 | 2.28 | -0.05 (-2.1 %) |
| rudder_step | rudder_step[left].bank_after_2_75_s_deg | -162.8 | -166.9 | -4.1 (-2.5 %) |
| rudder_step | rudder_step[left].pitch_change_deg | -64.1 | -66.3 | -2.2 (-3.4 %) |
| rudder_step | rudder_step[right].bank_after_2_75_s_deg | 159.3 | 161.7 | +2.4 (+1.5 %) |
| rudder_step | rudder_step[right].max_sideslip_deg | 26.7 | 26.3 | -0.4 (-1.5 %) |
| rudder_step | rudder_step[right].pitch_change_deg | -66.2 | -67.9 | -1.7 (-2.6 %) |
| slow_roll | slow_roll[left].heading_change_deg | 0.4 | 1.2 | +0.8 (+200.0 %) |
| slow_roll | slow_roll[left].height_change_m | -4.4 | -4.8 | -0.4 (-9.1 %) |
| slow_roll | slow_roll[left].max_height_deviation_m | 4.7 | 5.0 | +0.3 (+6.4 %) |
| slow_roll | slow_roll[left].max_sideslip_deg | 18.7 | 18.2 | -0.5 (-2.7 %) |
| slow_roll | slow_roll[left].peak_push_stick | 0.091 | 0.155 | +0.064 (+70.3 %) |
| slow_roll | slow_roll[left].peak_rudder_stick | 0.627 | 0.598 | -0.029 (-4.6 %) |
| slow_roll | slow_roll[right].heading_change_deg | 0.8 | -0.1 | -0.9 (-112.5 %) |
| slow_roll | slow_roll[right].height_change_m | -3.8 | -4.2 | -0.4 (-10.5 %) |
| slow_roll | slow_roll[right].max_height_deviation_m | 4.0 | 4.4 | +0.4 (+10.0 %) |
| slow_roll | slow_roll[right].max_sideslip_deg | 17.5 | 17.1 | -0.4 (-2.3 %) |
| slow_roll | slow_roll[right].peak_push_stick | 0.087 | 0.147 | +0.06 (+69.0 %) |
| slow_roll | slow_roll[right].peak_rudder_stick | 0.586 | 0.556 | -0.03 (-5.1 %) |
| snap_roll | snap_roll[left].alpha_before_45_deg_of_roll_deg | 23.5 | 21.9 | -1.6 (-6.8 %) |
| snap_roll | snap_roll[left].heading_change_at_stop_deg | -15.6 | 3.5 | +19.1 (+122.4 %) |
| snap_roll | snap_roll[left].height_lost_m | 44.6 | 53.9 | +9.3 (+20.9 %) |
| snap_roll | snap_roll[left].max_alpha_deg | 23.5 | 23.2 | -0.3 (-1.3 %) |
| snap_roll | snap_roll[left].mean_roll_rate_dps | 180.7 | 199.5 | +18.8 (+10.4 %) |
| snap_roll | snap_roll[left].mean_yaw_rate_dps | 67.2 | 73.8 | +6.6 (+9.8 %) |
| snap_roll | snap_roll[left].peak_load_factor_g | 3.36 | 3.18 | -0.18 (-5.4 %) |
| snap_roll | snap_roll[left].peak_roll_rate_dps | 312.2 | 327.7 | +15.5 (+5.0 %) |
| snap_roll | snap_roll[left].stop_after_deg | 485.6 | 546.0 | +60.4 (+12.4 %) |
| snap_roll | snap_roll[left].stop_error_deg | 125.6 | 186.0 | +60.4 (+48.1 %) |
| snap_roll | snap_roll[left].time_to_level_s | 2.02 | 1.95 | -0.07 (-3.5 %) |
| snap_roll | snap_roll[left].time_to_release_s | 1.82 | 1.63 | -0.19 (-10.4 %) |
| snap_roll | snap_roll[right].alpha_before_45_deg_of_roll_deg | 24.0 | 22.6 | -1.4 (-5.8 %) |
| snap_roll | snap_roll[right].autorotation_short_of_finish_deg | 68.7 | 0.0 | -68.7 (-100.0 %) |
| snap_roll | snap_roll[right].exit_bank_deg | 0.1 | 0.0 | -0.1 (-100.0 %) |
| snap_roll | snap_roll[right].heading_change_at_stop_deg | 13.9 | 9.9 | -4 (-28.8 %) |
| snap_roll | snap_roll[right].height_lost_m | 19.2 | 15.4 | -3.8 (-19.8 %) |
| snap_roll | snap_roll[right].max_alpha_deg | 26.2 | 25.9 | -0.3 (-1.1 %) |
| snap_roll | snap_roll[right].mean_roll_rate_dps | 197.5 | 212.0 | +14.5 (+7.3 %) |
| snap_roll | snap_roll[right].peak_roll_rate_dps | 339.5 | 354.3 | +14.8 (+4.4 %) |
| snap_roll | snap_roll[right].release_after_deg | 291.3 | 322.4 | +31.1 (+10.7 %) |
| snap_roll | snap_roll[right].release_reason | autorotation ended | finish point |  |
| snap_roll | snap_roll[right].stop_after_deg | 344.1 | 384.6 | +40.5 (+11.8 %) |
| snap_roll | snap_roll[right].stop_error_deg | -15.9 | 24.6 | +40.5 (+254.7 %) |
| snap_roll | snap_roll[right].time_to_level_s | 1.41 | 1.45 | +0.04 (+2.8 %) |
| snap_roll | snap_roll[right].time_to_release_s | 1.47 | 1.52 | +0.05 (+3.4 %) |
| snap_roll | snap_roll[right].yaw_to_roll_ratio | 0.464 | 0.43 | -0.034 (-7.3 %) |
| spin | spin[left].height_lost_per_turn_m | 26.4 | 23.6 | -2.8 (-10.6 %) |
| spin | spin[left].recovery_time_s | 0.4 | 0.36 | -0.04 (-10.0 %) |
| spin | spin[left].steady_turn_time_s | 1.36 | 1.27 | -0.09 (-6.6 %) |
| spin | spin[left].total_height_lost_m | 123.6 | 121.8 | -1.8 (-1.5 %) |
| spin | spin[left].turns_in_6_s | 2.78 | 3.02 | +0.24 (+8.6 %) |
| spin | spin[right].height_lost_per_turn_m | 26.5 | 21.1 | -5.4 (-20.4 %) |
| spin | spin[right].max_alpha_deg | 28.3 | 26.9 | -1.4 (-4.9 %) |
| spin | spin[right].recovery_time_s | 0.29 | 0.27 | -0.02 (-6.9 %) |
| spin | spin[right].recovery_turns | 0.25 | 0.28 | +0.03 (+12.0 %) |
| spin | spin[right].steady_turn_time_s | 1.3 | 1.03 | -0.27 (-20.8 %) |
| spin | spin[right].total_height_lost_m | 123.5 | 120.2 | -3.3 (-2.7 %) |
| spin | spin[right].turns_in_6_s | 2.83 | 3.6 | +0.77 (+27.2 %) |
| spin_inverted | spin_inverted[left].height_lost_per_turn_m | 27.6 | 30.3 | +2.7 (+9.8 %) |
| spin_inverted | spin_inverted[left].min_alpha_deg | -21.9 | -18.7 | +3.2 (+14.6 %) |
| spin_inverted | spin_inverted[left].recovery_time_s | 0.3 | 0.27 | -0.03 (-10.0 %) |
| spin_inverted | spin_inverted[left].recovery_turns | 0.16 | 0.15 | -0.01 (-6.3 %) |
| spin_inverted | spin_inverted[left].steady_turn_time_s | 1.18 | 1.1 | -0.08 (-6.8 %) |
| spin_inverted | spin_inverted[left].total_height_lost_m | 150.9 | 176.7 | +25.8 (+17.1 %) |
| spin_inverted | spin_inverted[left].turns_in_6_s | 3.68 | 4.05 | +0.37 (+10.1 %) |
| spin_inverted | spin_inverted[right].height_lost_per_turn_m | 26.2 | 29.4 | +3.2 (+12.2 %) |
| spin_inverted | spin_inverted[right].min_alpha_deg | -23.8 | -21.7 | +2.1 (+8.8 %) |
| spin_inverted | spin_inverted[right].recovery_time_s | 0.27 | 0.25 | -0.02 (-7.4 %) |
| spin_inverted | spin_inverted[right].recovery_turns | 0.15 | 0.13 | -0.02 (-13.3 %) |
| spin_inverted | spin_inverted[right].steady_turn_time_s | 1.14 | 1.1 | -0.04 (-3.5 %) |
| spin_inverted | spin_inverted[right].total_height_lost_m | 134.3 | 151.4 | +17.1 (+12.7 %) |
| spin_inverted | spin_inverted[right].turns_in_6_s | 3.63 | 3.75 | +0.12 (+3.3 %) |
| split_s | split_s.exit_bank_deg | -0.3 | 0.0 | +0.3 (+100.0 %) |
| split_s | split_s.exit_speed_mps | 24.11 | 25.22 | +1.11 (+4.6 %) |
| split_s | split_s.heading_error_deg | -6.2 | -2.9 | +3.3 (+53.2 %) |
| split_s | split_s.height_lost_m | 31.9 | 34.3 | +2.4 (+7.5 %) |
| split_s | split_s.height_lost_to_level_m | 31.6 | 34.1 | +2.5 (+7.9 %) |
| split_s | split_s.max_sideslip_deg | 9.1 | 8.3 | -0.8 (-8.8 %) |
| split_s | split_s.max_speed_mps | 24.67 | 25.68 | +1.01 (+4.1 %) |
| split_s | split_s.time_to_level_s | 3.79 | 3.83 | +0.04 (+1.1 %) |
| stall_inverted | stall_inverted.altitude_lost_m | 17.7 | – | added/removed |
| stall_inverted | stall_inverted.break_kind | wing drop or sink | – | added/removed |
| stall_inverted | stall_inverted.ratio_to_upright_vs | 1.195 | – | added/removed |
| stall_inverted | stall_inverted.recovery_time_s | 2.36 | – | added/removed |
| stall_inverted | stall_inverted.roll_off_in_1_s_deg | -111.1 | – | added/removed |
| stall_inverted | stall_inverted.stall_alpha_deg | -13.9 | – | added/removed |
| stall_inverted | stall_inverted.stall_speed_mps | 10.78 | – | added/removed |
| stall_power_on | stall_power_on.altitude_lost_m | 4.6 | 5.7 | +1.1 (+23.9 %) |
| stall_power_on | stall_power_on.bank_in_first_second_deg | -89.5 | -86.1 | +3.4 (+3.8 %) |
| stall_power_on | stall_power_on.deceleration_before_break_mps2 | 0.87 | 0.88 | +0.01 (+1.1 %) |
| stall_power_on | stall_power_on.max_bank_in_recovery_deg | 89.5 | 86.1 | -3.4 (-3.8 %) |
| stall_power_on | stall_power_on.ratio_to_cl_max_estimate | 0.737 | 0.754 | +0.017 (+2.3 %) |
| stall_power_on | stall_power_on.stall_speed_mps | 6.65 | 6.84 | +0.19 (+2.9 %) |
| takeoff | takeoff.ground_roll_m | 18.6 | 19.0 | +0.4 (+2.2 %) |
| takeoff | takeoff.liftoff_speed_mps | 15.51 | 15.79 | +0.28 (+1.8 %) |
| takeoff | takeoff.liftoff_speed_vs | 1.72 | 1.74 | +0.02 (+1.2 %) |
| takeoff | takeoff.max_rudder_stick | 0.04 | 0.05 | +0.01 (+25.0 %) |
| takeoff | takeoff.rudder_free_heading_change_3_s_deg | 2.1 | 2.0 | -0.1 (-4.8 %) |
| throttle_response | throttle_response.spool_down_90_10_s | 3.275 | 3.313 | +0.038 (+1.2 %) |
| throttle_response | throttle_response.spool_up_10_90_s | 2.071 | 2.092 | +0.021 (+1.0 %) |
| trim_sweep | trim_sweep[x0.90].alpha_deg | 2.11 | 2.18 | +0.07 (+3.3 %) |
| trim_sweep | trim_sweep[x0.90].stick_pitch | 0.046 | 0.097 | +0.051 (+110.9 %) |
| trim_sweep | trim_sweep[x0.95].alpha_deg | 1.76 | 1.82 | +0.06 (+3.4 %) |
| trim_sweep | trim_sweep[x0.95].stick_pitch | 0.04 | 0.087 | +0.047 (+117.5 %) |
| trim_sweep | trim_sweep[x1.00].alpha_deg | 1.46 | 1.51 | +0.05 (+3.4 %) |
| trim_sweep | trim_sweep[x1.00].stick_pitch | 0.036 | 0.078 | +0.042 (+116.7 %) |
| trim_sweep | trim_sweep[x1.05].alpha_deg | 1.2 | 1.25 | +0.05 (+4.2 %) |
| trim_sweep | trim_sweep[x1.05].stick_pitch | 0.032 | 0.07 | +0.038 (+118.8 %) |
| trim_sweep | trim_sweep[x1.10].alpha_deg | 0.98 | 1.02 | +0.04 (+4.1 %) |
| trim_sweep | trim_sweep[x1.10].stick_pitch | 0.029 | 0.064 | +0.035 (+120.7 %) |
| trim_sweep | trim_sweep[x1.15].alpha_deg | 0.78 | 0.82 | +0.04 (+5.1 %) |
| trim_sweep | trim_sweep[x1.15].stick_pitch | 0.026 | 0.058 | +0.032 (+123.1 %) |
| trim_sweep | trim_sweep[x1.20].alpha_deg | 0.61 | 0.65 | +0.04 (+6.6 %) |
| trim_sweep | trim_sweep[x1.20].stick_pitch | 0.024 | 0.053 | +0.029 (+120.8 %) |
| trim_sweep | trim_sweep[x1.25].alpha_deg | 0.46 | 0.49 | +0.03 (+6.5 %) |
| trim_sweep | trim_sweep[x1.25].stick_pitch | 0.022 | 0.049 | +0.027 (+122.7 %) |
| trim_sweep | trim_sweep[x1.30].alpha_deg | 0.32 | 0.35 | +0.03 (+9.4 %) |
| trim_sweep | trim_sweep[x1.30].stick_pitch | 0.02 | 0.045 | +0.025 (+125.0 %) |
| trim_sweep | trim_sweep[x1.35].alpha_deg | 0.2 | 0.23 | +0.03 (+15.0 %) |
| trim_sweep | trim_sweep[x1.35].stick_pitch | 0.018 | 0.042 | +0.024 (+133.3 %) |
| vmax | vmax.height_error_end_m | 0.11 | 0.04 | -0.07 (-63.6 %) |
| vmax | vmax.height_error_run_m | 0.25 | 0.23 | -0.02 (-8.0 %) |
| vmax | vmax.initial_acceleration_mps2 | 2.67 | 2.64 | -0.03 (-1.1 %) |
| vmax | vmax.time_to_90_percent_s | 3.22 | 3.28 | +0.06 (+1.9 %) |

**1485 change(s) beyond tolerance.**
