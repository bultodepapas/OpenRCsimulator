# F4U-16: selectable paint schemes

Built 2026-10-23 for the [F4U plan](../../../F4U-PLAN.md) at the owner's request ("an option for the different paint scheme"). The five complete liveries of the author's g1.13 delivery ([F4U-15](../F4U-15/README.md)) are selectable for the Corsair. Presentation only: every scheme flies the same model.

## Use

On Home, open **Aircraft** and select the F4U Corsair. The **Paint (F4U Corsair)** row at the top of the page cycles Naval 308 — Midnight (the default, D3), Super Corsair 57 / SOHIO, Sunburst Splash, Spectrum Wings and Blue Angels Corsair; the names are the author's. The backdrop shows each scheme. The choice is saved per aircraft in the `[liveries]` preferences and used by every flight of that aircraft, including Natural Random. Aircraft with one paint show no row. The direct route takes `--livery=<id>` and refuses an ID the aircraft does not offer.

The Flight page has no spare height at 1280×720 or 1920×1080 (`test_ui_home`). A first placement in its collapsed details was off screen at 1080p, so the row sits on the Aircraft page, where the aircraft is chosen.

## How it works

| Layer | Change |
| --- | --- |
| Runtime assets | [install_liveries.py](../../../../research/f4u-corsair/F4U-16/install_liveries.py) copies the four other frozen livery GLBs into `app/assets/aircraft/f4u-corsair-250/` byte for byte, with the default model's import settings. Git stores each once: the copies are the frozen delivery's blobs. |
| Geometry source | [compile_model.py](../../../../research/f4u-corsair/F4U-05/compile_model.py) lists the liveries in the author's order with the author's names and proves each is the same airframe as the default: node names, hierarchy, rest transforms, crash-section tags, mesh bounds and triangle count. Four mutations (moved hinge, retagged section, renamed node, grown mesh) are caught. Materials differ: the Blue Angels and Splash GLBs add a spinner material. |
| Model manifest | Optional `liveries` (version 2): `{id, label, path, sha256, import_sha256}`, two to eight, the first being the default asset ([contract](../../../AIRCRAFT_CONTRACT.md#model-and-package-contract)). `build_models.py` pins every GLB and import sidecar. |
| Provenance | `describe()` still verifies only the default asset. `model_registry.livery()` hashes another livery's GLB and sidecar when it is built, from the package proofs in an export; the export plugin adds those proofs. |
| Builder | `imported_model.build(manifest, livery_id)` loads the chosen GLB and checks it against the same generated geometry. The root carries `livery` and that GLB's `asset_sha256`; the derived check accepts only that pair. |
| Shell | Home's Paint row, `app_root.set_livery`, the backdrop cache keyed by aircraft and scheme, and the flight's `livery`. A Workshop trial flies the default paint, because appearance-profile slots target the default's surfaces. |

## Correction to F4U-17

The livery suite ended with `Pages in use exist at exit in PagedAllocator`, which `run_checked.py` counts as a failed check. The cause was F4U-17's fold binding: each hinge record referred to its fold and the fold's member list referred back to the hinge record. GDScript Dictionaries have no cycle collector, so every Corsair build leaked them. Fold members now name their hinge by key. `verify_f4u.gd` passes 33/33 with no engine error ([lesson](../../../LEARNINGS.md)).

## Verification (2026-10-23, Windows, Godot 4.7.2)

| Check | Result | Evidence |
| --- | --- | --- |
| [test_aircraft_liveries.gd](../../../../app/tests/test_aircraft_liveries.gd) | 75/75 through the checked runner: 17 manifest mutations rejected; version 1 manifests cannot declare liveries; on-use verification refuses unknown IDs and tampered GLB or sidecar hashes; all five schemes build through the production adapter with every binding, pass the derived check and paint the fuselage differently from the default; forged root identities fail; preferences round trip and refuse malformed entries; Home shows, cycles and resolves the row | [checks/test_aircraft_liveries.log](checks/test_aircraft_liveries.log) |
| [livery_check.gd](../../../../research/f4u-corsair/F4U-16/livery_check.gd) on the production shell, 1920×1080, OpenGL | 16/16: the row cycles all five schemes and back; the backdrop shows each one's GLB; each choice is saved, and the default is saved as no entry; a one-paint aircraft shows no row; Fly builds the saved scheme; the direct route refuses an unknown ID (exit 31) and flies `--livery=blueangels` | [checks/livery-check.json](checks/livery-check.json) |
| Screenshots | Each scheme on the Home backdrop with the row visible, and Spectrum Wings on the runway in flight. Reviewed; not committed | — |
| `verify_f4u.gd` | 33/33, no engine error | [checks/verify_f4u.log](checks/verify_f4u.log) |
| Parked-aircraft bakes | Rebaked for the importer pin; meshes byte-identical, `--check` 6/6 | [checks/parked-bake.log](checks/parked-bake.log) |
| Generators | `install_liveries.py`, `manifest.py`, `compile_model.py`, `derive_physics.py`, `costing_entry.py`, `build_models.py`, `build_descriptors.py`, `build_customization.py` and `build_runtime.py` current in `--check` mode | — |

## Found during verification: companion flights refused

`test_companions_shell.gd` fails on `main` (`4c760f66`): a Home flight with companions enabled is refused with "solver.sha256: current normalized physics and simulation sources do not match this profile". The Jensen Stik companion profile pins solver identity `69bf5c78…9ffc7290` (133 sources, re-bound in `ee054047` on GitHub's line). The merged tree hashes to `3a8ebbc5…c37ccad1` (134 sources), from parallel changes since: `ground_wheels.gd` rolling law (`e76a72f5`); `mass_inventory.gd`, `simulation.gd` and `vehicle_model.gd` (`7dedb38f`); the launch-trim cache, `launch_trim_cache.gd` and `flight_session.gd`; and F4U-17's throttle hold in `flight_session.gd`. F4U-16 changes no solver source. The [AFC-02 re-bind procedure](../../ai-companions/AFC-02/README.md#electric-hub-inflow-solver-re-bind-69bf5c78-2026-10-23) replays nine retained tapes on two disposable app copies. It was not run: drive C: had 2.1 GB free. The rolling-law change can alter ground runs, so parity is not assumed. The AI-companions owner decides between re-bind and requalification. Companions stay off by default.

## Costs

Headless on the development machine, a default Corsair build takes about 0.48 s; another scheme takes 0.53–0.60 s, including its 9.4–10 MB hash. The four added schemes add 48.5 MB of imported scenes (11.1–14.6 MB each) and 38.3 MB of export proof copies to a package. Only the chosen scheme loads.

## Limits

- Workshop previews, appearance profiles and trials use the default paint; its paint slots and markings do not apply to the other schemes.
- The scheme names are proper names and stay untranslated.
- Parked-aircraft bakes use each family's default paint; no parked Corsair exists.
