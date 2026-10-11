# GP-04 aircraft ground scenario measurements

Status: bounded force-only numerical evidence complete; physical calibration and the full handling matrix remain open. Recorded 2026-10-11 with Godot `4.7.2.stable.official.ed1daf0bf` on Windows.

The reproducible driver, `research/ground-physics/aircraft_ground_scenarios.gd`, loads the Ugly Stik 60, Extra 300S 60, and P-51D 120 models, their wheel profiles, and the default field surfaces. It integrates rigid-body motion and independent wheel rim speeds with aerodynamics and propulsion disabled. The 108 cases comprise, per aircraft: 12 coast-downs, six drops, two fixed-attitude touchdown drops, six fixed-position asymmetric surface probes, six dynamic runway-edge crossings, two taxi-steer probes, and two lateral-skid probes. Static support residuals and per-wheel measurements are retained in [aircraft_ground_scenarios.json](aircraft_ground_scenarios.json); the native pinned-engine run is [scenario.log](scenario.log).

All 36 coast-downs reached 0.1 m/s or less. All 18 runway coast-downs ended within the 100 m runway bounds, and rough-field distance was shorter at every tested speed and direction. The 10 m/s direction-averaged results were:

| Aircraft | Runway distance | Rough distance | Initial load-weighted Crr, runway / rough |
| --- | ---: | ---: | ---: |
| Ugly Stik 60 | 51.389 m | 16.612 m | 0.10073 / 0.30343 |
| Extra 300S 60 | 49.348 m | 16.354 m | 0.10528 / 0.31265 |
| P-51D 120 | 65.046 m | 21.244 m | 0.07927 / 0.24509 |

Initial rolling forces reproduce the independently recomputed profile/surface coefficients to floating-point output precision. Across the 36 cases, rollout distance differs from the constant-drag estimate based on initial load-weighted Crr by at most 4.40% (Extra on rough ground). These are model-internal checks, not measured rollout calibration.

The 0.1 m and 0.3 m drop tests were refined at 240, 480, and 960 Hz. Peak compression ranged from 0.04599–0.04602 m and 0.07337–0.07385 m for the Stik; 0.05743–0.05749 m and 0.09141–0.09162 m for the Extra; and 0.06601–0.06604 m and 0.10312–0.10319 m for the P-51. Rebound is measured after the first upward velocity reversal and ranged from 0.03415–0.03435 m and 0.06960–0.07013 m; 0.04888–0.04897 m and 0.10546–0.10591 m; and 0.04614–0.04620 m and 0.10423–0.10447 m, respectively. The largest adjacent-rate change in peak compression or rebound was 0.76%. Every drop stayed finite and within the 0.02 J mechanical-energy tolerance; the maximum measured energy gain was 3.41e-13 J. The Stik's 0.3 m drops had one contact-loss/reacquisition event at each rate; other drop cases had none.

The driver also compares peak compression against each contact's configured `max_compression` value. Those values are provisional numerical thresholds, not measured available travel or structural strength ([Extra profile source](../../../../app/data/aircraft/gp_extra_300s_60.json), [P-51 profile source](../../../../app/data/aircraft/p51d_mustang_120.json)). The 0.1 m drops stayed below every threshold. At 0.3 m, all three Extra wheels exceeded their thresholds: the mains reached 0.09162/0.08 m and the tail reached 0.07577/0.05 m, for peak over-limit distances of 0.01162 m and 0.02577 m. The P-51 tail reached 0.10319/0.08 m, 0.02319 m over its threshold; its mains stayed below 0.12 m. The Stik's maximum, 0.07385 m, stayed below its 0.12 m limits. The Extra's −5° touchdown drop also crossed the tail threshold by 0.000012 m. The JSON records per-wheel peaks and exceedances. These flags identify a modeled threshold crossing; they do not assert that a real gear leg collapses or survives.

The level and −5° fixed-attitude touchdown drops capture first-contact order. The Stik level case reached both mains at 0.125 s and its nose wheel at 0.129 s; the −5° case reached the nose at 0.100 s before the mains at 0.129 s. The Extra reached all wheels at 0.125 s when level; its −5° case reached the mains at 0.125 s and tail at 0.183 s. The P-51 reached its tail at 0.113 s and mains at 0.125 s when level; its −5° case reached the mains at 0.125 s and tail at 0.196 s. These are free-drop contact-order checks, not powered or aerodynamic landings.

Each aircraft has six dynamic edge crossings: 2, 5, and 10 m/s in both directions, starting from a supported pose 0.1 m inside the lower runway edge and moving diagonally across the seam. All 18 runs crossed both main wheels at distinct 240 Hz samples while loaded; every recorded transition had positive normal load on both sides, and the transition speeds were above 0.1 m/s (minimum 0.385 m/s). Material changes updated the rolling coefficient in the expected direction: main-wheel Crr changed between 0.100 and 0.300 for the Stik and Extra, and 0.075 and 0.225 for the P-51. No crossing case lost contact. The largest per-wheel normal-load step was 21.1 N (P-51 at 10 m/s). Terrain height differed by 3.42e-8 m across a 2 μm static seam bracket; the largest dynamic height-continuity residual was 3.96e-5 m. The fixed-position asymmetric probes also record individual material assignments and reversing yaw-moment signs between eastbound and westbound runs; they do not substitute for transient crossings.

The 0.5 s taxi-steer probes at ±0.2 produce opposite yaw signs (Stik −5.14/+5.17°, Extra −3.01/+3.01°, P-51 −2.35/+2.39°). Ground-only lateral-skid probes at ±0.5 m/s produce side forces opposing the skid.

Reproduce the measurements from the repository root with:

```powershell
& .tools\Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy --script "$PWD\research\ground-physics\aircraft_ground_scenarios.gd" -- "--out=$([IO.Path]::GetFullPath('docs\research\ground-physics\GP-04\aircraft_ground_scenarios.json'))" *> docs\research\ground-physics\GP-04\scenario.log
```

This evidence does not cover aerodynamic crosswind response, powered takeoff or landing, taxi on a deliberately inclined surface, brake-driven nose-over, or ground-loop/crash acceptance. No wheel/grass coefficient is presented as physically measured.
