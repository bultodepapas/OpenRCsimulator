# D6e-R3: the tendency to climb at part throttle, measured across the fleet

2026-10-19 · **Status: measured on all eight fixed-wing aircraft with a new hands-off throttle-step test (card v5). One shared-engine defect found and corrected: the glow throttle law admitted a constant charge per cycle, so a closed throttle pulled in flight and four aircraft flew level at 1–11 % of the stick ([NITRO-06](../../glow-engines/NITRO-06/README.md)). The remaining climb at mid-stick from the trimmed start is the physics of a fixed trim with a large thrust surplus, confirmed against an instrumented Ultra Stick; its size is set by the start operating point, which stays an owner decision.** Main physics track; follows [D6e-R1](../climb-trim/README.md). Model predictions, not physical validation.

## Question

The owner reports that every aircraft climbs persistently, even below full throttle. D6e-R1 (2026-10-13) had reproduced the Stik's loops, corrected its borrowed static margin and left the Timber's low-power report unreproduced. This step asks the same question of the whole fleet with a measurement that matches the complaint: leave the elevator at its launch trim, move only the throttle, and watch the path.

## Method

1. **`power_step`**, a new test on the [flight-test card](../../../../research/flight-test/README.md#card-v5-addition-d6e-r3) (v5): from each aircraft's own trimmed airborne start at 400 m, the throttle goes at 1 s to idle, 25, 50, 75 or 100 % and stays there 30 s. No pilot pitch input; wings held level and the ball centred so a spiral does not hide the longitudinal answer. It reports the height, speed, path angle and attitude, whether the airplane went past inverted, the level speed that throttle trims at (from `trim_sweep`) and the constant-speed climb angle the thrust excess at the trim speed predicts.
2. **`part_throttle_probe.gd`** ([tools](../../../../research/flight-dynamics/power-climb/README.md)): each propulsion law's steady rpm, thrust and shaft power on a throttle × airspeed grid, beside the level-flight drag of the data's polar.
3. **Neutral-point check** ([report](neutral-point-check.md)): the D6e-R1 geometric estimate applied to the other four airframes, to test whether a stiff pitch (the Stik's earlier cause) is fleet-wide.
4. **Literature** ([note](../../glow-engines/NITRO-06/throttle-power-research.md), [sources](../../glow-engines/NITRO-06/sources.md)): measured part-throttle engine data, in-flight idle, power-pitch coupling in instrumented RC flight, cruise operating points and static thrust-to-weight.

Tree: `12c2ac31` plus the card and this step's changes (the owner's commits `c8828140` and `890b94fc` captured most of them during the session); Godot 4.7.2 headless, 240 Hz, calm ISA air. The Extra now flies the finite MAX-61FX glow installation (committed `be97a75a`, after the FT-04 baseline), so its law is the glow law below.

## What the fleet did (before NITRO-06)

Path angle after 30 s with the elevator at its launch trim (hands-off throttle step; "loop" = past inverted, with the time); the trim throttle is the level-flight stick at the start speed.

| Aircraft (law) | Trim throttle | Idle | 25 % | 50 % | 75 % | 100 % |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Ugly Stik, legacy lag (rpm ∝ stick) | 28.3 % | −9.1° | −1.6° | +15.7° | loop 9.8 s | loop 5.9 s |
| Stik MAX-61FX (glow) | 1.5 % | −0.6° | +12.2° | +46° | loop 9.6 s | loop 8.0 s |
| Extra 300S MAX-61FX (glow) | 1.5 % | −0.5° | +8.0° | +19° | +40° | loop 10.9 s |
| Stik MAX-55AX (glow) | 10.3 % | −4.2° | +5.3° | +17° | loop 12.1 s | loop 8.6 s |
| Stik FS-64V (glow 4T) | 11.0 % | −5.0° | +6.8° | +20.5° | +42° | loop 15.4 s |
| P-51D 1/4, shaft (power ∝ stick) | 10.1 % | −5.2° | +5.9° | +17.7° | +33° | +47° |
| Ventage Jet, ECU map | 9.1 % | −6.8° | +7.4° | +29° | loop 27 s | loop 10 s |
| Timber, electric duty | 41.0 % | −3.7° | −5.3° | +4.7° | +29° | loop 4.7 s |

Seven of eight climb at 25 or 50 %. The two that descend at 25 % are the two whose level-flight throttle sits above 25 %. The sign and size follow the thrust surplus over the trim drag, not the airframe: the test's constant-speed prediction sin γ = (T(θ, V_trim) − T_trim)/W reproduces the flown end angle within a few degrees wherever the airplane settled (Stik 50 %: 15.7° flown, 14.4° predicted; Timber 75 %: 28.9° / 22.9°; P-51 50 %: 17.7° / 22.6°); the loops are the cases where thrust exceeds weight at the trim speed (static thrust-to-weight 1.5–1.9 for the Stiks, 1.6 for the Extra, 1.0 for the Timber), so no straight steady climb exists and the α-locked wing keeps curving the path, as D6e-R1 derived.

## Mechanism and what the measurements say about it

With the elevator fixed, the pitch balance holds the angle of attack, so lift follows the square of the speed and the throttle sets the climb angle, not the speed. This is the textbook stick-fixed behaviour and it is what an instrumented model does: the UMN Ultra Stick 120 logs (electric, 7.4 kg) show the elevator moving only 0.1–0.4° between idle, cruise and full power at the same airspeed, while the power changes the climb rate (level at 0.6–0.7 stick, +1.8 to +4.8 m/s above it; [note, section 3](../../glow-engines/NITRO-06/throttle-power-research.md#3-power-pitch-coupling-and-trim)). Real sport models carry a large surplus: measured static thrust of an O.S. 61FX with a 12×6 is 41.6 N (Glassock 2012), 1.4–1.7 times the Stik's weight, and level flight at 20 m/s needs about 13 % of its shaft power. The climb at mid-stick from a slow trim is therefore expected of these airplanes.

What decides how much of the stick is "above trim" is where the airborne start trims: the catalog starts trim at about 1.6 × the stall-speed estimate for every aircraft (15, 17–22, 25, 29 and 13.1 m/s), which is Carson's speed (3^¼ × the best-glide speed) for these polars, an efficient but slow point. Measured electric Ultra Sticks fly level at 0.55–0.83 of the stick; the sim's level-flight stick at the start speed was 1.5–41 %. Two separate things set that number: the propulsion law's part-throttle power (a physics question, below) and the choice of start speed (an operating-point decision the owner kept explicit in D6e-R1).

## Root causes found

### 1. The glow throttle law (shared engine, corrected: NITRO-06)

The glow installations mapped the stick to a constant charge per cycle, so the idle admitted 28 % of the cylinder at any speed; as the propeller unloaded in a glide, the idling engine made 174 W and 4.7 N at 20 m/s. That is why the glow Stiks "cannot slow down at idle" (FT-01 finding 2, FT-03 finding 4), why the 61FX and the Extra trimmed level at 1.5 % of the stick, and why a quarter stick climbed 8–12°. The corrected law models the carburettor as a flow restriction (isentropic nozzle, choked at small openings, Heywood §7.6.2) with the barrel's lens-shaped opening: at a fixed small opening the mass flow is fixed and the charge per cycle falls as 1/rpm. Derivation, parameters, anchors and results: [NITRO-06](../../glow-engines/NITRO-06/README.md).

### 2. Not the cause: pitch stiffness, the solver, the integration

- [Neutral-point check](neutral-point-check.md): the Extra's pitch stiffness matches its geometry to 0.1 mm; the Timber's 26 % margin is 23 % geometric (a large STOL tail, not a borrowed coefficient); the Avanti and the P-51 carry documented anchors (the Avanti stiffer than its blockout geometry, the P-51 softer, calibrated to the full-size glide neutral point). None repeats the Stik's D6e-R1 defect. A side finding: four generators compute `Cmq` about the CG while the runtime applies it at the aerodynamic reference point, 1–8 % less pitch damping than intended (the Stik was moved in D6e-R1).
- The trim solver and the integrator: every aircraft holds its start within 1 m for 30 s hands-off at the trim power ([FT-04](../../flight-test/FT-04/README.md) `hands_off`), and the energy prediction above reproduces the flown climb angles.

### 3. Findings for other tracks

- **Legacy lag law (Ugly Stik):** rpm proportional to the stick gives 63 % of the static rpm at half stick, where the measured O.S. 46 FX barrel band is 78–84 % ([note, section 1](../../glow-engines/NITRO-06/throttle-power-research.md#1-throttle-position-versus-rpm-and-power)). Not a climb cause (the law under-powers mid-stick), but it places the Stik's level-flight trim at 28 % of the stick where a real .61 sits lower. The glow 61FX installation is the shaft model of that engine; promoting it for the default Stik is the propulsion track's G2 decision.
- **Legacy shaft law (P-51):** admitted power proportional to the stick gives 27 % of peak at a quarter stick; Moulton's 100 cc butterfly dynamometer gives 62–66 % at the same rpm. The P-51's part-throttle power is probably low, not high. The P-51 also pitches up when the power is cut (its thrust line is 71 mm above the CG), hence the +5 m first five seconds of its idle case.
- **Propeller surrogate (glow installations):** the blade-element 12×6 reaches zero thrust near J 0.5 where the measured APC Sport reaches it at 0.75–0.77, so the idling engine windmills at 7,500 rpm at 20 m/s instead of the derived 5,000–6,200 (NITRO-02 open item).
- **Hands-off lateral behaviour:** the Extra, Timber and Avanti spiral away within 30 s of a small aileron pulse (FT-04 `hands_off`: 627°, 851°, 292° of heading); the power-step test holds the wings level for that reason. Spiral stability is its own investigation.
- **Start operating point (owner decision, D6e-R1 follow-up):** trimming the airborne start at the aircraft's cruise (for the Stik, the existing 50 % option at 20.6 m/s) would put idle below and full throttle above the trim as a pilot expects; it does not change the physics of the full-throttle pull-up on a 1.5 T/W airplane.

## The owner's procedure in the complete flight scene

`scene_probe.gd` ([tools](../../../../research/flight-dynamics/power-climb/README.md)) instantiates `main.tscn` with Home's default **Gentle breeze** weather (1.5 m/s east wind, 0.6 m/s gusts with a 0.15 m/s upward component for 4 s every 14 s, light turbulence), keyboard sampling on, and holds a throttle hands-off from the airborne start. Height after 40 s from 30 m (the Timber's keyboard start speed reads 11.4 m/s because the state speed is over the ground, into the headwind):

| Aircraft, slow start (1.6 Vs) | Trim throttle | 30 % | 50 % |
| --- | ---: | ---: | ---: |
| Timber, 13.1 m/s | 37 % | ground in 32 s | +12 m (peak +25 m, phugoid) |
| Ventage Jet, 29 m/s | 9 % | +181 m (14° mean, phugoid 18–41 m/s) | +268 m (peak pitch 40°) |
| Extra, 22 m/s | 22 % | −7 m (peak +24 m) | −2 m after a +64 m phugoid |
| Ugly Stik, 15 m/s | 28 % | +10 m | +65 m |

The jet at 30 % and the Stik at 50 % climb exactly as the hands-off card predicts; the gusts add a little lift and the phugoids are large, which is what a pilot sees as "it keeps going up". A keyboard-style takeoff (full throttle, up elevator held until airborne plus 3 s, then sticks centred and 50 %) ends in a bunt for the Timber and the Stik: at 55–75° of pitch with the wing unloaded the sudden release pitches past the trim angle into negative lift. That is a crude input, not a pilot's, and is reported as such.

## Remedy: the 50 % start for every airplane

The pilot's trim is the lever: a model is trimmed for the throttle it cruises at, and the catalog's slow start is not that trim. D6e-R1 built that start for the Stik (`cruise_trim.gd`, a bounded six-axis solve for the level speed at a requested throttle). This step offers it to every fixed-wing airplane (`half_power_start_supported` now excludes only rotorcraft; the bounded solve still refuses a launch it cannot bracket), widens the speed bound to 2.5 × the slow start, and makes the search fast enough for a launch and for the Workshop's 16 s qualification budget: a warm-started Newton (`Trim.solve` takes an optional initial point) and a bracketed Illinois false-position search replace 25–35 cold bisections with 6–10 warm solves. Solve times fell from 12–19 s to 2.6–6.0 s on the glow and electric aircraft and to 0.05–0.3 s on the others; the solutions are the same (speeds agree to 0.01 m/s).

The level trims at half throttle, with the elevator a pilot would hold at that speed:

| Aircraft | Slow start | 50 % start | Elevator at 50 % | Hands-off 10 s drift |
| --- | ---: | ---: | ---: | ---: |
| Ugly Stik | 15.0 m/s | 20.60 m/s | 1.36° up | 0.000 m |
| Stik MAX-61FX | 20.0 | 30.54 | 0.89° up | 0.56 m (fuel burn) |
| Stik MAX-55AX | 20.0 | 29.36 | 0.93° up | 0.44 m |
| Stik FS-64V | 20.0 | 22.93 | 1.15° up | 0.17 m |
| Extra 300S | 22.0 | 33.08 | 0.62° up | 0.28 m |
| P-51D 1/4 | 25.0 | 46.02 | 0.43° up | 0.12 m |
| Ventage Jet | 29.0 | 55.99 | 0.81° up | 0.71 m (fuel burn) |
| Timber | 13.1 | 16.18 | 0.55° down | 0.000 m |

`test_half_power_start.gd` (62 checks) flies every one: level at 50 % within the drift above, climbing at full throttle (31–119 m in 12 s; the P-51 first sinks because its thrust line is 71 mm above the CG) and descending at a quarter throttle (4–36 m in 8 s). In the complete scene with the gentle breeze:

| Aircraft, 50 % start | 30 % | 50 % | 70 % |
| --- | ---: | ---: | ---: |
| Timber, 16.2 m/s | ground in 13 s | −0.4 m | +61 m |
| Ventage Jet, 56.0 m/s | ground in 11 s | +17 m | +268 m |
| Extra, 33.1 m/s | ground in 11 s | +7 m | +44 m (peak +88 m) |
| Ugly Stik, 20.6 m/s | ground in 10 s | +1.6 m | +80 m |

Below half the airplane descends, above half it climbs, and the trim stays where it is. This is a start-point choice, not a physics change: the fixed-trim pull-up at full throttle on a 1.5 thrust-to-weight airplane remains, as it does on the real model. Making this start Home's default, and giving the runway start the same cruise trim so a takeoff is flown with up elevator and levels off at half throttle, are the owner's decisions; the data for both is above.

## After NITRO-06

The four glow-law aircraft, the same test, the same tree otherwise (filled from `tmp/ft-v5-power-after`; the complete card v5 baseline is [FT-05](../../flight-test/FT-05/README.md)):

| Aircraft | Trim throttle before → after | Idle | 25 % | 50 % | 75 % | 100 % |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Stik MAX-61FX | 1.5 % → 20.0 % | -0.6° → -12.0° | +12.2° → +4.2° | +46.2° → +37.4° | loop 9.6 s → loop 9.3 s | loop 8.0 s → loop 7.9 s |
| Extra 300S MAX-61FX | 1.5 % → 22.1 % | -0.5° → -9.7° | +8.0° → +1.6° | +19.1° → +18.6° | +40.1° → +42.6° | loop 10.9 s → loop 10.9 s |
| Stik MAX-55AX | 10.3 % → 22.4 % | -4.2° → -11.9° | +5.3° → +1.9° | +17.0° → +27.4° | loop 12.1 s → loop 10.7 s | loop 8.6 s → loop 8.6 s |
| Stik FS-64V (4T) | 11.0 % → 36.8 % | -5.0° → -21.5° | +6.8° → -8.5° | +20.5° → +12.6° | +42.3° → +54.8° | loop 15.4 s → loop 15.3 s |

Height change after 10 s and 30 s (m), before → after:

| Aircraft | Idle 10 s / 30 s | 25 % 10 s / 30 s | 50 % 10 s / 30 s |
| --- | --- | --- | --- |
| Stik MAX-61FX | -2.4 / -7.0 → -36.8 / -118.0 | +43.5 / +128.9 → +12.7 / +41.2 | +94.0 / +271.4 → +87.1 / +281.9 |
| Extra 300S MAX-61FX | -2.0 / -6.2 → -31.0 / -100.5 | +35.2 / +105.7 → +5.7 / +18.2 | +78.1 / +240.7 → +66.4 / +216.0 |
| Stik MAX-55AX | -13.2 / -40.6 → -37.1 / -118.2 | +22.5 / +63.7 → +5.7 / +18.8 | +68.0 / +185.5 → +71.8 / +227.8 |
| Stik FS-64V (4T) | -12.8 / -48.0 → -53.2 / -199.1 | +16.6 / +62.9 → -20.9 / -81.1 | +46.7 / +179.4 → +27.0 / +112.4 |

The idle now descends on every glow aircraft, a quarter stick holds roughly level or descends (the FS-64V at 37 % trim still sinks 7°), and the trim throttle sits where a quarter stick is below it and a half stick above it. The half- and full-stick pull-ups remain: they are the thrust surplus of these installations (static thrust-to-weight 1.5–1.9), now entered from a trim at 20–37 % of the stick instead of 1–11 %.

## Is it correct? Practice and measurements

The owner asked whether the trim, the throttle for level flight, inverted flight and hands-off flight match real RC and full-scale practice. [trim-practice-comparison.md](trim-practice-comparison.md) sets the simulator's trim curves, power-pitch coupling, inverted pushes and modes against manuals, trimming charts, the FAA handbook, the Cessna 172S manual and the UMN Ultra Stick logs ([research note](trim-practice-research.md), [sources](trim-practice-sources.md)). In short: models are trimmed at a throttle (½ electric trainers, ¾ electric scale and STOL, ¼–⅓ glow trainers) and then climb at full and descend at idle, which is what the 50 % start gives; the simulator's trim slopes (4.5–19° of elevator per unit lift coefficient) bracket the measured Ultra Sticks (6.2–9.8); the inverted pushes equal the linear estimate from those slopes; and the phugoid damping is two to four times the measured 0.1 at matched speed ratio, a propulsion thrust-speed item, not a trim one.

## Verification

### D6e-R4 release regression correction

2026-10-19: the new trim-throttle test held 35% up elevator until three seconds after liftoff. At one second after liftoff the reference Stik already reached about 73° pitch; at the next second it was inverted. Both reference and cruise cases crashed before the steady-flight measurement. That open-loop rotation is not a valid assertion that any takeoff must settle into level flight after releasing the elevator.

`test_trim_throttle.gd` now checks the two contracts separately: all eight fixed-wing runway routes retain the selected 50% flying trim while parked at idle, and neutral airborne holds compare the accepted reference/cruise equilibria at half throttle. Existing takeoff/ground tests retain responsibility for runway flight. The fixed-wing loader's rotorcraft case now explicitly asserts refusal instead of treating a failed load as a valid rotorcraft launch.

Native Windows Godot 4.7.2: 39 checks pass. Both 40-second airborne holds complete without crashes; the reference trim climbs at 1.3494 m/s over the second half, while the cruise trim drifts by less than one micrometre and ends at 20.5971 m/s. No physics law, trim solver or tolerance was changed. This does not qualify a pilot's takeoff procedure or physical flight behavior.

2026-10-19 follow-up: the Home-to-Fly custom-atmosphere fixture exposed a cached selected-trim mismatch: the session used the field density, but its selected 50% trim still had the 20.5971 m/s reference-density equilibrium. `_refit_selected_trim()` now refits when the requested throttle, density or engine charge differs from its cache, before the runway-start early return. The UI regression independently solves `CruiseTrim` from the active session density and charge and checks the selected speed, throttle and cache values. Native Windows Godot 4.7.2 `test_ui_atmosphere.gd` passes all atmosphere UI checks. This verifies Home-to-Fly startup consistency, not the atmosphere against measured weather or flight data.

- `power_step` is valid on all eight aircraft in [FT-05](../../flight-test/FT-05/README.md) (314 of 320 card tests valid); its constant-speed prediction agrees with the flown end angle in the settled cases (0.1–4° at idle and 25 %); the before/after tables come from the same card and tree except the glow law.
- NITRO-06 test counts and generator checks: [NITRO-06 § Verification](../../glow-engines/NITRO-06/README.md#verification).
- The non-glow aircraft are unchanged by this step: FT-05 records the same-tree comparison with and without the NITRO-06 files (see its verification); against FT-04 only the Timber compares at zero tolerance because other tracks changed the Stik, P-51 and Ventage Jet data in between.

## Reproduce

```sh
python3 research/flight-test/run.py --out /tmp/ft-power --only power_step            # all eight aircraft, about 4 min with 4 jobs
"$(app/get-godot.sh)" --headless --path app --audio-driver Dummy --script "$PWD/research/flight-dynamics/power-climb/part_throttle_probe.gd" -- --out=/tmp/part-throttle.csv
python3 research/flight-dynamics/power-climb/fleet_neutral_point.py
```
