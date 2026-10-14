# TT-19 — Blender r2 integration

2026-10-13. Native Windows, pinned Godot 4.7.2, Compatibility renderer on NVIDIA RTX 3090. This is software and visual integration evidence; the aircraft remains experimental.

## Accepted source and runtime

The runtime GLB is byte-identical to `Timber Trubo Evolucion V2 BLENDER/turbo_timber_evolution_r2/r2/export/aircraft.glb`, SHA-256 `d75ae605aa3afdf3f417a0ec535c3bd3126c2a5a4eb7827393727152245c6722`. The source package and its editable `source/aircraft_game.blend` remain untouched. The source manifest identifies all 144 nested delivery files, 19,438,463 bytes. Outer duplicate files and the ZIP are not pipeline inputs. The supplied LICENSE is copied verbatim.

| Godot-imported quantity | r1 | r2 |
| --- | ---: | ---: |
| Triangles | 64,291 | 42,519 |
| Mesh nodes | 15 | 21 |
| Material surfaces | 36 | 49 |
| Source materials | 10 | 10 |
| Runtime GLB bytes | 1,692,540 | 1,258,464 |

Triangles decrease 33.9%. Surfaces increase, so this does not establish a frame-time improvement. The cowl has two additional per-instance material overrides described below.

The builder now consumes the author's separate fixed sections and `openrc_section` extras. The legacy r1 triangle map is no longer loaded. Eight detachable groups plus the core cover the model. Left/right fixed wings retain their ailerons and flaps during breakup; engine/cowl and propeller remain distinct. All 13 moving pivots and the fixed thrust frame preserve their rest frames. Root, hinge, propeller and gear interfaces remain compatible with the common renderer.

The shared manifest supports `gltf_extras`. Validation rejects missing or invalid mesh/pivot section IDs, incompatible asset providers and an ancestor that would swallow a different detachable section. Negative tests exercise these failures. Generated model manifests and Workshop descriptors bind the final sources and GLB.

## Visual correction and remaining author work

The raw r2 import has white cowl-foam triangles protruding through its thin black/red markings. The author's `source/_export_data.json` reports 46 of 112 covered cowl samples still above the marking sheet after seating. Disabling generated LODs or mesh compression did not remove the defect; both importer settings were restored. [Godot's import configuration](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_3d_scenes/import_configuration.html) describes these separate importer controls.

The builder clones only the cowl's black and red materials and grows their rendered vertices along normals by 0.8 mm. This reduces the main white tearing without changing mesh vertices, source geometry, measurements or physics. Overrides are independent between model instances and survive wreck duplication. A 1.5 mm trial offered no material improvement, so the smaller correction is retained.

Compare the [raw r2 nose](comparison/r2-raw-inspection_nose_left.png) with the [corrected nose](final-captures/inspection_nose_left.png). Small marking-edge artifacts remain. The Blender author should fix marking/foam intersections in the source, preferably with material regions rather than overlapping shells, and make residual seating failures an export gate. Once corrected, remove the runtime material offset.

Visible white blocks at the assembled wing roots also need author review. The source exporter splits and paints closure faces white with a nominal 0.2 mm inset. These are the leading candidate, not a confirmed individual-face diagnosis. Closures should stay hidden while assembled and cover the openings after detachment. Do not remove the caps merely to improve the assembled view.

The supplied delivery reports flap contact at 40° (0–39° clear), suspension-wire/bracket contact above 6°, and 49 surfaces against the requested soft target of 40. Current flight holds flaps up and suspension static. These advisories are not corrected by clamping control limits. The approximately 75 mm overall-length discrepancy from the manufacturer reference and independent physical validation also remain open.

## Measurements and physical derivation

The measurement script now groups actual fixed wing, fuselage/cowl, tail and fin meshes separately. An early aggregate grouping incorrectly counted the wing-root closure as fuselage width; the final measurement excludes it. Pipeline outputs are regenerated from the imported scene and exact source metadata.

Skin span remains 1.545504 m. R1's 1.547912 m headline span included navigation lenses. Wing area changes from 0.328223 to 0.327007 m², horizontal-tail area from 0.076104 to 0.075715 m², and vertical-tail area above the fuselage from 0.024964 to 0.024848 m², principally following removal of raised paint-shell geometry. These differences do not justify uniform scaling or a claim of altered sweep.

The TT-07 physics generator uses the new measurements with the existing formulas and unchanged empirical inputs. Manual reference mass remains 2.190 kg; inventory, CG and inertia are unchanged. The author's 1.46 kg metadata ledger remains a non-flight placeholder. Estimated level-start speed becomes 13.09818 m/s from 13.07389 m/s. Elevator/rudder travel is re-derived from the same manual linear displacement and updated skin radii. Accepted tyre-profile radii remain unchanged; their difference from r2 mesh radii is only 14 µm main / 4 µm tail.

Authored max-span markers and collision contacts have distinct meanings. The r2 max-span marker lies aft on the wing cap, about 155 mm behind r1's selected navigation-lens marker. The collision generator instead uses the outermost measured leading-skin section at ±0.770 m, mirrored from the right side. This is 2.752 mm inside the maximum cap span; corresponding r1/r2 skin samples differ by less than 0.15 mm. It prevents an arbitrary marker tie from moving the wingtip contact aft. The original cap landmarks remain available for source conformance. [Machine-readable changes](integration.json) include final hull coordinates.

## Verification

- All 629 current application GDScripts parsed. [Parse results](checks/parse.json).
- The model verifier passes 452 checks of hierarchy, sections, dimensions, articulation, instance independence and the two bounded cowl overrides. The 37-check crash regression exercises actual left-wing/controls and cowl detachment without mutating the flying model. [Model](checks/model.log), [crash sections](checks/crash-sections.log).
- Seventeen focused runtime suites pass, including model manifests, renderer, catalog, crash behavior, Timber data/handling/ground, shadows, lights and Workshop trial/integration. The ground fixture now uses the same manifest-bound builder as flight; the old direct-builder fixture lacked the adapter's `model_manifest` field.
- A 3-second native flight produces 720 finite simulation ticks and retains level altitude. Runway/taxi tests qualify settled support, steering, takeoff and 240/480 Hz agreement. [Flight check](checks/flight-verification.log).
- Common model conformance passes in source and exported PCK modes. The package probe runs without `--path app`, checking that imported aircraft and their source proofs are actually packaged. [Conformance report](checks/verification.json), [source preflight](checks/preflight.json), [package preflight](checks/package-preflight.json).
- Exact delivery, geometry build/compile, asset, physics derivation and sensitivity checks pass. A scoped fresh checkout created through a temporary Git index verifies delivery bytes and generated artifacts; the main index was not staged. Nested delivery files use `-text`; generated geometry JSONs use LF. The supplied verification file's `/home/claude/...` path is retained as author-run provenance, not a runtime dependency.

The focused clearance check uses surface triangle crossings and nearest gaps. Ray parity cannot establish containment for the imported aggregate/open shells and is explicitly excluded; it previously produced false positives when applied to a clipped triangle subset. Crossing queries convert triangles to millimetres because Godot's fixed determinant tolerance can miss small triangles expressed in metres (US-V09c). Explicit 1 mm hit/miss fixtures and the final crossing-only control run pass 19 checks ([log](checks/clearance-scaled-controls.log)). Gap distances remain in metres and were not recomputed by that run. This check is not a general watertight-volume or swept-volume proof.

All tested manual and authored control poses have no triangle crossings; the nearest measured gaps are approximately 0.2–0.3 mm. The imported flap at 40° also has a roughly 0.3 mm gap in this check, so the author's endpoint contact report is retained as its own evidence, not reproduced as a triangle crossing.

Suspension clearance is **not qualified** by comparing each merged leg against the entire fuselage. Those meshes include the mechanical attachment itself: the final millimetre-scale diagnostic finds crossings at 0°, 6° and 7° on both sides ([observations](checks/clearance-gear-observations.log)). The probe separately verifies exact pose restoration, with five checks passing including its hit/miss fixtures. This contradicts a simplistic whole-leg interpretation of the author's isolated wire/bracket report. These observations remain explicit diagnostics; they do not constrain or certify the authored suspension range. Flight leaves suspension static, and the separate physical ground/takeoff checks pass. A future moving-suspension implementation needs named link/bracket collision pairs and source-author review.

Native review includes 12 neutral/full-control views and three colored section views. [Final model](final-captures/inspection_oblique_front_left.png), [top](final-captures/inspection_top.png), [full controls](final-captures/inspection_oblique_front_left_full.png), [section ownership](sections/timber_sections_top.png). Capture manifests record camera poses and hashes. No frame-rate or independent physical-validation claim is made.

Current operating instructions: [asset guide](../../../../assets/aircraft/turbo-lumber-evolution/README.md). Author contract: [Blender handoff](../../../BLENDER-AIRCRAFT-HANDOFF.md). Step ownership and remaining gates: [Timber plan](../../../TIMBER-INTEGRATION-PLAN.md).
