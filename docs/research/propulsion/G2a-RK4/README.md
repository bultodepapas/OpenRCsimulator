# G2a / G2b — Coupled propeller shaft

2026-10-09 · **Status: experimental implementation software verified; physical and performance acceptance open.**

The experimental P-51 route advances relative shaft RPM in the same RK4 state as the aircraft. Propeller loads, wake and gyroscopic momentum use the stage RPM; axial inflow uses the stage body state and weather time. Total moist density drives propeller loads, while dry-air charge drives indicated engine torque with mechanical friction unchanged.

The scalar simultaneous solve is

```text
h = I*Omega*a
b = J_inverse * (M_external - omega cross (J*omega + h))
Omega_dot = (Q_net/I - a dot b) / (1 - I*a dot J_inverse*a)
M_body = M_external - I*Omega_dot*a
```

`J` is locked aircraft inertia and `a` is the unit shaft axis. The denominator must be positive: removing axial spin inertia must leave a physical carrier. The resulting body derivative satisfies both total angular-momentum balance and the rotor-only axial torque balance. Existing prop loads already include `-Q_prop`; the additional term is only relative-spin reaction. [Sources and inertia/model caveats](sources.md) support this fixed-axis, axisymmetric formulation.

The default split route remains unchanged. Coupled mode is selected before launch, refuses unsupported aircraft and live changes, and needs reset after a tick-zero change. Continuous layout is optional wake states then RPM. A pure endpoint projection updates the existing RPM aux column only after all RK stages and validation succeed. Checkpoint v4 identifies integration semantics and includes complete weather; wrong mode/layout/RPM mirrors are refused before mutation. Golden v1 refuses the experiment because it omits continuous state.

## Reproduce

```sh
"$(app/get-godot.sh)" --headless --path app -- \
  --aircraft=p51d-mustang-120 --shaft-integrator=coupled-rk4 \
  --weather=hot-high --trace=/tmp/shaft.csv --t=3
python3 app/tests/check_atmosphere_trace.py /tmp/shaft.csv --duration 3
app/test.sh
```

The CSV retains its existing body/aux columns. A distinct `propeller-shaft-coupled-rk4-v1` model and explicit integration, rotor-coupling, continuous-layout and timing metadata identify the experiment. Older readers that do not recognize this propulsion model refuse it.

The [42-run refinement report](report.md) and [raw results](results.json) compare 60–3840 Hz production runs. The smooth throttle step converges at fourth order; gusts and table-crossing punches have irregular order. Across these three 0.5 s fixtures, the largest coupled 240 Hz RPM error relative to a separate 3840 Hz run is 0.0001068 RPM. These are numerical errors for the implemented model, not engine measurement errors. A short [CI refinement test](../../../../app/tests/test_shaft_refinement.gd) checks the smooth case on every gate.

[Session checks](../../../../app/tests/test_shaft_coupled.gd) cover stage RPM/time, relative-spin torque balance, combined wake integration, exact v4 replay, metadata freezing, signed wake increments, mode drafts and complete fault rollback. [Rotor checks](../../../../app/tests/test_rotor_coupling.gd) also verify shaft/body power balance and 10-second internal spin-up: inertial angular-momentum error is 3.36e-14 N·m·s, and integrated-work error is 2.20e-14 J. The [CLI suite](../../../../app/tests/test_shaft_cli.py) checks actual launches, refusal, reference/weather/atmosphere readers and complete-state FPS independence.

The complete `app/test.sh` [gate](test-gate.json) passed **143 GDScript suites**, including 54 focused G2 checks and seven real-app CLI tests. The legacy goldens, float64 guards, all-script parsing, fleet contracts and fixed-frame checks also pass; existing data-estimate notices and exit-time ObjectDB warnings remain, with zero engine errors. [Source manifest](source-manifest.json) identifies the final application/test inputs.

[Isolated mutations](mutations.json), reproduced with [mutation_check.py](mutation_check.py), prove the checks reject an omitted body-acceleration term, reversed rotor reaction and sampled gyro momentum. Control copies pass and live source bytes remain unchanged.

[Serial cost measurement](cost.md) records 1263–1325 µs/step for this coupled P-51 slice on the host, versus 488–525 µs for split in these cases. The 500 µs target stays open. The current stage evaluates aerodynamics twice; reusing one stage evaluation is a measured follow-up, with all torque/convergence/replay contracts retained.

The final [export checks](export-results.json) pass Linux flight smoke and all-platform pack/resource checks. [Source/Linux comparison](native-results.json), reproduced with [native_compare.py](native_compare.py), gives identical numeric rows for calm, hot-high and combined OU/custom-air coupled flights: 721 samples per run, independently checked by the applicable trace reader. Windows/macOS execution remains untested.

The existing G1b1 offline range auditor intentionally refuses this new propulsion model: coupled k1 uses the previous boundary RPM, whereas its split reconstruction uses current-row aux RPM. Extending that tool requires the correct timing contract rather than only accepting the new model name.

Engine-off in this experimental route retains mechanical friction and forward windmilling; it does not implement reverse rotation, fuel/ignition states or a measured stopped-prop drag map. The inherited 1 RPM cutoff zeros prop loads below it and suppresses a negative lumped shaft derivative at or below it; sub-1 RPM relative momentum can remain, so this is not a measured stop/bearing model. Negative RPM stages fail visibly rather than silently clamping the coupled state. CSV reports accepted endpoint RPM and k1 loads; a late-start recording's first prior k1 RPM is not separately recoverable from that CSV. Native checkpoints preserve complete current replay state.
