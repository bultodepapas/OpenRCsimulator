# Current-source audit: vehicle selection and appearance loading

**Audited revision:** [3c91936ab8f9064daa798311b5fb3e89e28d3754](https://github.com/bultodepapas/OpenRCsimulator/tree/3c91936ab8f9064daa798311b5fb3e89e28d3754), main retrieved on 2026-11-17. File/line references below describe that revision. This is source inspection, not a new timing profile or rendered UI review.

The [twenty-investigation expansion](techniques/README.md) adds F21–F24 below and independently checks exact beta2 engine seams. Its scoped comparison with main `16acd44` found the cited application paths unchanged; the runtime baseline remains `3c91936`.

## 1. Runtime identity and scope

[app/get-godot.sh](../../../../app/get-godot.sh) pins Godot 4.8-beta2 / cafc17a19. [app/project.godot](../../../../app/project.godot#L61-L74) selects Compatibility normally and Mobile for arm64, with 4× MSAA. [STACK](../../../STACK.md) and the renderer guard describe the Apple Silicon route. The project prioritizes native 1080p qualification before larger resolutions and finally 720p.

The production route is GDScript/Godot, not the frozen three.js prototype. The selected preview is a visual in Home's existing landscape. Changing an ordinary vehicle calls request_aircraft; it does not normally rebuild the entire field. A performance proposal that “keeps the field loaded” would repeat current behavior.

## 2. Current fleet and appearances

Sources: [aircraft catalog](../../../../app/app_state/aircraft_catalog.gd#L23-L162), [vehicle roster](../../../../app/app_state/vehicle_roster.gd#L21-L54), [livery choice assembly](../../../../app/render/airplane.gd#L275-L312), [vehicle paint data](../../../../app/data/vehicle_paints.json), [Corsair manifest](../../../../app/data/aircraft_models/f4u-corsair-250.json), [MoonRunner overlay](../../../../app/data/aircraft_model_overlays/moonrunner-x99.json) and [airship catalog](../../../../app/vehicles/airship/airship_catalog.gd#L11-L16).

| Family | Home ID | Display identity | Built-in appearances including default | Current alternative route |
| --- | --- | --- | ---: | --- |
| Airplane | jensen-das-ugly-stik-60 | Ugly Stick | 5 | Material paints |
| Airplane | stik-electric-6s | Ugly Stick · Electric 6S | 5 | Material paints shared by family definition |
| Airplane | gp-extra-300s-60 | Great Planes Extra 300S .60 | 1 | Delivered default |
| Airplane | p51d-mustang-120 | P-51D Mustang 1/4 | 1 | Delivered default |
| Airplane | f4u-corsair-250 | F4U-1D Corsair 1/4.5 | 13 | Separate verified GLB liveries |
| Airplane | sebart-avanti-s-a200-p100rx | Vantage Jet | 6 | Material paints |
| Airplane | turbo-lumber-evolution | Turbo Lumber Evolution | 1 | Delivered default |
| Airplane | moonrunner-x99 | MoonRunner X99 | 2 | Separate GLB liveries |
| Helicopter | xcell-60-research | X-Cell .60 Trainer | 4 | HX-700 material paints; surrogate status retained |
| Multirotor | openrc-fpv5-x1 | ION R5 | 1 | Delivered default; no alternate picker |
| Airship | rc-blimp-5m | RC blimp | 3 | Separate GLB skins |
| Car | mt8-bisonte | Bisonte MT8 | 4 | Material paints |
| Car | monster-car-2 | MONSTER CAR 2 | 3 | Material paints |

There are **13 selectable vehicles and 49 built-in appearances counted per selectable vehicle**. Shared paints counted for both Stik variants are not distinct mesh/texture allocations. This count excludes user-installed custom skins. The three additional Stik glow configurations are technical-only catalog entries, not three more Home cards. No boat appears in VehicleRoster at this revision.

Inventory cross-checks used Git object identity for the small JSON files: vehicle_paints.json blob 1a8c1f1f6b31603b7595cfc797ada4bc5a6e1e25; Corsair manifest cebf3dd5c6c11dafdef0e53d167973770926e0dc; MoonRunner overlay aaa8e436107a980c9d7c90127a5f997a27678e3d. Counts follow the runtime's default-plus-alternatives logic, not a count of files in an assets directory.

## 3. Interface findings

| ID | Verified source fact | Product implication |
| --- | --- | --- |
| F01 | [Home catalog, lines 521–597](../../../../app/ui/home.gd#L521-L597), constructs a VBox and one text button per Roster ID | Good simple list for the existing fleet; no visual comparison grid, Home search, type/source filters or favorites |
| F02 | [Paint row, lines 540–557](../../../../app/ui/home.gd#L540-L557), and [visibility/label update](../../../../app/ui/home.gd#L1590-L1640) provide direct paint access on the Vehicles page | Do not claim paint selection is absent; make exact skin identity visible on Flight and the selected pane too |
| F03 | [LiveryPicker, lines 58–136](../../../../app/ui/livery_picker.gd#L58-L136), already creates static named cards, marks the selection and loads one image per frame | Reuse its selection/focus model; it still creates all controls and eventually loads all available thumbnails, rather than a visible-window budget |
| F04 | [Livery choices](../../../../app/render/airplane.gd#L275-L298) look up content-hashed PNGs under assets/ui/liveries; the pinned tree contains 13 Corsair PNGs there | Other built-in/custom choices generally return ID/label without a gallery thumbnail; a thumbnail pipeline is missing across the fleet |
| F05 | [Preview state, lines 1455–1459](../../../../app/ui/home.gd#L1455-L1459), uses generic aircraft loading/failure text while the last model can remain visible | Explicit selected-versus-displayed vehicle/skin labels would avoid ambiguity, including for cars and airships |
| F06 | [AppRoot selection and skin setters](../../../../app/app_root.gd#L1069-L1185) save preferences and preserve separate aircraft/activity/ground/airship routes | Keep these semantics; optimistically changing a label is not proof that a save succeeded |
| F07 | [resolve_livery_choice](../../../../app/render/airplane.gd#L302-L312) canonicalizes the first aircraft choice to empty ID; ground defaults also use empty ID, blimp uses a named default | A new unified UI identity needs a compatibility mapping, not a silent rewrite of old preferences |

The proposed UI is in the [interface specification](ux-spec.md). Existing Workshop library search/favorites provide useful patterns, but their variant-UUID storage constraints do not make them a drop-in stock vehicle catalog. [Workshop](../../../AIRCRAFT-WORKSHOP.md) and [Creator](../../../plans/aircraft-creator.md) retain imported-content admission and test-flight boundaries; saved Creator content must not be assumed Home-flyable because it has a thumbnail.

## 4. Actual vehicle and skin request path

1. AppRoot.set_aircraft/set_vehicle updates Home and preferences, then calls HomeScene.request_aircraft. AppRoot.set_livery also calls request_aircraft, including for stock material-painted cars and aircraft. See [root setters](../../../../app/app_root.gd#L1069-L1166).
2. HomeScene increments generation, records requested vehicle/skin and invalidates obsolete consumers. Its key is vehicle ID, with a skin suffix when non-default. A retained key shows immediately. A miss publishes loading status and waits through two frame boundaries before requesting resources. See [request path](../../../../app/ui/home_scene.gd#L317-L366).
3. HomePreviewResources resolves a selected GLB path, starts ResourceLoader.load_threaded_request with subthreads false, polls, and retains at most two completed PackedScenes. It has one active request and only the latest queued replacement. Stale/failed terminal work is collected; ordinary cancel drops consumers, not underlying I/O. See [broker](../../../../app/ui/home_preview_resources.gd).
4. On completion, [HomeScene._build_requested_preview](../../../../app/ui/home_scene.gd#L434-L485) still calls the complete visual builder on main. It yields between model, presentation and geometry phases; there is no yield inside the monolithic builder call itself.
5. [AirplaneBuilder.build](../../../../app/render/airplane.gd#L39-L217) resolves and validates model provenance/dependencies, chooses/builds the visual, validates derived bindings, reads aircraft data, applies customization/materials and custom paint where applicable. ImportedModel loads its generated geometry script and scene and instantiates it before building bindings ([lines 17–35](../../../../app/aircraft/imported_model.gd#L17-L35)). A resource cache hit does not remove these later stages.
6. Home computes pose/framing, shadow geometry and potentially night-light layout, then publishes the prepared model. [show_aircraft](../../../../app/ui/home_scene.gd#L194-L255) hides/disables the prior root and evicts an LRU entry above three. Cache entries are vehicle/skin combinations, not necessarily three different airframes.

The current asynchronous route is therefore real and worth retaining. The central remaining question is which of its later stages dominates on the pinned engine and target host. It would be inaccurate to assert that every switch is a synchronous disk load, or that asynchronous ResourceLoader automatically removes model construction, validation and GPU costs.

## 5. Loading findings and investigation priority

| ID | Source and observation | Classification and next action |
| --- | --- | --- |
| F08 | HomeScene uses one cache entry per vehicle/skin and builds a missed pair through the full visual path | Verified structure. Pilot same-geometry material transactions; no claimed current speedup |
| F09 | [HomePresentation.hull_rest](../../../../app/ui/home_presentation.gd#L77-L140) scans mesh vertices for gearless presentation; [ProjectedShadow.collect](../../../../app/render/projected_shadow.gd#L37-L78) collects geometry | Verified work, unmeasured current cost. Attribute and evaluate generated immutable outputs |
| F10 | [HomePreviewGeometry](../../../../app/ui/home_preview_geometry.gd#L6-L119) caps copied input at 96 MiB and aims for 3,000 µs snapshot slices, but one surface read is indivisible and compute creates additional point/triangle arrays | The cap is not total preview/job/process RAM. Measure temporary peaks and per-surface maxima |
| F11 | [Home flight preparation](../../../../app/ui/home_flight_preparation.gd#L70-L102) waits 350 ms after settled Home, then pauses broker admissions while a dedicated scene load runs; completion owns unpause ([157–171](../../../../app/ui/home_flight_preparation.gd#L157-L171)) | Source-proven scheduling dependency, not measured delay. Test suppressing NEW speculation during browsing; preserve drain and launch adoption |
| F12 | Broker admissions pause includes even cached/procedural callbacks because their builders may load shared resources ([82–92](../../../../app/ui/home_preview_resources.gd#L82-L92)) | Do not “fix priority” by enabling unsafe concurrent construction. UI metadata/static feedback must remain independent |
| F13 | Home preparation keeps touching the common flight scene in the two-resource LRU; model instances separately retain dependencies | Two entries do not mean two uniquely allocated models. A byte ledger must represent shared owners and adopted jobs |
| F14 | [VehiclePaint.apply](../../../../app/render/vehicle_paint.gd#L62-L119) starts from origin materials, duplicates paints and loads referenced textures; it mutates matching surfaces during the traversal | Useful foundation, not a complete atomic reusable-appearance service. Handle material_override and preserve full fallback |
| F15 | [CustomSkin.choices](../../../../app/aircraft/custom_skin.gd#L129-L178) scans files and invokes archive inspection without texture decoding; [inspection](../../../../app/aircraft/custom_skin.gd#L314-L396) still reads archive/PNG bytes, checks dimensions and hashes content | “Names only” is not a cheap index. Build metadata at import/admission, maintain revisions and revalidate actual content at use |
| F16 | [CustomSkin.apply](../../../../app/aircraft/custom_skin.gd#L181-L238) requires a separately constructed validated stock model and prepares all changes before applying them; PNG decoding/mips and ImageTexture creation are additional work | Preserve atomicity/base identity. Do not run arbitrary current renderer/model operations on a worker or bypass admission for a cache hit |
| F17 | Current custom skin limits are 32 MiB archive, 16 MiB PNG, 4096² combined pixels, 32 installed choices and 128 scanned directory entries ([constants](../../../../app/aircraft/custom_skin.gd#L22-L28)) | These are safety/format limits, not a scalable metadata catalog or complete RAM budget. Do not raise them casually |
| F18 | [Registry](../../../../app/aircraft/model_registry.gd#L67-L95) already verifies only the selected alternate livery and avoids uploading unselected GLBs in package-proof checks ([363–378](../../../../app/aircraft/model_registry.gd#L363-L378)) | Preserve this useful optimization. Validation is not automatically the first bottleneck to remove |
| F19 | [Car launch](../../../../app/app_root.gd#L827-L873), [airship](../../../../app/app_root.gd#L900-L937) and [multirotor](../../../../app/app_root.gd#L964-L1002) drain Home preparation before reading some selection/settings values; Home emits their signals without a captured tuple | Source-visible launch identity gap; changing Home during the await can change later reads. Add immutable intent before waiting and a controlled-drain regression; no runtime reproduction is claimed here |
| F20 | Home resolves an unavailable skin to its default and [start_flight resolves it again](../../../../app/app_root.gd#L1379-L1380) after copying preferences | Exact-appearance guarantees require desired/effective/displayed identities and revision checks; absent skins must not silently become a default under stale UI identity |
| F21 | [Selection setters](../../../../app/app_root.gd#L1069-L1166) synchronously invoke full [preference validation](../../../../app/app_state/preferences.gd#L285-L355) and [verified temporary/backup publication](../../../../app/app_state/preferences_file.gd#L155-L218) | Additional cost boundary, not a measured bottleneck. T20 profiles validation/write/recovery separately; no-op/coalescing must preserve full state, all-writer order, durable-state checks and error semantics |
| F22 | [Creator's GLB policy](../../../../app/workshop/creator/glb_preflight.gd#L8-L60) admits only two named scalar material extensions; [required/used extension checks](../../../../app/workshop/creator/glb_preflight.gd#L234-L251) refuse other extensions | Engine capability does not imply product admission. BasisU, Draco, EXT meshopt, quantization, material variants and progressive LOD cannot simply be enabled for arbitrary user GLBs; qualify stock derivatives separately |
| F23 | [Jet import recipe](../../../../app/assets/aircraft/avanti-s-a200/avanti_s.glb.import#L28-L45) and [F4U recipe](../../../../app/assets/aircraft/f4u-corsair-250/f4u_corsair_three_tone.glb.import#L28-L45) use embedded-image mode `2`, generated LODs and forced-disabled mesh compression | Pinned [GLTFState](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/modules/gltf/doc_classes/GLTFState.xml) confirms mode `2` means BasisU. Recipes do not establish actual fresh-export formats, elapsed transcoding or residency; T16/T18 require inventory and matched experiments |
| F24 | [Debug bridge pipeline monitors](../../../../app/debug/debug_bridge.gd#L1723-L1728) aggregate five compilation categories in frame history | Existing diagnostic lead for T19. A sum/delta does not identify the responsible category or its elapsed CPU/GPU time; add scoped detail only if needed for attribution |

Prefetch, extra workers, larger caches and GPU warmup are experiments after attribution. The strongest direct code opportunity is avoiding unnecessary full visual preparation for a proven-compatible appearance change. The next opportunities are generated preview data and a scheduler that does not start low-priority flight preparation during active catalog use.

## 6. Historical evidence: useful, but not the current benchmark

[UI-05-R3, 2026-10-14](../UI-05-R3/README.md) measured Godot 4.7.2, Compatibility, RTX 3090/NVIDIA 610.88, 1280×720, evening defaults and Dummy audio. Five fresh processes per variant and 20 later warm samples per aircraft were used. Fresh process did not mean cold OS/driver caches.

| Historical candidate result | Extra first visit | Jet first visit |
| --- | ---: | ---: |
| Selection-handler median | 1.68 ms | 1.51 ms |
| First-feedback median | 8.67 ms | 6.44 ms |
| Requested-preview-ready median | 427.51 ms | 1,604.27 ms |

The historical report records the jet's worst first-visit frame interval as **1,173.92 ms**. It also reports a separate attribution run with resource loading at **716.22 ms** and scene instantiation at **0.55 ms** before remaining adapter/shadow/night work. The report's linked profile.log is absent from the pinned Git tree, so this review relies on the published report rather than independently inspecting that raw attribution trace. These observations are not additive terms from one measured switch, and the reported tiny instantiation value argues against assuming instantiate is dominant without a new trace.

[UI-05-R2](../UI-05-R2/README.md) already established useful recent-model reuse with explicit count/memory limitations. Later [Home preparation evidence](../UI-34c-R5/menu-preparation-2026-10-25/README.md) concerns Fly readiness after Home dwell, not skin-switch latency. Its published improvements cannot be reused as measurements for this proposal.

Current Godot 4.8-beta2 timings, current whole-fleet worst cases, native 1080p behavior, GPU residency and the user's hardware are **unmeasured in this review**. The [benchmark protocol](benchmark-protocol.md) closes those gaps before adopting performance claims.

## 7. Concrete changes justified by this audit

The [plan](../../../plans/vehicle-selection-performance.md) orders immediate identity/skin clarity, current-source measurements, a small material-only pilot and a browsing-aware scheduling experiment before broader caches. A metadata/thumbnail pipeline supports the larger catalog independently of full 3D loading. Memory admission and import revision handling precede neighbor prefetch and persistent derived-asset retention.

Preserve current latest-generation, validation, save, cancellation, independent flight build and controller contracts. Main-thread CPU work, GPU upload, driver/pipeline compilation, cache lifetime and user-import processing are different costs; each needs its own evidence. No code defect, exact runtime speedup or universal RAM/VRAM budget is inferred merely from a long function or a limited cache count.

The expanded research separates work admission, retention admission and peak reservations; makes proxy/full readiness explicit; and adds conditional package, geometry, persistence and retirement comparisons. [T01–T20](techniques/README.md#the-twenty-investigations) are research mechanisms, distinct from these F01–F24 source findings.
