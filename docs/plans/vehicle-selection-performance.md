# Responsive vehicle selection and skins

**Status:** proposed implementation plan, 2026-11-17. **Owner:** menu/product shell, under UI-05 and UI-39. **Step prefix:** UI-VS-00…12. No step below is delivered merely by adding this plan.

**Baseline:** main [3c91936](https://github.com/bultodepapas/OpenRCsimulator/tree/3c91936ab8f9064daa798311b5fb3e89e28d3754), Godot 4.8-beta2. [Dated audit and source inventory](../research/menu-investigations/vehicle-selection-2026-11-17/README.md). This is the authoritative implementation plan for vehicle catalog scale, skin-selection clarity and Home preview switching; the [menu redesign](menu-redesign.md) continues to own the overall shell and Home-to-flight loading.

## 1. Product outcome

A player can see many vehicles at once, identify the selected vehicle and its exact skin, change that skin in one action from visible choices, and keep browsing while a detailed preview is prepared. The catalog remains usable with 100 installed vehicles and is stress-tested with 1,000 metadata entries. These are different workloads: opening or querying 1,000 catalog entries must not synchronously create 1,000 scenes, GPU uploads or skin-archive scans. Background index bootstrap/repair is separately bounded.

For supported appearances of the same geometry, switching a skin reuses the prepared geometry, pose, camera framing and invariant shadow data. Different geometry still takes the normal validated construction route. Fly/Drive always uses the selected, valid vehicle/skin tuple; a delayed preview never changes that tuple or substitutes the previously displayed vehicle.

The first delivery targets 1920×1080. Higher resolutions follow, then 1280×720 as a compatibility check. Keep the existing lime/graphite design, native controls, controller navigation, translations, reduced motion and opaque mode. The [interface specification](../research/menu-investigations/vehicle-selection-2026-11-17/ux-spec.md) defines the proposed behavior.

## 2. Existing mechanisms to retain

| Existing mechanism | Preserve and extend |
| --- | --- |
| AppRoot-owned HomePreviewResources | One authoritative request owner; deduplication; one active request and latest queued intent; terminal collection of obsolete requests |
| HomeScene request generation and current-intent checks | Old callbacks cannot install the wrong vehicle or skin; cache hits remain immediate |
| Three recently built vehicle/skin previews | A safe baseline and rollback policy while adding measured byte admission; hidden nodes remain inactive |
| Two retained PackedScene references | Explicit strong ownership; account for the common flight scene sharing this pool |
| HomePreviewGeometry | Private value snapshots and numeric worker; live Nodes/resources and publication stay on main |
| Static LiveryPicker | Browsing and focus do not instantiate 3D models; selected choice and focus restoration already exist |
| Registry, skin and aircraft validation | Content identity, bindings, provenance and launch validity remain authoritative |
| Home flight preparation and loading surface | Selected scene/trim adoption, cancellation/drain and readiness gates remain intact |

Do not introduce a competing asset manager, a second unbounded model cache, a live simulation behind the menu, or an engine upgrade as a prerequisite. The current field already survives ordinary vehicle selection; preserving it is not a new optimization.

## 3. Ownership and affected seams

| Owner | Expected implementation boundary |
| --- | --- |
| UI-VS | app/ui/home.gd, livery_picker.gd, home_scene.gd, home_preview_resources.gd, home_preview_geometry.gd, home_flight_preparation.gd; small shared app_root.gd hooks; catalog widgets, preferences and i18n |
| AS and model authors | Preview descriptors, material-slot compatibility, generated bounds/pose/shadow metadata, source regeneration and manifest identities |
| Vehicle and skin owners | render/airplane.gd, vehicle_paint.gd, aircraft/custom_skin.gd, procedural skin adapters and each activity's visual route; geometry-changing skins retain their existing builders |
| VQ / DT-11a | Texture/import experiments, CPU/GPU attribution, memory accounting, first draw and package measurements |
| AE / AC | User-import admission, immutable library revisions, content/thumbnail cache and publication into Home; no duplicate import library |
| D6-GP / accessibility | Native focus/controller behavior and live localization/text scaling |
| Physics/session owners | Existing validated launch handoff only; no vehicle-specific kernel changes or shared mutable flight state |

New source paths named in this plan are proposals. Put new widgets beside existing UI code, generated data beside its owning model pipeline, and evidence in the dated investigation folder. Coordinate shared files before implementation. Keep source-generating inputs and exact tool versions in the existing model manifests rather than hand-editing generated geometry.

## 4. Selection and presentation contract

Keep distinct values for focused catalog item, persisted desired appearance, effective selected launch tuple, pending preview tuple, and displayed preview tuple. Each tuple identifies source, vehicle, skin and immutable content revision. A missing desired skin must not disappear into an unlabeled default: disclose any effective fallback, keep the desired identity available for recovery, and require an explicit new selection before launching that fallback. Focus changes alone do not persist a selection or start a full model build. Activating an available card immediately changes the selected tuple and queues its preview; there is no extra confirmation screen.

The header and action summary name the selected vehicle and skin immediately. If an old preview remains, label it explicitly, for example, “Showing Vantage Jet · preparing Corsair / Navy Blue.” A static thumbnail of the requested tuple can replace that old preview region while loading. Do not leave an unlabeled old aircraft underneath a new name. A preview failure leaves selection explicit, retains navigation, offers Retry and keeps independent launch-validity rules.

Preserve immediate aircraft Fly while its preview is pending, with independent launch validation. Extend the target contract to every activity: accepting Fly/Drive captures the exact source/vehicle/skin revisions and launch settings before any await, supplies matching transition feedback and uses that activity's validated route. This is additional work for the current car/airship/multirotor routes, which drain Home preparation before reading some live Home/preferences values; they do not all use the aircraft staged transition. Block duplicate launch acceptance while preserving safe cancellation/recovery. A later Home selection must not alter the accepted launch.

The current aircraft route copies preferences but resolves the skin again at launch, where an unavailable choice can become the default. The new contract must retain admitted immutable content through preparation or revalidate its exact identity at commit. Removal/replacement between selection, activation and readiness either preserves the exact accepted revision or refuses with recovery. It never silently substitutes a default or a different vehicle. Preview readiness alone does not decide flight validity.

~~~mermaid
flowchart TD
    A["Explicit selection"] --> B["Publish name, skin and focus"]
    B --> C{"Compatible preview retained?"}
    C -->|Yes| D["Prepare appearance transaction"]
    C -->|No| E["Request selected resources"]
    E --> F["Prepare validated preview"]
    D --> G{"Still current and valid?"}
    F --> G
    G -->|Yes| H["Commit and observe first draw"]
    G -->|No| I["Release stale candidate"]
~~~

This is a proposed state contract, not a promise that every engine operation becomes asynchronous. A frame budget cannot interrupt one indivisible builder, texture upload or mesh-array read.

## 5. Catalog architecture for 100+ vehicles

### Metadata first

Keep the aircraft catalog's aircraft-only contract. Build the UI view model from VehicleRoster plus admitted imported entries through an adapter; do not insert cars, boats or import drafts into aircraft-only solvers. Use stable IDs independent of translated labels and row positions. Preserve the existing historical alias and remembered aircraft/activity distinction.

Each catalog record should expose an immutable, versioned descriptor: vehicle ID, content revision, display name, family, origin, availability/validation state, supported activities, thumbnail identity, default and remembered skin IDs, skin-summary count, preview descriptor identity and launch adapter ID. Search indexes contain text and tags only. Navigation/open/query enumeration performs no synchronous geometry/texture loading, physics parsing or custom-archive inspection. Imported metadata is an untrusted hint: map an adapter ID only to an explicitly registered, owner-admitted activity; never load a script/path supplied by a catalog archive or trust its claimed ready status.

Use a simple in-memory ID map and stable sorted arrays initially. A database is not justified by 100 vehicles. Persistent import metadata belongs to the existing Creator/library storage owner. Keep the catalog visible while an incremental import/index refresh publishes a new immutable snapshot; reconcile selection and focus by ID.

On first upgrade, existing .orskin files may have no index. Provide bounded incremental discovery/revalidation for bootstrap and missing/stale/corrupt index repair. Show partial/unknown indexing state without blocking navigation and preserve desired saved IDs until reconciliation finishes. External changes trigger bounded reconciliation; directory and archive limits still apply. Catalog reads use published metadata snapshots while the background owner checks actual content. Index recovery may rebuild derivatives/indexes, not overwrite or recreate the user's source assets.

### Bounded UI and thumbnail work

The expanded Vehicles workspace uses a responsive card grid plus a selected-vehicle pane. Compare a simple native-control prototype with a pooled grid at 100 entries and keep the simpler implementation that meets the gates. The 1,000-entry acceptance case still requires viewport-bounded live cards/images: if the simple control does not provide that behavior, recycle native Control rows for the visible window plus one overscan row above and below. Preserve logical focus independently from recycled controls; materialize the next focused row before moving focus. No assumption that GridContainer or ItemList itself virtualizes children.

Use generated 256-pixel-class thumbnails for catalog cards and a larger tier only where the selected pane needs it. The exact pixel dimensions follow measured display size and quality tests. Load visible thumbnails first, then the overscan window, then the selected item's skin strip. A recycled card checks its bound ID/revision before accepting a late texture. Limit both decode/upload work per frame and total texture bytes. One texture per frame is not by itself a cost bound when user images can be large.

Generate stock thumbnails from accepted models at build time; generate imported thumbnails after admission, outside navigation. Key them by vehicle/skin content, camera/lighting recipe and generator version. Do not render the whole fleet on first menu open, use photography unrelated to the model, or synchronously read pixels back from the GPU on every click. Missing previews get a neutral family icon and “Preview unavailable,” never a different vehicle.

## 6. Fast skin changes

### Two explicit routes

**Compatible appearance route:** same geometry revision, hierarchy, material slots, adapter version, relevant visual options and neutral pose. Retain the selected preview root and immutable meshes; prepare only the changed texture/material bindings and any declared appearance-dependent data. Validate the candidate before replacing overrides. Publish one successful appearance transaction, then observe the requested skin's first draw.

**Full visual route:** a separate GLB with unproven geometry equivalence, changed hierarchy/material-slot schema, imported revision, procedural remeshing requirement or unsupported adapter. Continue using the existing validated builder. Do not infer compatibility merely from a shared display name or vehicle ID. Initially keep Corsair, MoonRunner and airship GLB variants on this route; migrate only after their authoring pipeline proves equivalence and regenerates the contracts.

Start the fast-route pilot with one material-painted ground vehicle, then one aircraft. Existing VehiclePaint.apply provides origin-material handling and per-instance copies, but it is not yet the proposed transactional controller. Extract a prepare/apply boundary rather than calling it blindly on a cached visual with accumulated overrides.

### Appearance transaction invariants

1. Resolve the current immutable vehicle and skin revisions, base-model identity, target slots and capability. A cache hit does not bypass this check.
2. Resolve the complete desired appearance from the verified base plus selected layers. A→B→Default must remove B's overrides and textures, including absent fields, not merge onto B indefinitely.
3. Prepare new mutable materials privately. Share only immutable meshes/textures. Never edit a material held by another preview, the stock PackedScene, a Workshop model or a live flight.
4. Load/validate/decode the required textures under the existing resource ownership and memory policy. Raw custom images require their own bounded decode stage; changing only a color should not decode unrelated images.
5. Confirm generation, base revision, slot map and scene lifetime immediately before commit. Missing texture, invalid slot, cancellation or revision change leaves the old appearance intact and releases the candidate.
6. Apply a bounded complete patch on main, update displayed skin identity, and retire replaced overrides under measured ownership. If a valid patch cannot fit the budget, use the normal candidate route or improve its asset grouping; partial visible repainting is not success.
7. Reuse bounds, support pose, neutral geometry and shadow data only when their dependency keys match. Emission, alpha/transparency, lighting skins, procedural adapters and material features may affect presentation or first-use shaders; encode those dependencies explicitly.

Do not reparent the Home visual into flight. Launch still builds/validates its own accepted state. Before adding a retained immutable appearance descriptor to the handoff, prove independent material ownership and preserve every launch contract.

## 7. Remove work that does not belong on selection

Use current phase measurements to choose the first expensive stage. Candidate authoring outputs are neutral bounds, parked support pose, propeller clearance, projected-shadow geometry, material-slot tables and default light anchors. They must derive from accepted source geometry and record the input hashes and algorithm version. For a known descriptor, the menu reads compact values instead of repeatedly scanning all vertices.

Keep runtime fallback for older/missing descriptors. Do not publish guessed landing gear, misleading ground capability or an approximate shadow as equivalent without review. Mesh topology, display pose, visibility, relevant material alpha and customization can invalidate different derived values; define keys per output rather than one arbitrary “model cached” flag. Validate generated-versus-runtime arrays/pose and visual output on representative models, including the gearless MoonRunner and helicopter.

A cached preview descriptor is presentation evidence, not physical validation. Initial aircraft data, imported content and every accepted flight retain their existing validation. Caching complete validation is a later, measured experiment requiring immutable dependency closure and versioned validator identity; a filename, modification time or vehicle ID alone is insufficient.

## 8. Loading priority and prefetch

Use one admission policy across visible thumbnails, selected skin/model requests and idle flight preparation. Keep the known scene-load safety gate. The intended priority is explicit launch, explicit vehicle/skin intent, visible UI assets, then optional speculation. Priority controls work not yet admitted; it does not preempt an active Godot load.

The present idle scene job begins after a rendered, settled Home and 350 ms stable intent, and pauses all preview-broker admissions. Measure the additional wait it causes when the player resumes browsing. First experiment: suppress admission of that scene/trim speculation while the Vehicles workspace or skin gallery is actively being browsed; resume after returning to the Flight workspace and settling. Already active jobs drain normally. Cached identity/thumbnail feedback remains immediate, even when a cold detailed preview must wait.

Compare current preparation, browsing-aware preparation and preparation off using 0/350/750 ms dwell cases. Report both menu latency and subsequent Fly readiness: improving one by hiding cost in the other is not sufficient. Do not simply unpause the broker while the dedicated scene worker is active or start competing loads; the existing workaround has lifecycle evidence that a new candidate must replace deliberately.

After selected loading and skin reuse are measured, trial one directional neighbor's resource or lightweight preview asset. Only admit it when no explicit request is pending, memory has reserved headroom and frame cadence is healthy. Hover/focus may nominate an intent after a short dwell, but cannot commit selection. On direction reversal, drop queued speculation, drain active work and retain its result only if still useful within budget. Disable speculation under memory pressure, on Home exit and during accepted launch. Do not preload all 100 vehicles.

## 9. RAM, VRAM and cache accounting

The present three-model/two-resource limits remain hard fallback caps during the first measurement phase. A later policy must account for unique resource allocations and in-flight peaks rather than only entry count. Distinguish compressed disk bytes, decoded CPU images/geometry, strong references, GPU texture/buffer estimates, OS resident memory and driver-reported residency. Shared references count once in the ledger; OS RSS and renderer memory overlap and must not be summed as if independent allocations. Unified-memory hardware needs one pressure policy with renderer sublimits.

| Cache/pool | Identity and budget rule |
| --- | --- |
| Catalog descriptors | Immutable catalog revision; metadata only, with bounded string/tag sizes |
| Thumbnail textures | Content + recipe + size tier; visible/selected references pinned, recent items evictable; initial experimental cap 16 MiB |
| Prepared visual resources | Content/import/engine identity plus applicable quality tier; selected and accepted-launch references pinned; active and queued reservations counted |
| Preview nodes and derived geometry | Geometry/adapter/pose and presentation dependencies; retain only useful recent entries; existing count cap until byte estimates are validated |
| Appearance materials/textures | Base geometry/slot contract + skin content + adapter version + relevant rendering options; private mutable overrides, shared immutable textures |
| Import/disk derivatives | Content-addressed, engine/importer/recipe-versioned, rebuildable; atomic publication, stale-entry invalidation and a user-clearable budget owned by the library pipeline |

The 16 MiB thumbnail cap is an experiment setting, not a universal device recommendation. For illustration, 256×144 RGBA8 is 144 KiB without mipmaps; 100 such decoded thumbnails are about 14.1 MiB before overhead. Full-fleet texture loading is unnecessary even when it happens to fit that small example.

Do not pick a universal 512 MiB or “N percent of VRAM” preview cache from guessed hardware capacity. UI-VS-00 must measure the maximum admitted stock/imported preview and transition peak on the target low-memory machine, the main desktop and Apple Silicon. UI-VS-05 then sets explicit conservative tier limits and records how they were derived. If reliable GPU budget data is unavailable, use conservative known texture/mesh estimates and observed pressure; preserve the user's graphics preference.

The ledger constrains application admission/reservations; it is not an absolute cap on all engine, driver or process allocations. Unknown-size imports need bounded validated dimensions/complexity and a conservative cost class before heavy preparation, or remain thumbnail-only. Track estimated/reserved bytes and observed process/GPU peaks separately. Keep hard concurrency/count limits while estimates are being qualified.

Admission reserves old displayed visual + candidate + decode/snapshot temporary data + pending uploads/destruction before starting work. When the request exceeds available budget: evict unpinned speculative/recent data, skip speculation, use a declared smaller preview tier, or retain a static thumbnail with a clear preview limit. Do not evict the active model under the player or silently lower flight quality. Use separate low/high watermarks to avoid unload/reload oscillation. Releasing a dictionary reference is not proof of immediate VRAM reclamation; sample after the relevant frames/drain and inspect remaining owners.

Content-keyed broker records alone do not invalidate Godot's path-based resource cache. Prefer immutable versioned paths for imported revisions and their dependency closure; ensure actual builder loads use the same revision. If a source is replaced in place, a tested reload boundary must preserve old live consumers and verify fresh dependencies before publication. Do not use CACHE_MODE_REPLACE as normal eviction. Persisted source-version retention stays with the library owner; retiring runtime cache references does not authorize deleting user source files. [Engine cache detail](../research/menu-investigations/vehicle-selection-2026-11-17/loading-research.md#application-keys-do-not-override-the-engines-path-cache).

Do not raise CustomSkin's 32-installed/128-directory-entry limits as a substitute for indexing. Keep archive/pixel/decompression limits while publishing bounded, verified skin metadata at import time. The full accepted archive remains verified on application/admission as required by its immutable revision contract.

## 10. Texture and GPU experiments

Measure load/decompression/transcode, CPU build, upload/attach and first draw separately. If current imported textures still spend material time in Basis Universal transcoding, compare an asset-pipeline output using target-appropriate VRAM compression. Preserve source pixels, color-space and normal-map semantics, alpha, mipmaps and material bindings; review silhouettes and skin details at 1080p and above. Smaller PNG/JPEG files alone do not lower resident texture memory.

For the Compatibility renderer, shader warmup requires a representative rendered draw, not a hidden Node or a preloaded material. Use only the selected candidate and the relevant rendering features behind an opaque transition where appropriate; do not flash a different aircraft or warm the fleet. A warmup draw still costs time, so measure total work and first usable frame. Existing flight first-draw preparation may already cover the necessary variants.

Godot 4.8-beta2 contains experimental texture mip streaming, but it is disabled by default and explicitly unsupported by Compatibility. It is a late, separate Mobile/Forward+ trial, not the main solution. No renderer migration is included. [Versioned evidence and alternatives](../research/menu-investigations/vehicle-selection-2026-11-17/loading-research.md).

## 11. Implementation sequence

Every row is a separate reviewable change or experiment; no fixed delivery estimate is justified before UI-VS-00.

| Step | Work and dependency | Acceptance evidence / current status |
| --- | --- | --- |
| UI-VS-00 | Extend existing selector/loading observers; pin code/assets/imports; inventory current 13 vehicles and cold/warm/skin/cache-pressure paths | Phase attribution, 1080p native baseline, RAM/VRAM limits and 100/1,000-entry UI fixture. **Pending** |
| UI-VS-01 | Explicit desired/effective/displayed skin identity and header; immutable activity launch tuple before drain, named feedback and exact revision check; no loader redesign | Native mouse/key/pad, EN/ES, 100–200% text; Drive/airship/quad selection changes during drain; missing/replaced skin at launch; save-error/recovery. **Pending; independent of heavy optimizations** |
| UI-VS-02 | Browsing-aware admission for existing Home preparation; preserve active-job drain | Measured blocked-preview wait and Fly tradeoff; rapid return, cancel, Quit and no competing-resource regressions. Depends 00. **Pending experiment** |
| UI-VS-03 | Material-only skin transaction pilot on one car then one aircraft | A→B→Default equality, missing-asset rollback, material ownership and no geometry rebuild on proven-compatible changes. Depends 00/01. **Pending** |
| UI-VS-04 | Generated preview metadata for the measured dominant fitting/shadow stage; compatibility fallback | Generated/runtime equivalence, invalidation, camera/grounding/shadow images and reduced phase cost. Depends 00, AS/model owners. **Pending** |
| UI-VS-05 | Unique-resource ledger, reservations and byte-aware admission/eviction with existing count caps as fallback | Reservation bounds plus observed peaks, unknown-size/low-memory fallback, 20-cycle plateau and no retained orphan ownership. Depends 00; required before broader retention/prefetch. **Pending** |
| UI-VS-06 | Shared metadata index and generated stock/skin thumbnails; bounded legacy bootstrap/repair through existing storage | Navigation/query has no synchronous GLB builds/archive scans; reproducible thumbnails; partial/index-repair state; imported invalid/missing/replaced entries remain explicit. Depends 01 and AC seam. **Pending** |
| UI-VS-07 | Bounded grid, search, type/origin filters, favorites/recent and persistent logical focus | 100/1,000 descriptors, fixed viewport-sized Control/thumbnail pool, native keyboard/controller and localization checks. Depends 06. **Pending** |
| UI-VS-08 | Content-addressed imported preview/skin derivatives; publish catalog changes atomically | Clean packaged runtime path, interrupted import/revision replacement/corrupt-cache recovery; no editor-only import assumption. Depends 05/06 and AC admission. **Pending** |
| UI-VS-09 | Texture-format/preview-tier A/B for measured heavy assets | Fresh-import and package comparison, appearance review, format/residency accounting and lower complete workload cost. Depends 00/05; VQ owns. **Conditional** |
| UI-VS-10 | At most one useful neighbor prefetch; actual selected-path shader warmup only if attributed | Benefit exceeds variation without regressing first Home, rapid browsing, memory or immediate Fly. Depends 02/05/07 and relevant attribution. **Conditional** |
| UI-VS-11 | Expand fast appearance route to qualified adapters; optional proven-equivalent GLB extraction | Fleet/material/custom/procedural regressions, generator proofs and matching launch skin; fallback retained. Depends 03/04/05. **Pending** |
| UI-VS-12 | Integrate stock/import/catalog/appearance/launch and package lifecycle qualification | Native 1080p matrix, above-1080p then 720p, supported renderer/platform evidence and honest remaining limits. Depends accepted preceding slices. **Pending** |

Start with 00 and 01, then run the small 02 experiment and 03 pilot. Do not make a new catalog wait for speculative texture streaming, nor build a complex disk cache before measuring the simpler changes. Stop optional experiments that fail to improve the complete workload or preserve correctness.

## 12. Proposed performance gates

These are acceptance targets on named, documented hardware, not promised timings for arbitrary imports. Baseline work may reveal a target that needs an explicit scope/asset-budget adjustment; report it instead of silently changing the denominator.

| User-visible measure | Proposed gate |
| --- | --- |
| Selection/focus feedback | Next normal rendered frame; p95 ≤50 ms, maximum ≤100 ms during tested browsing bursts |
| Cached vehicle or compatible cached skin, through first requested draw | p95 ≤100 ms, with no intentional minimum animation delay |
| Warm texture-only skin miss on an admitted supported asset | p95 ≤250 ms; report decode/upload and individual worst frame separately |
| First detailed preview of each admitted stock vehicle | p95 across repeated runs per vehicle ≤1 s; report every outlier and preserve immediate metadata/thumbnail feedback |
| Catalog open/filter, 100 and 1,000 metadata entries | p95 ≤100 ms to usable result; displayed Control/image pool bounded by visible window, not catalog count |
| Frame cadence while loading | Desired 16.7 ms cadence on the 60 Hz target; transitional p95 ≤33 ms, no unexplained main-thread slice above 100 ms; count frames above 33/50/100 ms |
| Memory and lifecycle | Explicit candidate peak bound; no monotonically growing ownership after repeated loops; retain selected state and clean teardown |
| Home and Fly | Preserve the existing global ≤5 s process-cold/≤3 s warm Home and ≤2 s Fly targets as pending gates; report dwell plus post-click time separately |

Small samples cannot establish reliable tail percentiles. Use the [benchmark protocol](../research/menu-investigations/vehicle-selection-2026-11-17/benchmark-protocol.md) for distributions, raw observations, historical limits and measurement overhead. No headless result or average FPS alone closes these gates.

## 13. Rollout and completion

Introduce experiments behind developer/test switches using the existing settings and diagnostic paths; expose only meaningful user controls. Keep the known synchronous/validated fallback until each new route proves parity and lifecycle behavior. Preserve native scene-load workaround unless the exact pinned-engine fixture and app lifecycle show it can be removed. Revert a candidate that produces stale skins, shared-material mutation, unbounded memory, lost focus, invalid import launch or loading delay integrated into simulation time.

Completion requires source and exported-package evidence with the selected skin visible and launched correctly, the 100-vehicle catalog responsive, current-source performance measured on the named targets, and every unsupported/import-limited state explicit. A nicer screenshot, a cache-hit microbenchmark or moving the wait into startup is insufficient.
