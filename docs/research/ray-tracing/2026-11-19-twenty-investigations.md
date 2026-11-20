# Optional ray tracing: twenty follow-up investigations

**Date:** 19 November 2026, America/Bogota.  
**Status:** completed source/documentation research; implementation and GPU qualification remain unexecuted.  
**Plan being improved:** [Optional ray tracing implementation and qualification plan](../../plans/optional-ray-tracing.md). That document owns the execution contract; this record owns the evidence, reasoning and rejected leads behind this revision.  
**Application source:** `e0a733937e255bacfe95ff09db0fb3838697239f`.  
**Starting plan/branch revision:** `ray-tracing@be15feb1e781f1ae5d59cf63a284a6c8cd85ac1c`. Its runtime source is unchanged from that application baseline.  
**Engine:** Godot `cafc17a192acf67903910a68aeb3c076c0907a4b`, official 4.8 beta2.  
**Shadow denoiser:** FidelityFX SDK v1.1.4, `c6efa6bf7f2027b3ec94f28578bb5965eabb9e55`, embedded Denoiser 1.3.0.  
**Separate NVIDIA lane:** Godot fork `135dff3887a3d2ccf45cafbd9bdffa7b718e1e76`, Streamline 2.11.1.  
**Change scope:** documentation only. No engine, simulation, settings, package or shader implementation is changed by this research.

## 1. Method, order and evidence rules

The work consists of **20 question-led investigations**, not 20 search queries. Round 1 completed I01–I10 across architecture, numerical correctness, denoising, content, platforms and qualification. Only after all ten findings were consolidated was Round 2 selected. I11–I20 follow specific unresolved boundaries from Round 1 and reduce them to source-specific implementation decisions and test oracles.

The original plan's 52-branch audit remains its repository-wide foundation. This follow-up checks exact engine, application, SDK, patch and tooling paths implicated by the new questions; it does not claim another complete historical branch audit.

Evidence labels used below:

- **Observed in source:** behavior read in the exact pinned implementation. This does not prove the built executable behaves correctly.
- **Documented:** an API or algorithm contract from its author, specification or official sample.
- **Derived/proposed:** an engineering decision or analytic consequence developed here; the implementation must prove it.
- **Community lead:** a firsthand forum, issue or Reddit report that suggested a question. It is not a product-support, performance or correctness oracle.
- **Unexecuted:** no new engine build, GPU trace, image comparison, performance run or package-fault experiment was performed.

The investigation deliberately rejected several plausible but unsupported bug claims. Existing global AS memory barriers, host-coherent instance allocations, already-fixed push-constant code and AMD SDK signature checks must not be described as absent.

### Round 2 selection checkpoint

| Completed Round 1 finding | Targeted Round 2 investigation | Why this follow-up was selected |
| --- | --- | --- |
| I01: current guide production and native lighting ownership | I11: exact Forward+ binding and pass layout | Decide the smallest viable insertion and its Off-state regressions. |
| I02: build synchronization and mutable generations | I12: typed buffers, per-AS scratch and barrier matrix | Replace vague synchronization requirements with an implementable owner contract. |
| I03: instance-dependent wind and alpha | I13: actual Club/Green source census and feasibility | Determine which real content makes the budget difficult before full implementation. |
| I04: SDK formats, subgroup assumptions and correspondence | I14: minimal packed-mask/format/reset adapter | Specify an adapter rather than leaving the executing agent to redesign a denoiser. |
| I05: moving shadows on static receivers | I15: independent analytic temporal fixture | Make ghosting and response measurable without assuming a new algorithm is required. |
| I06: numerical error and facing | I16: actual Godot depth/transform/culling path | Avoid a generic bias formula that does not fit raster-depth receivers. |
| I07: limits of Metal examples and patches | I17: retain/replace/re-prove audit | Separate reusable safety ideas from diagnostic-only restrictions. |
| I08: temporal provider input contracts | I18: actual producer/reset code in each lane | Detect unit/ownership gaps rather than assuming providers consume the same guides. |
| I09: examples and dependency provenance | I19: current package checks and isolated faults | Close the precise package-completeness gap without duplicating existing checks. |
| I10: comparability, capture overhead and statistical uncertainty | I20: asynchronous sample identity and reducer rules | Ensure an eventual performance verdict measures the submitted RT work. |

## 2. Round 1 — Broad investigation

### I01 — Where should optional sun shadows enter Godot?

**Question.** Can a compositor-only feature reliably obtain current guides and replace the selected sun's visibility?

**Evidence.** Public RenderingDevice APIs and official compositor examples provide useful prototype surfaces. PRE_OPAQUE follows a depth prepass only when that prepass runs. At the pinned engine, the normal/roughness request participates in a branch dependent on a valid Environment, while the force-prepass decision does not independently guarantee that request. The ordinary motion pass is later than the proposed pre-opaque denoising point. A valid texture RID therefore proves neither fresh contents nor matching receiver identity. Sources: [Godot compositor contract][G-COMP], [tutorial][G-COMPT], [Forward+ implementation][G-FC], [RD implementation][G-RD].

**Community lead.** A [Godot forum discussion about compositor depth][C-DEPTH] exposed confusion between access to a buffer and the render path producing it. Forum suggestions were not adopted as engine facts.

**Decision.** Retain the small engine-owned selected-sun seam. Do not claim that every GDExtension route is impossible; the decision follows this feature's required ordering, scene access and lighting ownership. Explicitly produce current depth, normals and validity or use native shadows.

**Required proof.** Phases 09–10/T05 must cover an absent Environment, a disabled ordinary prepass, SSAO/SSR off, supported MSAA levels, and a frame-specific receiver stamp. An allocated but unwritten buffer fails. **Follow-up:** I11.

### I02 — Are AS builds, scratch and geometry replacement actually safe?

**Question.** Does the existing TLAS reservation patch also make changed BLAS and their dependent queries transactional?

**Evidence.** A BLAS build invalidates dependent TLAS state in the pinned RD implementation. Prevalidating a later TLAS does not undo an earlier in-place BLAS mutation. Vulkan also requires explicit build dependencies and prohibits overlapping scratch for unordered builds in the same call. Sources: [RD build/dependency code][G-RD], [graph tracking][G-GRAPH], [Khronos build requirements][V-BUILD].

**Rejected leads.** The lack of a separate scratch buffer tracker is not, by itself, a proven same-AS race: the graph emits a global AS memory barrier. The inspected Vulkan CPU allocator requests HOST_VISIBLE and HOST_COHERENT, so a generic claim that instance uploads omit a required noncoherent flush would be wrong. A [Vulkan Reddit discussion][C-SCRATCH] was a synchronization lead, not evidence that this engine has that exact failure.

**Decision.** Changed geometry needs independently retained candidate BLAS/TLAS generations or native visibility before an unsafe mutation. Preserve older generations for already submitted frames; never render the current changed scene using stale geometry merely because the old AS is still valid.

**Required proof.** T02/T03 inject failure after candidate BLAS preparation and before TLAS publication, with several frames in flight. Validate old submitted output, current fallback, dependency state and retirement. **Follow-up:** I12.

### I03 — Can repeated vegetation share one deformed BLAS?

**Question.** Which native caster inputs determine exact geometry and alpha in OpenRC?

**Evidence.** Imported tree MultiMeshes enable native casting and assign per-instance phase/color data. The authored wind shader changes positions using phase, displayed clock, wind, basis/scale and plant parameters. Its flutter also changes normals without necessarily changing positions. Alpha uses material UV transformations, texture sampling, vertex/instance color and explicit discard behavior. A source mesh/material identity alone does not establish equal deformed vertices. Sources: [vegetation builder][O-VEG], [authored wind shader][O-WIND], [Godot caster classification][G-SHADERCPP], [spatial shader reference][G-SPATIAL].

Native shadow-mesh selection is conditional, so a simplified shadow mesh may be reused only after its source/LOD and silhouette contract is proven. Treeline and imported-hedge paths inspected in the first round explicitly disable casting; they are useful negative controls, not automatically missing RT casters.

**Decision.** Share rigid geometry where equivalent. For wind, use an exact deformation key or independently produced vertices, with all builds charged to the budget. Treat geometry displacement separately from normal-only flutter. Match actual alpha semantics instead of using a generic texture cutoff.

**Required proof.** T08 compares two instances of the same source with different phases, yaw and scale at the same displayed time; separately test UV/color/mip/threshold changes and native noncasters. **Follow-up:** I13.

### I04 — Is the pinned shadow denoiser a drop-in Vulkan component?

**Question.** What source boundaries must be adapted before its successful compilation could mean a useful result?

**Evidence.** The stock preparation path reduces a 32-lane 8×4 mask through subgroup operations and writes its result from multiple lanes; subgroup size need not equal workgroup size. The classifier can choose a nearest-depth velocity from a 2×2 quad, potentially borrowing another receiver's motion. The host and GLSL storage-image declarations also require explicit reconciliation. The no-half filter path contains compile-only zero-return helpers rather than a qualified f32 substitute. Sources: [host][F-HOST], [preparation][F-PREP], [classification][F-CLASS], [callbacks][F-CB], [filter][F-FILTER], [GLSL subgroup implementation][F-CORE], [Khronos subgroup guide][V-SUBGROUP].

**Decision.** Keep FidelityFX as the bounded first candidate, but own a small, documented adapter. Derive each dispatch from its actual shader, verify emitted SPIR-V image formats and arithmetic features, and validate per-pixel correspondence and initialized history.

**Required proof.** T09 uses all 32 bit positions, odd/partial extents, subgroup variation where available, mixed receiver IDs across a 2×2 boundary, and two deliberately different poisoned-history patterns on both ping-pong parities. A shader compiling is insufficient. **Follow-up:** I14.

### I05 — Does receiver motion describe a moving aircraft shadow?

**Question.** Can shadow history respond correctly when the aircraft moves but the ground, camera and light remain stationary?

**Evidence.** Original temporal-motion-vector research explains why lighting changes can move independently of primary surfaces. FidelityFX already includes local clamping and adaptive history behavior; these are relevant existing mechanisms, not proof of success or failure for OpenRC. Sources: [original research author page][P-TRMV], [paper][P-TRMVP], [AMD technique][F-TECH], [classifier][F-CLASS].

**Community leads.** A [Unity engineering discussion][C-UNITY] reports shadow-denoising lag and noise/ghosting tradeoffs. An [original graphics-programming Reddit post][C-TEMPORAL] describes adding lighting-change detection to temporal reuse. Reddit was available through indexed original-post text; direct thread retrieval was unavailable. Neither report establishes a defect in the selected SDK.

**Decision.** Extend the temporal gate to newly lit and newly shadowed static ground. Separate raw query output, denoiser output and final reconstructed output before choosing a remedy. Do not automatically add shadow-motion vectors or a second denoiser.

**Required proof.** Fixed camera/ground/sun; thin moving caster; slow and faster-than-width motion, reversal, hold, and offscreen caster influence. Apply the existing three-real-frame response bound to both transition directions. **Follow-up:** I15.

### I06 — What numerical offset is valid for a raster-depth receiver?

**Question.** Can a published triangle-hit offset formula be used unchanged for this feature?

**Evidence.** NVIDIA's derivation addresses triangle-hit reconstruction and includes hardware-tuned traversal error constants. OpenRC's receiver originates in raster depth and inverse projection, so depth quantization, projection arithmetic and raster/AS disagreement also matter. Vulkan's facing semantics distinguish geometry transforms from instance transforms, and require valid invertible instance transforms. Sources: [NVIDIA derivation][N-BIAS], [PBRT rounding-error treatment][P-PBRT], [Vulkan traversal][V-TRAVERSE], [AS specification][V-AS].

**Decision.** Derive and test the actual receiver uncertainty; do not present one vendor's constants as a universal raster-depth bound. Use an independent oracle built from unbiased intended geometry. An offset that removes acne but crosses a nearby blocker is a failure. Determine facing from the native caster path and the actual transform representation rather than automatically flipping every negative determinant.

**Required proof.** T02/T05 sweep small gaps, grazing directions, nonuniform and mirrored transforms, large translations and two-sided surfaces. Reject nonfinite, singular, mismatched or unvalidated cases into native fallback, counted against coverage. **Follow-up:** I16.

### I07 — What do the Metal experiments actually establish?

**Question.** Can the existing Metal patches serve as the production optional-shadow backend?

**Evidence.** Patch 0005 implements an experimental narrow immutable opaque, nonindexed float3 triangle-query route and already declares indirect BLAS resource residency. The separate [Metal intake record][O-MREADME] contains bounded M1 hit/readback evidence. Its one-shot build, descriptor restrictions and diagnostic tracking mode do not describe normal animated flight. Apple's documentation distinguishes residency, hazard tracking and optional refit; refit does not permit arbitrary topology changes. Sources: [0005][O-M0005], [Apple RT guidance][A-RT], [Metal resource session][A-RES], [refit API][A-REFIT].

**Decision.** Use the experiment as source evidence, retaining its useful safety ideas. A rebuild-first production candidate is allowed; do not introduce shared heaps, refit or compaction as prerequisites merely because an example uses them. API support and hardware acceleration remain separate facts.

**Required proof.** Before Metal qualification, enumerate every guard in 0005/0018/0027 and give it a retain, replace or re-prove disposition. Validate actual indexed/deformed/alpha source ownership and safe Off retirement. **Follow-up:** I17.

### I08 — Do temporal providers share guide and reset conventions?

**Question.** Can the RT denoiser, FSR2/FSR3, DLSS and MetalFX use the same motion/history assumptions?

**Evidence.** Official contracts differ in motion scaling, jitter handling, matrices, active extent, resource tags and frame identity. FSR distinguishes reactive and transparency/composition inputs. Streamline requires consistent frame tokens across tagged resources, constants and evaluation. MetalFX exposes a separate jittered-motion-vector setting. Sources: [FSR2 guide][A-FSR2], [FSR upscaler guide][A-FSR3], [Streamline DLSS guide][N-DLSS], [Reflex guide][N-REFLEX], [MetalFX descriptor][A-MFX].

**Decision.** Give each consumer a documented conversion owner and independent history epoch. Record sign, units, Y direction, resolution, jitter inclusion, current/previous matrices, active rectangles and token identity. Do not mandate a new shadow-reactive mask without a demonstrated defect and a provider-specific input contract. RT Off means zero RT work, not zero legitimate existing Reflex calls.

**Required proof.** Static jitter with zero physical motion; known camera/object motion; odd extents; cold/warm history; mismatched tokens; resize and reset failure. Keep generated frames off in initial qualification. **Follow-up:** I18.

### I09 — Which examples and runtime components are transferable?

**Question.** What can community implementations demonstrate without importing their unrelated architecture or dependencies?

**Evidence.** The pinned [Fahien demo][EX-GD] uses a real SBT, but reads texture data back and constructs an image texture for display; that diagnostic loop is not a normal-flight template. The reviewed [community fork][EX-RTX] has its own engine baseline, Streamline version and conditional RR path; matching export templates are not shipped and must be built separately. Its performance/support cannot be inherited by OpenRC. A [Godot push-constant issue][G-PUSHISSUE] described a driver-visible error; the fix is already represented in the reviewed beta2 source and must not be filed as a current unresolved defect.

Streamline 2.11.1 separates interposer/common, DLSS, Reflex/PCL, optional features and their runtime/license requirements. Source license and binary redistribution terms are not interchangeable. Sources: [2.11.1 build roster][N-CMAKE], [license][N-LICENSE], [manual-hooking guide][N-HOOK].

**Decision.** Use examples for minimal fixtures and historical regressions. Do not adopt a path-tracing fork, replace the engine pin, or copy every SDK binary by assumption. Qualify the exact feature/backend component roster.

**Required proof.** A nonzero push-constant known-result fixture plus a UBO control; archive/member identities and clean-package missing/mismatched-component tests. A DLSS dependency failure must not automatically change an independently qualified native RT capability. **Follow-up:** I19.

### I10 — Which performance evidence would actually be comparable?

**Question.** How should community examples, geometry organization and profiling advice affect qualification?

**Evidence.** A [Reddit Unreal example][C-PERF] reports a tuned scene with reduced TSR resolution, omitted grass shadows and limited wind deformation. It suggests variables to record, not an OpenRC speed estimate. The original post was retrieved through search indexing; direct thread retrieval was unavailable. AMD's [RRA guidance][A-RRA] shows why geometry grouping and large empty bounding volumes can affect traversal. NVIDIA documents that [deep geometry copies in captures][N-CAPTURE] alter memory and AS build/refit costs. The [AMD performance guide][A-PERF] emphasizes a controlled workload. The [Kalibera/Jones paper][P-STATS] explains why repeated frames are not equivalent to independent repeated executions.

**Decision.** Freeze content, wind, shadow-caster roster, internal pixels and presentation state. Profile geometry grouping only when counters identify a problem, preserving represented triangles and shadows. Keep instrumented diagnostic captures separate from ordinary performance runs. Specify the paired statistic and uncertainty method instead of saying only “benchmark several times.”

**Required proof.** An unprofiled paired baseline, immutable scene manifest, bounded partition experiment when justified, and a reducer that rejects missing/duplicated/stale asynchronous samples. Do not copy engine-specific console commands or disable content to match a community FPS number. **Follow-up:** I20.

## 3. Round 2 — Targeted implementation boundaries

### I11 — Exact Forward+ descriptor and selected-light insertion

**Source result.** Forward+ assigns sets 0/1/2/3 to scene, render pass, transforms and material. Its per-pass declarations occupy bindings 0–38, with 38 conditional on texture streaming; binding 6 is the native directional atlas. SDFGI has a separate set builder, and shader permutations do not all expose identical layouts. Sources: [Forward+ header][G-FCH], [render-pass builders][G-FC], [shader declarations][G-INC], [shader variants][G-SHADERCPP].

**Proposed implementation.** Reserve set 1 binding 39 at this pin for the mask, subject to reflected-layout validation; do not invent a second descriptor architecture. Match 2D/array view types. Add explicitly aligned implementation-UBO fields for enable and selected directional index. Resolve the requested sun's render-light instance to the index actually emitted for this viewport and frame. Missing, reordered, sky-only or skipped lights clear enable.

Reset the enable field on every environment/pass setup, then enable only eligible opaque/motion color passes with current admitted inputs. Bind an existing appropriately typed engine default texture on inactive paths; never leave a reflected descriptor unbound or allocate an RT-only dummy while Off. A one-layer default array must not be sampled at nonexistent view layers.

Insert visibility after native geometric shadow evaluation and before native fade/contact/opacity/light accumulation. Include the existing 8-bit shadow packing in final quality assessment. Explicitly request fresh RT guides in both prepass-selection and force-prepass decisions independently of Environment validity.

**Proof/plan impact.** Phases 09–10 and T01/T04/T05 compile and bind normal, depth, motion, transparent, SDFGI, lightmap, separate-specular, mono/multiview, uber and specialized variants. Multiview may remain product-excluded while its disabled layout must remain valid. No compiled shader or image proof exists yet.

### I12 — Typed deformation buffers, per-AS scratch and publication

**Source result.** `blas_create` accepts vertices through `vertex_buffer_owner`, not an arbitrary storage RID. A vertex buffer created with the AS-storage creation flag can also be bound for compute writes. The pin allocates scratch inside each AS. The graph tracks geometry reads, BLAS dependencies and the query's TLAS descriptor, but not TLAS instance storage and scratch as separate buffer trackers. Global AS barriers still matter. Sources: [RD][G-RD], [graph][G-GRAPH], [Vulkan build rules][V-BUILD].

**Proposed implementation.** Use tracked typed vertex/index buffers with actual storage/device-address/build-input usage. End deformation compute recording before enqueuing the build. Start with the existing per-AS scratch owner; shared scratch is deferred.

| Producer → consumer | Required Vulkan stage/access relationship |
| --- | --- |
| Transfer or compute deformation → geometry build input | Transfer-write or compute-shader-write → AS-build/shader-read |
| BLAS build → referencing TLAS build | AS-build/AS-write → AS-build/AS-read |
| Transferred TLAS instances → TLAS build | Transfer-write → AS-build/shader-read |
| TLAS build → compute query | AS-build/AS-write → compute-shader/AS-read |
| Query/filter mask → lighting | Compute-shader/write → fragment-shader/read, with the correct image layout |

Host-coherent mapped instance writes must precede submission and avoid in-flight ranges. Every candidate generation owns or retains its input, AS and scratch until dependent work completes. Descriptor tracking of the TLAS does not alone prove safe mutation/free of indirectly referenced BLAS.

**Proof/plan impact.** 01.2/02.4/04.2/06.3–06.4/08.3: known compute-deform hit, wrong-RID rejection, repeated build ordering, two-or-more-frame failure/publication tests, actual barrier/address receipts and zero post-retirement resources. A future pool needs its own shared hazard proof.

### I13 — Actual Club/Green workload and an early feasibility ledger

**Source result.** Green paradise's builder creates one subdivided grass plane and no Club scenery; the landscape test asserts this field structure. Club's existing vegetation test contains the following bundled source census. Sources: [Green builder][O-GREEN], [landscape tests][O-LTEST], [vegetation counts][O-VTEST], [scenery builder][O-SCENERY].

| Club source asset | Placements | Source triangles per asset | Tree-wind eligibility |
| --- | ---: | ---: | --- |
| Fagus | 4 | 9,312 | Potentially enabled |
| Pine | 5 | 4,246 | Potentially enabled |
| Quercus | 2 | 7,016 | Potentially enabled |
| Quercus 2 | 2 | 11,144 | Potentially enabled |
| Maple | 4 | 5,541 | Static under this tree-wind path |

The source total is **116,962 triangles**, including **94,798** across the 13 potentially wind-enabled placements. These are not live caster counts, selected-LOD primitives, BLAS bytes or GPU timings; the test was read, not run.

**Proposed implementation.** After the scene census, build a feasibility ledger before the complete effects pipeline: actual tape/frame/caster/LOD/surface/index/deformation keys, queried build sizes, aligned allocations and simultaneous live generations. Include phase, model basis/scale, local wind, displayed clock and plant parameters in an exact deformation key; equality of source IDs alone is insufficient. A normal-only flutter change does not require a new geometric BLAS.

Query actual build sizes using the same geometry, flags and primitive limits as the candidate, then measure the primitive upload/deformation/build path. Budget the maximum of unique simultaneously live allocations, not a sum of unrelated peak counters. Do not estimate BVH bytes from triangle counts.

**Proof/plan impact.** 05.1/05.4/06.2/08.2–08.4. Green can be an early integration field; it does not qualify Club, and aircraft/world-level casters still require inventory. A Club row that needs unsupported wind remains unqualified rather than disabling wind.

### I14 — Minimal, subgroup-independent FidelityFX adaptation

**Source result.** The stock preparation loop visits a 4×4 tile block and clamps edge IDs, repeating edge stores on partial tile grids. Its subgroup reduction need not cover all 32 bits. The classifier also borrows velocity from a nearest-depth 2×2 sample. Sources: [preparation][F-PREP], [classification][F-CLASS], [callbacks][F-CB], [host allocations][F-HOST].

**Proposed implementation.** Replace only preparation with one invocation per packed tile. For `tw=ceil(W/8)` and `th=ceil(H/4)`, use 8×8 local groups and `ceil(tw/8)×ceil(th/8)` dispatch. One in-range invocation reads the hit/valid words and stores `lit=(~hit)&valid` once. There is no subgroup reduction in this conversion. Do not clamp out-of-range tile IDs onto valid tiles.

Adapt classification/filtering to exclude invalid neighbors and normalize valid weights; zero padding must not become a real shadow sample. Disable homogeneous-tile shortcuts for neighborhoods containing invalid samples. Use each receiver's own velocity plus identity/prior-depth/normal/epoch validation. Conservatively reject reprojected history unless every tap in its bilinear footprint is valid, in bounds and compatible; apply corresponding checks to the actual depth/moment footprints. Checking only a nominal pixel permits cross-receiver contamination. For repeated shared Boolean reductions, use lane-0 clear, barrier, shared atomic OR, barrier, each lane's local result copy, and a final barrier before return/reuse. Calls/branches are workgroup-uniform; inactive lanes contribute neutral values without skipping barriers.

Freeze the first format candidate: two `rgba16f` moments, two `rg16f` scratch/history images, and `r32f` current depth, prior depth and output. Verify exact image/view formats, sample/storage/filter features and enabled FP16 arithmetic separately. These seven 1080p image payloads total **71.19 MiB**, before masks, guides, AS, alignment or in-flight copies. This is arithmetic for a proposed layout, not an allocation measurement.

Reset initializes both parities and prior-depth correspondence before any history read. Tests cover all 32 one-hot and all 32 one-clear patterns, mixed validity, dimensions 1×1/7×3/8×4/9×5/31×15/33×17, guard canaries, mixed IDs, poisoned histories and both parities. Add half-texel cross-receiver footprints and repeated shared reductions. Run 4,096+ mixed-visibility submissions and a controlled count round-trip near 2,048: the changed moments format also changes temporal-count precision. Stock damping/shortcuts mean ordinary flight is not guaranteed to reach that count. Inspect actual finite moments/variance and then test caster response. Phases 10–11/T09 retain the fixed quality/memory gates; unsupported features leave Soft unavailable.

### I15 — An independent moving-shadow oracle

**Source result.** The existing classifier clamps history to neighborhood statistics and adjusts history weight; static receiver motion is not itself a shadow-motion signal. This justifies a test, not a presumption of algorithm failure. Sources: [classifier][F-CLASS], [technique][F-TECH], [original research][P-TRMV].

**Derived fixture.** Fix ground at `z=0`, camera and sun. Put an opaque strip at height `h`, centered at `a(t)` with width `w`. For a unit test sampling uniformly over the direction-slope disk with half-angle `alpha`, define:

```text
r = h * tan(alpha)
u_plus  = (a(t) + w/2 - x) / r
u_minus = (a(t) - w/2 - x) / r
C(u) = 0,                                      u <= -1
       1,                                      u >= 1
       1/2 + (asin(u) + u*sqrt(1-u*u)) / pi,    otherwise
lit_visibility(x,t) = 1 - (C(u_plus) - C(u_minus))
```

This analytic formula applies to the stated slope-disk distribution. The product's uniform-solid-angle cone sampler requires independent quadrature for that actual measure; do not compare different distributions as if identical.

Use `h=10 m`, half-angle `0.265°` and 100 pixels/m: the penumbra radius is approximately 4.63 pixels. Sweep widths 2/8/32 pixels and speeds 0.25/1/4/12 pixels per real frame, both directions, reversal and a final hold. Thin strips may never become fully dark; compare position and integrated visibility deficit. Add an oblique-sun offscreen-caster case.

**Proof/plan impact.** 11.3/14.1/17.1, T09/T13: three-frame absolute error ≤0.10 after both newly-lit and newly-shadowed step-and-hold transitions. Report continuous-motion edge error and deficit. Isolate denoiser-only, reconstructor-only fed a converged reference, and the combined path in calibrated linear lighting. A teleport reset cannot hide ordinary motion lag.

### I16 — Exact depth conversion, bias envelope and facing policy

**Source result.** Forward+ ordinarily uses a supported D32_FLOAT_S8 or D24_UNORM_S8 depth attachment; some resolve paths use R32_FLOAT. FidelityFX copies current depth into its R32_FLOAT prior-depth image, while its Vulkan backend rejects depth-to-color copies. Sample the actual Godot depth aspect into an R32_FLOAT projection-depth image, then use tracked same-format history copies/ping-pong. Conversion does not recover precision lost earlier. Sources: [Godot formats][G-BUFFERS], [SDK host][F-HOST], [SDK Vulkan backend][F-VK].

The raster double-precision path can use split translations while the Vulkan TLAS stores float transform components. Float64 simulation is therefore not proof of matching raster/RT coordinates. OpenRC's NED-to-render mapping has determinant +1; it alone does not flip handedness. Sources: [raster shader][G-SHADER], [Vulkan transform upload][G-VK], [OpenRC frames][O-FRAMES].

**Proposed implementation.** Record actual format/build precision, projection, sample/jitter and transformed triangle agreement. Derive uncertainty from those inputs and use an explicit geometric normal, not an assumed flat normal from a normal-mapped buffer. For the parallel-plane fixture, let unit normal `n` point toward the blocker, unit lightward ray `d` have `c=dot(n,d)>0`, `gap>0`, and offset/error/`t_min` be nonnegative. Then `delta + E_normal + t_min*c < gap` is sufficient within that plane model, subject to rounding and `t_max`. Orient two-sided normals per ray; `c<=0` and ill-conditioned cases need separate facing/fallback handling. This is not a universal geometry/hardware proof.

Native facing is selected per surface, while instance facing/cull-disable flags cover the referenced BLAS. Initially group surfaces by uniform facing policy, and by the chosen opaque/alpha candidate policy where needed. Geometry-level opacity flags may differ within an AS; do not claim Vulkan inherently forbids that. Preserve shared input buffers and count additional AS instances.

**Proof/plan impact.** 06.2/09.1/10.1, T02/T05: unbiased float64 intended-geometry oracle; gaps 0.25/0.5/1/2/5 mm; translations 0/1,000/10,000/100,000 m as stress fixtures; mirrors, geometry transforms and mixed sidedness. Stress failures outside the advertised envelope are not automatically product failures, but ordinary-flight fallback must still meet coverage gates. No origin-rebasing system is introduced.

### I17 — Metal: retain, replace and re-prove

**Source result and disposition.** [0005][O-M0005], [0018][O-M0018] and [0027][O-M0027] have different experimental purposes:

| Inspected boundary | Production-shadow disposition |
| --- | --- |
| 0005 immutable/nonindexed/opaque geometry; one-shot build | Replace one-shot lifetime with retained generations; rebuild first, refit optional later. |
| 0018 expands indexed data; excludes compressed, skinned, blend-shape and LOD sources | Re-prove each admitted source; use native indexed input or a bounded exact expansion. |
| 0018 captures only at startup under an environment flag; later buffer access/update invalidates without regeneration | Replace with owned runtime acquisition for already-loaded assets and event-driven invalidation. No diagnostic readback requirement. |
| Cumulative non-refunded 64 MiB source and 256 MiB AS/scratch counters | Replace with actual live, retiring and peak accounting; retain safe admission limits. |
| 0027 requires a static scene/camera, exact constant shader, ≤16 surfaces, no visible lights, positive orthonormal transforms, no jitter/TAA/MSAA/upscaler; guide receipt false | Keep closed. Its primary-ray/flat-normal producer is not the sun-shadow seam. |
| Existing indirect residency, leases, source serials, epochs and TLAS→BLAS→source release | Retain the safety ideas and re-prove them against the chosen allocator/graph. |

**Proof/plan impact.** 18.1–18.3/T02/T03/T06–T08 require current indexed/deformed geometry, topology changes, mirrors, source invalidation during build, multiple in-flight frames, allocation/residency failure and safe Off retirement. Use native shadows while a current valid result is unavailable. Do not add a shared heap, assume a fixed retirement delay, or convert a general GPU-completion observer into proof of a particular guide/reset.

Apple's refit API has its own topology, scratch and synchronization requirements if later chosen; it is not a prerequisite for this rebuild-first candidate. No Metal compilation, execution or native-Retina timing was performed.

### I18 — Actual provider producers and reset acknowledgements

**Source result.** Godot generates normalized Halton jitter using internal dimensions; its raster velocity removes jitter and stores previous-minus-current UV. FSR2 receives pixel-scaled jitter. Its reactive input is an alpha-swizzled color view; transparency/composition input is empty. The stock beta2 path sets reset false with a FIXME. OpenRC's separate native lanes add a per-view FSR2 reset patch; that fix cannot be attributed to unpatched beta2. Sources: [culling][G-CULL], [Forward+][G-FC], [FSR2][G-FSR2], [reset patch][O-FSRRESET], [FSR3 preparation][O-FSRPREP].

The NVIDIA path uses unjittered matrices, nonjittered motion and a captured draw token for tags/constants/evaluation. Its success acknowledgements remain distinct from observed GPU completion. The MetalFX path passes half the normalized jitter with a Y flip without the internal-size multiplier used by FSR2, while Apple's field is documented in pixels. This is a **source-level unit mismatch candidate**, requiring projection/sign derivation and image proof before changing it. Sources: [DLSS implementation][N-GDLSS], [token patch][O-DLSSTOKEN], [MetalFX reset patch][O-MFXRESET], [Apple field][A-JITTER], [Apple's pixel/subpixel example and static-jitter test][A-JITTER-SESSION].

**Decision.** Require a per-lane producer/consumer receipt before enabling RT plus temporal reconstruction: exact units/sign/Y, actual active extent, jitter removal owner, matrices, token, reset epoch and observed acknowledgement stage. Stock beta2 FSR2 reset is an explicit prerequisite for its RT-combination row. Existing alpha-derived reactive images do not prove a shadow-reactivity signal.

**Proof/plan impact.** 10.4/17.1: static alternating jitter at two resolutions; known object/camera motion; moving shadow over unchanged ground; odd extents; failed/delayed resets; resizing and token mismatch. A new reactive mask is conditional on a demonstrated provider-specific defect, not mandatory speculative work.

### I19 — Package completeness versus internally consistent hashes

**Source result.** The native build helper verifies the Streamline archive SHA but reuses extraction when its stamp exists and derives its DLL receipt from the files found there. The packager verifies every listed file/hash, matching editor/templates, license presence and a closed package tree. Those checks do not independently prove that the required feature roster was complete before the receipt was generated. Existing tests use a generic runtime fixture and check mutation/identity mismatch. Sources: [build][O-BUILD], [packager][O-PRODUCT], [tests][O-PTEST].

The pinned NVIDIA loader uses `LoadLibraryA` for the interposer; the inspected function/local patch stack does not add the signature verification demonstrated by [NVIDIA's manual-hooking guide][N-HOOK]. This is a bounded source finding, not a claim about every NVIDIA-internal loader. The separate [AMD SDK24 intake][O-SDK24] already verifies its staged tree and signed AMD binaries. The locally rebuilt legacy AMD runtime is intentionally unsigned and uses its build receipt.

**Decision.** Add only the missing combination manifest: feature/backend, required/disabled component, archive/member/staged hashes, header/ABI, license and applicable signature policy. Bind an interposer verification to the module path actually loaded. Do not invent a vendor-signature requirement for locally compiled binaries.

**Required faults.** Before receipt generation, omit/alter a required SDK member; after packaging, remove/change a listed file; in isolated diagnostic copies, observe missing interposer/common, DLSS pair, Reflex/PCL/Vulkan-latency component, version mismatch and disabled RR/FG libraries. The fork still requests RR/NIS and game-session DLSS-G features, so missing libraries cannot be assumed harmless. Record provider-specific fallback without relabeling independent native RT capability. Phases 15.1/17.2/T14 own these tests; none was executed here.

### I20 — Submitted-frame identity and a reproducible qualification reducer

**Source result.** Godot advances its frame ring, collects old timestamp results, swaps result metadata and updates a frame index in `_begin_frame`. RenderingServer reads profiles after rasterizer end-frame. This warrants explicit submitted-work identity; a value read during the current application frame is not automatically that frame's GPU duration. OpenRC already owns viewport timing through leases. Sources: [RD ring/timestamps][G-RD], [RenderingServer profiling][G-RS], [timing lease][O-LEASE], [Khronos timestamp sample][V-TIME].

**Proposed measurement contract.** Capture immutable run/viewport-generation/render-frame/state-epoch/history-epoch/query-slot-generation/dimension metadata when recording work. Join completed results to that receipt. Record the engine's reported profile frame separately until its relation is proven. Reject duplicates, unavailable, stale, wrong-epoch and incomplete samples; never fill zero or infer a constant frame delay. Respect query support, valid bits, period, wrap and queue domains. Do not add CPU waits to gather metrics.

Use exactly five matched A/B pairs initially: ten independent process runs ordered AB, BA, AB, BA, AB, with A raster and B requested RT. Retain 30-second warmup and 60-second measurement, all attempts, fixed content and the existing activity denominator. Compute nearest-rank p95 per run, paired differences `p95(B_i)-p95(A_i)`, their median and a deterministic paired-bootstrap 95% interval. Judge the upper interval bound against the unchanged incremental budget. An inconclusive result may use one preregistered extension to ten pairs, retaining the first five; no selective deletion or indefinite retesting.

Separate uncapped GPU-cost collection from normal 60 Hz cadence, and instrumented captures from performance runs. Record cold/warm activation and shader-compilation deltas; do not warm RT resources while Off merely to improve first-enable timing. Sources: [statistical method paper][P-STATS], [capture overhead][N-CAPTURE], [Godot compilation guidance][G-PIPE].

**Proof/plan impact.** 00.3/00.4/14.2, T03/T11: synthetic reducer fixtures and a delayed alternating-work GPU calibration. The statistical recipe is a proposed project rule, not a claim that the cited paper mandates those exact numbers. No timings or pass verdicts were generated.

## 4. Integration decisions and deliberately rejected scope

The plan keeps its **20 phases, 80 subphases and 15 test families**. This revision strengthens the existing gates rather than creating a competing implementation track.

| Accepted change | Authoritative plan location |
| --- | --- |
| Actual field/deformation census and early feasibility ledger | 3.3–3.4; 05–08 |
| Typed AS inputs, per-AS scratch first and generation publication | 3.3; 01/02/04/06/08 |
| Concrete binding, per-pass resets and independently forced fresh guides | 3.5/3.7; 09–10 |
| R32F depth conversion, single-writer packing, explicit formats/reset/validity | 3.6; 10–11 |
| Unbiased numerical oracle and static-receiver moving-shadow fixture | 3.6; 4/5; 09/11/14 |
| Exact provider units, actual reset support and stage acknowledgements | 3.9; 10/17 |
| Metal guard disposition and runtime-owned source lifetime | 3.9; 18 |
| Feature-specific package completeness and narrowly scoped faults | 3.9; 15/17 |
| Asynchronous sample identity and frozen paired reducer | 5.2; 00/14 |

Rejected as automatic next steps: changing the engine/SDK pins, adopting a path-tracing fork, adding RR/Ray Regeneration/frame generation, integrating a second denoiser, adding shadow-motion vectors before a failure is measured, changing physics or the coordinate origin system, pooling scratch before ownership proof, forcing all shadow maps off, disabling wind/casters to pass, and widening numerical/performance limits after seeing results.

**Unresolved by research alone:** actual shader compilation and reflection, GPU ordering and correctness, active field geometry, fit within the 128 MiB/2 ms budgets, temporal quality, native Retina performance, package-fault behavior and independently reviewed pilot-visible benefit. These remain implementation gates, not hidden assumptions.

## 5. Source register and retrieval limits

Immutable GitHub links identify source inspected for the pinned decision. Official rolling documentation supplies API guidance; the exact SDK/engine source wins when a version differs. Community links remain leads. The TRMV author page and indexed paper text were accessible; the full large PDF could not be retrieved through the web reader. No unavailable PDF or Reddit thread is represented as fully read.

[G-RD]: https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/servers/rendering/rendering_device.cpp
[G-GRAPH]: https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/servers/rendering/rendering_device_graph.cpp
[G-VK]: https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/drivers/vulkan/rendering_device_driver_vulkan.cpp
[G-FC]: https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/servers/rendering/renderer_rd/forward_clustered/render_forward_clustered.cpp
[G-FCH]: https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/servers/rendering/renderer_rd/forward_clustered/render_forward_clustered.h
[G-INC]: https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/servers/rendering/renderer_rd/shaders/forward_clustered/scene_forward_clustered_inc.glsl
[G-SHADER]: https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/servers/rendering/renderer_rd/shaders/forward_clustered/scene_forward_clustered.glsl
[G-SHADERCPP]: https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/servers/rendering/renderer_rd/forward_clustered/scene_shader_forward_clustered.cpp
[G-BUFFERS]: https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/servers/rendering/renderer_rd/storage_rd/render_scene_buffers_rd.cpp
[G-CULL]: https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/servers/rendering/renderer_scene_cull.cpp
[G-FSR2]: https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/servers/rendering/renderer_rd/effects/fsr2.cpp
[G-RS]: https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/servers/rendering/rendering_server_default.cpp
[G-COMP]: https://docs.godotengine.org/en/stable/classes/class_compositoreffect.html
[G-COMPT]: https://docs.godotengine.org/en/stable/tutorials/rendering/compositor.html
[G-SPATIAL]: https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/spatial_shader.html
[G-PIPE]: https://docs.godotengine.org/en/stable/tutorials/performance/pipeline_compilations.html
[G-PUSHISSUE]: https://github.com/godotengine/godot/issues/121285
[O-VEG]: https://github.com/bultodepapas/OpenRCsimulator/blob/e0a733937e255bacfe95ff09db0fb3838697239f/app/scenery/imported_vegetation.gd
[O-WIND]: https://github.com/bultodepapas/OpenRCsimulator/blob/e0a733937e255bacfe95ff09db0fb3838697239f/app/scenery/imported_tree_wind.gdshaderinc
[O-GREEN]: https://github.com/bultodepapas/OpenRCsimulator/blob/e0a733937e255bacfe95ff09db0fb3838697239f/app/landscapes/green_paradise/landscape.gd
[O-LTEST]: https://github.com/bultodepapas/OpenRCsimulator/blob/e0a733937e255bacfe95ff09db0fb3838697239f/app/tests/test_landscapes.gd
[O-VTEST]: https://github.com/bultodepapas/OpenRCsimulator/blob/e0a733937e255bacfe95ff09db0fb3838697239f/app/tests/test_landscape_vegetation.gd
[O-SCENERY]: https://github.com/bultodepapas/OpenRCsimulator/blob/e0a733937e255bacfe95ff09db0fb3838697239f/app/scenery/scenery.gd
[O-FRAMES]: https://github.com/bultodepapas/OpenRCsimulator/blob/e0a733937e255bacfe95ff09db0fb3838697239f/app/render/frames.gd
[O-LEASE]: https://github.com/bultodepapas/OpenRCsimulator/blob/e0a733937e255bacfe95ff09db0fb3838697239f/app/render/render_timing_lease.gd
[O-M0005]: https://github.com/bultodepapas/OpenRCsimulator/blob/be15feb1e781f1ae5d59cf63a284a6c8cd85ac1c/tools/graphics/metalfx/patches/0005-metal-triangle-query.patch
[O-MREADME]: https://github.com/bultodepapas/OpenRCsimulator/blob/be15feb1e781f1ae5d59cf63a284a6c8cd85ac1c/tools/graphics/metalfx/README.md
[O-M0018]: https://github.com/bultodepapas/OpenRCsimulator/blob/be15feb1e781f1ae5d59cf63a284a6c8cd85ac1c/tools/graphics/metalfx/patches/0018-metal-rt-scene-inputs.patch
[O-M0027]: https://github.com/bultodepapas/OpenRCsimulator/blob/be15feb1e781f1ae5d59cf63a284a6c8cd85ac1c/tools/graphics/metalfx/patches/0027-metalfx-opaque-rt-view.patch
[O-FSRRESET]: https://github.com/bultodepapas/OpenRCsimulator/blob/be15feb1e781f1ae5d59cf63a284a6c8cd85ac1c/tools/graphics/native/fsr_history_reset.patch
[O-FSRPREP]: https://github.com/bultodepapas/OpenRCsimulator/blob/be15feb1e781f1ae5d59cf63a284a6c8cd85ac1c/tools/graphics/native/fsr3_prepare.glsl
[O-DLSSTOKEN]: https://github.com/bultodepapas/OpenRCsimulator/blob/be15feb1e781f1ae5d59cf63a284a6c8cd85ac1c/tools/graphics/native/dlss_frame_lifecycle.patch
[O-MFXRESET]: https://github.com/bultodepapas/OpenRCsimulator/blob/be15feb1e781f1ae5d59cf63a284a6c8cd85ac1c/tools/graphics/metalfx/patches/0002-metalfx-history-reset.patch
[O-BUILD]: https://github.com/bultodepapas/OpenRCsimulator/blob/be15feb1e781f1ae5d59cf63a284a6c8cd85ac1c/tools/graphics/native/build.py
[O-PRODUCT]: https://github.com/bultodepapas/OpenRCsimulator/blob/be15feb1e781f1ae5d59cf63a284a6c8cd85ac1c/tools/graphics/native/product.py
[O-PTEST]: https://github.com/bultodepapas/OpenRCsimulator/blob/be15feb1e781f1ae5d59cf63a284a6c8cd85ac1c/tools/graphics/native/test_product.py
[O-SDK24]: https://github.com/bultodepapas/OpenRCsimulator/blob/be15feb1e781f1ae5d59cf63a284a6c8cd85ac1c/tools/graphics/native/sdk24.py
[F-HOST]: https://github.com/GPUOpen-LibrariesAndSDKs/FidelityFX-SDK/blob/c6efa6bf7f2027b3ec94f28578bb5965eabb9e55/sdk/src/components/denoiser/ffx_denoiser.cpp
[F-PREP]: https://github.com/GPUOpen-LibrariesAndSDKs/FidelityFX-SDK/blob/c6efa6bf7f2027b3ec94f28578bb5965eabb9e55/sdk/include/FidelityFX/gpu/denoiser/ffx_denoiser_shadows_prepare.h
[F-CLASS]: https://github.com/GPUOpen-LibrariesAndSDKs/FidelityFX-SDK/blob/c6efa6bf7f2027b3ec94f28578bb5965eabb9e55/sdk/include/FidelityFX/gpu/denoiser/ffx_denoiser_shadows_tileclassification.h
[F-CB]: https://github.com/GPUOpen-LibrariesAndSDKs/FidelityFX-SDK/blob/c6efa6bf7f2027b3ec94f28578bb5965eabb9e55/sdk/include/FidelityFX/gpu/denoiser/ffx_denoiser_shadows_callbacks_glsl.h
[F-FILTER]: https://github.com/GPUOpen-LibrariesAndSDKs/FidelityFX-SDK/blob/c6efa6bf7f2027b3ec94f28578bb5965eabb9e55/sdk/include/FidelityFX/gpu/denoiser/ffx_denoiser_shadows_filter.h
[F-CORE]: https://github.com/GPUOpen-LibrariesAndSDKs/FidelityFX-SDK/blob/c6efa6bf7f2027b3ec94f28578bb5965eabb9e55/sdk/include/FidelityFX/gpu/ffx_core_glsl.h
[F-VK]: https://github.com/GPUOpen-LibrariesAndSDKs/FidelityFX-SDK/blob/c6efa6bf7f2027b3ec94f28578bb5965eabb9e55/sdk/src/backends/vk/ffx_vk.cpp
[F-TECH]: https://gpuopen.com/manuals/fidelityfx_sdk/techniques/denoiser/
[V-BUILD]: https://docs.vulkan.org/refpages/latest/refpages/source/vkCmdBuildAccelerationStructuresKHR.html
[V-AS]: https://docs.vulkan.org/spec/latest/chapters/accelstructures.html
[V-TRAVERSE]: https://docs.vulkan.org/spec/latest/chapters/raytraversal.html
[V-SUBGROUP]: https://docs.vulkan.org/guide/latest/subgroups.html
[V-TIME]: https://docs.vulkan.org/samples/latest/samples/api/timestamp_queries/README.html
[A-RT]: https://developer.apple.com/documentation/metal/accelerating-ray-tracing-using-metal
[A-RES]: https://developer.apple.com/videos/play/wwdc2022/10105/
[A-REFIT]: https://developer.apple.com/documentation/metal/mtlaccelerationstructurecommandencoder/refit%28sourceaccelerationstructure%3Adescriptor%3Adestinationaccelerationstructure%3Ascratchbuffer%3Ascratchbufferoffset%3Aoptions%3A%29
[A-MFX]: https://developer.apple.com/documentation/metalfx/mtlfxtemporalscalerdescriptor
[A-JITTER]: https://developer.apple.com/documentation/metalfx/mtlfxtemporalscalerbase/jitteroffsetx
[A-JITTER-SESSION]: https://developer.apple.com/videos/play/wwdc2022/10103/?time=556
[A-FSR2]: https://gpuopen.com/manuals/fidelityfx_sdk/techniques/super-resolution-temporal/
[A-FSR3]: https://gpuopen.com/manuals/fidelityfx_sdk/techniques/super-resolution-upscaler/
[A-RRA]: https://gpuopen.com/learn/improving-rt-perf-with-rra/
[A-PERF]: https://gpuopen.com/learn/unreal-engine-performance-guide/
[N-BIAS]: https://developer.nvidia.com/blog/solving-self-intersection-artifacts-in-directx-raytracing/
[N-CAPTURE]: https://docs.nvidia.com/nsight-graphics/UserGuide/ui-launch-application.html
[N-DLSS]: https://github.com/NVIDIA-RTX/Streamline/blob/v2.11.1/docs/ProgrammingGuideDLSS.md
[N-REFLEX]: https://github.com/NVIDIA-RTX/Streamline/blob/v2.11.1/docs/ProgrammingGuideReflex.md
[N-HOOK]: https://github.com/NVIDIA-RTX/Streamline/blob/v2.11.1/docs/ProgrammingGuideManualHooking.md
[N-CMAKE]: https://github.com/NVIDIA-RTX/Streamline/blob/v2.11.1/CMakeLists.txt
[N-LICENSE]: https://github.com/NVIDIA-RTX/Streamline/blob/v2.11.1/license.txt
[N-GDLSS]: https://github.com/NVIDIA-RTX/godot/blob/135dff3887a3d2ccf45cafbd9bdffa7b718e1e76/servers/rendering/renderer_rd/effects/dlss.cpp
[EX-GD]: https://github.com/Fahien/godot-raytracing-gdscript-demo/blob/3aff9fde9fa6fdd311194b40c56023e6821e5a95/raytracing.gd
[EX-RTX]: https://github.com/bailaiOWO/rtx-godot/blob/f1df9c1d8893b6ce36ed7674a0d74b0bdef3f7bf/README.md
[P-PBRT]: https://www.pbr-book.org/4ed/Shapes/Managing_Rounding_Error
[P-TRMV]: https://zheng95z.github.io/publications/trmv21
[P-TRMVP]: https://sites.cs.ucsb.edu/~lingqi/publications/paper_trmv.pdf
[P-STATS]: https://kar.kent.ac.uk/33611/45/p63-kaliber.pdf
[C-DEPTH]: https://forum.godotengine.org/t/trouble-getting-depth-with-compositor-effect/110182
[C-SCRATCH]: https://www.reddit.com/r/vulkan/comments/ptubyg
[C-UNITY]: https://discussions.unity.com/t/ray-tracing-effects-better-denoise-solution/1619279
[C-TEMPORAL]: https://www.reddit.com/r/GraphicsProgramming/comments/izgv54/
[C-PERF]: https://www.reddit.com/r/UnrealEngine5/comments/1xwhhbk/slowly_reaching_that_sweet_90fps_ray_tracing/
