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

[Serial cost measurement](cost.md) records 1263–1325 µs/step for this coupled P-51 slice on the host, versus 488–525 µs for split in these cases. The 500 µs target stays open. That initial stage evaluated aerodynamics twice. [G2a-R1](../G2a-R1/README.md) now reuses one stage evaluation with exact frozen-baseline trajectory parity and reduced measured cost.

The final [export checks](export-results.json) pass Linux flight smoke and all-platform pack/resource checks. [Source/Linux comparison](native-results.json), reproduced with [native_compare.py](native_compare.py), gives identical numeric rows for calm, hot-high and combined OU/custom-air coupled flights: 721 samples per run, independently checked by the applicable trace reader. That trace matrix has no Windows/macOS counterpart; narrow native Windows coverage for the stopped-shaft change is recorded below.

The existing G1b1 offline range auditor intentionally refuses this new propulsion model: coupled k1 uses the previous boundary RPM, whereas its split reconstruction uses current-row aux RPM. Extending that tool requires the correct timing contract rather than only accepting the new model name.

Engine-off in this experimental route retains mechanical friction and forward windmilling; it does not implement reverse rotation, fuel/ignition states or a measured stopped-prop drag map. The inherited 1 RPM cutoff zeros prop loads below it and suppresses a negative lumped shaft derivative at or below it; sub-1 RPM relative momentum can remain, so this is not a measured stop/bearing model. Negative RPM stages fail visibly rather than silently clamping the coupled state. CSV reports accepted endpoint RPM and k1 loads; a late-start recording's first prior k1 RPM is not separately recoverable from that CSV. Native checkpoints preserve complete current replay state.

2026-10-19 boundary regression: at engine-off rest, the scalar 1 RPM cutoff can return zero shaft rate while the simultaneous body solve still induces negative relative spin. The session resolves the cutoff's existing negative-torque suppression as a bounded static-friction constraint, using the authored zero-speed friction term and stage-local live inertia/mass properties. The ordinary momentum-coupling solve still closes the shaft/body torque balance; demand outside the bound refuses as unsupported reverse breakaway rather than clamping RPM. In the P-51 trim-reset fixture, required static torque is `5.8211e-5 N·m` against the authored `0.5 N·m` bound, and all four zero-RPM RK stages complete.

A near-cutoff sweep showed that the static-lock fix alone still allowed RK4's k4 trial to go negative from 1.000001, 1.001 or 1.01 RPM at 240 Hz. The fixed-wing model now refines the existing RK4 substeps when the estimated engine-off shaft stage drop nears the available nonnegative RPM domain, with 25% headroom. It does not project or clamp stages/endpoints or add a stop event. Invalid or nonfinite estimates request more than the kernel's 16-piece cap, which fails the tick closed before state advances instead of converting a malformed estimate to a count.

With the P-51 engine off and full usable fuel, all stage evaluations stayed nonnegative and fuel/event state stayed unchanged for starts `1.000001, 1.001, 1.01, 1.02, 1.05, 2.0 RPM` at 120, 240 and 480 Hz. The 240 Hz cases used 2 pieces near cutoff and 1 at 2 RPM; 120 Hz used 3 pieces near cutoff and 2 at 2 RPM. A 1.000001 RPM start ends at 0.6612844, 0.7459636 and 0.7459636 RPM at 120, 240 and 480 Hz respectively, then remains sub-1 RPM because the inherited scalar law returns zero rate there. Finite fuel at `1e-8 kg` locates `fuel_exhausted` at 0.000125 s within a two-piece tick without a negative RPM stage; the following zero-fuel/latch-off tick also refines while legacy `engine_running` remains true. A 16 Hz stress case requests 20 pieces and is rejected before state advancement; no count is clipped. The sub-1 RPM residual is existing model behavior, not a physical stop event or measured static-friction law. `FlightLog.solver_identity()` hashes `app/sim` and `app/physics` source bytes, so the runtime change appears in new flight-log solver hashes.

On 2026-10-19, native Windows `ShaftCLI.test_production_finite_fuel_defaults_to_coupled_and_refuses_split` confirmed explicit split selection is refused for the finite-liquid P-51 during preparation before trim/model commit or trace output, matching post-load validation; the final complete coupled candidate replay (`solver_changed=true`, 961 rows) matched the exact baseline across 4.0 s with zero body-state differences as a software regression control only ([flight-log manifest and retained files](flight-log-2026-10-19/flight-log-manifest.json)), while stopped-shaft behavior remains covered by the focused gates above.

To reproduce the evidence, run capture and exact replay in a checkout at baseline commit `a502e5fa2`, then candidate replay and comparison in the final candidate checkout. Keep the retained bundle unchanged: use a new scratch output directory `$B`, the retained capture fixture from the final checkout, and a Godot 4.7.2 executable:

```powershell
$Fixture = "C:/path/to/final-checkout/docs/research/propulsion/G2a-RK4/flight-log-2026-10-19/baseline/capture_release_p51_flightlog.gd"
$B = "C:/path/to/scratch/p51-shaft-replay"
$Godot = "C:/path/to/Godot_v4.7.2-stable_win64.exe"
if (Test-Path -LiteralPath $B) { throw "Use a new output directory" }
New-Item -ItemType Directory -Path "$B/baseline" | Out-Null
# Baseline checkout at a502e5fa2:
python tools/godot/run_checked.py --label p51-control-capture --timeout 240 --require-text P51_CAPTURE_COMPLETE -- $Godot --headless --path app --audio-driver Dummy --script $Fixture -- --out="$B/baseline/powered-p51-4s.orfl"
python tools/godot/run_checked.py --label p51-baseline-exact --timeout 240 --require-text "Flight log exact:" -- python tools/flight_log/flight_log.py replay "$B/baseline/powered-p51-4s.orfl" --out "$B/baseline/replay" --godot $Godot
# Final candidate checkout:
python tools/godot/run_checked.py --label p51-final-candidate --timeout 240 --require-text Wrote -- python tools/flight_log/flight_log.py replay "$B/baseline/powered-p51-4s.orfl" --candidate app/data/aircraft/p51d_mustang_120.json --out "$B/candidate" --godot $Godot
python tools/godot/run_checked.py --label p51-control-compare --timeout 90 --require-text Wrote -- python tools/flight_log/flight_log.py compare "$B/baseline/replay/flight.csv" "$B/candidate/flight.csv" --out "$B/comparison.json"
```

The [capture fixture](flight-log-2026-10-19/baseline/capture_release_p51_flightlog.gd) regenerates the four-second baseline on commit `a502e5fa2`; the bundle retains the exact baseline ORFL, both replay CSVs, reports, checked-run receipts and comparison.
