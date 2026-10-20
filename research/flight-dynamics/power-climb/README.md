# D6e-R3/R4 power-step tools

Read-only probes behind the [power-step climb investigation](../../../docs/research/flight-dynamics/power-climb-2026-10-19/README.md). Run the pinned Godot from the repository root ([TOOLS](../../../docs/TOOLS.md)). Nothing here writes to `app/`.

```sh
GODOT="$(app/get-godot.sh)"
# Steady engine speed, thrust and shaft power of every fixed-wing catalog propulsion law on a throttle × airspeed grid,
# beside the level-flight drag of the data's parabolic polar and the constant-speed climb angle the excess predicts.
"$GODOT" --headless --path app --audio-driver Dummy --script "$PWD/research/flight-dynamics/power-climb/part_throttle_probe.gd" -- --out=/tmp/part-throttle.csv [--aircraft=<id,id>]
# Geometric neutral point of each catalog airframe against the one its pitch coefficients imply.
python3 research/flight-dynamics/power-climb/fleet_neutral_point.py
```

```sh
# The owner's procedure in the complete flight scene (main.tscn, keyboard sampling, Home's gentle-breeze weather):
# airborne start, then a throttle held hands-off, and a keyboard-style runway takeoff; --start=airborne_half_power uses
# the 50 % level trim; --trim=cruise is Home's launch trim (D6e-R4: every start, runway included, trimmed for 50 %).
"$GODOT" --headless --path app --audio-driver Dummy --script "$PWD/research/flight-dynamics/power-climb/scene_probe.gd" -- [--aircraft=<id,id>] [--start=airborne|airborne_half_power] [--trim=reference|cruise] [--throttles=0.5,0.3] [--no-runway] [--no-airborne] [--level-off=40] [--rotate=0.35] [--seconds=40]
# Run the runway cases in their own process (--no-airborne): a runway launch refused after a crashed airborne case in the
# same process is reported and skipped. --level-off raises the hands-off release height, --rotate the ground-roll elevator.
```

The flown measurement is the flight-test card's `power_step` test (card v5): `python3 research/flight-test/run.py --out <dir> --only power_step` ([card](../../flight-test/README.md#the-card)). Model predictions, not physical validation.

`trim-practice/` holds the scripts that read the UMN Ultra Stick MATLAB logs (local-only under ignored `references/`) for the level-flight trim curve, the implied static margin, the inverted-push estimate and the fixed-elevator phugoid; run them with `python3 -I`. Their findings: [trim-practice-research.md](../../../docs/research/flight-dynamics/power-climb-2026-10-19/trim-practice-research.md).
