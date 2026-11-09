# Flight-test comparison

Baseline `tmp\extra300-feel-20261109\ft-baseline`, candidate `tmp\extra300-feel-20261109\ft-final`; tolerance max(0.01, 0.01 × |baseline|).

Card ft-card-v5 → ft-card-v5; commit 7e8ce3a4d0 → 7e8ce3a4d0 (candidate dirty).

## Great Planes Extra 300S .60 — 50 change(s)

Aircraft data changed between the runs.

| Test | Value | Baseline | Candidate | Change |
| --- | --- | --- | --- | --- |
| roll_rate | roll_rate[1.3Vs_left].max_sideslip_deg | 8.4 | 8.2 | -0.2 (-2.4 %) |
| snap_roll | snap_roll[left].alpha_before_45_deg_of_roll_deg | 27.3 | 26.1 | -1.2 (-4.4 %) |
| snap_roll | snap_roll[left].exit_bank_deg | 0.1 | 0.0 | -0.1 (-100.0 %) |
| snap_roll | snap_roll[left].heading_change_at_stop_deg | -13.6 | -10.1 | +3.5 (+25.7 %) |
| snap_roll | snap_roll[left].height_lost_m | 32.3 | 23.7 | -8.6 (-26.6 %) |
| snap_roll | snap_roll[left].max_alpha_deg | 27.4 | 26.1 | -1.3 (-4.7 %) |
| snap_roll | snap_roll[left].mean_roll_rate_dps | 176.5 | 209.6 | +33.1 (+18.8 %) |
| snap_roll | snap_roll[left].mean_yaw_rate_dps | 39.4 | 88.6 | +49.2 (+124.9 %) |
| snap_roll | snap_roll[left].peak_roll_rate_dps | 204.5 | 262.8 | +58.3 (+28.5 %) |
| snap_roll | snap_roll[left].stop_after_deg | 356.8 | 361.2 | +4.4 (+1.2 %) |
| snap_roll | snap_roll[left].stop_error_deg | -3.2 | 1.2 | +4.4 (+137.5 %) |
| snap_roll | snap_roll[left].time_to_level_s | 2.06 | 2.1 | +0.04 (+1.9 %) |
| snap_roll | snap_roll[left].time_to_release_s | 1.81 | 1.52 | -0.29 (-16.0 %) |
| snap_roll | snap_roll[left].yaw_to_roll_ratio | 0.223 | 0.423 | +0.2 (+89.7 %) |
| snap_roll | snap_roll[right].alpha_before_45_deg_of_roll_deg | 27.4 | 26.2 | -1.2 (-4.4 %) |
| snap_roll | snap_roll[right].autorotation_short_of_finish_deg | 69.5 | 0.0 | -69.5 (-100.0 %) |
| snap_roll | snap_roll[right].heading_change_at_stop_deg | -7.3 | 10.8 | +18.1 (+247.9 %) |
| snap_roll | snap_roll[right].height_lost_m | 24.6 | 21.8 | -2.8 (-11.4 %) |
| snap_roll | snap_roll[right].max_alpha_deg | 27.7 | 26.4 | -1.3 (-4.7 %) |
| snap_roll | snap_roll[right].mean_roll_rate_dps | 186.4 | 212.3 | +25.9 (+13.9 %) |
| snap_roll | snap_roll[right].mean_yaw_rate_dps | 84.0 | 90.5 | +6.5 (+7.7 %) |
| snap_roll | snap_roll[right].peak_roll_rate_dps | 268.4 | 279.7 | +11.3 (+4.2 %) |
| snap_roll | snap_roll[right].release_after_deg | 290.5 | 330.0 | +39.5 (+13.6 %) |
| snap_roll | snap_roll[right].release_reason | autorotation ended | finish point |  |
| snap_roll | snap_roll[right].stop_after_deg | 303.2 | 358.7 | +55.5 (+18.3 %) |
| snap_roll | snap_roll[right].stop_error_deg | -56.8 | -1.3 | +55.5 (+97.7 %) |
| snap_roll | snap_roll[right].time_to_level_s | 2.18 | 2.03 | -0.15 (-6.9 %) |
| snap_roll | snap_roll[right].yaw_to_roll_ratio | 0.451 | 0.426 | -0.025 (-5.5 %) |
| spin | spin[left].entered | spin | spiral (no spin) |  |
| spin | spin[left].height_lost_per_turn_m | 30.8 | 49.8 | +19 (+61.7 %) |
| spin | spin[left].max_alpha_deg | 32.0 | 29.6 | -2.4 (-7.5 %) |
| spin | spin[left].recovery_time_s | 0.53 | 0.52 | -0.01 (-1.9 %) |
| spin | spin[left].recovery_turns | 0.13 | 0.03 | -0.1 (-76.9 %) |
| spin | spin[left].steady_turn_time_s | 1.69 | 5.01 | +3.32 (+196.4 %) |
| spin | spin[left].total_height_lost_m | 124.5 | 102.2 | -22.3 (-17.9 %) |
| spin | spin[left].turns_in_6_s | 2.51 | 1.02 | -1.49 (-59.4 %) |
| spin | spin[right].entered | spin | spiral (no spin) |  |
| spin | spin[right].height_lost_per_turn_m | 34.9 | 54.5 | +19.6 (+56.2 %) |
| spin | spin[right].max_alpha_deg | 31.7 | 29.4 | -2.3 (-7.3 %) |
| spin | spin[right].recovery_time_s | 0.5 | 0.56 | +0.06 (+12.0 %) |
| spin | spin[right].recovery_turns | 0.12 | 0.03 | -0.09 (-75.0 %) |
| spin | spin[right].steady_turn_time_s | 1.82 | 5.77 | +3.95 (+217.0 %) |
| spin | spin[right].total_height_lost_m | 127.2 | 99.8 | -27.4 (-21.5 %) |
| spin | spin[right].turns_in_6_s | 2.32 | 0.87 | -1.45 (-62.5 %) |
| stall_power_off | stall_power_off.altitude_lost_m | 40.8 | 33.0 | -7.8 (-19.1 %) |
| stall_power_off | stall_power_off.bank_in_first_second_deg | -13.8 | -11.5 | +2.3 (+16.7 %) |
| stall_power_off | stall_power_off.deceleration_before_break_mps2 | 0.4 | 0.39 | -0.01 (-2.5 %) |
| stall_power_off | stall_power_off.max_bank_in_recovery_deg | 13.8 | 11.5 | -2.3 (-16.7 %) |
| stall_power_off | stall_power_off.recovery_time_s | 4.25 | 3.96 | -0.29 (-6.8 %) |
| stall_power_off | stall_power_off.stall_alpha_deg | 23.7 | 22.2 | -1.5 (-6.3 %) |

**50 change(s) beyond tolerance.**
