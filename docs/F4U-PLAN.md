# F4U Corsair 1/5: integration plan

Checked 2026-10-21 · Aircraft/model owner · Prefix **F4U-00…14**. Nothing flies yet: the catalog has no Corsair, and the visual model waits for the author's g1 delivery. This plan states what is prepared, what is blocked and how each step is proven. Implementation, passing software checks and physical validation remain separate claims.

## 1. Identity and scope

A 2.500 m, 1/5-scale F4U-1D Corsair for gasoline power, with retractable taildragger gear, simulated slotted flaps and finite fuel. The visual model derives from the author's full-size Blender master R59; the [delivery request](F4U-BLENDER-HANDOFF.md) specifies the game revision g1. Owner decisions so far are recorded in [DECISIONS](DECISIONS.md): 1/5 scale, sampled retracts, at least three original liveries, a clean configuration.

All required physical capabilities already exist in the aircraft contract: the P-51 flies `retractable_taildragger` gear, a gasoline shaft model, `finite_liquid_fuel` and simulated flaps. The Corsair adds no new physics law; its differences are data (inverted gull wing, NACA 230-series sections, slotted flaps, fin offset) and one presentation extension (F4U-02).

## 2. Documentation and ownership

| Topic | Authoritative home |
| --- | --- |
| Visual delivery requirements for the author | [Blender delivery request](F4U-BLENDER-HANDOFF.md) |
| Sources, full-size data, RC reference candidates | [F4U-01 evidence](research/f4u-corsair/F4U-01/README.md) |
| Provisional wing and tail geometry | [F4U-06 R59 sections](research/f4u-corsair/F4U-06/README.md) |
| R59 review method | [inspect_blend.py](../research/f4u-corsair/F4U-00/inspect_blend.py), [measure_neutral.py](../research/f4u-corsair/F4U-00/measure_neutral.py) |
| g1 preflight | [preflight_glb.py](../research/f4u-corsair/F4U-04/preflight_glb.py), [mutation test](../research/f4u-corsair/F4U-04/test_preflight_glb.py) |
| Shared model, retraction and section contracts | [Aircraft contract](AIRCRAFT_CONTRACT.md#model-and-package-contract) (AS) |
| Rights | [Licensing guide](AIRCRAFT-LICENSING.md) |

F4U owns `docs/F4U-*.md`, `docs/research/f4u-corsair/`, `research/f4u-corsair/` and, once created, `assets/aircraft/f4u-corsair-1-5/`, `app/assets/aircraft/f4u-corsair-1-5/`, `app/aircraft/f4u_*` and F4U tests. The external delivery folder stays read-only. Shared files (`model-bindings.json`, the retraction rig, catalog, Workshop descriptors) change only through their owners' generators and in coordinated commits.

## 3. Gaps found in the shared code

| Gap | Evidence | Resolution |
| --- | --- | --- |
| The imported retraction rig admitted only tricycle gear | `retractable_model.gd`, `imported_model_contract.gd` and `build_models.py` required `left/right/nose`. | **Resolved by F4U-02** (2026-10-22): nose or tail third wheel, with the dependent manifests, descriptors and parked bakes regenerated. |
| Imported GLB gear must rest stowed | `retractable_model.bind()` refuses carriers not at sample 0 (fully stowed). | Corrected in request revision 2: export at `GearRetract` frame 100. |
| Fin offset | NACA RM A7C05 lists a 2° left fin offset. The aero law has no zero-sideslip yaw coefficient. | No extension needed: `aero.surfaces.vertical.incidence` (radians) already offsets the fin's local flow angle in `physics/aero.gd`. F4U-07 sets it and tests the sign against propeller swirl. |
| Slotted flaps | The P-51 flap parameters come from plain-flap data (Roskam Part VI). | No new law: F4U-07 computes the existing flap parameters (effectiveness, angle limit, profile drag, stall shift) from single-slotted-flap data and checks the trend against NACA WR L-440. |

The crash system already supports the three-way wing split (`wing_center` plus outer panels): a hit naming one wing releases only that outer panel, and an unnamed hit releases all wing sections.

## 4. Steps

| ID | State | Work / proof |
| --- | --- | --- |
| F4U-00 | Done 2026-10-21 | R59 review and g1 request, [revision 2](F4U-BLENDER-HANDOFF.md). Proof: review scripts and hashes in the request. |
| F4U-01 | Done 2026-10-21 | [Sources and RC candidates](research/f4u-corsair/F4U-01/README.md). Owner selection of the hardware reference pending (D1). |
| F4U-02 | Done 2026-10-22 | [Retractable-taildragger rig](research/f4u-corsair/F4U-02/README.md): nose or tail third wheel; Avanti/Timber manifests, descriptors, customization and parked bakes regenerated; Avanti 390/390, Timber 452/452, retract suites green. Also fixed the conformance preflight that skipped the Avanti's pose checks; one pre-existing Timber teardown error is handed to TT. |
| F4U-03 | Waiting for g1 | Intake: copy the delivery unchanged to `assets/source-deliveries/f4u-corsair-g1/`; source manifest with per-file SHA-256 (Timber TT-01 pattern); LICENSE and reference-list review. |
| F4U-04 | Tool ready | Preflight: `preflight_glb.py` (strict profile) plus the author's verifier; Godot import with mesh compression disabled; compare landmarks with metadata. Proof of the tool: exact Avanti/Timber counts and 9/9 mutation checks (2026-10-21). Return failures to the author. |
| F4U-05 | Waiting for g1 | Model family: geometry compiler from g1 metadata plus `GearRetract` sampled stowed → down (Avanti `export_blender.py` method); `model-bindings.json` entry (`imported_glb`, `gltf_extras`, `retraction`); model manifest; Workshop descriptor. Proof: model verifier, pose/full-travel checks, conformance. |
| F4U-06 | Started 2026-10-21 | Physics source: full-size geometry ×0.2 from F4U-01 (S = 1.167 m², MAC 0.478 m, NACA 23018→23009), kit anchors from D1. [Provisional R59 sections](research/f4u-corsair/F4U-06/README.md) match published wing and tail areas within 0.6–4 %; gull, dihedral and incidence still lack a primary source. Remeasure on g1. Proof: source file with per-quantity provenance; g1 metrology agreement. |
| F4U-07 | After F4U-06 | Derivation generator (fork of the P-51 [P51-05](../research/p51/p51-05/derive_physics.py) method): gull-wing strips with per-panel dihedral, Reynolds-corrected sections, slotted flaps, fin offset, gasoline twin and propeller tables, ground-effect VLM. Calibration: NACA neutral points (27–30 % MAC) and CL_max trends; held-out checks separate. Output `app/data/aircraft/f4u_corsair_1_5.json`, never hand-edited. |
| F4U-08 | After F4U-05/07 | Gear contacts and `retraction_path` from the sampled g1 action; tail steering, brakes, pneumatic retract timing (Robart data). Proof: ground suites, runway start qualification. |
| F4U-09 | After F4U-08 | Catalog registration, EN/ES names, Home and menu entries, thumbnail. Display name per D2. |
| F4U-10 | After F4U-05 | Presentation: paint slots `paint_body/wing/wing_tip/tail`, livery set and default (D3), registration mounts, light anchors, smoke outlets (exhaust, wingtips). |
| F4U-11 | After F4U-05 | Crash: release checks for each outer panel with its aileron and outer flap, `wing_center`, cowl, propeller, canopy and gear; damage and cost dossier. |
| F4U-12 | After F4U-09 | Verification: `verify_f4u.gd`, clearance sweep, handling tests, flight-test card, baseline `.orfl` per [flight logging](FLIGHT-LOGGING.md). |
| F4U-13 | Owner | Rights record: name-use assessment, livery originality, plan provenance; release category per the licensing guide. |
| F4U-14 | Later | Physical evidence: builder logs, measured mass/CG/servo throws or flight video of the selected kit, if available. |

## 5. Owner decisions pending

| ID | Decision | Recommendation |
| --- | --- | --- |
| D1 | RC hardware reference | FokkeRC Vought F4U-1D 1/5 (2,500 mm, DLE-111/120, Robart rotating retracts). Its flying mass is unpublished; use a 16–21 kg placeholder until found. |
| D2 | Display name | Decide with F4U-13; "F4U Corsair" is a conditional historical name. |
| D3 | Default livery | Choose from the author's proposals. |
| D4 | Propeller variant | Three-blade F4U-1D (matches the airframe); the four-blade is F4U-4. |
| D5 | Engine | DLE-111 (kit specification) unless a 120 cc twin is preferred. |

## 6. Limits

Published full-size data and kit anchors make the physics an estimate. Full-scale Reynolds numbers are 3–4 times the model's. NACA figures come from degraded OCR and must be rechecked against page images before adoption. Software verification, matched geometry and passing conformance do not establish physical realism; F4U-14 evidence and pilot review decide that.
