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

```powershell
& .\.tools\Godot_v4.7.2-stable_win64_console.exe --headless --path app --script "$PWD/research/flight-dynamics/climb-trim/energy_probe.gd"
& .\.tools\Godot_v4.7.2-stable_win64_console.exe --headless --path app --script "$PWD/research/flight-dynamics/climb-trim/energy_probe.gd" -- --calm
& .\.tools\Godot_v4.7.2-stable_win64_console.exe --headless --path app --script "$PWD/research/flight-dynamics/climb-trim/energy_probe.gd" -- --calm --480
```

## Explicit half-throttle start

Home's standard Stik start selector cycles through the legacy airborne, runway and optional airborne-at-50%-throttle choices. The latter solves its speed and all trims; it is not an automatic in-flight assist or a measured cruise prescription. It does **not** eliminate inversion under all power histories.

```powershell
& .\.tools\Godot_v4.7.2-stable_win64_console.exe --headless --path app --script res://tests/test_cruise_trim.gd
& .\.tools\Godot_v4.7.2-stable_win64_console.exe --headless --path app --script res://tests/test_half_power_start.gd
& .\.tools\Godot_v4.7.2-stable_win64_console.exe --headless --path app --script "$PWD/research/flight-dynamics/climb-trim/loop_probe.gd" -- --half-power-start
& .\.tools\Godot_v4.7.2-stable_win64_console.exe --path app --script "$PWD/research/flight-dynamics/climb-trim/watch.gd" -- --half-power-start
```

The observer command opens normal Home with this explicit choice selected; press Fly to begin. Input and flight recording then work as before. The comparison probe repeats the captured raw keyboard events from the different initial state, plus fixed half/quarter/full-throttle controls; early ground contacts and persistent inversions are reported explicitly.
