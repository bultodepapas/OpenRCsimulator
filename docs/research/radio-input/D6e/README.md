# D6e: dual rates and expo as stick shaping

2026-10-13 · Status: implemented with software checks; owner flight acceptance open. Origin: [elevator investigation](../../flight-dynamics/elevator-repair-2026-10-13.md) §6 P1 and §3.4.

## Why

The simulator flew every aircraft on its manual's HIGH rates with no expo, and the keyboard commands full throw in 0.25 s. At 1.6 × the stall speed a quarter stick then reached the wing stall on the Avanti (30° elevator, 2.3° of α per degree), the P-51 and the Extra, after which the local strip model's post-stall autorotation rolled the airplane. The manuals state normal-flight rates: Avanti elevator 50 % travel with 40 % expo ([controls](../../avanti-s-controls-and-installation.md)), Extra low rate ¾ of 1¼ in at the elevator's widest part ([EX-06 primary sources](../../extra-300-realism/EX-06/primary-sources.md)), P-51 low rate 12° of 15° (Hangar 9 Mustang 1.50 manual, as the data's source). The Ugly Stik first declared no profile; D6e-S below gives it one.

## What

- Aircraft data: optional `controls.rates.normal` with six quantities, each with evidence: `aileron`, `elevator`, `rudder` (travel fraction of `max_throw`, 0.05–1) and `aileron_expo`, `elevator_expo`, `rudder_expo` (0–0.9). Contract, v1/v2 schemas and the AS-01 register carry it; the three generators emit it from their manuals (Extra: linear travel fraction converted to the command fraction of the angular throw, `asin(f·sin δ)/δ`, as the EX-08 audit did; expo 0 where the manual lists none). `max_throw` stays the mechanical maximum.
- Input: `Commands.expo(x, e) = (1 − e)·x + e·x³` (the same sense as the gamepad shaping in `rc_input.gd`) and `Commands.shape_sticks(c, profile, with_expo)`.
- Session: `FlightSession.rate_profile`, `"full"` by default (every test, scripted maneuver and golden flight is unchanged) or `"normal"`; `rates_active()` is true only for keyboard and gamepad sticks of an aircraft with a profile (the gamepad gets the travel without a second expo); a radio always passes through with its own rates. Trims stay in units of the maximum throw and are added after the shaping, like a radio's trim tabs.
- Flight scene: keyboard/gamepad flights use `normal`; `--rates=full` flies the maximum throws; the status line shows `rates: normal` while active. No in-flight toggle yet (a menu/key item for the UI track).

## Effect on the investigation's cases

With the normal profile a quarter stick is 7.5° × expo on the Avanti (2.8° of elevator at a quarter stick with 40 % expo), 3.5° on the Extra and 3.0° on the P-51, below the stall-reaching elevator of §3.4 of the plan at 1.6 Vs (9 %, 20 % and 13 % of the full throw there correspond to 2.7°, 4.8° and 2.0°). Full stick on the normal profile is 15° (Avanti), 14.1° (Extra) and 12° (P-51), which still stalls the wing from the start speed as the manuals warn ("excess throw can provoke a stall or snap roll", Extra p. 43).

## D6e-S: the Ugly Stik's normal rates (2026-10-14)

On the 2026-10-14 Stik audit the owner approved a profile for the Stik. No Jensen plan, note or article states throws ([sources](../../ugly-stik-sources.md)). The nearest primary source with both rates is the **Durafly Ugly Stik V2 manual** (Version 2, p. 8; a 1.1 m foam Ugly Stik): low/high rates of elevator 10/20 mm, aileron 10/18 mm and rudder 12/18 mm either way from neutral (PDF sha256 `652718b2…1d7de`, read 2026-10-14 from [air-rc.com](https://www.air-rc.com/assets/pdf/Ugly-Stik-V2_2216.pdf)). Millimetres do not transfer across scale and chord, so the data keeps the 20/20/25° `max_throw` as the high rate and borrows only the ratios: **elevator 0.50, aileron 0.556, rudder 0.667**. No Ugly Stik source states expo. The **0.15 expo** is labelled estimated, taken from an unattributed Hangar 9 Ultra Stick 10cc specification listing (15 % on low rates). The E-flite Ultra Stick 25e manual, the Stik's aerodynamic donor, gives ratios of 0.59/0.76/0.80 (p. 31, low/high 13/22, 19/25 and 51/63.5 mm) but no expo. The glow variants first went without it, because NITRO's recorded flight evidence binds their exact aircraft bytes. Since the NITRO-05 re-recording (2026-10-14), all three glow Stiks (MAX-55AX, FS-64V, MAX-61FX) inherit it through `build_installations.py`.

Effect, from the [elevator harness](../../../../research/flight-dynamics/elevator-repair/results/steps-comparison.md), `prod_repaired`. A full keyboard pull on normal rates is the trim plus half the throw, which is the harness's `a+0.50` case:

| Trim speed | Normal rates, full pull (`a+0.50`) | Full rates, full pull (`a+1.00`) |
| --- | --- | --- |
| 21 m/s | α peak 7.8°, below the 12.1° stall start; 3.1 g; +76° of pitch over the 1.5 s hold. A 95 °/s maximum roll in the 5 s window comes as speed falls to 1.4 m/s near the vertical | α 16.8° in 0.5 s, 370 °/s roll |
| 15 m/s, start speed | α reaches 12.2° at the end of the 1.5 s hold; 126 °/s maximum roll, speed down to 5.9 m/s | α 17.2° in 0.5 s, 269 °/s roll |

At 21 m/s a full pull no longer reaches the stall at entry. Holding full up from the start speed until the airplane runs out of speed still stalls it, as on a real model. The roll that follows is the open post-stall item, D8b-R2.

## D6e-R1: in-flight rate switch (2026-10-18)

The [elevator investigation](../../flight-dynamics/elevator-repair-2026-10-13.md#11-implementation-record-2026-10-13) left the in-flight switch open; before this step the profile was fixed at launch (`--rates`). `FlightSession.toggle_rate_profile()` now flips normal ⇄ full like a transmitter's D/R switch: **N** on the keyboard, or the optional gamepad action `rates_toggle` (unbound by default, listed under Flight in the controller setup and the controls guide). It is refused, with a note, when the aircraft has no `controls.rates` or a radio is connected (radios keep their own rates). The O2 transmitter overlay and the legacy HUD already show the live profile.

Only the input layer changes. The `.orfl` input boundary is post-rates, so the log format is unchanged; the header adds `rates` (the starting profile) and each switch is a `rates` event. Checks (2026-10-18): `test_rates.gd` 41/0, including a Stik flight logged across a switch at tick 40 (the same 0.6 stick: 0.6817 → 0.3529 of elevator throw, trim included), one `rates` event at that tick and an exact 120-tick replay; `test_flight_log` 3247/0, `test_controls_reference`, `test_controller_sections` 105/105, `test_controller_extended_actions` 104, `test_controller_flight_actions` 31/0, `test_overlay_manager` 97/0, `test_ui_help`, `test_ui_language`, `test_ui_modal_responsive` and `--check-only` parsing of every edited script. Not yet checked: a native in-flight press and the owner's feel.

## Checks

`test_rates.gd` (expo curve, loader parsing and rejection, session default and shaping, the Stik's Durafly ratios inherited by the three glow Stiks, the Timber unaffected; 27/0 on 2026-10-14), `test_aircraft_contract.gd`, `test_aircraft_data.gd`, `test_controls.gd`, `test_regime_consistency.gd`, the AS-01 schema/register checks and the generators' `--check`; `app/test.sh` for the whole.

## Limits

Transmitter curves differ between radios (expo sign and shape), and the manuals' percentages are starting points, not measured setups. Owners flying a radio see no change. Acceptance of the feel is the Gate 2 owner session.
