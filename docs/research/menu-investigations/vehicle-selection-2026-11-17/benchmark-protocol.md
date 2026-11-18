# Measurement and verification protocol

**Proposed acceptance work for UI-VS, 2026-11-17.** This file specifies future measurements; none of the runs below was performed for this documentation branch. [Current evidence and historical limits](code-audit.md). [Implementation steps and targets](../../../plans/vehicle-selection-performance.md).

Expanded after [twenty targeted investigations](techniques/README.md). Use the smallest comparison that resolves a measured uncertainty. Conditional experiments are not a requirement to implement every technique or run every combination.

The [deeper source analysis at a7de9b3](deep-code-analysis.md) adds D01–D14 and E19–E32 below. Those experiments distinguish verified call/asset counts from unmeasured elapsed costs. The source pin for each report remains explicit; do not profile the older documentation-branch runtime while labeling it newer main.

## 1. Reuse the existing measurement routes

Read the [tool index](../../../tools/README.md) and the relevant host-admission guide before running the application. Use an isolated source snapshot and profile. On enrolled hosts, reserve the required test-queue session and retain its ownership handle through teardown; do not overlap performance campaigns with other engine/asset-generation work. Follow the repository's U-drive cache/temp policy on the Windows host. This cloud source-only review did not reserve or launch a native session.

| Existing tool or evidence | Use and limits |
| --- | --- |
| [Debug bridge](../../../../tools/debug/README.md) | Actual menu selection, catalog/skin state, native screenshots, frames, timeline, profile, object inventory and lifecycle scenarios; prefer it over coordinate automation |
| [UI-05-R3 evidence](../UI-05-R3/README.md) | Prior selector observer and its correction for the final blocking frame; adapt its instrumentation to current source instead of inventing another framework |
| [Home/Fly loading probe](../../../../research/performance/README.md#homefly-loading-and-lake-geometry) | Current fixed-wing Home→Fly→Home and dwell/preparation controls; rejects headless; does not currently measure every vehicle/skin path |
| [Resource sampling](../../../../tools/godot/README.md) | OS RSS, CPU/I/O where supported and system available memory; verify PID, timestamp coverage and missing counters |
| [Texture inventory](../../../../research/performance/README.md#runtime-texture-inventory-vq-02a) | Existing runtime/import tools for actual formats, dimensions, consumers and estimates; use current pinned engine/source, not a stale example version |
| [Checked runner and test pool](../../../tools/shared.md#one-godot-script) | Targeted behavioral/parity checks; headless passes are not rendered latency or GPU evidence |

Do not change hashed production builders just to insert timing probes without regenerating their owner-controlled manifests. Use the existing external observer/debug seams, or add reviewed diagnostic spans in the owning slice and regenerate any affected identity through its pipeline. Record observer overhead with a no-observer control.

## 2. Define the endpoints

| Metric | Start and end | Important distinction |
| --- | --- | --- |
| Acknowledgement | Actual recognized selection event → first rendered frame carrying the requested vehicle/skin label/marker | Updating a Label or returning from the handler is not a drawn acknowledgement |
| Static preview | Selection event → first frame showing the correct thumbnail or explicitly labeled old preview | Useful feedback before detailed content; not detailed-preview readiness |
| Optional proxy | Selection event → first visible frame of the correct declared lightweight representation | Separate asset/tier endpoint; neither a thumbnail nor proxy counts as full detail; total full-ready cost is still reported |
| Queue wait | Selection request → admission of its resource/appearance work | Split waits behind obsolete loads and idle flight preparation |
| Resource ready | Accepted load request → terminal successful collection | Excludes later construction, GPU work and final image |
| Detailed preview ready | Selection event → first rendered frame of the requested vehicle + skin + revision | Check identity and readiness together; do not count the old model or a placeholder |
| Skin ready | Explicit skin activation → first frame of that exact appearance on the selected vehicle | Separate retained-material hit, texture miss, raw custom decode and full-GLB route |
| Launch acknowledgement | Accepted Fly/Drive → first matching loading/transition feedback | Distinguish aircraft staged route from current activity routes |
| Launch readiness | Accepted action → validated candidate, first complete draw and active control readiness | Paused/recovery first draw is separately labeled; loading time is never integrated as simulation time |
| Frame hitch | Consecutive rendered frame interval during complete request/commit/retire window | Continue observation beyond completion to include final construction and deferred disposal |
| Memory peak/plateau | Before request through candidate installation and retirement/drain | Peak overlapping ownership differs from retained steady cache; RSS is not VRAM |
| Selection persistence | Selection event → validation/serialization/publication spans and matching durable-generation acknowledgement | Separate in-memory selection from storage; no-op checks include full payload/commit semantics; pending/failed saves are not durable success |

Use monotonic engine time for local phase spans and record its mapping to external sampler timestamps. Software event-to-frame_post_draw is not physical mouse/controller-to-scanout latency. Report that boundary explicitly; real device/display latency needs its own hardware method.

### Minimum phase spans

Record catalog/index lookup, custom-skin inventory/admission, registry/provenance checks, broker queue wait, disk/resource load, script/resource dependency preparation, scene instantiation, visual adapter/bindings, paint/texture decode and mip generation, material creation/apply, pose/framing, shadow collection, night-light fitting/snapshot/worker, tree attachment, first requested draw, preference save and old-node/resource retirement. Mark unavailable/uninstrumented stages rather than assigning their time to “disk.”

For D01–D14, add spans only where the candidate needs them: statistics reduction versus history copying; selection UI/catalog/layout passes; initial Home refresh; alias comparison versus archive inspection; projector allocation versus redraw; rig finite checks versus sampler construction; procedural UV adaptation; and repeated paint/proof validation. Preserve an event timestamp **before** skin resolution and synchronous Home work. At a7, the existing AppRoot `_loading_started_usec` begins after livery resolution, so its `feedback_usec` cannot alone establish complete action-to-feedback latency (D04). Separate the numeric-worker queue reason from the flight-scene loader safety gate (D09).

Capture asynchronous start/end events with request generation and content identity. Do not sum overlapping resource, numeric and render work; retain both critical-path elapsed time and exclusive CPU spans. An outer 3 ms scheduler budget does not prove that a single surface read or upload respected it.

For dependency attribution, compare a recursive static resource inventory with actual dynamic paths requested during build, paint and first draw. Record path aliases, source/dependency revisions, request/collection counts and owner handoffs. Static enumeration alone does not prove all work is covered. For cooperative preparation, record per-slice CPU and the largest indivisible operation; prove an actual next-frame boundary rather than a chain of same-idle deferred calls.

For retirement, observe Node release, retained references, queued roots and aggregate memory separately. Qualify a conservative per-renderer observation window and bounded retirement allowance. No exact per-resource GPU reclamation signal is assumed. Test pressure/timeout fallback without treating timeout as freed bytes or blocking navigation forever.

## 3. Per-run identity and event record

Keep one small run manifest with source commit plus scoped diff, engine full version/hash, source/asset/import hashes, export/package identity, machine/OS/CPU/RAM/GPU/driver, renderer, actual viewport resolution, MSAA/quality/lighting/landscape, audio/input mode, isolated profile, observers, temperature/power state where relevant and competing workload disclosure.

Each selection record should contain run ID, sequence/generation, intent kind, source-qualified vehicle ID/revision, desired and effective skin IDs/revisions, displayed tuple before/after, timestamps for each phase, cache outcome, queue reason, canceled/failed/superseded flags, failure stage, admitted/reserved byte estimates and current ownership counts. Store native resource units explicitly: microseconds versus milliseconds, bytes versus MiB. A deleted/mismatched revision is not a successful cache hit.

Add only the diagnostics needed by a candidate: card binding generation and live-card count; actual encoded/decoded/GPU formats and unique owners; retention admission versus work admission; useful prefetched adoption before demand, late adoption, bytes/work discarded and eviction-caused reload; full-settings generation, writer count and durable generation. Report cache benefit as work/latency avoided on real demand, not only hit percentage. Pipeline compilation counter deltas are correlation, not a time measurement; the current debug bridge sum needs per-category detail if attribution requires it.

Deep-review counters are scoped by route and state: copied history records; query/summary cache misses; full catalog row visits and pending/executed layout calls; skin enumerations by family; alias file hashes and inspected archive bytes; candidate generations/build starts; projector/viewport IDs; layout snapshots/worker submissions; registry/structural/proof calls; compiled car samplers; remapped paint vertices/LODs; and paint passes. Count unique allocations separately from calls that may hit engine caches. Compare whole-request CPU and elapsed time without summing nested counters or overlapping work.

Reports include raw sample links/hashes, sample count, median, p95/p99 where sample size supports them, maximum, and counts of frames above 33/50/100 ms. Separate canceled and failed selections from successful latency distributions but report their counts and user-visible recovery. A lower average can hide one second-long freeze.

## 4. Cache and cold-state matrix

| State | How to establish/report it |
| --- | --- |
| First process, imported resources available | Fresh application/profile and exact import artifacts; declare OS/driver caches uncontrolled unless deliberately isolated |
| First vehicle visit within process | Select an item not yet requested/retained; account for shared textures/scripts loaded by earlier items |
| Resource retained, no preview node | Controlled fixture retains PackedScene through the existing broker and forces a node miss; keep validation equivalent |
| Preview node retained | A→B→A while A remains in the three-entry baseline cache |
| Post-eviction miss | A→B→C→D→A, including different skins competing for existing entries |
| Same geometry, cached skin | Same vehicle, accepted material/texture identity retained |
| Same geometry, uncached skin | Different texture/decode state with the geometry retained |
| Shader/pipeline first use | Record actual driver/cache state; do not infer it from a fresh process |
| New import/revision | First admitted content version, missing derivative cache, same-path replacement adversary and repaired index |

Do not clear the user's system/driver cache to manufacture “cold” results. Use an isolated profile/machine if true shader-cold testing is required. Import/source-editor preparation and shipped package startup are separate workloads.

## 5. Ordered experiment matrix

Change one material mechanism per candidate and alternate baseline/candidate order on the same host. Keep baseline asset bytes and settings constant except for the explicitly tested pipeline change.

| Experiment | Compare | Cases and decision |
| --- | --- | --- |
| E0: current-source attribution | Existing main, no optimization | All 13 stock vehicles; named heavy imported jet, procedural Stik/Extra, gearless MoonRunner, helicopter, quad, blimp, both cars; day/night and both landscapes |
| E1: compatible skin pilot | Full preview rebuild vs transactional material route | One car, then aircraft; default→A→B→default; material hit/texture miss/custom failure; accept only independent-instance and visual parity |
| E2: admission policy | Current scene_trim vs browsing-aware vs off | 0/350/750 ms intent dwell, active flight-scene drain, rapid return and immediate Fly/Drive; measure saved/delayed work and total readiness |
| E3: generated preview outputs | Current scans vs validated generated data | Gearless pose, helicopter support, imported/procedural shadow/night layouts; invalidation and runtime fallback |
| E4: memory policy | Existing count bounds vs byte admission with same fallback caps | A→B→C→D→A, many skins, tight synthetic budget, real low-memory host; old+candidate+temporary overlap and retirement |
| E5: catalog rendering | Current/simple native list vs pooled grid/list | 13, 100 and 1,000 metadata descriptors; long names/locales, search/filter/focus, missing thumbnails; no full-model creation during enumeration |
| E6: asset format/tier | Original import vs one generated candidate tier/format | Actual texture formats, dimensions, mips, quality, disk/import/package bytes, CPU load and GPU estimates; VQ approval by evidence |
| E7: prediction | Selected-only vs at most one neighbor | Forward browse, reversal, random search, no-hover controller, slow storage and pressure; useful/wasted work, duplicate loads and late callbacks |
| E8: shader preparation | Existing first draw vs bounded selected-path warmup | Only after first-use attribution; real Compatibility and Metal/Mobile paths separately, matching settings and total elapsed work |
| E9: import/index lifecycle | Indexed path vs bounded bootstrap/repair | Legacy .orskin folder, absent/corrupt/stale index, external file replacement/removal, interrupted derivative write and changed engine/recipe version |

### Targeted comparisons added by the twenty investigations

| Experiment | Compare | Cases and decision |
| --- | --- | --- |
| E10: dependency ownership | Baseline traced closure vs one justified early dependency preparation, through the existing owner | Dynamic paths, aliases, duplicate consumers, same-path incompatible options/revisions, stale/failed terminal collection, Home exit and immediate launch; accept only exact identity, balanced tokens and reduced complete wait |
| E11: retention admission | Current recency vs minimal probation/protected retention, with equal byte and count caps | Sequential full selections, frequent A revisits, delayed second access, skin churn, large entries; exclude metadata-only scroll from full-cache traffic; measure work avoided, eviction reload and bookkeeping |
| E12: reuse and retirement | A controlled 2×2: current retention vs one safely transferred root across Home recreation; current retirement vs pacing independent roots | Home return, launch overlap, failure, stale completion, materials reset and 20+ cycles; preserve total caps; identify each effect separately; reject moved hitches, pressure or owner leaks |
| E13: derivative publication | Current admitted path vs one immutable, content-keyed derivative generation | Same-path replacement with old owners, missing dependency, corrupt/interrupted generation, recipe/engine change, concurrent index refresh and clean export; distinguish visibility, process crash and power-loss guarantees |
| E14: package locality | Current package layout vs measured family grouping; then a separate matched compression comparison | Same closure/quality, actual file reads/seeks where measurable, decode/staging/upload, first draw, package/update bytes and peaks; no assumption that pack size equals loaded residency |
| E15: progressive preview | Thumbnail→full vs thumbnail→separate proxy→full | One measured heavy vehicle, correct skin, immediate launch, rapid abandonment, low memory and warm cache hit; useful proxy time, full-ready/launch time and combined cost; no fixed animation floor |
| E16: geometry delivery | Current owner-generated asset vs one change in mesh representation, complexity or eligible structure | Named nodes/hinges, skin slots, crash mappings, bounds and validation parity; nodes/surfaces/vertices, decode/instantiate, largest surface read, draw and memory; preserve Creator admission |
| E17: persistence | Existing transaction vs full-state/durable-state no-op detection; only then conditional generation-safe coalescing | Fast vehicle/skin changes; older queued snapshot overlapping another settings writer; external deletion/corruption/replacement after success; failed/pending retry, Home exit, launch, Quit, interrupted publish and restart; verify full payload, conflicts and recovery |
| E18: cooperative finalization | Existing preparation vs one measured phase split at safe boundaries | Large indivisible surface, cancellation between phases, stale generation, rollback, main/worker ownership and final draw; per-slice/max CPU, total elapsed and temporary peak; reject cosmetic yielding |

### Targeted comparisons added by the deeper code review

| Experiment | Compare | Cases and decision |
| --- | --- | --- |
| E19: compact Home statistics (D01) | Full query payload vs existing summary API, preserving service compatibility | Empty/large valid ledger, cold/warm, aircraft/activity, aliases, active time, flush/rollback/read-only/reset/delete and Statistics return/translation; parity of five rendered fields, no warm history copies, count remaining cold reductions |
| E20: identical pending intent (D02) | Current cancel/restart vs exact-revision pending-intent coalescing | Repeat A at each yield/load/build stage and completion inside callback gap; A→B→A, failure→Retry, save failure, same-path replacement and Home detach; no lost explicit selection/save semantics, balanced terminal collection |
| E21: selection UI invalidation (D03) | Current catalog/text/layout chain vs one dirty-state transaction | Catalog and arrow routes separately; 13/100/1,000 metadata rows, focus/scroll, notice/save errors, locale/text scale, resize and roster change; row/call counts plus actual first feedback/layout work |
| E22: empty skin resolution (D04) | Current enumeration vs empty-ID return with independent later validation | Default/named/custom, 0/32 installed skins, malformed unrelated archive, invalid chosen model and route guards; identical default output, rejection parity, pre-feedback bytes/work and true event-to-draw interval |
| E23: Home initialization (D05) | Default-then-actual refresh vs one installed selection/preferences snapshot | Default/other aircraft, saved activity, missing skin, directory revision, service installation and Home recreation; correct first tuple/focus, enumeration count; isolate effect from E22 |
| E24: alias inventory reuse (D06) | Repeated equality/path checks vs one bounded verified inventory transaction | 32 identical duplicate pairs, conflicting aliases, mutation/removal, invalid entries, first-32-valid order and 128-entry limits; accepted IDs/errors, hash/read/temp bytes and peak snapshots; no trusted mtime shortcut |
| E25: projector lifetime (D07) | Recreate on each bind vs same-binding fast path; separately, one reusable Home projector | Retained A→B→A, same A, shape/skin/light change, policy off/on, stale source and Home exit; instance/allocation/redraw counts, exact shadow and observed retirement/peak; no per-vehicle viewport pool |
| E26: early light-layout lookup (D08) | Current compute-then-lookup vs qualified early and late lookup in every route | Production async night and direct-show/no-worker paths; exact-asset/equivalence hit, changed vertices with same transforms/counts, pose/hash/anchor change, eviction/cancel; job count and final attached kit/layout; unproven variants use async/synchronous fitting and retain their result through attachment |
| E27: numeric-stage barrier (D09) | All-miss worker wait vs reservation-qualified wait only at numeric stage | Controlled obsolete worker then car/quad/day/night/retained requests, lighting change, reversal and teardown; queue reason, frame cadence and old-snapshot+candidate peak; preserve independent scene-loader safety gate |
| E28: scoped validation evidence (D10) | Existing repeated checks vs one internal immutable input/byte context | Structural/registry/source read counts; public calls, mutable builder input, normalization, closure cycles, missing/corrupt/replaced files and bad derived nodes; exact acceptance/diagnostics, no global path-success cache |
| E29: presentation package proof (D11) | Fresh proof closure each build vs qualified immutable package attestation | Fresh/repeated selection, source vs export, engine/proof/list/package change, missing/corrupt proof or compiled resource and altered companion; keep selected companion checks, bounded retention and failure parity |
| E30: parked Monster Car construction (D12) | Full builder vs preview mode that omits only unused samplers/driving structures | Same validated rig/node/paint output, stock skins, repeated visits/eviction, immediate Drive and Home return; preserve all finite checks in first candidate, corrupt-input refusal and driving articulation |
| E31: procedural paint geometry (D13) | Per-custom-skin adaptation vs one proven immutable mesh/UV derivative | Extra/P-51/Timber pilot; Stik no-clone control; custom A→B→default, two instances, all LODs/Extra original UVs, source/adapter change and eviction; private materials, peak/retained bytes and complete readiness |
| E32: HX-700 stock paint (D14) | Base pass then selected pass vs one base-plus-stock-skin pass | All named stock skins, default/custom, direct builder consumers, Low/higher detail, blade/blur appearance and independent instances; paint/material/texture calls, preview and flight/export parity |

Choose E19–E23 as small immediate-path screens where applicable, then the attributed presentation/build cases. E28/E29/E31 require owner-approved identity or generated-output designs; a source count alone does not authorize their implementation. E25 contains two sequential experiments, not a bundled claim. E30's first candidate deliberately retains rig validation. After each accepted screen, qualify the relevant complete flow; do not run a Cartesian product of E0–E32 across all hosts and assets.

| Research coverage | Experiment ownership |
| --- | --- |
| T01 / T02 | E5 catalog; E9 published metadata and repair |
| T03 / T04 / T05 | E15 proxy; E1 appearance; E3 generated outputs |
| T06 / T07 / T08 | E0/E10 dependencies and owner; E2/E7 duplicate-consumer cases; E18 safe slices |
| T09 / T10 | E2 browse admission; E7 prediction |
| T11 / T12 / T13 | E11 retention; E4 reservations; E12 reuse/retirement |
| T14 / T15 | E9/E13 publication; E14 layout/compression |
| T16 / T17 / T18 | E6 separate texture-format and tier candidates; E16 geometry |
| T19 / T20 | E8 first-use rendering; E17 persistence |

Run E0 to choose the critical stage, then the relevant narrow screen. E1/E2, the catalog contract, the smaller deep-review slices and required identity regressions are early candidates. E7/E8 and E11–E18 remain conditional except for correctness cases required by a changed storage/ownership path. After accepting a local change, qualify the affected complete flow and required target cases. E12's planned factorial comparison is an exception to one-factor screening because it measures two separate, potentially interacting effects under controlled caps.

Use five alternating fresh-process pairs and at least twenty warm transitions per representative case for screening, retaining every sample. Those small screens are descriptive, not reliable tail qualification. For final p95 gates collect at least thirty first-visit repetitions per gated vehicle/host case and at least two hundred warm/burst transitions across repeated runs; report tail uncertainty and maxima. Escalate sample count only when variation or a failed/inconclusive gate requires it. A 20-cycle lifecycle loop checks bounded ownership; it is not a long-duration soak qualification.

For catalog logic, 100/1,000 synthetic metadata records are legitimate fixtures. They do not prove the memory behavior of 100 distinct heavy assets. Add a library of admitted real/generated imports with varied node/surface/texture complexity and known content identities, then traverse it under bounded admission. Oversized or unknown-budget entries must exercise the documented thumbnail/fallback path. Do not weaken importer limits to make the fixture pass.

## 6. Existing reproducible launch probe

The existing [loading_probe.gd](../../../../research/performance/loading_probe.gd) accepts fixed-wing IDs, cycles from 1 to 50, dwell from 0 to 30,000 ms, and preparation modes off/scene/trim/scene_trim. Native Home currently defaults to scene_trim and 350 ms; the probe itself defaults to off, so specify the intended control explicitly. It is a launch-regression companion to selector measurements, not a skin benchmark.

Example on an admitted Windows native session, from the isolated repository root; create a fresh output parent first and never overwrite an earlier output/settings sidecar:

~~~powershell
& .tools/Godot_v4.8-beta2_win64_console.exe --path app --audio-driver Dummy --resolution 1920x1080 --windowed --script "$PWD/research/performance/loading_probe.gd" -- --output="U:/OpenRC-cache/vehicle-selection/run-001/loading.json" --aircraft=sebart-avanti-s-a200-p100rx --start=airborne --input=keyboard --cycles=5 --dwell-ms=0 --prefetch=scene_trim --prefetch-delay-ms=350
~~~

Verify recorded viewport_size and actual renderer. Repeat with the named candidate, matched dwell/settings and explicit audio mode. Use the documented checked runner and host reservation around it as required by that host. Do not compare Dummy-audio timings with an audio-enabled run as though only the selection change differed.

For selectors and non-aircraft activities, extend the existing observer/debug scenario to issue real UI activation or its documented native input route. Clearly label signal-based automation if used: it does not measure hardware input latency. Do not invent unsupported flags for loading_probe or silently route a car through its fixed-wing guard.

## 7. Targeted behavioral regressions

| Existing tests / boundary | Required additions for the relevant implementation slice |
| --- | --- |
| [test_ui_preview_resources.gd](../../../../app/tests/test_ui_preview_resources.gd) | One request/terminal collection per path, failed/invalid status, deduplication, aliases, paused admission, stale completion, owner teardown and adopted ownership |
| [test_ui_preview_requests.gd](../../../../app/tests/test_ui_preview_requests.gd) | Vehicle and skin A→B→A, old-image label, late failure/success, detached/replaced Home, filter/close, immediate launch and failed-launch recovery |
| [test_ui_home_preview_cache.gd](../../../../app/tests/test_ui_home_preview_cache.gd) and [test_home_preview_geometry.gd](../../../../app/tests/test_home_preview_geometry.gd) | Pinning/reservations/eviction, snapshot plus compute peak, generated fallback/equivalence, slow indivisible surface and disposal ownership |
| [test_vehicle_paint.gd](../../../../app/tests/test_vehicle_paint.gd), [test_aircraft_liveries.gd](../../../../app/tests/test_aircraft_liveries.gd), [test_custom_skin.gd](../../../../app/tests/test_custom_skin.gd), [test_skin_fleet.gd](../../../../app/tests/test_skin_fleet.gd) | A→B→default and custom↔stock, missing target/texture rollback, alpha/emission/night variants, procedural adapters, independent instances and matching launch appearance |
| [test_livery_picker.gd](../../../../app/tests/test_livery_picker.gd), [test_ui_home.gd](../../../../app/tests/test_ui_home.gd), [test_ui_home_layout.gd](../../../../app/tests/test_ui_home_layout.gd) | Visible-row/image bounds, selected/default/error cards, no build on focus, recycled binding tokens, controller/native focus, empty results and locale/text reflow |
| [test_home_vehicle_roster.gd](../../../../app/tests/test_home_vehicle_roster.gd) and [test_aircraft_catalog.gd](../../../../app/tests/test_aircraft_catalog.gd) | Stock IDs remain stable; namespaced imports cannot collide or spoof readiness/adapter; aircraft-only consumers stay aircraft-only; future family adapters are explicit |
| [test_home_flight_preparation.gd](../../../../app/tests/test_home_flight_preparation.gd) and root activity-route tests | No new speculation while browsing, active job drains before gate release, adopted work not duplicated/evicted, cancel/Quit; snapshot activity tuple before awaiting drain |
| Preferences/skin selection through Home/root | Legacy empty/default IDs and aliases, wanted/effective/displayed identity, missing skin on restart, save failure/retry and file replacement between selection and launch; if persistence changes, concurrent full-settings generations, bounded unsaved age, checkpoint semantics and interrupted publication recovery |
| [test_ui_statistics.gd](../../../../app/tests/test_ui_statistics.gd), [test_flight_statistics_lifecycle.gd](../../../../app/tests/test_flight_statistics_lifecycle.gd), [test_statistics_delete_commit.gd](../../../../app/tests/test_statistics_delete_commit.gd) and Home tests | D01 compact-field parity, live-time tolerance, availability/flush/reset/delete, query-only compatibility if retained, actual activity identity on translation and refresh after Statistics return |
| [test_procedural_skin.gd](../../../../app/tests/test_procedural_skin.gd), [test_presentation_sources.gd](../../../../app/tests/test_presentation_sources.gd), model/vehicle owner suites | D10–D14 public validation and diagnostic parity, mutable/replaced inputs, proof-package completeness, LOD/UV/material independence, preview-only car behavior, direct helicopter builders and actual activity launch |

A specifically required activity case is **Drive car A with skin X → hold a controlled preparation drain → change Home selection/skin → release drain**. The launched activity must use the original accepted tuple, or explicitly refuse/recover; it must not silently pick a later Home value. Repeat for airship and multirotor settings and failure paths. Current activity construction is not automatically the aircraft staged route; the source gap and proposed repair are recorded in the plan.

For immutable content, keep exact admitted bytes/revisions through preparation or recheck identity at commit. Exercise a custom skin deleted/replaced after its thumbnail appears and after launch activation, and an engine-cached resource replaced at the same path while old owners remain. Either preserve the exact accepted snapshot or refuse with recovery; never silently select a default under the old label.

## 8. Native and package acceptance

Inspect 1920×1080 first on the named desktop target, a modest-memory supported machine and Apple Silicon Mobile where available. Cover 100/150/200% text, EN/ES plus configured-locale/pseudolocalization coverage, mouse, keyboard and selected controller/radio navigation. Test actual screen-reader/native accessibility support separately when available; do not label it passed from accessible-name assertions alone. Then test 1440p/4K reflow/performance, with 720p last.

Cover day/night, Club/Green, opaque/reduced-motion modes, immediate launch during preview loading, repeated activation, Back, cancel, Quit, Home return, invalid resource, missing skin, import revision change and low-memory fallback. Broader shared-root changes require affected ordinary, helicopter, ground, airship, multirotor, Workshop and Natural Random routes with their own admission contracts. Rendering quality changes must preserve physical outputs and do not justify new golden flights.

Repeat the accepted flow in a clean exported package with its correct texture/import variants and included thumbnails/metadata. Source/editor success does not establish packaging or arbitrary user-import support. Retain compact manifests and summaries; keep large raw captures/logs out of Git except where the owning evidence policy explicitly requires them.

## 9. Decision and completion record

For each candidate record the exact input identity, tested matrix, useful/adopted/discarded speculative work, current versus candidate latency distribution, actual observed peak/plateau and visual/behavioral results. Report the improvement as a measured value with its scope; reject candidates whose benefit falls within variation or whose faster preview worsens total launch/startup cost beyond the agreed gate.

Conclude with accepted, rejected or inconclusive status and remaining target-hardware/package limits. A passing source-only test, a populated cache, a smooth spinner, or a lower mean handler time does not establish a responsive complete vehicle switch. Follow the repository's required CI policy when implementing; focused local checks do not bypass required hosted checks.
