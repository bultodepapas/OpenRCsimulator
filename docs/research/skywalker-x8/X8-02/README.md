# X8-02: the X8 model family and elevon roles

Built 2026-10-25 for the [X8 plan](../../../X8-PLAN.md). Software integration of the frozen r4 game model ([X8-00](../../../../assets/aircraft/skywalker-x8/source-manifest.json)) as visual family `skywalker-x8` on the shared imported-scene builder. The aircraft is not in the catalog and has no physics data yet (X8-06, X8-09), so no session flies it. Asset guide: [skywalker-x8/README.md](../../../../assets/aircraft/skywalker-x8/README.md).

## What exists

| File | Role |
| --- | --- |
| [install_assets.py](../../../../research/skywalker-x8/X8-02/install_assets.py) → `app/assets/aircraft/skywalker-x8/` | `skywalker_x8.glb` (abisal, SHA-256 `3e14a512…17ac`) and `skywalker_x8_bolido.glb` (`9ecaf7b4…8f93`), byte copies of the delivery's `export/` GLBs; sidecars with the Avanti/F4U import settings, uids from a headless Godot import; the delivery's `LICENSE.txt` |
| [compile_model.py](../../../../research/skywalker-x8/X8-02/compile_model.py) → [model-geometry.json](../../../../assets/aircraft/skywalker-x8/model-geometry.json) (`0fbf3d27…6df6`), [skywalker_x8_geometry.gd](../../../../app/aircraft/skywalker_x8_geometry.gd) | Checks every input against the source manifest; rest transforms from the GLB, each pivot and hinge axis equal to the delivered metadata within 1e-6; two elevons, propeller spin, thrust frame; both skins proven the same airframe; static door pivots, sections, landmarks and datum notes |
| Family `skywalker-x8` in [model-bindings.json](../../../../assets/aircraft/model-bindings.json) → [manifest](../../../../app/data/aircraft_models/skywalker-x8.json) (`f735c419…7ae1`) | Shared builder `imported_model.gd`: roles `elevon_left`/`elevon_right`, rotor `thrust_frame` → `propeller_spin` (axis +X, 0.3049 m), `gear: []` with no gear keys, glTF-extras crash sections, liveries `abisal` (default) and `bolido` |
| Family in [customization-bindings.json](../../../../assets/aircraft/customization-bindings.json) | Paint slots `body` (fuselage, hatch, doors) and `wing` (panels, elevons) on the default skin's `x8_livery` surfaces; no markings or smoke |
| [verify_skywalker_x8.gd](../../../../app/aircraft/verify_skywalker_x8.gd) | Builds both skins by family through `model_registry.gd` (no catalog entry needed) and checks behaviour |
| [test_elevon_model_contract.gd](../../../../app/tests/test_elevon_model_contract.gd) | Shared-contract test for the elevon roles |

## Shared change: elevon roles

`model_manifest.gd` and `build_models.py` add `elevon_left` and `elevon_right` to the closed role list. A family declares either the four conventional roles (unchanged rule) or exactly both elevons and none of aileron, elevator or rudder (`MODEL_CONTROL_LAYOUT_MIXED`; a missing partner is `MODEL_CONTROL_MISSING`). Flap roles stay optional. One hinge node still binds one role. `imported_model_contract.gd` is role-agnostic and needed no change.

`imported_model.gd` reads each role's angle through `role_degrees()`: conventional roles read their own key as before; an elevon is `elevator + aileron_<side>` in app degrees (trailing edge up), the exact inverse of the decomposition the physics side feeds (elevator = (eR + eL)/2, aileron_right = (eR − eL)/2, aileron_left = (eL − eR)/2), saturation included. `apply_surfaces` and the visual-only `set_visual_surfaces` both use it; existing families compute the same numbers as before.

**App sign.** The delivery's + is trailing edge down about local +X. `compile_model.py` turns each hinge +1° on the GLB vertices: the 8 aftmost elevon vertices fall 0.994 mm (chord about 57 mm), so `app_sign` is −1. Godot confirms it: +19.47° app (full pitch-up stick) raises both trailing edges 19.2 mm.

The camera doors are not a supported mechanism role (canopy, tailhook, cowl flaps). They are recorded under `unbound_pivots`, not bound, and stay at rest.

## Results

| Check | Result |
| --- | --- |
| Generators | `X8-00/manifest.py --check`, `install_assets.py --check`, `compile_model.py --check`, `build_models.py --check` (7 visual families) pass; generic GLB preflight passes for both runtime GLBs (38,504 triangles, 11 meshes, 24 surfaces, 9 materials, span 2.1172 m) |
| `verify_skywalker_x8.gd` | 36/36: asset hash and counts; every mesh's section; rests within 1e-7; both skins verified, built and accepted by `validate_derived`; nodes and propeller wrapper present once; no gear, folds or mechanisms; the eight paint targets resolve to `x8_livery`; neutral equals rest exactly; pitch ±19.47°, roll ±23.26° and two saturated combinations turn each hinge to within 1e-3° and move each trailing edge the right way, inside the −40…+31° clearance; doors static and unbound; the propeller wrapper sits on the hub with Z on the thrust axis and spins about it; two instances are independent and share the mesh |
| `test_elevon_model_contract.gd` | 25/25: elevon family accepted, flaps optional; mixing with an aileron, elevator or rudder, a single elevon, an added elevon on a conventional family and an unknown role rejected with their codes; render mapping (pitch only equal, roll only opposite, saturated decomposition exact to 1e-12°); built model posed and restored |
| Existing suites | `test_models.py` 19 tests pass (elevon layout and X8 binding tests added; fresh LF/CRLF clone regenerates); `test_imported_aircraft_model.gd` 68/0; `test_aircraft_package_proofs.gd` 34/0; `verify_f4u.gd`: the 28 asset, registry, importer, control, flap, fold, mechanism and gear checks pass |
| Regenerated manifests | The six other manifests change only in pins: `source_registry.sha256` (all), and for the three v2 families the `imported_model.gd` and `model_manifest.gd` dependency hashes |

**Pending regeneration.** The customization registry (`app/data/aircraft_customization.json`) still pins the previous manifest hashes and lacks the new family, so `render/airplane.gd` refuses every aircraft until `build_customization.py` runs: `verify_f4u.gd` stops at "render/airplane.gd builds the catalog aircraft", `test_aircraft_liveries.gd` fails its 14 production-adapter builds and `test_customization.py` its two currency tests, all with "customization companion is pinned to a different physical model manifest". Descriptors and parked bakes follow at registration (X8-09).

## Limits

No catalog entry, physics, Workshop descriptor or parked bake yet. Camera doors are static. Licence terms are not set by the owner. Import memory and frame cost at 1080p are not measured. Software integration only; nothing here is physical validation.
