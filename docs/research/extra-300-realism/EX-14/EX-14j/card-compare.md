# Flight-test comparison

Baseline `tmp\extra300-roll-continuity-20261109\card-baseline`, candidate `tmp\extra300-roll-continuity-20261109\card-candidate`; tolerance max(0.01, 0.01 × |baseline|).

Card ft-card-v5 → ft-card-v5; commit 5e673fbbdd → 5e673fbbdd (candidate dirty).

## Great Planes Extra 300S .60 — 25 change(s)

Aircraft data changed between the runs.

| Test | Value | Baseline | Candidate | Change |
| --- | --- | --- | --- | --- |
| snap_roll | snap_roll[left].heading_change_at_stop_deg | -10.1 | -10.3 | -0.2 (-2.0 %) |
| snap_roll | snap_roll[left].mean_roll_rate_dps | 209.6 | 207.1 | -2.5 (-1.2 %) |
| snap_roll | snap_roll[left].mean_yaw_rate_dps | 88.6 | 87.4 | -1.2 (-1.4 %) |
| snap_roll | snap_roll[left].release_after_deg | 318.8 | 322.8 | +4 (+1.3 %) |
| snap_roll | snap_roll[left].stop_error_deg | 1.2 | 0.6 | -0.6 (-50.0 %) |
| snap_roll | snap_roll[left].time_to_release_s | 1.52 | 1.56 | +0.04 (+2.6 %) |
| snap_roll | snap_roll[right].heading_change_at_stop_deg | 10.8 | 12.0 | +1.2 (+11.1 %) |
| snap_roll | snap_roll[right].height_lost_m | 21.8 | 21.4 | -0.4 (-1.8 %) |
| snap_roll | snap_roll[right].mean_roll_rate_dps | 212.3 | 199.7 | -12.6 (-5.9 %) |
| snap_roll | snap_roll[right].mean_yaw_rate_dps | 90.5 | 84.5 | -6 (-6.6 %) |
| snap_roll | snap_roll[right].peak_roll_rate_dps | 279.7 | 275.3 | -4.4 (-1.6 %) |
| snap_roll | snap_roll[right].release_after_deg | 330.0 | 337.9 | +7.9 (+2.4 %) |
| snap_roll | snap_roll[right].stop_error_deg | -1.3 | -2.5 | -1.2 (-92.3 %) |
| snap_roll | snap_roll[right].time_to_level_s | 2.03 | 1.98 | -0.05 (-2.5 %) |
| snap_roll | snap_roll[right].time_to_release_s | 1.55 | 1.69 | +0.14 (+9.0 %) |
| spin | spin[left].height_lost_per_turn_m | 49.8 | 51.2 | +1.4 (+2.8 %) |
| spin | spin[left].recovery_time_s | 0.52 | 0.51 | -0.01 (-1.9 %) |
| spin | spin[left].steady_turn_time_s | 5.01 | 4.72 | -0.29 (-5.8 %) |
| spin | spin[left].total_height_lost_m | 102.2 | 105.1 | +2.9 (+2.8 %) |
| spin | spin[left].turns_in_6_s | 1.02 | 1.06 | +0.04 (+3.9 %) |
| spin | spin[right].height_lost_per_turn_m | 54.5 | 55.6 | +1.1 (+2.0 %) |
| spin | spin[right].recovery_time_s | 0.56 | 0.55 | -0.01 (-1.8 %) |
| spin | spin[right].steady_turn_time_s | 5.77 | 5.39 | -0.38 (-6.6 %) |
| spin | spin[right].total_height_lost_m | 99.8 | 101.9 | +2.1 (+2.1 %) |
| spin | spin[right].turns_in_6_s | 0.87 | 0.9 | +0.03 (+3.4 %) |

**25 change(s) beyond tolerance.**
