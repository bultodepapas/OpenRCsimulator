# M5-ATM-2 fleet parity and simulation-step cost

2026-10-09 · **Status: observational software measurement; physical acceptance remains open.**

The frozen reference is the clean `9a4eabd` archive at `/tmp/openrc-atmosphere-baseline/app`. The candidate is the working tree based on `9a4eabd`, with the M5-ATM-2 changes in place. Before measuring, the exact candidate [benchmark harness](../../../../app/tests/bench_wind.gd) was copied into the frozen archive's `tests/` directory. Its SHA-256 was `ced8595ba941554eaf260e2bcec7a944eb5f45d275277189fed183fe4a9eeacb` in both trees.

All runs used Godot 4.7.2-stable official (`ed1daf0bf001b61586d9930840f2f1394092c079`), headless on Linux x86_64, Intel Core i5-10500, 12 logical CPUs. The complete `app/test.sh` gate had exited 0 (140 GDScript suites, no engine errors), and the UI captures were finished before the three serial runs. No other Godot or capture process was active during a run. The host's 1/5/15-minute load averages immediately before each run were `0.60/1.10/1.25` (frozen calm), `1.09/1.17/1.27` (candidate calm), and `1.00/1.14/1.26` (candidate hot-high); shared-host activity remains a measurement limitation.

For each airframe and trim, 15°-alpha stall, and ground fixture, the harness performed seven samples of 240 `session.sim.step()` calls, each preceded by 240 untimed warm-up steps and fixture restoration. It divides each timed batch duration by 240 and reports the median of those seven batch means. These are simulation-step timings, not per-tick tail percentiles or full rendered-frame timings. All three raw reports retain the seven measured batch means for each case.

The two calm runs accepted the same `openrc-weather v1` calm configuration. The custom run used [`hot-high.json`](hot-high.json): 1,500 m field elevation, 35 °C, QNH 1013.25 hPa, 50% RH, and zero wind, gust, or turbulence.

## Exact calm reference parity

At every checkpoint below, both the packed snapshot SHA-256 and cumulative trajectory SHA-256 match exactly between the frozen baseline and candidate calm run. The trajectory hash covers packed snapshots from tick 0 through the checkpoint; the raw reports contain the numeric state arrays as well.

| Airframe ID | Tick | Snapshot SHA-256 | Cumulative trajectory SHA-256 |
| --- | ---: | --- | --- |
| `jensen-das-ugly-stik-60` | 0 | `70f6ea089f4824bd859fd477a5f9fe61a920c4cd34fbd95abc97da6613112560` | `70f6ea089f4824bd859fd477a5f9fe61a920c4cd34fbd95abc97da6613112560` |
| `jensen-das-ugly-stik-60` | 240 | `bc96a1560e3cfabbceded978335a4e2c3f2f489bd13f186161a8976443ee053a` | `b6e0d514da1b3af90ed9eda1b417ab12c3dc50eb4f0da7c7b894622feed1e710` |
| `jensen-das-ugly-stik-60` | 480 | `b81f04c01f1087a7977e30f4de06163595d631c9fc85e4a95c02f36c6ab74f96` | `c5d2465231e1acdccd55d911e53e88fcfd80bb55c5a54f7b4907515b93cf2a6b` |
| `gp-extra-300s-60` | 0 | `00e73b30e516051976f3ffd295cf42a414f067f8b3294f49f7be57d1467d91d0` | `00e73b30e516051976f3ffd295cf42a414f067f8b3294f49f7be57d1467d91d0` |
| `gp-extra-300s-60` | 240 | `447eab9a97b063c643592a1d684872f5f8346ae6034d018d13ff2c5c7659ad39` | `cd4e871aa329d52721e45789aa8e2281bd65bab3eee4e5c3589ebcbfd6d937c5` |
| `gp-extra-300s-60` | 480 | `2146c3f37bc229ba4934adba518cfbcc19e1c0efa287d2cf11f46963a3e81b0a` | `ea081708f6628888970dd14d208cc45d8e41f21185c0d74db8ae5057eca89e6c` |
| `p51d-mustang-120` | 0 | `546cefb599c50a707475a77d09fa87f6552868504ad06a5a1b5107033cee6433` | `546cefb599c50a707475a77d09fa87f6552868504ad06a5a1b5107033cee6433` |
| `p51d-mustang-120` | 240 | `2bba8d13fd17f3e71fd70b2e6acca75557456478cf01070cfd38100e1260adb1` | `540704a5ca124c5fb40877712d907969a50cb5af467d185b8d54cd67d0e9c5eb` |
| `p51d-mustang-120` | 480 | `2bbd7889c289f4a604551713cbd35b07c40eb882bf89f53bead3490bad97d1d5` | `96cab339a1dfe5d354c7c94365eb1401dff3ce3cca92fa21e7a29f70f7a539ea` |
| `sebart-avanti-s-a200-p100rx` | 0 | `b4be80cf5ff24dfe4b1a980c2bd0f1412c663d3f283daff5a2aa6b912cdeecb1` | `b4be80cf5ff24dfe4b1a980c2bd0f1412c663d3f283daff5a2aa6b912cdeecb1` |
| `sebart-avanti-s-a200-p100rx` | 240 | `40572db05ffc8db65bfbbe249e2f595b6dce07a3dc23e9df22b0998ea8404bcb` | `f9c9af9051f3f2729cd98cabbba4ea434f624bb84b0de29663a87fc93563d117` |
| `sebart-avanti-s-a200-p100rx` | 480 | `08f38901b1a496ff94ddc04d6adfc783353a04dbca3b0b9748bc3e9be9820ca2` | `5c04afcb0582579418f240aa3390a094374ccbf3d93dbcc6d29f2ccba20fed18` |

## Median cost

Values are microseconds per simulation step. Reference delta is candidate calm versus frozen calm. The raw JSON stores the full precision medians and all seven batch means.

| Airframe ID | Fixture | Frozen calm | Candidate calm | Reference delta | Candidate hot-high |
| --- | --- | ---: | ---: | ---: | ---: |
| `jensen-das-ugly-stik-60` | trim | 366.971 | 369.692 | +0.74% | 379.954 |
| `jensen-das-ugly-stik-60` | stall | 358.438 | 383.829 | +7.08% | 400.175 |
| `jensen-das-ugly-stik-60` | ground | 415.800 | 430.492 | +3.53% | 444.808 |
| `gp-extra-300s-60` | trim | 267.258 | 274.050 | +2.54% | 270.458 |
| `gp-extra-300s-60` | stall | 291.583 | 285.096 | −2.22% | 286.633 |
| `gp-extra-300s-60` | ground | 410.275 | 420.321 | +2.45% | 418.879 |
| `p51d-mustang-120` | trim | 527.013 | 547.442 | +3.88% | 517.983 |
| `p51d-mustang-120` | stall | 526.754 | 574.054 | +8.98% | 543.558 |
| `p51d-mustang-120` | ground | 354.275 | 370.242 | +4.51% | 380.875 |
| `sebart-avanti-s-a200-p100rx` | trim | 302.625 | 319.192 | +5.47% | 317.229 |
| `sebart-avanti-s-a200-p100rx` | stall | 325.942 | 319.788 | −1.89% | 324.029 |
| `sebart-avanti-s-a200-p100rx` | ground | 289.933 | 287.554 | −0.82% | 283.921 |

The largest reported median is 574.054 µs for the candidate P-51 stall fixture, about 13.8% of a 240 Hz interval (4,166.7 µs). This is a median of batch means, not a bound on individual ticks, and excludes rendered-frame work. Timing changes have mixed signs and the sample distributions overlap; this single sequential comparison does not isolate a causal atmosphere overhead or establish performance acceptance. The P-51 cost budget remains open.

The measurement says nothing about physical acceptance. It does not validate engine output against field data or support a blanket torque correction.

## Raw reports

- [Frozen reference calm](cost-baseline-calm.json) — SHA-256 `30a2b8e4a9ae9893c3ec1d39da8af73fdb97a26862ddf545069e3f94bb9652b1`
- [Candidate calm](cost-candidate-calm.json) — SHA-256 `5c5fb3f574f767c7991370d22322e14a0cdf67fa98a57ea7e72b11b36ede2161`
- [Candidate hot-high](cost-candidate-hot-high.json) — SHA-256 `896939d8e89150f652f03931b3d7e833fde0f01ace9642d7593ed00061e986c1`
