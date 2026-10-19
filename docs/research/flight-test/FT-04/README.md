# FT-04: card v4, aerobatic, inverted, engine-failure, stall and runway tests

2026-10-19 · **Status: card `ft-card-v4` implemented and flown on all eight fixed-wing catalog aircraft. The 21 v3 tests are unchanged at zero tolerance, and the card is deterministic. FT-04 replaced FT-03 as the baseline; [FT-05](../FT-05/README.md) (card v5, 2026-10-19) replaces FT-04 after the NITRO-06 glow throttle law. Two independent checks hold: the turn back, and the stall in a turn. No aircraft can fly a stall turn; snap rolls, held stalls and dead-stick glides expose open physics work.** [Tool, card and workflow](../../../../research/flight-test/README.md#card-v4-additions-ft-04); previous baseline [FT-03](../FT-03/README.md) (card v3).

## What changed

Card v4 appends 18 tests after the unchanged v3 tests, in four files that take the runner:

| File | Tests |
| --- | --- |
| `card_aerobatics.gd` | `inverted_speeds`, `inverted_turn`, `immelmann`, `split_s`, `outside_loop`, `slow_roll`, `point_roll`, `snap_roll`, `stall_turn` |
| `card_power.gd` | `engine_cut_climb`, `glide_turn` |
| `card_stalls.gd` | `stall_turning`, `stall_cross_controlled`, `stall_held`, `stall_inverted`, `spin_inverted` |
| `card_field.gd` | `dead_stick_landing`, `go_around` |

Figure geometry and the qualities reported follow the FAI F3 execution guide (Sporting Code Volume F3, 2026, Annex 5B; [sources](sources.json)). Examples:
- the stall turn's pivot radius in wingspans (two spans is a wing-over);
- the snap roll's stall before the rotation, and autorotation to the finish (90° short scores zero);
- the point roll's over-rotation.

The battery reports these quantities, never a score.

Changes to the runner and its tools:
- **Pilot laws.** `point_nose` and `roll_rate` fly lines at any bank and vertical lines. The landing's approach and flare became shared functions with the same arithmetic.
- **Runner helpers.** `_inverted_pass` is the `inverted` law with a speed and a bank. `_cut_engine` is the session's own source cut.
- **Tools.** `compare.py --shared-tests` compares only the tests both profiles contain; `summarize.py` has one row per new test.

## Baseline

| Item | Value |
| --- | --- |
| Tree | A frozen copy of `app/` at `97136354`; the card files are identical to `76d1c15e` ([provenance](verification/provenance.md)) |
| Engine and conditions | Godot 4.7.2 official, Linux headless, 240 Hz; calm standard air |
| Aircraft | Every fixed-wing catalog aircraft (eight) |
| Runtime | 51 min with 4 jobs on the shared dev VM; 9–18 min per aircraft, 33–38 min per glow Stik (about 3–5× the card v3 times on the same VM) |
| Valid tests | Stik, Extra, P-51 and Ventage Jet 39/39; Timber 38/39; glow Stiks 35–36/39 |

Each aircraft folder holds `profile.md`, `profile.json` and `run.log`. [summary.md](summary.md) is the fleet table. These are model predictions, not physical validation.

The invalid tests are the airplanes' own answers:
- **Glow Stiks:** they cannot slow down at idle (FT-03 finding 4). Wings-level stalls and, for the 61FX and FS-64V, the turning and skidded stalls never break within 60 s. The 55AX keeps its v3 half-throttle knife-edge failure.
- **Timber:** it cannot hold height inverted at its start speed. Its α is bounded by the negative stall start, and it still sinks 3.2 m/s.

## Verification

- **The v3 tests did not move.** v3 and v4 were flown on the same snapshot and compared with `--shared-tests` at zero tolerance. The 21 shared tests of all eight aircraft (5,673 values) show 0 changes ([report](verification/v3-tests-unchanged.md)).
- **Deterministic.** A second v4 run of the Stik and the Ventage Jet matches the fleet run in all 39 tests at zero tolerance ([report](verification/determinism.md)). An earlier repeat of the Stik also matched; that card differed only in comments.
- **What moved since FT-03 is not FT-04.** On this snapshot the v3 tests differ from FT-03 only in the glow Stiks' takeoff and landing ground values (18 values, at most 3 % apart from heading errors of tenths of a degree), from the ground and wheel data committed in `272e2e51` and `97136354` ([report](verification/ft03-to-snapshot-v3.md)).
- **Each pilot does what the card asks.** Every figure phase has a time limit that leads into a recovery, and the outcome is classified. While the card was being built, every invalid result was traced to the pilot or to the airplane. Pilot faults were repaired before the final run: a release that waited for 360° while the Stik's autorotation reversed; a height-hold pull-out that re-stalled the P-51; a bang-bang stop rudder that sustained a Dutch roll on the Ventage Jet; stall flights too short for glow idle.

## Independent checks

- **Turn back after an engine failure.** At constant CL (speed 1.3 Vs × √n), the height lost per radian of heading is proportional to 1/sin 2φ, which is least at φ = 45°. Rogers (1995) shows the same optimum, reproduced by [Reed and Williams 2008](sources.json). The card finds 45° best in seven of eight aircraft; the Timber is best at 30°, losing 7.3 m against 8.0 m at 45°.

  | Height lost per 180° (m) | Stik | 55AX | 61FX | FS-64V | Extra | P-51 | Ventage | Timber |
  | --- | --- | --- | --- | --- | --- | --- | --- | --- |
  | 30° | 10.4 | 12.4 | 13.9 | 16.9 | 13.0 | 25.1 | 42.8 | 7.3 |
  | 45° | 10.0 | 11.4 | 12.3 | 15.0 | 11.4 | 22.0 | 38.1 | 8.0 |
  | 60° | 14.5 | 15.3 | 16.5 | 19.5 | 14.8 | 26.6 | 45.0 | 14.4 |

- **Accelerated stall.** In 30° and 45° level turns the break comes at 1.008–1.060 × Vs √n across the six aircraft that stall, as steady-turn theory predicts.

## Findings for the owning tracks

1. **No aircraft can fly a stall turn (slipstream and propulsion, E0b).** Kicked at 0.35 Vs or 0.6 Vs with a half-throttle blip, all 32 cases end in a tail slide, a wing-over or no pivot in 6 s.
   - The Stik reaches about 5°/s of yaw with full rudder.
   - The tail slipstream that would give rudder authority near zero airspeed is opt-in, and only the P-51 has it.
   - The P-51 reaches about 40°/s, but its nose falls toward the belly at 90°/s (propeller gyroscopic moment), and it rolls up to 186° during the pivot.
   - Torque-off reaches 60–354° across the fleet.

   A real Ugly Stik stall-turns easily with propwash. The next 3D figures (hover, torque roll) need the same physics.
2. **Snap rolls and held stalls (post-stall, D10-R4/D8b-R2d).** Every aircraft except the Timber stalls before 45° of roll and autorotates with a yaw-to-roll ratio of 0.21–0.51.
   - **Stik family, right snaps:** the autorotation dies 97–124° short of 360° (FAI zero), while left snaps reach the finish. With the pro-snap inputs held on (a development run), the Stik reverses into a left roll.
   - **Extra:** short both ways (86° and 111°).
   - **Ventage Jet:** stops after about 75° of roll.
   - **P-51:** runs on to 429–433°.
   - **Timber:** never stalls and rolls on its ailerons.

   With the stick held back 5 s after a stall, the Stik, Extra and P-51 enter a spin at 184–398°/s. The Ventage Jet and Timber drop a wing or mush. Inverted stalls roll off 107–145° in the first second, except the P-51, which only mushes at its elevator limit, at 1.72 Vs.
3. **Dead-stick glide (propulsion G1d, glow engines).**
   - **Glow Stiks:** with the engine cut, the propeller windmills at about 3,900–4,500 rpm, and the glide ratio is 4.3–7.4 (FS-64V 4.3).
   - **Electric aircraft and the P-51's gasoline engine:** with the source disabled, the propeller stops (0 rpm) and adds no drag (FT-03 finding 2), giving 9.9–13.7.

   The truth probably lies between, with a locked or free-wheeling propeller adding a measurable ΔCD (FT-03 finding 2).
4. **A running turbine cannot be cut (AV-05b).** `engine_cut_climb`, `glide_turn` and `dead_stick_landing` fly the Ventage Jet at idle (44,000 rpm), as each row's `engine_out` says.
5. **Engine failure in the climb.** At 1.6 Vs and full throttle the climb is steep (43–77°). With a 2 s reaction, seven of eight aircraft stall, the Stik at 0.30 Vs. With 1 s, only the Stik stalls (0.52 Vs). The numbers depend on the 1.6 Vs climb and the reaction time: they describe this scenario, not a limit of the airplane.
6. **Go-around.** The Ventage Jet's turbine spool-up lets it sink to the runway: 0.05 m with the throttle slammed, and a touch with it eased in over 2 s. The P-51 sinks to 0.03 m with a slow throttle. Propeller aircraft yaw and roll less than 3° in the go-around, which suggests weak torque and P-factor effects; this needs pilot reports.
7. **Skidded stall.** With half bottom rudder the P-51 overbanks before its wing stalls (right): it breaks at 1.36 Vs at 155° of bank, and to the left it rolls 76° into the turn. The Stik, 55AX, Extra and Ventage Jet roll 35–56° into the turn within a second. The Timber mushes and rolls 15–20°, to the outside in the right case.

## Limits

- Model predictions, not physical validation. The FAI guide defines the figures, not acceptance bands.
- Results depend on the pilot. Heights, sizes and pivot outcomes describe this pilot's technique, with the [rules](../../../../research/flight-test/README.md#pilot-rules) documented.
- Calm air, flaps up. Crosswind, flapped landings and 3D figures (hover, harrier, torque roll) are not in the card yet; the 3D figures wait for low-airspeed control authority (finding 1).
