# D6e: dual rates and expo as stick shaping

2026-10-13 · Status: implemented with software checks; owner flight acceptance open. Origin: [elevator investigation](../../../plans/elevator-flight-dynamics-repair.md) §6 P1 and §3.4.

## Why

The simulator flew every aircraft on its manual's HIGH rates with no expo, and the keyboard commands full throw in 0.25 s. At 1.6 × the stall speed a quarter stick then reached the wing stall on the Avanti (30° elevator, 2.3° of α per degree), the P-51 and the Extra, after which the local strip model's post-stall autorotation rolled the airplane. The manuals state normal-flight rates: Avanti elevator 50 % travel with 40 % expo ([controls](../../avanti-s-controls-and-installation.md)), Extra low rate ¾ of 1¼ in at the elevator's widest part ([EX-06 primary sources](../../extra-300-realism/EX-06/primary-sources.md)), P-51 low rate 12° of 15° (Hangar 9 Mustang 1.50 manual, as the data's source). The Ugly Stik's 20° is already its estimated low rate and declares no profile.

## What

- Aircraft data: optional `controls.rates.normal` with six quantities, each with evidence: `aileron`, `elevator`, `rudder` (travel fraction of `max_throw`, 0.05–1) and `aileron_expo`, `elevator_expo`, `rudder_expo` (0–0.9). Contract, v1/v2 schemas and the AS-01 register carry it; the three generators emit it from their manuals (Extra: linear travel fraction converted to the command fraction of the angular throw, `asin(f·sin δ)/δ`, as the EX-08 audit did; expo 0 where the manual lists none). `max_throw` stays the mechanical maximum.
- Input: `Commands.expo(x, e) = (1 − e)·x + e·x³` (the same sense as the gamepad shaping in `rc_input.gd`) and `Commands.shape_sticks(c, profile, with_expo)`.
- Session: `FlightSession.rate_profile`, `"full"` by default (every test, scripted maneuver and golden flight is unchanged) or `"normal"`; `rates_active()` is true only for keyboard and gamepad sticks of an aircraft with a profile (the gamepad gets the travel without a second expo); a radio always passes through with its own rates. Trims stay in units of the maximum throw and are added after the shaping, like a radio's trim tabs.
- Flight scene: keyboard/gamepad flights use `normal`; `--rates=full` flies the maximum throws; the status line shows `rates: normal` while active. No in-flight toggle yet (a menu/key item for the UI track).

## Effect on the investigation's cases

With the normal profile a quarter stick is 7.5° × expo on the Avanti (2.8° of elevator at a quarter stick with 40 % expo), 3.5° on the Extra and 3.0° on the P-51, below the stall-reaching elevator of §3.4 of the plan at 1.6 Vs (9 %, 20 % and 13 % of the full throw there correspond to 2.7°, 4.8° and 2.0°). Full stick on the normal profile is 15° (Avanti), 14.1° (Extra) and 12° (P-51), which still stalls the wing from the start speed as the manuals warn ("excess throw can provoke a stall or snap roll", Extra p. 43).

## Checks

`test_rates.gd` (expo curve, loader parsing and rejection, session default and shaping, Stik unaffected), `test_aircraft_contract.gd`, `test_aircraft_data.gd`, `test_controls.gd`, `test_regime_consistency.gd`, the AS-01 schema/register checks and the generators' `--check`; `app/test.sh` for the whole.

## Limits

Transmitter curves differ between radios (expo sign and shape), and the manuals' percentages are starting points, not measured setups. Owners flying a radio see no change. Acceptance of the feel is the Gate 2 owner session.
