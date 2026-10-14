# D6e-R1 climb and pilot-trim probes

The shared-code audit also uses `shared_code_probe.gd`: 400 seeded synthetic states per flyable aircraft, checking load invariance under quaternion sign, a common heading rotation of attitude/wind, and a common velocity offset of aircraft/wind. It also compares the ordinary load path with the stage-air reuse path. Half the samples carry explicit downwash state; a quarter also query ground effect. These checks exercise coordinate and state consistency, including reverse flow and large rates; they do not validate the aircraft's aerodynamic parameters.

`callback_probe.gd -- --fps=15` exercises actual SceneTree callbacks with a keyboard throttle pulse. Repeat at 30, 60 and 144 FPS and compare the reported state hashes at 240 physics ticks. This measures the production session's callback ordering and input sampling, not GPU rendering quality.

`frame_covariance_probe.gd` changes the body-coordinate basis, including inertia, force and rotor momentum, in 1,000 seeded rigid-body evaluations and checks the torque/power identity. `integration_probe.gd` compares a 0.5 s throttle transient at 120/240/480 Hz against 960 Hz for glow, electric and turbine configurations. It reports errors and rejects failed runs; it does not impose a universal convergence order on sampled auxiliary states or nonlinear electrical events.

`aero_power_probe.gd` tests mechanical power in isolated local-force and global-rate terms across the fleet (28,000 samples each). It disables the intrinsic wing pitching moment for the local-force check; this is a diagnostic of dissipative terms, not a physical-validation claim for every aerodynamic contribution.

Use the repository's pinned Godot from the root:

```powershell
& .\.tools\Godot_v4.7.2-stable_win64_console.exe --headless --path app --script "$PWD/research/flight-dynamics/climb-trim/probe.gd"
& .\.tools\Godot_v4.7.2-stable_win64_console.exe --headless --path app --script "$PWD/research/flight-dynamics/climb-trim/live_probe.gd"
& .\.tools\Godot_v4.7.2-stable_win64_console.exe --headless --path app --script res://tests/test_pilot_trim.gd
& .\.tools\Godot_v4.7.2-stable_win64_console.exe --path app --script "$PWD/research/flight-dynamics/climb-trim/native_probe.gd"
& .\.tools\Godot_v4.7.2-stable_win64_console.exe --headless --path app --script "$PWD/research/flight-dynamics/climb-trim/test_watch.gd"
```

`probe.gd` runs every catalog aircraft for ten simulated seconds at the solved power, 25%, 50%, and 25% with gentle weather. It samples neutral keyboard commands before each real simulation tick and prints JSON summaries. Actual tick duration and early crashes are reported, not hidden.

`live_probe.gd` instantiates the complete flight scene, retains real keyboard sampling and engine-driven physics callbacks, sets 25% power, and records ten seconds each for Timber and Stik under gentle weather. Keep the controls untouched and disconnect controllers for the neutral-input comparison. It prints the Recorder CSV paths; a pause ends the observation. These are generated diagnostic recordings, not recordings of the reported user flight.

The regression checks fleet equilibrium, manual trim sign, physical servo response, limits, reset, replay isolation, low-power descent, and a faster-cruise counterfactual. [Findings and limits](../../../docs/research/flight-dynamics/climb-trim/README.md).

`native_probe.gd` launches through Home using Enter, retains native rendering, copies the player's weather/settings into a separate diagnostic preferences file, and measures Timber at starting power and 25%, Timber on the runway at 25%, and Stik airborne at 25%. Results and screenshots go to `.tools/climb-native-*`. Power is applied after Home transitions into flight; summaries report absolute simulation time, while the altitude delta starts at recorder attachment. Do not operate the controls during this automated probe.

To capture an actual user reproduction without pressing T:

```powershell
& .\.tools\Godot_v4.7.2-stable_win64_console.exe --path app --script "$PWD/research/flight-dynamics/climb-trim/watch.gd"
```

`watch.gd` opens the normal Home and settings. Fly normally. Its independent recorder saves five-simulated-second CSV segments under `.tools/climb-observed/<UTC timestamp>-<pid>/`, plus raw keyboard/radio inputs, sampled pitch and elevator trim. Reset and aircraft changes start new segments; normal T recordings remain available. Graceful exit saves the final segment. `test_watch.gd` verifies exact checkpoint equality with an unobserved flight, segmentation, reset and detach. These diagnostic scripts stay outside the production app.

Pausing also closes the current segment. Independent `telemetry-*.jsonl` files retain full-precision state, loads, commands, auxiliary/continuous state, raw input and trim on every sampled tick, flushing every simulated second. These diagnostic samples survive a rejected replay CSV; they are not validated replays. The observer test checks pause saving and telemetry round-trip accuracy as well as unchanged simulation checkpoints.

## Captured Ugly Stik loops

`ugly-loop-inputs.json` retains raw-command change points and observed state checkpoints from the owner's 49.092-second flight on 2026-10-13. Commands remain held until the next sample. The original telemetry segment hashes identify the capture. `loop_probe.gd` replays those inputs through the real session and fails if the baseline state checkpoints differ by more than 1e-8 or the replay ends early. This is a diagnostic reproduction of a reported behavior, not an acceptance test requiring future models to loop.

```powershell
& .\.tools\Godot_v4.7.2-stable_win64_console.exe --headless --path app --script "$PWD/research/flight-dynamics/climb-trim/loop_probe.gd" -- --replay-only
& .\.tools\Godot_v4.7.2-stable_win64_console.exe --headless --path app --script "$PWD/research/flight-dynamics/climb-trim/loop_probe.gd"
& .\.tools\Godot_v4.7.2-stable_win64_console.exe --headless --path app --script "$PWD/research/flight-dynamics/climb-trim/loop_probe.gd" -- --isolate-trim
& .\.tools\Godot_v4.7.2-stable_win64_console.exe --headless --path app --script "$PWD/research/flight-dynamics/climb-trim/loop_probe.gd" -- --prop-sensitivity
python research/flight-dynamics/climb-trim/analyze_loop.py .tools/climb-observed/2026-10-13T19-28-33-88100 docs/research/flight-dynamics/climb-trim
```

The default comparison includes calm air, alternative starting trims and constant-power controls. `--isolate-trim` keeps the original starting state and moves only the elevator trim at five seconds, or removes rotor gyroscopic coupling. Add `--compare-physics` to `--replay-only` when evaluating an intentional solver change: it reports the historical checkpoint error and loop metrics instead of requiring the new physics to reproduce the old trajectory. The default remains strict. Counterfactuals that stop at ground contact are reported with their actual duration. An absence of loops before an early crash is not proof of satisfactory handling. The analyzer requires Python with matplotlib and reads the full captured CSV files; replay only needs pinned Godot and the compact fixture.

`--prop-sensitivity` runs the first fifteen seconds, switching only the Ct/Cp curves at five seconds, either preserving the prescribed maximum RPM or changing it to the estimated static torque-balance RPM. The comparison curves and their source/provenance are in the evidence directory. Both use one RPM slice throughout each run, retain the legacy RPM-lag law, and extrapolate beyond the slice using the legacy law. First inversion and first out-of-domain times are reported separately: do not describe either case as an installed, validated O.S./APC powertrain. Component-load diagnostics include the sampled downwash lag but omit ground effect/contact loads; they describe the airborne first-loop interval, not the last low-altitude ticks of a counterfactual.

`energy_probe.gd` independently integrates load work over the first fifteen seconds and compares it with body mechanical-energy change. It includes the sampled downwash lag; calm 240/480 Hz cases preserve the input-event times. Its airborne load audit omits ground contact/effect and is scoped to this interval. Energy closure tests numerical consistency, not aircraft parameter accuracy.

`pitch_causality_probe.gd` repeats the first fifteen seconds with absolute throttle caps of 1.0, 0.85, 0.75 and 0.5, preserving the recorded raw pitch and fixed launch elevator. It reconstructs the attached-model pitch moment from zero-angle, angle-of-attack, elevator, aileron, pitch-rate, force-arm, downwash and propulsion terms. The uncapped case must match the original state checkpoints. Caps are experimental interventions, not proposed flight assists. Its `PITCH_CAUSALITY` JSON output is retained in the evidence directory as `pitch-causality.json` with scope and source hashes.

`fixed_trim_power_equilibrium.gd` searches the standard Stik's projected longitudinal steady-flight conditions with the launch surfaces fixed: zero pitch moment and non-gravitational XZ force magnitude equal to weight. It recovers climb angle from force direction, enumerates the sampled attached pitch roots, and scans speed/power. It holds body rates and sideslip at zero with settled downwash; lateral equilibrium and real-aircraft calibration are outside this diagnostic. A missing equilibrium does not prove that a loop is inevitable.

`donor_reference_probe.gd` repeats the same interval with an approximate donor AERORP-to-CG transfer of only `Cm0`, `Cma` and `Cmde` in memory, recomputing the normal startup trim first. It keeps production data untouched, requires complete runs and historical baseline parity, and records omitted transport terms explicitly. Its `DONOR_REFERENCE_SENSITIVITY` output is preserved as `donor-reference-sensitivity.json`.

```powershell
& .\.tools\Godot_v4.7.2-stable_win64_console.exe --headless --path app --script "$PWD/research/flight-dynamics/climb-trim/pitch_causality_probe.gd"
& .\.tools\Godot_v4.7.2-stable_win64_console.exe --headless --path app --script "$PWD/research/flight-dynamics/climb-trim/fixed_trim_power_equilibrium.gd"
& .\.tools\Godot_v4.7.2-stable_win64_console.exe --headless --path app --script "$PWD/research/flight-dynamics/climb-trim/donor_reference_probe.gd"
```

```powershell
& .\.tools\Godot_v4.7.2-stable_win64_console.exe --headless --path app --script "$PWD/research/flight-dynamics/climb-trim/energy_probe.gd"
& .\.tools\Godot_v4.7.2-stable_win64_console.exe --headless --path app --script "$PWD/research/flight-dynamics/climb-trim/energy_probe.gd" -- --calm
& .\.tools\Godot_v4.7.2-stable_win64_console.exe --headless --path app --script "$PWD/research/flight-dynamics/climb-trim/energy_probe.gd" -- --calm --480
```

## Controlled intervention probes

`model_consistency_intervention_probe.gd` runs nine standard-Stik cases: baseline, an elevator lift derivative inferred from the modeled tail arm, and paired global elevator derivatives taken from the existing local force model. It re-solves startup trim at 15 m/s, preserves identical **absolute** throttle history for comparisons, and adds independent 30-second trim-hold controls. These are diagnostic counterfactuals, not aircraft calibrations. No production data are written; output defaults to the corresponding evidence JSON.

```powershell
& .\.tools\Godot_v4.7.2-stable_win64_console.exe --headless --path app --script "$PWD/research/flight-dynamics/climb-trim/model_consistency_intervention_probe.gd"
```

The probe checks historical baseline parity, complete runs, fixed elevator, absence of faults/contact, and source hash stability. Its first-inversion metric detects body-down reversal and must not be called a complete pitch loop. `--output=<path>` selects another evidence destination.

`coefficient_contract_probe.gd` independently computes the scalar attached force/moment equations and local-tail elevator derivative for all seven catalog aircraft. Its 126 runtime comparisons cover signed elevator, alpha and nonzero pitch rate, including ARP-to-CG transport. It exits nonzero on a 1e-9 force/moment comparison failure or a source hash change. Results go to `coefficient-contract-experiments.json` in the evidence directory.

```powershell
& .\.tools\Godot_v4.7.2-stable_win64_console.exe --headless --path app --script "$PWD/research/flight-dynamics/climb-trim/coefficient_contract_probe.gd"
```

`longitudinal_intervention_probe.gd` compares the standard flight with an explicit longitudinal constraint at all RK4 stages, at 240/480 Hz and with a neutral trim-hold control. It evaluates production loads but imposes `pdot=rdot=0`, `qdot=My/Jyy` and zero lateral motion. It measures unwrapped pitch/path turns; these metrics are valid for the projected plane only. The input history ends at 15 s, followed by absolute full throttle. Its assertions reproduce the current diagnostic behavior, not a requirement that future corrected physics must loop.

`powertrain_intervention_probe.gd` substitutes the existing 55AX and FS64V propulsion branches into the standard airframe in memory, preserving the baseline body state, surfaces and absolute throttle history. After 15 s it holds the last command (50.2083%) for 30 s. It reports the FS64V hybrid's failed native trim and explicit baseline-seeded exploratory initialization; this fallback is never a qualified launch or production repair. Dry engine/propeller mass differences are excluded, while fuel mass changes remain in the coupled solver.

```powershell
& .\.tools\Godot_v4.7.2-stable_win64_console.exe --headless --path app --script "$PWD/research/flight-dynamics/climb-trim/longitudinal_intervention_probe.gd"
& .\.tools\Godot_v4.7.2-stable_win64_console.exe --headless --path app --script "$PWD/research/flight-dynamics/climb-trim/powertrain_intervention_probe.gd"
```

Both write their correspondingly named evidence JSON files. They are research-only interventions with different post-15-second power protocols; do not compare their later trajectories as if all inputs were equal. Run pinned Godot headlessly from the repository root. The evidence report records decisions and validation limits for the entire campaign.

## Root-cause review tools

`independent_longitudinal.py` reimplements the Stik's attached longitudinal equations without simulator code: the fixed-elevator equilibrium map for the current and APC 12x6 propeller tables, then calm throttle steps with each table and with a 6 % static margin. `vlm_neutral_point.py` computes the stick-fixed neutral point from the Stik's own wing and stabilizer planform with a vortex lattice; it omits fuselage, propeller and slipstream. `root_cause_variant_probe.gd` runs the real session for the baseline, the APC table, a geometric 6 % margin (moving only the coefficient reference point) and both together, with calm 40 s steps and the owner's recorded inputs. It writes `root-cause-variants.json`.

```powershell
python research/flight-dynamics/climb-trim/independent_longitudinal.py
python research/flight-dynamics/climb-trim/vlm_neutral_point.py
& .\.tools\Godot_v4.7.2-stable_win64_console.exe --headless --path app --script "$PWD/research/flight-dynamics/climb-trim/root_cause_variant_probe.gd"
```

The Python checks need numpy and scipy. All three are counterfactuals for diagnosis, not calibrated aircraft data. They describe the data before the correction below; after it, the probe's `baseline` variant (ARP forced to the plan CG) no longer reproduces the historical aircraft, so keep `root-cause-variants.json` as the pre-correction record.

The implemented correction is reproduced by two derivations that write nothing. `derive_pitch_reference.py` prints the Stik's estimated neutral point, the ARP x that places the borrowed derivatives' neutral point there, and the loader's fin-arm `Cnb`/`Cndr` for it. `derive_tail_incidence.gd` solves the local horizontal-tail incidence that removes the static step between regimes at the 15 m/s trim. `research/aero/d11g/derive_rate_derivatives.gd` now prints ARP-referred `Cmq`, `CLq` and `Cnr`. Iterate D11g and the incidence solve until neither changes, then regenerate the glow variants and Workshop descriptors.

```powershell
python research/flight-dynamics/climb-trim/derive_pitch_reference.py
& .\.tools\Godot_v4.7.2-stable_win64_console.exe --headless --path app --script "$PWD/research/aero/d11g/derive_rate_derivatives.gd"
& .\.tools\Godot_v4.7.2-stable_win64_console.exe --headless --path app --script "$PWD/research/flight-dynamics/climb-trim/derive_tail_incidence.gd"
python research/glow-engines/build_installations.py
python research/aircraft-editor/build_descriptors.py
& .\.tools\Godot_v4.7.2-stable_win64_console.exe --headless --path app --script "$PWD/research/flight-dynamics/climb-trim/root_cause_variant_probe.gd" -- --production
```

The last command measures the shipped data with the same protocol and writes `root-cause-correction.json`.

## Explicit half-throttle start

Home's standard Stik start selector cycles through the legacy airborne, runway and optional airborne-at-50%-throttle choices. The latter solves its speed and all trims; it is not an automatic in-flight assist or a measured cruise prescription. It does **not** eliminate inversion under all power histories.

```powershell
& .\.tools\Godot_v4.7.2-stable_win64_console.exe --headless --path app --script res://tests/test_cruise_trim.gd
& .\.tools\Godot_v4.7.2-stable_win64_console.exe --headless --path app --script res://tests/test_half_power_start.gd
& .\.tools\Godot_v4.7.2-stable_win64_console.exe --headless --path app --script "$PWD/research/flight-dynamics/climb-trim/loop_probe.gd" -- --half-power-start
& .\.tools\Godot_v4.7.2-stable_win64_console.exe --path app --script "$PWD/research/flight-dynamics/climb-trim/watch.gd" -- --half-power-start
```

The observer command opens normal Home with this explicit choice selected; press Fly to begin. Input and flight recording then work as before. The comparison probe repeats the captured raw keyboard events from the different initial state, plus fixed half/quarter/full-throttle controls; early ground contacts and persistent inversions are reported explicitly.
