# TT-00-R1 — review of the Blender game delivery r1

2026-10-08 · **Status: independent delivery review; no application integration.**

Owning [plan](../../../TIMBER-INTEGRATION-PLAN.md), original [v12 audit](../TT-00/README.md), requested [handoff convention](../../../BLENDER-AIRCRAFT-HANDOFF.md). Incoming package: `Timber turbo evolution/turbo_timber_evolution/r1/`. The author's revision `r1` is distinct from this research step's `TT-00-R1` identifier.

## Assessment

**r1 is a useful curated visual asset for the next isolated viewer step. Its estimated data is not ready for a flight model, and its source pipeline is not yet reproducible as documented.** The developer has addressed the major asset-organization requests: a neutral GLB, explicit frames and datum, named articulations, fixed/rotating propulsion separation, compact geometry, metadata, part mapping and demonstration material.

Keep this delivery for internal integration experiments. Request the source-pipeline repairs, a physical-data correction and redistribution terms before treating it as a release-ready aircraft. The length discrepancy is acknowledged but remains unresolved; the proposed nose correction is a hypothesis requiring better dimensional evidence.

## Independently verified improvements

The [binary audit](glb-audit.json) records SHA-256 for all 38 supplied files (12,301,268 bytes). It decodes exported vertex/index buffers and composes the complete node transforms, rather than trusting counts or accessor bounds supplied by the author. [Blender DNA inspection](blend-audit.json) checks stored authoring structure separately.

| Area | Earlier v12 | r1 result |
| --- | --- | --- |
| Import artifact | No GLB | Neutral GLB 1,692,540 bytes; demo GLB 1,708,076 bytes |
| Geometry | 1,134,030 triangles across the full STL set | 64,291 exported triangles, 15 mesh nodes, 36 surfaces, ten materials |
| Small hardware | Springs alone: 765,356 triangles | Cosmetic cable/spring mesh: 112 triangles |
| Root | Blender presentation translation/pitch | Exported root is identity at the documented datum |
| Articulation | Stored Blender drivers/constraints, incomplete sidecar membership | 13 explicit moving pivots; named hierarchy and rest transforms agree with metadata |
| Units/frame | Inferred conversion and datum shift | Explicit millimetre CAD → metre Blender → simulator conversion; 242 mm photo-datum shift documented |
| External image dependencies | Not established by evaluated export | GLB has no external buffer/image URI; solid materials, no image textures |
| Source scene | 171 objects; 130 meshes; 20 materials plus studio content | 30 objects; 15 meshes; ten materials; no stored cameras, lights, actions, drivers or constraints |

The triangle reduction is **94.33% relative to the entire old STL collection**, combining retessellation, simplification and deliberate omissions. It is not a measured frame-rate improvement or a like-for-like geometric-error bound.

All 13 articulation parents, axis directions and local rest rotations agree with the GLB. Largest declared-pivot error is about **0.00046 mm**; largest landmark error is **0.00043 mm**, consistent with six-decimal metadata rounding. These are metadata-to-artifact consistency measurements, not real-aircraft dimensional accuracy.

Independent +10° probes confirm trailing-edge-down ailerons/flaps/elevator, right-moving rudder, tailwheel steering displacement, outboard gear compression, forward wheel rolling and the declared propeller direction. Horns/markings are grouped by the export map; the audit verifies their containing mesh hierarchy, not the physical clearance of every original CAD part.

The neutral artifact contains no animation. The demo contains one `control_demo` animation with 13 channels. The neutral exported geometry has finite positions and no exactly zero-area triangles in the decoded buffers. We did not independently reproduce the author's duplicate-face, normal-consistency or coplanar-overlap analysis; the supplied report still describes non-manifold edges and small residual overlaps. Those are not automatically disqualifying for visual meshes.

## Issues and their consequences

### 1. The advertised reconstruction sequence is incomplete

The supplied README says that `modelo_v12.py` creates the BREP cache. In the supplied code, `auditoria2.py` creates that cache, and that command is missing from the sequence. There is also a directory mismatch:

| Resource | Producer or delivered location | Consumer expectation |
| --- | --- | --- |
| Original STL sidecar | `modelo_v12.py` writes `source/scripts/stl_v12/escena.json` | `exporta_juego.py` reads `source/stl_v12/escena.json` |
| BREP cache | Running `auditoria2.py source/scripts/modelo_v12.py` creates `source/scripts/modelo_v12.py.brep/` | Export/documentation scripts read `source/modelo_v12.py.brep/` |
| Lightweight STL directory | Must be generated into a specifically chosen destination | Export script fixes it to `source/scripts/stl_juego/` |

These generated directories are absent in the delivery. Their absence alone would be acceptable if one documented clean-build command produced them at the expected paths. As shipped, the missing step and conflicting paths break that contract. The supplied GLBs remain independently usable.

**Request:** add explicit source/cache/output arguments or a shared package-root definition, include the cache-generation step, pin the complete tool environment, and demonstrate reconstruction from a fresh copy without author-local files. Compare rebuilt dimensions, pivots, materials and mesh counts; explain any non-deterministic binary metadata separately.

### 2. Mass data must not be used for first flights

The component ledger sums to **1.4599 kg**, consistent with its stated 1.46 kg. Its weighted longitudinal CG is **60.657 mm** aft of the declared datum, consistent with the rounded 60.6 mm entry. The arithmetic is credible; the component estimates are not a validated mass budget.

The previously collected manufacturer manual for the B revision gives **2.190 kg** with its recommended 4S 3200 mAh pack. r1 is roughly **0.730 kg / 33.3% lighter**; even its stated +15% range ends at 1.679 kg. The earlier unsuffixed manual's 2.150 kg is also well outside that range. Hardware revision still needs confirmation, but neither known reference supports this first-flight mass. [Manufacturer evidence](../TT-00/sources.md)

The phrase `Use for first flights only` in `metadata.json → mass_properties.status` should be replaced with an explicit non-flight placeholder designation. Obtain a matched mass/CG measurement or a revision-specific documented baseline, then reconcile component estimates to it. An agreeable CG percentage does not validate mass, inertia or handling. No inertia tensor is supplied.

### 3. Length and hardware identity remain unresolved

Decoded dimensions are **1.547912 m span, 1.116560 m length and 0.434000 m height**. The earlier length discrepancy remains about **76.6 mm** against the 1.040 m reference. The author proposes shortening the nose by approximately 50–60 mm based on photos; we have not independently calibrated those photos or verified that allocation of the discrepancy.

Do not correct geometric dimensions to preserve an estimated CG. Establish geometry from reliable endpoints/reference evidence, then recompute masses, CG and wheel relationships. The package identifies wheels, no slats and no floats, but not the exact commercial hardware revision. Propeller, motor and battery remain estimated.

### 4. The supplier verifier is not a failing acceptance gate

`verification.json` records 20 passing checks. Inspection of `verifica_glb.py` shows that checks write/print results but do not produce a failing process exit when a check is false. It also consumes generated `_export_data.json`, absent until the export pipeline works. We did not rerun that Blender verifier.

**Request:** aggregate mandatory failures, exit nonzero on any failure and test a deliberately changed pivot and missing node in disposable copies. Treat the stored report as the author's evidence, not an automatically enforced CI gate.

Our independent audit exits nonzero for failed checks. [Mutation evidence](audit-mutations.json) confirms a valid control passes and that a 10 mm pivot shift and reversed declared axis fail their intended checks.

### 5. Distribution is explicitly pending

`LICENSE.txt` now identifies authorship and explicitly limits the package to internal evaluation while redistribution terms are unset. This is clearer than v12, but it does not grant permission to publish its assets. Record the owner's chosen terms before a public repository asset commit or packaged release. This review does not distribute the supplied model files.

## Adapter decisions for the simulator team

These are integration tasks, not reasons to ask the model author to redo a sound rig:

- **Root name:** use a small wrapper named `airplane` around `TurboTimberEvolution`, or normalize the imported root in the builder without changing the datum.
- **Propeller axis:** all r1 pivots use local +X, while the current app writes `propeller.rotation.z`. Add an axis-aware adapter or a correctly oriented wrapper; directly reusing that assignment would spin around the wrong axis.
- **Control signs:** r1 positive aileron/elevator angles move the trailing edge down; the app's `surface_degrees()` describes those surfaces positive up. Convert explicitly. Rudder is right-positive in both descriptions. Preserve `rest * local_rotation`.
- **Gear:** keep wheel spin, tail steering and suspension separate. Verify steering against the simulator's tail-contact convention. Static cosmetic cables do not follow suspension compression; either keep visual compression disabled initially or rebuild those endpoints during posing.
- **Identifiers/schema:** the package uses underscores in `eflite_turbo_timber_evolution`; the plan proposes a hyphenated catalog ID. Choose one app ID and record the source alias. Delivery metadata is not `openrc-aircraft v1`: `evidence` labels, configuration choices and units require deliberate normalization into the app's `kind`/source contract.
- **Physics:** current loader inspection still accepts `glow_prop` and `turbine`, not electric propulsion. Flight flaps, physical mass/inertia and trim remain separate prerequisites. The existence of the demo does not implement flight behavior.

## Reproduction and scope

From repository root, with the external r1 package present and Python with **NumPy 1.26.4**:

```bash
python3 research/timber/tt00-r1/audit_glb.py \
  'Timber turbo evolution/turbo_timber_evolution/r1' /tmp/timber-r1-audit.json
cmp /tmp/timber-r1-audit.json docs/research/timber-integration/TT-00-R1/glb-audit.json
python3 research/timber/tt00-r1/check_audit_mutations.py \
  'Timber turbo evolution/turbo_timber_evolution/r1' /tmp/timber-r1-mutations.json
cmp /tmp/timber-r1-mutations.json docs/research/timber-integration/TT-00-R1/audit-mutations.json
```

The GLB reader supports the uncompressed, nonsparse accessors used by this package; it is not a full glTF validator. The saved JSON preserves source hashes, counts, transforms, discrepancies and checks. Binary-reader setup for the additional `.blend` inspection is documented in [TT-00](../TT-00/README.md); rerun that same script with r1's `source/aircraft.blend`.

The incoming package remains unmodified. No shared application code, physics data, other aircraft or ROADMAP changed for this analysis. App-wide tests and flight/export acceptance are outside this isolated delivery review. Original source reconstruction, evaluated Blender authoring, physical validation and target-machine performance remain unproven.
