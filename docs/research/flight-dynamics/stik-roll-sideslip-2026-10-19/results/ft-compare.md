# Flight-test comparison

Baseline `ft/base`, candidate `ft/cand`; tolerance max(0.01, 0.01 × |baseline|).

Card ft-card-v3 → ft-card-v3; commit bfc32834f6 → bfc32834f6 (candidate dirty).

## Jensen Das Ugly Stik 60 — 77 change(s)

Aircraft data changed between the runs.

| Test | Value | Baseline | Candidate | Change |
| --- | --- | --- | --- | --- |
| aero_sweep | aero_sweep[beta_15].cl | -0.003 | -0.0164 | -0.0134 (-446.7 %) |
| aero_sweep | aero_sweep[beta_15].cl_local | -0.003 | -0.0164 | -0.0134 (-446.7 %) |
| knife_edge | knife_edge[left_100pct].aileron_stick | -0.224 | -0.319 | -0.095 (-42.4 %) |
| knife_edge | knife_edge[left_100pct].height_change_10_s_m | -71.8 | -77.9 | -6.1 (-8.5 %) |
| knife_edge | knife_edge[left_100pct].pitch_attitude_deg | 4.4 | 3.1 | -1.3 (-29.5 %) |
| knife_edge | knife_edge[left_100pct].vertical_speed_mps | -10.13 | -11.03 | -0.9 (-8.9 %) |
| knife_edge | knife_edge[left_50pct].aileron_stick | -0.251 | -0.344 | -0.093 (-37.1 %) |
| knife_edge | knife_edge[left_50pct].height_change_10_s_m | -181.1 | -183.2 | -2.1 (-1.2 %) |
| knife_edge | knife_edge[left_50pct].pitch_attitude_deg | -29.0 | -29.5 | -0.5 (-1.7 %) |
| knife_edge | knife_edge[left_50pct].vertical_speed_mps | -25.56 | -25.83 | -0.27 (-1.1 %) |
| knife_edge | knife_edge[right_100pct].aileron_stick | 0.276 | 0.37 | +0.094 (+34.1 %) |
| knife_edge | knife_edge[right_100pct].height_change_10_s_m | -72.5 | -78.0 | -5.5 (-7.6 %) |
| knife_edge | knife_edge[right_100pct].pitch_attitude_deg | 4.4 | 3.3 | -1.1 (-25.0 %) |
| knife_edge | knife_edge[right_100pct].vertical_speed_mps | -10.08 | -10.88 | -0.8 (-7.9 %) |
| knife_edge | knife_edge[right_50pct].aileron_stick | 0.256 | 0.349 | +0.093 (+36.3 %) |
| knife_edge | knife_edge[right_50pct].height_change_10_s_m | -179.4 | -181.6 | -2.2 (-1.2 %) |
| knife_edge | knife_edge[right_50pct].pitch_attitude_deg | -28.4 | -28.8 | -0.4 (-1.4 %) |
| knife_edge | knife_edge[right_50pct].vertical_speed_mps | -25.19 | -25.47 | -0.28 (-1.1 %) |
| knife_edge_full_rudder | knife_edge_full_rudder[left_100pct].aileron_stick | -0.231 | -0.325 | -0.094 (-40.7 %) |
| knife_edge_full_rudder | knife_edge_full_rudder[left_100pct].height_change_10_s_m | -93.4 | -96.8 | -3.4 (-3.6 %) |
| knife_edge_full_rudder | knife_edge_full_rudder[left_100pct].pitch_attitude_deg | 0.6 | -0.1 | -0.7 (-116.7 %) |
| knife_edge_full_rudder | knife_edge_full_rudder[left_100pct].vertical_speed_mps | -12.7 | -13.24 | -0.54 (-4.3 %) |
| knife_edge_full_rudder | knife_edge_full_rudder[left_50pct].aileron_stick | -0.251 | -0.345 | -0.094 (-37.5 %) |
| knife_edge_full_rudder | knife_edge_full_rudder[left_50pct].pitch_attitude_deg | -29.3 | -29.7 | -0.4 (-1.4 %) |
| knife_edge_full_rudder | knife_edge_full_rudder[right_100pct].aileron_stick | 0.277 | 0.371 | +0.094 (+33.9 %) |
| knife_edge_full_rudder | knife_edge_full_rudder[right_100pct].height_change_10_s_m | -84.4 | -87.7 | -3.3 (-3.9 %) |
| knife_edge_full_rudder | knife_edge_full_rudder[right_100pct].pitch_attitude_deg | 2.0 | 1.3 | -0.7 (-35.0 %) |
| knife_edge_full_rudder | knife_edge_full_rudder[right_100pct].vertical_speed_mps | -11.72 | -12.25 | -0.53 (-4.5 %) |
| knife_edge_full_rudder | knife_edge_full_rudder[right_50pct].aileron_stick | 0.256 | 0.35 | +0.094 (+36.7 %) |
| knife_edge_full_rudder | knife_edge_full_rudder[right_50pct].pitch_attitude_deg | -28.6 | -28.9 | -0.3 (-1.0 %) |
| roll_rate | roll_rate[0.8Vmax_left].height_change_m | -9.8 | -10.1 | -0.3 (-3.1 %) |
| roll_rate | roll_rate[0.8Vmax_left].max_sideslip_deg | 9.9 | 10.1 | +0.2 (+2.0 %) |
| roll_rate | roll_rate[0.8Vmax_left].time_to_360_s | 1.83 | 1.86 | +0.03 (+1.6 %) |
| roll_rate | roll_rate[0.8Vmax_right].height_change_m | -9.5 | -9.7 | -0.2 (-2.1 %) |
| roll_rate | roll_rate[0.8Vmax_right].max_sideslip_deg | 9.3 | 9.4 | +0.1 (+1.1 %) |
| roll_rate | roll_rate[0.8Vmax_right].time_to_360_s | 1.82 | 1.84 | +0.02 (+1.1 %) |
| roll_rate | roll_rate[1.3Vs_left].height_change_m | -37.1 | -38.5 | -1.4 (-3.8 %) |
| roll_rate | roll_rate[1.3Vs_left].max_roll_rate_dps | 165.3 | 151.1 | -14.2 (-8.6 %) |
| roll_rate | roll_rate[1.3Vs_left].max_sideslip_deg | 19.3 | 17.2 | -2.1 (-10.9 %) |
| roll_rate | roll_rate[1.3Vs_left].time_to_360_s | 3.22 | 3.48 | +0.26 (+8.1 %) |
| roll_rate | roll_rate[1.3Vs_right].max_roll_rate_dps | 181.3 | 173.2 | -8.1 (-4.5 %) |
| roll_rate | roll_rate[1.3Vs_right].max_sideslip_deg | 17.6 | 15.7 | -1.9 (-10.8 %) |
| roll_rate | roll_rate[1.3Vs_right].time_to_360_s | 3.07 | 3.24 | +0.17 (+5.5 %) |
| roll_rate | roll_rate[start_left].height_change_m | -28.8 | -29.4 | -0.6 (-2.1 %) |
| roll_rate | roll_rate[start_left].max_roll_rate_dps | 166.5 | 160.0 | -6.5 (-3.9 %) |
| roll_rate | roll_rate[start_left].max_sideslip_deg | 14.6 | 14.1 | -0.5 (-3.4 %) |
| roll_rate | roll_rate[start_left].time_to_360_s | 2.88 | 3.02 | +0.14 (+4.9 %) |
| roll_rate | roll_rate[start_right].max_roll_rate_dps | 177.9 | 174.7 | -3.2 (-1.8 %) |
| roll_rate | roll_rate[start_right].max_sideslip_deg | 13.6 | 13.2 | -0.4 (-2.9 %) |
| roll_rate | roll_rate[start_right].time_to_360_s | 2.74 | 2.84 | +0.1 (+3.6 %) |
| rudder_step | rudder_step[left].bank_after_2_75_s_deg | -84.6 | -104.1 | -19.5 (-23.0 %) |
| rudder_step | rudder_step[left].max_sideslip_deg | 25.3 | 24.9 | -0.4 (-1.6 %) |
| rudder_step | rudder_step[left].peak_roll_rate_dps | -60.7 | -65.2 | -4.5 (-7.4 %) |
| rudder_step | rudder_step[left].pitch_change_deg | -63.1 | -68.4 | -5.3 (-8.4 %) |
| rudder_step | rudder_step[right].bank_after_2_75_s_deg | 78.1 | 94.1 | +16 (+20.5 %) |
| rudder_step | rudder_step[right].max_sideslip_deg | 26.1 | 25.8 | -0.3 (-1.1 %) |
| rudder_step | rudder_step[right].peak_roll_rate_dps | 63.3 | 68.7 | +5.4 (+8.5 %) |
| rudder_step | rudder_step[right].pitch_change_deg | -61.6 | -65.7 | -4.1 (-6.7 %) |
| spin | spin[left].height_lost_per_turn_m | 28.3 | 26.0 | -2.3 (-8.1 %) |
| spin | spin[left].recovery_time_s | 0.31 | 0.94 | +0.63 (+203.2 %) |
| spin | spin[left].recovery_turns | 0.23 | 0.9 | +0.67 (+291.3 %) |
| spin | spin[left].steady_turn_time_s | 1.32 | 1.28 | -0.04 (-3.0 %) |
| spin | spin[left].total_height_lost_m | 126.8 | 135.8 | +9 (+7.1 %) |
| spin | spin[left].turns_in_6_s | 2.98 | 3.16 | +0.18 (+6.0 %) |
| spin | spin[right].height_lost_per_turn_m | 30.4 | 28.1 | -2.3 (-7.6 %) |
| spin | spin[right].recovery_time_s | 0.68 | 0.25 | -0.43 (-63.2 %) |
| spin | spin[right].steady_turn_time_s | 1.43 | 1.31 | -0.12 (-8.4 %) |
| spin | spin[right].total_height_lost_m | 146.0 | 126.2 | -19.8 (-13.6 %) |
| spin | spin[right].turns_in_6_s | 2.85 | 3.05 | +0.2 (+7.0 %) |
| stall_power_off | stall_power_off.altitude_lost_m | 32.5 | 36.3 | +3.8 (+11.7 %) |
| stall_power_off | stall_power_off.bank_in_first_second_deg | -77.8 | -75.7 | +2.1 (+2.7 %) |
| stall_power_off | stall_power_off.max_bank_in_recovery_deg | 77.8 | 75.7 | -2.1 (-2.7 %) |
| stall_power_off | stall_power_off.recovery_time_s | 3.19 | 3.36 | +0.17 (+5.3 %) |
| stall_power_on | stall_power_on.altitude_lost_m | 5.9 | 6.8 | +0.9 (+15.3 %) |
| stall_power_on | stall_power_on.bank_in_first_second_deg | -78.9 | -76.0 | +2.9 (+3.7 %) |
| stall_power_on | stall_power_on.max_bank_in_recovery_deg | 78.9 | 76.0 | -2.9 (-3.7 %) |
| stall_power_on | stall_power_on.recovery_time_s | 2.41 | 2.55 | +0.14 (+5.8 %) |

**77 change(s) beyond tolerance.**
