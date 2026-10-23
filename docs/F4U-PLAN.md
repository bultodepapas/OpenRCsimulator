# F4U Corsair 1/4.5: integration plan

Checked 2026-10-23 · Aircraft/model owner · Prefix **F4U-00…14**. The Corsair is an **experimental catalog aircraft**: Home, Quick Flight and the Workshop offer it, the standard flight-test battery flies it, and every catalog-wide suite passes with it. Its physics remains an unvalidated estimate; physical evidence (F4U-14) and the owner's rights decisions (F4U-13) are open. This plan states what is done, what is open and how each step is proven. Implementation, passing software checks and physical validation remain separate claims.

## 1. Identity and scope

A 2.778 m, 1/4.5-scale F4U-1D Corsair of the CARF-Models class, powered by a Moki S250 five-cylinder radial with a 30x18 three-blade, with retractable taildragger gear, simulated slotted flaps and finite fuel. The visual model derives from the author's full-size Blender master R59; the [delivery request](F4U-BLENDER-HANDOFF.md) specifies the game revision g1.3. Owner decisions are recorded in [DECISIONS](DECISIONS.md): sampled retracts, at least three original liveries, a clean configuration (F4U-00), and since 2026-10-22 the 1:4.5 CARF-class giant with a Moki radial (F4U-00-R3), which replaced 1:5.

All required physical capabilities already exist in the aircraft contract: the P-51 flies `retractable_taildragger` gear, a gasoline shaft model, `finite_liquid_fuel` and simulated flaps. The Corsair adds no new physics law; its differences are data (inverted gull wing, NACA 230-series sections, slotted flaps, fin offset) and one presentation extension (F4U-02).

## 2. Documentation and ownership

| Topic | Authoritative home |
| --- | --- |
| Visual delivery requirements for the author | [Blender delivery request](F4U-BLENDER-HANDOFF.md) |
| Sources, full-size data, CARF and Moki data | [F4U-01 evidence](research/f4u-corsair/F4U-01/README.md) |
| Sources, pipeline and commands | [Asset guide](../assets/aircraft/f4u-corsair-250/README.md) |
| Provisional 1/4.5 geometry | [F4U-06 R59 extraction](research/f4u-corsair/F4U-06/README.md) |
| Provisional physics data and checks | [F4U-07 evidence](research/f4u-corsair/F4U-07/README.md) |
| Model family and its probe | [F4U-05 evidence](research/f4u-corsair/F4U-05/README.md) |
| Retractable-taildragger rig | [F4U-02 evidence](research/f4u-corsair/F4U-02/README.md) |
| R59 review method | [inspect_blend.py](../research/f4u-corsair/F4U-00/inspect_blend.py), [measure_neutral.py](../research/f4u-corsair/F4U-00/measure_neutral.py) |
| Delivery preflight and the g1.2 and g1.3 reviews | [F4U-04 evidence](research/f4u-corsair/F4U-04/README.md), [preflight_glb.py](../research/f4u-corsair/F4U-04/preflight_glb.py), [mutation test](../research/f4u-corsair/F4U-04/test_preflight_glb.py) |
| Shared model, retraction and section contracts | [Aircraft contract](AIRCRAFT_CONTRACT.md#model-and-package-contract) (AS) |
| Rights | [Licensing guide](AIRCRAFT-LICENSING.md) |

F4U owns `docs/F4U-*.md`, `docs/research/f4u-corsair/`, `research/f4u-corsair/`, `assets/aircraft/f4u-corsair-250/` and, once created, `app/assets/aircraft/f4u-corsair-250/`, `app/aircraft/f4u_*`, `app/data/aircraft/f4u_corsair_250.json` and F4U tests. The external delivery folder stays read-only. Shared files (`model-bindings.json`, the retraction rig, catalog, Workshop descriptors) change only through their owners' generators and in coordinated commits.

## 3. Gaps found in the shared code

| Gap | Evidence | Resolution |
| --- | --- | --- |
| The imported retraction rig admitted only tricycle gear | `retractable_model.gd`, `imported_model_contract.gd` and `build_models.py` required `left/right/nose`. | **Resolved by F4U-02** (2026-10-22): nose or tail third wheel, with the dependent manifests, descriptors and parked bakes regenerated. |
| Imported GLB gear must rest stowed | `retractable_model.bind()` refuses carriers not at sample 0 (fully stowed). | Corrected in request revision 2: export at `GearRetract` frame 100. |
| A sampled oleo slider as compression helper | g1.3's main sliders move 22.2 mm during `GearRetract` and are the compression helpers; the rig refused sampled helpers and `ground_gear.gd` compressed from the stowed pose. | **Resolved by F4U-05** (2026-10-22): a compression helper may be sampled and `apply()` refreshes its compression rest; spin and steering helpers stay unsampled. Avanti unchanged (390/390). |
| Fin offset | NACA RM A7C05 lists a 2° left fin offset. The aero law has no zero-sideslip yaw coefficient. | No extension needed: `aero.surfaces.vertical.incidence` can carry it. F4U-07 keeps the fin at 0°, as the RC kit and the visual model are built, and uses the CARF manual's 2.5° right thrust instead. |
| Slotted flaps | The flap parameters come from plain-flap data (Roskam Part VI). | No new law. F4U-07 uses the plain-flap fit, conservative for a slotted flap; digitizing single-slotted data (Roskam Fig. 8.17) and checking against NACA WR L-440 remains open. |

The crash system already supports the three-way wing split (`wing_center` plus outer panels): a hit naming one wing releases only that outer panel, and an unnamed hit releases all wing sections.

## 4. Steps

| ID | State | Work / proof |
| --- | --- | --- |
| F4U-00 | Done 2026-10-21; revision 3 2026-10-22 | R59 review and delivery request; [revision 3](F4U-BLENDER-HANDOFF.md#0-review-of-g12-and-what-g13-changes) asks for g1.3: g1.2 scaled 10/9 to 1:4.5 and exported with the gear stowed. Proof: review scripts and hashes in the request. |
| F4U-01 | Done 2026-10-21; giant-scale sources 2026-10-22 | [Sources](research/f4u-corsair/F4U-01/README.md): full-size NACA data, the CARF 1:4.5 kit, manual and review, Moki S250/S400 manuals, Mejzlik tables, field reports. |
| F4U-02 | Done 2026-10-22 | [Retractable-taildragger rig](research/f4u-corsair/F4U-02/README.md): nose or tail third wheel; Avanti/Timber manifests, descriptors, customization and parked bakes regenerated; Avanti 390/390, Timber 452/452, retract suites green. Also fixed the conformance preflight that skipped the Avanti's pose checks; one pre-existing Timber teardown error is handed to TT. |
| F4U-03 | Done 2026-10-22 | g1.3 copied unchanged to `assets/source-deliveries/f4u-corsair-g1-3/`; [manifest.py](../research/f4u-corsair/F4U-03/manifest.py) freezes it in [source-manifest.json](../assets/aircraft/f4u-corsair-250/source-manifest.json) (90 files, visual revision `g1.3-c69151b3c96c`) and proves the copy equals the author's manifest. Licence terms unset (F4U-13). g1.2 was reviewed but not committed. |
| F4U-04 | Done 2026-10-22 | [Reviews](research/f4u-corsair/F4U-04/README.md): g1.2 returned (gear down, 1:5); g1.3 accepted: 89/89 hashes, author's verifier and scale witness, our preflight with the stowed-gear rule and 1:4.5 span, non-gear meshes equal g1.2 × 10/9 within 0.0001 mm, GLB equals `GearRetract` frame 100 within 6 × 10⁻⁷, clean Godot 4.7.2 import. Preflight mutation suite 12/12. |
| F4U-05 | Done 2026-10-22 | [Model family](research/f4u-corsair/F4U-05/README.md): the delivered GLB under `app/assets/aircraft/f4u-corsair-250/`; `GearRetract` sampled from the frozen game source (101 poses, 0.55 µm midpoint error); `compile_model.py` → `model-geometry.json` and `f4u_corsair_geometry.gd`; binding with three flap hinges per side, rotor and sampled taildragger retraction; customization coverage entry. Proof: the model probe 28/0 through the production registry (now `verify_f4u.gd`), shared retract suites and Avanti verifier green, manifests/descriptors/customization/parked bakes regenerated and current. |
| F4U-06 | Done, provisional, 2026-10-22 | [R59 extraction](research/f4u-corsair/F4U-06/README.md) to `geometry-r59.json` at 1/4.5 (every length × 10/9 of the 1/5 run, checked field by field). Planform and tail areas match published values within 0.6–4 %; gull, dihedral and incidence lack a primary source. g1.3 landmarks agree within 0.3 mm ([comparison](research/f4u-corsair/F4U-06/README.md#comparison-with-g13-2026-10-22)); the physics sections stay with R59. |
| F4U-07 | Done, provisional, 2026-10-22 | [Native v2 generator](research/f4u-corsair/F4U-07/README.md) at 1/4.5: 21.5 kg, CARF throws, flaps and thrust angles, Moki S250 from the manual's two static points (static 4,274 rpm against the manual's 4,400, 28.0 kgf), 30x18 three-blade from a blade-element model calibrated on Mejzlik tables (`fit_propeller.py`). Probe 22/22; top speed 57.7 m/s against CARF's 200 km/h warning; pb/2V 0.062 against the full-size 0.064. Remaining: body-yaw calibration, thin-tip stall data, a Moki dyno curve or three-blade table, PDF recheck of OCR values. Output moves to `app/data/aircraft/` at F4U-09; never hand-edited. |
| F4U-08 | Done 2026-10-22 | [Ground data](research/f4u-corsair/F4U-08/README.md): contacts and retraction paths from the g1.3 `GearRetract` in each wheel's plane; GP-06c travel 0.100 m mains / 0.110 m tail (reserve drop worst 93 %); wheel profile with estimated 2.0 N·m pneumatic main brakes; prop-strike probes on the physical 30 in disc. Proof: reserve-drop and visual-contact suites, `verify_f4u.gd` contacts within 0.5 µm of the rendered wheel bottoms. |
| F4U-09 | Done 2026-10-22 | [Catalog registration](research/f4u-corsair/F4U-09/README.md): experimental entry after the P-51, EN/ES texts, Workshop descriptor, economy route, three-blade audio. Natural Random v1 stays at five aircraft (versioned list). Proof: 52 catalog-iterating suites; nine fleet-count assertions updated, then 22/22 affected suites green. |
| F4U-10 | Done 2026-10-22 | [Presentation](research/f4u-corsair/F4U-10/README.md): four paint slots, registration on both fuselage sides, wingtip/tail show smoke, exhaust smoke at the left middle stack, propeller drawn at its physical 30 in, generic night kit. Only the default livery is selectable (no texture-livery switch in the app). |
| F4U-11 | Done 2026-10-22 | [Crash and economics](research/f4u-corsair/F4U-11/README.md): ten wreck sections; C3 wing hits release only their outer panel, a spinner hit propeller, engine and canopy; independent partial costing dossier (servo proxies priced, kit and Moki unpriced with dated evidence). |
| F4U-12 | After F4U-09 | Verification: `verify_f4u.gd`, clearance sweep, handling tests, flight-test card, baseline `.orfl` per [flight logging](FLIGHT-LOGGING.md). |
| F4U-13 | Owner | [Rights record](research/f4u-corsair/F4U-13/README.md) prepared: asset terms unset, Royal RC plan provenance open, name decision D2. Internal use only until the owner acts. |
| F4U-14 | Owner, later | Physical evidence: a piloted baseline `.orfl` (`python tools/flight_log/flight_log.py record --aircraft f4u-corsair-250 --out <new file>`), builder logs, measured mass/CG/servo throws or flight video of a CARF Corsair with a Moki S250. |

## 5. Owner decisions

D1, D4 and D5 follow the owner's 2026-10-22 direction and live in [source.json](../assets/aircraft/f4u-corsair-250/source.json); changing one is a source edit and a regeneration.

| ID | Decision | State |
| --- | --- | --- |
| D1 | RC hardware reference | CARF-Models F4U-1D 1:4.5 (2,800 mm, Sierra retracts). Replaced the FokkeRC 1/5 recommendation |
| D2 | Display name | Open; decide with F4U-13. "F4U Corsair" is a conditional historical name |
| D3 | Default livery | Midnight Blue as delivered (embedded); Coastal Three Tone and Scarlet 308 await a texture-livery feature |
| D4 | Propeller | 30x18 three-blade (Moki manual). CARF's 32 in ground-adjustable scale three-blade is the alternative once data exist |
| D5 | Engine | Moki S250 five-cylinder radial. The Moki S400 belongs to 1/3.5–1/3 models |

## 6. Limits

Published full-size data and kit anchors make the physics an estimate. Full-scale Reynolds numbers are 3–4 times the model's. NACA figures come from degraded OCR and must be rechecked against page images before adoption. Software verification, matched geometry and passing conformance do not establish physical realism; F4U-14 evidence and pilot review decide that.
