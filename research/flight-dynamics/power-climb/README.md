# D6e-R3 power-step tools

Read-only probes behind the [power-step climb investigation](../../../docs/research/flight-dynamics/power-climb-2026-10-19/README.md). Run the pinned Godot from the repository root ([TOOLS](../../../docs/TOOLS.md)). Nothing here writes to `app/`.

```sh
GODOT="$(app/get-godot.sh)"
# Steady engine speed, thrust and shaft power of every fixed-wing catalog propulsion law on a throttle × airspeed grid,
# beside the level-flight drag of the data's parabolic polar and the constant-speed climb angle the excess predicts.
"$GODOT" --headless --path app --audio-driver Dummy --script "$PWD/research/flight-dynamics/power-climb/part_throttle_probe.gd" -- --out=/tmp/part-throttle.csv [--aircraft=<id,id>]
# Geometric neutral point of each catalog airframe against the one its pitch coefficients imply.
python3 research/flight-dynamics/power-climb/fleet_neutral_point.py
```

The flown measurement is the flight-test card's `power_step` test (card v5): `python3 research/flight-test/run.py --out <dir> --only power_step` ([card](../../flight-test/README.md#the-card)). Model predictions, not physical validation.
