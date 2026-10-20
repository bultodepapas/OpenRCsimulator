# Is it correct? Trim practice, throttle for level flight, inverted flight and hands-off flight: simulator against RC and full-scale practice

2026-10-20 · D6e-R3 follow-up to the owner's question. The simulator's numbers below come from the [FT-05 card](../../flight-test/FT-05/README.md) (trim sweeps, inverted passes, linear modes, hands-off flights) and two read-only probes; the practice and measurement side is in [trim-practice-research.md](trim-practice-research.md) with its sources. Model predictions against other airframes and published practice; no acceptance band is claimed.

## 1. Simulator numbers

### Elevator trim and throttle for level flight against speed

Elevator in degrees trailing-edge up (the trim a pilot would hold), throttle as a fraction of the stick, from the FT-05 trim sweep (calm ISA air, 400 m). Vs is the measured power-off stall speed.

| Aircraft (throw) | 1.3 Vs | 1.6 Vs | 2.0 Vs | 2.5 Vs | 3.0 Vs | Trim slope 1.6→2.5 Vs |
| --- | --- | --- | --- | --- | --- | --- |
| Ugly Stik (20°) | +4.1°, 21 % | +2.5°, 31 % | +1.5°, 46 % | +1.0°, 64 % | +0.6°, 86 % | −0.18°/(m/s) |
| Stik MAX-61FX (20°) | +5.5°, 7 % | +3.5°, 12 % | +2.1°, 20 % | +1.3°, 33 % | +0.9°, 48 % | −0.24 |
| Stik MAX-55AX (20°) | +6.3°, 7 % | +3.8°, 12 % | +2.3°, 20 % | +1.4°, 33 % | +1.0°, 49 % | −0.27 |
| Stik FS-64V (20°) | +4.8°, 11 % | +2.9°, 19 % | +1.7°, 32 % | +1.1°, 50 % | +0.8°, 85 % | −0.22 |
| Extra 300S (24°) | +5.1°, 10 % | +3.3°, 14 % | +2.0°, 22 % | +1.1°, 35 % | +0.7°, 47 % | −0.22 |
| P-51D 1/4 (15°) | +3.2°, 7 % | +2.0°, 10 % | +1.2°, 17 % | +0.7°, 31 % | +0.4°, 55 % | −0.09 |
| Ventage Jet (30°) | +4.1°, 7 % | +2.7°, 10 % | +1.8°, 18 % | +1.1°, 33 % | +0.8°, 52 % | −0.09 |
| Timber (18°) | +6.7°, 36 % | +1.8°, 43 % | −1.1°, 53 % | −3.0°, 69 % | −3.8°, 83 % | −0.60 |

Every airplane is speed-stable (more up elevator the slower it flies). The electric Timber and the legacy-law Stik fly level at half throttle near 2 Vs; the glow, gasoline and turbine laws put half throttle near 3 Vs because they carry a larger thrust surplus at the slow end. The Timber's steep trim curve is its 23–26 % static margin (STOL tail) with a cambered wing.

### Power-pitch coupling at constant speed

Elevator change between the engine-stopped glide and level flight at the same speed, from the six-axis trim solver (positive = more up elevator with power):

| Aircraft | 1.6 Vs | 2.0 Vs | 2.5 Vs | What produces it |
| --- | --- | --- | --- | --- |
| Ugly Stik | −0.02° | 0.00° | +0.02° | thrust line through the CG, no slipstream model |
| Stik glow (3) | +0.02 to +0.03° | +0.06 to +0.07° | +0.14° | hub-inflow propeller only |
| Extra 300S | +0.29° | +0.31° | +0.34° | thrust line 23 mm above the CG, 0.5° downthrust |
| P-51D 1/4 | +0.37° | +0.37° | +0.42° | thrust line 71 mm above the CG, slipstream on the tail, propeller normal force |
| Ventage Jet | −0.07° | −0.03° | +0.01° | nozzle 10 mm below the CG |
| Timber | +0.15° | +0.18° | +0.21° | 2° downthrust |

### Inverted flight

From the card's inverted passes (height held through a bounded negative angle of attack, speed held with the throttle). The card's `elevator_stick` is the recorded command column, which already includes the trim, so it is the total elevator angle; the push is that angle minus the upright trim at the same speed.

| Aircraft | Speed | Angle of attack | Elevator inverted (total) | Upright trim at that speed | Push | Throttle inverted / upright |
| --- | --- | --- | --- | --- | --- | --- |
| Ugly Stik | 0.6 Vmax (19.6 m/s) | −4.5° | 1.2° down | 1.5° up | 2.8° | 0.52 / 0.46 |
| Stik MAX-61FX | 0.6 Vmax (22.9) | −3.8° | 1.4° down | 1.7° up | 3.1° | 0.33 / 0.27 |
| Extra 300S | 0.6 Vmax (24.6) | −2.7° | 2.4° down | 1.5° up | 3.9° | 0.28 / 0.28 |
| P-51D 1/4 | 0.6 Vmax (34.9) | −4.1° | 1.6° down | 0.9° up | 2.5° | 0.24 / 0.23 |
| Ventage Jet | 0.6 Vmax (43.9) | −2.0° | 1.3° down | 1.3° up | 2.6° | 0.26 / 0.27 |
| Timber | 0.6 Vmax (18.1) | −8.0° | 8.8° down | 1.5° down | 7.3° | 0.62 / 0.56 |

At the slow start speed the push grows (Stik 1.5° down total, Extra 2.9°, P-51 2.9°, Timber 11.9° down from a stick of −0.66, two thirds of the throw; the Timber's inverted pass at 13 m/s is invalid in FT-05, it sinks 3 m/s at its negative stall bound). Linear theory puts the push at 2·CL·dδe/dCL; with each airplane's own trim slope that is 2.7–3.3° for the Stik, 3.0–3.4° Extra, 1.9–2.1° P-51, 1.5–1.7° Jet and 9–12° Timber, which the flown passes reproduce within the nonlinearity of the negative-α lift.

### Hands-off flight and the longitudinal modes

| Aircraft | Phugoid at the start speed (period, ζ) | at 0.8 Vmax | Short period at the start (Hz, ζ) | Hands-off 30 s after 0.2 pulses: height, heading |
| --- | --- | --- | --- | --- |
| Ugly Stik | 9.9 s, 0.25 | 17.6 s, 0.84 | 1.33, 0.94 | −0.3 m, 69° |
| Stik MAX-61FX | 12.4 s, 0.63 | overdamped | 1.79, 0.88 | −5.5 m, 111° |
| Extra 300S | 11.0 s, 0.48 | 14.3 s, 0.93 | 2.27, 0.84 | −103 m, 417° (spiral) |
| P-51D 1/4 | 10.8 s, 0.19 | 15.5 s, 0.61 | 0.80, 0.93 | −9 m, 109° |
| Ventage Jet | 16.0 s, 0.09 | 33.2 s, 0.42 | 1.05, 0.72 | −62 m, 330° (spiral) |
| Timber | 6.7 s, 0.13 | 11.8 s, 0.49 | 1.75, 0.63 | −52 m, 851° (spiral) |

The classical phugoid estimate is a period of 0.45·V s (Lanchester) and a damping ratio of 1/(√2·L/D) (0.06–0.10 for these glide ratios); the simulator's periods are 1.2–1.5 times Lanchester's and its damping is higher because the propeller laws' thrust falls with speed, which damps the speed exchange. The phugoid is what a pilot sees as "porpoising" after any disturbance; the spiral is what takes the Extra, Jet and Timber away hands-off.

## 2. Practice and measurements

The full note with sources is [trim-practice-research.md](trim-practice-research.md) ([sources](trim-practice-sources.md)); its measured items come from the UMN Ultra Stick 120 "Baldr" and 25e "Thor" logs on disk, a flying-wing identification paper, Dorobantu's thesis, kit and model manuals, the FAA handbook and the Cessna 172S manual. The quality labels are the note's.

**How a model is trimmed.** Every RC source gives a trim throttle, never a trim speed: E-flite trims its electric trainers at half throttle ("if your aircraft does not fly straight and level at half throttle with the sticks at neutral, adjust the trim") and its scale, STOL and EDF models, the Timber among them, at three quarters; the glow PT-40 is "designed to fly level with neutral elevator trim at approximately 1/4 to 1/3 throttle"; the trimming charts (Goldsmith, Scale R/C Modeler) then check thrust line and CG at full throttle and by the inverted push. Once trimmed the expectation is full throttle climbs, half holds height, low throttle descends gently (Apprentice manuals), a 20–30° full-throttle climb for the glow trainer. Power-pitch is tuned with 0.5–6° of downthrust (high-wing trainers at the top) and, on pattern and big sport models, a 2–15 % throttle-to-elevator mix. Full scale: attitude, then power, then trim (FAA handbook); a C172S cruises at 50–77 % power and the POH never states a throttle position. Measured electric cruise sticks: Ultra Stick 120 0.55–0.69, 25e 0.78–0.92 (system-identification sorties at 70 %); autopilot defaults 40–45 %.

**At what speed that is.** Measured and published cruise points cluster at 1.6–2.4 × stall speed (Ultra Sticks 1.6–2.1, Dorobantu's "cruise" 1.8–2.3, C150/C152 1.8, C172S 2.3–2.4). The simulator's 50 % start lands the electric Timber and the legacy-law Stik at 2.0–2.1 Vs, inside that band, and the glow Stiks, Extra, P-51 and jet at 2.9–3.1 Vs, above it; at a quarter to a third of the stick the glow Stik flies 2.2–2.5 Vs, the PT-40's practice.

**The trim curve, measured.** From the UMN logs (quasi-steady level segments, regression on lift coefficient): Ultra Stick 120 at its nominal CG 6.0° up elevator at 19 m/s falling to 2.3° at 31 m/s, 9.8 ± 0.6° per unit CL (6.2 with the CG 3 % further aft); 25e 6.7°/CL. Slopes −0.43°/(m/s) at 19–25 m/s flattening to −0.1 to −0.2 above. The implied static margins are 8.6 % (120 nominal), 5.4 % (aft) and 11 % (25e), agreeing within 2–5 % with the published identified models. Dorobantu's identified short period for the 25e is 2.6 Hz at ζ 0.83; his phugoid was not identified (the 10 s sweeps cannot excite it) and was held at the model's 0.38.

**Inverted.** Practice ranges from "a touch of down" on symmetrical aerobats through about an eighth of the stick on sport models to "almost full stick" on flat-bottom trainers; Pitts pilots hold 5–8 lbf forward. No measured RC inverted elevator exists; the linear estimate from the measured trim slopes gives 2.5–7° for the Ultra Sticks.

**Hands-off.** With the elevator fixed the Ultra Stick 120 swings 6 m/s and 14° of pitch with a 13.6 s period (Lanchester 10.7 s) and a damping of about 0.1 over the one cycle recorded; the 25e 8.0 s (Lanchester 8.2 s); the KHawk Zephyr flying wing, identified in the frequency domain, ζ 0.10–0.13 at cruise. Real periods run 1.0–1.6 × Lanchester's. Only 40 s of hands-off data exist in twelve UMN flights: pilots do not leave the elevator alone. Commercial simulators start on the runway or from a saved state with author-set fixed trims and no auto-trim.

## 3. Verdict

1. **Trimming at a throttle is the practice, and the 50 % start follows it.** The manuals trim at a stick position (½ electric trainers, ¾ electric scale and STOL, ¼–⅓ glow trainers) and expect idle to descend and full throttle to climb; the pilot then holds that trim. The simulator's slow start (9–37 % of the stick) was below every documented trim point; the 50 % start sits where the electric trainers are trimmed and where the measured Ultra Sticks fly level. A per-type trim throttle (¾ for the Timber as its own manual says, ¼–⅓ for the glow Stik) would be a refinement the data supports, if the owner wants Home to use the manufacturer's figure; the mechanism exists (`cruise_trim` takes any throttle).
2. **The climb at full throttle and the descent at idle are correct in kind and size.** The Apprentice and PT-40 manuals describe exactly the hands-off behaviour the card measures from the 50 % trim: level at half, 20–30° climb at full on a trainer (the Timber climbs 61 m in 40 s at 70 %), a gentle descent below half. The measured Ultra Stick 120 shows the same: elevator unchanged with power, climb rate set by the throttle.
3. **The trim curves are realistic.** The simulator's elevator-per-lift-coefficient values (Stik 6.3°/CL, Extra 7.6–8.7, Timber 14–19, others 4.5–6.3) bracket the measured Ultra Sticks (6.2–9.8°/CL) and imply the same kind of static margins; the speeds at which half the trim change happens match the logs. Nothing here says the pitch stiffness is wrong.
4. **Inverted flight is consistent.** The flown pushes equal the linear estimate from each airplane's own trim slope, the semi-symmetrical Stik needs a sport model's "touch of down" (2.8°), the Extra a little more at its slower inverted speed, and the cambered Timber two thirds of the stick, as a flat-bottom trainer does; the throttle inverted is 0–13 % higher than upright, the drag of the negative angle of attack. No measured RC inverted elevator exists to tighten this.
5. **Two things the measurements do not support, both outside the trim question.** The simulator's phugoid damping at matched speed ratio is two to four times the measured electric cases (Stik 0.25 at 1.6 Vs and 0.84 at 2.7 Vs against about 0.1 at 2 Vs; the glow Stiks are overdamped at their 50 % start), which makes a disturbed airplane settle faster than a real one; the likely cause is the thrust-speed slope of the propulsion laws (the legacy fixed-rpm law has no unloading, the glow law is choked at small openings), a propulsion-track item (G2) that changes how long the porpoising lasts, not the trim or the steady climb. And the hands-off spiral of the Extra, jet and Timber (330–851° in 30 s) is the dihedral effect that D10-R5 gave the Stik family and not yet the rest of the fleet.
6. **What remains an estimate.** The glow installations' part-throttle power (NITRO-06) is calibrated to one dynamometer figure; where half throttle falls on the glow Stiks (2.9–3.1 Vs against the PT-40's ¼–⅓ practice at 2.2–2.5 Vs) is the only place where the simulator's throttle scale may be high, and a measured rpm-against-stick curve for an O.S. barrel carburettor would settle it.

Practical reading for the owner: from the 50 % start every airplane behaves as the manuals describe; the one habit the simulator does not do for you is the pilot's own trimming after a speed change, which real pilots do with the trim lever and which Page Up/Down provides at 0.1° per press (between EdgeTX's fine and medium trim steps).
