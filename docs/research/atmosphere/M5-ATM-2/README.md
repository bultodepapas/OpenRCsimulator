# M5-ATM-2/3: atmosphere through flight

2026-10-09 · **Status: implemented; final software verification below. Physical acceptance remains open.**

The conditions editor now pairs **14 sliders** with precise numeric entries across wind, gusts, turbulence and atmosphere. The accent tracks, large vector thumbs, visible units and keyboard focus make adjustment practical; untouched/typed values are not quantized by initialization. Apply/Cancel and scrolling preserve their existing contracts.

Home → Weather → Atmosphere configures field elevation, temperature, QNH and liquid-water RH. Reference air keeps the original density literal; custom air drives the same density through trim, stage aerodynamics, propeller/turbine loads, shaft prop load, downwash, transported wake and runway static solving. Catalog start speed remains true airspeed. Infeasible trims fail visibly instead of flying the old sea-level trim.

[Kernel/source evidence](../M5-ATM-1/kernel/README.md) distinguishes the ISA pressure reduction, ambient field temperature, total moist density and dry-air charge. [Trim evidence](trim.md) records the optional density/charge interface and six-axis residual verification. The naturally aspirated shaft correction scales indicated torque with dry-air charge and leaves friction fixed. NACA's [humidity study](https://ntrs.nasa.gov/archive/nasa/casi.ntrs.nasa.gov/19930091500.pdf) supports the oxygen-intake dependence; this first-order implementation is an estimated correction rather than an RC engine measurement. Prescribed-RPM glow models and the existing turbine density/ram map keep their own assumptions.

Custom atmosphere is uniform for the whole flight; no altitude-dependent sounding, gravity variation, Reynolds-dependent polars or fuel/ECU thermodynamics are added. Elevation is a pressure input, not a terrain translation. EAS and density altitude describe the field condition separately from actual TAS/AGL altitude.

## Proof

- [Flight integration](../../../../app/tests/test_atmosphere_flight.gd): 139 checks covering all four airframes, reference byte parity, six-axis custom-density equilibrium, one-second level hold, fixed-density/EAS telemetry, reset, fresh-reference checkpoint adoption, malformed restore refusal, extreme-field trim refusal/recovery, combined OU replay, runway static state, dry-charge/friction algebra, shaft update and per-propulsion load scaling.
- [Trim checks](../../../../app/tests/test_trim_density.gd): 35 checks, including sea-level default equality across the fleet, density/ratio validation, equal-qbar glide scaling and explicit P-51 charge propagation.
- [Independent telemetry](telemetry.md): v6 re-evaluates field atmosphere and row EAS, then validates the wind/OU contract through a strict projection to the existing independent reader.
- [UI/capture checks](ui.md): EN/ES, legacy draft preservation, v3 schema, numeric bounds/precision, saved preferences, mode switch, focus/scroll and Home→Fly.

The complete `app/test.sh` gate passed: **140 GDScript test suites**, all-script parsing, float64 guards, six atmosphere CLI tests, legacy golden flights, model contracts and 30/60/144 FPS checks. [Gate summary](test-gate.json) records the log identity and exit status; existing data-estimate notices and exit-time ObjectDB warnings remain. [Source manifest](source-manifest.json) identifies the application/test inputs. Generated captures/packages remain local outputs; reports link tracked evidence and source tools.

The final [export check](export-results.json) generated Linux, Windows and macOS packages and passed Linux flight smoke and all-platform pack/resource checks. [Native comparison](native-results.json), reproduced with [native_compare.py](native_compare.py), independently verifies 721 samples per run: exact source/Linux numeric rows for all four hot-high aircraft and a P-51 case combining wind, gusts, OU turbulence and custom air. Windows/macOS execution remains untested.

[Observed step cost and frozen-baseline parity](cost.md) preserve raw serial measurements. Reference-air snapshots and cumulative trajectories match frozen `9a4eabd` exactly at ticks 0/240/480 for all four aircraft. The P-51 still exceeds the 500 µs target in both baseline and candidate cases; performance acceptance remains open.

## Reproduce

```sh
"$(app/get-godot.sh)" --path app -- --weather=hot-high
"$(app/get-godot.sh)" --headless --path app -- --weather=hot-high --trace=/tmp/air.csv --t=3
python3 app/tests/check_atmosphere_trace.py /tmp/air.csv --duration=3
app/test.sh
```

`--weather-file=path.json` accepts complete weather v3, including combined gusts/turbulence/custom atmosphere. Reference mode keeps the existing default physics. No new dependency or aircraft coefficient is introduced.


Preferences with weather v3 save outer schema 3; weather v1/v2 retain schemas 1/2. The actual frozen schema-2 reader refuses to overwrite the new file: [older-reader.json](older-reader.json) records identical before/after hashes and `ERR_FILE_NO_PERMISSION`. Reproduce the writer/older-reader experiment with [schema_probe.gd](schema_probe.gd) against their respective app trees.
