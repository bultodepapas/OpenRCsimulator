# D6e-R1 climb and pilot-trim probes

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
