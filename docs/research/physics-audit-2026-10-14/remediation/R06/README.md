# R06 Slice A: isolated Stik wash candidate

This evidence adds a separate, experimental aircraft-v2 file for the Jensen Ugly Stik 60. The production aircraft, catalog, runtime and existing documentation are unchanged. The candidate is stateless: it uses the current optional slipstream calculation without transported wake state, new fuel behavior or a Glow-installation guard change. It is not promoted or physically calibrated.

The candidate generator reads the existing E0b2 geometry handoff and E0b3b generated profile. It checks that the E0b2 visual geometry matches its compiled runtime source, compares a fresh E0b2 derivation semantically with the checked-in geometry handoff using an absolute numeric tolerance of `2e-12`, checks that the three E0b3b areas match the E0b2 polygons, and runs E0b3b's exact `--check`. The strict E0b2 `--check` currently exits 1 because its regenerated JSON prints several mathematically equivalent polygon areas with different last-bit decimal spellings (for example `0.04629457865` and `0.046294578649999994`). That result is retained in [e0b2-strict-check.log](e0b2-strict-check.log); no E0b2 output was rewritten. The candidate's own generator `--check` passes.

The generated [aircraft-v2 candidate](../../../../../research/physics-audit-2026-10-14/remediation/stik_wash_candidate/aircraft_v2.json) preserves the production model ID so the same external wheel profile applies. Its separate location and input hash keep it out of the catalog. The hub and tail-piece geometry are derived from estimated visual geometry, not owner measurements. The profile reuses the three E0b3b groups: mirrored neutral horizontal-tail halves and the vertical fin/rudder outline. The horizontal neutral coverage plane remains 5 mm above the current aerodynamic load reference; the existing slipstream code keeps that load reference for moments.

The exact non-geometric values come from `app/tests/test_wash_profile.gd::combined_raw()` and are copied as **estimated assumptions**, not measurements or fitted gains:

| Quantity | Candidate value | Provenance |
|---|---:|---|
| `thrust_angles` | `[0, 0] deg` | Estimated explicit shaft-axis assumption from the existing fixture setup |
| `wash_factor` | `[1.0, 1.4]` | Estimated static/forward-flow fixture values |
| `swirl_factor` | `0.0` | Estimated fixture value; excludes modeled swirl |
| `vertical_drift` | `0.543` | Estimated fixture value |
| `edge_fraction` | `0.15` | Estimated occupancy-smoothing fixture value |
| `reverse_fade` | `[0.1, 0.2]` | Estimated reverse-flow fixture values |

Every candidate coefficient carries this source string in the aircraft data: `app/tests/test_wash_profile.gd::combined_raw; copied exactly as an estimated experimental test configuration, not measured or calibrated`. Geometry quantity sources retain the E0b2/E0b3b generator provenance. In particular, this experiment does not infer a real radial velocity profile from the smooth occupancy parameter.

`AircraftData.load_file()` accepts both files. The baseline remains without `propulsion.slipstream`; the candidate contains three stateless wash pieces and retains the baseline model ID and applied wheel profile. The probe also checks that engine-off candidate elevator/rudder moment slopes exactly equal the baseline free-flow slopes.

The control-authority measurements below use calm air at `rho=1.225 kg/m3`, zero body rates, `alpha=0 deg`, and actual surface deflections of `±0.01 rad` (central difference, reported per radian). The motor-on row holds the existing prescribed engine model at its authored `max_rpm=11,149 rpm`; this is a rated-static prescribed-RPM comparison, not an RPM/torque measurement or a load-responsive shaft result. Moments are body-axis `My` for elevator and `Mz` for rudder. These are outputs of the current aerodynamic and slipstream laws, not claims about the real airframe.

| Speed | RPM case | Baseline `dMy/dδe` | Candidate `dMy/dδe` | Wash addition | Baseline `dMz/dδr` | Candidate `dMz/dδr` | Wash addition |
|---:|---|---:|---:|---:|---:|---:|---:|
| 0 m/s | Engine off, 0 rpm | 0.000000 | 0.000000 | 0.000000 | 0.000000 | 0.000000 | 0.000000 |
| 0 m/s | Estimated idle, 2,800 rpm | 0.000000 | -0.467638 | -0.467638 | 0.000000 | -0.298233 | -0.298233 |
| 0 m/s | Rated-static, 11,149 rpm | 0.000000 | -7.414214 | -7.414214 | 0.000000 | -4.728371 | -4.728371 |
| 5 m/s | Engine off, 0 rpm | -1.815667 | -1.815667 | 0.000000 | -0.723931 | -0.723931 | 0.000000 |
| 5 m/s | Estimated idle, 2,800 rpm | -1.815667 | -2.967124 | -1.151457 | -0.723931 | -1.394023 | -0.670092 |
| 5 m/s | Rated-static, 11,149 rpm | -1.815667 | -13.990806 | -12.175139 | -0.723931 | -8.265441 | -7.541511 |
| 15 m/s | Engine off, 0 rpm | -16.341003 | -16.341003 | 0.000000 | -6.515378 | -6.515378 | 0.000000 |
| 15 m/s | Estimated idle, 2,800 rpm | -16.341003 | -15.292491 | +1.048511 | -6.515378 | -5.939615 | +0.575763 |
| 15 m/s | Rated-static, 11,149 rpm | -16.341003 | -33.949584 | -17.608581 | -6.515378 | -16.932072 | -10.416694 |
| 29 m/s | Engine off, 0 rpm | -61.079038 | -61.079038 | 0.000000 | -24.353035 | -24.353035 | 0.000000 |
| 29 m/s | Estimated idle, 2,800 rpm | -61.079038 | -59.340385 | +1.738652 | -24.353035 | -23.393073 | +0.959963 |
| 29 m/s | Rated-static, 11,149 rpm | -61.079038 | -74.069965 | -12.990928 | -24.353035 | -31.721208 | -7.368173 |

The signed slopes follow the current surface sign convention: positive elevator is trailing-edge down and positive rudder is trailing-edge left. The `0 m/s` engine-on result is a steady axial-wash calculation with prescribed RPM; it does not model an engine actually starting at rest.

The [extended probe](authority-extended.log) adds the authored estimated idle RPM and 29 m/s cases: **37 checks, 0 failed**. At idle and high advance speed, the modeled wash reduces tail-authority magnitude; the test requires finite response rather than assuming every spinning-prop condition increases authority. These values do not qualify the propeller's windmilling quadrant or measured idle installation behavior. The original 27-check log and its source identities remain historical evidence.

One 240-tick/1-second same-input session pair also ran through `FlightSession`. Both started from the baseline's fresh 15 m/s trim and had byte-equal initial body, input, auxiliary and continuous arrays; the candidate had the same input/continuous-state layout and received the baseline input vector `[0.0203603743602471, 0.081665568916526, 0.0249785446538168, 0.282148546613114]` at every tick. Initial RPM was `5,155.658216`. Both remained finite. Across the run, the largest baseline/candidate deltas were `0.08235 m` position, `0.06802 m/s` velocity, `0.01757 rad` attitude and `0.02030 rad/s` angular rate. This open-loop comparison isolates the candidate law under a shared start and command; it is not exact replay, retrimmed-candidate equivalence or physical validation.

A further **six-second, 1,441-row** experiment uses the complete [R11 Stik recording](../R11/final-scenarios-03/stik/candidate.orfl), whose own exact replay passed, and changes only to this generated candidate. The [candidate replay report](same-tape-6s/replay.json) records `mode=candidate`, `status=ok`, `complete=true`, and `solver_changed=false`; baseline and candidate use solver SHA-256 `3877ec2dab0d72194f979ad85c396a2ecc40aa8388cd31b252ea99dd10584123`. It preserves every input tick and the complete baseline initial state. [Comparison](same-tape-6s/comparison.json): maximum position component difference `2.339964 m`, velocity component `0.654389 m/s`, angular-rate component `0.142508 rad/s`, and attitude angle `0.045076 rad`. These component maxima differ from the vector norms in the short probe above. They quantify the effect of the wash assumptions; they do not demonstrate an improvement in real-flight prediction or a newly trimmed candidate.

The stopped, transported-wake diagnostic is separate from the stateless candidate. With `rpm=0`, per-piece transported increments `[2, 2, 2] m/s`, zero rates and body axial velocity sampled at `[-1e-8, 0, +1e-8] m/s`, the current branch at [slipstream.gd:57](../../../../../app/physics/slipstream.gd#L57) returns exact zero on the negative side and finite tail loads at zero/positive flow. The one-sided jump is `0.004311 N` force norm and `0.002925 N·m` moment norm; exact-zero loads are `[-0.0014755583, 0, -0.0040502547, 0, -0.0029246083, 0]` in `[Fx,Fy,Fz,Mx,My,Mz]`. The diagnostic identifies the binary `v[0] >= 0` fade as the boundary; it does not change the runtime or select a replacement law. A future transport slice must define the residual wake's behavior under flow reversal and test both one-sided limits with nonzero stored wake before choosing a continuous closure.

## Reproduction

From the repository root:

```powershell
python research/physics-audit-2026-10-14/remediation/stik_wash_candidate/derive_candidate.py
python research/physics-audit-2026-10-14/remediation/stik_wash_candidate/derive_candidate.py --check
& .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy --script C:/DEVELOPMENT/OpenRCsimulator/research/physics-audit-2026-10-14/remediation/stik_wash_candidate/probe.gd
& .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy --script res://tests/test_wash_profile.gd
& .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy --script res://tests/test_slipstream_downwash.gd
```

The candidate generator output is captured in [candidate-generator-check.log](candidate-generator-check.log). The probe, fixture-test and downwash-test output are [stik-wash-candidate-probe.log](stik-wash-candidate-probe.log), [test_wash_profile.log](test_wash_profile.log) and [test_slipstream_downwash.log](test_slipstream_downwash.log). The two existing tests pass `20/0` and `15/0`; the candidate probe passes `27/0`. [source-identities.json](source-identities.json) records the source/candidate hashes. The probe log records baseline SHA-256 `5fe8ece91b7ebe92f304f764f0d50edc936ae5c4ab1d1c801cf20827ec1ee9b6` and candidate SHA-256 `dfd289f5c8f392fb12e247b1cb14803feafd337339f1baf372154d2c53cedb20`.

The result is an experimental software composition with quantified model response. Geometry, wash gains, radial occupancy, zero swirl, reverse fading, RPM and the real installation response remain unmeasured. It does not close R06 physical validation, load-responsive shaft behavior, stopped-propeller aerodynamics, fuel mass or Glow lifecycle composition.
