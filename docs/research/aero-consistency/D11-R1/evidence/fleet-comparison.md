# Flight-test comparison

Baseline `tmp/aileron-20261026/fleet-base`, candidate `tmp/aileron-20261026/fleet-candidate`; tolerance max(0.01, 0.01 × |baseline|).

Card ft-card-v5 → ft-card-v5; commit 9d2141db83 → 67e20941ff (candidate dirty).

## F4U-1D Corsair 1/4.5 — 20 change(s)

Aircraft data changed between the runs.

| Test | Value | Baseline | Candidate | Change |
| --- | --- | --- | --- | --- |
| roll_rate | roll_rate[0.8Vmax_left].height_change_m | -58.3 | -44.8 | +13.5 (+23.2 %) |
| roll_rate | roll_rate[0.8Vmax_left].max_sideslip_deg | 11.2 | 10.7 | -0.5 (-4.5 %) |
| roll_rate | roll_rate[0.8Vmax_left].time_to_360_s | 4.53 | 3.82 | -0.71 (-15.7 %) |
| roll_rate | roll_rate[0.8Vmax_right].height_change_m | -51.2 | -47.1 | +4.1 (+8.0 %) |
| roll_rate | roll_rate[0.8Vmax_right].max_sideslip_deg | 11.5 | 11.2 | -0.3 (-2.6 %) |
| roll_rate | roll_rate[0.8Vmax_right].time_to_360_s | 4.32 | 3.99 | -0.33 (-7.6 %) |
| roll_rate | roll_rate[1.3Vs_left].height_change_m | -28.2 | -47.0 | -18.8 (-66.7 %) |
| roll_rate | roll_rate[1.3Vs_left].max_roll_rate_dps | 49.3 | 56.8 | +7.5 (+15.2 %) |
| roll_rate | roll_rate[1.3Vs_left].max_sideslip_deg | 15.6 | 18.9 | +3.3 (+21.2 %) |
| roll_rate | roll_rate[1.3Vs_right].height_change_m | -39.5 | -55.0 | -15.5 (-39.2 %) |
| roll_rate | roll_rate[1.3Vs_right].max_roll_rate_dps | 69.8 | 72.8 | +3 (+4.3 %) |
| roll_rate | roll_rate[1.3Vs_right].max_sideslip_deg | 12.6 | 14.2 | +1.6 (+12.7 %) |
| roll_rate | roll_rate[start_left].height_change_m | -39.3 | -53.9 | -14.6 (-37.2 %) |
| roll_rate | roll_rate[start_left].max_roll_rate_dps | 60.9 | 62.9 | +2 (+3.3 %) |
| roll_rate | roll_rate[start_left].max_sideslip_deg | 14.5 | 15.6 | +1.1 (+7.6 %) |
| roll_rate | roll_rate[start_right].height_change_m | -46.8 | -58.0 | -11.2 (-23.9 %) |
| roll_rate | roll_rate[start_right].max_roll_rate_dps | 72.2 | 74.6 | +2.4 (+3.3 %) |
| roll_rate | roll_rate[start_right].max_sideslip_deg | 12.9 | 13.7 | +0.8 (+6.2 %) |
| stall_power_off | stall_power_off.bank_in_first_second_deg | -74.6 | -77.4 | -2.8 (-3.8 %) |
| stall_power_off | stall_power_off.max_bank_in_recovery_deg | 74.6 | 77.4 | +2.8 (+3.8 %) |

## Great Planes Extra 300S .60 — 19 change(s)

Aircraft data changed between the runs.

| Test | Value | Baseline | Candidate | Change |
| --- | --- | --- | --- | --- |
| roll_rate | roll_rate[0.8Vmax_right].max_sideslip_deg | 4.8 | 4.7 | -0.1 (-2.1 %) |
| roll_rate | roll_rate[1.3Vs_left].height_change_m | -17.2 | -13.9 | +3.3 (+19.2 %) |
| roll_rate | roll_rate[1.3Vs_left].max_roll_rate_dps | 271.9 | 307.7 | +35.8 (+13.2 %) |
| roll_rate | roll_rate[1.3Vs_left].max_sideslip_deg | 7.5 | 8.2 | +0.7 (+9.3 %) |
| roll_rate | roll_rate[1.3Vs_left].time_to_360_s | 1.96 | 1.69 | -0.27 (-13.8 %) |
| roll_rate | roll_rate[1.3Vs_right].height_change_m | -17.0 | -14.6 | +2.4 (+14.1 %) |
| roll_rate | roll_rate[1.3Vs_right].max_roll_rate_dps | 273.8 | 302.3 | +28.5 (+10.4 %) |
| roll_rate | roll_rate[1.3Vs_right].max_sideslip_deg | 10.1 | 10.5 | +0.4 (+4.0 %) |
| roll_rate | roll_rate[1.3Vs_right].time_to_360_s | 1.96 | 1.75 | -0.21 (-10.7 %) |
| roll_rate | roll_rate[start_left].height_change_m | -9.5 | -9.3 | +0.2 (+2.1 %) |
| roll_rate | roll_rate[start_left].max_sideslip_deg | 5.0 | 4.3 | -0.7 (-14.0 %) |
| roll_rate | roll_rate[start_right].height_change_m | -9.5 | -9.3 | +0.2 (+2.1 %) |
| roll_rate | roll_rate[start_right].max_sideslip_deg | 6.6 | 6.0 | -0.6 (-9.1 %) |
| stall_power_off | stall_power_off.altitude_lost_m | 38.7 | 40.0 | +1.3 (+3.4 %) |
| stall_power_off | stall_power_off.bank_in_first_second_deg | 13.8 | -13.6 | -27.4 (-198.6 %) |
| stall_power_off | stall_power_off.deceleration_before_break_mps2 | 0.38 | 0.39 | +0.01 (+2.6 %) |
| stall_power_off | stall_power_off.max_bank_in_recovery_deg | 13.8 | 13.6 | -0.2 (-1.4 %) |
| stall_power_off | stall_power_off.recovery_time_s | 4.17 | 4.22 | +0.05 (+1.2 %) |
| stall_power_off | stall_power_off.wing_drop | right | left |  |

## Ugly Stick — 27 change(s)

Aircraft data changed between the runs.

| Test | Value | Baseline | Candidate | Change |
| --- | --- | --- | --- | --- |
| roll_rate | roll_rate[0.8Vmax_left].height_change_m | -11.6 | -11.1 | +0.5 (+4.3 %) |
| roll_rate | roll_rate[0.8Vmax_left].max_sideslip_deg | 10.0 | 9.7 | -0.3 (-3.0 %) |
| roll_rate | roll_rate[0.8Vmax_left].time_to_360_s | 1.86 | 1.82 | -0.04 (-2.2 %) |
| roll_rate | roll_rate[0.8Vmax_right].height_change_m | -10.8 | -10.5 | +0.3 (+2.8 %) |
| roll_rate | roll_rate[0.8Vmax_right].max_sideslip_deg | 9.2 | 9.0 | -0.2 (-2.2 %) |
| roll_rate | roll_rate[0.8Vmax_right].time_to_360_s | 1.82 | 1.79 | -0.03 (-1.6 %) |
| roll_rate | roll_rate[1.3Vs_left].height_change_m | -41.0 | -36.4 | +4.6 (+11.2 %) |
| roll_rate | roll_rate[1.3Vs_left].max_roll_rate_dps | 152.9 | 178.1 | +25.2 (+16.5 %) |
| roll_rate | roll_rate[1.3Vs_left].max_sideslip_deg | 16.9 | 19.3 | +2.4 (+14.2 %) |
| roll_rate | roll_rate[1.3Vs_left].time_to_360_s | 3.53 | 3.1 | -0.43 (-12.2 %) |
| roll_rate | roll_rate[1.3Vs_right].height_change_m | -33.7 | -32.8 | +0.9 (+2.7 %) |
| roll_rate | roll_rate[1.3Vs_right].max_roll_rate_dps | 172.4 | 186.9 | +14.5 (+8.4 %) |
| roll_rate | roll_rate[1.3Vs_right].max_sideslip_deg | 15.3 | 17.1 | +1.8 (+11.8 %) |
| roll_rate | roll_rate[1.3Vs_right].time_to_360_s | 3.24 | 2.98 | -0.26 (-8.0 %) |
| roll_rate | roll_rate[start_left].height_change_m | -31.8 | -29.8 | +2 (+6.3 %) |
| roll_rate | roll_rate[start_left].max_roll_rate_dps | 156.3 | 177.3 | +21 (+13.4 %) |
| roll_rate | roll_rate[start_left].max_sideslip_deg | 14.0 | 14.6 | +0.6 (+4.3 %) |
| roll_rate | roll_rate[start_left].time_to_360_s | 3.05 | 2.81 | -0.24 (-7.9 %) |
| roll_rate | roll_rate[start_right].height_change_m | -27.3 | -26.8 | +0.5 (+1.8 %) |
| roll_rate | roll_rate[start_right].max_roll_rate_dps | 176.5 | 186.6 | +10.1 (+5.7 %) |
| roll_rate | roll_rate[start_right].max_sideslip_deg | 12.9 | 13.5 | +0.6 (+4.7 %) |
| roll_rate | roll_rate[start_right].time_to_360_s | 2.84 | 2.68 | -0.16 (-5.6 %) |
| stall_power_off | stall_power_off.altitude_lost_m | 29.6 | 34.4 | +4.8 (+16.2 %) |
| stall_power_off | stall_power_off.bank_in_first_second_deg | -75.4 | -80.5 | -5.1 (-6.8 %) |
| stall_power_off | stall_power_off.max_bank_in_recovery_deg | 75.4 | 80.5 | +5.1 (+6.8 %) |
| stall_power_off | stall_power_off.recovery_time_s | 3.05 | 3.31 | +0.26 (+8.5 %) |
| stall_power_off | stall_power_off.stall_alpha_deg | 17.5 | 18.3 | +0.8 (+4.6 %) |

## P-51D Mustang 1/4 — 28 change(s)

Aircraft data changed between the runs.

| Test | Value | Baseline | Candidate | Change |
| --- | --- | --- | --- | --- |
| roll_rate | roll_rate[0.8Vmax_left].height_change_m | -14.1 | -10.8 | +3.3 (+23.4 %) |
| roll_rate | roll_rate[0.8Vmax_left].max_roll_rate_dps | 189.2 | 222.4 | +33.2 (+17.5 %) |
| roll_rate | roll_rate[0.8Vmax_left].max_sideslip_deg | 10.6 | 10.1 | -0.5 (-4.7 %) |
| roll_rate | roll_rate[0.8Vmax_left].time_to_360_s | 2.16 | 1.98 | -0.18 (-8.3 %) |
| roll_rate | roll_rate[0.8Vmax_right].height_change_m | -14.7 | -13.5 | +1.2 (+8.2 %) |
| roll_rate | roll_rate[0.8Vmax_right].max_roll_rate_dps | 186.1 | 215.4 | +29.3 (+15.7 %) |
| roll_rate | roll_rate[0.8Vmax_right].max_sideslip_deg | 9.1 | 8.8 | -0.3 (-3.3 %) |
| roll_rate | roll_rate[0.8Vmax_right].time_to_360_s | 2.15 | 2.06 | -0.09 (-4.2 %) |
| roll_rate | roll_rate[1.3Vs_left].height_change_m | -61.4 | -43.5 | +17.9 (+29.2 %) |
| roll_rate | roll_rate[1.3Vs_left].max_roll_rate_dps | 135.6 | 161.3 | +25.7 (+19.0 %) |
| roll_rate | roll_rate[1.3Vs_left].max_sideslip_deg | 20.8 | 19.0 | -1.8 (-8.7 %) |
| roll_rate | roll_rate[1.3Vs_left].time_to_360_s | 4.0 | 3.47 | -0.53 (-13.2 %) |
| roll_rate | roll_rate[1.3Vs_right].height_change_m | -57.8 | -47.2 | +10.6 (+18.3 %) |
| roll_rate | roll_rate[1.3Vs_right].max_roll_rate_dps | 138.4 | 153.5 | +15.1 (+10.9 %) |
| roll_rate | roll_rate[1.3Vs_right].max_sideslip_deg | 18.7 | 16.7 | -2 (-10.7 %) |
| roll_rate | roll_rate[1.3Vs_right].time_to_360_s | 3.96 | 3.54 | -0.42 (-10.6 %) |
| roll_rate | roll_rate[start_left].height_change_m | -47.9 | -36.6 | +11.3 (+23.6 %) |
| roll_rate | roll_rate[start_left].max_roll_rate_dps | 136.5 | 160.5 | +24 (+17.6 %) |
| roll_rate | roll_rate[start_left].max_sideslip_deg | 15.1 | 14.2 | -0.9 (-6.0 %) |
| roll_rate | roll_rate[start_left].time_to_360_s | 3.53 | 3.14 | -0.39 (-11.0 %) |
| roll_rate | roll_rate[start_right].height_change_m | -45.2 | -40.7 | +4.5 (+10.0 %) |
| roll_rate | roll_rate[start_right].max_roll_rate_dps | 138.3 | 152.7 | +14.4 (+10.4 %) |
| roll_rate | roll_rate[start_right].max_sideslip_deg | 12.4 | 12.2 | -0.2 (-1.6 %) |
| roll_rate | roll_rate[start_right].time_to_360_s | 3.48 | 3.25 | -0.23 (-6.6 %) |
| stall_power_off | stall_power_off.altitude_lost_m | 55.6 | 50.4 | -5.2 (-9.4 %) |
| stall_power_off | stall_power_off.bank_in_first_second_deg | -98.7 | -86.4 | +12.3 (+12.5 %) |
| stall_power_off | stall_power_off.max_bank_in_recovery_deg | 98.7 | 86.4 | -12.3 (-12.5 %) |
| stall_power_off | stall_power_off.stall_alpha_deg | 16.1 | 16.3 | +0.2 (+1.2 %) |

## Ventage Jet — 28 change(s)

Aircraft data changed between the runs.

| Test | Value | Baseline | Candidate | Change |
| --- | --- | --- | --- | --- |
| roll_rate | roll_rate[0.8Vmax_left].height_change_m | -2.4 | -2.5 | -0.1 (-4.2 %) |
| roll_rate | roll_rate[0.8Vmax_left].max_roll_rate_dps | 717.0 | 970.7 | +253.7 (+35.4 %) |
| roll_rate | roll_rate[0.8Vmax_left].max_sideslip_deg | 2.7 | 2.3 | -0.4 (-14.8 %) |
| roll_rate | roll_rate[0.8Vmax_left].time_to_360_s | 0.58 | 0.47 | -0.11 (-19.0 %) |
| roll_rate | roll_rate[0.8Vmax_right].height_change_m | -2.4 | -2.5 | -0.1 (-4.2 %) |
| roll_rate | roll_rate[0.8Vmax_right].max_roll_rate_dps | 717.4 | 971.5 | +254.1 (+35.4 %) |
| roll_rate | roll_rate[0.8Vmax_right].max_sideslip_deg | 2.7 | 2.4 | -0.3 (-11.1 %) |
| roll_rate | roll_rate[0.8Vmax_right].time_to_360_s | 0.58 | 0.47 | -0.11 (-19.0 %) |
| roll_rate | roll_rate[1.3Vs_left].height_change_m | -9.2 | -6.4 | +2.8 (+30.4 %) |
| roll_rate | roll_rate[1.3Vs_left].max_roll_rate_dps | 314.0 | 412.8 | +98.8 (+31.5 %) |
| roll_rate | roll_rate[1.3Vs_left].max_sideslip_deg | 7.3 | 6.0 | -1.3 (-17.8 %) |
| roll_rate | roll_rate[1.3Vs_left].time_to_360_s | 1.34 | 1.04 | -0.3 (-22.4 %) |
| roll_rate | roll_rate[1.3Vs_right].height_change_m | -9.1 | -6.4 | +2.7 (+29.7 %) |
| roll_rate | roll_rate[1.3Vs_right].max_roll_rate_dps | 316.0 | 414.7 | +98.7 (+31.2 %) |
| roll_rate | roll_rate[1.3Vs_right].max_sideslip_deg | 6.9 | 5.7 | -1.2 (-17.4 %) |
| roll_rate | roll_rate[1.3Vs_right].time_to_360_s | 1.34 | 1.04 | -0.3 (-22.4 %) |
| roll_rate | roll_rate[start_left].height_change_m | -6.9 | -5.0 | +1.9 (+27.5 %) |
| roll_rate | roll_rate[start_left].max_roll_rate_dps | 357.5 | 475.4 | +117.9 (+33.0 %) |
| roll_rate | roll_rate[start_left].max_sideslip_deg | 5.8 | 4.2 | -1.6 (-27.6 %) |
| roll_rate | roll_rate[start_left].time_to_360_s | 1.14 | 0.89 | -0.25 (-21.9 %) |
| roll_rate | roll_rate[start_right].height_change_m | -6.9 | -5.0 | +1.9 (+27.5 %) |
| roll_rate | roll_rate[start_right].max_roll_rate_dps | 358.6 | 477.0 | +118.4 (+33.0 %) |
| roll_rate | roll_rate[start_right].max_sideslip_deg | 5.8 | 3.9 | -1.9 (-32.8 %) |
| roll_rate | roll_rate[start_right].time_to_360_s | 1.14 | 0.89 | -0.25 (-21.9 %) |
| stall_power_off | stall_power_off.altitude_lost_m | 56.7 | 55.8 | -0.9 (-1.6 %) |
| stall_power_off | stall_power_off.bank_in_first_second_deg | 30.0 | 22.9 | -7.1 (-23.7 %) |
| stall_power_off | stall_power_off.deceleration_before_break_mps2 | 0.61 | 0.63 | +0.02 (+3.3 %) |
| stall_power_off | stall_power_off.max_bank_in_recovery_deg | 30.0 | 22.9 | -7.1 (-23.7 %) |

## X8 Flying Wing — 0 change(s)

## Ugly Stick · MAX-55AX — 22 change(s)

Aircraft data changed between the runs.

| Test | Value | Baseline | Candidate | Change |
| --- | --- | --- | --- | --- |
| roll_rate | roll_rate[0.8Vmax_left].height_change_m | -8.3 | -8.2 | +0.1 (+1.2 %) |
| roll_rate | roll_rate[0.8Vmax_left].max_sideslip_deg | 9.1 | 8.9 | -0.2 (-2.2 %) |
| roll_rate | roll_rate[0.8Vmax_left].time_to_360_s | 1.57 | 1.55 | -0.02 (-1.3 %) |
| roll_rate | roll_rate[0.8Vmax_right].max_sideslip_deg | 8.2 | 8.1 | -0.1 (-1.2 %) |
| roll_rate | roll_rate[1.3Vs_left].height_change_m | -41.4 | -36.3 | +5.1 (+12.3 %) |
| roll_rate | roll_rate[1.3Vs_left].max_roll_rate_dps | 157.8 | 181.4 | +23.6 (+15.0 %) |
| roll_rate | roll_rate[1.3Vs_left].max_sideslip_deg | 16.1 | 18.7 | +2.6 (+16.1 %) |
| roll_rate | roll_rate[1.3Vs_left].time_to_360_s | 3.53 | 3.11 | -0.42 (-11.9 %) |
| roll_rate | roll_rate[1.3Vs_right].height_change_m | -33.0 | -32.5 | +0.5 (+1.5 %) |
| roll_rate | roll_rate[1.3Vs_right].max_roll_rate_dps | 187.3 | 191.2 | +3.9 (+2.1 %) |
| roll_rate | roll_rate[1.3Vs_right].max_sideslip_deg | 14.6 | 16.4 | +1.8 (+12.3 %) |
| roll_rate | roll_rate[1.3Vs_right].time_to_360_s | 3.18 | 2.98 | -0.2 (-6.3 %) |
| roll_rate | roll_rate[start_left].height_change_m | -20.2 | -19.6 | +0.6 (+3.0 %) |
| roll_rate | roll_rate[start_left].max_roll_rate_dps | 179.4 | 190.2 | +10.8 (+6.0 %) |
| roll_rate | roll_rate[start_left].time_to_360_s | 2.36 | 2.27 | -0.09 (-3.8 %) |
| roll_rate | roll_rate[start_right].height_change_m | -18.4 | -18.0 | +0.4 (+2.2 %) |
| roll_rate | roll_rate[start_right].time_to_360_s | 2.25 | 2.19 | -0.06 (-2.7 %) |
| stall_power_off | stall_power_off.altitude_lost_m | 26.2 | 26.8 | +0.6 (+2.3 %) |
| stall_power_off | stall_power_off.bank_in_first_second_deg | -80.5 | -85.0 | -4.5 (-5.6 %) |
| stall_power_off | stall_power_off.max_bank_in_recovery_deg | 80.5 | 85.0 | +4.5 (+5.6 %) |
| stall_power_off | stall_power_off.recovery_time_s | 2.92 | 2.99 | +0.07 (+2.4 %) |
| stall_power_off | stall_power_off.stall_alpha_deg | 18.2 | 18.9 | +0.7 (+3.8 %) |

## Ugly Stick · MAX-61FX — 26 change(s)

Aircraft data changed between the runs.

| Test | Value | Baseline | Candidate | Change |
| --- | --- | --- | --- | --- |
| roll_rate | roll_rate[0.8Vmax_left].height_change_m | -9.2 | -8.9 | +0.3 (+3.3 %) |
| roll_rate | roll_rate[0.8Vmax_left].max_sideslip_deg | 9.3 | 9.1 | -0.2 (-2.2 %) |
| roll_rate | roll_rate[0.8Vmax_left].time_to_360_s | 1.62 | 1.59 | -0.03 (-1.9 %) |
| roll_rate | roll_rate[0.8Vmax_right].height_change_m | -8.2 | -8.1 | +0.1 (+1.2 %) |
| roll_rate | roll_rate[0.8Vmax_right].max_sideslip_deg | 8.4 | 8.3 | -0.1 (-1.2 %) |
| roll_rate | roll_rate[0.8Vmax_right].time_to_360_s | 1.57 | 1.55 | -0.02 (-1.3 %) |
| roll_rate | roll_rate[1.3Vs_left].height_change_m | -43.7 | -36.4 | +7.3 (+16.7 %) |
| roll_rate | roll_rate[1.3Vs_left].max_roll_rate_dps | 152.2 | 179.5 | +27.3 (+17.9 %) |
| roll_rate | roll_rate[1.3Vs_left].max_sideslip_deg | 16.5 | 19.1 | +2.6 (+15.8 %) |
| roll_rate | roll_rate[1.3Vs_left].time_to_360_s | 3.57 | 3.07 | -0.5 (-14.0 %) |
| roll_rate | roll_rate[1.3Vs_right].height_change_m | -33.3 | -32.2 | +1.1 (+3.3 %) |
| roll_rate | roll_rate[1.3Vs_right].max_roll_rate_dps | 181.5 | 189.5 | +8 (+4.4 %) |
| roll_rate | roll_rate[1.3Vs_right].max_sideslip_deg | 14.8 | 16.6 | +1.8 (+12.2 %) |
| roll_rate | roll_rate[1.3Vs_right].time_to_360_s | 3.16 | 2.93 | -0.23 (-7.3 %) |
| roll_rate | roll_rate[start_left].height_change_m | -21.6 | -20.6 | +1 (+4.6 %) |
| roll_rate | roll_rate[start_left].max_roll_rate_dps | 177.6 | 189.5 | +11.9 (+6.7 %) |
| roll_rate | roll_rate[start_left].time_to_360_s | 2.41 | 2.29 | -0.12 (-5.0 %) |
| roll_rate | roll_rate[start_right].height_change_m | -19.0 | -18.5 | +0.5 (+2.6 %) |
| roll_rate | roll_rate[start_right].max_sideslip_deg | 10.7 | 10.5 | -0.2 (-1.9 %) |
| roll_rate | roll_rate[start_right].time_to_360_s | 2.26 | 2.19 | -0.07 (-3.1 %) |
| stall_power_off | stall_power_off.altitude_lost_m | 30.8 | 36.0 | +5.2 (+16.9 %) |
| stall_power_off | stall_power_off.bank_in_first_second_deg | -82.4 | -90.2 | -7.8 (-9.5 %) |
| stall_power_off | stall_power_off.deceleration_before_break_mps2 | 0.31 | 0.3 | -0.01 (-3.2 %) |
| stall_power_off | stall_power_off.max_bank_in_recovery_deg | 82.4 | 90.2 | +7.8 (+9.5 %) |
| stall_power_off | stall_power_off.recovery_time_s | 3.1 | 3.36 | +0.26 (+8.4 %) |
| stall_power_off | stall_power_off.stall_alpha_deg | 17.9 | 18.6 | +0.7 (+3.9 %) |

## Ugly Stick · FS-64V — 25 change(s)

Aircraft data changed between the runs.

| Test | Value | Baseline | Candidate | Change |
| --- | --- | --- | --- | --- |
| roll_rate | roll_rate[0.8Vmax_left].height_change_m | -15.9 | -15.2 | +0.7 (+4.4 %) |
| roll_rate | roll_rate[0.8Vmax_left].max_sideslip_deg | 10.5 | 10.2 | -0.3 (-2.9 %) |
| roll_rate | roll_rate[0.8Vmax_left].time_to_360_s | 2.18 | 2.12 | -0.06 (-2.8 %) |
| roll_rate | roll_rate[0.8Vmax_right].height_change_m | -14.5 | -14.3 | +0.2 (+1.4 %) |
| roll_rate | roll_rate[0.8Vmax_right].max_sideslip_deg | 9.7 | 9.5 | -0.2 (-2.1 %) |
| roll_rate | roll_rate[0.8Vmax_right].time_to_360_s | 2.1 | 2.05 | -0.05 (-2.4 %) |
| roll_rate | roll_rate[1.3Vs_left].height_change_m | -46.3 | -37.6 | +8.7 (+18.8 %) |
| roll_rate | roll_rate[1.3Vs_left].max_roll_rate_dps | 137.4 | 162.8 | +25.4 (+18.5 %) |
| roll_rate | roll_rate[1.3Vs_left].max_sideslip_deg | 16.4 | 19.1 | +2.7 (+16.5 %) |
| roll_rate | roll_rate[1.3Vs_left].time_to_360_s | 3.85 | 3.28 | -0.57 (-14.8 %) |
| roll_rate | roll_rate[1.3Vs_right].height_change_m | -31.6 | -31.2 | +0.4 (+1.3 %) |
| roll_rate | roll_rate[1.3Vs_right].max_roll_rate_dps | 174.6 | 176.4 | +1.8 (+1.0 %) |
| roll_rate | roll_rate[1.3Vs_right].max_sideslip_deg | 14.5 | 16.2 | +1.7 (+11.7 %) |
| roll_rate | roll_rate[1.3Vs_right].time_to_360_s | 3.23 | 3.04 | -0.19 (-5.9 %) |
| roll_rate | roll_rate[start_left].height_change_m | -19.5 | -18.5 | +1 (+5.1 %) |
| roll_rate | roll_rate[start_left].max_roll_rate_dps | 176.5 | 178.3 | +1.8 (+1.0 %) |
| roll_rate | roll_rate[start_left].max_sideslip_deg | 11.1 | 10.8 | -0.3 (-2.7 %) |
| roll_rate | roll_rate[start_left].time_to_360_s | 2.4 | 2.3 | -0.1 (-4.2 %) |
| roll_rate | roll_rate[start_right].height_change_m | -17.2 | -16.9 | +0.3 (+1.7 %) |
| roll_rate | roll_rate[start_right].time_to_360_s | 2.28 | 2.21 | -0.07 (-3.1 %) |
| stall_power_off | stall_power_off.altitude_lost_m | 32.6 | 31.9 | -0.7 (-2.1 %) |
| stall_power_off | stall_power_off.bank_in_first_second_deg | -87.5 | -98.3 | -10.8 (-12.3 %) |
| stall_power_off | stall_power_off.max_bank_in_recovery_deg | 87.5 | 98.3 | +10.8 (+12.3 %) |
| stall_power_off | stall_power_off.recovery_time_s | 3.33 | 3.28 | -0.05 (-1.5 %) |
| stall_power_off | stall_power_off.stall_alpha_deg | 18.4 | 19.2 | +0.8 (+4.3 %) |

## Turbo Lumber Evolution — 26 change(s)

Aircraft data changed between the runs.

| Test | Value | Baseline | Candidate | Change |
| --- | --- | --- | --- | --- |
| roll_rate | roll_rate[0.8Vmax_left].height_change_m | -6.9 | -4.9 | +2 (+29.0 %) |
| roll_rate | roll_rate[0.8Vmax_left].max_roll_rate_dps | 385.4 | 493.6 | +108.2 (+28.1 %) |
| roll_rate | roll_rate[0.8Vmax_left].max_sideslip_deg | 13.4 | 11.5 | -1.9 (-14.2 %) |
| roll_rate | roll_rate[0.8Vmax_left].time_to_360_s | 1.08 | 0.87 | -0.21 (-19.4 %) |
| roll_rate | roll_rate[0.8Vmax_right].height_change_m | -6.8 | -5.0 | +1.8 (+26.5 %) |
| roll_rate | roll_rate[0.8Vmax_right].max_roll_rate_dps | 380.8 | 487.5 | +106.7 (+28.0 %) |
| roll_rate | roll_rate[0.8Vmax_right].max_sideslip_deg | 15.1 | 12.9 | -2.2 (-14.6 %) |
| roll_rate | roll_rate[0.8Vmax_right].time_to_360_s | 1.1 | 0.88 | -0.22 (-20.0 %) |
| roll_rate | roll_rate[1.3Vs_left].height_change_m | -18.6 | -11.4 | +7.2 (+38.7 %) |
| roll_rate | roll_rate[1.3Vs_left].max_roll_rate_dps | 272.4 | 321.8 | +49.4 (+18.1 %) |
| roll_rate | roll_rate[1.3Vs_left].max_sideslip_deg | 36.6 | 30.1 | -6.5 (-17.8 %) |
| roll_rate | roll_rate[1.3Vs_left].time_to_360_s | 2.07 | 1.63 | -0.44 (-21.3 %) |
| roll_rate | roll_rate[1.3Vs_right].height_change_m | -19.3 | -12.1 | +7.2 (+37.3 %) |
| roll_rate | roll_rate[1.3Vs_right].max_roll_rate_dps | 290.3 | 336.0 | +45.7 (+15.7 %) |
| roll_rate | roll_rate[1.3Vs_right].max_sideslip_deg | 36.5 | 30.9 | -5.6 (-15.3 %) |
| roll_rate | roll_rate[1.3Vs_right].time_to_360_s | 2.06 | 1.63 | -0.43 (-20.9 %) |
| roll_rate | roll_rate[start_left].height_change_m | -15.9 | -9.6 | +6.3 (+39.6 %) |
| roll_rate | roll_rate[start_left].max_roll_rate_dps | 291.4 | 353.5 | +62.1 (+21.3 %) |
| roll_rate | roll_rate[start_left].max_sideslip_deg | 29.0 | 22.7 | -6.3 (-21.7 %) |
| roll_rate | roll_rate[start_left].time_to_360_s | 1.8 | 1.43 | -0.37 (-20.6 %) |
| roll_rate | roll_rate[start_right].height_change_m | -16.0 | -10.4 | +5.6 (+35.0 %) |
| roll_rate | roll_rate[start_right].max_roll_rate_dps | 300.0 | 364.8 | +64.8 (+21.6 %) |
| roll_rate | roll_rate[start_right].max_sideslip_deg | 30.2 | 23.9 | -6.3 (-20.9 %) |
| roll_rate | roll_rate[start_right].time_to_360_s | 1.81 | 1.45 | -0.36 (-19.9 %) |
| stall_power_off | stall_power_off.bank_in_first_second_deg | -13.6 | -13.4 | +0.2 (+1.5 %) |
| stall_power_off | stall_power_off.max_bank_in_recovery_deg | 13.6 | 13.4 | -0.2 (-1.5 %) |

**221 change(s) beyond tolerance.**
