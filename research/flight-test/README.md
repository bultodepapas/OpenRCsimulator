# Standard flight-test battery (FT)

2026-10-16 · **Status: research tool, card `ft-card-v2`.** Flies one standard test card through the real session loop for every fixed-wing catalog aircraft. It writes a profile per aircraft and compares two runs case by case. [Baseline profiles and findings](../../docs/research/flight-test/FT-01/README.md)

The card measures what a test pilot would measure on a real model:

- speeds: stall with and without power, maximum level speed, the throttle needed for each speed;
- vertical performance: climb and glide;
- control responses: roll, pitch and yaw;
- maneuvers: loop, turns, knife-edge, inverted flight, spins;
- stability: the linear modes and a hands-off flight;
- the takeoff and the landing.

Each test starts from the session's own trimmed airborne start or its qualified runway start. A closed-loop pilot (`pilot.gd`) flies it through the same loop as the game: servos, aerodynamics, propulsion, slipstream, gear, field surfaces and crash checks.

The results are what the model predicts. They are not physical validation, and the battery has no pass/fail bands for the airplane. It reports whether its pilot did what the card asks, and how the airplane responded. Real-model data, pilot reports or [flight logs](../../docs/FLIGHT-LOGGING.md) judge realism.

## Standard workflow

From the repository root, with the [pinned Godot](../../docs/TOOLS.md#developer-setup). `run.py` finds `.tools/` or `GODOT`.

```bash
python research/flight-test/run.py --out tmp/ft-baseline                       # every fixed-wing aircraft
python research/flight-test/run.py --out tmp/ft-candidate --aircraft p51d-mustang-120 --app tmp/candidate/app
python research/flight-test/compare.py tmp/ft-baseline tmp/ft-candidate --out tmp/ft-compare.md
```

1. **Baseline.** Run the battery on the unchanged tree. `--aircraft all` (the default) asks the catalog for every aircraft a flight session accepts; the helicopter is left out. Four parallel jobs take about 9 minutes on the owner's desktop, and each glow Stik about 6.
2. **Candidate.** Make one explicit change in a disposable copy of `app/` (or the working tree) and run it with `--app`.
3. **Compare.** The comparator lists, per aircraft:
   - every test whose validity changed;
   - every value that moved by more than max(`--abs`, `--rel` × |baseline|), 0.01 and 1 % by default;
   - added or removed cases, and whether the aircraft data changed.

   `--fail-on-change` makes it exit 1. Every listed change needs an explanation; none is a verdict.

`run.py` writes these files:

- `<out>/<aircraft>/profile.json`: every metric, table and note.
- `profile.md`: the readable report.
- `run.log` and one CSV trace per flight, in the `openrc-trace` columns with session metadata, at 20 Hz (`--full-traces` writes every tick).
- `<out>/run.json`: card version, git commit and dirty paths, Godot version, `--app`, and each aircraft's data-file SHA-256, exit status and valid count.
- `<out>/summary.md`: the comparison table across aircraft.

It exits 1 when a run fails or Godot reports a script error. A test that is not valid is a result, not a run failure. Runs are deterministic: two runs of the full battery compare with no change.

You can also run one aircraft directly: `<godot> --headless --path app --audio-driver Dummy --script "$PWD/research/flight-test/flight_test.gd" -- --aircraft=<id> --out=<dir> [--only=a,b]`, or list the aircraft with `-- --list`.

**Card versions.** A change to a test, its cases or its pilot changes what is measured, so it bumps `VERSION` in `flight_test.gd` and needs a new baseline. `compare.py` refuses to compare different card versions unless given `--allow-card-change`.

## Reference speeds

Tests are placed with speeds taken from each aircraft, never fixed numbers:

- `V_start` is the catalog start speed.
- `Vs` is the measured power-off stall speed. Until it is measured, or when it cannot be measured, `sqrt(2W/(ρ S CL_max))` stands in.
- `Vmax` is the measured full-throttle level speed; the trim sweep's limit stands in until it is measured.
- `a1` and `n1` are the solved positive and negative stall-start angles of attack.

The card runs in the order below, so later tests use the measured values. Table rows carry a stable `case` ID (for example `start_right` or `1.3Vs`) so they compare across versions of the same aircraft.

## The card

| Test | Start and pilot | Reports (cases) |
| --- | --- | --- |
| `trim_sweep` | Level trims on a fixed grid of start-speed multiples (`x0.50` … `x4.00`), from just above the stall estimate to more than full throttle; no flight | throttle, elevator, α, rpm per case; slowest trim; cruise throttle |
| `stall_power_off` | 1.4 Vs, idle; height held with the elevator, wings level, ball centred | stall speed and α; break kind (drop/sink, or elevator limit for a wing that only mushes); wing drop; height and time to recover (unload, level, full power) |
| `vmax` | Start speed, full throttle; height, wings and ball held until the speed changes < 0.15 m/s over 3 s | maximum level speed, rpm, times to +5/+10 m/s and to 90 %, initial acceleration, end and run height error |
| `modes` | Linearized modes of the real equations; no flight (`1.3Vs`, `start`, `0.8Vmax`) | short period and phugoid frequency/period and damping, dutch roll, roll time constant, spiral time to double or half |
| `stall_power_on` | 1.4 Vs, 50 % throttle; nose raised 2°/s from trim | as the power-off stall |
| `throttle_response` | Start speed, height held; trim → full at 1 s, full → idle at 7 s | rpm 10–90 % spool-up and spool-down, speed gained |
| `hands_off` | Start speed at 400 m; 0.2 up elevator for 0.5 s at 1 s and 0.2 right aileron for 0.5 s at 2 s, then no input for 30 s | height, speed, bank and heading change at 10 and 30 s; flown phugoid period; time to reach the 60 m floor |
| `climb` / `glide` | Full throttle or idle, speed held with the elevator for 25 s (`1.3Vs`, `1.6Vs`, `2.0Vs`) | vertical speed, path and pitch angle, glide ratio; when thrust exceeds the climb need near vertical, says so |
| `roll_rate` | Full aileron each way, other controls at trim (`1.3Vs`, `start`, `0.8Vmax` × `right`/`left`) | peak rate, time to 360°, height change, adverse sideslip |
| `pitch_pull` | Full up elevator for 1 s (`start`, `0.8Vmax`) | peak load factor, α and pitch rate; whether it stalls |
| `loop` | 0.8 Vmax, full throttle; α held 2° below the stall start, roll rate stopped, feet off | time, height, minimum speed, load factor, sideslip, heading change |
| `turn_60` | Start speed, full throttle; 60° bank, height and ball held (`right`, `left`) | sustained speed, turn rate from the ground track, radius, load factor |
| `rudder_step` | Full rudder, other controls at trim (`right`, `left`) | yaw rate, sideslip, induced roll, pitch change |
| `knife_edge` | 0.8 Vmax; 90° bank (PI), height with top rudder, heading with elevator (`right`/`left` × `100pct`/`50pct`) | rudder, aileron and elevator needed; vertical speed; sideslip; sustained or not |
| `knife_edge_full_rudder` | As above with full top rudder held | vertical speed and couplings at the rudder stop |
| `inverted` | Inverted pass at 0.6 Vmax: roll over, then height through an α bounded by the negative stall start, speed with the throttle | elevator, α, throttle |
| `spin` | 1.2 Vs at 400 m, idle; full up and full rudder for 6 s, then opposite rudder and half forward stick until yaw stops (`right`, `left`) | spin or spiral, time and height per turn, recovery turns and time |
| `takeoff` | Qualified runway start (glow engines started); throttle over 2 s, rudder heading hold, PI rotation at 1.25 Vs to min(8°, a1 − 3°); also 3 s rudder-free | lift-off speed and Vs ratio, ground roll, rudder used, heading error, rudder-free swing |
| `landing` | Qualified runway aircraft; gear down; 4° final from 30 m at 1.3 Vs aimed 10 m past the threshold; elevator flies the path and throttle the speed; flare at one second of approach sink above the wheels | touchdown speed, sink, pitch and distance past the threshold; bounce; rollout distance and time without brakes |

## Pilot rules

The rules in `pilot.gd` come from the failures met while building the card ([FT-01](../../docs/research/flight-test/FT-01/README.md)).

- **Scheduled gains.** Gains are stick per radian at `V_start`, scaled by `(V_start/V)²` and bounded to 0.25–4.
- **Integrators in stick units.** They reach the full ±1, so a hold never stops short of a stop the airplane could still use.
- **Coordination centres the ball.** A slow integral moves the sideslip target until the lateral specific force is zero. A pilot judges coordination by the ball, and under power β = 0 is not coordinated.
- **Bounded α near limits.** Inverted flight and the loop hold α inside the stall limits. The approach is coupled: elevator for the path, throttle for the speed, which suits engines with spool lag. The flare is a PI on sink from the approach attitude.
- **Honest validity.** A test is valid only when its pilot did what the card asks: target reached, hold converged, no crash.
  - A trim that fails at the requested speed starts at the next faster trimmable speed, and the report says so.
  - Airborne tests stop at 60 m.
  - Saturation is read from the pilot's own commands, because the recorded command columns include trims.
  - Some results are the airplane's own limit, not a pilot failure: thrust above weight, a mushing wing, a spiral instead of a spin, no trim at a slow speed, the floor reached in a spiral dive. The report states them as such.

## Limits

- Calm, standard air only (the runner refuses turbulence). Flaps up. Retractable gear up in the air and down for the landing.
- Results depend on the pilot. Recovery heights, maneuver times, loop size and landing distances describe this pilot's technique, not the best the airplane can do.
- `modes` uses the 4×4 block projections of `physics/flight_modes.gd`; an unusual root structure is reported, not forced.
