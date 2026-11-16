# Twenty-four investigations strengthening Flight Simulator import

**Research and access date:** 2026-11-16. **Branch baseline:** `ce1216e644bd9916c66fa6ee885984a6e5bef1b5`. **Status:** additional research and proposed requirements; no importer, converter integration or flight qualification delivered. The [AC-FS plan](../../../../plans/flight-simulator-aircraft-import.md) remains the owner of scope, sequencing and acceptance. This follow-up extends the [original repository audit and compatibility investigation](../README.md).

The work addresses 24 distinct engineering questions. Each investigation records primary evidence, what that evidence does and does not establish, a resulting design decision, and an independently reproducible fixture or acceptance proposal. The purpose is to improve the feature plan using actual aircraft projects and reported conversion failures, while retaining the existing Creator architecture.

## Investigation register

| ID | Question / evidence cases | Consequence for the feature | Owning work |
| --- | --- | --- | --- |
| [R01](visual-and-legacy.md#r01-source-and-compiled-gltf) | Source versus processed glTF; Asobo importer, A32NX, Blender issues | Detect actual encoding and capabilities; record converter versions | AC-FS-03/04 |
| [R02](visual-and-legacy.md#r02-dds-and-material-fidelity) | DDS normals, ORM, alpha and color; FSDeveloper conversion reports | Per-material conversion profiles and asymmetric visual known answers | AC-FS-04/05 |
| [R03](visual-and-legacy.md#r03-lod-selection-and-completeness) | Empty/reduced LODs; MCX and iFly reports | Explicit LOD picker with resource and completeness evidence | AC-FS-03/05 |
| [R04](visual-and-legacy.md#r04-controls-and-animation-semantics) | XML/SimVars, ASK-13, FS9 conversion and PC-7 controls | Trace source semantics; confirm rigid hinges and endpoints | AC-FS-06 |
| [R05](visual-and-legacy.md#r05-modelconverterx-preparation) | ModelConverterX author guidance and restrictions | Optional author-operated legacy preparation with declared losses | AC-FS-12 |
| [R06](visual-and-legacy.md#r06-legacy-mdl-and-air-dialects) | FS2004/FSX/P3D MDL and AIR; Legacy Importer | Version-qualified observations; no universal legacy decoder claim | AC-FS-12 |
| [R07](aircraft-mod-cases.md#r07-c152x-and-simulator-updates) | C152X and JPLogistics update history | Base-plus-overlay identity, simulator-build context and reimport | AC-FS-02/03/10 |
| [R08](aircraft-mod-cases.md#r08-c172-mod-dependencies) | MGouge425 and Bagolu C172 mods | Cross-file dependencies and competing overrides remain visible | AC-FS-03 |
| [R09](aircraft-mod-cases.md#r09-savage-carbon-geometry-and-balance) | Savage Carbon geometry, CG and performance changes | Transform physical landmarks consistently; derive the RC inventory | AC-FS-07 |
| [R10](aircraft-mod-cases.md#r10-as33-me-glider-systems) | AS33 Me ballast, propeller and tow behavior | Identify unsupported systems and visual/physical discrepancies | AC-FS-03/15 |
| [R11](aircraft-mod-cases.md#r11-vl3-visual-and-physical-discrepancies) | VL3 Rotax 915 visual two-blade / physical three-blade configuration | Keep geometry, declarations and new RC installation distinct | AC-FS-03/07 |
| [R12](aircraft-mod-cases.md#r12-a32nx-custom-systems-and-su9) | A32NX SU9 engine-control fix and user reports | Record custom runtime dependencies and build-sensitive behavior | AC-FS-03/15 |
| [R13](physics-and-calibration.md#r13-low-reynolds-tools-and-airfoil-data) | XFOIL, XFLR5, OpenVSP/VSPAERO and UIUC | Scoped low-Re estimates with solver/domain/data provenance | AC-FS-14 |
| [R14](physics-and-calibration.md#r14-propeller-datasets-and-operating-limits) | UIUC measured propellers, APC modeled data and RPM limits | Distinguish measurement from prediction; select actual RC propulsion | AC-FS-07/14 |
| [R15](physics-and-calibration.md#r15-controls-and-response-calibration) | Controller sensitivity and 2020/2024 effectiveness reports | Separate input curves, actuators, travel, visuals and aerodynamic effect | AC-FS-06/07/14 |
| [R16](physics-and-calibration.md#r16-mass-balance-and-contact-semantics) | DA40NG, SubSonex and conditional contact units | Per-field units and mass roles; contacts remain separately gated | AC-FS-03/07/15 |
| [R17](physics-and-calibration.md#r17-telemetry-and-independent-validation) | FSTelemetry, Flight Recorder, JSBSim and SimConnect scope | Tool-neutral measurement envelope and independent RC validation | AC-FS-09/14 |
| [R18](physics-and-calibration.md#r18-conditional-flight-model-fields) | Normalization selectors and conditionally active legacy fields | Role-aware semantics; never mark a whole field inactive from its age | AC-FS-02/03/07 |
| [R19](packages-and-tools.md#r19-native-2024-composition) | Native 2024 merge stages, attachments and Fenix authoring discussion | Dedicated composition evaluator with provenance | AC-FS-13 |
| [R20](packages-and-tools.md#r20-livery-and-variant-dependencies) | Legacy liveries in 2024, A2A registration and base-container reports | Resolve variant/model/paint closure and declare dynamic-text omissions | AC-FS-03/05/13 |
| [R21](packages-and-tools.md#r21-interchange-and-validation-tools) | Khronos Validator and Assimp format scope | Independent standards diagnostics plus Creator admission | AC-FS-04 |
| [R22](packages-and-tools.md#r22-optimization-and-moving-parts) | gltfpack and glTF Transform maintainer discussions | Controlled transformations that preserve motion identities and paint | AC-FS-04/06 |
| [R23](packages-and-tools.md#r23-package-updates-and-reimport) | VFS/override documentation, B707 patch and update reports | Version-qualified overlay graph and three-way reimport | AC-FS-02/03/10/13 |
| [R24](packages-and-tools.md#r24-regression-corpus-and-asset-rights) | Khronos generated/sample assets and test-model licenses | Original fixtures first; per-stage results and per-asset rights | AC-FS-01/11 |

The [tooling and fixture backlog](tooling-and-fixtures.md) makes the proposed evaluation sequence concrete. All 24 investigations are completed as research; their implementation and experimental acceptance checks are still open.

## What changes in the plan

### Resolve the actual aircraft configuration

An enhancement mod, livery or partial package can depend on a separately installed aircraft and on other mods. C152X, the C172 improvements and the VL3 project provide concrete cases. A source receipt therefore needs the selected base, ordered overlays, variant, livery, exterior LOD, declared simulator build and resolution-policy version. Effective values must retain their overridden declarations. Unknown precedence is an unresolved result, not permission to take the last file enumerated. [R07/R08/R11](aircraft-mod-cases.md), [R19/R20/R23](packages-and-tools.md)

The native-2024 path needs its own later composition work: menu/flight merge stages, attachment indexing, aliases, parameter substitution and transforms. A legacy aircraft running in 2024 remains a different source form. Documentation and support advice about protected overrides have changed, so historical guidance cannot define one timeless VFS rule. [R19/R23](packages-and-tools.md)

### Keep physical meaning with each field

The mapping registry must track a field's simulator build, mode, conditional flags and role. One value can influence different source subsystems differently: `pitch_moment_delta_elevator` retains sign/autopilot significance even when the modern aerodynamic model does not use its magnitude in the legacy way. The same contact tuple position can mean a ratio or feet depending on `set_max_compression`. These are concrete counterexamples to blanket legacy-field filtering and uniform column conversion. [R16/R18](physics-and-calibration.md)

Source comments, mesh appearance, CFG values and runtime behavior can disagree. The VL3 README explicitly documents a visual/physical blade-count difference; AS33 Me reports separate visual propeller and simulated shaft behavior. Record discrepancies without guessing which representation is the authoritative real aircraft. The target RC equipment selection remains an explicit new installation. [R10/R11](aircraft-mod-cases.md)

### Normalize visuals while preserving their meaning

DDS decoding needs a separate material interpretation, including channels, color spaces, UVs, normal convention and alpha. A low-detail LOD can meet resource limits while losing an expected control or paint. Optimizers may merge parts or discard names needed for subsequent articulation. Require source-to-output correspondence and independently declared expected inventories where a loss must be detected; an arbitrary output mesh cannot prove what its original contained. [R02/R03/R04](visual-and-legacy.md), [R22](packages-and-tools.md)

Creator already supports mesh-bearing nodes and proper-subset groups, with restrictions on origins, local axes and overlapping bindings. Reuse that capability. Skin, morph and animation input still requires explicit supported normalization before ordinary GLB admission. The prepared-GLB route remains the first useful release. [Current parts](../../../../../app/workshop/creator/visual_parts.gd), [preflight](../../../../../app/workshop/creator/glb_preflight.gd), [R01/R04/R05](visual-and-legacy.md)

### Treat calibration as an evidence workflow

XFOIL/XFLR5/VSPAERO can contribute bounded estimates, not automatic whole-aircraft truth. UIUC measurements and APC predictions are different evidence kinds. Motor/propeller choice, operating point, actual component balance and RC control timing cannot be recovered by shrinking a full-scale configuration. Proposed measurements must carry units, frames, operating conditions, timing uncertainty and source rights; independent RC evidence remains the basis for a real-handling claim. [R13–R18](physics-and-calibration.md), [conversion specification](../conversion-and-scaling.md)

### Make updates reviewable and repeatable

Compare old captured source, new captured source and the current authored target. Preserve manual edits, surface conflicts, invalidate renamed hinge bindings and create a new conversion revision when tools or source change. Numeric equivalence does not guarantee identical physical bytes if emitted provenance changes. Keep old immutable aircraft versions available. [R23](packages-and-tools.md#r23-package-updates-and-reimport)

## Evidence method and limits

Evidence comes from official Microsoft/Prepar3D documentation, maintainer repositories and issues, aircraft authors' releases and first-person posts on Microsoft Flight Simulator Community, Microsoft DevSupport, FSDeveloper and author-controlled download listings. Original source code and data providers are used for technical tool and measurement claims. The individual investigations identify dates, versions, retrieved text and unresolved questions.

Repository source pins and specific historical releases are retained where inspected; moving `main`/`master` pages and forum discussions are labeled as access-date observations. The [tool revision record](packages-and-tools.md#tool-revision-record) records six inspected repository commits, not installed dependency versions. A closed issue is not automatically a merged fix; an author's claimed fix is not an independently reproduced result. Conflicting reports remain conflicting.

Some DevSupport pages were available only through indexed excerpts when direct access returned an error; those cases are marked locally and are not used as sole authority for a documented format rule. Image-based guide procedures were not reconstructed. No forum account was contacted, no executable mod or aircraft binary was run, and no converter, renderer, simulator telemetry or flight benchmark was executed.

This work inspected documentation, selected repository text, configuration and glTF JSON. Public readability and freeware labels do not establish permission to redistribute models, textures or datasets. Each candidate retains its own evidence gap; no restricted aircraft, SDK sample or third-party executable is added to the branch. The proposed corpus recreates failure mechanisms using independently authored small assets.

## Decisions still requiring experiments

The research does not close the following implementation questions:

- Which exact source/material profile can be normalized faithfully within Creator's current byte, mesh, image and memory bounds?
- Which independently authorized real conventional aircraft will complement the original synthetic trainer?
- Which converter release and recipe preserve required geometry, paint and rigid bindings on every advertised desktop target?
- What is the smallest shared provenance and immutable dependency extension that works for both ClearView and Flight Simulator?
- Which supported RC domain passes AC-12 or a separately preregistered numerical campaign, followed by the existing lifecycle, Home and exported-platform gates?

These questions are assigned to AC-FS-01…15 in the [updated plan](../../../../plans/flight-simulator-aircraft-import.md#7-work-packages). The research makes the experiments more specific; it does not substitute for them.

## Verification of this documentation change

The final review checked the 24 unique investigation IDs and their 24 corresponding fixture proposals, source attribution and confidence boundaries, current Creator group-binding/preflight behavior, and first-release sequencing. Three independent cross-reviews resulted in corrections to group support, static-pose admission, conditional source semantics, unestablished redistribution rights and numerical-gate wording. A narrow matching correction was made in the ClearView plan.

Focused repository checks passed for 164 new or affected local document links and anchors, the changed-file whitespace check, and the advance-ratio, pitch-speed, CG, unit-conversion, image-memory and coefficient-normalization examples. The six new research documents contain 116 distinct external reference URLs; this count does not claim every URL was directly accessible or every reported bug was reproduced. The change contains only Markdown documentation. No importer tests, conversion/render campaign, simulator benchmark or flight qualification was run.
