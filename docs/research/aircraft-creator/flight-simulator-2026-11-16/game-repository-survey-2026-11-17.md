# Flight Simulator import: twenty game and asset-pipeline studies

**Date:** 2026-11-17. **OpenRC baseline:** `947fd7cb96ffdabb461fef63bd228342377e41ab`. **Status:** source research and proposed engineering decisions; no upstream program, converter or performance campaign was executed. These are **20 additional repository cases**, G01–G20, extending the [earlier 24 investigations](follow-up-24-investigations/README.md) and [26 aircraft/converter cases](code-investigations-2026-11-17.md). The [feature plan](../../../plans/flight-simulator-aircraft-import.md), [wizard](../../../plans/flight-simulator-import-wizard.md) and [eight milestones](../../../plans/flight-simulator-import-milestones.md) own implementation and acceptance.

## Scope and method

The sample combines game/simulator projects, a game compatibility engine, general engines and runtime asset libraries. It is not a claim that all 20 are indie games or Flight Simulator converters. Each case reads actual implementation at an immutable commit and identifies a transferable mechanism, its limits, an original proposed fixture and existing AC-FS/M owners. Source behavior is distinguished from an inferred failure mode and from OpenRC's proposed requirement. No runtime defect was reproduced; no aircraft assets or third-party code were adopted.

Naev, OpenMW and Veloren's GitHub repository metadata identifies their primary development elsewhere; their pinned GitHub snapshots are the evidence here, not a claim of primary-repository freshness. The original glTFast upgrade guide and Unity variant support one G18 family case; aliases/forks are not counted twice. The Godot snapshot is a separate reference: OpenRC's [stack](../../../STACK.md) names its own pinned 4.8-beta2 engine, and this survey does not upgrade it or establish equivalent API behavior on that build.

### Repository register

| Case | Repository at inspected revision | Main contribution |
| --- | --- | --- |
| G01 | [Rowlhouse/PicaSim][repo-G01] | Consistent visual/hinge transforms, separate physical construction |
| G02 | [paparazzi/crrcsim-pprz][repo-G02] | Independent visual and physical-configuration choices |
| G03 | [RigsOfRods/rigs-of-rods][repo-G03] | Source-located diagnostics and partial-validation counterexample |
| G04 | [FlightGear/flightgear][repo-G04] | Explicit aircraft selection and discovery-cache scope |
| G05 | [pioneerspacesim/pioneer][repo-G05] | Per-model mesh sharing and separate render/collision processing |
| G06 | [OoliteProject/oolite][repo-G06] | Ordered inheritance and actual verifier-coverage limits |
| G07 | [VDrift/vdrift][repo-G07] | Cache ownership and diagnostic-placeholder limits |
| G08 | [endless-sky/endless-sky][repo-G08] | Batched contradictory-dependency diagnostics |
| G09 | [naev/naev][repo-G09] | Declared versions versus content identity; GitHub mirror |
| G10 | [OpenMW/openmw][repo-G10] | Ordered source lookup and origin/error reporting; GitHub mirror |
| G11 | [OpenRA/OpenRA][repo-G11] | Inspectable effective configuration and inheritance errors |
| G12 | [OpenRCT2/OpenRCT2][repo-G12] | Metadata inspection without images, loading cleanup and weak-index limits |
| G13 | [luanti-org/luanti][repo-G13] | Required/optional edges and unresolved-dependency reporting |
| G14 | [veloren/veloren][repo-G14] | Duplicate/failed source visibility and watcher limits; GitHub mirror |
| G15 | [godotengine/godot][repo-G15] | Existing engine boundary, external URI and synchronous-call limits |
| G16 | [bevyengine/bevy][repo-G16] | Separate own, direct and recursive dependency readiness |
| G17 | [FyroxEngine/Fyrox][repo-G17] | Shared pending work, terminal states and failed-reload preservation |
| G18 | [Unity-Technologies/com.unity.cloud.gltfast][repo-G18] | Cooperative frame budgeting and explicit resource disposal |
| G19 | [KhronosGroup/UnityGLTF][repo-G19] | Injectable data loader and partial-scene cleanup |
| G20 | [jkuhlmann/cgltf][repo-G20] | Allocator/file callbacks, ownership and parser-budget boundaries |

The full 40-character revision is embedded in every repository/source link. The [license register](#license-and-reuse-register) records observed declarations separately from integration decisions.

## Game and simulator cases

### G01

**PicaSim: keep geometry, hinge and physics transformations traceable.** [AeroplaneGraphics::Init][G01-graphics] reads model scale and offset, combines them with aircraft size scale, and applies the same visual scale/offset to both control-surface hinge endpoints. [RenderModel::Init][G01-render] applies the passed scale-then-offset operation to vertices. [AeroplanePhysics::Init][G01-physics] separately creates dimensional scaling from size/mass inputs and physical components from XML.

**Adapt:** retain an explicit source-model-to-target-visual transform and apply it to all relevant landmarks and hinges. Physical scaling continues through OpenRC's typed, qualified target rules; this code is not evidence that another simulator's scaling law is appropriate for the target RC aircraft.

**Independent fixture:** model scale 3, size scale 2, offset `(1,2,3)`, and hinge endpoints `(1,0,0)` / `(1,1,0)` yield `(8,4,6)` / `(8,10,6)` under the declared visual chain: combined scale 6 and scaled offset `(2,4,6)`. An asymmetric mesh must agree with those landmarks. Compare physical scale/mass results separately. **Owners:** M4/M5, AC-FS-05/06/07; W03/W05/W07.

### G02

**Patched CRRCsim: visual choice and flight configuration are separate decisions.** [XMLModelFile::ListOptions/getGraphics/getConfig][G02-variants] enumerate graphics and configuration independently. Both start at index zero; an out-of-range selected index returns the first matching entry. This is the inspected Paparazzi fork, not a universal CRRCsim-version claim.

**Adapt:** keep distinct stable selected identities for model, livery and physical source configuration, with qualified compatibility between them. Automatically resolve unique or retained valid choices. An invalid explicit choice must not silently become the first item after a source update.

**Independent fixture:** two visuals and two configurations, with visual 1/configuration 0 explicitly selected, must preserve those exact identities without questions. Reorder source entries while keeping stable identities, then remove the selected one: preserve the unresolved choice and show only the necessary selection. This does not commit OpenRC to implementing a CRRCsim adapter. **Owners:** M2/M4/M5, AC-FS-02/03/05/07; W01/W02/W12.

### G03

**Rigs of Rods: diagnostics can retain source location even when validation removes bad entries.** [ProcessOgreStream/ProcessRawLine/LogMessage][G03-parser] track filename, line and keyword. [Validator::Validate and its section macro][G03-validator] remove individual invalid component entries, while the returned `valid` value reflects separate configuration checks; an animator with no source is a concrete rejected entry.

**Adapt:** route source-located diagnostics into the existing Creator result/field/step system, retain invalid raw declarations, and attach the affected capability. A sanitized remainder must not erase a required control's deficit. This is a source observation, not an executed upstream bug report.

**Independent fixture:** one valid control binding and one declaration missing its source. Retain both observations, identify the invalid location, keep the usable draft where permitted, and block a claim that both controls are complete. A later correction replaces the affected diagnostic without losing unrelated edits. **Owners:** M2/M4/M5, AC-FS-02/03/06/07; W04/W05/W11/W16.

### G04

**FlightGear: explicit selection outranks discovery, and a discovery cache has a limited job.** [FindAndCacheAircraft::loadAircraft/checkCache][G04-discovery] honors an explicit aircraft directory and refuses a missing requested set file there. Its discovery cache checks configured roots, matching name and path existence; selected configuration is then read. This is not evidence that converted aircraft content is cached by those weak keys.

**Adapt:** preserve explicit source selection and exact dialect-defined precedence. Treat metadata discovery as a bounded convenience, then capture and validate actual bytes. A converted-stage receipt needs stronger identity than a discovered path.

**Independent fixture:** two roots contain a same-named source. An explicit selected root chooses its unique file without a question; absence there is reported rather than silently switching roots. Replacing bytes at the same path changes the new capture and invalidates affected results. **Owners:** M2/M3/M7, AC-FS-02/03/04/10; W02/W09/W12/W13.

### G05

**Pioneer: reuse per-model mesh nodes and process geometry by role.** [Loader::CreateModel/LoadMesh][G05-loader] cache references to mesh nodes by name across LOD definitions, delete the model on a mesh-load exception, and process renderable geometry separately from collision meshes. The inspected node cache does not establish immutable-only sharing; that is OpenRC's proposed safeguard below. No resource saving was measured here.

**Adapt:** deduplicate equivalent immutable decode/geometry work within the bounded import, while retaining distinct selected instances, transforms, hinges and provenance. Keep collision/physical source inputs even when they need no GPU render buffer. Sharing mutable materials or node state must not couple independent edits. The existing Creator output subset and all-retained-resource ceilings still apply.

**Independent fixture:** repeated eligible mesh references plus a collision-only component. The normalization recipe must preserve its declared selected instances and physical inputs; instrument any claimed reduction in decoded/render-buffer allocations. Mutate one instance's placement/paint/control and prove the other stays unchanged. An injected required-mesh failure cannot publish a partial model. **Owners:** M3/M4/M7, AC-FS-04/05/06/11; W05/W09/W10/W13.

### G06

**Oolite: inspect actual merge order and actual validation coverage.** [loadShipData/applyLikeShips/mergeShip][G06-registry] apply patches before inheritance, merge child values over a resolved parent, and stop when unresolved references cannot make progress. The actual stage order differs from a preceding summary comment. [OOModelVerifierStage][G06-verifier] checks model-file existence and queues work, but explicitly leaves its DAT check unimplemented.

**Adapt:** record the executed, version-qualified merge order and each effective property's origin. Missing references and cycles require attributed outcomes. A stage name, queued verifier or existing file cannot substitute for geometry/material/flight evidence. Oolite's inheritance/removal semantics do not become Flight Simulator semantics.

**Independent fixture:** parent supplies mass/span, child overrides span; other entries contain a missing parent and a two-node cycle. Assert exact effective values/origins for the valid child and separate unresolved outcomes for the others. A present malformed model must fail ordinary geometry admission even if metadata inspection succeeds. **Owners:** M2/M4/M5, AC-FS-02/03/05/07; W04/W11/W17.

### G07

**VDrift: a useful diagnostic default can hide a missing required model at its consumer.** [ContentManager::load][G07-content] searches configured paths, caches successful content and supplies a default while returning false on failure. The [factory][G07-default] makes a cube default, and [LoadDrawable][G07-load] uses the returned model without checking that Boolean. The content manager also releases entries held only by its cache.

**Adapt:** use explicit ownership for temporary resource release. If a placeholder is useful for a report, keep it visibly incomplete and outside admitted aircraft/flight publication. All consumers must preserve the source failure rather than infer success from a non-null model.

**Independent fixture:** start with a valid accepted preview, fail a required new mesh, then cancel/retry. Preserve the accepted revision, report the missing mesh, publish no placeholder, and drain only job-owned resources within the frozen limits. No saved Store object may be evicted by this temporary-cache policy. **Owners:** M3/M4/M7, AC-FS-04/05/10/11; W09/W11/W12/W18.

### G08

**Endless Sky: batch contradictory dependency diagnostics.** [PluginManager::Load][G08-manager] records required, optional and conflicting roles and reports duplicate plugin names with both paths. [PluginDependencies::IsValid][G08-deps] checks all role collisions before returning; required-plus-optional warns, while combinations with conflicting roles invalidate the declaration.

**Adapt:** preserve typed dependency declarations and report all independently detectable contradictions within the diagnostic budget. A rule may distinguish a redundant declaration from a blocking one. Use such roles only where the source adapter/profile actually defines them; do not add fictional MSFS `conflicts` semantics.

**Independent fixture:** an original resolver-contract profile declares A required/conflicting and B optional/conflicting. Produce both attributed blockers in one result. A separate redundant required/optional declaration has its documented outcome. An absent dependency proven nonessential creates no question. **Owners:** M1/M2, AC-FS-02/03; W02/W04/W11.

### G09

**Naev: declared name/version is not captured content identity.** [changed()][G09-plugin] compares maps from plugin identifier to semantic version. Same-version byte replacement is invisible to that particular comparison. [Plugin metadata][G09-metadata] defines lower numeric priority as higher precedence; this is Naev's rule, not a generic mod rule.

**Adapt:** include exact captured dependency bytes and qualified resolution context in invalidation. Reuse Creator's existing document-revision compile cache and immutable Store. Declared versions, modification times and watcher events may help discovery but cannot authorize reused conversion or readiness. Source scripts remain inert.

**Independent fixture:** change a required file to equal-length different bytes while retaining its declared version and timestamp. A new capture changes identity and invalidates affected stages; manual overrides survive. Unchanged inputs can reuse only correctly keyed verified work. **Owners:** M1/M2/M5/M7, AC-FS-02/03/07/10; W09/W12/W17.

### G10

**OpenMW: make winning and failed source locations inspectable.** [VFS::Manager][G10-manager] builds an index from ordered archives and can report the winning archive; [FileSystemArchive][G10-archive] warns on normalized-name collisions and includes the traversal location in errors. That traversal follows directory symlinks.

**Adapt:** retain the selected origin and overridden candidates in the effective source report. Apply only the exact source profile's precedence, and keep OpenRC's stricter rooted capture/no-follow rules. Following symlinks or warning-and-continuing on an ambiguous name is not borrowed into untrusted aircraft intake.

**Independent fixture:** a qualified overlay-over-base rule selects the unique overlay texture with both origins retained and no question. Two same-tier normalized matches become ambiguity; an inaccessible required edge reports its declaring file and failing target. A filename alone never lets an unrelated root satisfy the dependency. **Owners:** M2, AC-FS-02/03; W02/W04/W11.

### G11

**OpenRA: expose the effective configuration, with actionable inheritance errors.** [MiniYaml::Merge/ResolveInherits][G11-merge] process ordered sources and report missing or repeated parents with locations. The [resolved-rules command][G11-report] displays finalized merged rules. That output alone does not establish full typed provenance of each value.

**Adapt:** provide an expandable effective source report showing raw declarations, winning rule, source location, converted units, target disposition and user override separately. Reuse the existing Creator diagnostic/field UI. Do not import OpenRA's removal/inheritance language as MSFS grammar.

**Independent fixture:** qualified base/variant rules supply base mass and overridden span with separate origins. A missing/repeated parent produces source-located diagnostics. Editing mass manually survives re-resolution; restoring automatic returns to the attributed proposal, and downstream CG/inertia/readiness checks follow existing owners. **Owners:** M2/M5, AC-FS-02/03/07; W04/W08/W17.

### G12

**OpenRCT2: inspect metadata before expensive images, and explicitly finish loading work before replacement.** [ObjectFileIndex::Create][G12-index] calls [ObjectFactory][G12-factory] with image loading disabled. [FileIndex::LoadOrBuild][G12-fileindex] can rebuild a stale/corrupt index, but its aggregate count/size/time/path/version/language checks are not byte identity. [ObjectManager][G12-loader] collects missing required objects, deduplicates parallel loads, joins jobs and unloads newly loaded objects when a load fails before replacing object lists. Registrations and `obj->Load()` occur before the error check, so this is not proof of general transaction atomicity.

**Adapt:** inspect bounded metadata first where the format allows, defer expensive selected-closure decode, and keep OpenRC's new preview private until fully accepted. Treat an index as disposable acceleration. Reuse Store's actual transaction/CAS semantics rather than infer rollback from another engine's cleanup.

**Independent fixture:** metadata inspection produces no image/scene decode; a corrupt index rebuilds. Same-size/timestamp-preserving byte replacement invalidates affected work. Loading one valid and one corrupt required asset reports the failure, joins/drains all jobs, preserves the previous aircraft and creates no new accepted preview/revision; a successful retry creates only the intended revision. **Owners:** M1/M2/M3/M7, AC-FS-01/02/03/04/10/11; W02/W09/W12/W13/W18.

### G13

**Luanti: preserve unmet edges and distinguish their causes in OpenRC.** [resolveDependencies/getUnsatisfiedModsError][G13-resolver] add optional edges only when the dependency exists, remove satisfied edges and report remaining names. The message says a cycle may be responsible; the inspected path does not identify which unmet edges form a cycle.

**Adapt:** keep required and qualified optional edges with origins. Classify a proven missing node separately from a cycle among present nodes; report the specific cycle members rather than ask the player to locate a file that is already present. Optionality must come from the source profile, never from convenience. No package Lua/code executes.

**Independent fixture:** A requires absent B; present C and D require each other; E is absent and proven optional. Report missing B and the C–D cycle separately, with no question for E. Supplying B resolves only its affected chain. Recapturing with E now present changes the resolution context and any dependent results. **Owners:** M1/M2, AC-FS-02/03; W02/W04/W11.

### G14

**Veloren: a fallback and watcher silence cannot establish complete source resolution.** [CombinedSource::read and CombinedCache::combine][G14-cache] have distinct behavior: `read` logs duplicates and returns the first match, while `combine` concatenates successful sources and logs some non-missing errors even when another source succeeds. Plugin hot reload is explicitly unavailable.

**Adapt:** keep failed and losing origins beside a selected value; distinguish a permitted optional fallback from failure of a required overlay. Revalidate captured closure on an explicit new capture even when no watcher event fired. A fallback must have a qualified rule, not just an available same-named asset.

**Independent fixture:** a required overlay is unreadable while a base texture exists. Retain that error and the affected limited/refused state unless a separately qualified alternative demonstrably satisfies the same required capability. Permission to fall back for an absent optional overlay does not cover this failure. Correcting the overlay and recapturing resolves its bytes; associated proposals refresh without erasing manual edits. **Owners:** M2/M5/M7, AC-FS-02/03/07/10; W02/W10/W12/W17.

## Engine and asset-library cases

### G15

**Godot: reuse the current admitted-byte boundary, not unrestricted engine file resolution.** The separately pinned [GLTFDocument implementation][G15-gltf] joins decoded external buffer/image URIs to a base path and uses FileAccess/ResourceLoader. `append_from_buffer()` parses synchronously; `generate_scene()` creates scene nodes and mesh instances. OpenRC already [preflights self-contained bytes](../../../../app/workshop/creator/source_importer.gd) before [building the visual](../../../../app/workshop/creator/visual_builder.gd).

**Adapt:** resolve source dependencies once through captured bytes and normalize before the existing engine boundary. An empty base path, injectable loader or callback is not a sandbox guarantee. Evaluate the actual pinned OpenRC engine before choosing an API; keep preview/native work inside measured limits.

**Independent fixture:** permit an in-root parent reference but refuse decoded escapes, symlinks and external URLs. After capture, disable source access and verify only the captured closure supplies normalization. Measure near-ceiling `append_from_buffer` and scene-creation stalls on the actual target engine; exceeding the frozen limit blocks that profile. **Owners:** M2/M3/M4/M7, AC-FS-03/04/05/11; W09/W11/W13/W14.

### G16

**Bevy: distinguish an asset's own load from transitive readiness.** [LoadContext][G16-loader] records dependency edges and can collect them without immediately loading every asset. [AssetServer state handling][G16-state] distinguishes own, direct and recursive load states, waits for unresolved IDs and emits dependency-loaded only after recursive pending/failed sets are empty. Its convenience byte reader uses `read_to_end`; that API alone supplies no OpenRC byte budget.

**Adapt:** each import stage records its own result and the required dependency-closure result. A parsed aircraft CFG may be complete as a file while its visual remains blocked by a missing nested texture. Feed the causal edge chain into help; visual readiness and flight qualification remain separate gates.

**Independent fixture:** A references B references C. A/B parse while C is missing or delayed: their own parse can finish, but the required closure never reports complete. Diagnostics identify the B→C declaration and affected A capability. Supplying and admitting C completes the current closure once; stale generations cannot finish it. **Owners:** M1/M2/M3/M4, AC-FS-02/03/04/05; W02/W09/W11.

### G17

**Fyrox: share pending work deliberately and preserve accepted data when reload fails.** [ResourceManager][G17-manager] canonicalizes a registered path, shares an existing resource, queues pending work, and preserves previous successful data after a failed reload. It ages out sole-owned runtime resources. [ResourceState::commit][G17-state] installs a terminal state and wakes waiters.

**Adapt:** use job-owned pending/terminal states and verified stage keys, while retaining the previous accepted preview until the new one passes. Path/UUID alone is insufficient identity. Releasing an ephemeral runtime resource must never prune accepted Store/history blobs, and setting a cancelled state does not stop its worker.

**Independent fixture:** same path with bytes A then B; bytes A with a changed conversion recipe; exact unchanged retry. Only the last may reuse the corresponding verified output. A failed reimport retains the accepted preview and manual edits; all waiting consumers receive the matching generation's outcome, and only owned temporary resources are released. **Owners:** M2/M3/M7, AC-FS-02/04/10/11; W09/W12/W13/W18.

### G18

**Unity glTFast: schedule cooperative work and explicitly drain resource tasks.** The [upgrade guide][G18-origin] identifies the Unity variant/monorepo; it is counted once. [TimeBudgetPerFrameDeferAgent][G18-defer] calculates a frame fraction and yields at cooperative breakpoints. [GltfImport][G18-import] awaits texture-task disposal on unsuccessful/cancelled paths and provides explicit resource disposal; other paths copy byte arrays or read a whole stream into a string.

**Adapt:** make cooperative work units bounded, account for copies and resource lifetimes, and keep cancellation charged until work drains. A `Task.Yield`, progress display or average frame rate cannot bound an indivisible decoder. This is a scheduling reference, not a Unity dependency or a measured faster Godot implementation.

**Independent fixtures:** in the positive bounded-work case, rapid A→B→C selection never starts B and starts C only after A drains; longest UI stall, peak owned memory and cleanup meet preregistered limits. In the separate negative case, an indivisible decode deliberately exceeds the frozen stall ceiling: observe the breach, keep it charged/undrained while alive, and block that profile or require isolation/redesign. The violating run is never reported as a performance pass. **Owners:** M3/M7, AC-FS-04/11; W09/W13/W14.

### G19

**UnityGLTF: inject a data source and own partial-scene cleanup.** [ImportOptions/VerifyDataLoader/LoadSceneAsync/GetNode][G19-import] allow an `IDataLoader`, otherwise can construct a web-request loader; guard one importer instance; check cancellation at particular points; and clean up partial nodes/native buffers after failures. One instance's guard does not bound concurrent instances or all work.

**Adapt:** every external dependency request must resolve through job-owned captured bytes, or be eliminated by normalization to a self-contained in-memory buffer. A library with no external dependency requests need not expose an injectable resolver. No default disk/network fallback is allowed. Keep the global one-active/one-pending admission policy. Resource cleanup must cover partial engine construction and actual worker completion before accepting the replacement preview.

**Independent fixture:** one required texture is absent from capture, but an identical filename exists outside it. The import reports it missing and never opens that outside file. Cancel during partial scene creation while later selections arrive: old accepted aircraft survives, obsolete nodes are released, and only the latest pending selection may proceed after drain. **Owners:** M2/M3/M4/M7, AC-FS-02/03/04/05/11; W02/W09/W11/W13.

### G20

**cgltf: allocator and file callbacks make ownership explicit but do not supply every bound.** [cgltf_options/cgltf_calloc/cgltf_load_buffer_file/cgltf_free/cgltf_parse_json][G20-parser] expose allocation and read/release callbacks, check multiplication in the allocation helper, join/decode buffer references, distinguish borrowed/allocated/file-owned buffers, and perform a token-count prepass when requested automatically.

**Adapt:** evaluate such hooks only if an existing-runtime gap justifies another component. Enforce captured-only resolution, aggregate allocation and token limits, matching release ownership, and bounded preprocessing. An allocator cap does not bound CPU or memory outside its callbacks. This is a candidate for a bounded comparison, not a selected MSFS decoder; vendor extensions and physical conversion still require their own rules.

**Independent fixture:** equivalent two-buffer sources with contained and encoded escaping references; permitted reads return exact captured bytes and every other read fails. Inject allocation failure partway through and exceed a token ceiling: report failure, balance every owned allocation/release and measure the whole-process peak and prepass cost. **Owners:** M2/M3/M7, AC-FS-02/03/04/11; W09/W11/W13.

## Reuse decisions carried into the plan

| Decision | Evidence | Implementation consequence |
| --- | --- | --- |
| Reuse Creator boundaries first | Current source importer, Authoring, result envelope and Store; G15 | Extend capture/observation/normalization upstream of the existing GLB/compiler/trial/Store paths. No parallel catalog or engine migration |
| Inspect metadata before expensive selected-closure decode | G04/G12/G16 | A bounded candidate index may defer image/mesh work where semantics permit; it never certifies content, replaces capture or silently picks an ambiguous aircraft |
| Model dependencies and their causes explicitly | G06/G08/G10/G11/G13/G16 | Versioned edge roles, deterministic precedence, exact missing/cycle/conflict outcomes, winning/losing origins and per-capability transitive readiness |
| Make resolution and user help share evidence | G03/G08/G10/G11/G13 | Existing diagnostic codes/field/step plus bounded source/edge context; group common root causes and offer only applicable recovery actions |
| Reuse derived work by content and recipe | G04/G09/G12/G17 | Relevant input/closure/rule/tool/profile identities govern reuse; path, timestamp, declared version and watcher silence are insufficient |
| Share only qualified immutable resources | G05/G07/G17 | Preserve instance identity and edit isolation; retain collision/physical inputs and all required parts; measure actual allocations |
| Stage replacement and drain owned work | G07/G12/G17/G18/G19 | Old accepted preview/flight stays available; no partial or placeholder becomes ready; wait/terminate/join before freeing a superseded job's budget |
| Centralize source I/O and resource accounting | G15/G18/G19/G20 | Captured-only dependency reads, no default fallback, limits include preprocessing, copies, decoder/native work and cleanup |

These are accepted **planning decisions**, with implementation and measured benefit still open. The [canonical cache/readiness contract](../../../plans/flight-simulator-aircraft-import.md#45-dependency-readiness-and-reuse-of-derived-work) and [wizard help](../../../plans/flight-simulator-import-wizard.md#source-help-and-recovery) own current requirements. The G fixtures can extend an existing C/F/W test where they exercise the same mechanism; do not duplicate tests merely to increase a count.

### Component selection and bounded experiments

1. **Existing OpenRC and pinned Godot first.** Identify the exact missing source-normalization operation, required input semantics and independent expected output. Current byte admission, result handling, document revision cache, trial and immutable storage remain the baseline. An external library is justified by a concrete coverage, correctness or measured resource need.
2. **Compare a narrow candidate.** A small parser with explicit I/O/allocation hooks such as cgltf may enter AC-FS-04's comparison only after exact file/dependency terms and build targets are reviewed. Pin its real supported accessor/extension subset. It does not supply an MSFS material translator, rig mapper or RC physical model by itself.
3. **Use other engines as design references.** Bevy/Fyrox state handling and glTFast/UnityGLTF scheduling/cleanup inform the implementation; importing their engine frameworks is not selected. GPL/noncommercial game code is not copied by this research. Any later file reuse is a separate recorded decision.
4. **Measure equivalent outcomes.** Compare a cold bounded import, exact-input retry, paint-only edit, physical-property edit, required-file change and recipe change on named 1080p-first targets. Record stage invocation counts, hit/miss reasons, output identities, peak memory and longest UI stall, conversion time and full cancellation drain. All variants must satisfy the same independent visual/physical/admission oracles. A speedup from skipping a required part or using stale evidence is a failure.
5. **Keep cache optional and disposable.** Establish the correct uncached result first. Add only a measured-useful cache, bounded by entries/bytes/lifetime. Corrupt, incompatible or unverifiable entries rebuild from captured inputs. If those inputs are unavailable, report that condition; never fetch replacements silently or delete accepted Store data. No persistent cache service or new global scheduler is mandated.

## License and reuse register

This register reports the inspected declaration, not a completed integration or redistribution review. Exact source-file headers, dependencies and asset terms remain separate; no code or assets from these projects are vendored. Reading implementation for an independent design does not adopt its license as OpenRC's license.

| Case | Observed declaration and scope |
| --- | --- |
| G01 | [LICENSE.txt][G01-license]: PolyForm Noncommercial 1.0.0. Do not describe this snapshot as unrestricted open-source code or infer aircraft-asset permissions |
| G02 | [COPYING][G02-license]: GPLv2; selected source has a GPLv2 notice. Model terms require separate review |
| G03 | [COPYING][G03-license] and selected parser: GPLv3. Content is a separate scope |
| G04 | [LICENSE.md][G04-license]: GPLv2 text; inspected source header says v2-or-later. Aircraft/dependencies are separate |
| G05 | Selected loader identifies GPLv3 and [licenses/GPL-3.txt][G05-license]. No asset or Assimp-transitive clearance inferred |
| G06 | [LICENSE.md][G06-license]: program GPLv2-or-later; included artwork/configuration may use that license or CC BY-NC-SA 3.0. Selected registry also has its own permissive notice. Resolve exact-file terms before reuse |
| G07 | [LICENSE][G07-license]: GPLv3 text; selected source headers say v3-or-later. Content remains separate |
| G08 | [copyright][G08-license]: GPL-3+ default source declaration and separately listed artwork/exception terms |
| G09 | [LICENSE][G09-license]: GPLv3 source default with specified later-version permissions/exceptions; separate data and asset records |
| G10 | [README][G10-readme]: GPLv3 project declaration and separate fonts. Original game data is not included in that conclusion |
| G11 | [Inspected command header][G11-report]: GPL-3.0-or-later; separate game content/dependencies need review |
| G12 | [README][G12-readme]: GPLv3-or-later; inspected file headers name GPLv3. Exact-file review precedes adoption; original game files remain separate |
| G13 | [Resolver header][G13-resolver]: LGPL-2.1-or-later; [LICENSE.txt][G13-license] separately lists media and exceptions |
| G14 | [Workspace Cargo.toml][G14-license]: GPL-3.0-or-later; [assets crate][G14-crate] inherits it. Artwork/dependencies remain separate |
| G15 | [LICENSE.txt][G15-license]: MIT declaration; engine adoption is governed by OpenRC's existing pinned-engine process |
| G16 | [Cargo.toml][G16-license]: MIT OR Apache-2.0; not a transitive-component review |
| G17 | [LICENSE.md][G17-license]: MIT declaration; no engine integration selected |
| G18 | [Unity package LICENSE.md][G18-license]: Apache-2.0; Unity coupling, extensions and transitive components need separate evaluation |
| G19 | [LICENSE][G19-license]: MIT declaration; codecs/plugins and Unity dependencies are distinct |
| G20 | [LICENSE][G20-license]: MIT declaration; no decoder adoption or broad format qualification established |

## Evidence limits and continuation

Three read-only investigations partitioned game/simulator code, mod/configuration systems and asset engines. The lead inspected the decisive source sections and license declarations, corrected overbroad inferences and integrated the plan. In particular, FlightGear's discovery cache is not a conversion cache; Luanti's message is not cycle classification; OpenRCT2 cleanup is not proof of transaction atomicity; and a cooperative yield is not a hard decoder deadline.

The 20 cases provide implementation ideas and original acceptance examples. They do not qualify a real W01 aircraft, a shipped converter, physical fidelity, throughput or desktop performance. M1 still identifies the exact authorized source; M3 still selects and measures a bounded app-owned runtime; M6/M7 retain numerical, launch, saved-lifecycle and packaged-target gates. Automatic conversion and zero follow-up questions for complete supported input remain the product objective.

## Pinned source references

[G01-render]: https://github.com/Rowlhouse/PicaSim/blob/5b2c5871b82aecae4ae6293b862f31600a6a949c/source/PicaSim/RenderModel.cpp
[repo-G01]: https://github.com/Rowlhouse/PicaSim/tree/5b2c5871b82aecae4ae6293b862f31600a6a949c
[repo-G02]: https://github.com/paparazzi/crrcsim-pprz/tree/2d1131ec7d99f1172e4f051a303966046f62dbda
[repo-G03]: https://github.com/RigsOfRods/rigs-of-rods/tree/ebf31a2187bbc31a38331a86b233dfa7e60c52fb
[repo-G04]: https://github.com/FlightGear/flightgear/tree/807e406dd3bceca816942490a999970e157dbcfa
[repo-G05]: https://github.com/pioneerspacesim/pioneer/tree/254916fad966bce42f99024c5233899beef9eee8
[repo-G06]: https://github.com/OoliteProject/oolite/tree/21978c37b2f11c8664adf3e2062efc1d0c875979
[repo-G07]: https://github.com/VDrift/vdrift/tree/f4767dd0eb98f55a61d64c8c1462e254e0a23fa6
[repo-G08]: https://github.com/endless-sky/endless-sky/tree/0ccd5b9af613dc6da179763eb3beeb4208852af0
[repo-G09]: https://github.com/naev/naev/tree/65cf3a39b892614c003ac13d24e43855e98fa36b
[repo-G10]: https://github.com/OpenMW/openmw/tree/77eec0471802676324fb014d4d465ea652a8ec27
[repo-G11]: https://github.com/OpenRA/OpenRA/tree/b4d95a56717d8d0070f195e343f6c2728ce87900
[repo-G12]: https://github.com/OpenRCT2/OpenRCT2/tree/683f454670c5776a6d6e9e8966b6762f7c4b42dd
[repo-G13]: https://github.com/luanti-org/luanti/tree/8bb14e85d21a09d37961ed97548f6a9f71349422
[repo-G14]: https://github.com/veloren/veloren/tree/131d1193387861d35c74655662148f303c22c5b4
[repo-G15]: https://github.com/godotengine/godot/tree/bf828694fd29ccb0902cba2d2a8375cbaedd721f
[repo-G16]: https://github.com/bevyengine/bevy/tree/56d244d4e6f91c87194c888d914976b4ec16da04
[repo-G17]: https://github.com/FyroxEngine/Fyrox/tree/710a43e2eddab19b848be734ec9d1d706cf87d5a
[repo-G18]: https://github.com/Unity-Technologies/com.unity.cloud.gltfast/tree/fdb580527a41fd7006916030768ba74d3728f987
[repo-G19]: https://github.com/KhronosGroup/UnityGLTF/tree/a33785e484ef58fb15b7709a06200808a5e70680
[repo-G20]: https://github.com/jkuhlmann/cgltf/tree/85cd62382dfea638278962690cf515023f33ed00
[G01-graphics]: https://github.com/Rowlhouse/PicaSim/blob/5b2c5871b82aecae4ae6293b862f31600a6a949c/source/PicaSim/AeroplaneGraphics.cpp
[G01-physics]: https://github.com/Rowlhouse/PicaSim/blob/5b2c5871b82aecae4ae6293b862f31600a6a949c/source/PicaSim/AeroplanePhysics.cpp
[G01-license]: https://github.com/Rowlhouse/PicaSim/blob/5b2c5871b82aecae4ae6293b862f31600a6a949c/LICENSE.txt
[G02-variants]: https://github.com/paparazzi/crrcsim-pprz/blob/2d1131ec7d99f1172e4f051a303966046f62dbda/src/mod_fdm/xmlmodelfile.cpp
[G04-discovery]: https://github.com/FlightGear/flightgear/blob/807e406dd3bceca816942490a999970e157dbcfa/src/Main/fg_init.cxx
[G05-loader]: https://github.com/pioneerspacesim/pioneer/blob/254916fad966bce42f99024c5233899beef9eee8/src/scenegraph/Loader.cpp
[G06-registry]: https://github.com/OoliteProject/oolite/blob/21978c37b2f11c8664adf3e2062efc1d0c875979/src/Core/OOShipRegistry.m
[G06-verifier]: https://github.com/OoliteProject/oolite/blob/21978c37b2f11c8664adf3e2062efc1d0c875979/src/Core/OXPVerifier/OOModelVerifierStage.m
[G07-content]: https://github.com/VDrift/vdrift/blob/f4767dd0eb98f55a61d64c8c1462e254e0a23fa6/src/content/contentmanager.h
[G07-load]: https://github.com/VDrift/vdrift/blob/f4767dd0eb98f55a61d64c8c1462e254e0a23fa6/src/loaddrawable.cpp
[G07-default]: https://github.com/VDrift/vdrift/blob/f4767dd0eb98f55a61d64c8c1462e254e0a23fa6/src/content/modelfactory.cpp
[G12-loader]: https://github.com/OpenRCT2/OpenRCT2/blob/683f454670c5776a6d6e9e8966b6762f7c4b42dd/src/openrct2/object/ObjectManager.cpp
[G03-parser]: https://github.com/RigsOfRods/rigs-of-rods/blob/ebf31a2187bbc31a38331a86b233dfa7e60c52fb/source/main/resources/rig_def_fileformat/RigDef_Parser.cpp
[G03-validator]: https://github.com/RigsOfRods/rigs-of-rods/blob/ebf31a2187bbc31a38331a86b233dfa7e60c52fb/source/main/resources/rig_def_fileformat/RigDef_Validator.cpp
[G15-gltf]: https://github.com/godotengine/godot/blob/bf828694fd29ccb0902cba2d2a8375cbaedd721f/modules/gltf/gltf_document.cpp
[G16-loader]: https://github.com/bevyengine/bevy/blob/56d244d4e6f91c87194c888d914976b4ec16da04/crates/bevy_asset/src/loader.rs
[G16-state]: https://github.com/bevyengine/bevy/blob/56d244d4e6f91c87194c888d914976b4ec16da04/crates/bevy_asset/src/server/info.rs
[G17-manager]: https://github.com/FyroxEngine/Fyrox/blob/710a43e2eddab19b848be734ec9d1d706cf87d5a/fyrox-resource/src/manager.rs
[G17-state]: https://github.com/FyroxEngine/Fyrox/blob/710a43e2eddab19b848be734ec9d1d706cf87d5a/fyrox-resource/src/state.rs
[G18-defer]: https://github.com/Unity-Technologies/com.unity.cloud.gltfast/blob/fdb580527a41fd7006916030768ba74d3728f987/Packages/com.unity.cloud.gltfast/Runtime/Scripts/TimeBudgetPerFrameDeferAgent.cs
[G18-import]: https://github.com/Unity-Technologies/com.unity.cloud.gltfast/blob/fdb580527a41fd7006916030768ba74d3728f987/Packages/com.unity.cloud.gltfast/Runtime/Scripts/GltfImport.cs
[G18-origin]: https://github.com/atteneder/glTFast/blob/7e778180c5fe0e284eee505e7275b2d91d9a1566/Documentation~/UpgradeGuides.md
[G19-import]: https://github.com/KhronosGroup/UnityGLTF/blob/a33785e484ef58fb15b7709a06200808a5e70680/Runtime/Scripts/GLTFSceneImporter.cs
[G20-parser]: https://github.com/jkuhlmann/cgltf/blob/85cd62382dfea638278962690cf515023f33ed00/cgltf.h
[G08-manager]: https://github.com/endless-sky/endless-sky/blob/0ccd5b9af613dc6da179763eb3beeb4208852af0/source/PluginManager.cpp
[G08-deps]: https://github.com/endless-sky/endless-sky/blob/0ccd5b9af613dc6da179763eb3beeb4208852af0/source/Plugin.cpp
[G09-plugin]: https://github.com/naev/naev/blob/65cf3a39b892614c003ac13d24e43855e98fa36b/src/plugin.rs
[G09-metadata]: https://github.com/naev/naev/blob/65cf3a39b892614c003ac13d24e43855e98fa36b/docs/manual/src/plugins/metadata.md
[G10-manager]: https://github.com/OpenMW/openmw/blob/77eec0471802676324fb014d4d465ea652a8ec27/components/vfs/manager.cpp
[G10-archive]: https://github.com/OpenMW/openmw/blob/77eec0471802676324fb014d4d465ea652a8ec27/components/vfs/filesystemarchive.cpp
[G11-merge]: https://github.com/OpenRA/OpenRA/blob/b4d95a56717d8d0070f195e343f6c2728ce87900/OpenRA.Game/MiniYaml.cs
[G11-report]: https://github.com/OpenRA/OpenRA/blob/b4d95a56717d8d0070f195e343f6c2728ce87900/OpenRA.Mods.Common/UtilityCommands/OutputResolvedRulesCommand.cs
[G12-index]: https://github.com/OpenRCT2/OpenRCT2/blob/683f454670c5776a6d6e9e8966b6762f7c4b42dd/src/openrct2/object/ObjectRepository.cpp
[G12-factory]: https://github.com/OpenRCT2/OpenRCT2/blob/683f454670c5776a6d6e9e8966b6762f7c4b42dd/src/openrct2/object/ObjectFactory.cpp
[G12-fileindex]: https://github.com/OpenRCT2/OpenRCT2/blob/683f454670c5776a6d6e9e8966b6762f7c4b42dd/src/openrct2/core/FileIndex.hpp
[G13-resolver]: https://github.com/luanti-org/luanti/blob/8bb14e85d21a09d37961ed97548f6a9f71349422/src/content/mod_configuration.cpp
[G14-cache]: https://github.com/veloren/veloren/blob/131d1193387861d35c74655662148f303c22c5b4/common/assets/src/plugin_cache.rs
[G02-license]: https://github.com/paparazzi/crrcsim-pprz/blob/2d1131ec7d99f1172e4f051a303966046f62dbda/COPYING
[G03-license]: https://github.com/RigsOfRods/rigs-of-rods/blob/ebf31a2187bbc31a38331a86b233dfa7e60c52fb/COPYING
[G04-license]: https://github.com/FlightGear/flightgear/blob/807e406dd3bceca816942490a999970e157dbcfa/LICENSE.md
[G05-license]: https://github.com/pioneerspacesim/pioneer/blob/254916fad966bce42f99024c5233899beef9eee8/licenses/GPL-3.txt
[G06-license]: https://github.com/OoliteProject/oolite/blob/21978c37b2f11c8664adf3e2062efc1d0c875979/LICENSE.md
[G07-license]: https://github.com/VDrift/vdrift/blob/f4767dd0eb98f55a61d64c8c1462e254e0a23fa6/LICENSE
[G08-license]: https://github.com/endless-sky/endless-sky/blob/0ccd5b9af613dc6da179763eb3beeb4208852af0/copyright
[G09-license]: https://github.com/naev/naev/blob/65cf3a39b892614c003ac13d24e43855e98fa36b/LICENSE
[G10-readme]: https://github.com/OpenMW/openmw/blob/77eec0471802676324fb014d4d465ea652a8ec27/README.md
[G12-readme]: https://github.com/OpenRCT2/OpenRCT2/blob/683f454670c5776a6d6e9e8966b6762f7c4b42dd/readme.md
[G13-license]: https://github.com/luanti-org/luanti/blob/8bb14e85d21a09d37961ed97548f6a9f71349422/LICENSE.txt
[G14-license]: https://github.com/veloren/veloren/blob/131d1193387861d35c74655662148f303c22c5b4/Cargo.toml
[G14-crate]: https://github.com/veloren/veloren/blob/131d1193387861d35c74655662148f303c22c5b4/common/assets/Cargo.toml
[G14-readme]: https://github.com/veloren/veloren/blob/131d1193387861d35c74655662148f303c22c5b4/README.md
[G15-license]: https://github.com/godotengine/godot/blob/bf828694fd29ccb0902cba2d2a8375cbaedd721f/LICENSE.txt
[G16-license]: https://github.com/bevyengine/bevy/blob/56d244d4e6f91c87194c888d914976b4ec16da04/Cargo.toml
[G17-license]: https://github.com/FyroxEngine/Fyrox/blob/710a43e2eddab19b848be734ec9d1d706cf87d5a/LICENSE.md
[G18-license]: https://github.com/Unity-Technologies/com.unity.cloud.gltfast/blob/fdb580527a41fd7006916030768ba74d3728f987/Packages/com.unity.cloud.gltfast/LICENSE.md
[G19-license]: https://github.com/KhronosGroup/UnityGLTF/blob/a33785e484ef58fb15b7709a06200808a5e70680/LICENSE
[G20-license]: https://github.com/jkuhlmann/cgltf/blob/85cd62382dfea638278962690cf515023f33ed00/LICENSE
