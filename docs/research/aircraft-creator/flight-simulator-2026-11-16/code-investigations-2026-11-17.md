# Flight Simulator import: source-code investigations

**Date:** 2026-11-17. **OpenRC baseline:** `2e83947f9c1d7acf257ff2971cee58151e569106`. **Status:** inspected source and proposed engineering requirements; no converter, aircraft or performance campaign executed. This document deepens the [24 earlier investigations](follow-up-24-investigations/README.md) with **26 code-backed cases across eight external repositories and OpenRC**. Cases are not a count of independent publications or successful imports. The [milestones and contingency matrix](../../../plans/flight-simulator-import-milestones.md) own the resulting implementation evidence, including positive, refusal and recovery outcomes. Existing AC-FS owners and W01–W19 remain authoritative.

## Inspection method and pinned sources

Read the named source functions, configuration/XML and selected tests at immutable commits. Distinguish **observed code**, **inferred risk**, **proposed independent fixture**, and **executed result**. Here the last category is absent. A source-level counterexample is not an upstream runtime bug reproduction. No third-party source was executed, vendored or turned into an OpenRC dependency; no binary aircraft assets were downloaded or decoded.

| Key | Repository and inspected revision | Role and current disposition |
| --- | --- | --- |
| FBW | [flybywiresim/aircraft](https://github.com/flybywiresim/aircraft/tree/753bbdd744d26d76b600c5f23ee59ece4f68341f), `753bbdd744d26d76b600c5f23ee59ece4f68341f` | Real composition/control counterexamples; mixed code/art terms; outside the first RC topology |
| C17 | [Delta-Simulations/MSFS-C-17](https://github.com/Delta-Simulations/MSFS-C-17/tree/75d119d6cd3bfc163f073a75277f8ffb70007b05), `75d119d6cd3bfc163f073a75277f8ffb70007b05` | Active-LOD and conditional-motion cases; mixed terms; no first-release flight claim |
| BRICK | [tml1024/flying-brick](https://github.com/tml1024/flying-brick/tree/e816b6b86bfbd16183ed5784b3336a0338b8315b), `e816b6b86bfbd16183ed5784b3336a0338b8315b` | Custom-flight-code counterexample; original code MIT, separately referenced assets retain their own terms |
| ASOBO | [Official 2020 Blender IO](https://github.com/AsoboStudio/Microsoft-Flight-Simulator-2020-glTF-Blender-IO/tree/b3c2f174776ad9119999ce5b73106333a24bfeee), `b3c2f174776ad9119999ce5b73106333a24bfeee` | Source-format/material reference, Apache-2.0 declaration; Blender/add-on coupling remains, not a selected shipped converter |
| BLEND | [bestdani/msfs2blend](https://github.com/bestdani/msfs2blend/tree/296246a5158766a2f85277c43d87dde35400a36e), `296246a5158766a2f85277c43d87dde35400a36e` | Reconstruction counterexamples; conflicting root/file license declarations, no code adoption |
| LEGACY | [LievreAI/msfsLegacyImporter](https://github.com/LievreAI/msfsLegacyImporter/tree/bf4fe3f28c2138d37ff5c4d0d890fc30e7335cd7), `bf4fe3f28c2138d37ff5c4d0d890fc30e7335cd7` | CFG/mutation prior art; MIT root declaration does not complete dependency/asset review |
| VALIDATOR | [KhronosGroup/glTF-Validator](https://github.com/KhronosGroup/glTF-Validator/tree/602c54043ba66856b2e68c40fdf2bced975cdb8a), `602c54043ba66856b2e68c40fdf2bced975cdb8a` | Apache-2.0 candidate standards checker; report scope and options require their own admission |
| PEER | [jamesx0416/FlightSim](https://github.com/jamesx0416/FlightSim/tree/88af3af16034c7f2d249e8965ef461ee3a139ecf), `88af3af16034c7f2d249e8965ef461ee3a139ecf` | Additional MSFS importer prior art. No license grant established for inspected files; no license/notice path found in the complete 148-entry tree. Reference only, no copying or dependency adoption |
| OPENRC | [bultodepapas/OpenRCsimulator](https://github.com/bultodepapas/OpenRCsimulator/tree/2e83947f9c1d7acf257ff2971cee58151e569106), baseline above | Existing runtime contracts to extend and regress, not third-party conversion proof |

The [original aircraft/rights investigation](sources-and-examples.md#inspected-aircraft) retains the detailed asset limitations. These sources still do not establish an authorized conventional real-aircraft source for W01. Selecting and recording that exact source is a milestone requirement, not a success inferred from this repository list.

## Aircraft and build-system cases

### C01

**Parent references can be valid inside a selected root.** FBW's livery uses a sibling `base_container`, and its [model.cfg](https://github.com/flybywiresim/aircraft/blob/753bbdd744d26d76b600c5f23ee59ece4f68341f/fbw-a32nx/src/base/flybywire-aircraft-a320-neo/SimObjects/AirPlanes/_FlyByWire_A320_NEO-LIVERY/MODEL.FBW/model.cfg) uses two parent segments to reach the base model. [Variation CFG](https://github.com/flybywiresim/aircraft/blob/753bbdd744d26d76b600c5f23ee59ece4f68341f/fbw-a32nx/src/base/flybywire-aircraft-a320-neo/SimObjects/AirPlanes/_FlyByWire_A320_NEO-LIVERY/aircraft.cfg)

**Decision:** distinguish source dependency references from archive member names. Resolve a reference relative to its declaring file under a versioned rule, then enforce selected-root containment and no-follow access. Archive entries remain strict; permitting a reference's `..` must never permit extraction traversal or filesystem escapes. This corrects the earlier categorical traversal wording.

### C02

**Present on disk does not mean active LOD.** C17's [C17.xml](https://github.com/Delta-Simulations/MSFS-C-17/blob/75d119d6cd3bfc163f073a75277f8ffb70007b05/PackageSources/SimObjects/Airplanes/C17/MODEL/C17.xml) selects `C17.gltf`; its `C17_LOD01.gltf` declaration is commented out.

**Decision:** select from active, version-qualified declarations. A smaller orphan file is not an automatic fallback. A separate explicit recovery selection must have a new selection identity and its own completeness assessment. The earlier LOD01 JSON inspection remains valid as a file inspection, not proof it is the active exterior.

### C03

**A rudder name does not define its motion.** The same C17 XML's `Rudder_Upper_Section` and `Rudder_Lower_Section` depend on on-ground state and a 15-knot threshold, with different lags. For a hypothetical +40-percent input, the expressions request 50/30 below the threshold on the ground and 70/70 otherwise.

**Decision:** those numbers are expression targets, not measured deflections. Report unrepresented conditional behavior; do not flatten it into a proven single-hinge mapping. Independently authored controls for an eligible RC design remain distinct from faithful source-motion conversion.

### C04

**Generated behavior is a dependency, not interchangeable authored text.** FBW's [exterior XML](https://github.com/flybywiresim/aircraft/blob/753bbdd744d26d76b600c5f23ee59ece4f68341f/fbw-a32nx/src/base/flybywire-aircraft-a320-neo/SimObjects/AirPlanes/FlyByWire_A320_NEO/model/A320_NEO.xml) includes `A32NX/generated/A32NX_Exterior.xml`. Its [behavior build](https://github.com/flybywiresim/aircraft/blob/753bbdd744d26d76b600c5f23ee59ece4f68341f/fbw-a32nx/src/behavior/build.js), `translate()`, transforms `type="rnp"` source expressions before writing that output.

**Decision:** identify an unbuilt source tree precisely. Do not run its build script or silently substitute authored XML for generated behavior. Supplying the already generated authorized artifact resolves the missing-file dependency only; its expressions still need qualified semantic support. A later declarative adapter requires its own semantic contract. Otherwise retain the affected limited result.

### C05

**A base glTF can be an assembly ingredient.** FBW's [modelsv2.json](https://github.com/flybywiresim/aircraft/blob/753bbdd744d26d76b600c5f23ee59ece4f68341f/fbw-a32nx/src/model/modelsv2.json) replaces fuselage/windshield nodes, appends parts and attaches lights to wing bones; [buildv2.js](https://github.com/flybywiresim/aircraft/blob/753bbdd744d26d76b600c5f23ee59ece4f68341f/fbw-a32nx/src/model/buildv2.js) applies these operations before `saveGltf()`.

**Decision:** keep source ingredients, assembly recipe and supplied assembled output as separate identities. A successfully decoded ingredient cannot establish the expected complete aircraft. No repository build execution is implied by automatic import.

### C06

**Readable CFG can coexist with a different governing flight law.** Flying Brick's [panel.cfg](https://github.com/tml1024/flying-brick/blob/e816b6b86bfbd16183ed5784b3336a0338b8315b/PackageSources/SimObjects/Airplanes/FlyingBrick/panel/panel.cfg) points to a `FlightModel` WASM gauge. [FlyingBrick.cpp](https://github.com/tml1024/flying-brick/blob/e816b6b86bfbd16183ed5784b3336a0338b8315b/Sources/Code/FlyingBrick.cpp), `throttle2vs()` and `setDirectControl()`, freezes ordinary motion and writes position/velocity; it also reads `static_cg_height`.

**Decision:** trace declarative module references even when modules are inert. Valid wing/control fields do not prove source-equivalent dynamics. A qualified newly authored RC configuration needs separate eligibility and evidence; a custom-code indicator cannot be removed to manufacture success.

### C07

**Visual travel and simulator control feedback can be different signals.** FBW's [ailerons.rs](https://github.com/flybywiresim/aircraft/blob/753bbdd744d26d76b600c5f23ee59ece4f68341f/fbw-a32nx/src/wasm/systems/a320_systems_wasm/src/ailerons.rs) combines hydraulic aileron, elevator and spoiler asymmetry for `AILERON POSITION` feedback and suppresses writes in tracking mode. Its [authored behavior](https://github.com/flybywiresim/aircraft/blob/753bbdd744d26d76b600c5f23ee59ece4f68341f/fbw-a32nx/src/behavior/src/A32NX_Exterior.xml) maps separate left/right hydraulic variables to animation keys.

**Decision:** preserve control dependencies and signs separately from node labels. Recognizing an animation target is not evidence that OpenRC represents the coupled flight-control law.

## Converter and validator cases

### C08

**Repository and source-file license declarations conflict.** BLEND's [root LICENSE](https://github.com/bestdani/msfs2blend/blob/296246a5158766a2f85277c43d87dde35400a36e/LICENSE) declares Apache-2.0; the [Python file header](https://github.com/bestdani/msfs2blend/blob/296246a5158766a2f85277c43d87dde35400a36e/io_msfs_gltf.py) declares GPL v2-or-later.

**Decision:** correct the unqualified Apache description in the earlier tool table. Record this unresolved file-level provenance before any reuse decision. Reading the implementation for failure cases does not select it as a product dependency or resolve the declarations.

### C09

**A successful operator result can contain failed meshes.** BLEND's `get_indices()` uses 16-bit indices, `read_primitive()` assumes specific UV/shared-view layouts, and `create_meshes()` catches per-mesh failures while the operator can finish. [Reader, mesh handler and operator](https://github.com/bestdani/msfs2blend/blob/296246a5158766a2f85277c43d87dde35400a36e/io_msfs_gltf.py)

**Decision:** independently verify expected selected parts, decoded positions and buffer extents. A tool exit status or nonempty scene is insufficient. Broader legal glTF encodings may be qualified individually or refused explicitly; neither silent omission nor parser-layout guessing is acceptable.

### C10

**Scene and transform assumptions change geometry.** BLEND's `create_objects()` reads TRS; `setup_object_hierarchy()` chooses `scenes[0]`. Its conversion changes axes, winding and UVs. [Implementation](https://github.com/bestdani/msfs2blend/blob/296246a5158766a2f85277c43d87dde35400a36e/io_msfs_gltf.py)

**Decision:** use equivalent matrix/TRS fixtures with an asymmetric parent, nonzero pivot, another default scene and front-face markers. Derive world-space reference points independently. Blender's coordinate conversion is not automatically the Godot/OpenRC conversion.

### C11

**Missing images and fallback ordering affect identity.** BLEND's `import_images()` omits missing slots; `collect_fallbacks_of()` returns a set and resolves recursive paths using the original texture root. [Image/fallback functions](https://github.com/bestdani/msfs2blend/blob/296246a5158766a2f85277c43d87dde35400a36e/io_msfs_gltf.py)

**Decision:** preserve each source image index/URI, including failure, and resolve documented ordered fallbacks relative to the correct declaring file. Missing material input must not shift later images or borrow a same-named file from an unselected root.

### C12

**A normal-image rewrite is a specific conversion policy.** BLEND's `convert_normal_image()` changes green/blue channels and saves the image; its `texconv` invocation uses overwrite mode. [Conversion functions](https://github.com/bestdani/msfs2blend/blob/296246a5158766a2f85277c43d87dde35400a36e/io_msfs_gltf.py)

**Decision:** test asymmetric tangent vectors, alpha and color-space roles against an independently specified material profile. Perform writes only to owned staging copies. Do not infer material correctness from producing a PNG, or apply one normal formula to every source convention.

### C13

**Zero and missing material factors differ.** ASOBO's `AsoboMaterialGeometryDecal.Defaults` uses 1.0, while `from_dict()` guards assignments by truthiness, skipping explicit zero. [Defaults and import handler](https://github.com/AsoboStudio/Microsoft-Flight-Simulator-2020-glTF-Blender-IO/blob/b3c2f174776ad9119999ce5b73106333a24bfeee/addons/io_scene_gltf2_msfs_2020/com/msfs_material_props.py)

**Decision:** static inference on a default material suggests a zero would remain default; this was not reproduced in Blender. OpenRC fixtures must distinguish absent, zero and nonzero for supported material fields, or refuse the unsupported extension without substituting a default.

### C14

**A migration heuristic is not a physics oracle.** LEGACY's [cfgHelper.cs](https://github.com/LievreAI/msfsLegacyImporter/blob/bf4fe3f28c2138d37ff5c4d0d890fc30e7335cd7/fs2020LegacyImporter/cfgHelper.cs), `readCSV()`, rewrites comment delimiters and splits values at `=`; `parseCfgDoubleTable()` ignores parse-success flags. [FixFlightModelClick()](https://github.com/LievreAI/msfsLegacyImporter/blob/bf4fe3f28c2138d37ff5c4d0d890fc30e7335cd7/fs2020LegacyImporter/MainWindow.xaml.cs) reads gross weight but parses span twice in one diameter heuristic.

**Decision:** preserve literal source text and explicit errors under a versioned grammar. Do not import these generated values as observed or measured aircraft properties. Unknown numeric data must not silently become zero.

### C15

**Zero validator errors is not a compatibility certificate.** Khronos [errors.dart](https://github.com/KhronosGroup/glTF-Validator/blob/602c54043ba66856b2e68c40fdf2bced975cdb8a/lib/src/errors.dart) makes `UNSUPPORTED_EXTENSION` informational. [context.dart](https://github.com/KhronosGroup/glTF-Validator/blob/602c54043ba66856b2e68c40fdf2bced975cdb8a/lib/src/context.dart) permits filtered issues and stops at the configured issue cap; [validation_result.dart](https://github.com/KhronosGroup/glTF-Validator/blob/602c54043ba66856b2e68c40fdf2bced975cdb8a/lib/src/validation_result.dart) reports `issues.truncated`.

**Decision:** a report used as pass evidence must be complete for its declared checks, with options and limits pinned. Independently admit every required extension through OpenRC's qualified registry. Unsupported-by-validator, unsupported-by-converter, standards-invalid and truncated are different outcomes. A diagnostic-only partial report may remain visible but cannot pass its gate.

### C16

**An authoring utility may mutate the input directory.** LEGACY's `splitCfg()` renames the original CFG; `saveCfgFile()` deletes/recreates destinations. [cfgHelper.cs](https://github.com/LievreAI/msfsLegacyImporter/blob/bf4fe3f28c2138d37ff5c4d0d890fc30e7335cd7/fs2020LegacyImporter/cfgHelper.cs)

**Decision:** optional author tools cannot be embedded as unrestricted source readers. Any selected app-owned worker consumes owned captured input and writes private outputs. Inject output failures/collisions and verify original hashes, cleanup and absence of publishable half-results.

## Additional importer prior art

PEER is useful because it contains concrete MSFS parsing/normalization functions. Its browser compatibility runtime is a different scope; its README claims are not OpenRC evidence. No reuse license was established, and no code from it is adopted.

### C17

**Primitive offsets need dialect semantics.** PEER's [sanitizeMsfsGltf.ts](https://github.com/jamesx0416/FlightSim/blob/88af3af16034c7f2d249e8965ef461ee3a139ecf/src/msfs/gltf/sanitizeMsfsGltf.ts) rewrites `StartIndex`/`PrimitiveCount` slices, while [normalizeAsoboPrimitiveBaseVertex.ts](https://github.com/jamesx0416/FlightSim/blob/88af3af16034c7f2d249e8965ef461ee3a139ecf/src/msfs/gltf/normalizeAsoboPrimitiveBaseVertex.ts) uses index-range heuristics for rebasing.

**Decision:** qualify exact dialect/version and units for byte offsets, index offsets and base vertices. Use different independently marked triangles so a plausible but wrong subset cannot pass a triangle-count test. Ambiguous interpretation remains unsupported; do not adopt a range heuristic as a universal format rule.

### C18

**Typed storage does not determine component meaning.** PEER's [normalizeMsfsTexcoords.ts](https://github.com/jamesx0416/FlightSim/blob/88af3af16034c7f2d249e8965ef461ee3a139ecf/src/msfs/gltf/normalizeMsfsTexcoords.ts) reinterprets non-normalized two-component `Int16Array` UV storage as half-float bits.

**Decision:** require a qualified encoding discriminator before reinterpretation. Test independent half-float bit patterns and an input with the same storage but no supported dialect evidence. Check nonfinite results and normalized/integer alternatives instead of inferring them from array type alone.

### C19

**Sanitization can hide data loss.** PEER's `sanitizeNodes()` removes invalid mesh references; `sanitizeSkins()` removes negative skeleton references. [sanitizeMsfsGltf.ts](https://github.com/jamesx0416/FlightSim/blob/88af3af16034c7f2d249e8965ef461ee3a139ecf/src/msfs/gltf/sanitizeMsfsGltf.ts)

**Decision:** permitted repairs need a named rule, before/after correspondence and an expected-loss policy. Required geometry cannot disappear under a successful-import label. Unknown broken references fail or produce an explicitly limited result, never a ready aircraft by silent deletion.

### C20

**Convenient CFG structures can erase conflict evidence.** PEER's [config.ts](https://github.com/jamesx0416/FlightSim/blob/88af3af16034c7f2d249e8965ef461ee3a139ecf/src/msfs/config.ts), `parseCfg()`, stores section keys in a map; `getCfgSection()` returns the first matching section.

**Decision:** OpenRC must retain repeated declarations and line origins before applying documented effective-value rules. A map can be a derived lookup, not the source-evidence record. Duplicate fields/sections require explicit semantics rather than accidental first-section/last-key behavior.

## OpenRC integration cases

### C21

**Ignoring stale results does not stop stale work.** [source_importer.gd](../../../../app/workshop/creator/source_importer.gd) and GLB admission have no cancellation argument. [Creator UI](../../../../app/ui/aircraft_creator.gd), `_start_import()`, can leave superseded ordinary jobs running; [ClearView conversion](../../../../app/workshop/creator/clearview/converter.gd) ends with serialization and ordinary re-admission.

**Decision:** bound live jobs and owned memory, including serialization/PNG/native work that cannot immediately yield. The initial automatic pipeline admits one active import plus one coalesced latest pending selection; internal parallelism counts against a frozen worker budget. Cancellation must drain owned work, not merely suppress its result.

### C22

**Background conversion does not remove preview stalls.** [visual_builder.gd](../../../../app/workshop/creator/visual_builder.gd), `_glb_scene()`, calls `GLTFDocument.append_from_buffer()` and `generate_scene()` synchronously. [Creator UI](../../../../app/ui/aircraft_creator.gd), `_sync_preview()`, invokes it during refresh and can retry without bindings after failure.

**Decision:** measure preview creation and editing on the main thread separately from worker conversion. Bound rebuild attempts and retained scenes. If an indivisible call exceeds the frozen target budget, narrow the admitted profile or change the integration seam; an asynchronous progress bar is not proof of responsiveness.

### C23

**Selected visible geometry is not the whole engine allocation.** [glb_preflight.gd](../../../../app/workshop/creator/glb_preflight.gd) applies ceilings to all nodes and unreferenced meshes because the engine builds them, although reported visible bounds/counts describe the selected scene.

**Decision:** normalize the justified selected closure and its shared dependencies, then count all retained resources. A tiny chosen LOD plus an oversized orphan still cannot bypass admission. Removing unused source data is distinct from dropping required parts; both need correspondence and expected inventory.

### C24

**Bindings must survive graph transformation by correspondence.** [visual_parts.gd](../../../../app/workshop/creator/visual_parts.gd) binds node indices; [visual_builder.gd](../../../../app/workshop/creator/visual_builder.gd), `_map_nodes()`, checks graph/engine correspondence. PEER's [name-protection helper](https://github.com/jamesx0416/FlightSim/blob/88af3af16034c7f2d249e8965ef461ee3a139ecf/src/msfs/gltf/collectProtectedNodeNames.ts) illustrates one optimization precaution, but repeated names remain ambiguous.

**Decision:** retain source-file/node/instance identity through normalized nodes and engine instances. Swap indices of same-named siblings in an independent fixture; a stale index or name must never bind the other control. Unprovable correspondence becomes an explicit remapping requirement.

### C25

**ClearView path support is narrower than a general FS resolver.** [clearview/archive.gd](../../../../app/workshop/creator/clearview/archive.gd), `safe_name()` and `_index()`, require ASCII names and reject case collisions.

**Decision:** version the FS filename/encoding/comparison policy; do not inherit a Unicode claim from these primitives. Archive fixtures can contain NFC/NFD spellings on every host; directory fixtures must record whether that filesystem can represent both distinctly. Unsupported representations get precise refusal rather than a borrowed texture.

### C26

**A start check and actual launch can consume different field reads.** [app_root.gd](../../../../app/app_root.gd) checks a loaded field, then passes its path into a candidate; [main.gd](../../../../app/main.gd) loads that path again. [trial.gd](../../../../app/workshop/creator/trial.gd) diagnostics do not constitute the proposed complete environment/backend/energy receipt.

**Decision:** freeze and verify the full check-to-launch context. An injected field or weather change must cause refusal/recheck while preserving the previous flight. This is a concrete boundary test for existing open AC-09/AC-FS-09 work, not a reproduced failure of normal synchronous startup.

## Decisions carried into execution

The source findings change requirements, not just the bibliography: allow safe in-root parent references; select active declarations; identify generated/assembled dependencies; refuse silent partial conversions; distinguish zero/absent/invalid values; keep validator scope explicit; preserve graph and material identities; and bound every stage through preview and launch. The [contingency matrix](../../../plans/flight-simulator-import-milestones.md#contingency-matrix) assigns all 26 cases to original fixtures, expected outcomes, milestones and existing AC-FS owners.

Three independent read-only assignments supplied aircraft-code evidence, tool-code evidence and an OpenRC/milestone challenge. The lead checked the material source claims, retained the automatic-first product goal and integrated the final decisions. Rejected shortcuts include treating helper agreement, a tool's completion status, a repository license badge, a plausible visual or a compiler-accepted draft as completed-feature evidence.
