# FT-01: flight-test card, first profiles

2026-10-16 · Revision 1 · **Status: tool implemented; six fixed-wing aircraft profiled. The P-51 and the Ventage Jet are the reference profiles; knife-edge exposes a shared side-force gap.** [Tool and card](../../../../research/flight-test/README.md)

Godot 4.7.2 official, native Windows, 240 Hz, calm standard air, commit `0296ac59`. Each aircraft folder has `profile.md`, `profile.json` and its `run.log`. The P-51 folder also keeps the 20 Hz CSV traces; the others regenerate with the command in the tool README. Two independent runs of the P-51 and the Extra 300 gave identical profiles, wall time aside. All results are model predictions, not physical validation.

## Comparison

From [`summarize.py`](../../../../research/flight-test/summarize.py) ([table](summary.md)). Values in parentheses come from a test whose pilot did not meet the card; – means not measured.

| Metric | P-51D Mustang 1/4 | Ugly Stik 60 (electric) | Ugly Stik 60 · MAX-61FX | Extra 300S .60 | Turbo Lumber Evolution | Ventage Jet |
| --- | --- | --- | --- | --- | --- | --- |
| Mass (kg) / start speed (m/s) | 21.50 / 25.0 | 2.89 / 15.0 | 2.89 / 20.0 | 3.42 / 17.0 | 2.19 / 13.1 | 11.71 / 29.0 |
| Power-off stall (m/s), wing drop | 15.45 left | 9.60 left | – | 10.51 left | 8.58 left | 18.02 right |
| Power-on stall, 50 % throttle (m/s) | 13.02 | 8.72 | 6.42 | 9.80 | 8.27 | 13.30 |
| Max level speed (m/s) | 58.2 | 32.7 | 38.1 | 34.6 | 30.1 | 73.1 |
| Time +10 m/s from start speed, full throttle (s) | 2.39 | 1.52 | 2.00 | 1.84 | 2.15 | 2.63 |
| Best full-throttle climb (m/s) | 17.1 | 17.2 | 20.9 | 15.2 | 10.7 | 20.2 |
| Best idle glide ratio | 11.3 | 9.3 | – | 8.0 | 13.9 | 9.8 |
| Full-aileron roll at start speed (°/s) | 137 | 201 | 208 | 272 | 300 | 363 |
| 60° level turn, full throttle (°/s) | 17.7 | 31.2 | 26.1 | 30.0 | 33.3 | 14.3 |
| Loop height (m) / time (s) | 101 / 6.5 | 43 / 4.5 | 43 / 3.9 | 47 / 4.8 | 38 / 4.6 | 118 / 6.3 |
| Knife-edge, full top rudder, full throttle: vertical speed (m/s), sideslip (°) | −20.3, 22.0 | −4.8, 17.3 | +9.1, 17.3 | −37.7, 20.7 | −24.8, 16.9 | +0.5, 15.5 |
| Inverted pass: elevator stick / α (°) | −0.085 / −4.0 | −0.028 / −4.5 | −0.021 / −3.7 | −0.116 / −3.5 | −0.494 / −8.0 | −0.026 / −1.8 |
| Spin (right): time per turn (s) / recovery turns | 1.46 / 0.34 | 1.32 / 0.16 | 1.24 / 0.29 | 1.26 / 0.26 | spiral | spiral |
| Lift-off speed (m/s, Vs) / ground roll (m) | 21.4 (1.38) / 34 | 16.2 (1.69) / 15 | 16.8 (1.77) / 16 | no runway start | 12.3 (1.43) / 10 | 25.6 (1.42) / 56 |
| Spool-up 10–90 % (s) | 4.35 | 0.55 | 2.66 | 0.55 | 0.50 | 1.24 |
| Valid tests | 17 / 17 | 17 / 17 | 15 / 17 | 16 / 17 | 17 / 17 | 17 / 17 |

Heights lost in stall recoveries, maneuver times and the loop size describe this card's pilot technique. They are not minimums the airplane can achieve.

## P-51 profile against its references

[P-51 report](p51d-mustang-120/profile.md). The references are those of the [P-51 realism research](../../p51-flight-realism.md).
- **Power-off stall:** 15.45 m/s, 0.99 of the CL_max estimate, α 16.2°. It drops the left wing, like the XP-51's stall break in NACA MR L-566. Power-on at half throttle it stalls at 13.0 m/s.
- **Takeoff:** lift-off at 21.4 m/s (1.38 Vs) after a 34 m roll in 3.9 s, against the 20–50 m RC class estimate. Rudder-free, it swings 41° left in 3 s.
- **Maximum level speed:** 58.2 m/s gear up at 7588 rpm. The gear-down envelope test gives 51.4 m/s, against a Top Flite Giant owner's ~51 m/s.
- **Climb and glide:** it climbs at 14.4–17.1 m/s (34–46° path) at full throttle. Gear up at idle, its best glide ratio is 11.3 at 1.3 Vs. A level trim needs 9.9 % throttle at 25 m/s.
- **Roll:** full aileron gives 134–138°/s at 20–25 m/s and 186–189°/s at 47 m/s. It loses 43–61 m in a full roll at low speed with the elevator at trim.
- **Turns:** a 60° full-throttle turn is symmetric with the ball centred: 17.7°/s, 184 m radius, 2.05 g at 56.6 m/s.
- **Spins:** they develop at 1.46 s per turn (right) and 1.66 s (left), losing 40–48 m per turn, and recover in about a third of a turn.
- **Knife-edge:** not sustainable. See the next section.

## Finding 1: knife-edge has no side force beyond 15° of sideslip

Of the propeller aircraft, only the strongly powered glow Stik climbs in knife-edge, and only at full throttle. The Extra 300 is an aerobatic design built for knife-edge, yet with full top rudder it sinks 38 m/s. At its 20.7° of sideslip it develops CY = −0.023 on wing area. Its own linear coefficient, CYβ = −0.479/rad, gives −0.173 at that sideslip, and holding it up at 48 m/s needs only about 0.05. The traces show the same collapse for the P-51 (−0.054 at 22.0°; linear −0.161) and the electric Stik (−0.092 at 17.3°; linear −0.148).

All three blend from the empirical oracle to the local surface model between 15° and 25° of sideslip (`aero.envelope.sideslip_blend`). The local model carries wing strips, tail surfaces and the opt-in fuselage yaw couple. It has no fuselage side force, the crossflow load a fuselage carries at large sideslip. The side force therefore fades exactly where knife-edge flight begins. The jet holds knife-edge only because its thrust carries weight at 16° of nose-up attitude.

This is a shared physics gap, not a P-51 data error. A fix is a fuselage crossflow side-force law in the local model, with per-aircraft side-area data from each generator, verified against this card's knife-edge rows. No coefficient was changed here.

## Finding 2: the glow Stik cannot fly slowly

The MAX-61FX Stik has no level trim below 19.5 m/s, while the electric Stik trims down to 10.5 m/s. The session trim fails there with a non-finite residual. Ten seconds into a flight at idle the engine still turns 10,930 rpm, so the airplane cannot slow down to stall in 40 s. Its power-off stall is therefore unmeasured. The electric Stik idles at 2800 rpm on the same card. This points at the glow installation's in-flight idle or the trim solver's glow branch. It belongs to the [glow engine track](../../../GLOW-ENGINES.md).

## Pilot lessons from building the card

These are recorded so the next card or pilot does not repeat them.
- **Coordination means the ball.** With β = 0 coordination, the P-51's left and right 60° turns differed by 17 % (19.0 against 16.0°/s). An 8–10 N slipstream side force at zero sideslip loaded one turn and unloaded the other. Centring the ball made both 17.7°/s, matching g·tanφ/V.
- **Schedule gains and keep integrators in stick units.** A fixed sideslip gain diverged at 54 m/s. Integrators bounded inside a scheduled gain stopped at a third of the stick: the Stik's knife-edge held 79° of bank with aileron to spare.
- **Bound α near the limits.** An attitude-holding inverted pilot stalled the P-51's cambered wing negatively and lost the bank.
- **Validity has to be judged on the pilot's own commands.** The recorded command columns include the radio trims, so full rudder read as 0.96. Saturation is now taken from the pilot's raw commands.
- **Not every miss is a pilot failure.** A climb whose speed cannot fall to target near vertical, a wing that only mushes at the elevator stop, and a spiral instead of a spin are reported as the airplane's results.

## Limits

The card is pilot-dependent, as stated in the tool README. It flies calm air with flaps up and the gear up in the air. The Extra 300 has no qualified runway start. The glow Stik's power-off stall is unmeasured, and one of its knife-edge holds did not converge (+0.6 m/s). No result here was compared against measured flights of these exact models.
