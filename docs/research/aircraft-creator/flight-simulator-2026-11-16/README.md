# Flight Simulator import investigation

**Research date:** 2026-11-16. **OpenRC source:** `6dfe1b9179af408f6b765b91ca164e626570db9f`. **Status:** research and proposed design, not implemented compatibility. The [feature plan](../../../plans/flight-simulator-aircraft-import.md) owns AC-FS-00…15. This investigation answers which aircraft sources are useful, how to reuse existing import paths, what scaling can mean, and what evidence is needed before calling a conversion flyable.

| Document | Purpose |
| --- | --- |
| [Implementation plan](../../../plans/flight-simulator-aircraft-import.md) | Product flow, ownership, architecture, steps, dependencies and release gates |
| This investigation | Current import audit, version matrix, findings, alternatives and evidence limits |
| [Automatic import wizard](../../../plans/flight-simulator-import-wizard.md) | Clarified product goal: in-app conversion, conditional questions, editable defaults and ready-state acceptance |
| [Conversion and scaling](conversion-and-scaling.md) | Per-field mapping, units, reference frames, inertia, aerodynamic semantics and RC scaling |
| [Sources and examples](sources-and-examples.md) | Primary-source register, inspected aircraft and conversion-tool assessment |
| [24 additional investigations](follow-up-24-investigations/README.md) | Specialist forums, GitHub issues, six aircraft-mod case studies, conditional physics, composition, tools and regressions |
| [Tool and fixture backlog](follow-up-24-investigations/tooling-and-fixtures.md) | Optional tool decisions, exact experiment boundaries and 24 proposed failure-mechanism fixtures |

## Findings that determine the design

1. **Build on Aircraft Creator.** STL/GLB admission, ClearView normalization, explicit placement, physical authoring, trial and immutable storage already provide the relevant seams. A separate Flight Simulator aircraft loader or parallel catalog would duplicate them.
2. **The completed product must convert a supported source automatically inside OpenRC.** Readable data plus a prepared GLB remains an engineering/recovery path; the owner clarified that the default release needs in-app normalization and a conditional wizard. A bounded spike chooses the actual automatic source profile. Built Community glTF is not guaranteed source glTF; Asobo's own authoring importer excludes package-built input. [F08–F09](sources-and-examples.md#format-and-package-sources)
3. **A source package has several independently convertible parts.** Geometry, paint, moving-part semantics, physical configuration and executable systems must be assessed separately. A downloaded livery or stock-aircraft enhancement can omit the aircraft itself. [F05–F07, F25–F26](sources-and-examples.md#format-and-package-sources)
4. **Flight characteristics need an explicit target model.** Modern/legacy MSFS fields do not share all meanings, many modern effects come from distributed surfaces, and legacy AIR contains information absent from CFG. Automatic RC construction must use an explicit attributed target profile and supported conversion rules; matching coefficient names alone is insufficient. [Mapping evidence](conversion-and-scaling.md#field-mapping-and-dispositions)
5. **RC size does not determine RC mass, power or handling.** Similarity laws are useful estimates under stated assumptions; Reynolds mismatch and actual component layout require separate treatment. [Scaling derivation](conversion-and-scaling.md#scaling-laws)
6. **2024 needs a separate native-source adapter.** Preset/attachment composition and dynamic parameters add a configuration-resolution problem. StreamedPackages is not necessarily a complete local aircraft. [F10–F14](sources-and-examples.md#format-and-package-sources)
7. **Asset rights affect the fixture strategy.** Public source code, freeware downloads and purchased aircraft do not establish cross-simulator redistribution rights. Inspected realistic projects have mixed asset terms. Start with project-authored fixtures and separately authorized real examples. [Rights and fixtures](sources-and-examples.md#rights-and-fixture-policy)
8. **Existing flight qualification remains a dependency.** Creator's AC-12 campaign did not pass its registered gate; Home, portable closure and exported-platform work remain open. Format detection and preview can proceed independently. [Current Creator plan](../../../plans/aircraft-creator.md#6-gates)

## Follow-up findings integrated into the plan

The [24 additional investigations](follow-up-24-investigations/README.md) extend this original audit at branch baseline `ce1216e644bd9916c66fa6ee885984a6e5bef1b5`. They add version-qualified base/overlay resolution, field-specific sign/magnitude/subsystem semantics, explicit model/physics discrepancies, material and LOD completeness evidence, motion-preserving optimization, three-way reimport and a concrete tool/corpus backlog. The six aircraft-mod studies cover C152X/JPLogistics, the MGouge425 and Bagolu C172 modifications, Savage Carbon, AS33 Me, VL3 Rotax 915 and A32NX.

The owner subsequently clarified that the first completed feature must automatically convert a supported source in-app, ask only unresolved questions and leave an editable, ready RC aircraft. The [wizard contract](../../../plans/flight-simulator-import-wizard.md) replaces the earlier prepared-GLB-first product assumption while retaining that engineering/recovery route. Existing flight, Home and packaged-platform gates still apply.

## Repository audit

The root [AGENTS guidance](../../../../AGENTS.md), [consolidated audit ledger](../../../../external%20Audits/CONSOLIDATED-AUDITS.md), [architecture](../../../STACK.md), [aircraft contract](../../../AIRCRAFT_CONTRACT.md), [ownership registry](../../../README.md#tracks-plans-and-step-ids), Creator and ClearView plans were reviewed before proposing new work. Existing audit findings are retained as dependencies, not reopened as newly discovered defects.

The tree was inspected at the exact baseline above, including the ClearView source-observation changes already present there. Runtime source and accepted data determine current behavior; older plans and prior conversations are not used to claim implementation.

### Existing import and editing paths

| Path | Observed implementation | Limits and reuse decision |
| --- | --- | --- |
| Binary/ASCII STL | `creator/stl_reader.gd` and content-based `source_importer.gd` | Static shape; no texture, articulation or flight characteristics. Reuse bounded admission and orientation/size workflow |
| Self-contained GLB 2.0 | `glb_preflight.gd`, `png_check.gd`, `visual_builder.gd` | Rigid subset, embedded PNG, strict graph/accessor/material checks. Reuse as normalized visual boundary, not direct MSFS-format support |
| GLB moving parts | `visual_parts.gd` and Creator parts UI | User-confirmed controls/propeller; supported local axes/pivots/role counts. Source animation requires conversion or explicit refusal |
| ClearView ZIP/AC3Db | `creator/clearview/` and wizard integration | Experimental bounded ZIP, v5/v6 parameters, visual conversion, selected images and re-admission. Reuse proven primitives after shared-owner/version review |
| ClearView observations | `clearview/observations.gd`, `aircraft_creator_source_report.gd` | Source declarations are read-only metadata; hashes do not prove source authenticity, archive membership or physical truth. Physical-field adoption is not implemented |
| Stock `.orskin` | Stock model-family/revision-bound paint import | Appearance only. It does not import geometry or physics; the Creator skin branch remains AC-16 work |
| Workshop variant bundle | `workshop/bundle.gd`, registered aircraft/dependency recipes | Data-only variant of a known base. It is not a portable arbitrary Creator aircraft package |
| Creator `.orcaircraft` | AC-19 planned format/work | Not implemented as a completed portable source/configuration closure |
| Creator Home selection | AC-18 planned integration | Existing trial and local save slices do not close Home/restart qualification |
| Stock Workshop scaling | `workshop/compiler.gd` and capability classification | Estimated size/weight/virtual-power transforms apply to the admitted prescribed-RPM family; finite-energy/other-law imports cannot inherit this support |
| Flight Simulator intake | No adapter found in the inspected Creator, Workshop, UI, tests and owning plans | New AC-FS subtrack; no present compatibility claim |

Sources: [Creator guide](../../../AIRCRAFT-WORKSHOP.md#aircraft-creator-experimental), [Creator plan](../../../plans/aircraft-creator.md), [ClearView plan](../../../plans/clearview-aircraft-import.md), [skins guide](../../../AIRCRAFT-SKINS.md), and the source map below.

### Source map and concrete constraints

All paths are relative to the repository root and observations apply to the pinned baseline.

| Source | Relevant contract |
| --- | --- |
| [`source_importer.gd`](../../../../app/workshop/creator/source_importer.gd) | Captures bounded bytes once, hashes them, detects supported content and refuses flat/empty bounds; import is not physics admission |
| [`limits.gd`](../../../../app/workshop/creator/limits.gd) | 32 MiB model, 200,000 triangles, 600,000 expanded vertices; 512 nodes, 128 meshes, 256 primitives, 32 materials, 16 images; 4,096-pixel side and 16,777,216 aggregate image pixels; 4 GiB Store quota |
| [`glb_preflight.gd`](../../../../app/workshop/creator/glb_preflight.gd) | Self-contained BIN/PNG; rejects animations/skins, external URI assets, unknown required extensions and unsupported transforms. Generic source admission must remain strict |
| [`placement.gd`](../../../../app/workshop/creator/placement.gd) | `scale × rotation × (point − datum)`, into structural `[aft,right,up]`; positive uniform scale and explicit nose/up choices |
| [`visual_parts.gd`](../../../../app/workshop/creator/visual_parts.gd) | Restricted rigid node bindings and propeller; imported arbitrary groups/hinges are not automatically representable |
| [`clearview/archive.gd`](../../../../app/workshop/creator/clearview/archive.gd) | ZIP32 subset, bounded stored/raw-DEFLATE, no filesystem extraction; 64 MiB archive, 256 MiB aggregate advertised expansion, 4,096 entries and exact member checks |
| [`clearview/package.gd`](../../../../app/workshop/creator/clearview/package.gd), [`converter.gd`](../../../../app/workshop/creator/clearview/converter.gd) | Model-root inventory, supported scene/image normalization, converted GLB re-admitted through Creator |
| [`clearview/motion.gd`](../../../../app/workshop/creator/clearview/motion.gd) | Conservative v6 frame/hinge proposals; refuses ambiguous/overlapping or precision-unsafe groups; user still assigns role/sign |
| [`clearview/observations.gd`](../../../../app/workshop/creator/clearview/observations.gd) | Closed `openrc-source-observations v1`, raw parameter evidence, explicit declared/unverified associations and bounded report rows |
| [`definition.gd`](../../../../app/workshop/creator/definition.gd), [`compiler.gd`](../../../../app/workshop/creator/compiler.gd), [`packages.gd`](../../../../app/workshop/creator/packages.gd) | Complete conventional electric gearless authoring; source context is removed before physical emission; inventory and package derivations are authoritative |
| [`record_loader.gd`](../../../../app/workshop/creator/record_loader.gd), [`trial.gd`](../../../../app/workshop/creator/trial.gd) | Ordinary aircraft-byte validation, frozen candidate and exact-context trial boundaries |
| [`store.gd`](../../../../app/workshop/creator/store.gd) | Immutable objects/revisions and root-pointer publication; storage identity is not proof of definition-to-physics semantic correspondence |
| [`workshop/compiler.gd`](../../../../app/workshop/compiler.gd), [`bundle.gd`](../../../../app/workshop/bundle.gd) | Existing registered variants and capability-gated transformations; preserve separate contracts |

Creator's first package is conventional aft-tail, single tractor electric, finite battery and gearless. Its development bounds include span 0.9–2.2 m, aspect ratio 4–7, taper 0.6–1, mass 1–4 kg and wing loading 3–8 kg/m², plus independent tail-volume, balance, control, thrust and installation bounds. These are development limits, not physical validation. The [package derivation](../estimated-trainer-package.md#package-domain-development-bounds) owns the complete table.

**A useful existing counterexample:** the dated ClearView corpus reports 18 visual admissions and eight refusals across 26 model roots. An admitted V-22 visual does not become a supported tiltrotor flight model. Treat that as evidence for separate visual/flight outcomes, not as 18 compatible aircraft. [ClearView results](../clearview-2026-11-15.md#7-implementation-evidence)

**Persistence counterexample:** a converted ClearView GLB can retain original parameter bytes, but the original ZIP remains external. Store validates object identity without proving that a stored definition compiles to its paired physical record. The new receipt/closure design must verify both source-byte closure and the semantic definition→physics relationship before claiming reproducible conversion. [Current guide](../../../AIRCRAFT-WORKSHOP.md#aircraft-creator-experimental)

## Version and source matrix

The following outcomes are proposed. None is a tested Flight Simulator import in OpenRC. Model encoding, effective configuration, accessible dependencies and permissions matter more than the product name alone.

| Generation / source form | Readable data opportunity | Geometry/paint route | Flight-model limit | Proposed priority |
| --- | --- | --- | --- | --- |
| FS2004 / FS9 | Compatible legacy CFG observations | External conversion of older MDL/BMP subset; author source export when available | AIR/binary records and animation dialect require separate coverage | Later limited legacy route |
| FSX / Acceleration / Steam | `aircraft.cfg`, engine/contact/weight metadata; referenced AIR identification | Externally prepared GLB from authorized MDL or original source | CFG alone omits aero tables; gauge/custom-FDM behavior not converted | Legacy data after modern-source MVP; exact cases tested |
| Prepar3D | Related SimObject/CFG/AIR family | ModelConverterX or author export, with exact P3D/model version recorded | Version-specific materials, AIR, modules and custom simulation | Per-version legacy extension; no blanket v1–v6 promise |
| MSFS 2020 authoring source | Split or embedded readable CFG; model/variant/LOD/behavior references | Automatic qualified source-glTF/material conversion; optional prepared-GLB route | Active modern/legacy semantics and OpenRC law fit still required | First target |
| MSFS 2020 compiled Community package | Accessible CFG may be useful independently of visuals | Content probe; supported converter or authorized source export | Runtime optimized data and DDS/material extensions; no ordinary-glTF assumption | Experimental, per-source outcomes |
| MSFS 2024 legacy 2020-style package | Route according to detected source semantics | Same restrictions as its actual underlying encoding | Host version does not upgrade compatibility | Reuse only proven legacy/source path |
| MSFS 2024 native modular source | Common/preset/attachment configurations and dynamic values | Assemble selected exterior/livery and normalize admitted formats | Composition/overrides and newer tensor/material rules | Separate later adapter |
| MSFS 2024 streamed/Marketplace content | A local directory may expose only metadata or partial files | Require complete authorized local source/export | Missing/protected content and custom runtime systems | Explain inability; no extraction/bypass |
| Livery or stock-aircraft improvement | Often only overrides or textures | Requires a separately supplied base/model closure | Mod's code license does not license missing base assets | Dependency-report case |
| Pre-FS2004, scenery-only packages, helicopters/VTOL | Outside this fixed-wing scope | Optional future research | Different data/vehicle laws | Not committed by this plan |

Primary support: [F01–F16](sources-and-examples.md#format-and-package-sources), [legacy flight-model documentation](conversion-and-scaling.md#legacy-air-and-source-runtime-code). FS2004 and particular FSX/Steam/P3D combinations were investigated through documentation/tool support; no binary aircraft corpus was executed. Their grouping is a proposed family strategy, not a measured interoperability result.

### Why modern source is preferable to a universal installed-package importer

The 2020 SDK describes manifests/layouts and a build pipeline; source models and built models are different artifacts. The official Asobo plugin's explicit compiled-input limitation is direct evidence against treating every `.gltf` in Community as a normal export. Conversely, its pure Khronos export option supports an author-controlled preparation route. [F01, F08–F09](sources-and-examples.md#format-and-package-sources)

The inspected A32NX LOD06 reinforces this with actual file evidence: it declares required DDS support, an optimized Asobo asset extension and 29 animations. It cannot enter the current rigid, PNG-only Creator subset unchanged even though its path is under `src/model`. The C-17 low LOD has no declared textures/animations and includes invisible/shadow material features; choosing the smallest LOD is not automatically a useful exterior. [Pinned inspections](sources-and-examples.md#inspected-aircraft)

For native 2024 sources, common files and selected presets/attachments compose the aircraft; dynamic CFG parameters can be overridden per attachment. Later decoding of a texture does not solve that composition. Official documentation also distinguishes built texture representations and says StreamedPackages downloads a few files needed to stream the rest. [F10–F14](sources-and-examples.md#format-and-package-sources)

### Why flight-data conversion is a separate feature

The target simulator's laws decide what a parameter means. Legacy AIR tables, MSFS surface normalization, propeller/CFD interactions and custom modules cannot be reproduced by copying fields whose names resemble OpenRC coefficients. The implementation must record each field as supported, inactive, conflicting, unresolved, reference-only or adopted through an explicit mapping. [Detailed mapping](conversion-and-scaling.md)

An automatically constructed, explicitly estimated RC configuration can still be useful when the full-scale source FDM is unavailable. It must declare which source dimensions are reused, which flight parameters are borrowed/estimated and which motor/propeller/battery/control installation is newly selected. A full-sized airliner exterior at RC scale does not fit the current conventional trainer law merely because its span is 1.5 m.

## Alternatives considered

| Approach | Benefit | Decision |
| --- | --- | --- |
| Send installed glTF directly to Godot | Appears short to implement | Reject as product architecture: skips Creator's supported subset, assumes source/built equivalence and does not handle physics or systems |
| Use a simulator SDK compiler/importer in the product | Could handle some proprietary build details | Do not select without applicable permission; SDK/sample terms are material, and a build pipeline is not a universal decoder |
| Require Blender/ModelConverterX for every player | Reuses established tools | Optional author/recovery workflow only; the normal automatic route ships its own qualified conversion runtime |
| Implement MDL/AIR and native 2024 first | Potentially broad catalogue | Defer: more binary/version/composition uncertainty before the shared Creator flight and persistence gates close |
| Generic file adapter plus guessed stock physics | Quick flyable-looking result | Reject implicit substitution; offer a separately authored, labelled RC installation only when topology/domain fit is explicit |
| Reuse Creator with source reports and bounded normalization | Matches existing architecture and admits useful staged results | Selected proposal; qualification remains per source/configuration/domain |

These are engineering conclusions from the inspected contracts and external sources. Tool selection and performance remain conditional on implementation spikes; no benchmark advantage is asserted.

## Evidence scope and remaining unknowns

This work inspected current repository source/plans, official format/physics documentation and public aircraft source files. Three external aircraft repositories were pinned and examined at configuration/model-JSON level; their exact revisions and file paths are in [sources and examples](sources-and-examples.md#inspected-aircraft). Mesh counts are declarations derived from JSON, not decoded or rendered validation. No binary aircraft assets, SDK samples or simulator executables were installed/copied into this branch.

No model was converted or test-flown, no FS/Prepar3D telemetry was collected, no numerical gate was rerun, and no physical handling or target-hardware performance is claimed. The current task changes documentation only. Formula arithmetic, document paths/anchors, branch ancestry and the published file set are the relevant checks; the [plan](../../../plans/flight-simulator-aircraft-import.md#8-verification-and-release-contract) defines future implementation verification.

Open decisions include the first complete authorized conventional aircraft, source-package closure budgets, decoder workspace/cancellation, provider/versioned provenance adoption, accurate source-to-LE landmarks, the existing Creator numerical gate, and shared Home/portable-source completion. Realistic inspected examples are valuable stress cases, but none establishes a permissive, dependency-free first-flight fixture.

### Review decisions

The integrated design accepts the format research's source-first strategy and the physics research's separation of original data, dimensional estimates and RC reauthoring. The initial review proposed prepared GLB plus readable observations as an early useful milestone. The later owner clarification retains that engineering increment and requires an in-app automatic conversion journey for completed-product acceptance, as specified in the linked wizard. It retains the repository audit's failed/open gates and semantic storage limitation. Exact version labels, source-array order, model JSON features and worked scaling arithmetic were checked before integration; helper reports are evidence inputs, not compatibility certification.

### Documentation verification (2026-11-16)

A read-only independent review found and closed three design gaps before publication: coordinate order must be field/version-specific; adopted provenance needs a versioned Definition/Compiler/UI/Store path; and per-file capture checks cannot claim an atomic multi-file revision. The plan now requires independent definition-to-physical-byte correspondence, whole-closure race cases and applicable required CI. A bounded follow-up review found no remaining material defect in those corrections. A separate formats review checked the pinned source identities, paths, declared model counts and tool/license descriptions against the recorded inspections.

Reused `tools/ci/check_docs.py` link/anchor functions against the staged Git tree for the seven changed Markdown files: **120 new or affected local links, zero errors**. Unchanged links outside the affected targets were excluded; 62 external link occurrences were not subjected to a blanket network availability check. `git diff --cached --check` reported no whitespace errors.

An independent arithmetic check reproduced the synthetic scaling example's area, mass, speed, inertia, power, Reynolds ratio, both conditional stall estimates and wing-loading counterexample, plus the asymmetric tensor transform and its inverse. These checks verify the written derivation and document navigation. No runtime code, generated aircraft data or third-party assets changed; simulator tests, required implementation CI, conversion fidelity and exported-platform flight qualification were not run or claimed.

### Automatic wizard clarification (2026-11-16)

Following the owner clarification after `8a0ec5320789a1eddccd576e066537aacffa2dff`, the plan now requires automatic in-app conversion for its advertised source profile, zero follow-up questions when source/profile data suffice, conditional unit-aware controls and later editing with coherent recomputation. Prepared GLB remains an engineering/recovery path. The new wizard specification defines W01–W14 and assigns them to existing AC-FS work; these are proposed journeys, not executed importer tests.

Two focused independent reviews informed the integrated design. Accepted corrections preserve qualified in-app reduction of oversized sources, avoid mandatory pickers for already resolved choices, distinguish unavailable features from answerable questions, and separate an unsaved candidate's trial readiness from actual Store publication. The editing contract names coherent governing-input or validated-override routes and exposes fixed-package limitations as implementation work.

Verification for this documentation revision: 195 new or affected local links/anchors passed; W01–W14 and the 16 existing AC-FS work-package IDs were checked; scale-once, aspect-ratio invariance and CG arithmetic checks passed; changed-file whitespace checks passed. Only 14 Markdown files changed. No automatic importer, converter runtime, UI or flight campaign was implemented or executed.

### Automatic import contract audit (2026-11-16)

**Audited revision:** `b9088ad19fa688e8f01cd22bbfd94a1d6f9596b1`. Scope: the automatic import plan, wizard and conversion specification against the current Creator Authoring/Definition/Compiler, inventory proposals, UI, Store and accepted power-package data. Two independent read-only reviews covered product/persistence and physics/data semantics; the lead checked material claims against the actual source and integrated the corrections. This audit corrects planning contracts and records implementation dependencies. It does not patch the current Creator or implement the importer.

| ID / severity | Finding and concrete evidence | Accepted correction and focused acceptance |
| --- | --- | --- |
| A01 / High | The wizard's blanket “partial Store failure” rule could misreport a committed aircraft as unsaved. [`_on_publish_pressed()`](../../../../app/ui/aircraft_creator.gd) publishes first and separately saves the draft; [`Store`](../../../../app/workshop/creator/store.gd) has a root-pointer commit point and an explicit uncertain-readback outcome. A later draft quota/conflict failure is not publication rollback | Separate confirmed absence, confirmed publication, uncertain commit and concurrent-revision conflict. Reconcile pending UUID/revision/record identity before retry and avoid duplicate revisions. **W18; AC-FS-02/10/11**, coordinated with AC-13 |
| A02 / Medium | Zero-question save lacked a default display-name policy. [`Authoring`](../../../../app/workshop/creator/authoring.gd) starts unnamed; Creator's test-flight filename fallback is display-only, while [`publication`](../../../../app/ui/aircraft_creator.gd) and Store require a valid nonempty name | Generate a bounded editable name from selected metadata, source basename or a fallback; keep display names separate from UUID and preserve user names on reimport. **W15; AC-FS-02/03/10** |
| A03 / Medium | Invalid edits were promised to survive, but the persistence seam was unspecified. [`set_item_raw()` / `snapshot()`](../../../../app/workshop/creator/authoring.gd) return before dirty tracking for a nonnumeric item edit and serialize accepted inventory values. The [`UI`](../../../../app/ui/aircraft_creator.gd) holds item/size/datum errors separately and clears local buffers on reopening; a rejected input can disappear while an older accepted value remains | Own raw text/units/validity in the versioned document, include rejected edits in dirty/history/backup handling, and validate current raw state at publication/flight. Save invalid drafts without losing their blockers. **W16; AC-FS-02/07/10**, with AC-13/14 |
| A04 / Medium | Item-wide evidence cannot implement property-level edit preservation. [`Authoring.set_item_raw()`](../../../../app/workshop/creator/authoring.gd) edits an estimated item's value without changing its `kind`; [`propose_airframe_inventory()`](../../../../app/workshop/creator/definition.gd) refreshes the whole estimated item, and [`Compiler`](../../../../app/workshop/creator/compiler.gd) applies one kind to mass, position and size. Changing the whole item to manual would mislabel untouched estimates | Separate per-property ownership/overrides from evidence under stable component IDs, merge only eligible automatic properties and preserve independent provenance through undo/reset/save. **W17; AC-FS-02/07/08/10** |
| A05 / Medium | The conversion spec required ESC limits/actual equipment while the plan permitted an estimated default, without specifying whether ratings were mandatory or modeled. The [power package](../../../../app/data/creator/power-electric-4s-800kv-apc12x6-estimated-v1.json) has synthetic electrical values and borrowed 11×6 curves at 12×6 diameter; [`propulsion_block()`](../../../../app/workshop/creator/packages.gd) emits an ideal ESC. “60 A” appears only in hardware-description prose | Permit a numerically qualified ideal/estimated simulated profile with explicit unmodeled limits; keep real-installation claims separate. Requalify edited equipment against its coupled law/data envelope. **W19; AC-FS-07/08**; rated-limit support remains conditional on advertising that capability |

The [wizard](../../../plans/flight-simulator-import-wizard.md) now defines W15–W19 in addition to W01–W14; all are proposed implementation journeys. The [feature work packages](../../../plans/flight-simulator-aircraft-import.md#7-work-packages) explicitly order shared state/identity work before automatic recomputation and publication. AC-14's remaining undo/redo slice is named, and the ready-envelope predicate must cover permitted CG/inertia, equipment and actuator edits rather than inheriting qualification from static bounds alone. These refinements preserve automatic in-app conversion and editable estimates without expanding the first release to a real-hardware or rated-ESC simulator.

Existing source capture, axis/scale separation, inventory-derived mass properties, source-law conditional mapping, source-to-visual correspondence, stale-job rejection and exact trial/start identities remain applicable. The audit did not establish new failures in those already specified contracts. The existing numerical, Home/portable and exported-platform qualification work remains open; passing documentation checks cannot close it.

**Verification:** the integrated correction received focused closure review; remaining property-granularity and conditional-rated-profile wording was aligned before staging. Reused `tools/ci/check_docs.py` against the staged Git tree: **87 new or affected local links across 14 bounded related documents, zero errors**, with all existing anchors in the five changed documents preserved. W01–W19 are unique and consecutive; all 16 AC-FS work packages remain, and the five new journeys map to their stated implementation owners. Changed-file whitespace checks passed. This revision changes five Markdown files only. Runtime tests, conversion, numerical campaigns and platform qualification were not run or claimed.
