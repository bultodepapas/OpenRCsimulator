# F4U-05: the Corsair model family on the shared imported-scene builder

Built 2026-10-22 for the [F4U plan](../../../F4U-PLAN.md). Software integration of the accepted g1.3 visual model ([F4U-04](../F4U-04/README.md)); the aircraft is not in the catalog yet (F4U-09), so no session flies it.

## What exists

| File | Role |
| --- | --- |
| [f4u_corsair.glb](../../../../app/assets/aircraft/f4u-corsair-250/f4u_corsair.glb) and its `.import` | The delivered `aircraft.glb`, byte for byte (SHA-256 `c69151b3…464e`); import settings identical to the Avanti's: mesh compression off, no animation, texture kept inside the scene |
| [sample_gear.py](../../../../research/f4u-corsair/F4U-05/sample_gear.py) → [gear-samples.json](../../../../assets/aircraft/f4u-corsair-250/gear-samples.json) | Blender 5.2.2 on the frozen game source (never saved): 101 uniform parent-local poses of the 17 `GearRetract` carriers, sample 0 stowed (frame 100), wheel-centre paths, midpoint interpolation error |
| [compile_model.py](../../../../research/f4u-corsair/F4U-05/compile_model.py) → [model-geometry.json](../../../../assets/aircraft/f4u-corsair-250/model-geometry.json), [f4u_corsair_geometry.gd](../../../../app/aircraft/f4u_corsair_geometry.gd) | Checks every input against [source-manifest.json](../../../../assets/aircraft/f4u-corsair-250/source-manifest.json); rest transforms from the GLB itself; ten control hinges, the thrust frame and the gear rig |
| Family `f4u-corsair-250` in [model-bindings.json](../../../../assets/aircraft/model-bindings.json) → [manifest](../../../../app/data/aircraft_models/f4u-corsair-250.json) | Shared builder `imported_model.gd`: controls with three flap hinges per side, rotor (`thrust_frame` → `propeller_spin`, axis +X), sampled taildragger retraction, glTF-extras crash sections |
| Family in [customization-bindings.json](../../../../assets/aircraft/customization-bindings.json) | Coverage entry with no slots; textured-livery paint, markings and smoke belong to F4U-10 |
| `probe_model.gd` (since replaced by [verify_f4u.gd](../../../../app/aircraft/verify_f4u.gd), F4U-12) | Built through the production registry and checked behavior |

Control signs follow the Timber, which is authored the same way (local +X, trailing edge down positive): app commands map with −1 for ailerons and elevator, +1 for rudder and flaps. Ranges are the author's checked clearance envelopes (±25°, ±35°, 0–50°); physical throws stay in the aircraft data.

## Shared change: a sampled oleo slider as compression helper

g1.3's main-gear oleo sliders (`gear_compression_left/right`) slide 22.2 mm, their full travel, during `GearRetract`, and the request named them as the compression helpers. The shared rig refused a helper that is also a sampled carrier, and `render/ground_gear.gd` added compression to the pose held at bind (stowed), which would have left the down pose 22 mm off. The rule is now: a compression helper may be sampled, and `retractable_model.gd` `apply()` refreshes its compression rest from each sample, so the existing `ground_gear.gd` code offsets the pose just sampled. Spin and steering helpers stay unsampled, because presentation code rotates them. `build_models.py` applies the same rule through an extracted `_validate_retraction_rig()`. The Avanti's helpers are unsampled and behave exactly as before.

The code change entered history inside commit `c699a7b7` (another track's commit picked up the working tree); the evidence is here and in the [contract](../../../AIRCRAFT_CONTRACT.md#model-and-package-contract).

## Results

| Check | Result |
| --- | --- |
| Gear samples | Sample 0 equals the GLB's stowed carriers (Blender within 1e-6 m and 1e-6 rad, then written from the GLB's own numbers); the last sample's wheel centres equal the delivered down-pose metadata within 2e-5 m; interpolation error at the 100 midpoints 0.55 µm and 0° (samples up to 7.4 mm apart, so subframes were evaluated) |
| Registry and builder (`probe_model.gd`, 28 checks) | Manifest accepted; the scene builds; derived validation passes hinges, rotor, gear, asset and crash sections |
| Controls | +10 app degrees raise the aileron and elevator trailing edges 17–21 mm and move the rudder's 41 mm right; each returns to rest; a 30° flap command turns the hinges 30.000° and lowers all six panels 62–65 mm; 80° clamps at 50.000° |
| Gear | Wheel centres on their compiled paths at extensions 0, 0.5 and 1 (error 0); 0.01 m of `ground_gear.gd` compression raises the main wheel 0.010000 m from the down sample, and the next sample restores it |
| Presentation against physics contacts | Tail 0.0000 m; mains 0.0124 m (lateral: the R59 extraction took the low-poly tyre's lowest vertex); reconciled in F4U-08 |
| Shared suites | `test_retractable_gear.gd` 77/0 (new: sampled compression accepted, sampled spin and steering rejected, `apply()` refresh), ground 26/0, trace 21/0, input 8/0, `test_gear_visual_contacts.gd` 89/0, package proofs 29/0, `verify_avanti.gd` 390/390; Python standardization 55 tests and editor 8 tests pass |
| Regeneration | Six model manifests (all re-pin the binding registry), two Workshop descriptors, the customization registry, six parked-aircraft provenance files (meshes byte-identical); every `--check` passes, `bake_parked_aircraft.gd -- --check` 6/6 |
| Conformance `--models-only` | All steps pass except `preflight`, whose log carries the pre-existing Timber dummy-renderer teardown error handed to TT in [F4U-02](../F4U-02/README.md); `preflight.json` reports all eight catalog aircraft ok |

## Limits

The Corsair has no catalog entry, Workshop descriptor, parked bake or session yet (F4U-09/10). Crash release of each section is untested (F4U-11). Main-wheel contacts differ laterally by 12 mm between the visual model and the physics data until F4U-08 resamples them from g1.3. Software integration; nothing here is physical validation.
