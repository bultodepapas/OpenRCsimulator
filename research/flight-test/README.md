# Standard flight-test battery (FT)

2026-10-16 · **Status: research tool, card `ft-card-v4`** (v3, 2026-10-18: adds `aero_sweep`; v4, 2026-10-19: FT-04 adds aerobatic, inverted, power-off, stall and runway tests). Flies one standard test card through the real session loop for every fixed-wing catalog aircraft. It writes a profile per aircraft and compares two runs case by case. Baseline profiles and findings: [FT-01](../../docs/research/flight-test/FT-01/README.md) (card v2), [FT-03](../../docs/research/flight-test/FT-03/README.md) (card v3 on the D10-R2 tree, with measured-RC comparisons) and [FT-04](../../docs/research/flight-test/FT-04/README.md) (card v4).

The card measures what a test pilot would measure on a real model:

- speeds: stall with and without power, maximum level speed, the throttle needed for each speed;
- vertical performance: climb and glide;
- control responses: roll, pitch and yaw;
- maneuvers: loop, turns, knife-edge, inverted flight at three speeds and in a turn, spins upright and inverted;
- aerobatic figures as the FAI F3 execution guide defines them: Immelmann, Split-S, outside loop, slow and four-point rolls, snap rolls, stall turns;
- engine failure: in the climb, the turn back and the dead-stick landing;
- stalls: wings level with and without power, in a turn, skidded, held with the stick back, and inverted;
- stability: the linear modes and a hands-off flight;
- the aerodynamic model itself: which model (coefficient oracle or local surfaces) carries the loads, and what each gives, without flying;
- the takeoff, the landing and the go-around.

Each test starts from the session's own trimmed airborne start or its qualified runway start. A closed-loop pilot (`pilot.gd`) flies it through the same loop as the game: servos, aerodynamics, propulsion, slipstream, gear, field surfaces and crash checks.

The results are what the model predicts. They are not physical validation, and the battery has no pass/fail bands for the airplane. It reports whether its pilot did what the card asks, and how the airplane responded. Real-model data, pilot reports or [flight logs](../../docs/FLIGHT-LOGGING.md) judge realism.

## Standard workflow

From the repository root, with the [pinned Godot](../../docs/TOOLS.md#developer-setup). `run.py` finds `.tools/` or `GODOT`.

```bash
python research/flight-test/run.py --out tmp/ft-baseline                       # every fixed-wing aircraft
python research/flight-test/run.py --out tmp/ft-candidate --aircraft p51d-mustang-120 --app tmp/candidate/app
python research/flight-test/compare.py tmp/ft-baseline tmp/ft-candidate --out tmp/ft-compare.md
```

1. **Baseline.** Run the battery on the unchanged tree. `--aircraft all` (the default) asks the catalog for every aircraft a flight session accepts; the helicopter is left out. Card v3 took about 10 minutes with four parallel jobs on the owner's desktop (each glow Stik 6–7). Card v4 takes 3–5 times as long: 51 minutes with four jobs on the shared dev VM, each glow Stik 33–38. `--only` runs a subset; tests that place themselves by Vs and Vmax should then include `trim_sweep,stall_power_off,vmax`.
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
- with `--diagnostics`, one `<test>.aero.csv` per flight at the same 20 Hz: α, β, airspeed, the production local-flow and sideslip weights, and body-axis CX…Cn from the coefficient oracle, the local model and the blended production loads. They are recomputed read-only from the session's own state, servo deflections, density, wind, downwash lag and ground height; `lerp_residual` checks that the blend equals oracle + w·(local − oracle) (exact without flaps). Profiles are identical with and without it.
- `<out>/run.json`: card version, git commit and dirty paths, Godot version, `--app`, and each aircraft's data-file SHA-256, exit status and valid count.
- `<out>/summary.md`: the comparison table across aircraft.

`python research/flight-test/spin_state.py <out> [aircraft ...]` reads the spin traces offline. It prints each aircraft's state averaged over the card's steady window (4.0–6.25 s): α, |β|, airspeed, body rates, Ωb/2V, pitch angle, pitch-rate swing and sink. Beside each aircraft it prints two spins measured in flight with the same entry: NASA FASER (Ultra Stick 120) and the UIUC Aero Testbed (35 % Extra 260). Their speeds are scaled to that aircraft's wing loading. These rows compare other airframes; they are not acceptance bands ([sources](../../docs/research/flight-dynamics/rc-aero-data-sources.md), [current findings](../../docs/research/flight-test/FT-03/README.md#against-measured-rc-class-data)).

`python research/flight-test/polar_fit.py <out> [aircraft ...]` works the same way for lift and drag (card v3 or later). It fits each airframe polar from `aero_sweep`: CL at α 0, CLα, and CD = CDmin + K(CL − CL_md)² with e. It then compares the idle glides with that polar, so the excess shows the idle propeller and trim drag. It also prints the NASA FASER and Southampton FliTePlat wind-tunnel references.

It exits 1 when a run fails or Godot reports a script error. A test that is not valid is a result, not a run failure. Runs are deterministic: two runs of the full battery compare with no change.

You can also run one aircraft directly: `<godot> --headless --path app --audio-driver Dummy --script "$PWD/research/flight-test/flight_test.gd" -- --aircraft=<id> --out=<dir> [--only=a,b]`, or list the aircraft with `-- --list`.

**Card versions.** A change to a test, its cases or its pilot changes what is measured, so it bumps `VERSION` in `flight_test.gd` and needs a new baseline. `compare.py` refuses to compare different card versions unless given `--allow-card-change`. Add `--shared-tests` to compare only the tests both profiles contain: a card that appends tests then shows its earlier tests unchanged (`--rel 0 --abs 0 --fail-on-change`). New tests go after the existing ones for this reason.

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
| `aero_sweep` | No flight; start speed, every control neutral (in flight a deflected rudder lowers the fin's angle and the weight; use `--diagnostics` for the flown regime). Sideslip sweep at the level-trim α and α sweep at zero sideslip through the pure loads functions | per case CY/Cn/Cl (sideslip) or CL/CD/Cm (α) from the oracle, the local model and the blended production loads, and the production local-flow weight; the sideslip and α where the local model takes all loads; CY at 20° against the oracle; the knife-edge side-force margin (best \|CY\| up to 30° over W/qS at 0.8 Vmax) |
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

### Card v4 additions (FT-04)

These tests run after the v3 tests, which run exactly as before. They live in four files: `card_aerobatics.gd` (aerobatic and inverted), `card_power.gd` (engine failure), `card_stalls.gd` (stall and spin variants) and `card_field.gd` (runway). Figure geometry and the qualities reported follow the FAI F3 aerobatic manoeuvre execution guide (Sporting Code Volume F3, Annex 5B, 2026 edition; [source manifest](../../docs/research/flight-test/FT-04/sources.json)). The battery reports what a judge would look at, never a score.

| Test | Start and pilot | Reports (cases) |
| --- | --- | --- |
| `inverted_speeds` | The `inverted` pass at three speeds (`start`, `0.6Vmax`, `0.8Vmax`) | elevator, α and throttle against speed |
| `inverted_turn` | Inverted-pass speed; roll 135° (45° from inverted), height through the bounded α, speed with the throttle, ball centred (`right`, `left`) | sustained speed, turn rate, radius, load factor, elevator, α |
| `immelmann` | 0.8 Vmax, full throttle; half loop at α 2° below the stall start, then a full-aileron half roll with the line held | height gained; speed over the top in m/s and in Vs; exit speed; heading error from the reversal; load factor |
| `split_s` | Start speed, idle; a full-aileron half roll with the line held, then a half loop down at α 2° below the stall start | height lost, exit and peak speed, load factor, heading error |
| `outside_loop` | 0.6 Vmax at 300 m; pushed loop at α 2° inside the negative stall start; idle on the way down, full throttle on the way up | depth, time, least speed, least load factor, sideslip, heading change |
| `slow_roll` | 0.8 Vmax, full throttle; one roll at 90°/s, the line held at every bank with elevator and rudder, knife-edge and inverted feedforward (`right`, `left`) | roll time, height and heading change, roll-rate constancy, peak rudder and push, aileron saturation |
| `point_roll` | As `slow_roll`, with 90° part rolls at 180°/s and a 1 s point after each (`right`, `left`) | over-rotation at each point; elevator and rudder at each point; height and heading change |
| `snap_roll` | 1.6 Vs, level-trim throttle; full up elevator, rudder and aileron the same way. Released 0.2 s of roll rate before 360°, when the autorotation dies, or after 4 s; then sticks centred, opposite rudder, level and pull out (`right`, `left`) | snap or aileron roll (α before 45° of roll); yaw-to-roll ratio; how far short of 360° the autorotation ended (FAI zeroes > 90°); where the rotation stopped; height lost |
| `stall_turn` | 0.8 Vmax, full throttle; vertical up-line, then idle; full rudder with a half-throttle blip at 0.35 Vs and, early, at 0.6 Vs; then down-line and pull-out (`right`/`left` × `0.35Vs`/`0.6Vs`) | outcome (pivot, wing-over, flop, tail slide or no pivot); pivot radius in wingspans; torque-off and pitch during the pivot; height lost |
| `engine_cut_climb` | Full-throttle climb at 1.6 Vs from 250 m; engine cut at 6 s; the climb attitude held for a 1 s or 2 s reaction, then a glide at 1.4 Vs (`delay_1s`, `delay_2s`) | least speed in m/s and in Vs, α margin, stall, height gained and lost, windmill rpm, how the engine was cut |
| `glide_turn` | Engine cut at the start; speed 1.3 Vs × √n; 4 s straight, then a full circle (`30deg`, `45deg`, `60deg`) | height per 180° and 360°, sink straight and in the turn, radius; the bank that loses least |
| `stall_turning` | 1.4 Vs × √n, idle; 30° or 45° of bank held, height with the elevator until the break (`30_right`, `30_left`, `45_right`, `45_left`) | stall speed against Vs × √n, α, roll-off inside or outside and how far in 1 s, height and time to recover |
| `stall_cross_controlled` | 20° of bank held with the ailerons against half bottom rudder, height with the elevator, idle (`right`, `left`) | as `stall_turning`: whether it rolls under |
| `stall_held` | From 400 m, the power-off stall, then full up elevator for 5 s with ailerons and rudder neutral, or used for wings level and the ball (`controls_neutral`, `wings_level`) | mush, wing drop or spin entry; bank, rotation rate and heading change while held; height lost |
| `stall_inverted` | 1.6 Vs; roll inverted, idle; height held through a push that may pass the negative stall start | inverted stall speed against the upright Vs, α, roll-off, height and time to recover |
| `spin_inverted` | 1.6 Vs at 400 m, inverted, idle; full down elevator and full rudder for 6 s; then opposite rudder, neutral elevator, roll upright, pull out (`right`, `left` rudder) | spin or spiral, time and height per turn, least α, recovery turns and time |
| `dead_stick_landing` | Qualified runway aircraft. An engine-off glide at 1.4 Vs measures the glide path; then a final from 30 m on that path, aimed 10 m past the threshold, with the engine cut, the elevator flying the path and the landing flare | glide ratio and path, touchdown against the aim, speed, sink, bounce, rollout |
| `go_around` | The `landing` approach; at 3 m the throttle goes to full in 0.3 s or 2 s; wings level, runway heading with the rudder, 1.3 Vs with the elevator (`fast`, `slow`) | least wheel height and whether it touched, bank and heading excursions, peak aileron and rudder, time to 15 m |

## Pilot rules

The rules in `pilot.gd` come from the failures met while building the card ([FT-01](../../docs/research/flight-test/FT-01/README.md)).

- **Scheduled gains.** Gains are stick per radian at `V_start`, scaled by `(V_start/V)²` and bounded to 0.25–4.
- **Integrators in stick units.** They reach the full ±1, so a hold never stops short of a stop the airplane could still use.
- **Coordination centres the ball.** A slow integral moves the sideslip target until the lateral specific force is zero. A pilot judges coordination by the ball, and under power β = 0 is not coordinated.
- **Bounded α near limits.** Inverted flight and the loop hold α inside the stall limits. The approach is coupled: elevator for the path, throttle for the speed, which suits engines with spool lag. The flare is a PI on sink from the approach attitude.
- **Attitude-free laws (v4).** `point_nose` turns the nose toward an earth direction through whichever of elevator and rudder points that way at the current bank. One law holds a line upright, in knife-edge, inverted and on a vertical line. `roll_rate` holds a body roll rate.
- **Feedforward from earlier tests (v4).** A competent pilot puts the control in before the airplane needs it. The slow and four-point rolls use this run's knife-edge results (top rudder, aileron, nose elevation) and its inverted 0.8 Vmax result (push, α). The line PI corrects the rest. A missing result leaves that term at zero, and the report says so.
- **Figures end in a recovery (v4).** Every figure phase has a time limit that leads into the recovery. The report classifies the outcome (the stall turn's pivot, wing-over, flop or tail slide; the snap's release reason) instead of ending the flight at the failure.
- **α-limited pull-outs (v4).** After a snap, a stall or a dive the pilot levels the wings and pulls out at half the stall-start α before holding height; a full height-hold pull stalls again.
- **Engine failure is the session's own cut (v4).** A glow engine is cut with `glow_cut()` and other sources are disabled, as SF-04 does; the propulsion model decides whether the propeller windmills or stops. A running continuous turbine has no hot cutoff yet (AV-05b), so it stays at idle and the report says so.
- **Honest validity.** A test is valid only when its pilot did what the card asks: target reached, hold converged, no crash.
  - A trim that fails at the requested speed starts at the next faster trimmable speed, and the report says so.
  - Airborne tests stop at 60 m.
  - Saturation is read from the pilot's own commands, because the recorded command columns include trims.
  - Some results are the airplane's own limit, not a pilot failure: thrust above weight, a mushing wing, a spiral instead of a spin, no trim at a slow speed, the floor reached in a spiral dive. The report states them as such.

## Limits

- Calm, standard air only (the runner refuses turbulence). Flaps up. Retractable gear up in the air and down for the landing, the dead-stick landing and the go-around.
- No crosswind, flapped landing or 3D figures (hover, harrier, torque roll) yet.
- Results depend on the pilot. Recovery heights, maneuver times, loop size and landing distances describe this pilot's technique, not the best the airplane can do.
- `modes` uses the 4×4 block projections of `physics/flight_modes.gd`; an unusual root structure is reported, not forced.
