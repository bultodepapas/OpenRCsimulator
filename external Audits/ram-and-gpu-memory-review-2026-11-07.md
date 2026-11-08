RAM and GPU memory review — 2026-11-07
Regenerated 2026-11-08 from the retained audit. Measurements and implementation status below describe the original 2026-11-07 snapshot.
Outcome and scope
This review treats memory as a way to avoid repeated work while keeping ownership,
peaks and recovery predictable. Two small production changes preserve that goal:
the existing circuit mesh reuse now has an eviction bound, and cold parked-Stik
detail merging reuses a successfully read shared ORM image within one material.
No physics law, simulation representation, imported asset, texture resolution or
graphics-quality setting was changed.

The strongest additional findings are growing manual telemetry storage and three
4096² Monster Car 2 maps not configured for GPU block compression. The former has a production-component
retention witness; the latter has traced import/engine-format evidence, not a
measured GPU-residency result. Native Windows/Linux graphical and macOS/Metal
qualification remains open. No confirmed regression from previously delivered
work was found.

The two runtime changes and two regressions are published as code-only draft PR #11, commit 7171aef8111aa7005267d3eb2bff64caa311ffdb. The full report, raw evidence and ledger updates are retained in the private audit deliverable; they were not published in that PR.

Baseline: bultodepapas/OpenRCsimulator commit
997e212784dbf873a7b054ddbbc68e7905495adf. Work was isolated on
audit/memory-2026-11-07; unrelated working trees and their changes were preserved.
The GitHub connector was used for repository discovery, source/history inspection,
the exact engine implementation, and baseline CI status. The baseline's CI run
42333181434 passed; that result does not qualify this candidate.

Before delivery, upstream 8306c72f5a141c1261abb46bc3c31cc0d32cda1b was incorporated.
Its CI/export/tool changes do not alter the measured runtime, lifecycle runner or
checked runner; frozen tested-file hashes were rechecked after incorporation.

Read first: consolidated audit queue
and completed work.
The 29 originating external reports were not relabeled or edited. CPU ownership,
GPU/assets and hardware/profiling were reviewed in parallel; a separate independent
reviewer challenged ownership, measurement attribution and claimed benefits.

Evidence and runnable component probes:
audit evidence bundle.
The evidence manifest distinguishes final passes, exploratory failures, source
arithmetic, sampled process memory and unavailable native measurements.
Actual configuration
Topic	Verified configuration and implication
Engine	app/get-godot.sh pins 4.8.beta2.official.cafc17a19; full upstream commit cafc17a192acf67903910a68aeb3c076c0907a4b. The local executable's SHA-512 matched the pinned receipt. Latest/stable manuals are explanatory references; engine-sensitive conclusions were checked against this commit.
Desktop renderer	app/project.godot: Compatibility/OpenGL by default; ARM64 override selects Mobile. docs/STACK.md describes native Metal on Apple Silicon and the renderer guard. Optional High rendering uses Forward+. A quality tier's label does not by itself prove the effective backend.
Platforms	Windows/Linux x86-64, macOS universal Apple Silicon/Intel. Mobile/web are not shipped targets in this review.
Resolution and targets	Repository guidance prioritizes 1920×1080, then higher resolutions, then 1280×720. The project viewport default is not a qualification target. The documented M1/8 GB Mac is a dated test-host inventory, not a certified minimum.
Rendering allocations	4× 3D MSAA; reflection atlas already limited to two slots. Keep these existing decisions when comparing candidate memory.
Simulation	Shared float64 simulation, 240 Hz, RK4, at most 12 catch-up steps. This review keeps solver arithmetic, tick ordering and replay data unchanged.
Local execution	Linux x86-64 headless/dummy rendering and audio; no display or exposed GPU device. The optional native stage library was absent, and lifecycle logs explicitly used the gdscript_reference fallback. Native Home prefetch is disabled headless.


Repository anchors: engine pin,
settings, stack,
Mac test-host guide.
Prioritized findings and audit reconciliation
Priorities order the next engineering work; they are not claims of a crash or a
measured frame-rate defect. “New” means a specific finding added by this review.
Priority	Finding and affected owner	Evidence/status	Action and prior-work relationship
P1	Manual T telemetry grows for the recording duration and survives stop: sim/trace.gd, sim/recorder.gd, sim/rotorcraft_recorder.gd	New; source plus component witness. 34 base fixed-wing or 46 rotorcraft Float64 columns per accepted tick. Fixed-wing CSV export also constructs whole-record strings.	Introduce bounded chunk storage with explicit write/backpressure outcomes and complete-trace recovery. Separate from already-bounded F10 and A24's bundle hashing. Not implemented here.
P1 experiment	Three 4096² Monster Car 2 maps are not configured for GPU block compression	Concrete extension of A26 §2F. Imported RGB8+mips; pinned RD expands RGB8 to RGBA8. Conditional logical total about 256 MiB.	Test platform-correct VRAM compression before considering selective resolution reduction. Actual format, residency, paint/emission/PBR quality and exported behavior still need native evidence.
P2	Session-long ground control history and checkpoint expansion: sim/ground_vehicle/session.gd	New source-derived finding. Four Float64 values per tick; checkpoint also creates byte, numeric and base64 representations.	Preserve exact replay through a versioned segmented tape or bounded disk spool. Do not truncate a ring and claim equivalent checkpoints. Not implemented.
P2 completed	Circuit dirt mesh dictionary had no eviction: vehicles/ground/airfield_track_view.gd	New defensive bound on existing RCV-43 reuse. Distinct caller identities could accumulate; unchanged stock flights normally use one key. No ordinary-cycle leak reproduced.	Implemented two-entry LRU and 4 MiB source-geometry proxy admission. Warm reuse and active-scene ownership verified.
P2 completed	Repeated shared ORM image retrieval during parked-Stik merge: scenery/parked_aircraft.gd	Specific extension of SC-09-R2/A26 transfer work. Two cached variants, nine qualifying aliased materials.	One successful image snapshot supplies both channel means per material. No persistent image cache. Source analysis gives 27→18 non-null texture image requests across the two first merges when shared first reads succeed; not a per-frame saving.
P2 known/open	Stik compact CPU samples, discarded audio loops, cloud readback	Already A28 §§1/2/3/5; A1/A7 cloud ownership.	Keep their existing owners and qualification gates. Retaining an additional 1 MiB Stik CPU sample can be worthwhile; qualify exact texture/skin output and native readback cost before adoption. No duplicate “new finding.”
P2 known/open	Native load readiness, shader work and transition peaks	Already A26 §2F/G, A24; UI-34c preload implemented.	Extend existing probes and byte/pressure admission. Do not add a second scene cache or assume a loaded PackedScene has finished every renderer cost.
P3 hypothesis	Natural Random source cache retains stamped historical keys and full field dictionaries	Unreproduced source finding. Path+length+mtime can miss a same-size/same-time edit. Uncached launch validation rejects mismatches.	Reproduce on disposable data, then compact/bound entries and use exact content identity when required. Inferred impact is stale generation/false refusal, not acceptance of mismatched flight data.


1. Bound manual telemetry without losing the record
Trace._rows appends packed Float64 values; Recorder.stop() saves without
clearing them. FlightRows.rows behaves similarly. Both start methods clear on a
new recording. T-key routes are in app/main.gd and app/helicopter_main.gd.
This is intentional retained ownership, not an unreachable-object leak.

For c columns and accepted tick rate f, raw element storage after simulated
duration t is approximately 8 c f t, plus the initial row. The exact schema can
add columns; array capacity, metadata, allocator overhead and CSV are additional.
Recording/history	Columns	Raw payload per simulated hour at 240 Hz
Fixed-wing base trace	34	224.12 MiB
Rotorcraft trace	46	303.22 MiB
Ground control tape	4	26.37 MiB


These are arithmetic projections, not one-hour execution measurements. Fixed-wing
Trace.to_csv() retains row strings and their joined output while packed rows
remain alive. Rotorcraft FlightRows.save() writes one formatted row at a time;
it does not share that whole-CSV amplification.

Recommended design: keep simulation production synchronous and ordered, but move
owned immutable recording chunks to one writer. As an initial engineering design,
4096 rows per chunk with one filling, at most two queued and one being written
costs 5.75 MiB of rotorcraft Float64 payload (4.25 MiB for the base fixed-wing
schema). A provisional 8 MiB raw-chunk ceiling must account for the actual chosen
schema; use row-at-a-time final CSV formatting or a separately bounded format
buffer. These are proposed limits, not implemented ones.

Store a durable spool and freeze final metadata/tick identity at finalization.
Preserve current schema precision, metadata updates, trace readers, checkpoint
and replay contracts. On disk-full, slow writes or pressure, report an incomplete
recording and preserve its accepted prefix for recovery; never silently discard
old rows or change physics timing to make a full queue disappear. A new T request
after failed saving currently can clear old rows; that source-traced recovery path
requires its own witness and cannot be assumed protected by the completed UI-31
departure gate. Dispose buffers only after the consumer/recovery contract permits.

Validation: compare every accepted tick, field and metadata value against the
current recorder; inject write failures and backpressure, stop/restart/scene exit,
retry and shutdown. Measure long recording and export peaks. This is cross-cutting
storage work, so a small silent row cap is not a safe targeted fix.
2. Make the large texture experiment specific
app/vehicles/ground/monster_car_2_model.gd loads
monster_truck_nitro_1.glb. Its import extracts the body color, emission and MR
maps. All three 4096×4096 sidecars select lossless storage, mipmaps and
vram_texture=false; the freshly imported scene references all three, and their
.ctex headers are RGB8 with a complete mip chain. Disk PNG/JPEG/WebP compression
does not establish a GPU block-compressed format [S4].

Pinned RenderingDevice texture storage expands RGB8 to RGBA8 [E2]. Thus each map
has a conditional logical chain of
4 × sum(4096², 2048², ..., 1²) = 89,478,484 bytes.
Three total 268,435,452 bytes, effectively 256 MiB, before driver alignment,
staging, views and other allocations. This is not observed VRAM. Embedded GLB
images and extracted dependencies are not automatically two resident copies.

First experiment: retain 4096² and mips while selecting the appropriate supported
VRAM compression/import variant. Compare diffuse paint, emission at night and
roughness/metallic response. If actual sampled block formats use 8 or 4 bits per
pixel, the same texel count would have roughly one quarter or one eighth of the
RGBA8 payload; this is a format calculation, not a promised format or saving on
the M1. Check actual Compatibility and Mobile/Metal imports and exports, including
fallback/transcoding. Only then test selected 2048² maps, whose texel payload is
roughly one quarter at equal format. Preserve alpha, normal/data-channel semantics,
distant markings and mip stability. Do not disable mips to reduce the inventory.

The flight HX-700 provides another candidate, with a logical RD RGBA8 estimate
near 58 MiB for its three extracted maps. The separate articulated preview is
about 122 MiB. Do not add those figures without demonstrating simultaneous
ownership. Ground grass/dirt maps already request VRAM compression; the project
compression flag alone says nothing about a procedural ImageTexture's actual
runtime format. Asset metadata and arithmetic are retained in the evidence.
3. Preserve useful circuit reuse with bounded ownership
The previous _surface_cache strongly retained every supplied key. The production
flight caller hashes circuit, surface, lake and grid identity. Normal stock
repetition shares a key; content changes or distinct builder inputs are the
accumulation precondition. RCV-43 already measured the value of warm reuse on its
historical Windows headless workload (416 ms first dirt build versus 3.4 ms warm).
Those are prior results, not measurements from this review.

The implementation retains at most two keys/meshes and admits against
B = 40 V + 4 I: 12-byte position, 12-byte normal, 16-byte Color and 4-byte index
source arrays. It calculates this before mesh upload, avoiding a renderer
readback just to count bytes. Keys longer than 128 characters, missing keys,
unsupported attributes and entries larger than 4 MiB bypass storage. Hits promote
recency; insertion evicts least-recently-used references. clear_surface_cache()
provides explicit release. A live MeshInstance retains its own reference.

The checked stock flight mesh contains 18,159 vertices and 105,240 indices:
1,147,320 logical bytes. Two comparable entries use 2,294,640 bytes of the proxy
budget. This is a cap on retained source-geometry accounting, not resident RAM,
GPU allocation or all live meshes. A new mesh is built before admission, so old
cache contents, its source arrays, the new mesh and renderer staging can overlap.
Unknown/oversize input still builds normally and is not made inexpensive by bypass.

With only two entries, dictionary lookup is expected constant time and promotion/
eviction scans a bounded two-item list. A hit avoids grid/road evaluation and mesh
recreation. Eviction can increase rebuild cost when a working set exceeds the
budget. One entry would also preserve repeated stock-flight reuse; the second
entry supports A→B→A behavior, without a measured product-level hit-rate claim.
No physics geometry, road sampling law, material values or grid resolution changed.

Validation covers exact cached mesh identity; no road sampling on a hit;
LRU/count/byte/key boundaries; oversize bypass; same-key replacement; live-node
ownership during clear/eviction; actual stock rebuild arrays, AABB, material and
terrain. The new cache checks and existing flight/car consumers passed. Under
pressure a future owner can clear optional cache references; active resources
remain valid and their release/residency is managed by their owners and driver.
4. Read the parked shared ORM image once
ParkedAircraft.mesh() already retains the two derived Stik meshes for finite
stock paths. The changed work runs on their first merge below High detail, not
each frame or each placement. SC-09-R2 already documented runtime derivation;
this review removes one precise duplicated operation within it.

The assembled and service assets have five and four materials, respectively,
whose metallic and roughness slots reference the same PortableCompressedTexture2D.
Previously each slot independently requested an image. Now a successful common
image supplies both existing channel-mean loops with unchanged accumulation order
and 64-bit GDScript scalars. The image dies on helper return before albedo sampling.
Generic mutable Texture2D inputs and distinct textures keep the old independent
paths. If the first common read fails, metallic uses its existing default and
roughness still makes its original second attempt.

The stable baked-resource/synchronous-call assumption is explicit. A hypothetical
second read failing after a successful first read, or concurrent mutation of the
baked PCT, is not behaviorally identical to taking one successful snapshot.
PortableCompressedTexture2D's type alone does not guarantee immutability. Pinned
engine get_image() delegates to RenderingServer.texture_2d_get [E1]; the manual
warns about repeated GPU retrievals [S3].

Source inventory predicts 15→10 non-null texture get_image requests for assembled
and 12→8 for service, 27→18 combined, assuming the shared first reads succeed.
The corresponding serialized compressed chains total 5,767,288 bytes; actual
returned bytes, allocations, transfer size and peak impact are unmeasured.
Old reads were sequential;
there is no justified claim that 5.5 MiB disappears from peak RSS or VRAM.
No persistent image cache was added; retained memory impact remains unmeasured.
No eviction policy or stale cross-material image state is introduced.

Tests require readable pixels from the actual nine stock PCT aliases, compare
channel values with independent reads, and cover helper failure retry and
non-mipmapped inputs. Generic production paths remain unchanged by inspection.
Dummy-renderer success establishes component
logic, not a successful Metal GPU round trip or visual qualification.
5. CPU buffers and precomputed simulation work
The shared simulation already spends small bounded memory to save computation.
FlightSession._kernel_pre_step() arms eleven capability/layout facts for one
tick; acceptance/fault clears them. _deflections() reuses a read-only result
while its four control inputs match. Simulation._refresh_inertia_inverse()
retains the input inertia and inverse until the inputs change. The native stage
prepares and reuses continuous-state, wheel and anchor scratch; its configuration
guard reparses changed inputs at the owning boundary. These are existing
optimizations, not missing caches or new results.

The A3 stage-validation experiment already covers the 13-value body slice after
the combined-state scan. An ordinary joint RK4 tick with n substeps and no event
trials creates 416n logical temporary bytes in that slice alone. Its qualified
complete-session gain remains open; this review does not repeat it as new work.

app/physics/integrator.gd also makes three intermediate state copies and one
result copy per normal RK4 piece. For state width N=13+C, that is 32nN logical
bytes copied per tick, excluding derivative arrays and event trials. At N=35,
n=1, 240 Hz, the copy volume is 268,800 bytes/s. This is operation/space
accounting, not observed allocator traffic or timing. A retained workspace costs
about 8N bytes per vector and can avoid repeated allocation, but it still must
write the values.

Only pursue that workspace if allocation attribution makes it worthwhile. It must
be per-owner and nesting-safe, keep all four derivatives alive through the same
weighted sum, and never overwrite committed previous, _last_valid_*, escaped
observer arrays or the high-state retained during event bisection. Preserve exact
stage times, reduction order, rejection/rollback, checkpoint/replay and reentrant
callback behavior. A global pool or two-buffer swap without those guarantees is
not justified. Finite warmup must be explicit, and owner teardown releases the
workspace. No integrator edit is included here.

A narrower, source-only native candidate is capturing a checked read-only packed
array pointer once in research/native-kernel/src/nk_kernel.cpp before copying
continuous values into already-sized scratch. The file already uses this approach
for body state. It could avoid per-index binding calls while retaining O(C) work
and O(C) existing scratch [S11]. Check empty layouts, exact values, refusal/replay
and native trajectory oracles before measuring. It may be negligible, and the
current native-stage admission is Linux x86-64; it is not a present Mac speedup.
Measurement baseline and reproducibility
The exact pinned engine was imported successfully with the complete application
and required aircraft authoring JSON. Early sparse-checkout import/lifecycle
failures were setup failures, retained separately and excluded from measurements.
No production change preceded the two valid baseline lifecycle runs.

tools/godot/lifecycle_check.py exercised Home→flight→Home and
Home→Workshop→Home with one warmup cycle, three measured cycles, eight settling
frames and one-second dwell. These are paused/headless ownership checks. They do
not measure active-flight CPU/GPU frame times, input latency, native preload or
first-visible-frame latency. The processes were fresh, but imported assets and OS
filesystem caches were warm; no OS-cache-cold claim is made.

Both unchanged baselines completed with zero node/orphan/resource growth and no
shutdown leak warnings. All sampled retired objects were gone. The maximum
temporary object-count rise was 32 and returned to baseline. The first baseline's
settled static-allocation increase peaked at 59,656 bytes and ended at +4,900;
the repeated baseline ended 953,488 bytes below its initial settled value. This
variation is not evidence of a leak or of a memory optimization.

The existing checked resource sampler could not identify the engine reliably in
this container: child PIDs and the mounted /proc used different namespaces. Its
307,200-byte “engine RSS” belonged to a wrapper and is discarded. The retained
read-only observer instead matched the exact engine argv, unique output subtree,
host PID, process start ticks and namespace PID. The baseline v1 observer and
subsequent v2 safeguards are retained with their results. The observer is an
environment-specific evidence aid, not a replacement for the normal runner.

The valid unchanged process series has 186 samples at approximately 0.25 seconds,
spanning 46.33 seconds. Peak sampled VmRSS and last observed kernel VmHWM were
1,277,050,880 bytes (1,217.89 MiB, about 1.189 GiB). These kernel counters are
approximate; PSS was permission-denied. VmPeak/VmSize describe virtual address
space, not committed physical RAM. HWM is only established through the final
observation, not the inaccessible instant of process exit [S9].

The host exposes about 9.73 GiB through /proc/meminfo, but the cgroup cap is
8 GiB. Near-cap cgroup usage was largely file-backed cache; no OOM kill delta was
observed. Host “available RAM” must not be substituted for container headroom,
and cgroup activity is not attributed solely to the game.
Final evidence	Unchanged measured baseline	Combined candidate
Lifecycle completion / checked verdict	Complete / pass	Complete / pass
Settled nodes / orphans / resources	922 / 0 / 1,234 throughout	922 / 0 / 1,234 throughout
Objects, baseline→cycle 1→2→3	5,683→5,699→5,715→5,683	5,683→5,699→5,715→5,683
Static allocator, first→final settled bytes	909,847,342→908,893,854	909,897,836→908,944,348
Retired objects still alive / shutdown leak warnings	0 / 0	0 / 0
Observed RSS/HWM peak, bytes	1,277,050,880	1,277,976,576
Observed RSS/HWM peak, MiB	1,217.891	1,218.773
Process samples / span	186 / 46.33 s	193 / 48.10 s


The sampled peak difference is +0.883 MiB; it is not a demonstrated memory saving
or a diagnosed regression. Both final static deltas are −953,488 bytes. The
candidate has 50,494 additional static bytes at equivalent checkpoints, without
attributing that difference to any one resource. This comparison checks ownership
at equivalent checkpoints;
one candidate run and two baselines are not a statistically qualified speed or
resident-memory improvement.

Focused final checks: circuit cache 28/28; existing circuit flight 60/60; existing
car-track geometry zero failures; parked texture reuse 13/13; both complete stock
merged meshes match the frozen baseline's decoded arrays/LODs/bounds/materials;
the portable retained comparison also passed. Checked import generated the two
test UID sidecars. No final check reported a Godot error or warning. Earlier
draft/test-harness failures are recorded separately, not hidden as passing runs.
Executed recorder witness
The production helicopter recorder accepted synthetic structurally valid
telemetry for 12,000 ticks, representing 50 simulated seconds. Including its
initial row it held 12,001 × 46 × 8 = 4,416,368 bytes of array elements.
Successful CSV saving left all 12,001 rows alive. Starting a new recording reduced
the trace to one 368-byte row. Debug static allocation rose from 87,756,831 bytes
before start to 93,292,915 after saving; that includes capacity/other allocations
and is not RSS. The probe does not simulate a flight or test failed-save recovery.
Its JSON, source digest and checked completion receipt are retained.
Native measurements still required
Question	Reproducible method and acceptance evidence
Process memory and peak overlap	Normal host: checked runner with pinned psutil 7.2.2 and exact engine PID; RSS/working set, peak where exposed, commit/virtual metrics separately. Correlate phase markers with imports, Home, launch, Workshop, restart/end, export and shutdown. Short spikes require finer targeted sampling/event instrumentation.
Apple Silicon allocation vs footprint	Instruments Game Memory with Allocations, Metal Resource Events and VM Tracker from launch. Record physical footprint, compressed/swapped dirty pages, resource creation/release and actual same-device allocation counters. Profiling runs are for attribution; compare clean observer-off runs separately [S6].
Dedicated/shared GPU memory	Windows: query per-adapter LOCAL/NON_LOCAL budget/current usage where supported, plus OS/driver profiling. Vulkan: per-heap VK_EXT_memory_budget, not a sum over aliased memory types. These are proposed integrations, not current OpenRC telemetry [S7, S8].
Cold/warm loading and readiness	Existing research/performance/loading_probe.gd on a native display; five fresh-process and five warmed loads. Separate request, resource ready, instantiate, scene work, first actual draw and input-ready times. Record cache state; fresh process is not automatically a cold shader/disk cache.
Frame pacing and sustained use	Existing research/performance/sustained_flight.gd, real 1080p output first. Use owning A26 campaign: five alternating independent 30 s warmup + 120 s screens; worthwhile finalists get three independent 30-minute active runs per role. Report CPU/GPU/frame p50/p95/p99, maximum and hitch bursts, simulation/wall ratio, not only average FPS.
Representative stress	Stik solo and companions, helicopter and Monster Car 2, day/night/lake, Workshop flight/articulated preview, repeated scene/restart/seed changes, extended T/F10 recording and stop/export. Isolate one changed variable; qualify other supported backends separately.


Budget strategy: active working set, transition reserve, optional reuse
Do not assign a whole-game RAM or VRAM minimum from this headless process. The
current evidence supports category bounds and a native calibration strategy.
Use logical payload estimates for admission planning, but validate them against
backend allocation and OS footprint. Count shared resource identity once.
Category	Existing or proposed policy	Lifetime, pressure response and exclusions
Circuit mesh reuse	Implemented here: ≤2 entries and ≤4 MiB source-geometry proxy	Process/script cache; LRU or explicit clear. Live nodes and construction/upload peaks are outside this proxy.
Workshop thumbnails	Existing ≤16 entries, ≤4 MiB logical RGBA pixels; maximum dimension 512	Retain current content-keyed bounded cache; evict optional old previews first. Active UI and readback/viewport allocations remain independent.
Trim preparation	Existing 2 entries, 1 MiB retained-key cap and one managed job	Key includes complete inputs; generation/cancellation/draining rules stay intact. The key bound is not a limit on all worker/result memory.
Home scenes/previews	Existing two retained PackedScenes; one active and one latest queued load	Preserve UI-34c first-draw/stable-selection gate. Add marginal byte/peak admission after profiling, not a second preload owner. Cancellation drains jobs and releases broker refs; active scenes may still own dependencies.
Collision/ground reuse	Existing collision serialized cache: one entry/8 MiB; ground patch cache: eight/4 MiB	Keep useful computation reuse. Serialized caps exclude decoded caller worlds and transient serialization.
Cloud tiles	Existing max four process entries, including failures	Successful RG16F2048² tile is 16 MiB logical; four are 64 MiB. An HDR bake target is 32 MiB; image copies, publication texture, staging and older/live owners can overlap. Analytic fallback remains essential. Seed/LRU redesign belongs to A1/A7/A28.
Manual traces	Proposed: bounded immutable chunks; initial ≤8 MiB raw pipeline with schema-aware admission	Writer queue has a finite maximum; stop incomplete explicitly on unrecoverable pressure/I/O, preserve accepted data and recovery. Formatting and disk spool need separate budgets.
Stik sample handoff	Existing A28 proposal: one additional 1 MiB compact CPU sample	Tied to generated source/skin identity, never a reference to the whole atlas by accident. Release on replacement/owner teardown; preserve original fallback and pixel equality.
Audio reuse	Existing single completed shared ambience WAV; A28 defers unused legacy loops	Preserve initial phases/order and partial-bank fallback. Measure the actual byte inventory and first-audio latency before introducing further pools.
Active textures/meshes	Per-resource manifest of actual runtime format/dimensions/mips/owners	Essential flight resources remain resident while used. Reduce avoidable payload or keep a profitable derived result; no guessed aggregate GPU cap. Monster texture experiment is the first large concrete target.
Render targets	Explicit resolution/sample/format/attachment inventory	At 1080p one RGBA8 single-sample plane is 7.91 MiB; four samples are nominally 31.64 MiB before resolve/depth/alignment. Native attachment lifetime, tiling and memoryless allocation must be inspected. Current quality is preserved.


The transition peak is approximately the union of old and new live resources,
plus decoding, generated arrays, upload/download staging, drawables and caches.
It is not simply the steady-state sum of two scenes. For a calibrated budget B,
admit optional additional retention C only when

active working set + measured transition reserve + C + safety reserve <= B.

Use a high-percentile transition envelope plus a worst-observed stress case;
the exact reserve must be measured on the target host. Cache performance should
be assessed as expected avoided work per retained byte. For hit probability h,
cache-miss work Tmiss, hit work Thit and average maintenance/pressure penalty
P, benefit requires h (Tmiss - Thit) > P. A cache with no likely second use
only moves cost and consumes headroom. Record hits, misses, evictions, rebuilds,
peak entry bytes and invalidation reasons without per-frame expensive formatting.
Hardware adaptation
Hardware test class	Sensible initial policy to validate
8 GB unified or otherwise constrained system	Keep existing small caps and at most one background preparation owner. Do not add speculative whole-aircraft retention before measuring its marginal footprint/transition peak. The bounded 1 MiB Stik sample is a better first RAM-for-work experiment than preloading the fleet. Trim optional old thumbnails/meshes before active flight data.
16 GB unified, or 16 GB system RAM plus discrete GPU	Use the same correctness and ownership rules. Consider one measured next-choice resource within the existing broker capacity when repeated selection evidence predicts reuse. Dedicated GPU allocation must also fit its dynamic local budget; system RAM capacity cannot rescue a VRAM oversubscription assumption.
32 GB+ system/unified memory and higher-capacity GPU	Increase optional reuse only for measured load/hitch gains, with explicit byte bounds and transition reserve. Keep active-worker concurrency bounded. Higher resolution can consume the apparent surplus in attachments; do not scale every cache proportionally to installed capacity.


These are test classes, not newly certified minimum/recommended specifications.
On Apple Silicon the CPU and GPU share physical memory; do not add RSS or
physical footprint to Metal allocation totals [S6]. Use footprint/pressure and
GPU allocation as separate, overlapping constraints. Apple
recommendedMaxWorkingSetSize is an approximate performance guideline;
currentAllocatedSize is allocation, not free capacity [S10]. Windows local and
non-local GPU segments are not two extra amounts of system RAM [S7].

If reliable native budget/pressure telemetry is added, one trial policy is to
admit measured optional growth below 70% of the applicable device recommendation
or dynamic budget, stop new speculation at 80%, and readmit only below the lower
threshold after recovery. 70/80% are unvalidated policy hypotheses, not vendor
limits or present behavior. They must coexist with measured transition headroom
and OS pressure; unknown pressure is not “normal.” On warning/critical events,
cancel future optional work, drain generation-owned jobs and release unowned
cache entries. Do not free resources still referenced by a draw, scene or worker.
Without dependable native telemetry, retain fixed known caps and the current
fallbacks. No new pressure controller is implemented in this change.
Interpreting Godot counters correctly
Pinned MEMORY_STATIC is debug allocator accounting; release builds can return
zero when the counter is unavailable. It is not total process RAM. Compatibility
video bookkeeping equals texture + render-buffer + buffer bookkeeping, while its
texture category already includes render buffers. Do not add video to its parts.
On the pinned Metal backend total device memory uses currentAllocatedSize;
on Vulkan it uses VMA statistics.allocationBytes, not dynamic heap budget/usage.
These implementation details were checked in [E3–E6]. None of those numbers alone
establishes physical residency, pressure or a leak.
Practical implementation sequence
1. Reviewable local changes completed: retain the cache and ORM patches,
   focused checks, recorder witness and combined lifecycle receipts. No asset or
   simulation changes accompany them. Required CI and native appearance/performance
   qualification remain separate from local success.
2. Bound recording storage under its existing owners: production T recorders
   first, then versioned ground replay/checkpoint storage. Prove exact records and
   recovery under failure before claiming lower memory. Avoid coupling this work
   to A24's already tracked F10 whole-bundle hashing issue.
3. Run the highest-value native asset experiment: Monster Car 2 compression
   at unchanged resolution, then selective downsize only if justified. Measure
   actual resident/allocated/footprint peaks and moving day/night quality on
   Compatibility and Metal; retain source/import/package hashes.
4. Spend small, purposeful RAM where it saves expensive work: qualify A28's
   1 MiB Stik sample and deferred legacy audio allocation first. Preserve current
   trim/geometry/scene caches. Measure hit probability and first-use/warm-load
   costs before growing them or adding new resource pools.
5. Attribute and adapt: connect native memory/pressure data to the existing
   loading and sustained-flight probes, then design byte admission and eviction.
   First qualify 1080p on the constrained supported test host, then discrete and
   higher-capacity hardware, then higher-resolution output.
Sources and compatibility notes
Repository statements use the frozen source or the retained candidate/evidence.
These sources are primary documentation or the exact engine implementation.
General guidance is not a promise that a particular API is already used by OpenRC.
- S1 — Godot ownership/cache: Resource, ResourceLoader. Path-cache reuse does not remove the need to manage strong references.
- S2 — Loading/concurrency: background loading, thread-safe APIs, WorkerThreadPool. Poll readiness before retrieving; keep scene-tree publication on its owner, and drain owned work.
- S3 — Image readback: Texture2D.get_image, interpreted against E1 below. A new image/readback request can have a synchronization and copy cost; count alone is not timing.
- S4 — Texture formats: Godot importing images, Apple feature tables. Select and verify per-platform actual formats; storage compression and GPU compression differ.
- S5 — Pipeline readiness: Godot pipeline compilation. Use the existing A26/pinned-backend investigation; a zero Compatibility pipeline monitor is not proof of zero driver work.
- S6 — Allocation/footprint: Apple Game Memory documentation, WWDC22 memory analysis, Apple GPU storage modes. Shared physical memory requires overlapping-accounting discipline.
- S7 — Windows budgets: QueryVideoMemoryInfo, DXGI_QUERY_VIDEO_MEMORY_INFO. Budgets depend on current conditions; they are not physical capacity.
- S8 — Vulkan budgets: VK_EXT_memory_budget, memory allocation specification. Work per heap, not aliased memory type.
- S9 — Linux accounting: /proc documentation, RSS accuracy discussion. Sampled counters and inaccessible PSS remain qualified.
- S10 — Metal device estimates: currentAllocatedSize, recommendedMaxWorkingSetSize, hasUnifiedMemory.
- S11 — Packed arrays: Godot C++ core types. Pointer-access guidance for native binding calls is not a reason to change float64 simulation representation or GDScript ownership.
- E1 — Pinned PCT read: portable_compressed_texture.cpp.
- E2 — Pinned RGB8 conversion: RD texture storage.
- E3 — Monitor/allocator scope: performance.cpp, memory.cpp.
- E4 — Compatibility accounting: GLES utilities.
- E5 — RenderingDevice totals: RD utilities, rendering_device.cpp.
- E6 — Driver totals: Metal driver, Vulkan driver.