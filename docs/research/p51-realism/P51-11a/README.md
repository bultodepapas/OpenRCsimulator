# P51-11a: flight flaps and engine smoke for the P-51D

2026-10-15 · Revision 1 · **Status: implemented and verified in software.**
- The P-51 flies with simulated, animated plain flaps (15°/45° kit settings).
- Two optional refinements to the shared flap law fix a wrong-way result on this wing: takeoff flaps lowered CLmax.
- It publishes an estimated RC exhaust outlet, so engine smoke and the smoke pump work.
- Retracts are the next step (P51-11b).

Prefix: P51-11a. [P-51 guide](../../../P51-PLAN.md) · [Tools](../../../../research/p51/p51-11/README.md)

## Flap data

The flap data comes from [`derive_physics.py`](../../../../research/p51/p51-05/derive_physics.py) and uses the shared hinged-trailing-edge law (`controls.flaps.hinged_trailing_edge.v1`), as the Ventage Jet does.

| Input | Value | Basis |
| --- | --- | --- |
| Settings | 15° take-off, 45° landing | CARF 1:4.3 manual p. 28 (`source.json`); XP-51 20°/50° (NACA MR L-566) |
| Span from centreline | 0.1249–0.7996 m | Scaled full-size flap; agrees with XP-51 32.22 ft², chord 23/17 in |
| Hinge fraction | 0.79 (c_f/c 0.21) | Scaled full-size flap |
| Effective-angle limit L | 14.34° | Least squares of the runtime's L·tanh(τδ/L) to Roskam Part VI Fig. 8.13 K′ at c_f/c 0.21 (FAST-GA digitization), rms 0.48° |
| Profile drag coefficient | 0.104 | Raymer eq. 12.61: 0.9 (c_f/c)^1.38 |
| Travel time | 2.5 s each way | Estimated slowed RC servo; the full-size flap took about 15 s |
| Speed advisory | 21.3 m/s EAS | 165 mph full-flap placard at equal CL (0.555); HUD advisory only |
| Elevator mix | 0 | The CARF manual specifies none |

## Finding: the shared law flew wrong on this wing

[`flap_probe.gd`](../../../../research/p51/p51-11/flap_probe.gd) solves trimmed maximum lift (power off, elevator for zero pitch moment) and trim changes on the runtime equations. With the shared law as it was ([output](flap-probe-shared-law.txt)):

- **Takeoff flaps lowered CLmax.** 15° gave 0.890 against 0.989 clean, raising the stall speed from 15.9 to 16.8 m/s; 20° about broke even and 45° gave +18 %. The law shifts a flapped strip's whole stall onset by its full camber shift. On a wing without a tabulated polar the strip then falls onto the flat-plate post-stall plateau while the unflapped outboard wing is still at its peak. The Ventage Jet's measured-proxy polar keeps post-stall lift high, so it is unaffected (×1.22 at 15°).
- **Flaps pitched the nose up 3–4.8°** (elevator at equal stall margin) where the XP-51 needed 1.0° more up elevator at 20° (power on) and about −0.1° with 50° flap plus gear (power off; [Table III](sources/mr-l566-table3-p47.png)). At fixed α, 20° of flap gave wing ΔCm −0.022 and tail ΔCm +0.058 for ΔCL 0.32. The wing term is too small because flap lift acted at the wing-body ARP, which the calibrated fuselage term places 53.7 mm (0.11 c) ahead of the wing's own 25 % MAC.

## Correction: two optional shared-law fields

When absent, both fields leave the law exactly as before. They are byte-identical at κ = 1 and offset 0, checked over 300 states.

1. **`flaps.stall_shift_fraction` κ = 0.328.** A flapped strip stalls κ of its camber shift earlier, so its section CLmax rises by slope·(1−κ)·shift. κ is derived as the mean over 15–45° of 1 − ΔClmax/ΔCl₀. ΔClmax comes from Roskam Part VI Figs. 8.31–8.33 (FAST-GA digitization) at the flap-span t/c 0.149 and c_f/c 0.21; ΔCl₀ = cl_α·τ·K′·δ with cl_α 6.0/rad (NACA 66-series). The range over 15–45° is 0.28–0.41. The loader rejects κ when the wing has a tabulated polar, which sets its own stall.
2. **`flaps.lift_reference_offset_m` = 0.0537 m.** Flap camber lift acts at the wing's 25 % MAC: the generator's x_ac − x_ARP.

## Results ([final probe](flap-probe-final.txt))

| | Clean | 15° | 20° | 45° | XP-51 flight |
| --- | ---: | ---: | ---: | ---: | --- |
| Trimmed CLmax | 0.989 | 1.105 | 1.132 | 1.195 | Gliding 1.5, landing (50°) 1.6 ([table](sources/mr-l566-clmax-p34.png)) |
| Ratio to clean | 1 | 1.117 | 1.144 | 1.208 | 1.067 at 50° |
| 1-g stall speed | 15.9 m/s | 15.1 | 14.9 | 14.5 | — |
| Glide angle at CL 0.56 | 6.5° | 7.1° | 7.6° | 10.2° | — |
| Power-off trim change at equal stall margin (negative = more up) | — | +1.1° | +1.3° | +1.5° | ≈ −0.1° (50° + gear) |
| Power-on trim change | — | +0.9° | +1.1° | +1.1° | −1.0° at 20° |

Before the correction the trim change was +2.9 / +3.6 / +4.8° power off. Sensitivity runs: [offset only](flap-probe-offset-only.txt), [κ 0.6](flap-probe-kappa0.6.txt), [κ 0.4](flap-probe-kappa0.4.txt). κ = 0.6 was still non-monotonic, and κ hardly changes the 45° value, which the post-stall plateau term sets.

**Open.** The model's +21 % at 45° lies between a Roskam full-flap estimate for this span (about ×1.5) and the XP-51's measured ×1.07, whose stall was defined by lateral instability. The power-on trim change keeps the wrong sign by about 2°. The probable source is the missing propeller-wing coupling (the slipstream over the flapped inboard wing), the P51-22 owner's item. Neither is calibrated away.

## Mechanism and rendering

[`p51d_model.gd`](../../../../app/aircraft/p51d_model.gd) hangs each flap panel on `flap_<side>_hinge` on the swept hinge line, as the ailerons. The pivots sit outside the four control-surface hinges, so the model contract and radio bindings are unchanged. `set_flaps()` renders the session's accepted angle. The flap nose uses a 2:1 bevel and a 3 mm cove: the swept hinge carries the nose apex at the flap ends about 0.5 mm forward at 40–45°, and `verify_p51_clearance` caught it. Clearance now passes with the flaps at 15° and 45°: 28 checks in 42 s.

## Engine smoke (P51-V12)

The smoke system needs an authored RC outlet. The CARF 1:4.3 manual (pp. 11–13; [PDF](https://carf-models.com/files/product/9b/86/19/carf_models_mustang_instructions.pdf), SHA-256 `c27824e3…c7d7ce`, as in the resource manifest) installs the engine with a wrap-around header and an MTW 110 canister inside the fuselage. The canister sits in a plywood tunnel along the floor behind a heat shield, and the radiator exit is cut open for the cooling air. The manual does not state where the canister outlet exits.

The builder therefore publishes one **estimated** anchor at the radiator exit door's trailing edge, pointing along the open door, with an 8 mm radius (an MTW 110-class outlet) and an optional presentation smoke pump. The smoke system accepts it: one valid anchor, and kind `glow_prop` matches the propulsion source. The exhaust-visibility law was tuned for oily glow fuel; a 1:40 gasoline mix smokes less, which is a presentation estimate for the smoke owner.

## Verification

Godot 4.7.2, native Windows ([logs](tests/)).

- **New and changed checks:**
  - [`test_p51_flaps.gd`](../../../../app/tests/test_p51_flaps.gd) passes 12/12: data, byte identity, monotonic CLmax and the pinned diagnosis, the 2.5 s actuator through the session, and the rendered hinges.
  - `verify_p51` passes 248/248 and `verify_p51_clearance` 28/28.
  - `test_flap_aero`, `test_flaps_session`, `test_flaps_ui`, Ventage Jet handling and gamepad, `test_aircraft_data`, `test_aircraft_contract` (2,932), trim, modes and golden pass.
  - Schema, parameter register, model manifests, generator, descriptors and the inventory oracle are current.
- **Shared fixes needed by this step:**
  - `Maneuvers.fly` now passes the session's trace metadata for flap and retractable-gear sessions. Before, the trace silently dropped every row of a flap-equipped scripted flight.
  - `test_aircraft_contract` excludes the v2-only flap module from its legacy-adapter comparison, as it already excludes capabilities.
- **Found later:** the migrator's `--check-known` rejected the new flap capability. It is fixed in [P51-11b](../P51-11b/README.md#shared-changes-made-by-this-step-owner-review-requested).
- **Known failures, unchanged:** the P-51 loop (P51-22 departure), lift-off speed and the 80 m stall band.
- **Blocked by another track:** `test_aircraft_catalog` and `test_engine_smoke` do not parse. Commit `932c308d` removed `AirplaneBuilder.AVANTI_ID`, and 19 test references remain. The smoke test's P-51 assertion is updated and will run once that is resolved.

## Limits

Section values come from handbook charts at full-scale Reynolds number; the model wing works at about 0.7 million. The flap law is a strip camber shift with a bounded post-stall plateau, not a flap section polar. The flap pitch and CLmax comparisons are full-size data at equal CL or stall margin. The exhaust outlet location is an estimate from the kit manual. Software verification is not physical validation.
