# Twenty investigations for responsive vehicle and skin loading

**Research date:** 2026-11-17. **Deliverable:** twenty distinct, source-backed investigations and an expanded implementation plan. These are design recommendations and controlled experiments, not implemented optimizations or measured OpenRC speedups. [Authoritative plan](../../../../plans/vehicle-selection-performance.md) · [Audit](../code-audit.md) · [Experiments](../benchmark-protocol.md).

The intended result is a catalog that remains responsive with 100 installed vehicles, a clear and fast skin selector, and bounded preparation of the vehicle the player actually requests. A 1,000-record metadata fixture tests catalog scale separately from a library of heavy real imports. Existing validation, resource ownership and accepted launch identity remain mandatory.

## Research method and useful search vocabulary

Each investigation starts with a concrete symptom, identifies the mechanism that could cause it, searches that mechanism in engine documentation or original engineering work, and checks whether the result fits OpenRC's actual code and engine version. Every note records the queries used, primary sources, application seam, counterexample, experiment and rejection conditions. Twenty investigations does not mean twenty searches: a useful investigation often needed several queries and a version/source check.

| Symptom or question | Terms used to find the relevant mechanism | Why these terms are useful |
| --- | --- | --- |
| Opening the catalog touches too many assets | `asset registry`, `soft references`, `metadata-only discovery`, `UI virtualization`, `recycled bindings` | Separates discovering a vehicle from preparing its visual, and records from live controls |
| The new vehicle appears late even with a spinner | `progressive mesh loading`, `preview proxy`, `time to first useful preview`, `material variants` | Finds ways to deliver truthful visual feedback and reuse geometry |
| Background loading still freezes a frame | `dependency closure`, `load_threaded_get blocking`, `cooperative scheduling`, `largest indivisible task` | Searches for work after I/O and for the operations a frame budget cannot interrupt |
| Rapid browsing starts obsolete work | `singleflight`, `latest request wins`, `admission control`, `backpressure`, `prefetch accuracy coverage timeliness` | Separates duplicate suppression, bounded work and useful prediction |
| A larger cache does not improve revisits | `scan pollution`, `cache admission`, `TinyLFU`, `S3-FIFO`, `asset churn` | Examines whether a one-off selection should displace a frequently revisited vehicle |
| Memory spikes while swapping models | `unique resource ownership`, `reservation budget`, `hysteresis`, `retirement backlog` | Measures overlap and release timing instead of only counting retained entries |
| A changed imported skin still looks old | `content-addressed derived data`, `immutable revision paths`, `atomic publication`, `cache invalidation` | Connects application identity to actual resource paths and crash recovery |
| Files are small but loading is slow | `Basis Universal transcode`, `GPU-native block compression`, `KTX2`, `meshopt`, `Draco`, `bundle locality` | Distinguishes storage, decoding, geometry creation and GPU delivery |
| First draw or selection acknowledgement hitches | `pipeline compilations`, `in-frustum warmup`, `settings write coalescing`, `atomic commit` | Finds costs outside the model-file read without assuming either is dominant |

Sources from Unreal, Unity, browser scheduling, Go, cache research and SQLite supply mechanisms and counterexamples. They do not supply drop-in Godot APIs, benchmark numbers for OpenRC, or permission to replace its established owners. Live `stable`/`latest` documentation is labeled separately from pinned beta2 source. A smaller file, a higher hit rate or a smooth animation is not sufficient evidence of lower complete user wait.

## The twenty investigations

The recommendation column records this research pass. Current delivery status and ownership remain in the plan; all implementation is pending. Experiment identifiers refer to the benchmark protocol. **Early** means a recommended first implementation slice after attribution, **core** means an architectural or correctness boundary, and **conditional** means proceed only when the stated bottleneck is observed.

| ID and investigation | Mechanism and application | Recommendation / plan owner | Experiment |
| --- | --- | --- | --- |
| [T01 — Metadata catalog](01-metadata-catalog.md) | Published descriptors and soft references let search/filter work without loading models or scanning skin archives | Core; UI-VS-06 | E5, E9 |
| [T02 — Virtualized cards](02-virtualized-cards.md) | Recycle a viewport-sized set of native controls and reject late thumbnail results for obsolete bindings | Core for the 1,000-entry case; UI-VS-07 | E5 |
| [T03 — Progressive preview](03-progressive-preview.md) | Immediate correct thumbnail; optionally a separately authored, cheaper 3D representation before the full visual | Thumbnail core; proxy conditional; UI-VS-01/04/09 | E15 |
| [T04 — Material variants](04-material-variants.md) | Prepare and atomically commit a private appearance patch while retaining proven-compatible geometry | Early car then aircraft pilot; UI-VS-03/11 | E1 |
| [T05 — Offline preview data](05-offline-preview-data.md) | Generate invariant bounds, pose and shadow data through the owning model pipeline | Early after dominant-stage attribution; UI-VS-04 | E3 |
| [T06 — Dependency closure](06-dependency-closure.md) | Trace hidden synchronous dependencies after the selected resource becomes ready | Core measurement; UI-VS-00 | E0, E10 |
| [T07 — Singleflight ownership](07-singleflight-ownership.md) | One engine request owner per exact resource identity; stale consumers detach without abandoning terminal collection | Preserve current owner; generalize only when needed; UI-VS-02/10 | E2, E7, E10 |
| [T08 — Cooperative finalization](08-cooperative-finalization.md) | Split measured main-thread preparation into safe stages and measure the largest indivisible operation | Conditional measured stage; UI-VS-04/05 | E18 |
| [T09 — Admission and backpressure](09-admission-backpressure.md) | Stop admitting new idle flight speculation during active browsing while preserving the active-job drain | Early scheduling experiment; UI-VS-02 | E2 |
| [T10 — Predictive prefetch](10-predictive-prefetch.md) | At most one useful, timely neighbor under spare capacity; measure coverage, accuracy, waste and lost headroom | Conditional after selected-path work; UI-VS-10 | E7 |
| [T11 — Scan-resistant retention](11-scan-resistant-admission.md) | After serving a selection, avoid letting one-off full previews evict useful revisits; trial a small probation rule | Conditional trace-driven experiment; UI-VS-05 | E11 |
| [T12 — Memory reservations](12-memory-reservations.md) | Reserve visible, candidate, decode, upload and retirement overlap; count shared allocations once | Core before broader retention; UI-VS-05 | E4 |
| [T13 — Reuse and retirement](13-pooling-retirement.md) | Retain the current bounded pool; separately test safe carryover across Home recreation and paced destruction | Conditional on measured rebuild/disposal cost; UI-VS-05/12 | E12 |
| [T14 — Versioned disk derivatives](14-content-addressed-cache.md) | Immutable resource paths and dependency closure plus verified, recoverable publication | Core imported-derivative contract; UI-VS-08 | E9, E13 |
| [T15 — Dependency locality](15-bundle-locality.md) | Group measured asset families and compare package layout independently from compression | Conditional I/O/package experiment; UI-VS-09 | E14 |
| [T16 — Texture representation](16-texture-compression.md) | Compare portable Basis data with target-native blocks using the actual exported format and complete load path | Conditional transcode attribution; UI-VS-09 | E6 |
| [T17 — Resolution and residency](17-resolution-residency.md) | Author smaller preview textures without first retaining the full ones; qualify streaming separately by renderer | Tiers conditional; streaming deferred; UI-VS-09 | E6 |
| [T18 — Mesh delivery](18-mesh-delivery.md) | Separate codec decode, node/surface complexity, GPU representation and rendering LOD | Conditional owner-generated stock trial; UI-VS-09 | E16 |
| [T19 — Shader warmup](19-shader-warmup.md) | Use existing first draw as baseline; only warm the exact selected renderer/material path when attributed | Conditional; UI-VS-10 | E8 |
| [T20 — Selection persistence](20-selection-persistence.md) | Measure synchronous validation/save; consider full-state no-op detection and generation-safe write coalescing | Measure first; conditional UI-VS-00/01 | E17 |

T01–T20 are research identifiers. F01–F24 in the audit are source findings; the two sequences are not interchangeable. Related notes intentionally answer different questions: T09 decides whether heavy work may start, T11 decides whether a completed result deserves retention, and T12 decides whether its peak can fit. T03 concerns presentation tiers, T17 texture residency, and T18 geometry delivery. T05 generates data; T14 governs its identity and publication.

## What changes in the plan

The first wave remains measurement, selection identity, browsing-aware admission and a material-only skin pilot. The research makes these changes more specific:

1. **Measure the complete request.** Add hidden dependency loads, the largest atomic preparation call, post-frame retirement and selection persistence to the existing load/build/draw spans. No assumption that the disk is the bottleneck.
2. **Make immediate feedback a stable product path.** A requested thumbnail and exact skin label work even if the full preview is slow, unsupported or over budget. A 3D proxy is an optional additional asset with its own cost and identity.
3. **Separate memory admission from retention.** Always serve admitted explicit intent before speculative retention policy. Keep current count caps until unique-byte and overlap estimates are qualified; experiment with scan resistance only if real full-selection traces justify it.
4. **Qualify formats through both engine and product policy.** Stock export experiments and arbitrary imported GLBs are different contracts. Existing generated recipes are evidence to inspect, not proof of elapsed transcode time.
5. **Make every experiment falsifiable.** Each note includes an adverse case and a reason to keep the baseline. Optional work cannot block the usable catalog or hide cost in startup, flight launch, a later disposal frame or unreported memory.

## Compatibility and evidence boundaries

| Candidate | Verified engine/format fact | OpenRC constraint and decision |
| --- | --- | --- |
| Material variants | Khronos defines material mappings over existing geometry; Godot resources can be shared | Use the current private-material seam. Creator's extension allowlist does not admit `KHR_materials_variants`; do not require that extension for the pilot |
| Progressive mesh preview | Progressive LOD mechanisms exist in other loaders | No established OpenRC `MSFT_lod` route. Use independently generated preview files and a separate closure, if justified |
| Basis textures | Pinned `GLTFState` defines mode `2` as BasisU; pinned built-ins register `KHR_texture_basisu` support | Jet and F4U recipes use mode `2`. Actual packaged formats/cost remain unmeasured. Creator rejects that extension in user GLBs |
| Draco / EXT meshopt / quantization | Khronos specifies decoding and fallback requirements | Creator currently refuses these extensions. The core Godot list alone cannot establish every module/plugin's support; qualify an owner-produced candidate before any product admission change |
| Mip streaming | Pinned beta2 source has the module, disabled by default and unavailable on Compatibility | Deferred Mobile/Forward+ experiment, with whole-texture replacement overlap and minimum-level limits; not the main catalog solution |
| Warmup / baking | Godot distinguishes first-draw behavior by renderer and intermediate baking from hardware pipelines | Measure existing Home/flight draws and target drivers. Do not assume preloading or a hidden node proves Compatibility coverage |
| Offline cooking | Godot's post-import hook is editor-only | Generate stock derivatives before packaging; user imports need the existing runtime admission/derivative route |
| DirectStorage | Microsoft's path requires native integration and supporting assets/platform | Inspiration for I/O attribution only; no Windows-specific engine fork is justified for this selector plan |

The individual notes link each primary source and exact code seam. The table is a decision map, not a claim of tested support for untrusted formats.

## Source pin and drift check

Runtime audit: [OpenRC `3c91936`](https://github.com/bultodepapas/OpenRCsimulator/tree/3c91936ab8f9064daa798311b5fb3e89e28d3754). Initial documentation delivery: [branch commit `4b750f4`](https://github.com/bultodepapas/OpenRCsimulator/commit/4b750f4a40d5ab03bda91035bedc48484ac19547). Engine: [Godot `cafc17a19`](https://github.com/godotengine/godot/tree/cafc17a192acf67903910a68aeb3c076c0907a4b), 4.8-beta2.

Main had advanced to [OpenRC `16acd44`](https://github.com/bultodepapas/OpenRCsimulator/commit/16acd4433614023d223526abd3c7cae9fd3caffd) during this research. A scoped Git diff covering UI, AppRoot, aircraft, render, preferences, data, engine/project settings, Creator preflight, debug bridge and the two cited model import sidecars found only two AI-companion data changes: `app/data/ai/companions/aircraft/jensen-das-ugly-stik-60.json` and `app/data/ai/companions/behavior-manifest.json`. The cited selector, builder, persistence, importer and sidecar seams were unchanged. This is a scoped drift check, not an audit of every newer subsystem. The documentation branch retains its original runtime base.

Pinned engine inspection additionally checked resource request/collection ownership, dependency-string representation, deferred-call scheduling, resource sharing, editor-only post-import scope, glTF extension registration, the KTX route and embedded-image enum. Current vendor documentation remains supporting evidence, with target-executable qualification required before implementation claims.

## Reading and decision workflow

Start with the plan and E0, choose the measured critical stage, then read the corresponding note and run its smallest decisive comparison. Preserve raw results and reject an inconclusive optional optimization. Use the benchmark's targeted mappings rather than running every conditional experiment on every asset and host. The useful output is a lower complete user wait with correct selection, bounded memory and reliable launch—not adoption of all twenty techniques.

The parent [delivery verification](../README.md#delivery-verification) records documentation checks. No native simulation, package qualification or timing experiment was run for these notes.
