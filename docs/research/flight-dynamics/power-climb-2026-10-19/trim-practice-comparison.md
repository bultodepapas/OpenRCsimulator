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

From the card's inverted passes (height held through a bounded negative angle of attack, speed held with the throttle). "Elevator" is the total surface angle: the level trim at that speed plus the pilot's push.

| Aircraft | Speed | Angle of attack | Elevator, total | Throttle inverted / upright at that speed |
| --- | --- | --- | --- | --- |
| Ugly Stik | 0.6 Vmax (19.6 m/s) | −4.5° | +0.3° (1.2° below the upright trim) | 0.52 / 0.46 |
| Stik MAX-61FX | 0.6 Vmax (22.9) | −3.8° | +0.3° (1.4° below) | 0.33 / 0.27 |
| Extra 300S | 0.6 Vmax (24.6) | −2.7° | −0.9° (2.4° below) | 0.28 / 0.28 |
| P-51D 1/4 | 0.6 Vmax (34.9) | −4.1° | −0.6° (1.6° below) | 0.24 / 0.23 |
| Ventage Jet | 0.6 Vmax (43.9) | −2.0° | +0.0° (1.3° below) | 0.26 / 0.27 |
| Timber | 0.6 Vmax (18.1) | −8.0° | −10.3° (8.8° below) | 0.62 / 0.56 |

At the slow start speed the push grows: Stik 1.5°, Extra 2.9°, P-51 2.9°, Timber 11.9° of down elevator from a stick of −0.66 (two thirds of the throw), with the Timber's inverted pass at 13 m/s invalid in FT-05 (it sinks 3 m/s at its negative stall bound).

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

PRACTICE_PLACEHOLDER

## 3. Verdict

VERDICT_PLACEHOLDER
