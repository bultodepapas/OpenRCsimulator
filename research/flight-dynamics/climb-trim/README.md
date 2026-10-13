# D6e-R1 climb and pilot-trim probes

Use the repository's pinned Godot from the root:

```powershell
& .\.tools\Godot_v4.7.2-stable_win64_console.exe --headless --path app --script "$PWD/research/flight-dynamics/climb-trim/probe.gd"
& .\.tools\Godot_v4.7.2-stable_win64_console.exe --headless --path app --script "$PWD/research/flight-dynamics/climb-trim/live_probe.gd"
& .\.tools\Godot_v4.7.2-stable_win64_console.exe --headless --path app --script res://tests/test_pilot_trim.gd
```

`probe.gd` runs every catalog aircraft for ten simulated seconds at the solved power, 25%, 50%, and 25% with gentle weather. It samples neutral keyboard commands before each real simulation tick and prints JSON summaries. Actual tick duration and early crashes are reported, not hidden.

`live_probe.gd` instantiates the complete flight scene, retains real keyboard sampling and engine-driven physics callbacks, sets 25% power, and records ten seconds each for Timber and Stik under gentle weather. Keep the controls untouched and disconnect controllers for the neutral-input comparison. It prints the Recorder CSV paths; a pause ends the observation. These are generated diagnostic recordings, not recordings of the reported user flight.

The regression checks fleet equilibrium, manual trim sign, physical servo response, limits, reset, replay isolation, low-power descent, and a faster-cruise counterfactual. [Findings and limits](../../../docs/research/flight-dynamics/climb-trim/README.md).
