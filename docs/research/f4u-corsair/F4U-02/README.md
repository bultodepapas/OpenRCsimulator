# F4U-02: retractable-taildragger extension of the imported gear rig

Delivered 2026-10-22 for the [F4U plan](../../../F4U-PLAN.md). The sampled retraction rig of imported (GLB) aircraft now accepts left/right wheels plus exactly one steered **nose or tail** wheel. Before, it admitted only tricycle gear, so the Corsair's retracting tailwheel could not be bound.

## Change

| File | Change |
| --- | --- |
| [retractable_model.gd](../../../../app/aircraft/retractable_model.gd) | Third wheel is `tail` when declared, else `nose`; the steering helper is required on that wheel and bound as `gear.steering`. |
| [imported_model_contract.gd](../../../../app/aircraft/imported_model_contract.gd) | `retraction` admits gear keys left/right/steering plus `nose` or `tail`. |
| [imported_model.gd](../../../../app/aircraft/imported_model.gd) | New refusal when a rig wheel has no manifest gear key (previously a missing-key runtime error). |
| [build_models.py](../../../../research/aircraft-standardization/build_models.py) | Same two layouts (`RETRACT_ROLE_SETS`); new check that the rig's wheels equal the family's gear keys. |
| [Aircraft contract](../../../AIRCRAFT_CONTRACT.md#model-and-package-contract) | Construction text updated. |
| Tests | `test_retractable_gear.gd`: taildragger rig valid; nose+tail and unsteered tail rejected. `test_models.py`: tail keys accepted, mixed or missing third wheel rejected, rig/binding mismatch rejected. |

Existing data is unchanged in meaning. The Avanti and Timber model manifests pin the three scripts, so they were regenerated with `build_models.py` (only the three script hashes changed), followed by `build_descriptors.py` (two Workshop descriptors), `build_customization.py` and the parked-aircraft bake (`tools/scenery/bake_parked_aircraft.gd`, OpenGL). The bake is deterministic: all six `.res` meshes are byte-identical; only the Avanti and Timber provenance JSON changed. Dated evidence under `docs/research/` keeps its historical hashes by convention.

## Verification (Windows, Godot 4.7.2, Python 3.11)

| Check | Result |
| --- | --- |
| `build_models.py --check`, `build_descriptors.py --check`, `build_customization.py --check` | Current (5 families, 8 descriptors) |
| `bake_parked_aircraft.gd -- --check` | 6/6 ok (Avanti and Timber failed before the rebake) |
| `test_retractable_gear.gd` | 71 checks, 0 failed (3 new) |
| `verify_avanti.gd` | 390 checks, 0 failures |
| `verify_timber.gd` | 452 checks, 0 failures |
| `test_gear_visual_contacts.gd`, `test_retractable_gear_ground.gd`, `test_retractable_gear_input.gd` | 89/89, 26/26, 8/8 |
| `test_models.py`, `test_customization.py` | 27 tests OK |
| `--check-only` parse of the four changed scripts | OK |
| `conformance.py --models-only` | 15 of 16 steps pass; `preflight` fails on two pre-existing engine errors (below) |

## Pre-existing defects found by the conformance run

Both reproduce on clean `HEAD` (`4c3a3749`) with the changes stashed.

1. **Fixed — the Avanti's control pose checks were silently skipped.** `research/aircraft-standardization/preflight.gd` looked up every non-visual control role in the roll/pitch/yaw deflection map. The Avanti's flight flaps are not in that map, so the function aborted with a script error while the aircraft still printed PASS. Flaps now must hold rest under conventional commands, as visual-only surfaces already did. After the fix the Avanti completes its pose checks and passes.
2. **Handed to the Timber owner — dummy-renderer teardown error.** Freeing a second Timber instance prints `ERROR: Parameter "material" is null` twice (`material_get_instance_shader_parameters`, dummy material storage). The first instance and all other aircraft free cleanly. Reproduction: build `turbo-lumber-evolution` twice through `render/airplane.gd` and free the second root. The cached paint-repair path assigns the same materials as the first build, so this is not a missing-material render defect; it appears to be a material released before its render instance in teardown. The conformance log scan treats it as a failure, so `preflight` stays red until it is resolved.
