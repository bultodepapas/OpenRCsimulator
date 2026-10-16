# Flight-test card (FT-01)

2026-10-16 · **Status: research tool.** Flies one generic test card through the real session loop for any fixed-wing catalog aircraft and writes a profile. [First results](../../docs/research/flight-test/FT-01/README.md)

The card measures what a test pilot would measure on a real model: stall, speeds, climb and glide, roll, pitch and yaw responses, a loop, turns, knife-edge, inverted flight, spins and the takeoff. Each test starts from the session's own trimmed airborne start or its qualified runway start. It is flown by a closed-loop pilot (`pilot.gd`) through servos, aerodynamics, propulsion, slipstream, gear, field surfaces and crash checks. The results are software evidence of what the model does. They are not physical validation, and they are not a band check: comparing them with a real airplane is a separate step.

## Run

From the repository root, with the [pinned Godot](../../docs/TOOLS.md#developer-setup):

```bash
<godot> --headless --path app --audio-driver Dummy --script "$PWD/research/flight-test/flight_test.gd" -- \
    --aircraft=p51d-mustang-120 --out="$PWD/tmp/flight-test" [--only=vmax,roll_rate] [--full-traces]
python research/flight-test/summarize.py tmp/flight-test p51d-mustang-120 gp-extra-300s-60   # comparison table
```

The output goes to `<out>/<aircraft>/`:
- `profile.json` holds every metric, table and note.
- `profile.md` is the readable report.
- There is one CSV trace per flight in the `openrc-trace` columns, with the session metadata. It is sampled at 20 Hz, or every tick with `--full-traces`.

The full card takes about 2 minutes per aircraft on the owner's desktop. Runs are deterministic: two runs give identical profiles.

## Reference speeds

Each test is placed with speeds taken from the aircraft, never fixed numbers:
- `V_start`: the catalog start speed.
- `Vs`: the measured power-off stall speed. Until it is measured, `sqrt(2W/(ρ S CL_max))` stands in.
- `Vmax`: the measured full-throttle level speed. Until it is measured, the trim sweep's limit stands in.
- `a1`: the solved stall-start angle of attack.

The card flies the tests in order, so later tests use the measured values.

## The card

| Test | Start and pilot | Reports |
| --- | --- | --- |
| `trim_sweep` | Level trims from 1.1 Vs until a trim needs more than full throttle; no flight | throttle, elevator, α and rpm per speed; slowest trim; cruise throttle |
| `stall_power_off` | 1.4 Vs, idle; height held with the elevator, wings level, ball centred | stall speed and α, break kind, wing drop and bank, height lost and time to recover (unload, level, full power) |
| `vmax` | Start speed, full throttle; height, wings and ball held until the speed changes < 0.15 m/s over 3 s | maximum level speed, rpm, times to +5/+10 m/s and to 90 %, initial acceleration |
| `stall_power_on` | 1.4 Vs, 50 % throttle; nose raised 2°/s from trim | as the power-off stall |
| `throttle_response` | Start speed, height held; trim → full at 1 s, full → idle at 7 s | rpm 10–90 % spool-up and spool-down, speed gained |
| `climb` / `glide` | 1.3, 1.6 and 2.0 Vs at full throttle or idle, speed held with the elevator for 25 s | vertical speed, path angle and glide ratio; whether thrust exceeds the climb need |
| `roll_rate` | 1.3 Vs, start speed and 0.8 Vmax; full aileron each way, other controls at trim | peak roll rate, time to 360°, height change, adverse sideslip |
| `pitch_pull` | Start speed and 0.8 Vmax; full up elevator for 1 s | peak load factor, α and pitch rate; whether it stalls |
| `loop` | 0.8 Vmax, full throttle; α held 2° below the stall start, roll rate stopped, feet off | time, height, minimum speed, load factor, sideslip, heading change |
| `turn_60` | Start speed, full throttle; 60° bank each way, height and ball held | sustained speed, turn rate (ground track), radius, load factor |
| `rudder_step` | Start speed; full rudder each way, other controls at trim | yaw rate, sideslip, induced roll, pitch change |
| `knife_edge` | 0.8 Vmax at full and 50 % throttle, each way; 90° bank (PI), height with top rudder, heading with elevator | rudder, aileron and elevator needed; vertical speed; sideslip; whether it is sustained |
| `knife_edge_full_rudder` | As above with full top rudder held | vertical speed and couplings at the rudder stop |
| `inverted` | Inverted pass at 0.6 Vmax; roll over, then height through an α bounded by the negative stall start and speed with the throttle | elevator, α and throttle needed |
| `spin` | 1.2 Vs at 400 m, idle; full up and full rudder for 6 s, then opposite rudder and stick forward until yaw stops | spin or spiral, time per turn, height per turn, recovery turns and time |
| `takeoff` | Qualified runway start only, with a glow start when needed; throttle over 2 s, rudder heading hold, PI rotation at 1.25 Vs to min(8°, a1 − 3°); also 3 s rudder-free | lift-off speed and Vs ratio, ground roll, rudder used, heading error, rudder-free swing |

## Pilot rules

The rules in `pilot.gd` follow from what went wrong while building the card.

- **Scheduled gains.** Gains are stick per radian at `V_start` and scale with `(V_start/V)²`, bounded to 0.25–4. A fixed gain over-controls at high speed: the sideslip loop diverged at 54 m/s on the P-51.
- **Integrators in stick units.** Every hold has an integrator that can reach the full ±1 stick whatever the schedule. A proportional pilot measures its own steady error ([P51-22](../../docs/research/p51-realism/P51-22/README.md)).
- **Coordination centres the ball.** A slow integral moves the sideslip target until the lateral specific force is zero, the way a pilot keeps the ball centred. Under power the P-51 has an 8–10 N side force at zero sideslip, so holding β = 0 made its left and right 60° turns differ by 17 %. Centring the ball made them equal, matching the turn-rate formula. A fast loop closed directly on the ball oscillates, because the rudder's own side force leads the sideslip.
- **Bounded α near limits.** Inverted flight and the loop hold α inside the stall limits instead of an attitude. Pushing for an attitude stalls a cambered wing inverted.
- **Honest failures.** A test is valid only when its pilot did what the card asks: target reached, hold converged, no crash. A trim that fails at the requested speed starts at the next faster trimmable speed, and the report says so. Airborne tests stop at 60 m instead of crashing. Saturation is read from the pilot's own commands, not from the trimmed servo columns. Some results are the airplane's own limit rather than a pilot failure, and the report states them as such: thrust above weight in a slow climb, a benign wing that only mushes at the elevator stop, a spiral instead of a spin.

## Limits

- Calm, standard air only (the runner refuses turbulence). Flaps up. Retractable gear up in the air and down on the runway.
- Each test result depends on its pilot. Recovery heights and maneuver times describe this pilot's technique, not a minimum the airplane can achieve.
- The metrics are what the model predicts. Use real-model data, pilot reports or flight logs to judge realism.
