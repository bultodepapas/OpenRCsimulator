
### 1280x720

| Case | Runs × frames | Wall p50 (min–max) | Wall p95 | Δ wall p50 vs static | CPU p50 / p95 | GPU p50 / p95 | Draw calls |
| --- | --- | --- | --- | --- | --- | --- | --- |
| burn_color_static | 1 × 600 | 52.1 (52.1–52.1) | 66.4 | -24.8 ms (-32.2 %) | 46.3 / 59.3 | 48.7 / 61.9 | 56 |
| burn_color_uniform | 1 × 600 | 54.3 (54.3–54.3) | 68.2 | -22.6 ms (-29.4 %) | 48.1 / 60.0 | 50.1 / 62.4 | 56 |
| burn_sky_static | 1 × 600 | 59.6 (59.6–59.6) | 73.0 | -17.3 ms (-22.5 %) | 55.4 / 67.8 | 55.7 / 68.2 | 56 |
| static | 3 × 600 | 76.9 (55.0–330.6) | 114.0 | +0.0 ms (+0.0 %) | 68.5 / 101.6 | 71.4 / 105.3 | 56 |
| light2_shadow | 3 × 600 | 101.9 (59.4–222.3) | 152.8 | +25.1 ms (+32.6 %) | 92.2 / 139.2 | 96.0 / 142.9 | 112 |
| burn_sky_uniform | 1 × 40 | 128.4 (128.4–128.4) | 145.3 | +51.5 ms (+67.0 %) | 123.8 / 141.0 | 123.9 / 141.5 | 56 |
| light2 | 3 × 600 | 144.6 (53.8–198.3) | 189.7 | +67.7 ms (+88.1 %) | 128.5 / 169.2 | 134.5 / 174.8 | 56 |
| uniform_realtime256 | 3 × 600 | 177.9 (75.0–234.5) | 243.5 | +101.0 ms (+131.4 %) | 154.6 / 211.1 | 162.5 / 219.1 | 56 |
| mesh_disc | 3 × 600 | 189.4 (54.9–207.1) | 262.6 | +112.5 ms (+146.4 %) | 164.6 / 226.4 | 173.8 / 238.3 | 57 |
| uniform_realtime32 | 3 × 600 | 197.8 (85.3–224.3) | 296.7 | +120.9 ms (+157.3 %) | 172.3 / 258.8 | 181.4 / 268.5 | 56 |
| uniform_incremental | 3 × 600 | 197.8 (74.1–244.0) | 304.7 | +121.0 ms (+157.3 %) | 169.7 / 245.9 | 178.9 / 262.6 | 56 |
| uniform | 3 × 600 | 199.1 (53.1–231.1) | 291.6 | +122.3 ms (+159.0 %) | 168.5 / 254.0 | 178.2 / 262.9 | 56 |
| sky_ambient_uniform_rt32 | 3 × 600 | 223.9 (65.5–363.0) | 336.2 | +147.0 ms (+191.3 %) | 205.5 / 307.7 | 206.4 / 310.2 | 56 |
| sky_ambient_static | 3 × 600 | 253.3 (73.4–264.4) | 349.2 | +176.4 ms (+229.5 %) | 229.3 / 316.5 | 231.1 / 315.7 | 56 |
| sky_ambient_uniform | 3 × 600 | 407.6 (101.6–514.4) | 561.1 | +330.7 ms (+430.2 %) | 385.8 / 527.7 | 388.4 / 533.4 | 56 |

### 1920x1080

| Case | Runs × frames | Wall p50 (min–max) | Wall p95 | Δ wall p50 vs static | CPU p50 / p95 | GPU p50 / p95 | Draw calls |
| --- | --- | --- | --- | --- | --- | --- | --- |
| static | 1 × 300 | 90.1 (90.1–90.1) | 105.3 | +0.0 ms (+0.0 %) | 80.8 / 94.2 | 84.0 / 98.0 | 56 |
| uniform | 1 × 300 | 90.7 (90.7–90.7) | 109.1 | +0.6 ms (+0.7 %) | 80.3 / 96.3 | 83.7 / 100.9 | 56 |
| light2 | 1 × 300 | 101.2 (101.2–101.2) | 116.5 | +11.1 ms (+12.3 %) | 91.0 / 103.5 | 94.3 / 107.8 | 56 |
| mesh_disc | 1 × 300 | 102.7 (102.7–102.7) | 119.5 | +12.5 ms (+13.9 %) | 90.8 / 107.7 | 94.7 / 111.6 | 57 |
| sky_ambient_uniform | 1 × 300 | 139.2 (139.2–139.2) | 177.1 | +49.1 ms (+54.5 %) | 131.6 / 166.9 | 132.0 / 167.2 | 56 |

### Parity (2° FOV, disc ≈ 185 px)

- look az090_el25: B/A disc signal (8-bit) 1.081; centre A [183, 182, 182], B [190, 194, 201]
- look az132_el25: B/A disc signal (8-bit) 1.083; centre A [183, 182, 182], B [190, 194, 201]
- look az060_el41: B/A disc signal (8-bit) 1.074; centre A [183, 182, 182], B [189, 193, 201]
- mask: 32 positions, 8 partly occluded; |t_A - t_B| over 151860 pixels: p50 0.0000, p99 0.0134, max 0.0320
  - az143_el22: mean t_A 0.906, t_B 0.905, max |Δt| 0.025
  - az116_el30: mean t_A 0.939, t_B 0.938, max |Δt| 0.025
  - az134_el38: mean t_A 0.900, t_B 0.900, max |Δt| 0.029
  - az149_el38: mean t_A 0.299, t_B 0.298, max |Δt| 0.013
  - az179_el38: mean t_A 0.862, t_B 0.861, max |Δt| 0.024
  - az122_el46: mean t_A 0.212, t_B 0.211, max |Δt| 0.011
  - az152_el46: mean t_A 0.625, t_B 0.624, max |Δt| 0.020
  - az167_el46: mean t_A 0.845, t_B 0.845, max |Δt| 0.032

### Paired, one process (25 cycles × blocks of 30 frames, 6 settle; 1280x720)

| Config | Samples | Wall p50 / p95 | CPU p50 | GPU p50 | Paired Δ wall vs static: median (IQR) | Δ / static |
| --- | --- | --- | --- | --- | --- | --- |
| light2 | 600 | 72.7 / 116.1 | 64.9 | 68.0 | +3.45 ms (-0.59 … +6.43), 25 cycles | +4.92 % |
| mesh_disc | 600 | 72.1 / 114.3 | 63.1 | 65.8 | +3.65 ms (-1.62 … +7.87), 25 cycles | +5.20 % |
| static | 600 | 70.2 / 129.4 | 61.4 | 64.0 | +0.00 ms (+0.00 … +0.00), 25 cycles | +0.00 % |
| uniform | 600 | 68.4 / 112.6 | 60.8 | 63.5 | -1.87 ms (-5.60 … +3.12), 25 cycles | -2.67 % |

### Cloud-occlusion parity per weather preset (|t_A - t_B|, 286895 pixels: p50 0.0008, p99 0.0120, max 0.0350)

- classic: no layered decks (legacy or clear): see parity_mask
- clear: no layered decks (legacy or clear): see parity_mask
- cirrus (1 decks): partial positions 6/8, max |Δt| 0.035, max |Δ mean t| 0.0022; mean t_A per position: 0.58, 0.59, 1.00, 0.90, 0.60, 0.53, 0.68, 1.00
- fair_cumulus (1 decks): partial positions 2/8, max |Δt| 0.029, max |Δ mean t| 0.0015; mean t_A per position: 1.00, 1.00, 1.00, 1.00, 0.64, 0.57, 1.00, 1.00
- broken (2 decks): partial positions 8/8, max |Δt| 0.027, max |Δ mean t| 0.0019; mean t_A per position: 0.43, 0.63, 0.30, 0.46, 0.36, 0.35, 0.96, 0.53
- overcast (2 decks): partial positions 8/8, max |Δt| 0.007, max |Δ mean t| 0.0003; mean t_A per position: 0.02, 0.02, 0.02, 0.02, 0.02, 0.02, 0.02, 0.02
- prestorm (3 decks): partial positions 8/8, max |Δt| 0.012, max |Δ mean t| 0.0007; mean t_A per position: 0.10, 0.17, 0.01, 0.01, 0.23, 0.05, 0.25, 0.07
- distant_storm (2 decks): partial positions 0/8, max |Δt| 0.000, max |Δ mean t| 0.0000; mean t_A per position: 1.00, 1.00, 1.00, 1.00, 1.00, 1.00, 1.00, 1.00
- electrical_storm (3 decks): partial positions 1/8, max |Δt| 0.006, max |Δ mean t| 0.0008; mean t_A per position: 0.00, 0.02, 0.00, 0.00, 0.00, 0.00, 0.01, 0.00

### Lights (captures)

- moon_shadowed_only: ground luma 0.0773, draw calls 58
- moon_plus_light2_noshadow: ground luma 0.1051, draw calls 58
- moon_plus_light2_shadow: ground luma 0.1074, draw calls 114
- light2_noshadow_only: ground luma 0.0270, draw calls 26
- no_direct_light: ground luma 0.0000, draw calls 26
