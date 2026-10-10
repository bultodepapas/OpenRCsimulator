# G2a RK4 refinement

Status: measured 2026-10-09; step G2a-RK4.

This measures final-state convergence of the production P-51 flight session over exact 0.5 s runs. The servo inputs stay at the trimmed commands; `throttle_step` applies `trim + 0.03` at the initial boundary, `smooth_gust` applies a raised-cosine gust over the run, and `practical_punch` holds throttle at 0.8. Each integration mode is compared only with its own separate high-rate run.

Rates: 60, 120, 240, 480, 960, 1920, 3840 Hz; reference: 3840 Hz; simulated duration: 0.5 s. All durations are integer tick counts. Errors are endpoint position, body velocity, body rate, quaternion angle, and RPM relative to the matching mode's reference.

The observed orders use error-to-reference ratios between adjacent rates. Piecewise propulsion tables and their knots prevent a global fourth-order claim; table-knot diagnostics below show where the production load evaluations sampled ranges spanning knots.

Measurement gates: **PASS**. Smooth throttle-step order must remain within 3.75–4.25 for all five metrics at 60/120/240 Hz; coupled 240 Hz RPM error must stay at or below 0.0002 rpm in all cases; the 0.8 punch must cross propeller Cp/Ct and shaft power knots.

## Coupled RK4

Errors are final-state norms in the units shown; observed order `p` at a coarse rate uses that error divided by the next finer rate's error.

### throttle_step

| Hz | Position (m) | Velocity (m/s) | Rate (rad/s) | Attitude (rad) | RPM | p position | p velocity | p rate | p attitude | p RPM |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 60 | 1.79711e-09 | 3.81838e-08 | 9.70161e-09 | 1.62161e-09 | 1.30027e-06 | 4.01 | 4.06 | 4.02 | 4.04 | 4.03 |
| 120 | 1.1185e-10 | 2.29585e-09 | 5.98258e-10 | 9.87541e-11 | 7.9503e-08 | 4 | 4.03 | 4.01 | 4.02 | 4.02 |
| 240 | 6.96854e-12 | 1.40608e-10 | 3.71867e-11 | 6.09284e-12 | 4.90991e-09 | 3.98 | 4.01 | 4 | 4.01 | 4.03 |
| 480 | 4.40207e-13 | 8.70156e-12 | 2.31713e-12 | 3.78506e-13 | 3.01043e-10 | 1.34 | 3.95 | 4.02 | 3.87 | 4.51 |
| 960 | 1.73502e-13 | 5.63847e-13 | 1.43136e-13 | 2.59217e-14 | 1.31877e-11 | 0.0973 | 3.03 | 4.19 | 2.54 | 2.27 |
| 1920 | 1.62184e-13 | 6.89987e-14 | 7.86029e-15 | 4.46585e-15 | 2.72848e-12 | — | — | — | — | — |
| 3840 | 0 | 0 | 0 | 0 | 0 | — | — | — | — | — |

### smooth_gust

| Hz | Position (m) | Velocity (m/s) | Rate (rad/s) | Attitude (rad) | RPM | p position | p velocity | p rate | p attitude | p RPM |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 60 | 9.66913e-07 | 7.68966e-05 | 8.74484e-06 | 3.03902e-06 | 0.000539748 | 1.89 | 1.88 | 1.85 | 1.88 | 0.225 |
| 120 | 2.60536e-07 | 2.09474e-05 | 2.43357e-06 | 8.26307e-07 | 0.000461951 | 1.91 | 2.01 | 1.73 | 2.04 | 2.11 |
| 240 | 6.94087e-08 | 5.19723e-06 | 7.32519e-07 | 2.00573e-07 | 0.000106764 | 2.24 | 2.58 | 1.99 | 2.62 | 6.53 |
| 480 | 1.47206e-08 | 8.66485e-07 | 1.84969e-07 | 3.25163e-08 | 1.15927e-06 | 3.72 | 3.44 | 2.35 | 2.51 | 0.899 |
| 960 | 1.11866e-09 | 7.97465e-08 | 3.62503e-08 | 5.72744e-09 | 6.21498e-07 | -0.0135 | 0.16 | 0.0392 | 0.0989 | 2.11 |
| 1920 | 1.12918e-09 | 7.13541e-08 | 3.52796e-08 | 5.34798e-09 | 1.44196e-07 | — | — | — | — | — |
| 3840 | 0 | 0 | 0 | 0 | 0 | — | — | — | — | — |

### practical_punch

| Hz | Position (m) | Velocity (m/s) | Rate (rad/s) | Attitude (rad) | RPM | p position | p velocity | p rate | p attitude | p RPM |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 60 | 3.84994e-07 | 2.34061e-06 | 1.18025e-06 | 2.03776e-07 | 0.00140619 | 2.59 | 1.95 | 1.55 | 2.1 | 4.71 |
| 120 | 6.3759e-08 | 6.05165e-07 | 4.03741e-07 | 4.73856e-08 | 5.37674e-05 | 4.44 | 4.17 | 5.97 | 4.7 | 1.92 |
| 240 | 2.94489e-09 | 3.37027e-08 | 6.45181e-09 | 1.8187e-09 | 1.41772e-05 | 0.567 | 1.3 | -0.21 | 0.606 | 1.18 |
| 480 | 1.98817e-09 | 1.36783e-08 | 7.46227e-09 | 1.19468e-09 | 6.27592e-06 | 1.57 | 1.4 | 1.71 | 1.46 | 0.837 |
| 960 | 6.69261e-10 | 5.1862e-09 | 2.27885e-09 | 4.34293e-10 | 3.51262e-06 | -0.0131 | 0.168 | -0.0811 | 0.122 | 0.36 |
| 1920 | 6.75359e-10 | 4.61664e-09 | 2.41063e-09 | 3.99075e-10 | 2.73639e-06 | — | — | — | — | — |
| 3840 | 0 | 0 | 0 | 0 | 0 | — | — | — | — | — |


## Sampled split baseline

Errors are final-state norms in the units shown; observed order `p` at a coarse rate uses that error divided by the next finer rate's error.

### throttle_step

| Hz | Position (m) | Velocity (m/s) | Rate (rad/s) | Attitude (rad) | RPM | p position | p velocity | p rate | p attitude | p RPM |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 60 | 0.000759254 | 0.0040139 | 0.000522908 | 0.000199226 | 0.968302 | 1.04 | 1.03 | 1.03 | 1.03 | 1.03 |
| 120 | 0.000370098 | 0.00196643 | 0.000256901 | 9.73574e-05 | 0.47318 | 1.05 | 1.05 | 1.05 | 1.05 | 1.05 |
| 240 | 0.000178236 | 0.000949419 | 0.000124215 | 4.69462e-05 | 0.228173 | 1.1 | 1.1 | 1.1 | 1.1 | 1.1 |
| 480 | 8.29805e-05 | 0.00044258 | 5.79457e-05 | 2.18705e-05 | 0.106299 | 1.22 | 1.22 | 1.22 | 1.22 | 1.22 |
| 960 | 3.5521e-05 | 0.000189574 | 2.48294e-05 | 9.36498e-06 | 0.0455178 | 1.59 | 1.59 | 1.59 | 1.59 | 1.59 |
| 1920 | 1.18333e-05 | 6.31741e-05 | 8.27574e-06 | 3.12032e-06 | 0.0151661 | — | — | — | — | — |
| 3840 | 0 | 0 | 0 | 0 | 0 | — | — | — | — | — |

### smooth_gust

| Hz | Position (m) | Velocity (m/s) | Rate (rad/s) | Attitude (rad) | RPM | p position | p velocity | p rate | p attitude | p RPM |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 60 | 0.000111595 | 0.00105604 | 0.000190944 | 4.32249e-05 | 1.95513 | 1.03 | 1.01 | 1.04 | 1.01 | 1.05 |
| 120 | 5.47976e-05 | 0.000523098 | 9.31705e-05 | 2.14259e-05 | 0.945973 | 1.05 | 1.09 | 1.1 | 1.08 | 1.06 |
| 240 | 2.64479e-05 | 0.000245241 | 4.35362e-05 | 1.01082e-05 | 0.453449 | 1.1 | 1.08 | 1.08 | 1.08 | 1.1 |
| 480 | 1.23391e-05 | 0.000116287 | 2.0538e-05 | 4.77628e-06 | 0.210837 | 1.22 | 1.21 | 1.22 | 1.21 | 1.23 |
| 960 | 5.29429e-06 | 5.01234e-05 | 8.79677e-06 | 2.0676e-06 | 0.0901868 | 1.59 | 1.61 | 1.6 | 1.61 | 1.59 |
| 1920 | 1.76309e-06 | 1.6407e-05 | 2.89633e-06 | 6.75582e-07 | 0.0300291 | — | — | — | — | — |
| 3840 | 0 | 0 | 0 | 0 | 0 | — | — | — | — | — |

### practical_punch

| Hz | Position (m) | Velocity (m/s) | Rate (rad/s) | Attitude (rad) | RPM | p position | p velocity | p rate | p attitude | p RPM |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 60 | 0.0102347 | 0.0565083 | 0.00995002 | 0.0028146 | 10.815 | 1.04 | 1.03 | 1.03 | 1.04 | 1.03 |
| 120 | 0.0049854 | 0.0276532 | 0.00488497 | 0.0013734 | 5.29032 | 1.05 | 1.05 | 1.05 | 1.05 | 1.05 |
| 240 | 0.00240015 | 0.0133443 | 0.00236092 | 0.000661741 | 2.55285 | 1.1 | 1.1 | 1.1 | 1.1 | 1.1 |
| 480 | 0.00111725 | 0.006219 | 0.00110116 | 0.000308168 | 1.18973 | 1.22 | 1.22 | 1.22 | 1.22 | 1.22 |
| 960 | 0.000478218 | 0.00266349 | 0.000471801 | 0.000131939 | 0.509501 | 1.59 | 1.59 | 1.59 | 1.59 | 1.59 |
| 1920 | 0.000159306 | 0.000887535 | 0.000157245 | 4.39564e-05 | 0.169779 | — | — | — | — | — |
| 3840 | 0 | 0 | 0 | 0 | 0 | — | — | — | — | — |


## Stage and table-knot coverage

`Stage span` lists table abscissae within the min/max values passed to production RK load evaluations. `Endpoint crossed` lists abscissae crossed between consecutive committed tick endpoints; it does not assert that an RK stage landed exactly on a knot.

| Mode | Case | Stage queries | J range | RPM range | Cp J stage span | Ct J stage span | Shaft RPM stage span | Endpoint crossings (Cp / Ct / shaft) |
| --- | --- | ---: | ---: | ---: | --- | --- | --- | --- |
| coupled-rk4 | throttle_step | 480 | 0.6257–0.63998 | 3545.8–3636.5 | — | — | — | — / — / — |
| coupled-rk4 | smooth_gust | 480 | 0.57303–0.65759 | 3477–3545.8 | 0.6, 0.65 | 0.6, 0.65 | 3500 | 0.6, 0.65 / 0.6, 0.65 / 3500 |
| coupled-rk4 | practical_punch | 480 | 0.49799–0.63998 | 3545.8–4729.3 | 0.5, 0.55, 0.6 | 0.5, 0.55, 0.6 | 4000, 4500 | 0.6, 0.55, 0.5 / 0.6, 0.55, 0.5 / 4000, 4500 |
| split | throttle_step | 480 | 0.62566–0.63975 | 3547.1–3636.7 | — | — | — | — / — / — |
| split | smooth_gust | 480 | 0.57296–0.65771 | 3476.6–3545.8 | 0.6, 0.65 | 0.6, 0.65 | 3500 | 0.6, 0.65 / 0.6, 0.65 / 3500 |
| split | practical_punch | 480 | 0.49769–0.63743 | 3560.1–4731.2 | 0.5, 0.55, 0.6 | 0.5, 0.55, 0.6 | 4000, 4500 | 0.6, 0.55, 0.5 / 0.6, 0.55, 0.5 / 4000, 4500 |

## Reproduction

```sh
python3 docs/research/propulsion/G2a-RK4/refinement.py
```

Machine-readable run and source hashes: [`results.json`](results.json).
