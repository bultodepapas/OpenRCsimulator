OPEN RC SIMULATOR: Apple Silicon and Metal Optimization Handoff
Prepared for: the developer responsible for Open RC Simulator
Document date: 6 November 2026, America/Bogota
Purpose: consolidate the source audits, internet research, numerical experiments, implementation sketches, rejected approaches, and remaining validation work into one actionable engineering document.
Read this before implementing: this document consolidates evidence from several explicitly identified revisions. It is not a fresh audit of the current branch tip. A historical defect must be checked against today's source before opening or fixing it. CPU numerical results, Godot language checks, repository-recorded Mac measurements, and proposed architectures are distinguished throughout.

Contents
1. Purpose and reading guide
2. Source revisions and evidence
3. Executive decisions
4. Simulator contracts to preserve
5. What already exists and what the M1 evidence supports
6. Historical audit findings to recheck
7. Cloud density through interval bounds
8. Hash-lattice textures and independent mip levels
9. Bounded cloud-transmission polynomial
10. Integer noise factoring
11. Zero-contribution sky patch
12. Angular algebra and shared powers
13. Terrain and grass algebra
14. Solar lookup and rejected relief bundle
15. Native-resolution aircraft crop
16. Native Metal rate maps and engine boundaries
17. Other shader, cache, and rendering work
18. CPU and physics findings from the later audit
19. Tools, libraries, compiler work, and packaging
20. Implementation work packages
21. Benchmark and correctness acceptance protocol
22. Reproduction and artifact inventory
23. Source map and references
24. Developer completion checklist
1. Purpose and reading guide
The strongest opportunity is to reduce the mathematical work performed by the actual rendering path: prove that some contributions are zero, bound unevaluated noise, exploit integer structure, and design approximations for the small domains the simulator actually uses.

The evidence also argues for disciplined performance measurement. A faster requested configuration is meaningless if the renderer silently falls back; an improved shader average is insufficient if startup, frame pacing, memory, or moving-aircraft readability regresses.

This handoff covers four related bodies of work:
- The original Apple Silicon audit, including benchmark correctness, renderer lifecycle, tools, and native export concerns.
- The first experimental kit: density bounds, hash-lattice textures, solar lookup, relief caching, aircraft-crop geometry, and native Metal rate-map research.
- The mathematical lab: conditioned interval evaluation, bounded exponential approximation, integer factoring, angular identities, terrain counterexamples, and a small sky patch.
- A separately saved later numerical audit: duplicate aircraft air sampling, model-geometry preparation, and a ground-vehicle passivity defect.
The last body of work uses a different source revision and is presented separately in Section 18. It contributes useful CPU and correctness evidence; it must not be mixed into the earlier shader benchmark baseline.

For implementation, start with Sections 2–6, then the work packages in Section 20. For mathematical review, prioritize Sections 7–13. For reproduction, use Section 22 and the original archives.
2. Source revisions and evidence
2.1 Revision ledger
Evidence set	OpenRC revision	Role
Original Apple Silicon audit, 5 November	fc018b38e44bfd3b83d46c88f7e6c6ab0c8137ab	Historical CI, benchmark, cache-lifecycle and renderer findings
Earlier broad rendering commit discussed by that audit	e9bb60291be353b7051a3d4ae13afef6ac670bd4	Context for the original default/cache evidence mismatch
Experimental kit and mathematical lab	93ffbb101917dff86ecc2632f07e2e45c450a178	Main shader and architecture research baseline
Later, separate numerical audit	3df2791752fe2c1faad132fcb11febbb0ae788d1	CPU air-data reuse and ground-vehicle numerical findings


The research engine was Godot 4.8.beta2.official.cafc17a19, full engine source revision:

cafc17a192acf67903910a68aeb3c076c0907a4b.

The mathematical lab records the Linux engine executable SHA-256:

34d0599a1f17acc76583610969878065d1b1701615af77271e32201351b9c564.

The shader experiments used Linux x86_64, Python 3.12.14 and NumPy 2.3.5. Their native Metal GPU execution was unavailable. The later CPU audit used the pinned Linux debug editor on a shared Intel Xeon Platinum 8573C.

No new benchmark or repository audit was performed while assembling this handoff. The saved archives were recovered and checked, and the mathematical archive's manifest matched its retained files.
2.2 Evidence vocabulary
Evidence type	What it supports	What it does not establish
Source inspection	A code path, formula, resource choice, or conditional failure mechanism	Frequency, current-HEAD status, measured product impact
Repository-recorded Mac result	The named historical host, candidate, workload and measurement	A new candidate's speed or general product qualification
Exact-real derivation	An identity or bound under its mathematical assumptions	Actual compiler evaluation order or GPU output
CPU float32 screen	Agreement or counterexamples for the specified arithmetic model and inputs	Exhaustive float32 correctness or native Metal behavior
Godot shader-language check	Parsing/type checking through the pinned front end	Metal compilation, texture sampling, image parity or GPU timing
Headless camera-method test	Actual pinned Camera3D geometry/API behavior	Seamless scene composition or rendering performance
Later reference-kernel audit	Its reported production/reference numerical checks	Native ARM64 parity or whole-frame Apple performance
Proposed architecture	A mechanism and a testable implementation direction	Implemented, qualified or profitable production behavior


Every operation-count reduction in this document is scoped to its expression or logical evaluations. None is an FPS prediction.
3. Executive decisions
1. Reconcile evidence before accepting optimizations. Recheck the historical acceptance, effective-render, profiling, source-identity and cache-readiness findings on the current branch.
2. Use the working C2+C5b stable ImageTexture baseline. The old C5 black-output problem was a texture-path/backend issue. It is not evidence that every interpolation-based technique fails.
3. Prioritize cloud interval termination and the high-octave hash-lattice atlas. They target repeated procedural work and have substantial numerical screening.
4. Qualify the small zero-contribution patch independently. It is a narrow implementation candidate with complete source and successful language checks.
5. Measure degree-five and degree-six transmission polynomials against native exponential lowering. Their error is bounded; their speed is unknown.
6. Treat integer factoring and shared powers as generated-code experiments. The compiler may already remove some source redundancy.
7. Retain negative results. Mask-only wrapping showed no useful M1 gain; naive squared-distance ordering changes parcel identities; the tested post-threshold relief bundle has unfavorable error/memory tradeoffs.
8. Keep the native-pixel aircraft crop as a larger renderer prototype. Its projection geometry was tested. Scene rendering and performance remain open.
9. Gate engine-level Metal work on a demonstrated limitation. Native rate-map import has a real source seam, but ordinary desktop VRS settings do not complete the integration.
10. Handle the later tire/brake passivity finding as a correctness issue. Separately, the same later audit provides a concrete CPU optimization: reuse one air-data result inside the downwash pre-step.
4. Simulator contracts to preserve
The proposed visual optimization work preserves:
- Float64 flight simulation and the existing 240 Hz RK4 integration policy.
- Accepted simulation time, deterministic input timing and replay.
- Atomic simulation-state publication, refusal/rollback behavior and observer semantics.
- The primary product target of actual 1920×1080 output, before higher-output qualification.
- Aircraft visibility, thin features, propeller readability, correct occlusion, and control response.
- Analytic fallbacks for absent, unready, stale or unsupported visual caches.
- Compatibility and other supported renderer paths.
- Headless operation without unintended graphical resource creation.
Visual cache updates must follow the accepted simulation clock and explicit invalidation. Shader work must not feed altered state or time back into physics. Approximate visual functions are not permission to approximate the flight integrator.

The later CPU air-data optimization has a narrower sharing scope: one callback, one committed state, one time, one model and one density. It must not become a cache across RK stages.
5. What already exists and what the M1 evidence supports
5.1 Existing Apple and rendering work
The original audit already found Apple Silicon Mobile/Metal selection, renderer recovery, geometric shoreline clipping, incremental sky radiance, MetalFX policy, matched-flight collectors and sustained evidence. Recommending these as unimplemented features would duplicate work.

At the 93ffbb shader baseline, a 2048×2048 RG16F stable ImageTexture exists per cloud seed:
- R stores full five-octave noise used for ground/near-grass cloud shadows.
- G stores the unnormalized first three octaves used by C5b sky relief.
- The last two relief octaves remain analytic.
- The sky cloud silhouette remains analytic.
- Base texture storage is 16 MiB per seed, excluding CPU copies, temporary render targets and allocation overhead.
The earlier C5 failure was later diagnosed as Mobile/Metal sky shaders reading the previous ViewportTexture as black. Publishing a stable ImageTexture fixed that path. The original audit's attribution of that failure to interpolated neighbor differences is superseded.

This correction does not invalidate the separate later relief-bundle experiment: that experiment independently found numerical errors from filtering already-thresholded densities.
5.2 Historical Mac measurements
The R4 host was reported as MacBookAir10,1, seven-core M1 GPU, 8 GiB memory, macOS 27.0.1, AC power, built-in 2560×1600 display. The named sweep used official beta2, Mobile/Metal, Medium scenery and an uncapped technical-flight circuit; each cell had 10 seconds of warmup and 20 seconds of observation.
Historical observation	Recorded result	Interpretation
Internal scale 1.0 → 0.5 with 4× MSAA	38.3 → 89.6 FPS	Strong pixel sensitivity for that workload
Profiled pass attribution	28.42 ms total, 22.34 ms opaque	Opaque work dominated that diagnostic frame
Hide ground material	About 11.08 ms less GPU time	Ground shading deserves investigation; visibility changes prevent additive budgeting
Disable cloud shadows	About 3.55 ms less GPU time	Five-octave shadow noise was a justified target
Disable sky clouds / relief	About 7.59 / 2.34 ms less GPU time	Separate sky diagnostics, not additive guaranteed savings
Five short Metal/GL pairs	Metal +32.2–36.3% FPS	Useful renderer comparison; native-Retina p95 still roughly 27.2–28.5 ms
Earlier beta1 six-run sustained bundle	+17.64–23.17% paired FPS	Six shaders plus lighting WeakRef reuse in that engine; not isolated shader attribution
Earlier combined C1+C2+D1 profile	61 FPS; p95 17.28 ms; p99 29.11 ms	Short diagnostic result; p99 still missed the named screen


The earlier C2-only tile screen reported 28.09 → 25.72 ms, but used a different candidate from the later RG16F hybrid. Do not attach that old result to arbitrary default-on source.

The later, working C2+C5b record at 93ffbb reported:
Configuration	GPU time
Tile off	26.20 ms
Tile on	23.45 ms
Default	23.44 ms


The off/on difference is 2.75 ms, approximately 10.5%. These were single profiled runs. Separate 1920×1080 pilot/aircraft-ground stills had maximum differences of 2/255 with no pixels above that threshold. They do not establish moving-flight or sustained qualification.
5.3 Pixels and pacing
Output and setting	Approximate internal pixels
2560×1600 at scale 1	4.096 million
2560×1600 at scale 0.75	1920×1200 = 2.304 million
2560×1600 at scale 2/3	About 1707×1067 = 1.82 million
1920×1080 native	2.074 million
3840×2160 at scale 0.5	1920×1080 = 2.074 million


A window size in macOS points is not necessarily the drawable size. Record output, drawable and internal dimensions.

A historical MetalFX 2/3 diagnostic recorded 28.26 → 18.68 ms, versus 16.87 ms for matched bilinear scaling. MetalFX had a reconstruction cost and reportedly improved distant-aircraft readability. This supports a quality/performance comparison, not an automatic recommendation to select it.

A 60 Hz interval is 16.67 ms. The project's p95 ≤18 ms and p99 ≤25 ms screens are engineering gates; they allow missed refresh intervals. CPU and GPU durations overlap, so they should not simply be summed.

Evidence: original audit AUDIT, later kit KIT, and the pinned repository R4/R5 records.
6. Historical audit findings to recheck
These findings were established at fc018b. Their status at current HEAD was not revalidated for this handoff. A subsequent fix should close the corresponding item rather than preserve it as an open defect.
6.1 CI and release preflight
GitHub Actions run 42120685263, job 127571913297, rejected five missing Godot UID sidecars:
- renderer_guard.gd.uid
- cloud_shadow_map.gd.uid
- cloud_shadow_map.gdshader.uid
- test_cloud_shadow_map.gd.uid
- test_renderer_guard.gd.uid
Downstream app, visual, native and release jobs did not run in that workflow. Recheck the current pipeline; if still missing, generate and track sidecars with the pinned editor. Bypassing the preflight would invalidate the downstream claim of qualification.
6.2 Requested rendering versus effective rendering
The fixture recorded effective_render, but the reducer did not include it in normalized acceptance identity. A synthetic case requested MetalFX Spatial Quality while recording Native, fallback=true and device-unsupported, yet still returned performance/health/checked eligibility.

Required repair, if still applicable:
- Reconcile actual renderer method/driver, selected reconstruction provider, scale, MSAA and fallback reason.
- Reject a requested-versus-effective mismatch from the intended comparison.
- Distinguish a selected enum/property from demonstrated GPU execution.
- Represent unavailable execution evidence explicitly rather than treating it as success.
Relevant files: research/performance/native_summary.py and research/performance/sustained_flight.gd.
6.3 Diagnostic profiling could qualify as performance acceptance
Adding --gpu-profile to the checked engine command still left the synthetic record performance-eligible. Classify profiled/captured runs as diagnostics and exclude them from clean performance acceptance. Keep them for attribution.
6.4 Source identity omitted new rendering inputs
The sustained fixture hashed 16 named inputs and omitted the new cloud map owner/shaders, tile environment setting and effective bake state. Different default rendering could retain the same normalized source/scenario identity.

Bind the complete relevant source and dirty patch, explicit cache state and successful bake generation. An unset environment variable no longer necessarily means that the cache is off.
6.5 Cloud-cache readiness and failure fallback
At the historical revision, texture_for() created a zero-filled placeholder and apply() enabled it before a validated bake. A null/empty/wrong-size readback freed the viewport while leaving the placeholder enabled, with no scheduled retry.

This was a conditional failure found by inspection, not a reproduced Mac incident. Verify whether later commits corrected it.

A sound publication model is:
absent/unready -> keep analytic rendering
baking -> keep analytic rendering
validated texture for expected seed/generation -> publish atomically
failed/stale bake -> keep analytic rendering; record bounded retry/failure state
Test seed changes beyond four unique values, layer removal, rewind, scene teardown, headless startup, Compatibility and failed bakes. Four 16 MiB textures alone account for 64 MiB; this is not a measured whole-process footprint.
6.6 Recovery and confirmation lifecycle
The startup confirmer counted at least 120 process callbacks and three seconds; it did not prove presentation or a valid frame. The Home route armed the guard, while direct-flight paths and later faults had different coverage.

The historical MetalFX toggle sequence also exposed a possible stale-timer race: disabling cleared a marker, but an old timer could later clear a newly enabled marker. Use activation generations or cancellable confirmations. Validate actual route/toggle behavior on an exported app.
6.7 Shoreline transaction behavior
Horizon.with_hole() refused a hole entirely inside one source triangle. The lake attachment logged a failed cut and continued publishing the lake and physics metadata.

This is a conditional custom-lake risk, not a reproduced default-lake defect. A small accepted lake inside a coarse triangle needs a focused fixture. Either complete the ground cut or publish a coherent fallback before exposing the lake as active.
6.8 What was corrected by later evidence
Original concern	Later evidence / treatment
Published C2 evidence did not qualify the new hybrid	Later C2+C5b has its own named single-profile and still-image results
Earlier C5 flattening interpreted as interpolation failure	Superseded by black ViewportTexture sampling diagnosis and stable ImageTexture fix
UID, reducer, readiness, timer and shoreline findings	Recheck current source; these were not automatically disproved by the later shader results
Post-threshold relief cache quality	Separate later experiment; its unfavorable numerical results remain relevant


7. Cloud density through interval bounds
Priority: first numerical GPU prototype.
Targets: cloud_field_fbm(), cloud_density(), cloud_field_threshold(), and the C5b cloud_detail_density() consumer.
Evidence: KIT bounds prototype, extended by MATH interval experiment.
7.1 Exact-real derivation
The five value-noise octaves have weights:
\[
a_i\in\left\{\frac12,\frac14,\frac18,\frac1{16},\frac1{32}\right\},
\qquad A=\sum_i a_i=\frac{31}{32}.
\]
For ideal octave values \(n_i\in[0,1]\), let \(S\) be the already evaluated weighted sum and \(R\) the sum of remaining amplitudes. Then:
\[
F\in\left[\frac{S}{A},\frac{S+R}{A}\right].
\]
The source evaluates:
\[
D=\operatorname{smoothstep}(1-c,1.25-c,F),
\]
where \(c\) is the original local coverage after clustering, not merely the global coverage uniform.

Consequently:
\[
S+R<A(1-c)\implies D=0,
\qquad
S>A(1.25-c)\implies D=1.
\]
When neither condition holds, evaluate the original next octave. Near a visible transition, the complete original expression remains available.
Octaves completed	Raw remaining amplitude	Remaining normalized contribution
1	15/32	15/31
2	7/32	7/31
3	3/32	3/31
4	1/32	1/31


This optimizes a density consumer. A tile baker or other caller that needs continuous raw noise cannot substitute a saturated density for that noise.
7.2 Original analytic-field experiments
The first kit checked variants after two, three and four octaves:
Screen	Parameterized comparisons	Differing CPU outputs
cloud_bounds_screen.py	34,775,040	0
early2_screen.py	47,185,920	0
adversarial23.py	23,183,360	0
Total	105,144,320	0


These reuse coordinates across parameters. They are not 105 million independent observations of a device.

For one 256² periodic grid, seed 1253, coverage 0.35 and clustering 0.35:
Check placement	fBm value-noise octave evaluations skipped	All hash work skipped, including cluster work
After three octaves	31.638%	26.365%
After two octaves	39.778%	33.148%
After two and three	44.897%	37.415%
After two, three and four	45.993%	38.328%


Coverage changes the result. At coverage 0.65 and clustering 0.35, the two-only test skipped 7.117% of fBm value-noise octave evaluations, whereas three-only skipped 10.881%. The fBm/density consumer still runs; these counts describe its internal octave work.

Only 68.08% of sampled 2×2 blocks agreed on the two-octave decision, and 73.44% agreed on the three-octave decision. These are spatial-coherence proxies, not Metal SIMD measurements.
7.3 Extension to the current C5b relief path
C5b already samples the first three octaves from the low-frequency tile. Only the final weights 1/16 and 1/32 remain. Test an interval with \(R=3/32\) immediately after that sample; after evaluating octave 3, test with \(R=1/32\).

The later experiment first filtered positions to those whose full analytic CPU-reference body density was positive, because that is where the source can call relief. It then used the actual near/mid/far offsets 0.10, 0.28 and 0.62 along the light ray.

Each of the three calls normally requires two high octaves, making six the baseline:
Scenario	Active body points	Near / middle / far mean	Total mean out of six	Logical reduction
Coverage .35, cluster 0, ray (0,1)	9,717	1.8444 / 1.3899 / .8438	4.0781	32.03%
Coverage .70, cluster .8, ray (-2.8,2.1)	41,063	.9774 / .8102 / .7528	2.5404	57.66%
Coverage .15, cluster 1, ray (0,1)	6,523	1.8781 / 1.6482 / 1.3184	4.8447	19.25%
Coverage 1, cluster 1, ray (-2.8,2.1)	61,759	.7792 / .7655 / .7767	2.3213	61.31%


The unconditioned default full field averaged 2.5641/5 octaves. The unconditioned C5b case averaged .4166/2, but that overstates relief opportunity because most clear-body positions do not call relief. Use the conditioned table for that consumer.

The later screen checked 18 scenarios of 65,536 positions through both full and detail paths, plus the conditioned offsets. Recorded output-bit mismatches were zero. A deliberately incorrect zero-remaining-amplitude rule produced 9,717 mismatches.
7.4 Numerical and implementation qualifications
The original prototype used an empirical 1e-5 margin in normalized-noise units. The later one used 1e-4 in raw weighted-sum units:
zero if S + R + margin < A*(1-c)
one  if S     - margin > A*(1.25-c)
otherwise continue
These margins have different units. Neither is a universal proof for Metal fast math.

The later harness computes every octave to obtain the reference and infer which work could be skipped. It is not an early-exit shader benchmark. The low tile is modeled with half-float texels and ideal float32 bilinear interpolation; actual sampler precision is unmeasured.

Implementation must:
- Preserve the original cluster expression, seeds, period handling, fallback and ambiguous-value arithmetic.
- Compute local coverage before interval classification.
- Preserve the existing zero-coverage shortcut without counting it as a new saving.
- Establish an outward error enclosure for interpolation, summation and thresholds on the actual backend.
- Measure branch/coherence and register effects.
- Test sky, spatial and canvas consumers, seams, seeds, dense/sparse clouds and motion.
The first kit provides front-end-checked after-three and after-two/three shader sketches. The later conditioned interval experiment is CPU-only; it is not one of the seven mathematical shader checks.

An additional unimplemented idea is a conservative spatial min/max atlas. Bounds must use outward rounding and exact/nearest fetches; interpolated min/max values are not automatically conservative. A 2048² RG16F bound atlas alone costs 16 MiB per seed. No speed or correctness result exists for this extension.
8. Hash-lattice textures and independent mip levels
Priority: first native texture experiment alongside interval evaluation.
Target: the four corner hashes in cloud_field_value_noise().
Evidence: KIT, cloud_prototype/.
8.1 Preserve the interpolation, precompute its corner values
The source uses quintic value noise:
\[
u(f)=f^3\bigl(f(6f-15)+10\bigr).
\]
Store the scalar hash at each integer lattice corner. An ideal linear sample at:
\[
\mathrm{uv}=\frac{\lfloor p\rfloor+u(\operatorname{fract}(p))+0.5}{N}
\]
performs the original four-corner bilinear interpolation, using the original quintic weights. The half-texel offset is essential.

The tested atlas is 1024² RG16F:
- R: octave 3, period 512, repeated 2×2.
- G: octave 4, period 1024.
- Linear filtering, repeat addressing, explicit LOD 0, no mip filtering for this atlas.
- Current low-octave cache and exact silhouette preserved.
- Correct seed/readiness fallback retained.
For three fully evaluated relief offsets, the source-level trade is 24 hash calls removed, six texture fetches added, and three existing low-tile samples retained.

Persistent addition: 4 MiB per seed, or 16 MiB for four seeds, before temporary resources.
8.2 Numerical results
Eight scenarios used 8,192 coordinates each, covering five distinct seeds in total, with three relief offsets per point:
Comparison	Maximum observed CPU-model difference
Current C5b → lattice candidate density	0.00013393163681030273
Current C5b → candidate active-cloud scalar relief	0.0002461075782775879
Exact full noise → current C5b density	0.015202224254608154
Exact full noise → candidate density	0.015269458293914795
Exact → candidate with ideal low octaves	0.00013402104377746582


These are different comparison baselines. The current low tile dominates the full-reference difference in that model; the candidate's incremental difference is much smaller. None is an encoded display-pixel error.

Useful controls:
- Periodic repeat on a binary-fraction grid: zero difference.
- Independent integer/double oracle on 1,024 binary-exact inputs: maximum octave difference 1.1920929e-7.
- Missing half-texel offset: maximum octave error 0.62684.
- Wrong seed: maximum octave error 0.96920.
Sensitivity studies matter:
- A hypothetical eight-fractional-bit interpolation model increased default density error to .00071239 and scalar-relief error to .0011220. This does not identify Metal's actual sampler precision.
- Direct quantization of exact corners to RG16_UNORM reduced the modeled default density/relief errors to approximately 8.94e-6 / 1.23e-5. This result cannot be obtained by first rounding through an RG16F bake target; format creation, filterability and the true bake path remain unverified.
The test's .001 density threshold was a development screen, not an approved visual tolerance.
8.3 More aggressive representation: independently authored mips
An unimplemented extension stores all five octave lattices in one texture:
Mip	Resolution	Independent octave
0	1024²	4
1	512²	3
2	256²	2
3	128²	1
4	64²	0


Use integral LOD 4-octave with an explicitly mip-enabled sampler. Do not generate these levels by downsampling: each octave has an independent seed seed + octave*7919.

The five useful levels contain 1,396,736 samples: approximately 2.664 MiB R16F or 5.328 MiB R32F per seed, excluding tiny tails, padding and allocation overhead. This is memory accounting, not evidence that it replaces the current 16 MiB tile profitably.

Under ideal interpolation, binary16 corner quantization alone is bounded by 2^-12 in normalized fBm. The .25-wide smoothstep has maximum derivative 6, so the corresponding density bound is .00146484375. This excludes coordinate, sampler, compiler, lighting and output effects.

Qualify manual mip upload and mip access in the pinned engine. R32F filtering needs a feature check. Rectangular stretched fields need their own exact periods and representation.
8.4 Adoption decision
Retain only if actual target output and total frame cost improve against current C2+C5b. Integer ALU savings may be outweighed by texture traffic, cache misses, occupancy, bakes or synchronization. Keep seed changes, periodic seams and the stable ImageTexture publication behavior in the trial.
9. Bounded cloud-transmission polynomial
Priority: a small controlled shader trial after the baseline is trustworthy.
Target: app/render/cloud_relief.gdshaderinc.
Evidence: MATH, exp_polynomial/.
9.1 Domain derived from the source
The source computes:
\[
\tau=.65d_n+.45d_m+.25d_f,\qquad x=1.6\tau,\qquad T=e^{-x}.
\]
For densities in [0,1], ideal x lies in [0,2.16]. The supplied guard uses the binary32 endpoint:
\[
X=9059697/4194304=2.1600000858306885,
\]
with center:
\[
C=X/2=1.0800000429153442.
\]
Out-of-domain inputs use the original exponential expression. Do not clamp the domain silently.
9.2 Construction and proof
These are truncated Chebyshev-series polynomials, not minimax polynomials.
1. Construct the exact rational Taylor polynomial \(Q_{32}(x)=\sum_{k=0}^{32}(-x)^k/k!\).
2. Bound the Taylor remainder on [0,X] by \(X^{33}/33!\).
3. Convert \(Q_{32}(C(1+y))\) exactly into Chebyshev coefficients.
4. Retain degrees through n and bound the discarded tail with \(|T_k(y)|\le1\) on [-1,1].
5. Convert back to coefficients in \(t=x-C\).
6. Quantize coefficients to the actual binary32 values.
7. Bound that coefficient change by \(\sum_j|a_j-\hat a_j|C^j\).
The real bound covers exact evaluation of the polynomial with quantized coefficients.

A separate conditional bound includes rounding of t=x-C and each Horner stage. It assumes round-to-nearest binary32, gradual underflow, the stated ordering and true correctly rounded FMA. Center subtraction is not assumed exact:
\[
|\delta t|\le2^{-24}C+2^{-150}\approx6.437302\times10^{-8}.
\]
The derivative bound is evaluated over the expanded radius \(C+|\delta t|\).
9.3 Results
Degree	Real bound including coefficient quantization	Conditional IEEE-RN FMA bound	Observed host-FMA maximum
4	2.9920e-4	2.9939e-4	2.9921e-4
5	2.641706e-5	2.660503e-5	2.645865e-5
6	2.026621e-6	2.214913e-6	2.112994e-6
7	1.57923e-7	3.46265e-7	2.7069e-7
8	4.34325e-8	2.31783e-7	1.6788e-7


Bounds are rounded upward. The host comparison used 1,000,001 grid inputs, 250,000 fixed-seed random inputs and seven special values: 1,250,008 total. The reference is NumPy binary64 exponential at the same float32 inputs, not interval-certified infinite-precision sampling.

The C harness also evaluates separately rounded multiply/add:
- Degree 5 bound 2.666935e-5; observed maximum approximately 2.650408e-5.
- Degree 6 bound 2.279280e-6; observed maximum approximately 2.112994e-6.
Nine out-of-domain/nonfinite host fallback cases passed, including NaN classification. This does not establish Metal fast-math NaN behavior or payload preservation.

Degrees seven/eight show diminishing benefit because evaluation rounding becomes material.
9.4 Native Metal sketch
The archive includes both degree-five and degree-six functions. The degree-six function is:
inline float research_cloud_transmission_deg6(
    float optical_depth, bool enable_polynomial
) {
    float x = 1.6f * optical_depth;
    if (enable_polynomial && x >= 0.0f && x <= 2.16000009f) {
        float t = x - 1.08f;
        float p =  0.000491670449f;
        p = fma(p, t, -0.00297039864f);
        p = fma(p, t,  0.0141351372f);
        p = fma(p, t, -0.0565167814f);
        p = fma(p, t,  0.16980119f);
        p = fma(p, t, -0.339607567f);
        p = fma(p, t,  0.339595377f);
        return p;
    }
    return exp(-1.6f * optical_depth);
}
All decimal coefficients were checked against the retained binary32 bit patterns. The Godot helpers passed the front end. The native MSL sketch was not Metal-compiled. The host C11 evaluator was compiled and executed.
9.5 Downstream error and performance decision
The relief scalar's transmission coefficient is:
\[
.38+.12\,\mathrm{edge}\,\mathrm{forward}.
\]
For body and forward in [0,1], edge=4 body (1-body) lies in [0,1], so the coefficient is at most .5. The final clamp is nonexpansive. A real transmission error bounded by B therefore changes the clamped scalar by at most B/2.

For degree six, that is approximately 1.013311e-6, then multiplied by the absolute light-color channel. Subsequent arithmetic, possible normalized-dot overshoot, HDR exposure, tone mapping and quantization are outside this bound.

Test degree five first and degree six as the tighter-error option. Native exponential lowering may already outperform five/six dependent FMAs. Inspect the emitted code, complex-function/ALU utilization, register demand and full-pass timing.
10. Integer noise factoring
Target: cloud_field_hash2(), wrapping and four-corner value noise.
Evidence: MATH, integer_noise/.

The hash structure is:
\[
H(x,y,s)=\bigl((xA)\oplus(yB)\oplus(sC)\bigr)A\pmod{2^{32}},
\]
where A=1597334677, B=3812015801 and C=2654435761.

Compute xA, yB and sC once. Obtain neighboring products by adding A or B, except when the coordinate wraps to zero. Preserve the final multiplication for each of the four corner hashes.

This expresses seven source multiplications instead of sixteen, plus neighbor additions/selects. It does not imply the compiler emits nine fewer instructions; common-subexpression elimination may already share products.

Supported square periods are 4, 64, 128, 256, 512 and 1024, with an explicit base-or-cluster context guard. Unsupported, stretched or nonsquare paths retain the original implementation.

Preserve the original floating mod, floor, quintic weights and interpolation order.
10.1 Observed agreement
- 34,348,032 corner hashes: zero mismatches.
- 250,000 same-wrapped-coordinate noise points per period, 1.5 million total: zero CPU-model output-bit differences.
- Intended Euclidean integer-wrap comparisons passed.
Negative signed GLSL remainder is not portable. The negative-coordinate tests compare with intended Euclidean behavior, not a guaranteed result from every original shader backend.
10.2 Variants and counterexamples
Transformation	CPU result	Decision
Remove floating wrap, domain [-128,128)	38,197/250,000 five-octave outputs differ; max 4.47035e-6	Reject as bitwise-equivalent rewrite
Remove floating wrap, domain [-3,67)	19,125/250,000 differ; max 3.45707e-6	Same issue in a near-wrapped domain
Wrap once then double	1,980,385 finite float32 inputs × five octaves, zero wrapped-coordinate bit differences	Interesting conditional candidate; Metal behavior unverified
Negative subnormal coordinates	Three targeted cases yield negative wrapped q in the CPU model	Preserve domain/FTZ/remainder qualifications


The existing project already tested mask-only wrapping on M1: 28.40 ms versus 28.42 ms, treated as no useful gain and reverted. The additional four-corner factoring is the new part worth testing.
11. Zero-contribution sky patch
Narrowest complete source patch: math_lab/exact_support/sky_support.patch.
Baseline: 93ffbb.
Status: patch applicability and Godot language checks passed; no target GPU output/timing.

The patch makes exactly three changes:
1. Move the existing c <= 0 return in sun_disc_profile() directly after the dot product, avoiding projection, lengths and asin on that hemisphere.
2. When uniform sun_scatter == 0, return haze_lin + lobe_term(d) before the directional power.
3. In the classic-cloud branch, compute smoothstep(.03,.25,EYEDIR.y) first and call cloud_density() only if that fade is positive.
The third change retains independent cirrus, including .02 < EYEDIR.y <= .03, where the main cloud fade is zero but cirrus may contribute.

The new density branch contains no texture sampling or derivative operations and reconverges before later work. The sun-disc helper also has no derivative call in the skipped work. The moon's derivative-sensitive path is preserved.

The equivalence claim is for intended physically bounded inputs with finite intermediates. Finite inputs alone can still overflow intermediate expressions; signed zero and backend reassociation also prevent universal bitwise assertions.

Layered-cloud compositing is unchanged. In particular, at alpha=0 the expression 1-(1-density)*(1-alpha) is a real identity but its subtract/subtract round trip is not always a bitwise identity. Skipping that whole branch requires a separate numerical decision.
12. Angular algebra and shared powers
Evidence: MATH, angular_algebra/. These are real identities or support arguments with measured float32 differences.
12.1 Aureole support before acos
The existing aureoles return zero at angular radii of at least 45 degrees. In ideal normalized geometry, a dot-product test can reject that region before acos.

The sketch compares against 0.7071057558059692, approximately cos(45°) minus a 1e-6 dot-space guard.
- 1,977,069 values: zero false culls in the CPU model.
- Eighteen already-zero samples retained within the conservative boundary.
- Deliberately unsafe threshold .71: 5,840 false culls, detected.
A 45° cap covers 14.6447% of a full sphere. Camera pixels and performance do not follow directly from that area. Disabled aureoles already have uniform early exits.

Do not move moon_disc()'s fwidth(rr) behind a varying branch.
12.2 Eliminate a square-root/square round trip in air mass
For the same already-rounded squared horizontal length q:
\[
s=\min(\sqrt q,1),\qquad
X=\frac1{\sqrt{1-.96s^2}}
\]
becomes, in real arithmetic:
\[
X=\frac1{\sqrt{1-.96\min(q,1)}}.
\]
The source clamp is preserved; one square root is removed.

Across 1,101,341 inputs:
- Maximum air-mass difference: 7.62939453125e-6.
- Maximum relative difference: 1.554334e-6.
- At default extinction k=.2, sun-path difference: 5.960465e-7.
- Normalized moon-path difference: 3.576279e-6.
GPU dot contraction and native inversesqrt are outside this CPU model.
12.3 Recover the moon tangent from Cartesian coordinates
The source's east tangent is (-sin(lon),cos(lon),0), with longitude from atan2. Away from the pole:
\[
e=\frac{(-p_y,p_x,0)}{\sqrt{p_x^2+p_y^2}}.
\]
Keep longitude for UVs. Retain the original trig path when squared xy radius ≤1e-12.

Across 550,006 directions, 25,002 used the polar fallback. Maximum tangent-vector difference was 3.47552e-7; the modeled normal-mapped frame's maximum component difference was 3.42727e-7.

This is lower priority because the textured moon usually occupies a small screen region.
12.4 Share one addition chain for powers 8, 12 and 24
float x = max(cosine_angle, 0.0);
float x2  = x * x;
float x4  = x2 * x2;
float x8  = x4 * x4;
float x12 = x8 * x4;
float x24 = x12 * x12;
Five shared multiplications produce all three powers. Reuse only when the consumers have the same light cosine. Do not conflate sun, moon or alternate dominant-light directions.

Keep the original absence of an upper clamp. The 996,895-input screen includes small overshoot above one. Maximum differences versus binary64 powers were approximately 1.95e-7, 2.97e-7 and 5.96e-7 respectively.

Constant powers may already be strength-reduced. Explicitly shared intermediates may also lengthen live ranges and increase registers. Generated-code inspection decides whether the source rewrite is useful.
13. Terrain and grass algebra
Evidence: MATH, grass_algebra/. Main targets are ground.gdshader and grass_surface.gdshaderinc.
13.1 Share the identical pilot distance
rough_grass_colour(world_pos.xz) computes distance(p,pilot_xz); the ground fragment later computes the same distance again with unchanged arguments.

A ground-specific helper taking an already-computed distance can express two calls as one. Keep the original-signature wrapper for other include consumers. No derivative relocation is necessary. Compiler inlining/CSE may already eliminate the duplication; no performance result or production patch exists for this candidate.
13.2 Squared-distance ordering changes rounded ties
The parcel shader ranks nine hashed sites using rounded distances and strict less-than comparisons. Sorting by squared distance and taking only two final square roots preserves real-number ordering, but may alter ties created by the original square root.

At position (-1295.2213134765625,31.047367095947266), with field size 230 and blend width 80:
Candidate, in source loop order	Squared distance	Float32 square root
Cell (-6,-1)	24180.30859375	155.50018310546875
Cell (-7,0)	24180.3046875	155.50018310546875


The original retains the earlier second-nearest site (-6,-1). Squared ordering selects (-7,0). The nearest site remains (-6,0).
Screen	Points	Ordered site-pair changes	Raw color changes	Maximum raw component difference
Random annulus, 700–3000 m	500,000	0	0	0
Procedural bisectors and adjacent float32 coordinates	900,000	6,640	1,692	0.2948699


The latter intentionally concentrates on difficult boundaries; its frequency is not a predicted share of screen pixels. The color difference is before outer blending and display conversion.

Decision: do not merge the naive rewrite under an exact-equivalence claim.
13.3 Guarded parcel rejection
The tested alternative rejects only candidates beyond:
q > d2*d2*(1 + 1e-5) + 1e-5
Potential winners keep the original distance and ordered comparisons.
Population	Original sqrt calls	Guarded sqrt calls	Logical calls avoided
Random	4,500,000	2,441,853	45.74%
Adversarial	8,100,000	4,537,433	43.98%


There were zero modeled selected-ID/color differences over all 1.4 million points. The margin is empirical. Added squared arithmetic, branching and SIMD divergence may outweigh the saved square roots.
13.4 Reuse derivative footprints only with an error budget
The real chain rule gives:
\[
dFdx(p/s+c)=dFdx(p)/s
\]
for positive constant s, and similarly for y. The source's four noise scales could share a base footprint, reducing four dFdx, four dFdy and eight lengths to two derivatives and two lengths plus scaling.

Finite arithmetic differs because lane-wise division/translation happens before differencing in the original expression.

Each scale was screened with 250,000 synthetic quads, coordinates within ±20 km, and steps approximately 1e-4–316 m:
Scale / offset	Maximum modeled filtered-noise difference	Threshold branch flips
37 / 0	4.98891e-5	2
160 / 17	1.12057e-5	0
9 / 5	1.75923e-4	0
60 / 3	2.68966e-5	0


These are finite-difference models, not actual GPU fragment quads. Keep derivatives in valid control flow and qualify moving grass/filter transitions on the target backend.
13.5 Finite anti-tiling hash palette
The default anti-tiling path uses:
i = floor(vnoise(uv*1.2)*8)
hash22(vec2(i,17))
hash22(vec2(i+1,17))
The bounded input set suggests a tiny palette or literal specialization:
- One million coordinates within ±20 km, tile size 6 m: observed indices 0–7.
- Same CPU float32 hash used dynamically and for the palette: zero differences.
- Potential saving: two hash calls. Both textureGrad calls remain.
- Retain entries for rounded endpoint indices 8/9 and a dynamic fallback.
CPU double-generated constants are unsafe as an assumed exact substitute: salt 17/index 8 differed from float32 by .00352509; salt 71/index 8 differed by .00474655.

The supplied dispatch sketch calls the original hash with literal arguments. Target constant folding, stage consistency, branch cost and actual GPU equality remain open.
13.6 Pilot-anchor and stable-material proposals
The near-pilot grass anchor uses three value-noise expressions at uniform pilot coordinates. A station-update scalar or proven shared GPU result might remove repeated fragment work. Update all material copies and invalidate on station/world/material changes. A CPU double fract hash is not automatically equivalent to GPU float/FMA.

A broader terrain cache could retain slowly changing material channels while leaving footprint filtering, near detail, weather and lighting live. Establish locality and invalidation before adding clipmaps. These are proposals with no new timing result.
14. Solar lookup and rejected relief bundle
14.1 Warped solar-halo lookup
The broad halo uses:
\[
H(\mu)=e^{-18\arccos\mu}.
\]
Use:
\[
t=\sqrt{(1-\mu)/2}=\sin(\theta/2),\qquad
L(t)=e^{-36\arcsin t}.
\]
A 512×1 R16F texture stores L(i/511), uses 1,024 bytes, and concentrates useful sampling resolution near the sun. Map the transformed coordinate to texel centers with u=(511*t+0.5)/512. Use linear data, clamped sampling, no mips and a readiness fallback.

The CPU screen used 820,197 unique float32 dot values, including 167,773 exhaustive representable values near one:
Texels	Maximum normalized halo error, ideal interpolation
64	.0310601
128	.00861973
256	.00223869
512	.0006784201
1024	.000305057
2048	.000213325


For 512 texels, the existing .35 multiplier reduces that normalized difference to .000237447. Sun radiance and exposure still affect final output. An eight-bit interpolation sensitivity model gave .000810802; ten-bit gave .000709653. A uniform-dot 512-entry comparison had a much worse maximum error, about .35095.

Integration trap: the source shares acos(mu) with a legacy analytic disc edge. Replacing the halo alone does not eliminate that acos; it removes an exponential while adding a square root and texture lookup. Additional support restructuring would need its own proof. Exact disc, limb darkening, refraction, occlusion and photometry remain separate.

This is lower priority until generated code and target timing justify it.
14.2 Post-threshold near/mid/far relief bundle
The tested alternative baked already-thresholded near/mid/far densities into RGB for one seed, coverage, clustering and light ray. One sample could then supply all three.

The model used the same 8,192 positions per scenario and size, with a quarter near periodic seams. The default case is seed 1253, coverage .35, cluster 0, ray (0,1). The adverse case is seed 77, coverage .70, cluster .8, ray (-2.8,2.1). These differ from the earlier interval grid's clustering .35. Memory assumes RGBA16F packaging. Errors below concern active-body samples:
Scenario	Size	Base memory per combination	Neighbor-density max / p95	Scalar-relief max / p95
Default	512²	2 MiB	.285 / .120	.366 / .141
Default	1024²	8 MiB	.117 / .0490	.160 / .0632
Default	2048²	32 MiB	.0261 / .0126	.04254 / .01831
Clustered low sun	512²	2 MiB	.260 / .0858	.336 / .0673
Clustered low sun	1024²	8 MiB	.118 / .0346	.144 / .0264
Clustered low sun	2048²	32 MiB	.0411 / .0116	.04963 / .008185


Filtering after thresholding loses subtexel structure, and the shoulder term can amplify density differences. This is separate evidence from the corrected old black-texture diagnosis.

A stale-cache test at 2048² changed only the light ray's x component:
- +.01: default relief max/p95 .04315/.01938.
- +.05: .08776/.02853.
These are ray-coordinate changes, not measured sun angles or elapsed time. Seed, coverage, clustering, relevant shape and dominant-light direction require invalidation. Uniform periodic drift can change lookup coordinates without a rebake when other inputs stay fixed.

Two 32 MiB replacement buffers plus the existing 16 MiB tile already account for 80 MiB before other allocations.

Decision: deprioritize the tested bundle. The corner-hash lattice has a much more favorable incremental error/memory profile. Keep the failed design and its results as evidence.
15. Native-resolution aircraft crop
Status: actual pinned-Godot projection geometry checked; scene rendering, visual seams and performance untested.
Evidence: KIT, crop_projection_prototype/.
15.1 Architecture
Render most of the scene at a lower internal scale. Render a padded crop around the projected aircraft at one physical output pixel per crop pixel, through an off-axis camera sharing the full World3D. Composite before native-resolution UI.

The crop must include terrain, trees and other occluders, not merely aircraft layers. It must include propeller/effects and account for aircraft motion. The existing magnifier uses a different camera/FOV and aircraft-only layers; it is useful infrastructure, not an equivalent implementation.

For main near-plane extents L,R,B,T and top-left-origin crop [x0,x1]×[y0,y1] in W×H output pixels:
\[
l=L+(R-L)x_0/W,\qquad r=L+(R-L)x_1/W,
\]
\[
t=T-(T-B)y_0/H,\qquad b=T-(T-B)y_1/H.
\]
Use the same transform and clipping distances. Derive the projection from the actual main-camera matrix or validated project_position mapping, accounting for aspect mode, offsets, camera attributes, jitter, drawable pixels and synchronization.
15.2 Actual camera-method results
The prototype tested 96 configurations: eight crop rectangles, FOV 40/70/100°, both aspect modes and identity/transformed cameras. The main viewport was 1920×1080, near .5 and far 500.
Check	Population	Result
Projection correspondence	3,168 comparisons	Maximum .0086895 px, below .01 px screen
Verified inverse-projection rays	1,056 comparisons	Maximum vector difference 2.884674e-6
Near/far and crop-edge clipping	1,152 checks	Passed; exact-boundary classifications excluded
Main/crop camera-space depth	3,168 comparisons	Maximum difference 0
Negated-offset controls	72 configurations	All rejected; maximum displacement 1807.106 px


Expected correspondence:
crop.unproject_position(world)
≈ main.unproject_position(world) - crop_origin
15.3 Pinned Camera3D helper limitation
The off-axis crop's project_ray_normal() disagreed with the corresponding main-camera ray in 792/1,056 samples, with maximum vector difference about 1.29545. Source inspection found the helper constructs a centered ray from viewport half-extents without the off-axis center.

Use:
main_camera.project_ray_normal(crop_origin + crop_local_pixel)
with the corresponding main-camera origin, or the separately verified inverse-projection reconstruction. Do not assume the crop camera's convenience ray helper matches its rendered off-axis projection.

The report also records a diagnostic off-axis inversion failure in project_position(). The successful construction used the main camera's mapping. Recheck helper behavior when changing engine versions.
15.4 Cost model and qualification
A simple shaded-area model is:
\[
A_{relative}=s^2+p,
\]
where s is background linear scale and p is crop area divided by full output area. For s=2/3 and p=.10, this is .5444.

That model omits duplicate culling, submissions, shadow/environment passes, postprocessing and compositing. It is not a 45.6% GPU-time prediction.

Qualify:
- Foreground occlusion, fast flight, propeller, smoke, lights and multiple aircraft.
- Crop padding, quantized movement, hysteresis and fallback when the crop is large.
- Fog, exposure, sky, sun/moon, shadow maps, depth/screen readers, LOD and antialiasing.
- Borders during motion, camera cuts, resize/fullscreen and replay.
- Both CPU and GPU complete-frame cost.
Equal camera-space depth does not prove equal depth-buffer or postprocessing behavior.
16. Native Metal rate maps and engine boundaries
16.1 Rasterization-rate maps
Apple's MTLRasterizationRateMap can separate logical viewport coordinates from a smaller physical render target. An aircraft region could retain higher sampling while other parts use lower rates.

This is rasterization rate, not display refresh-rate control. Apple maps have separate horizontal column and vertical row rates rather than an arbitrary 2D mask. A high-detail rectangle therefore also affects its full rows/columns.

Query device support, actual supported rates and physical target size. Implement coordinate reconstruction/unwarping and account for screen/depth readers, transparency, MSAA, reconstruction and temporal history.
16.2 What the pinned engine source actually exposes
At engine cafc17a:
- Normal Metal creation with TEXTURE_USAGE_VRS_ATTACHMENT_BIT errors.
- texture_create_from_extension recognizes a native Objective-C MTLRasterizationRateMap.
- The Metal framebuffer can retain that map.
- metal3_objects.cpp assigns it to the render-pass descriptor.
- An XR path exposes a relevant map format and external import.
- The ordinary desktop Viewport.VRS_TEXTURE path does not automatically supply this native object to built-in Mobile scene rendering.
This is a real import seam, not a completed desktop feature. A native extension importing a map into its own RD framebuffer still does not prove access to the built-in scene pass. An engine patch may be required; the investigation did not prove it inevitable.

Suggested sequence: native simple-scene import and reconstruction, then built-in scene integration, then full visual consumers, then complete-frame timing/energy. No native rate-map prototype or benchmark was completed in the recovered work.
16.3 Metal 4 and other engine projects
The pinned driver factory returns MTL3::RenderingDeviceDriverMetal. Broader documentation or a vendor demonstration does not establish Metal 4 dispatch in that exact template. The referenced refactor PR 114484 described actual Metal 4 dispatch as future work at the time of the audit.

Tile shaders, asynchronous scheduling, memoryless main buffers, a different presentation loop and an engine fork require a captured limitation, a reproducible build and a fallback.

The pinned main depth/MSAA allocation had a transient-allocation TODO. That is not measured wasted DRAM traffic. Memoryless conversion requires proving no later sample/copy dependency.

Eligible textures already use private storage. Recommending private storage generically would repeat existing behavior. Investigate specific usage flags, upload transitions and read-mostly texture optimization only where a capture supports the case.
17. Other shader, cache, and rendering work
17.1 Half-resolution cloud subpass
Godot exposes use_half_res_pass, AT_HALF_RES_PASS and HALF_RES_COLOR. An experiment could evaluate expensive cloud color at half width/height while preserving full-resolution celestial edges, horizon and aircraft.

Keep cubemap/IBL behavior and cloud occlusion consistent. A half-resolution subpass has one quarter as many pixels, but it may still execute where the sky is occluded by terrain. It also needs reconstruction and another pass. Quarter-resolution is a separate visual decision.

This is a quality/performance candidate already identified in the original audit, not a newly completed result.
17.2 Small compile-time shader variants
Consider a small number of prewarmed variants for simple/layered sky, optional ground detail, or screen/depth consumers. Use shared includes and compare the same visible features.

Apple function constants and Godot source/preprocessor specialization are related mechanisms but not identical APIs. Confirm what the actual engine path exposes. Uniform branches may already compile well.

Avoid variant explosion, per-frame Shader/ShaderMaterial creation and new first-use hitches. Inspect register demand and emitted work.
17.3 Screen-footprint filtering
Ground already uses derivatives, fades and guards. Extend these only where work is still performed below useful pixel scale.

Cloud-frequency suppression must preserve coverage/normalization and avoid abrupt bands or shimmer. Compute required derivatives before divergent control flow. This is a filtering/quality change and is distinct from the interval method, which preserves ambiguous density calculations.
17.4 Screen and depth dependencies
Water, glare and afterimage materials can require screen-color copies, depth resolves or mip chains. A hidden material may leave renderer-wide dependency flags active after instantiation.

Measure a variant that never instantiates the relevant consumer. A scene/collision visibility approximation for glare must account for moving blockers, horizon and visual-only geometry. Water refraction and depth tint have broader requirements.

The existing geometric shoreline change removed a discard from the large ground material; its historical D1 diagnostic was about 2.3 ms. Preserve that improvement while rechecking geometry failure behavior.
17.5 Layered-cloud front-to-back bounds
The real premultiplied recurrence is:
\[
C\leftarrow C+T\alpha C_{layer},\qquad
T\leftarrow T(1-\alpha),\qquad
C_{final}=C+TC_{base}.
\]
It exposes a bound on omitted far-layer radiance. Floating-point reordering changes results. Density also drives solar occlusion through exp(-8*density), whose magnitude sensitivity to density is at most 8 before solar intensity and display processing.

An arbitrary alpha cutoff near a bright sun is not sufficient. Bound omitted HDR/cloud/base contribution and solar effects explicitly. A less aggressive trial retains every density but skips only negligible far-layer relief.

The default classic sky has one deck; the kit described two decks in broken/overcast and three in storm presets. The opportunity is weather-specific. No implementation or timing was established.
17.6 Cache ownership and transitions
Key each cache by the function it actually stores. Including irrelevant inputs would cause unnecessary rebakes.
Cached quantity	Inputs that can require a rebuild	Inputs normally evaluated live or through lookup coordinates
Corner-hash lattice	Seed, octave/period layout, hash algorithm, format/resolution and relevant generation	Coverage, clustering threshold, light color/ray and periodic drift
Current raw-noise R/G tile	Seed, noise definition/frequency/layout, format/resolution and relevant generation	Coverage, cluster threshold, light ray and drift
Post-threshold light-conditioned relief bundle	Seed, coverage, clustering, relevant shape/frequency, sample ray, format/resolution and generation	Camera and periodic drift while all cached inputs remain fixed; final lighting terms not stored in the map


Distinguish semantic rebuilds from coordinate updates and stale-job cancellation. Rewind, weather change, dominant sun/moon switch, layer removal and failed completion need explicit behavior; they do not all require regenerating a seed-only lattice. Invalidate when a stored-function input changes, and use generations to prevent an obsolete completion from publishing into a new owner.

The stable ImageTexture path includes per-new-seed GPU readback, CPU conversion and upload. Investigate a GPU copy/blit only if cold/transition measurements show a hitch. Removing the copy without reproducing valid sky sampling could reintroduce the earlier problem.
18. CPU and physics findings from the later audit
Separate source: 3df2791752fe2c1faad132fcb11febbb0ae788d1.
Source report: CPU.
Important scope: the following are the saved audit's reported reference-kernel/source results. They were not rerun while preparing this handoff, and they are not M1 measurements.
18.1 Confirmed passivity problem in ground-vehicle contact
The later audit reports that the tire relaxation force can add mechanical energy, with a corresponding sign issue in the brake row.

For scalar contact slip s, force f, free acceleration a_free and positive mobility W:
\[
\dot s=a_{free}+Wf.
\]
Requesting \(\dot s=-s/\tau\) yields:
\[
f=\frac{-s/\tau-a_{free}}{W}.
\]
For s>0 and a_free<-s/tau, this force is positive, so f*s>0. A magnitude cap alone does not enforce dissipation.

The production scalar-solver counterexample used W=1, s=1 m/s, a_free=-2 m/s², tau=1 s and a 10 N cap, producing f=+1 N and +1 W. The brake row had an analogous +1 W witness. The identity-matrix fixture is a unit counterexample; stock-model evidence establishes application relevance.
Stock Bisonte energy witness
The report initializes the stock ground vehicle on flat static ground, retains initialized attitude/suspension, sets forward speed 5 m/s and each relative wheel spin to 30 rad/s, with radius .1 m and full throttle. Slip is +2 m/s.

It reports approximately +10.96036 N longitudinal force per tire. This solve exited after six sweeps, so the energy-injection witness did not depend on the separately documented 128-sweep convergence cap:
Energy term	Reported power
Motor mechanical input	+468.000000000 W
Rolling resistance	-5.683934337 W
Tire contact	+87.682882561 W
Mechanical-energy rate	+549.998948224 W


A central finite-difference directional derivative of the production energy function agreed within 6.3e-8 W over epsilon from 1e-4 to 1e-7 s. The report found no tangential elastic-energy state that could explain this positive contact work.

The artificial contact term is about 18.7% of motor input at this witness; it is not a lap-average ratio.
Ordinary drive/brake sequence
Starting from the production initializer:
- 0–1.50 s: full throttle.
- 1.50–1.75 s: full brake.
- 1.75–2.75 s: full throttle.
- 2.75–3.50 s: full brake.
- Steering zero, reverse false, throttle/brake never overlap.
All 840 steps of the 3.5-second, 240 Hz run were accepted. At throttle reapplication, positive tire-contact power reached 168.812180765 W. The refinement table and work-integral estimates below cover the first 2.25 seconds, using the same control boundaries; they are not full 3.5-second integrals.
Outer rate	Peak positive tire power	Positive tick samples
240 Hz	168.812180765 W	25
480 Hz	168.803890401 W	48
960 Hz	168.800126563 W	94


The peak persists under refinement. The report distinguishes outer rate from the solver's own substeps.

Left-endpoint positive-work estimates were 3.686816, 3.500552 and 3.409141 J. Piecewise-linear estimates excluding intervals across control changes were 3.329558, 3.322076 and 3.319965 J. These are sampled quadrature estimates, not exact work integrals.

No positive brake work occurred in that particular ordinary-driving sequence. The brake issue was separately demonstrated in scalar/valid-state checks; a sampled simultaneous-throttle/brake state reached +108 W. Do not portray that brake state as the ordinary trajectory result.
Repair direction
For a static ground surface and the modeled nonelastic tangential contact, a necessary condition is:
\[
\mathbf f\cdot\mathbf s\le0,
\qquad
\|\mathbf f\|\le\mu N.
\]
The existing mobility-metric projection could include that half-space. This is a necessary constraint, not a complete calibrated tire law. Do not clamp longitudinal and lateral signs independently: total contact work is the relevant dot product.

For nonzero brake spin, torque bounds must oppose spin. At zero spin, allow both signs for static holding. Near-zero treatment requires an integration-consistent design, not an arbitrary epsilon.

Check both:
- app/physics/ground_vehicle/vehicle_dynamics.gd
- research/rc-monster-truck/native/src/ground_vehicle_kernel.hpp
The native source was inspected, not executed by that audit. No validated tire-law patch was supplied. Required regressions include scalar energy, stock energy balance, drive/brake/reversal, zero-slip hold, combined slip, refinement and reference/native parity.
18.2 Reuse the downwash air-data calculation
At the later revision, flight_session.gd calls _wing_cl(s,aux) and then air_data(s,sim.time()).V. The helper itself calls air_data with the same committed state/time.

A one-callback candidate is:
var lag_air: Dictionary = air_data(s, sim.time())
var cl_now := Aero.wing_wake_velocity(
    s, lag_air, _deflections(aux), aircraft.model, _ground_up(s))
var speed: float = lag_air.V
The remaining lag equation stays unchanged. The historical helper name _wing_cl refers here to a dimensional wing lift-velocity proxy, not a dimensionless lift coefficient.

Reported ten alternating batches, 128 calls each after warmup:
Weather	Wind queries	Median pre-step time
Legacy steady	2 → 1	77.33594 → 69.67578 microseconds
Spatial, eight modes	20 → 10	577.63672 → 331.13281 microseconds


These are approximately 9.9% and 42.7% reductions in this callback on the shared Intel/debug host. They are not full-tick, FPS or Apple Silicon improvements.

The saved report records:
- 192 varied-state pre-step outputs matching byte-for-byte.
- 24 accepted integration steps per weather mode matching state, auxiliary state, continuous state and modes.
- Four refusal/failure cases matching nonfinite output, fault and rollback.
- A separate reconstruction retaining spatial benefit: 605.01172 → 350.93359 microseconds, nine of ten pairs favoring reuse.
- Reconstructed legacy medians 80.65625 → 75.26172 microseconds, seven of ten pairs favoring reuse.
Do not pool original and reconstruction timings.

The optimization assumes pure deterministic environment queries. Preserve possible _wing_cl override/dispatch behavior; the prototype bypassed it through a direct helper call. Verify the production contract rather than silently changing extension behavior.
18.3 Prepare invariant station geometry only with lifetime guarantees
wind_aircraft_flow.gd:_sample rebuilds and validates geometry from the model on each call. Prepared station arms could avoid dictionary traversal and allocations.

The unguarded prototype matched 402 sampled comparisons, but after mutating station_ys[0] to NaN the baseline rejected the model while the cached path still succeeded. Dictionary identity did not imply unchanged geometry.

An eight-batch microbenchmark gave about 247.53 → 225.00 microseconds per stage_air call, excluding the required cache guard and with shared-host noise. This motivates a design, not a deployable speedup.

Prepare geometry at a validated model-change boundary; establish immutability or reliable generation/invalidation. Never reuse state-dependent flow/Air receipts across integration stages.
18.4 Checked suspicions that were not promoted to new bugs
The same report records:
- Rotor/body power identity: 600 sampled X-Cell states, maximum residual 9.1e-13 W.
- Rotor-inflow root scan: 27,150 samples, maximum residual approximately 1e-13.
- P-51 low-fuel runway/airborne runouts completed without the suspected fault.
- Selected fuel-exhaustion and rotor-stop checkpoint/event replay matched byte-for-byte.
- Stopped electric-propeller reverse-breakaway refusal was already documented and tested.
- The 128-sweep truck limit and associated small numerical yaw were known limitations; one trajectory did not support inflating them into a new severe finding.
These bounded checks do not constitute complete rotorcraft or vehicle calibration.
19. Tools, libraries, compiler work, and packaging
19.1 Mathematical tools
Tool	Practical role	Qualification
FPCore / FPBench	Record input domains, precision and rounding intent	A representation, not a target-performance result
Herbie	Discover alternate floating-point formulations	Check domain, accuracy and target cost of suggestions
Sollya fpminimax	Search representable-coefficient approximations	Follow with a certified error analysis; fitting alone is insufficient
Gappa	Verify bounds for specified arithmetic	Its model must match the emitted evaluation
Exact rational Python / compiled C harness	Reproduce the supplied polynomial construction and host screens	This is the method actually executed in MATH


Herbie, Sollya and Gappa were researched, not run in the recovered mathematical experiments. The provided polynomial is Chebyshev truncation, not a Sollya minimax output.
19.2 Native Apple/Godot diagnosis
Tool	Question	Boundary
Existing frame streams, debug bridge, script profiler, Perfetto export	Which route/tick/observer coincides with a hitch?	Reuse bounded collection and source/replay identity
Xcode GPU frame capture and Metal counters	Which draw, shader, resource or dependency is expensive?	Diagnostic capture; use clean runs for acceptance
Instruments Game Performance / Metal System Trace	CPU wait, GPU work, submission or presentation?	Discover installed templates and available signals
Time Profiler / macOS sample	Which stacks execute or wait?	Aggregate sampling does not measure every 240 Hz call
Allocations, VM and Metal resource views	Memory growth and resource lifetime?	Avoid summing overlapping accounting scopes
Metal HUD	Quick native-render diagnosis	Some historical logged fields were redacted; not final instrumentation
gpucapture / gpudebug	Reproducible command-line capture/inspection	Audit references macOS 27 tools; verify installation and permissions
Tracy / engine tracing	Internal phases missing from external sampling	Source build and matched profiler versions required


Hardware limits in the researched documentation: GPU heatmaps/shader cost graphs were documented for M3 and later; Processor Trace recording for M4 and later with suitable tools/OS. The Power Profiler page covered iPhone/iPad rather than an M1 Mac. Use available Mac thermal/power tooling.

Do not make unavailable newer-chip features prerequisites for an M1 experiment.
19.3 Precision and compiler behavior
The pinned project research records that the Metal driver already uses MathModeFast. It also records that SPIRV-Cross MSL ignores RelaxedPrecision, so custom Godot mediump/lowp annotations do not automatically become native half. Engine-internal FP16 variants are a separate path.

Potential half-precision quantities need range and error arguments. World coordinates, fract hashes, decision thresholds, derivatives and sensitive HDR/night terms are poor candidates for an unqualified conversion.

SPIR-V Fma spelling does not itself guarantee the conditional proof's exact rounding/operation model. Inspect the actual backend.

For native simulation work, -fno-fast-math alone can leave contraction enabled. Where contraction is prohibited, retain and inspect -ffp-contract=off, compiler flags and pragmas. Rendering fast-math policy and simulation arithmetic policy are separate.
19.4 Libraries and asset tools
Tool/library	Useful when	Main caution
Godot VRAM compression and mipmaps	Texture residency/bandwidth is attributed	ETC2/ASTC import already existed; inspect actual resident formats
Arm astcenc	Offline ASTC quality/bitrate experiments	Procedural data requires separate numerical gates
KTX-Software / Basis Universal	Preparation, validation and transcoding	Pin encoder and host; outputs may differ across architectures
meshoptimizer / gltfpack	Vertex/loading/LOD cost is measured	Preserve propeller, hinge, aircraft node/material contracts
Accelerate, vDSP, vForce	A sufficiently large native batch consumer exists	Double precision does not ensure reference-equivalent reduction/transcendental behavior
metal-cpp	Native Metal integration is justified	It exposes APIs; it does not optimize the existing Godot renderer by itself
Tracy	Instrumented CPU/GPU/lock/allocation diagnosis is needed	Use the existing Godot integration and bounded capture


Static import compression does not automatically compress runtime ImageTexture data. Unified memory still has residency and bandwidth limits.

NEON/vectorization, PGO and ThinLTO are conditional native experiments. PGO needs representative training, held-out workloads and a distinct optimized binary; macOS LTO/build caveats must be checked for the pinned toolchain. Small GDExtension calls or reordered reductions can lose performance or equivalence.

QoS can express urgency; forcing a named performance core is not a portable design.
19.5 Export and first-use behavior
Godot's shader baker stores intermediate shader representation. It complements final driver-specific pipeline creation.

The original audit found the shared export wrapper using headless exports; the researched Godot documentation says headless disables the baker and Metal baking requires macOS. Recheck the current wrapper before assuming a preset checkbox enables baking.

Use a separately identified native Mac export stage. Inspect the actual package and measure cold launch, Home-to-Fly and first use of dynamically introduced meshes/materials/particles/UI.

Qualify the real exported app's fullscreen and Game Mode state. The researched requirements included Apple Silicon, macOS 14+ and macOS fullscreen. Game Mode may improve scheduling consistency; it does not eliminate shader pixel work. Preserve Intel/Compatibility and release identity.
19.6 Presentation and reconstruction
Keep Spatial reconstruction as a separately measured Mobile path. The audited Temporal policy used Forward+ and requires its own renderer cost, history, motion-vector and reset evaluation.

Compare propellers, gear, control surfaces, smoke, foliage, camera cuts, pause/resume, resize and teleport. Native UI is preserved.

Once sustained headroom exists, compare paced 60 Hz and uncapped runs, and evaluate a two-image swapchain against the default three-image setting for latency and deadline stability. Dynamic resolution should follow qualified fixed presets, with readability floor and hysteresis.

Displayed frame interpolation does not increase simulation rate or establish lower input latency.
20. Implementation work packages
Rebase each candidate onto a frozen current revision and retain the old evidence as historical. Do not apply a patch blindly because its recorded applicability check passed at 93ffbb.
Order	Work package	First deliverable	Evidence required to retain it
0	Recheck historical release/evidence defects	Current-source disposition for UID, effective render, diagnostic eligibility, identity and readiness	Correct receipts and current CI; known fallbacks cannot pass as another configuration
0	Recheck later contact passivity finding	Reproduced or closed scalar/stock/drive witnesses on current source	Energy contract, zero-slip behavior and reference/native agreement for any fix
1	Zero-contribution sky changes	Rebased small patch with full-sky check	Real output and matched clean timing; cirrus/derivatives preserved
2	Interval density termination	Separate direct-analytic and C5b candidates with conservative target bounds	Raw numeric agreement at boundaries, lifecycle and branch/workload benefit
3	High-octave lattice atlas	Stable published 1024² RG16F atlas with exact key/fallback	Actual sampler/image behavior, bake/memory costs and complete-frame benefit
4	Transmission polynomial	Degree-five and degree-six target variants	Emitted arithmetic, error budget and native timing versus exp
5	Integer and smaller algebra	Factored hash, shared powers, duplicate pilot-distance reuse as isolated changes	Generated-code difference and measured useful gain; no unqualified FP equivalence
6	Same-callback Air reuse	Production-safe callback/dispatch change	Refusal/replay parity and target release callback/tick measurements
7	Prepared station geometry	Explicit immutable/admitted-model generation	Mutation/refusal cases preserved and net gain including invalidation checks
8	Larger renderer trial	Native-pixel aircraft crop with full occluders	Seamless motion, exposure/depth/effects and total CPU/GPU improvement
9	Engine/native investigation	Minimal rate-map or captured pass-dependency prototype	Supported path, bounded maintenance cost, fallback and product workload evidence
Parallel release work	Native Mac baking/prewarm and package checks	Identified exported app	Cold/warm loading, pacing, recovery and supported platform behavior


Work-package rules
- One question per candidate. Keep analytic cache-off, stock C2+C5b and modified stock clearly identified.
- Separate a code implementation improvement from a deliberate quality reduction.
- Retain failed candidates, exact counterexamples and measured neutral results.
- Do not add independent percentage savings. Shared bottlenecks and interactions change the combined result.
- Recompute a combined error budget after combining approximations.
- Move to an engine fork only when a captured limitation and a minimal native proof justify it.
- Review model/lifetime changes with the developer responsible for simulation and replay, even when the optimization appears to be a cache.
21. Benchmark and correctness acceptance protocol
21.1 Freeze the candidate and effective workload
Every receipt should include:
identity:
  source_commit: full SHA
  dirty_patch_sha256: exact candidate patch or clean marker
  engine_commit: full SHA
  engine_binary_sha256: hash
  template_and_export_package_sha256: hashes
  compiler_sdk_flags: required for native changes
rendering:
  method_and_driver: actual values
  requested_reconstruction: requested mode
  effective_reconstruction: actual provider/mode/fallback reason
  output_drawable_internal_pixels: all dimensions
  msaa_vsync_frame_cap: explicit values
  cloud_cache_requested_ready_seed_generation: explicit values
host:
  mac_model_gpu_cores_ram_os: recorded
  display_refresh: recorded
  power_source_power_mode: recorded
  thermal_swap_competing_work: recorded
workload:
  aircraft_field_weather_seed: recorded
  camera_input_tape_route: recorded
  accepted_simulation_time: recorded
measurement:
  diagnostic_or_clean: explicit classification
  warmup_observation_duration: recorded
  missing_signals: explicit unavailable values
A property readback alone does not establish that a scaler or shader feature executed. Use a short appropriate capture for attribution, then clean runs for adoption.
21.2 Correctness before speed
For cloud candidates, compare raw float outputs around both smoothstep edges, periodic seams, negative/prewrapped coordinates, seed changes and cache unavailable/wrong-seed paths. Exercise dense/sparse coverage, clustering, high/low sun, moon and relevant layers.

For polynomial candidates, retain domain guards and compare extrema, endpoint neighbors and actual target operation order. A CPU FMA proof cannot silently transfer to different emitted arithmetic.

For terrain candidates, include the saved parcel tie, additional procedural bisectors, derivative transition neighborhoods and moving views. An 8-bit screenshot is insufficient to prove hash-bit equality.

For lifecycle changes, include cold bake, failure, repeated seed changes, scene teardown, rewind, Home/Fly/Workshop transitions and renderer fallback.

For behavior-preserving CPU optimizations, use state/auxiliary/mode/event/refusal/rollback parity and the relevant energy tests. A smaller callback time does not justify changed transaction semantics. A tire-law correctness fix intentionally changes the faulty trajectories: validate the corrected energy/holding contract, deterministic replay of the corrected model, model/version compatibility policy, and reference/native agreement rather than requiring byte parity with the defective law.
21.3 Visual qualification
Primary output is native 1920×1080. Keep exact output, exposure and camera identity for comparisons. Include:
- Distant aircraft, propeller, gear, control surfaces and moving thin features.
- Cloud contours, relief, shadow consistency, horizon and periodic seams.
- Ground/grass motion, lakes, trees and foreground occlusion.
- Sunrise, night, bright sun/moon and weather transitions.
- Camera motion/cuts, resize/fullscreen, pause/resume and replay.
The existing 2/255 still-image result belongs to its recorded scenes and candidate. Do not turn it into a universal acceptance tolerance without a defined current test contract. Small scalar error can cross output quantization boundaries.
21.4 Performance protocol
Use short diagnostics to identify shader/pass, ALU/complex-function, memory, register/occupancy, submission and presentation costs. Then disable heavy profiling for paired timings.

The retained project protocol recommends five alternating short pairs, then three 30-minute runs per role for finalists. Preserve source-bound receipts and observation-overhead checks.

Record:
- p50/p95/p99/p99.9 frame intervals and slow-frame counts.
- GPU pass attribution separately from visible presentation.
- CPU execution/waits, full tick cost and simulation-versus-wall progress.
- Cold/transition spikes and first use.
- Resident/peak memory, resource lifetime, swap and thermal/power trends.
- Final-five-minute behavior in sustained runs.
- State/input/replay evidence appropriate to the candidate.
Process/viewport metrics are not automatically on-glass timestamps; step_usec excludes some publication/observer work. Instrumentation scope must be explicit.

A candidate passes only when correctness/readability survives and a complete-workload benefit exceeds variation. A reduced operation count is a reason to test, not the acceptance result.
22. Reproduction and artifact inventory
22.1 Supporting artifacts
Provide the two ZIP archives with this Markdown when the developer needs to reproduce the experiments. This document contains the findings and decisions; the archives contain the full scripts, sketches, results and receipts.
Artifact	Identity / purpose
OpenRC_Apple_Silicon_Audit_2026-11-05.pdf	Original 16-page audit at fc018b; historical findings and primary-source ledger
OpenRC_Apple_Silicon_Experimental_Kit_2026-11-05.zip	Earlier experiments; 66 archive entries
OpenRC_Mathematical_Optimization_Lab_2026-11-05.zip	Mathematical experiments; 69 archive entries
OpenRCsimulator-math-audit-3df2791.txt	Separate later CPU/physics report; its own harness/evidence described in that report


Archive SHA-256 values:
Experimental kit:
3c80742fec67e43720ebe43716385688506186d5f696432594c268ba30b8bc73

Mathematical lab:
7ebb1ea430f1c601596cd94f7a3ce8827a44af30dbe2d6edd508d68234fa516d
The mathematical archive has a MANIFEST.json covering 68 payload files; all matched when preparing this handoff.

The separate CPU audit's full source harness is not part of these two shader archives. Its report names the probes, source manifest and candidate patch; obtain its matching evidence package before reproducing those tests. Do not present the shader ZIPs as containing that CPU harness.
22.2 Earlier kit layout
Directory	Contents
bounds_prototype/	Original interval screens, after-three and after-two/three shaders
cloud_prototype/	Lattice CPU model, result JSON, baker/consumer/canvas shaders
solar_prototype/	Warped LUT screen, 512-entry binary16 data, shader include
relief_cache_prototype/	Post-threshold bundle screen and rejected-result distributions
crop_projection_prototype/	Actual Godot camera geometry, source note and checked receipts
metal_research/	Native rate-map, mip-pyramid and other architecture analysis
verification/	Five shader-wrapper front-end checks and receipts


From the extracted kit directory:
python3 -B run_cpu_screens.py --repo /absolute/path/to/pinned/OpenRCsimulator
python3 -B run_cpu_screens.py --only lattice
python3 -B run_cpu_screens.py --only solar
python3 -B run_cpu_screens.py --only relief-cache
Use Python/NumPy versions recorded in the archive. The launcher handles the frozen bounds script's historical repository path. The repository and engine executable are not bundled.

Markers in retained checks include:
- OPENRC_EXPERIMENTAL_SHADER_LANGUAGE_CHECKS_PASSED
- CROP PROJECTION PASSED
22.3 Mathematical lab layout
Directory/file	Contents
interval_noise/	Conditioned full/C5b interval screen, local reference helper and results
exp_polynomial/	Exact-rational construction, host C, Godot/MSL sketches and coefficient bits
integer_noise/	Modular factoring, wrap comparisons and shader wrapper
angular_algebra/	Aureole, air-mass, tangent and shared-power screens
grass_algebra/	Parcel counterexample/filter, derivative and palette experiments
exact_support/	Complete sky candidate and three-change patch
verification/	Seven resource checks and full receipts
run_cpu_experiments.py	Portable group launcher
MANIFEST.json	Source/evidence identity and payload hashes


From extracted math_lab:
python3 run_cpu_experiments.py --repo /path/to/OpenRCsimulator

python3 run_cpu_experiments.py --only exp angular integer
python3 run_cpu_experiments.py --repo /path/to/OpenRCsimulator --only grass
python3 run_cpu_experiments.py --only interval
Requirements: Python 3, NumPy (recorded 2.3.5), and a C11 compiler/libm available as cc for the polynomial screen. These scripts were verified on Linux; their compiler/engine command lines are not claimed as already qualified on macOS. The grass run checks the recorded repository revision.

The launcher regenerates JSON and logs inside the extracted lab. Copy the archive first if preserving the original retained receipts is important.

Pinned Linux shader-language commands:
/path/to/Godot_v4.8-beta2_linux.x86_64 --headless --editor \
  --path /path/to/math_lab/verification/project --import

/path/to/Godot_v4.8-beta2_linux.x86_64 --headless \
  --path /path/to/math_lab/verification/project \
  --audio-driver Dummy --script res://verify.gd
Non-mutating patch check:
git -C /path/to/OpenRCsimulator apply --check \
  /path/to/math_lab/exact_support/sky_support.patch
Use the project's existing checked-runner in normal development. The retained mathematical run exited zero, reported zero errors/warnings and emitted OPENRC_MATH_SHADER_LANGUAGE_PASSED.

Its seven resources were original full sky, modified full sky, integer-noise wrapper, guarded-parcel wrapper, palette wrapper, angular wrapper and polynomial wrapper. The dummy renderer requests compiled uniform lists; this does not generate or execute Metal code. The later interval experiment is outside those seven resources.
23. Source map and references
23.1 Archived evidence
The links below identify the saved evidence. A recipient without access should receive the named artifacts directly. This handoff does not grant access to them.
- AUDIT — Original Apple Silicon audit.
- KIT — First experimental kit.
- MATH — Mathematical optimization lab.
- CPU — Separate later CPU/physics audit.
23.2 Main shader and evidence source map
All following OpenRC links are pinned to the indicated revision rather than a moving main branch:
Source	Purpose
sky.gdshader at 93ffbb	Sky composition, support patch, aureoles, layered weather
cloud_field.gdshaderinc	Noise/hash, fBm, clustering and density thresholds
cloud_shadow_map.gdshaderinc	Ground cache and C5b detail consumers
cloud_shadow_map.gd	Texture creation, bake, publication and lifetime
cloud_relief.gdshaderinc	Optical-depth and lighting equations
moon_disc.gdshaderinc	Tangent construction and derivative-sensitive lunar disc
ground.gdshader	Parcel selection and duplicate pilot distance
grass_surface.gdshaderinc	Noise footprint, palette and pilot anchor
camera/magnifier.gd	Related existing viewport/camera infrastructure
R4 corrected evidence	Cloud baseline, rejected mask-only test and renderer attribution
Apple Silicon performance plan	Qualification priorities and project protocol


Historical audit source at fc018b:
- Benchmark reducer
- Sustained fixture
- Renderer guard
- Shoreline geometry
- Lake publication
- Export wrapper
- Historical sustained comparison
- Failed historical CI job
Separate CPU audit at 3df2791:
- Flight session pre-step
- Aircraft wind flow
- Ground-vehicle dynamics
- Native ground-vehicle mirror
23.3 Pinned engine source
- Camera3D helpers
- Metal driver factory
- Metal device driver and native texture import
- Metal3 render-pass objects
- Mobile renderer
- Mobile shader configuration
- Render scene buffers
- XR external interface
- Metal refactoring PR 114484
23.4 Primary mathematical and shader references
These sources explain methods and API/compiler contracts. They do not supply the OpenRC experiment numbers.
- NIST DLMF approximation techniques
- NIST Chebyshev representations
- Sollya fpminimax
- Gappa
- Herbie tutorial
- FPBench FPCore
- Khronos GLSL operators and integer semantics
- Khronos SPIR-V GLSL extended instructions, including Fma
- GLSL ES specification, derivatives/control flow
- GPU Gems: improved noise implementation
- GPU Gems: hardware filtering techniques
- Bruneton atmospheric precomputation reference
23.5 Apple primary references
Availability statements below belong to the retrieved research. Verify them against the chosen current device, OS, Xcode and SDK when implementing.
- Optimize Metal performance for Apple Silicon Macs
- Metal shader performance best practices
- GPU compilation and fast-math discussion
- Texture/LUT precision guidance
- Texture caching and usage guidance
- Metal compiler math mode
- Inspecting shaders
- Optimizing GPU performance
- Metal tools
- WWDC26 command-line GPU tools reference
- Metal HUD metric meanings
- Creating rasterization-rate maps
- Rasterization-rate rendering
- Rate-map layer descriptor
- Rate-map reconstruction discussion
- 32-bit float filtering support
- Metal capabilities
- GPU performance heatmaps
- Shader cost graph
- Processor Trace
- Power Profiler availability
- Game Mode
- Accelerate
- metal-cpp
23.6 Godot, compiler and asset references
- Godot 4.8 beta2 release
- Sky shader passes
- Pipeline compilation and shader baker
- Resolution scaling
- Sky process modes
- Image formats and supplied mips
- Texture readback
- Camera3D
- Viewport and World3D
- Shader preprocessor
- Image import/compression
- Godot profiling
- Godot Tracy integration
- Build-system production/LTO options
- Frame pacing
- Clang floating-point semantics and PGO
- LLVM ThinLTO
- Arm astcenc
- meshoptimizer gltfpack
- KTX-Software releases
- Tracy
24. Developer completion checklist
- [ ] Identify the current OpenRC revision and disposition each historical finding.
- [ ] Confirm the engine/template, effective renderer and actual output dimensions.
- [ ] Confirm the working stable ImageTexture baseline and ready/failed/stale behavior.
- [ ] Preserve the C5 diagnosis correction and the separate rejected relief-bundle result.
- [ ] Recheck the later tire/brake energy witnesses on their matching/current source.
- [ ] Choose one candidate and freeze its source, mathematical assumptions and visual contract.
- [ ] Inspect emitted target code where the claimed benefit depends on compiler behavior.
- [ ] Run raw numeric boundary checks before relying on screenshots.
- [ ] Preserve derivative control flow, clustering, periodicity, seed and fallback semantics.
- [ ] Compare moving native-1080p output and complete CPU/GPU workload.
- [ ] Record clean paired measurements separately from diagnostics.
- [ ] Include bake, first-use, memory and sustained thermal/pacing behavior.
- [ ] Verify simulation/replay/refusal contracts for any CPU or native change.
- [ ] Retain neutral and rejected candidates with their evidence.
- [ ] Update the project plan with the exact accepted revision, implementation and measured limits.
Recommended first technical sequence: validate the baseline and evidence machinery; qualify the small sky patch; test bounded cloud evaluation and the lattice atlas independently; compare the bounded transmission polynomial against native exp; then consider larger renderer or engine changes. The strongest general method is to prove that work cannot affect the output before paying to compute it.