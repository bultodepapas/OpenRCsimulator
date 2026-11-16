# R19–R24: package composition, tools and regression evidence

**Product-direction update:** the later [automatic wizard contract](../../../../plans/flight-simulator-import-wizard.md) owns current delivery acceptance: in-app conversion, questions only for unresolved data and editable results. Earlier preparation/manual-step recommendations in this dated evidence are optional development/recovery proposals; underlying format and physics findings remain unchanged.

**Investigated:** 2026-11-16. **Baseline:** OpenRC `ce1216e644bd9916c66fa6ee885984a6e5bef1b5`. These are six distinct investigations within the [24-question follow-up](README.md). Official documentation and repository text establish documented behavior; community posts establish reported cases. No converter, third-party binary model or simulator was run. Proposed changes are owned by the [AC-FS implementation plan](../../../../plans/flight-simulator-aircraft-import.md).

## R19: Native 2024 composition

**Question.** What must the later native-2024 adapter preserve beyond ordinary file discovery and last-value-wins parsing?

**Evidence.** Microsoft's modular-merging reference describes distinct menu-time and flight-time composition. Common data, ordered attachments and the chosen preset participate in configuration resolution; model assembly and further XML/FLT composition also matter. Indexed parameters can be renumbered, manual merge can use `AttachmentRebind`, and dynamic parameters and `[uid]` substitution depend on attachment identity. This is richer than concatenating matching filenames. The attachment reference additionally defines alternate path/GUID selectors, aliases and transforms. The editor exposes an override hierarchy so authors can inspect where effective values came from. [R19-S1–S3]

A developer seeking an external antenna for the Fenix A321 received a DevSupport suggestion to define a new preset referencing both the existing attachments and the additional object. Another participant emphasized aircraft-specific hierarchy and naming. That discussion supports using the selected preset and actual attachment graph as source identity; it does not prove that an arbitrary Fenix export is available or licensed for OpenRC. The DevSupport page could not be opened directly, so this case is limited to the indexed posts retrieved by search. [R19-S4]

**Decision.** AC-FS-13 needs a versioned merge evaluator, not merely a recursive directory reader. Its report should show effective value, overridden declarations, source order, selected preset/livery and unresolved references. Preserve source-node identity through model composition before normalization. Unsupported rebind/dynamic-expression forms keep the affected field unresolved. Do not run behavior expressions to make a dependency appear complete.

**Acceptance fixture.** Author a small common source plus two attachments and two presets. Give the attachments the same indexed key, different aliases, a dynamic dimension, a manual rebind and a nonidentity attachment transform. Assert the selected preset's effective values and composed landmarks against independent hand-authored answers. Reordering attachments must have the documented result; duplicate aliases and unresolved dynamic names must produce actionable failures. The first 2020 path remains independent of this later work.

**Status.** Composition semantics documented; the community extension is a reported authoring case; OpenRC evaluator unimplemented.

| Source | Identity / relevance |
| --- | --- |
| R19-S1 — [Modular SimObject Merging](https://docs.flightsimulator.com/msfs2024/retail/content-configuration/modular-simobjects/modular-simobject-merging/) | Microsoft retail documentation, accessed 2026-11-16; merge stages, indexing and substitutions |
| R19-S2 — [attached_objects.cfg](https://docs.flightsimulator.com/msfs2024/retail/content-configuration/cfg-files/attached_objects.cfg/) | Microsoft retail reference; selectors, aliases, transforms and model merging |
| R19-S3 — [SimObject Editor: parameter hierarchy](https://docs.flightsimulator.com/msfs2024/retail/devmode/editors/simobject-editor/the-simobject-editor/) | Microsoft's source-provenance UI; useful report precedent, not an SDK dependency |
| R19-S4 — [Understanding the MSFS 2024 Attachment System for the Fenix A321](https://devsupport.flightsimulator.com/t/understanding-the-msfs-2024-attachment-system-for-the-fenix-a321/18372) | TimboRose / FlyingRaccoon / EzRyder, 2026-08-21; indexed discussion inspected, direct open returned 502 |

## R20: Livery and variant dependencies

**Question.** Which source selections and dependencies make a livery or variant an independently resolvable result?

**Evidence.** Microsoft's static-livery and aircraft references describe inherited aircraft/panel configuration and base-container references. Model and texture selection therefore cannot be reduced to finding a PNG or DDS with a familiar name. The source family must also be known: the community conversion guide deliberately scopes itself to legacy 2020 aircraft running in 2024. [R20-S1–S3]

That guide's discussion records an A2A Comanche livery whose dynamic registration disappeared, and later disagreement about behavior after a simulator patch. The guide contains much of its procedure in images; those image instructions were not independently reconstructed in this investigation. Another thread proposes a different `base_container` path but explicitly calls it a hypothesis pending testing. Retain that as a troubleshooting lead, not a universal path-repair rule. [R20-S3–S4]

**Decision.** Source selection must distinguish an aircraft, a variant, a texture-only livery, a model-changing livery and an enhancement patch. Resolve model/texture fallbacks only inside the declared selected roots. Record the exact base and any panel/model dependencies. A static exterior preview may omit dynamic registration with a visible limitation; it must not execute HTML/JavaScript or import cockpit systems to reproduce a tail number. Do not claim that an observed source title or thumbnail identifies the actual geometry.

**Acceptance fixture.** Two liveries share the same model and use identical relative texture names with different bytes; import both without cross-contamination. Add a third livery with a model override and a fourth with a missing base. Confirm independent paint identity, model-override detection, deterministic fallback order and unavailable dependencies. Dynamic registration receives an explicit omission/bake decision and never changes physical quantities. Preserve missing versus intentionally transparent paint.

**Status.** Inheritance documented; community symptoms are historical first-person reports, not verified current bugs. Livery fidelity remains a separate outcome from geometry admission and flight.

| Source | Identity / relevance |
| --- | --- |
| R20-S1 — [Static Liveries](https://docs.flightsimulator.com/msfs2024/retail/models-and-textures/modeling/aircraft/airframe/liveries/static-liveries/) | Microsoft; inherited panel behavior and livery structure |
| R20-S2 — [aircraft.cfg](https://docs.flightsimulator.com/msfs2024/retail/content-configuration/cfg-files/aircraft.cfg/) | Microsoft; base-container and aircraft-selection semantics |
| R20-S3 — [Unofficial Guide to Conversion of Liveries for MSFS 2024](https://forums.flightsimulator.com/t/unofficial-guide-to-conversion-of-liveries-for-msfs-2024-2020-legacy-aircraft-only/677083) | BilingualHarp7, opened 2024-11-28; December reports/updates; legacy-aircraft scope and dynamic-registration example |
| R20-S4 — [Most liveries don't work in 2024, post 93](https://forums.flightsimulator.com/t/most-liveries-dont-work-in-2024/666372/93) | Bananimal6685, 2024-12-08; explicitly tentative VFS-path theory, not an adopted fix |

## R21: Interchange and validation tools

**Question.** Can an established tool reduce new parser/converter work without weakening Creator admission?

**Evidence.** Khronos glTF Validator checks structure, references and supported resource semantics and emits machine-readable issues/statistics. Its documented extension coverage is finite. A successful report therefore establishes neither complete MSFS-extension interpretation nor Creator compatibility. The inspected Apache-2.0 repository provides a suitable candidate for an offline second opinion, with exact version and resource policy recorded. [R21-S1]

Assimp can provide an independent geometry interchange comparison. Its documentation identifies `.mdl` support as Quake/3D GameStudio families; the extension name is not evidence of Microsoft FSX MDL support. Its project license also explicitly separates non-BSD test models from the library license. This rules out a shortcut that chooses Assimp for Flight Simulator solely because a format list says MDL. [R21-S2–S3]

The existing OpenRC reader requires an empty `extensionsRequired` list and a small explicit `extensionsUsed` set. It also excludes general animation/skins and non-PNG textures. That remains the product boundary even if another importer accepts more. [R21-S4]

**Decision.** Add an offline validation lane: captured source inventory → bounded conversion → Khronos structural report → unchanged Creator preflight → rendered/semantic comparison. Distinguish four verdicts: standard-glTF structural validity, target-subset admission, conversion fidelity and physical availability. A standards-valid skin can correctly be unsupported by Creator; a standards-invalid accessor is a different diagnosis. External tools run with local captured resources and bounded process time/memory/output; resource callbacks must not fetch URLs or arbitrary host files. A tool warning that a vendor extension was not validated stays visible.

**Acceptance fixture.** Include one valid standard file outside Creator's subset, one malformed accessor, one unsupported required vendor extension and one admitted simple GLB. Require the report to preserve the different reasons. Compare an asymmetric authorized source through the selected author workflow and independent interchange reader; check vertices, world-space bounds, material assignment and rigid pivots. Agreement between two tools is supporting evidence, not a replacement for known answers.

**Status.** Documentation/license/source inspection only. No tool installed, integrated, benchmarked or selected as a runtime dependency.

| Source | Identity / relevance |
| --- | --- |
| R21-S1 — [glTF Validator](https://github.com/KhronosGroup/glTF-Validator/tree/602c54043ba66856b2e68c40fdf2bced975cdb8a) | Pinned 2026-11-16; README and LICENSE inspected; Apache-2.0; JSON reports and bounded coverage |
| R21-S2 — [Assimp introduction](https://github.com/assimp/assimp-docs/blob/master/source/about/introduction.rst) | Project documentation; MDL family and interchange scope; accessed 2026-11-16 |
| R21-S3 — [Assimp LICENSE](https://github.com/assimp/assimp/blob/6bf4b3a4f0d1750c4a4cdc5a3dd0fef4ec0a666d/LICENSE) | BSD-style library terms, dependency terms and explicit non-BSD model exception |
| R21-S4 — [Creator GLB preflight](../../../../../app/workshop/creator/glb_preflight.gd) | OpenRC baseline; narrow supported subset and extension rules |

## R22: Optimization and moving parts

**Question.** Which optimizations can silently destroy node identity, later control binding or material behavior?

**Evidence.** `gltfpack` documents mesh merging, quantization, animation resampling and hierarchy pruning. Its options include named-node/material preservation, but output may require extensions unsupported by Creator. The maintainer's answer to discussion 631 explains a reported UV/renaming issue and the role of texture transforms and named-node preservation. [R22-S1–S2]

The glTF Transform maintainer explains in discussion 1520 that the convenience `optimize` command can flatten hierarchy and merge meshes, conflicting with animation applied afterward. The same reply warns that same-named image files written into one output directory can overwrite each other. Its inspected `dedup` implementation defaults `keepUniqueNames` to false. These are strong reasons to choose individually reviewed transforms instead of an opaque optimize-everything preset. [R22-S3–S4]

**Decision.** Retain the exact captured original plus a bounded, independently inspectable pre-optimization reference where feasible; use an already-admitted reference for controlled optimizer fixtures and evaluate optimization only on a copy. Record node/part correspondence before and after each stage. Never merge surfaces assigned different motion. Preservation flags are necessary candidates, not sufficient proof: test rest geometry, full deflections, propeller pivot/direction, UVs, transparency and material identity. Compressed/quantized/WebP/KTX2 output must be decoded or otherwise normalized to the existing GLB/PNG subset; extension names must not be deleted to force admission. Require final normalized output to pass ordinary Creator preflight; a large or unsupported original never enters the runtime importer directly.

Separate compressed size from decoded cost. One 4096×4096 RGBA8 image is 64 MiB before mipmaps or temporary buffers, by dimensional arithmetic. Measure aggregate decoded memory, converter workspace, main-thread stalls, cancellation and actual draw/frame cost. Optimizing the visual must leave the authored physical geometry, inventory and coefficients unchanged. The first player path need not include any optimizer.

**Acceptance fixture.** Use mirrored ailerons, an offset elevator hinge, two same-shaped but independently moving meshes, two same-named textures with different contents, transparent glazing and explicit landmarks. Compare reference and each selected transform. Refuse a conversion profile that breaks node identity or target-subset admission even if it produces a much smaller file.

**Status.** Author-documented transformations and reported user cases; no optimization benefit measured on OpenRC.

| Source | Identity / relevance |
| --- | --- |
| R22-S1 — [gltfpack documentation](https://github.com/zeux/meshoptimizer/blob/f0a684f11ead064e176775c9b796f82a55910e92/gltf/README.md) | Pinned 2026-11-16; MIT license inspected separately; quantization, pruning and preservation options |
| R22-S2 — [meshoptimizer discussion 631](https://github.com/zeux/meshoptimizer/discussions/631) | Junisek / maintainer zeux, 2023-11-06–08; UV transforms and node names |
| R22-S3 — [glTF Transform discussion 1520](https://github.com/donmccurdy/glTF-Transform/discussions/1520) | f1-outsourcing / maintainer donmccurdy, 2024-10-07; external-animation and texture-collision case |
| R22-S4 — [glTF Transform dedup implementation](https://github.com/donmccurdy/glTF-Transform/blob/8e2a94a2616d293c4b503d0fb6a4b42e6ec7c62f/packages/functions/src/dedup.ts) | Pinned source; `keepUniqueNames` default; MIT license inspected |

## R23: Package updates and reimport

**Question.** Can an imported configuration be reproduced when two mods override the same file or an update changes the base aircraft?

**Evidence.** Microsoft's VFS reference describes package-order hints, tie-breaking and later-package priority. The Project Inspector describes explicitly declared overrides for protected global files. A 2025 developer report about a B707 behavior patch contains a staff explanation of changed override requirements and a discussion of differing package-order hints. It is an observed support exchange, not a universal workaround. [R23-S1–S3]

There is a material documentation/version caveat: current general VFS/Inspector pages describe broad `ModelBehaviorDefs` restrictions, while SDK release notes record a later relaxation for some subfolders. A policy evaluator must identify the source simulator/documentation version and retain uncertainty; it cannot flatten historical advice into one permanent rule. This investigation did not establish the effective runtime behavior for every build. [R23-S4]

The livery guide also records a user workaround that edits the base package, followed by a warning that updates may overwrite the changes. This motivates a read-only source import and explicit new revisions inside OpenRC, rather than modifying the user's simulator installation. [R20-S3]

**Decision.** The importer should resolve only explicitly selected package roots and retain the ordered package/override graph. A directory listing or a lone `flight_model.cfg` is not evidence of the effective installed aircraft. Report competing declarations and a version-qualified policy; unsupported or ambiguous global overrides remain unresolved and unexecuted. Keep source installation bytes untouched.

Reimport compares the old source, newly captured source and current authored RC values. Preserve user overrides; a source change and a user edit to the same adopted field require an explicit conflict decision. Removed attachments or renamed nodes invalidate dependent bindings until remapped. A compiler/tool update creates a new conversion revision. Distinguish numeric parameter equivalence from exact v2 byte identity: a changed emitted provenance string can change record bytes even when the numeric value is the same.

**Acceptance fixture.** Two patches target the same CFG/XML path, with and without declared order; update the base and one patch independently. Confirm deterministic selection where documented, uncertainty where not, visible conflicts, retained manual mass/CG, invalidated renamed-node bindings and continued access to the old immutable aircraft version.

**Status.** Versioned resolution and three-way reimport are design consequences; no installed VFS or user aircraft was modified.

| Source | Identity / relevance |
| --- | --- |
| R23-S1 — [VFS Information](https://docs.flightsimulator.com/msfs2024/retail/devmode/menus/tools_info/virtual-file-system/virtual-file-system-information/) | Microsoft; package ordering and override model; current page accessed 2026-11-16 |
| R23-S2 — [Project Inspector](https://docs.flightsimulator.com/msfs2024/retail/devmode/editors/project-editor/the-project-inspector/) | Microsoft; explicit global override declarations |
| R23-S3 — [Simple FS2020 aircraft mod not working after SU1 or SU2](https://devsupport.flightsimulator.com/t/simple-fs2020-aircraft-mod-not-working-anymore-with-fs2024-after-su1-or-su2/14790) | FawnPanda67166 / FlyingRaccoon, July 2025; indexed discussion inspected; direct open returned 502 |
| R23-S4 — [SDK release notes](https://docs.flightsimulator.com/msfs2024/retail/introduction/sdk-release-notes/) | Microsoft; inspected entry relaxes some ModelBehaviorDefs override restrictions; not a complete version-by-version qualification |

## R24: Regression corpus and asset rights

**Question.** Which fixtures can establish parser and converter behavior without copying a restricted aircraft or confusing broad glTF support with the Creator subset?

**Evidence.** Khronos glTF Asset Generator is an MIT-licensed C# project with positive and negative asset cases, including transforms, materials, interleaving and malformed mesh structures. It offers independent specification-oriented examples, but many legal glTF features intentionally exceed the Creator subset. Its exact inspected revision is recorded below. [R24-S1]

Khronos glTF Sample Assets uses per-asset credit/license records; its README specifically directs readers to each model's own documentation. It is therefore an additional source of selected reference assets, not a blanket-license aircraft library. Assimp's library license similarly carves out third-party test models. Tool license and test-content license must remain separate. [R24-S2–S3]

**Decision.** Build three corpus layers: original tiny synthetic cases; selected independently licensed standards fixtures; and optional authorized real-aircraft cases identified by source revision and component permissions. Start with an original conventional trainer whose geometry, pivots and physical values have independent known answers. Recreate the *failure mechanism* from community threads in small original fixtures instead of committing the reported aircraft. Standards fixtures test admission; they do not establish MSFS material fidelity or flight realism.

Every corpus row should identify source form/revision, tool recipe, required capabilities, exact expected outcome at each stage, and artifact rights. Preserve meaningful negative outcomes: malformed, valid-but-unsupported, incomplete closure, ambiguous configuration, static-only visual, or physics-unavailable. Do not convert a refused case into a passing test by stripping required extensions or silently substituting another aircraft. A compatibility statement names the exact source and achieved stage, not merely the simulator version.

**Acceptance fixture.** At minimum: embedded PNG GLB; malformed accessor; unsupported skin; negative scale; required DDS extension; same-named textures with different bytes; split/embedded CFG; missing base; attachment reindex/rebind; per-file and inter-file source races; renamed hinge; source/manual conflict; stale converter version; and saved definition paired with unrelated physics. Add low-Re/propulsion and flight cases through their owning campaigns, preserving the failed AC-12 evidence.

**Status.** Corpus design and source/license inspection complete; fixture generation, tool qualification and actual importer tests remain open under AC-FS-01/04/11.

| Source | Identity / relevance |
| --- | --- |
| R24-S1 — [glTF Asset Generator](https://github.com/KhronosGroup/glTF-Asset-Generator/tree/3d99767e9a67fbfe109f0d298c1e8d909bcac9db) | README and MIT LICENSE inspected at pinned revision; generated positive/negative specification cases |
| R24-S2 — [glTF Sample Assets README](https://github.com/KhronosGroup/glTF-Sample-Assets/blob/8f492390ddc7a2ae221a1369ef560589cf8c70fb/README.md) | Per-model license/credit scope; collection license is not a universal asset license |
| R24-S3 — [Assimp test-model exception](https://github.com/assimp/assimp/blob/6bf4b3a4f0d1750c4a4cdc5a3dd0fef4ec0a666d/LICENSE) | The library's terms do not cover all test/models-nonbsd assets |

## Tool revision record

These are inspected source revisions for evaluation, **not installed versions or production dependency pins**. Adoption requires a chosen release/build, dependency and license review, exact recipe and measured bounded execution. No third-party source or binary was vendored in this research branch.

| Project | Inspected commit | License observation |
| --- | --- | --- |
| Khronos glTF Validator | `602c54043ba66856b2e68c40fdf2bced975cdb8a` | Apache-2.0 LICENSE; retain NOTICES/dependency review |
| glTF Transform | `8e2a94a2616d293c4b503d0fb6a4b42e6ec7c62f` | MIT LICENSE.md; CLI dependencies reviewed separately at adoption |
| meshoptimizer / gltfpack | `f0a684f11ead064e176775c9b796f82a55910e92` | MIT LICENSE.md; optional codec dependencies separate |
| glTF Asset Generator | `3d99767e9a67fbfe109f0d298c1e8d909bcac9db` | MIT LICENSE; selected generated assets still recorded individually |
| glTF Sample Assets | `8f492390ddc7a2ae221a1369ef560589cf8c70fb` | Per-asset README/license/credits; no blanket permissive claim |
| Assimp | `6bf4b3a4f0d1750c4a4cdc5a3dd0fef4ec0a666d` | BSD-style library plus dependency terms and non-BSD model exception |
