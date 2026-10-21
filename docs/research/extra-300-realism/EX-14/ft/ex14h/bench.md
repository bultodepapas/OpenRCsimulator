# EX-14h post-stall bench (post_stall_sweep.gd, static loads at 25 m/s, controls neutral)

Rows: the legacy blend (Extra data at 1a00c874~1), the adopted polar (shipped data), and Sandia NACA 0015 and 13 % (0012/0015 interpolated) section polars at Re 360,000 by the Avanti AV-17-R2 policy (research/extra-300/ex14/sandia_polar.py).

FASER: CLmax 0.937 at 15.0°; measured Clp + Clβ̇ sin α at 20 / 25 / 30 / 35°: +0.00 / +0.08 / +0.08 / +0.19
| Data | CLmax at α | RMS retention error (15–30°) | RMS Clp error (10–17.5°) | Clp > 0 below 17.5° | Clp at 20 / 25 / 30 / 35° (reference only) |
| --- | --- | --- | --- | --- | --- |
| extra-legacy.json | 1.041 at 14.0° | 0.297 | 0.853 | 3 of 6 | -0.19 / -0.20 / -0.22 / -0.23 |
| gp_extra_300s_60.json | 1.002 at 14.0° | 0.059 | 0.255 | 1 of 6 | +0.03 / -0.14 / -0.17 / -0.18 |
| extra-s15.json | 0.993 at 14.0° | 0.174 | 0.292 | 2 of 6 | +0.11 / +0.00 / -0.25 / -0.34 |
| extra-s13.json | 1.019 at 14.0° | 0.243 | 0.662 | 3 of 6 | +0.11 / -0.25 / -0.32 / -0.35 |
extra-legacy.json Clp: 12:-0.50 14:+0.17 15:+0.79 16:+0.99 17:+0.84 18:+0.48 19:-0.02 20:-0.19 22:-0.20 25:-0.20 30:-0.22 35:-0.23 40:-0.24
gp_extra_300s_60.json Clp: 12:-0.46 14:+0.07 15:+0.01 16:-0.16 17:-0.21 18:-0.24 19:-0.15 20:+0.03 22:+0.06 25:-0.14 30:-0.17 35:-0.18 40:-0.23
extra-s15.json Clp: 12:-0.38 14:-0.15 15:-0.02 16:+0.02 17:+0.00 18:+0.05 19:+0.03 20:+0.11 22:+0.25 25:+0.00 30:-0.25 35:-0.34 40:-0.17
extra-s13.json Clp: 12:-0.42 14:-0.11 15:+0.08 16:+0.24 17:+0.47 18:+1.04 19:+0.61 20:+0.11 22:-0.10 25:-0.25 30:-0.32 35:-0.35 40:-0.21
