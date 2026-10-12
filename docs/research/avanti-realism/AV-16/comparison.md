# AV-16 flight matrix comparison

Model predictions, not independent physical validation.

| Case | Final speed baseline → corrected (m/s) | Altitude change baseline → corrected (m) | Peak total-axis component baseline → corrected (rad/s) |
| --- | ---: | ---: | ---: |
| level_trim_22 | 22.000 → 22.000 | 0.000 → 0.000 | 0.000 → 0.000 |
| level_trim_29 | 29.000 → 29.000 | 0.000 → 0.000 | 0.000 → 0.000 |
| level_trim_45 | 45.000 → 45.000 | 0.000 → 0.000 | 0.000 → 0.000 |
| level_trim_65 | 65.000 → 65.000 | 0.000 → 0.000 | 0.000 → 0.000 |
| engine_off_glide_21 | 21.000 → 21.000 | -40.260 → -40.228 | 0.000 → 0.000 |
| roll_normal_negative | 46.955 → 46.846 | -77.596 → -76.970 | 3.081 → 3.098 |
| roll_high_negative | 36.050 → 36.272 | -28.135 → -29.059 | 6.572 → 6.580 |
| roll_normal_positive | 46.898 → 46.787 | -77.227 → -76.598 | 3.118 → 3.135 |
| roll_high_positive | 36.121 → 36.311 | -28.462 → -29.251 | 6.598 → 6.607 |
| pitch_normal_negative | 42.577 → 42.556 | -68.718 → -68.768 | 2.325 → 2.329 |
| pitch_high_negative | 36.093 → 36.024 | -67.638 → -67.498 | 3.679 → 3.689 |
| pitch_normal_positive | 27.168 → 27.104 | -7.696 → -7.642 | 1.895 → 1.899 |
| pitch_high_positive | 26.769 → 26.691 | -29.500 → -29.487 | 3.064 → 3.074 |
| yaw_normal_negative | 30.055 → 30.047 | -4.389 → -4.365 | 1.141 → 1.125 |
| yaw_high_negative | 30.310 → 30.299 | -5.588 → -5.547 | 1.409 → 1.390 |
| yaw_normal_positive | 30.526 → 30.513 | -5.908 → -5.866 | 1.149 → 1.146 |
| yaw_high_positive | 30.799 → 30.780 | -7.170 → -7.107 | 1.409 → 1.390 |
| throttle_up_step_22 | 10.360 → 10.234 | 56.572 → 56.829 | 2.152 → 2.133 |
| idle_descent_approach_22 | 22.228 → 22.156 | -38.697 → -38.559 | 0.052 → 0.051 |
| idle_to_full_go_around_input_22 | 24.436 → 24.680 | 95.039 → 95.322 | 0.478 → 0.469 |
| guided_30deg_turn_left | 28.960 → 28.960 | -2.041 → -2.046 | 1.325 → 1.333 |
| cross_control_slip_left | 39.486 → 39.515 | -41.575 → -41.712 | 1.056 → 1.039 |
| guided_30deg_turn_right | 28.980 → 28.980 | -2.158 → -2.161 | 1.325 → 1.333 |
| cross_control_slip_right | 39.154 → 39.189 | -40.236 → -40.393 | 1.056 → 1.039 |
| high_pitch_stall_entry_idle_24 | 26.975 → 26.641 | -59.974 → -59.572 | 2.320 → 3.165 |
| high_pitch_stall_entry_full_power_24 | 27.117 → 26.944 | -8.240 → -8.089 | 2.411 → 2.420 |
| stall_rotation_response_left_rudder | 43.858 → 43.168 | -139.572 → -135.536 | 3.390 → 3.246 |
| stall_rotation_response_right_rudder | 41.216 → 41.166 | -127.116 → -128.009 | 4.466 → 4.552 |
| pitch_loop_input_negative_50 | 54.337 → 53.610 | -284.602 → -271.162 | 14.346 → 13.353 |
| pitch_loop_input_positive_50 | 44.824 → 42.519 | -59.175 → -49.136 | 9.596 → 9.472 |
| inverted_hands_off_35 | 35.000 → 35.000 | 0.000 → 0.000 | 0.000 → 0.000 |
| environment_gentle-practice | 26.996 → 26.996 | 1.256 → 1.254 | 0.027 → 0.027 |
| environment_gusty | 32.822 → 32.840 | -0.680 → -0.725 | 0.057 → 0.057 |
| environment_hot-high | 29.000 → 29.000 | 0.000 → 0.000 | 0.000 → 0.000 |

Steady speed/RPM 1%; smooth pulse axis peak/speed and throttle endpoint 5%. Denominator floors are 1 m/s, 1 RPM and 0.1 rad/s. Nonlinear and stochastic cases are descriptive.

Selected refinement checks: 84/84 pass. Exact values and nonlinear trajectory/spin observations are in [comparison.json](comparison.json).
