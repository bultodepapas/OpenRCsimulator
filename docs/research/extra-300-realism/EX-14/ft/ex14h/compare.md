# Flight-test comparison

Baseline `production`, candidate `candidate`; tolerance max(0.01, 0.01 × |baseline|).

Card ft-card-v5 → ft-card-v5; commit 3bfdc64f5a → 3bfdc64f5a.

## Great Planes Extra 300S .60 — 207 change(s)

Aircraft data changed between the runs.

| Test | Value | Baseline | Candidate | Change |
| --- | --- | --- | --- | --- |
| aero_sweep | aero_sweep[alpha_15].cd | 0.1031 | 0.1377 | +0.0346 (+33.6 %) |
| aero_sweep | aero_sweep[alpha_15].cd_local | 0.1031 | 0.1377 | +0.0346 (+33.6 %) |
| aero_sweep | aero_sweep[alpha_15].cl_lift | 0.9558 | 0.9729 | +0.0171 (+1.8 %) |
| aero_sweep | aero_sweep[alpha_15].cl_lift_local | 0.9558 | 0.9729 | +0.0171 (+1.8 %) |
| aero_sweep | aero_sweep[alpha_20].cl_lift | 0.5401 | 1.035 | +0.4949 (+91.6 %) |
| aero_sweep | aero_sweep[alpha_20].cl_lift_local | 0.5401 | 1.035 | +0.4949 (+91.6 %) |
| aero_sweep | aero_sweep[alpha_20].cm | -0.3764 | -0.349 | +0.0274 (+7.3 %) |
| aero_sweep | aero_sweep[alpha_20].cm_local | -0.3764 | -0.349 | +0.0274 (+7.3 %) |
| aero_sweep | aero_sweep[alpha_30].cl_lift | 0.6211 | 0.891 | +0.2699 (+43.5 %) |
| aero_sweep | aero_sweep[alpha_30].cl_lift_local | 0.6211 | 0.891 | +0.2699 (+43.5 %) |
| aero_sweep | aero_sweep[alpha_30].cm | -0.261 | -0.2217 | +0.0393 (+15.1 %) |
| aero_sweep | aero_sweep[alpha_30].cm_local | -0.261 | -0.2217 | +0.0393 (+15.1 %) |
| dead_stick_landing | dead_stick_landing.flare_height_m | 1.83 | 1.81 | -0.02 (-1.1 %) |
| dead_stick_landing | dead_stick_landing.glide_path_deg | 6.8 | 6.7 | -0.1 (-1.5 %) |
| dead_stick_landing | dead_stick_landing.glide_sink_mps | 1.83 | 1.81 | -0.02 (-1.1 %) |
| dead_stick_landing | dead_stick_landing.touchdown_past_aim_m | 13.9 | 13.7 | -0.2 (-1.4 %) |
| engine_cut_climb | engine_cut_climb[delay_1s].alpha_margin_to_stall_deg | 5.1 | 5.0 | -0.1 (-2.0 %) |
| engine_cut_climb | engine_cut_climb[delay_1s].height_change_10_s_m | -5.1 | -5.0 | +0.1 (+2.0 %) |
| engine_cut_climb | engine_cut_climb[delay_1s].max_alpha_deg | 8.2 | 8.3 | +0.1 (+1.2 %) |
| engine_cut_climb | engine_cut_climb[delay_2s].alpha_margin_to_stall_deg | 1.9 | 1.7 | -0.2 (-10.5 %) |
| engine_cut_climb | engine_cut_climb[delay_2s].min_speed_mps | 8.76 | 8.67 | -0.09 (-1.0 %) |
| glide | glide.best.pitch_deg | 4.0 | 4.1 | +0.1 (+2.5 %) |
| glide | glide[1.3Vs].pitch_deg | 4.0 | 4.1 | +0.1 (+2.5 %) |
| glide | glide[1.6Vs].path_angle_deg | -5.4 | -5.3 | +0.1 (+1.9 %) |
| glide | glide[1.6Vs].pitch_deg | 0.2 | 0.3 | +0.1 (+50.0 %) |
| glide | glide[1.6Vs].vertical_speed_mps | -1.66 | -1.64 | +0.02 (+1.2 %) |
| glide | glide[2.0Vs].path_angle_deg | -7.8 | -7.7 | +0.1 (+1.3 %) |
| glide | glide[2.0Vs].pitch_deg | -4.3 | -4.2 | +0.1 (+2.3 %) |
| glide | glide[2.0Vs].vertical_speed_mps | -3.02 | -2.97 | +0.05 (+1.7 %) |
| glide_turn | glide_turn.least_height_lost_180_m | 14.7 | 14.5 | -0.2 (-1.4 %) |
| glide_turn | glide_turn[30deg].height_lost_180_m | 17.2 | 17.0 | -0.2 (-1.2 %) |
| glide_turn | glide_turn[30deg].height_lost_360_m | 34.6 | 34.2 | -0.4 (-1.2 %) |
| glide_turn | glide_turn[30deg].radius_m | 41.6 | 41.1 | -0.5 (-1.2 %) |
| glide_turn | glide_turn[45deg].height_lost_180_m | 14.7 | 14.5 | -0.2 (-1.4 %) |
| glide_turn | glide_turn[45deg].height_lost_360_m | 29.4 | 29.0 | -0.4 (-1.4 %) |
| glide_turn | glide_turn[45deg].radius_m | 28.6 | 28.3 | -0.3 (-1.0 %) |
| glide_turn | glide_turn[60deg].height_lost_180_m | 17.8 | 17.5 | -0.3 (-1.7 %) |
| glide_turn | glide_turn[60deg].height_lost_360_m | 32.9 | 32.5 | -0.4 (-1.2 %) |
| glide_turn | glide_turn[60deg].radius_m | 23.4 | 23.1 | -0.3 (-1.3 %) |
| glide_turn | glide_turn[60deg].straight_sink_mps | 2.78 | 2.75 | -0.03 (-1.1 %) |
| go_around | go_around[fast].min_wheel_height_m | 0.98 | 1.0 | +0.02 (+2.0 %) |
| go_around | go_around[slow].min_wheel_height_m | 0.42 | 0.44 | +0.02 (+4.8 %) |
| landing | landing.touchdown_pitch_deg | 6.4 | 6.5 | +0.1 (+1.6 %) |
| loop | loop.heading_change_deg | -1.7 | -1.8 | -0.1 (-5.9 %) |
| loop | loop.max_load_factor_g | 7.34 | 7.22 | -0.12 (-1.6 %) |
| modes | modes[1.3Vs].spiral_time_to_double_s | 4.2 | 4.1 | -0.1 (-2.4 %) |
| pitch_pull | pitch_pull[0.8Vmax].load_factor_at_cl_max | 8.82 | 8.91 | +0.09 (+1.0 %) |
| pitch_pull | pitch_pull[0.8Vmax].peak_alpha_deg | 24.5 | 24.1 | -0.4 (-1.6 %) |
| pitch_pull | pitch_pull[0.8Vmax].peak_load_factor_g | 8.03 | 7.75 | -0.28 (-3.5 %) |
| pitch_pull | pitch_pull[start].load_factor_at_cl_max | 3.92 | 3.97 | +0.05 (+1.3 %) |
| pitch_pull | pitch_pull[start].peak_load_factor_g | 3.58 | 3.47 | -0.11 (-3.1 %) |
| roll_rate | roll_rate[1.3Vs_left].height_change_m | -17.0 | -17.2 | -0.2 (-1.2 %) |
| roll_rate | roll_rate[1.3Vs_left].max_sideslip_deg | 7.4 | 7.5 | +0.1 (+1.4 %) |
| roll_rate | roll_rate[1.3Vs_right].height_change_m | -16.8 | -17.0 | -0.2 (-1.2 %) |
| snap_roll | snap_roll[left].alpha_before_45_deg_of_roll_deg | 27.8 | 28.5 | +0.7 (+2.5 %) |
| snap_roll | snap_roll[left].autorotation_short_of_finish_deg | 122.9 | 0.0 | -122.9 (-100.0 %) |
| snap_roll | snap_roll[left].heading_change_at_stop_deg | 18.2 | -17.5 | -35.7 (-196.2 %) |
| snap_roll | snap_roll[left].height_lost_m | 39.8 | 24.1 | -15.7 (-39.4 %) |
| snap_roll | snap_roll[left].max_alpha_deg | 27.8 | 28.5 | +0.7 (+2.5 %) |
| snap_roll | snap_roll[left].mean_roll_rate_dps | 145.2 | 167.4 | +22.2 (+15.3 %) |
| snap_roll | snap_roll[left].mean_yaw_rate_dps | 75.7 | 78.5 | +2.8 (+3.7 %) |
| snap_roll | snap_roll[left].peak_load_factor_g | 2.49 | 2.2 | -0.29 (-11.6 %) |
| snap_roll | snap_roll[left].peak_roll_rate_dps | 191.8 | 236.0 | +44.2 (+23.0 %) |
| snap_roll | snap_roll[left].release_after_deg | 237.1 | 340.3 | +103.2 (+43.5 %) |
| snap_roll | snap_roll[left].release_reason | autorotation ended | finish point |  |
| snap_roll | snap_roll[left].stop_after_deg | 237.7 | 356.3 | +118.6 (+49.9 %) |
| snap_roll | snap_roll[left].stop_error_deg | -122.3 | -3.7 | +118.6 (+97.0 %) |
| snap_roll | snap_roll[left].time_to_level_s | 2.72 | 2.03 | -0.69 (-25.4 %) |
| snap_roll | snap_roll[left].time_to_release_s | 1.63 | 2.03 | +0.4 (+24.5 %) |
| snap_roll | snap_roll[left].yaw_to_roll_ratio | 0.521 | 0.469 | -0.052 (-10.0 %) |
| snap_roll | snap_roll[right].alpha_before_45_deg_of_roll_deg | 27.7 | 29.0 | +1.3 (+4.7 %) |
| snap_roll | snap_roll[right].autorotation_short_of_finish_deg | 84.2 | 69.0 | -15.2 (-18.1 %) |
| snap_roll | snap_roll[right].heading_change_at_stop_deg | 1.0 | -4.5 | -5.5 (-550.0 %) |
| snap_roll | snap_roll[right].height_lost_m | 32.1 | 26.2 | -5.9 (-18.4 %) |
| snap_roll | snap_roll[right].max_alpha_deg | 27.7 | 29.0 | +1.3 (+4.7 %) |
| snap_roll | snap_roll[right].mean_roll_rate_dps | 164.7 | 169.9 | +5.2 (+3.2 %) |
| snap_roll | snap_roll[right].mean_yaw_rate_dps | 82.2 | 81.0 | -1.2 (-1.5 %) |
| snap_roll | snap_roll[right].peak_load_factor_g | 2.18 | 2.24 | +0.06 (+2.8 %) |
| snap_roll | snap_roll[right].peak_roll_rate_dps | 252.1 | 229.3 | -22.8 (-9.0 %) |
| snap_roll | snap_roll[right].release_after_deg | 275.8 | 291.0 | +15.2 (+5.5 %) |
| snap_roll | snap_roll[right].stop_after_deg | 276.9 | 301.5 | +24.6 (+8.9 %) |
| snap_roll | snap_roll[right].stop_error_deg | -83.1 | -58.5 | +24.6 (+29.6 %) |
| snap_roll | snap_roll[right].time_to_level_s | 2.55 | 2.16 | -0.39 (-15.3 %) |
| snap_roll | snap_roll[right].time_to_release_s | 1.68 | 1.71 | +0.03 (+1.8 %) |
| snap_roll | snap_roll[right].yaw_to_roll_ratio | 0.499 | 0.477 | -0.022 (-4.4 %) |
| spin | spin[left].height_lost_per_turn_m | 30.4 | 31.1 | +0.7 (+2.3 %) |
| spin | spin[left].max_alpha_deg | 29.8 | 31.9 | +2.1 (+7.0 %) |
| spin | spin[left].recovery_time_s | 0.25 | 0.53 | +0.28 (+112.0 %) |
| spin | spin[left].recovery_turns | 0.19 | 0.13 | -0.06 (-31.6 %) |
| spin | spin[left].steady_turn_time_s | 1.43 | 1.7 | +0.27 (+18.9 %) |
| spin | spin[left].total_height_lost_m | 136.3 | 124.1 | -12.2 (-9.0 %) |
| spin | spin[left].turns_in_6_s | 2.91 | 2.48 | -0.43 (-14.8 %) |
| spin | spin[right].height_lost_per_turn_m | 26.2 | 35.5 | +9.3 (+35.5 %) |
| spin | spin[right].max_alpha_deg | 29.2 | 31.6 | +2.4 (+8.2 %) |
| spin | spin[right].recovery_time_s | 0.62 | 0.5 | -0.12 (-19.4 %) |
| spin | spin[right].recovery_turns | 0.24 | 0.12 | -0.12 (-50.0 %) |
| spin | spin[right].steady_turn_time_s | 1.21 | 1.85 | +0.64 (+52.9 %) |
| spin | spin[right].total_height_lost_m | 146.9 | 127.5 | -19.4 (-13.2 %) |
| spin | spin[right].turns_in_6_s | 3.39 | 2.28 | -1.11 (-32.7 %) |
| spin_inverted | spin_inverted[left].height_lost_per_turn_m | 25.4 | 27.7 | +2.3 (+9.1 %) |
| spin_inverted | spin_inverted[left].min_alpha_deg | -26.1 | -25.7 | +0.4 (+1.5 %) |
| spin_inverted | spin_inverted[left].recovery_turns | 0.19 | 0.13 | -0.06 (-31.6 %) |
| spin_inverted | spin_inverted[left].steady_turn_time_s | 1.02 | 1.19 | +0.17 (+16.7 %) |
| spin_inverted | spin_inverted[left].total_height_lost_m | 156.1 | 145.1 | -11 (-7.0 %) |
| spin_inverted | spin_inverted[left].turns_in_6_s | 4.38 | 3.66 | -0.72 (-16.4 %) |
| spin_inverted | spin_inverted[right].recovery_turns | 0.19 | 0.15 | -0.04 (-21.1 %) |
| spin_inverted | spin_inverted[right].steady_turn_time_s | 1.06 | 1.12 | +0.06 (+5.7 %) |
| spin_inverted | spin_inverted[right].total_height_lost_m | 165.7 | 173.0 | +7.3 (+4.4 %) |
| spin_inverted | spin_inverted[right].turns_in_6_s | 4.42 | 4.32 | -0.1 (-2.3 %) |
| stall_cross_controlled | stall_cross_controlled[left].altitude_lost_m | 34.6 | 38.5 | +3.9 (+11.3 %) |
| stall_cross_controlled | stall_cross_controlled[left].bank_at_break_deg | -40.3 | -25.5 | +14.8 (+36.7 %) |
| stall_cross_controlled | stall_cross_controlled[left].max_bank_in_recovery_deg | 98.0 | 44.0 | -54 (-55.1 %) |
| stall_cross_controlled | stall_cross_controlled[left].recovery_time_s | 4.02 | 4.95 | +0.93 (+23.1 %) |
| stall_cross_controlled | stall_cross_controlled[left].roll_off | inside | outside |  |
| stall_cross_controlled | stall_cross_controlled[left].roll_off_in_1_s_deg | -57.7 | 26.4 | +84.1 (+145.8 %) |
| stall_cross_controlled | stall_cross_controlled[left].stall_alpha_deg | 22.4 | 23.3 | +0.9 (+4.0 %) |
| stall_cross_controlled | stall_cross_controlled[right].altitude_lost_m | 32.6 | 36.9 | +4.3 (+13.2 %) |
| stall_cross_controlled | stall_cross_controlled[right].bank_at_break_deg | 40.2 | 25.1 | -15.1 (-37.6 %) |
| stall_cross_controlled | stall_cross_controlled[right].max_bank_in_recovery_deg | 91.8 | 38.4 | -53.4 (-58.2 %) |
| stall_cross_controlled | stall_cross_controlled[right].recovery_time_s | 3.9 | 4.78 | +0.88 (+22.6 %) |
| stall_cross_controlled | stall_cross_controlled[right].roll_off | inside | outside |  |
| stall_cross_controlled | stall_cross_controlled[right].roll_off_in_1_s_deg | 51.6 | -28.2 | -79.8 (-154.7 %) |
| stall_cross_controlled | stall_cross_controlled[right].stall_alpha_deg | 22.0 | 23.0 | +1 (+4.5 %) |
| stall_held | stall_held[controls_neutral].heading_change_held_deg | -1484.9 | 506.6 | +1992 (+134.1 %) |
| stall_held | stall_held[controls_neutral].height_lost_held_m | 81.5 | 63.6 | -17.9 (-22.0 %) |
| stall_held | stall_held[controls_neutral].height_lost_to_recovery_m | 132.6 | 92.6 | -40 (-30.2 %) |
| stall_held | stall_held[controls_neutral].max_bank_held_deg | 179.4 | 105.4 | -74 (-41.2 %) |
| stall_held | stall_held[controls_neutral].max_rotation_rate_dps | 432.3 | 149.8 | -282.5 (-65.3 %) |
| stall_held | stall_held[controls_neutral].recovery_time_s | 2.7 | 2.02 | -0.68 (-25.2 %) |
| stall_held | stall_held[controls_neutral].rotation_rate_last_2_s_dps | 408.5 | 138.2 | -270.3 (-66.2 %) |
| stall_held | stall_held[wings_level].heading_change_held_deg | -765.9 | 253.5 | +1019 (+133.1 %) |
| stall_held | stall_held[wings_level].height_lost_held_m | 84.5 | 37.8 | -46.7 (-55.3 %) |
| stall_held | stall_held[wings_level].height_lost_to_recovery_m | 127.8 | 54.1 | -73.7 (-57.7 %) |
| stall_held | stall_held[wings_level].max_bank_held_deg | 145.3 | 57.3 | -88 (-60.6 %) |
| stall_held | stall_held[wings_level].max_rotation_rate_dps | 206.3 | 71.9 | -134.4 (-65.1 %) |
| stall_held | stall_held[wings_level].outcome | spin entry | wing drop |  |
| stall_held | stall_held[wings_level].recovery_time_s | 2.17 | 2.11 | -0.06 (-2.8 %) |
| stall_held | stall_held[wings_level].rotation_rate_last_2_s_dps | 189.8 | 67.7 | -122.1 (-64.3 %) |
| stall_inverted | stall_inverted.altitude_lost_m | 26.1 | 25.3 | -0.8 (-3.1 %) |
| stall_inverted | stall_inverted.recovery_time_s | 3.2 | 2.95 | -0.25 (-7.8 %) |
| stall_inverted | stall_inverted.roll_off_in_1_s_deg | -136.8 | -105.8 | +31 (+22.7 %) |
| stall_inverted | stall_inverted.stall_alpha_deg | -16.1 | -16.8 | -0.7 (-4.3 %) |
| stall_inverted | stall_inverted.stall_speed_mps | 11.67 | 11.51 | -0.16 (-1.4 %) |
| stall_power_off | stall_power_off.altitude_lost_m | 41.2 | 38.7 | -2.5 (-6.1 %) |
| stall_power_off | stall_power_off.bank_in_first_second_deg | -76.0 | 13.8 | +89.8 (+118.2 %) |
| stall_power_off | stall_power_off.deceleration_before_break_mps2 | 0.48 | 0.38 | -0.1 (-20.8 %) |
| stall_power_off | stall_power_off.max_bank_in_recovery_deg | 76.0 | 13.8 | -62.2 (-81.8 %) |
| stall_power_off | stall_power_off.recovery_time_s | 4.6 | 4.17 | -0.43 (-9.3 %) |
| stall_power_off | stall_power_off.stall_alpha_deg | 21.1 | 23.5 | +2.4 (+11.4 %) |
| stall_power_off | stall_power_off.wing_drop | left | right |  |
| stall_power_on | stall_power_on.altitude_lost_m | 19.0 | 18.6 | -0.4 (-2.1 %) |
| stall_power_on | stall_power_on.bank_in_first_second_deg | -70.8 | -45.1 | +25.7 (+36.3 %) |
| stall_power_on | stall_power_on.deceleration_before_break_mps2 | 1.07 | 1.01 | -0.06 (-5.6 %) |
| stall_power_on | stall_power_on.max_bank_in_recovery_deg | 70.8 | 45.1 | -25.7 (-36.3 %) |
| stall_power_on | stall_power_on.ratio_to_cl_max_estimate | 0.909 | 0.883 | -0.026 (-2.9 %) |
| stall_power_on | stall_power_on.recovery_time_s | 4.52 | 3.99 | -0.53 (-11.7 %) |
| stall_power_on | stall_power_on.stall_alpha_deg | 20.2 | 23.0 | +2.8 (+13.9 %) |
| stall_power_on | stall_power_on.stall_speed_mps | 10.01 | 9.73 | -0.28 (-2.8 %) |
| stall_turn | stall_turn[left_0.35Vs].kick_speed_mps | 3.88 | 3.84 | -0.04 (-1.0 %) |
| stall_turn | stall_turn[left_0.35Vs].pitch_during_pivot_deg | 116.1 | 113.7 | -2.4 (-2.1 %) |
| stall_turn | stall_turn[left_0.35Vs].pivot_radius_m | 2.72 | 2.76 | +0.04 (+1.5 %) |
| stall_turn | stall_turn[left_0.35Vs].pivot_radius_spans | 1.68 | 1.7 | +0.02 (+1.2 %) |
| stall_turn | stall_turn[left_0.6Vs].height_lost_top_to_level_m | 177.4 | 174.9 | -2.5 (-1.4 %) |
| stall_turn | stall_turn[left_0.6Vs].min_forward_speed_mps | -4.53 | -4.58 | -0.05 (-1.1 %) |
| stall_turn | stall_turn[left_0.6Vs].pitch_during_pivot_deg | 82.3 | 84.9 | +2.6 (+3.2 %) |
| stall_turn | stall_turn[left_0.6Vs].pivot_radius_m | 30.15 | 29.55 | -0.6 (-2.0 %) |
| stall_turn | stall_turn[left_0.6Vs].pivot_radius_spans | 18.55 | 18.18 | -0.37 (-2.0 %) |
| stall_turn | stall_turn[left_0.6Vs].torque_off_deg | 221.1 | 242.0 | +20.9 (+9.5 %) |
| stall_turn | stall_turn[right_0.35Vs].kick_speed_mps | 3.88 | 3.84 | -0.04 (-1.0 %) |
| stall_turn | stall_turn[right_0.35Vs].pitch_during_pivot_deg | 119.3 | 116.2 | -3.1 (-2.6 %) |
| stall_turn | stall_turn[right_0.35Vs].torque_off_deg | 125.8 | 127.2 | +1.4 (+1.1 %) |
| stall_turn | stall_turn[right_0.6Vs].min_forward_speed_mps | -0.09 | -0.14 | -0.05 (-55.6 %) |
| stall_turn | stall_turn[right_0.6Vs].pitch_during_pivot_deg | 99.5 | 96.9 | -2.6 (-2.6 %) |
| stall_turn | stall_turn[right_0.6Vs].torque_off_deg | 68.1 | 64.5 | -3.6 (-5.3 %) |
| stall_turning | stall_turning[30_left].altitude_lost_m | 33.3 | 27.5 | -5.8 (-17.4 %) |
| stall_turning | stall_turning[30_left].bank_at_break_deg | -50.2 | -41.7 | +8.5 (+16.9 %) |
| stall_turning | stall_turning[30_left].max_bank_in_recovery_deg | 107.8 | 60.3 | -47.5 (-44.1 %) |
| stall_turning | stall_turning[30_left].recovery_time_s | 3.91 | 3.5 | -0.41 (-10.5 %) |
| stall_turning | stall_turning[30_left].roll_off | inside | outside |  |
| stall_turning | stall_turning[30_left].roll_off_in_1_s_deg | -57.6 | 36.3 | +93.9 (+163.0 %) |
| stall_turning | stall_turning[30_left].stall_alpha_deg | 20.6 | 22.3 | +1.7 (+8.3 %) |
| stall_turning | stall_turning[30_right].altitude_lost_m | 28.6 | 25.3 | -3.3 (-11.5 %) |
| stall_turning | stall_turning[30_right].bank_at_break_deg | 50.2 | 36.6 | -13.6 (-27.1 %) |
| stall_turning | stall_turning[30_right].max_bank_in_recovery_deg | 99.6 | 47.2 | -52.4 (-52.6 %) |
| stall_turning | stall_turning[30_right].recovery_time_s | 3.61 | 3.49 | -0.12 (-3.3 %) |
| stall_turning | stall_turning[30_right].roll_off | inside | outside |  |
| stall_turning | stall_turning[30_right].roll_off_in_1_s_deg | 49.4 | -33.8 | -83.2 (-168.4 %) |
| stall_turning | stall_turning[30_right].stall_alpha_deg | 20.2 | 22.1 | +1.9 (+9.4 %) |
| stall_turning | stall_turning[45_left].altitude_lost_m | 29.7 | 21.0 | -8.7 (-29.3 %) |
| stall_turning | stall_turning[45_left].bank_at_break_deg | -65.4 | -54.5 | +10.9 (+16.7 %) |
| stall_turning | stall_turning[45_left].max_bank_in_recovery_deg | 122.5 | 71.1 | -51.4 (-42.0 %) |
| stall_turning | stall_turning[45_left].recovery_time_s | 3.47 | 3.08 | -0.39 (-11.2 %) |
| stall_turning | stall_turning[45_left].roll_off | inside | outside |  |
| stall_turning | stall_turning[45_left].roll_off_in_1_s_deg | -57.1 | 47.8 | +104.9 (+183.7 %) |
| stall_turning | stall_turning[45_left].stall_alpha_deg | 20.3 | 21.3 | +1 (+4.9 %) |
| stall_turning | stall_turning[45_left].stall_speed_mps | 13.36 | 13.22 | -0.14 (-1.0 %) |
| stall_turning | stall_turning[45_right].altitude_lost_m | 24.5 | 19.7 | -4.8 (-19.6 %) |
| stall_turning | stall_turning[45_right].bank_at_break_deg | 64.9 | 53.9 | -11 (-16.9 %) |
| stall_turning | stall_turning[45_right].max_bank_in_recovery_deg | 112.6 | 66.7 | -45.9 (-40.8 %) |
| stall_turning | stall_turning[45_right].recovery_time_s | 3.27 | 3.05 | -0.22 (-6.7 %) |
| stall_turning | stall_turning[45_right].roll_off | inside | outside |  |
| stall_turning | stall_turning[45_right].roll_off_in_1_s_deg | 47.7 | -48.8 | -96.5 (-202.3 %) |
| stall_turning | stall_turning[45_right].stall_alpha_deg | 19.6 | 20.9 | +1.3 (+6.6 %) |
| takeoff | takeoff.max_rudder_stick | 0.09 | 0.1 | +0.01 (+11.1 %) |
| takeoff | takeoff.rudder_free_heading_change_3_s_deg | -13.2 | -13.4 | -0.2 (-1.5 %) |
| trim_sweep | trim_sweep[x0.55].rpm | 4991 | 5110 | +119 (+2.4 %) |
| trim_sweep | trim_sweep[x0.55].throttle | 0.128 | 0.141 | +0.013 (+10.2 %) |

**207 change(s) beyond tolerance.**
