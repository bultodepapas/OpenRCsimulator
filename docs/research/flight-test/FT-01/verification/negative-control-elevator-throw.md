# Flight-test comparison

Baseline `run A`, candidate `P-51 with controls.max_throw.elevator × 1.2 (disposable copy)`; tolerance max(0.01, 0.01 × |baseline|).

Card ft-card-v2 → ft-card-v2; commit d2c8bcebbb → d2c8bcebbb (candidate dirty).

## gp-extra-300s-60

Missing from the candidate.

## jensen-das-ugly-stik-60

Missing from the candidate.

## P-51D Mustang 1/4 — 76 change(s)

Aircraft data changed between the runs.

| Test | Value | Baseline | Candidate | Change |
| --- | --- | --- | --- | --- |
| hands_off | hands_off.bank_10_s_deg | 6.8 | 6.7 | -0.1 (-1.5 %) |
| hands_off | hands_off.bank_30_s_deg | 16.7 | 17.7 | +1 (+6.0 %) |
| hands_off | hands_off.bank_after_aileron_pulse_deg | 9.8 | 10.4 | +0.6 (+6.1 %) |
| hands_off | hands_off.heading_change_30_s_deg | 110.5 | 115.0 | +4.5 (+4.1 %) |
| hands_off | hands_off.height_change_10_s_m | -5.56 | -6.26 | -0.7 (-12.6 %) |
| hands_off | hands_off.height_change_30_s_m | -11.85 | -12.85 | -1 (-8.4 %) |
| hands_off | hands_off.speed_change_10_s_mps | 2.37 | 2.7 | +0.33 (+13.9 %) |
| hands_off | hands_off.speed_change_30_s_mps | 1.63 | 1.77 | +0.14 (+8.6 %) |
| inverted | inverted.elevator_servo | -0.085 | -0.071 | +0.014 (+16.5 %) |
| inverted | inverted.elevator_stick | -0.085 | -0.071 | +0.014 (+16.5 %) |
| inverted | inverted.vertical_speed_mps | -0.06 | -0.03 | +0.03 (+50.0 %) |
| knife_edge | knife_edge[left_100pct].height_change_10_s_m | -112.7 | -109.3 | +3.4 (+3.0 %) |
| knife_edge | knife_edge[left_100pct].pitch_attitude_deg | 5.9 | 6.3 | +0.4 (+6.8 %) |
| knife_edge | knife_edge[left_100pct].vertical_speed_mps | -17.21 | -16.76 | +0.45 (+2.6 %) |
| knife_edge | knife_edge[left_50pct].height_change_10_s_m | -186.8 | -183.9 | +2.9 (+1.6 %) |
| knife_edge | knife_edge[left_50pct].pitch_attitude_deg | -8.1 | -7.8 | +0.3 (+3.7 %) |
| knife_edge | knife_edge[left_50pct].vertical_speed_mps | -28.92 | -28.62 | +0.3 (+1.0 %) |
| knife_edge | knife_edge[right_100pct].pitch_attitude_deg | 4.8 | 4.9 | +0.1 (+2.1 %) |
| knife_edge_full_rudder | knife_edge_full_rudder[left_100pct].height_change_10_s_m | -172.1 | -167.1 | +5 (+2.9 %) |
| knife_edge_full_rudder | knife_edge_full_rudder[left_100pct].pitch_attitude_deg | 0.0 | 0.4 | +0.4 |
| knife_edge_full_rudder | knife_edge_full_rudder[left_100pct].vertical_speed_mps | -24.27 | -23.78 | +0.49 (+2.0 %) |
| knife_edge_full_rudder | knife_edge_full_rudder[left_50pct].pitch_attitude_deg | -10.4 | -10.2 | +0.2 (+1.9 %) |
| landing | landing.max_heading_error_deg | 1.4 | 1.2 | -0.2 (-14.3 %) |
| landing | landing.touchdown_pitch_deg | 5.8 | 6.0 | +0.2 (+3.4 %) |
| landing | landing.touchdown_sink_mps | 0.53 | 0.48 | -0.05 (-9.4 %) |
| loop | loop.heading_change_deg | 1.6 | 0.6 | -1 (-62.5 %) |
| loop | loop.height_change_m | 39.7 | 36.1 | -3.6 (-9.1 %) |
| loop | loop.loop_height_m | 101.1 | 96.6 | -4.5 (-4.5 %) |
| loop | loop.loop_time_s | 6.45 | 6.21 | -0.24 (-3.7 %) |
| loop | loop.max_sideslip_deg | 5.5 | 5.6 | +0.1 (+1.8 %) |
| pitch_pull | pitch_pull[0.8Vmax].peak_alpha_deg | 20.3 | 22.3 | +2 (+9.9 %) |
| pitch_pull | pitch_pull[0.8Vmax].peak_pitch_rate_dps | 164.6 | 186.2 | +21.6 (+13.1 %) |
| pitch_pull | pitch_pull[start].peak_alpha_deg | 21.0 | 23.0 | +2 (+9.5 %) |
| pitch_pull | pitch_pull[start].peak_pitch_rate_dps | 76.0 | 86.8 | +10.8 (+14.2 %) |
| spin | spin[left].height_lost_per_turn_m | 48.4 | 53.8 | +5.4 (+11.2 %) |
| spin | spin[left].max_alpha_deg | 40.2 | 41.4 | +1.2 (+3.0 %) |
| spin | spin[left].recovery_time_s | 0.61 | 1.41 | +0.8 (+131.1 %) |
| spin | spin[left].recovery_turns | 0.37 | 1.15 | +0.78 (+210.8 %) |
| spin | spin[left].steady_turn_time_s | 1.66 | 1.85 | +0.19 (+11.4 %) |
| spin | spin[left].total_height_lost_m | 183.3 | 216.6 | +33.3 (+18.2 %) |
| spin | spin[left].turns_in_6_s | 2.09 | 1.86 | -0.23 (-11.0 %) |
| spin | spin[right].height_lost_per_turn_m | 39.7 | 44.5 | +4.8 (+12.1 %) |
| spin | spin[right].max_alpha_deg | 31.1 | 37.3 | +6.2 (+19.9 %) |
| spin | spin[right].recovery_time_s | 0.42 | 0.33 | -0.09 (-21.4 %) |
| spin | spin[right].recovery_turns | 0.34 | 0.24 | -0.1 (-29.4 %) |
| spin | spin[right].steady_turn_time_s | 1.46 | 1.56 | +0.1 (+6.8 %) |
| spin | spin[right].total_height_lost_m | 190.3 | 183.7 | -6.6 (-3.5 %) |
| spin | spin[right].turns_in_6_s | 2.63 | 2.28 | -0.35 (-13.3 %) |
| stall_power_off | stall_power_off.altitude_lost_m | 52.9 | 56.7 | +3.8 (+7.2 %) |
| stall_power_off | stall_power_off.bank_in_first_second_deg | -87.6 | -92.5 | -4.9 (-5.6 %) |
| stall_power_off | stall_power_off.max_bank_in_recovery_deg | 87.6 | 92.5 | +4.9 (+5.6 %) |
| stall_power_off | stall_power_off.recovery_time_s | 4.32 | 4.23 | -0.09 (-2.1 %) |
| stall_power_off | stall_power_off.stall_alpha_deg | 16.2 | 16.7 | +0.5 (+3.1 %) |
| stall_power_on | stall_power_on.altitude_lost_m | 0.0 | 9.3 | +9.3 |
| stall_power_on | stall_power_on.bank_in_first_second_deg | -76.1 | -81.9 | -5.8 (-7.6 %) |
| stall_power_on | stall_power_on.max_bank_in_recovery_deg | 76.1 | 81.9 | +5.8 (+7.6 %) |
| stall_power_on | stall_power_on.recovery_time_s | 3.42 | 3.89 | +0.47 (+13.7 %) |
| stall_power_on | stall_power_on.stall_alpha_deg | 15.2 | 15.6 | +0.4 (+2.6 %) |
| takeoff | takeoff.max_heading_error_deg | 6.0 | 6.1 | +0.1 (+1.7 %) |
| takeoff | takeoff.max_rudder_stick | 0.37 | 0.38 | +0.01 (+2.7 %) |
| takeoff | takeoff.rudder_free_heading_change_3_s_deg | -41.2 | -42.5 | -1.3 (-3.2 %) |
| trim_sweep | trim_sweep[x0.70].stick_pitch | 0.212 | 0.177 | -0.035 (-16.5 %) |
| trim_sweep | trim_sweep[x0.75].stick_pitch | 0.18 | 0.15 | -0.03 (-16.7 %) |
| trim_sweep | trim_sweep[x0.80].stick_pitch | 0.156 | 0.13 | -0.026 (-16.7 %) |
| trim_sweep | trim_sweep[x0.85].stick_pitch | 0.136 | 0.113 | -0.023 (-16.9 %) |
| trim_sweep | trim_sweep[x0.90].stick_pitch | 0.119 | 0.099 | -0.02 (-16.8 %) |
| trim_sweep | trim_sweep[x0.95].stick_pitch | 0.106 | 0.088 | -0.018 (-17.0 %) |
| trim_sweep | trim_sweep[x1.00].stick_pitch | 0.094 | 0.078 | -0.016 (-17.0 %) |
| trim_sweep | trim_sweep[x1.05].stick_pitch | 0.084 | 0.07 | -0.014 (-16.7 %) |
| trim_sweep | trim_sweep[x1.10].stick_pitch | 0.075 | 0.063 | -0.012 (-16.0 %) |
| trim_sweep | trim_sweep[x1.15].stick_pitch | 0.068 | 0.056 | -0.012 (-17.6 %) |
| trim_sweep | trim_sweep[x1.20].stick_pitch | 0.061 | 0.051 | -0.01 (-16.4 %) |
| turn_60 | turn_60[left].vertical_speed_mps | -0.19 | -0.17 | +0.02 (+10.5 %) |
| turn_60 | turn_60[right].vertical_speed_mps | -0.15 | -0.13 | +0.02 (+13.3 %) |
| vmax | vmax.height_error_end_m | 0.02 | 0.07 | +0.05 (+250.0 %) |
| vmax | vmax.height_error_run_m | 1.55 | 1.47 | -0.08 (-5.2 %) |

## sebart-avanti-s-a200-p100rx

Missing from the candidate.

## stik-glow-55ax-2t

Missing from the candidate.

## stik-glow-61fx-2t

Missing from the candidate.

## stik-glow-fs64v-4t

Missing from the candidate.

## turbo-lumber-evolution

Missing from the candidate.

**83 change(s) beyond tolerance.**
