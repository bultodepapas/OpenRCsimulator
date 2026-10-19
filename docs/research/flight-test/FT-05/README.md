# FT-05: card v5 fleet baseline with the hands-off throttle step and the NITRO-06 glow throttle law

2026-10-19 · **Status: card `ft-card-v5` flown on all eight fixed-wing catalog aircraft after the NITRO-06 glow throttle law. 314 of 320 tests valid; `power_step` valid on every aircraft. The glow Stiks now stall power-off (9.3–10.0 m/s) where FT-04 could not slow them down at idle. FT-05 replaces FT-04 as the current baseline.**** [Tool, card and workflow](../../../../research/flight-test/README.md#card-v5-addition-d6e-r3); previous baseline [FT-04](../FT-04/README.md) (card v4); the investigation that added the test and changed the law: [D6e-R3](../../flight-dynamics/power-climb-2026-10-19/README.md), [NITRO-06](../../glow-engines/NITRO-06/README.md).

## What changed

- **Card v5** appends one test after the 39 v4 tests: `power_step` (`card_power.gd`), hands-off throttle steps from the trimmed airborne start to idle, 25, 50, 75 and 100 %, 30 s each, wings held level, the elevator at its trim. It reports height, speed, path angle, attitude, inverted time, the level speed that throttle trims at and the constant-speed climb angle the thrust excess predicts. `summarize.py` has one row for it.
- **Physics since FT-04:** the glow installations (three Stiks and, since `be97a75a`, the Extra) take their charge per cycle from the NITRO-06 carburettor law instead of a stick-proportional admission; the glow fuel-transport seed settles to its fixed point. The Ugly Stik, P-51, Ventage Jet and Timber laws are unchanged.

## Baseline

| Item | Value |
| --- | --- |
| Tree | Working tree on `890b94fc` with this step's uncommitted documentation and the final glow seed/solver edits ([run.json](run.json) lists the dirty paths and every aircraft's data SHA-256). The Ugly Stik, P-51 and Ventage Jet data files changed between FT-04 (`97136354`) and this tree through other tracks' fuel work (FUEL-05f half tank, FUEL-08/09/12 liquid fuel), the Timber's did not. |
| Engine and conditions | Godot 4.7.2 official, Linux headless, 240 Hz; calm standard air |
| Aircraft | Every fixed-wing catalog aircraft (eight) |
| Runtime | About 95 min with 3 jobs on the shared dev VM under load (8–19 min per aircraft, 36–39 min per glow Stik) |
| Valid tests | Stik, 55AX and P-51 40/40; 61FX, FS-64V, Ventage Jet and Timber 39/40; Extra 38/40 |

Each aircraft folder holds `profile.md`, `profile.json` and `run.log`. [summary.md](summary.md) is the fleet table. These are model predictions, not physical validation.

## Verification

- **Every aircraft completed the card with exit 0 and no script errors**; the invalid tests are the airplanes' answers: the 61FX finds no power-on stall break within 40 s at 50 % throttle; the FS-64V flies no up-line for the stall turn; the Extra's full-throttle knife-edges end in a rejected nonfinite stage at 90° of bank with the rudder saturated (a crash-detection limit of the Extra, reported as such); the Ventage Jet does not recover its right inverted spin; the Timber cannot hold the inverted pass at its start speed (as in FT-04).
- **Same tree, with and without NITRO-06.** SAME_TREE_PLACEHOLDER
- **Against FT-04** (`compare.py --allow-card-change --shared-tests --rel 0 --abs 0`): the Timber shows 0 changes over the 39 shared tests; the other seven moved, the glow aircraft by the law and the Stik, P-51 and Ventage Jet by data that other tracks changed since FT-04 (the comparator reports "aircraft data changed" for them). The same-tree run above is the comparison that isolates this step.

## Findings

1. **Hands-off throttle steps (D6e-R3).** From the trimmed start, 25 % of the stick gives −8.5° to +7.4° of path and 50 % gives +4.7° to +37° on every aircraft; 75 % or 100 % takes seven of eight past inverted within 5–27 s with the elevator at its trim. The constant-speed prediction from the thrust excess matches the flown angle wherever the airplane settles (differences 0.1–4° at idle and 25 %). [Analysis and mechanism](../../flight-dynamics/power-climb-2026-10-19/README.md).
2. **Glow idle in flight (NITRO-06).** Level-flight throttle at the start speed: 61FX 20.0 %, 55AX 22.4 %, FS-64V 36.8 %, Extra 22.1 % (FT-04: 1.3–11 %). The three glow Stiks' power-off stalls are valid for the first time (9.98, 9.56, 9.30 m/s) and their idle glides have finite ratios (12.6, 14.4, 9.0). The 61FX still finds no 50 %-throttle stall break, now because half a stick is 81 % of its static rpm.
3. **Extra on the glow law.** The Extra now trims at 22 m/s (catalog start) with 22 % throttle and reaches 41.0 m/s; its full-throttle knife-edge is the one card test that ends in a rejected stage, as noted above (crash-realism and aero tracks).
4. The FT-04 findings on stall turns, snap rolls, dead-stick glides and the go-around stand; the dead-stick glide ratios of the glow Stiks (6.6, 7.3, 4.2) are unchanged because the engine is cut, not idling, in that test.

## Limits

- Model predictions, not physical validation. The glow part-throttle law is calibrated to estimates and one dynamometer figure of another engine ([NITRO-06 limits](../../glow-engines/NITRO-06/README.md#limits)).
- Results depend on the pilot ([rules](../../../../research/flight-test/README.md#pilot-rules)); `power_step` has no pilot pitch input by design.
- Calm air, flaps up; the FT-04 limits on crosswind and 3D figures stand.
