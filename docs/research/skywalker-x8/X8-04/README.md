# X8-03/04/05/08: flying-wing extensions of the aircraft contract

2026-10-25. The X8 is the first catalog aircraft without a horizontal tail, rudder or landing gear and with a pusher. The [standardization plan](../../../plans/aircraft-standardization.md#control-surfaces-and-actuators) rules that each needs an explicit capability. These steps add them as opt-in modules: a file without the new selections takes exactly the previous code paths, so the existing fleet's data, trims and golden flights are unchanged. The [aircraft contract](../../../AIRCRAFT_CONTRACT.md) owns the semantics; this page records the design reasons and the proof.

## What changed

| Step | Capability | Code |
| --- | --- | --- |
| X8-03 | `controls: elevon` | `ControlSurfaces.elevon_deflections_deg` (radio mix, end-point clipping, exact symmetric/antisymmetric decomposition); `AircraftData._controls` (elevon end point, zero rudder throw, rates without a rudder axis); zero rudder terms and fin effectiveness; `Trim` bank unknown instead of the rudder, elevon end-point check; `CruiseTrim`, `FlightSession._model_is_valid`, `PhysicalIdentity` and the contact contract accept the two elevon IDs |
| X8-04 | optional `airframe_layout: tailless` | `AircraftData._surfaces` (`aero.surfaces.tailless`, no horizontal element), `_induced_map` (no tail share), `_derive_tailless` (τ, station shift, section moment, elevon couple); `Aero._wing_flow`, `_local_loads`, `local_flow_weight` (per-strip stations, elevon angle and couple, no horizontal element) |
| X8-05 | `propulsion_layout: single_pusher` | electric propellers only; the loader requires the hub aft of the CG |
| X8-08 | `damage: tolerant_hull` + `crash_tolerance` | `HullContact.prepare/prepare_geometry` store the aircraft's thresholds and every terminal test reads them; `FlightSession` passes them and records them in trace metadata; the crash director divides its specific energy by `presentation_durability` |
| shared | registry and schema | `aircraft-contract-v2.json` (when-selected object rules), `aircraft-modules-v1.json` (`optional_capability_keys`), both classifiers, `build_schema.py` (if/then rules), physical identity in GDScript and Python |

## Design decisions

- **Elevons stay two logical channels.** Physics keeps the symmetric (`elevator`) and antisymmetric (`aileron_*`) parts that the NTNU coefficients are defined on (δe = (δel+δer)/2, δa = (δel−δer)/2). The mix clips each elevon at its servo end point and then decomposes the clipped pair exactly, so the oracle, the strips and the rendered hinges see the same surfaces.
- **No rudder means zero, not small.** The contract, loader and schema require exactly zero rudder terms and fin effectiveness. A phantom rudder would leave the trim with a singular or fictitious unknown.
- **Rudderless trim banks.** A symmetric airframe trims with zero bank. Propeller torque needs a small aileron, and the resulting yaw is balanced by sideslip with a fraction of a degree of bank. The trim state keeps the flight-path angle exactly.
- **A real strip law, not a disguised tail.** A lumped "horizontal" element at the elevons would satisfy the old loader but misplace lift. On the tailless law each strip acts at its own swept quarter chord, which gives pitch stiffness, pitch damping and tip-stall pitch-up from geometry. The elevons act where they are. The loader derives only what the oracle fixes (CLδe, the neutral point, Cm0, Cmδe), the same "same airplane in two models" rule `_induced_map` applies to CLα and CL0. Roll damping and elevon roll power are predictions.
- **Optional capability keys.** Every v2 file declares every capability. A seventh required key would have forced every aircraft generator to rewrite its data. The registry's `optional_capability_keys` lets an absent `airframe_layout` select the historical law and add nothing to the classification.
- **Pusher without wake.** Electric propellers have no slipstream or P-factor modules, so a pusher's loads are the existing axial thrust, torque and gyroscopic terms at its hub. Prop strike already uses the disc wherever it is. A pusher wake module remains outside v2.
- **Tolerance is data, the law is shared.** `HullContact.law()` (the event-policy identity) is unchanged. The per-aircraft thresholds are part of the aircraft file, so the model hash and checkpoints pin them, and the trace records them.

## Proof

| Check | Result |
| --- | --- |
| Golden flights (`test_golden.gd`) | 4/4 unchanged |
| Contract, loader, modules, physical identity, surfaces | `test_aircraft_contract` 3385/0, `test_aircraft_data` 88/0, `test_aircraft_modules` 85/0, `test_physical_identity` 314/0, `test_control_surfaces` 26/0 |
| Trim and regimes | `test_trim` 14/0, `test_trim_integrity` 731/0, `test_cruise_trim` 22/0, `test_electric_trim_reuse` 18/0, `test_regime_consistency` 90/0, `test_strip_induced` 41/0 (before X8 registration) |
| Offline schema and classifier | all 16 existing v2 files validate against the regenerated schema; Python and GDScript classifiers agree |
| `test_x8_flying_wing.gd` | 37/0: mix and saturation, eight fail-closed mutations, strips reproduce CLα/Cmα/CLδe/Cmδe within 2 %, rudderless trims, glide, tolerant hull (a 3 m/s belly touchdown is terminal under 2.5 J/kg and survivable at 12.5 J/kg) |

## Limits

The tailless law has no ground effect, no downwash lag and no spanwise flow; its strips are planar (the induced map is the unswept Weissinger form). The vertical element lumps both winglets at the centreline, which is exact for their linear side force and yaw but not for asymmetric winglet stall. Servo rate limits act before the mix. These are software contracts and derivations, not physical validation.
