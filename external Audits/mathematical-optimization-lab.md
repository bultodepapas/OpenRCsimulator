# OpenRC Simulator — Mathematical Optimization Lab
## Apple Silicon, Metal, procedural rendering, and native simulation

**Source freeze:** [`3df2791752fe2c1faad132fcb11febbb0ae788d1`](https://github.com/bultodepapas/OpenRCsimulator/tree/3df2791752fe2c1faad132fcb11febbb0ae788d1), commit timestamp 2026-11-06 01:23:16 UTC.  
**Purpose:** an engineering addendum to the developer audit, focused on algebraic work elimination, bounded approximation, geometric support, spectral filtering, and same-evaluation reuse.  
**Evidence:** source inspection, primary technical research, and 12 reproducible portable numerical probes.  
**Execution environment:** Linux x86-64, CPython 3.12.14, NumPy 2.3.5, SciPy 1.17.0. No Godot execution, Metal compilation, Apple GPU capture, or target-Mac timing was performed for this lab.  
**Deliverables:** this report and `OpenRC_Mathematical_Optimization_Kit.zip`, containing scripts, retained JSON results, a runner, source manifest, and implementation sketches.

## 1. Engineering decision

The most promising next step is to **remove repeated mathematical work and make the cost of approximation explicit**.

Start with three rendering candidates:

1. **Share the four coarse-noise corner hashes across the three cloud-relief queries when their wrapped lattice cells match.** Keep the original path at cell crossings.
2. **Replace the ordinary solar halo/disc angle calculation with chord geometry.** This removes an inverse trigonometric operation without adding a texture or cache.
3. **Give cloud relief a linear-color error budget and omit queries whose possible contribution fits inside it.** Test a cheap conservative decision rule before a tighter, more expensive one.

In parallel, evaluate **same-stage wing-flow reuse** on the actual production physics path. It can remove whole repeated strip evaluations while preserving their expressions and serial reductions.

These are candidates for implementation and measurement, not measured speedups. A lower source operation count can lose on Apple GPUs if it increases live registers, divergence, or texture latency. The ranking below balances expected scope, numerical control, and implementation complexity.

### 1.1 Ranked experiment register

| ID | Candidate | Evidence obtained here | First implementation decision |
| --- | --- | --- | --- |
| M01 | Same-cell cluster corner reuse | Zero observed difference in selected float32 screens and seam controls; 82.49–99.14% same-cell rate in three clustered cases | Implement three-query fast path with original fallback |
| M02 | Chord-space solar halo and ordinary disc | Global real halo bound; 1,162,773 distinct cosine inputs screened | Implement behind a render experiment switch |
| M03 | Error-budgeted cloud relief | Monotonic endpoint proof; reduced requested query counts within a chosen CPU-model budget | Start with cheap far bound; preserve reference path |
| M04 | Aureole/disc support tests before inverse trig | Exact geometric support in real arithmetic; sampled float32 boundary checks | Small independent candidate; retain safe boundary fallback |
| M05 | Shared ground noise footprint | 500,000 synthetic quads; small rounding differences | Inspect generated shader first, then test shared calculation |
| M06 | Relief-wave common subexpressions and unused sine elimination | 300,000 float32 samples; tiny modeled slope difference | Preserve amplitude-gradient terms at surface edges |
| M07 | Photo-material endpoint fetch elimination | Exact endpoint reasoning; spatial coherence screen | Branch with explicit gradients already available |
| M08 | Shared grass/dirt normal frame | 400,000 synthetic normal cases | Overlap-only candidate with degeneracy coverage |
| M09 | Same-stage wing-flow reuse | Current call-graph duplication verified | Prototype at evaluator boundary; require byte-level oracles |
| M10 | Flap invariant and clean-strip preparation | Current nested-loop dependencies verified | Lazy per-evaluation preparation, original reduction order |
| M11 | Bounded-degree transmission polynomial | Chebyshev tail derivation and float32 coefficient tests | Lower priority until GPU counters implicate exponential cost |
| M12 | Guarded parcel distance rejection | Unguarded version failed; guarded numerical screen passed | Research only until rounding and branch cost are resolved |
| R01 | Footprint-aware noise statistics | A moment approximation improved one statistic but failed a stronger filter test | Do not ship residual-mean substitution |
| R02 | Analytic box filtering of terrain waves | Sinc derivation and synthetic omission bounds | Separate visual-quality research, not a parity refactor |

### 1.2 What changed since the earlier audit

The earlier guide was frozen at `93ffbb101917dff86ecc2632f07e2e45c450a178`. The current snapshot adds missing UID sidecars and makes reconstruction **Auto** the default. Its policy tries supported MetalFX modes while keeping internal height at least 1,000 rows; otherwise it selects Native. The relevant cloud, ground, and aerodynamic formulas inspected for this lab remain the basis of the experiments. See the current [reconstruction implementation][S9].

The repository's [`optimization help.md`][S10] already discusses partial-fBm early exits, hash atlases, an octave dictionary, a solar LUT, crop rendering, relief caches, and rasterization-rate maps. This lab does not count those as new results or rerun their reported campaigns. Its contribution is the additional mathematics, new numerical controls, rejected alternatives, and concrete implementation seams below.

## 2. Evidence and numerical contracts

Use four labels when discussing these results:

- **Proved in real arithmetic:** a mathematical statement under explicit assumptions. Floating-point rounding and compiler math modes are additional questions.
- **Observed in a portable model:** a result from the included scripts and their specified samples. It is not an exhaustive input proof or a simulation of Apple's texture units.
- **Source-derived cost:** a count of expressions or calls that a proposed rewrite can remove. A compiler may already remove some of them.
- **Target-device result:** an actual comparable GPU or CPU measurement. This lab contains none.

Rendering and simulation need different contracts. A render experiment may have an explicit pre-tonemap linear-RGB or normal-angle tolerance. The 240 Hz RK4 simulation, float64 state, accepted-tick transactions, refusal behavior, and replay contracts remain unchanged. Reuse is confined to one evaluation and exactly matching inputs.

A tolerance of 0.001 in linear RGB is **not a promise of invisibility or one display code value**. Exposure, tone mapping, gamma, bloom, and temporal history can change the visible error. Establish the bound at the relevant consumer and inspect the final output. Multiple approximate effects need a combined budget.

For a downstream transform with a known Lipschitz bound \(G\),

\[
\|F(x+\delta)-F(x)\|\leq G\|\delta\|.
\]

One may allocate \(\varepsilon_{linear}\leq\varepsilon_{output}/G\) only after establishing that bound for the actual operating range and pipeline. A guessed display conversion does not qualify an approximation.

## 3. M01 — Share the coarse polynomial underlying cloud relief

**Source:** [cloud field][S1], [C5b detail consumer][S2], [cloud relief][S3].  
**Evidence:** `noise/cloud_lab.py`, `seam_control.py`, `four_point_lab.py`, `octave_sharing.py`, `unique_corners.py` and corresponding JSON.

### 3.1 The repeated work

The relief shader evaluates three displaced cloud densities at

\[
p_j=p+t_jr,\qquad t_j\in\{0.10,0.28,0.62\},
\quad r=\frac{light_{xz}}{\max(light_y,0.28)}.
\]

When clustering is active, each density evaluates coarse value noise at

\[
q_j=\operatorname{mod}(p_j,64)/16.
\]

Inside a given lattice cell, the four corner hashes are fixed. Only the fractional coordinates and their quintic weights vary:

\[
h(t)=6t^5-15t^4+10t^3,
\]

\[
N(u,v)=
\operatorname{mix}\big(
\operatorname{mix}(a,b,h(u)),
\operatorname{mix}(c,d,h(u)),
h(v)\big).
\]

The code uses value noise with a quintic interpolant. It is not Perlin gradient noise. [Perlin's improved-noise paper][P1] is relevant to the interpolant's derivative continuity, not evidence that the algorithms are identical.

### 3.2 Proposed path

Compute the original wrapped coordinates and integer cells for all three queries. If those cells match, calculate their four hashes once. Evaluate each original fractional interpolation, cluster smoothstep, coverage adjustment, and density threshold separately. At any crossing, use the original evaluations.

This changes twelve source-level corner hashes to four **for the clustered coarse-noise portion on the fast path**. It does not remove two thirds of the complete cloud shader. With `cluster_strength = 0`, there is no cluster evaluation to save.

For uniformly distributed coarse-cell phase, the same-cell probability is

\[
P=\prod_{i\in\{x,y\}}
\max\left(0,1-\frac{0.52|r_i|}{16}\right).
\]

This probability is a geometric model. Active cloud points need not have uniform phase.

### 3.3 Observations

With 32,768 float32 coordinates, coverage 0.35, clustering 1, seed 1253, and a 45-degree light azimuth:

| Light direction y | Same cell among active cloud points |
| ---: | ---: |
| 0.28 | 82.49% |
| 0.866 | 97.20% |
| 0.99 | 99.14% |

The selected CPU calculations matched exactly across five seeds. A separate 4,900-coordinate seam control included values adjacent to periodic and coarse-cell boundaries. The guarded path again had zero observed difference. Deliberately sharing without the cell check produced 2,386 errors above \(10^{-5}\), with a maximum cluster error of 1.0 in the shallow-ray case.

A four-query version can also retain the sky-body corners. Its same-cell rates were 79.50%, 96.51%, and 99.05%. It potentially changes sixteen hashes to four, but carries data farther through the shader. Start with the smaller three-query interface.

A more aggressive corner-deduplication model found a mean of 4.367 distinct corners per three-query low-sun sample, versus twelve naive corner evaluations. That is a lower bound on necessary hash evaluations, not a cheap implementation: cross-cell bookkeeping can cost more than it saves.

### 3.4 Important failure boundary

The same strategy does not generalize automatically to C5b's live octaves 3 and 4. Those lattices are much finer. In the diagonal-ray tests at light y = 0.28 and 0.866, neither octave put all three samples in one cell. Even at y = 0.99, the rates were only 33.56% and 2.46%.

Preserve periodic reduction and coordinate precision. Check both ray signs, mixed seeds, cluster strengths, tile-disabled operation, and seed mismatch fallback. The real C5b path reads low octaves from a filtered RG16F tile; the numerical cloud screen substitutes analytic low octaves. Its active-point frequencies are therefore estimates for a source model, not the actual renderer.

## 4. M02 — Remove the solar inverse cosine with chord geometry

**Source:** [sky solar accumulation][S4].  
**Evidence:** `angular/angular_lab.py` → `chord_sun` in `angular/results.json`.

### 4.1 Transformation

The current ordinary path uses

\[
\mu=\operatorname{clamp}(v\cdot s,-1,1),\qquad
\theta=\arccos\mu,
\]

\[
H=e^{-18\theta},\qquad
D=1-\operatorname{smoothstep}(0.9r_s,1.1r_s,\theta).
\]

Define the chord coordinate

\[
c=\sqrt{2-2\mu}=2\sin(\theta/2).
\]

Use \(H_c=e^{-18c}\). For the ordinary disc, transform both angular thresholds through the same chord mapping:

\[
c_i=2\sin(0.9r_s/2),\qquad
c_o=2\sin(1.1r_s/2),
\]

\[
D_c=1-\operatorname{smoothstep}(c_i,c_o,c).
\]

This replaces the shared `acos` with a square root. It requires no LUT, extra texture, temporal state, or approximation of the cloud field. The disc ramp is a slightly different parameterization; it is not algebraically identical.

Precompute the thresholds when the active sun radius changes, using the same rounded angular thresholds as the reference. The application sets the radius from atmospheric sun-diameter data. Do not hard-code the default values.

The optional limb-darkening/squash profile retains its own formula. The radiance-cubemap behavior, light direction selection, cloud occlusion, sun color, and sun-disc control must also be preserved.

### 4.2 A global halo bound

Since \(c\leq\theta\), the chord halo overestimates the real-arithmetic angular halo. For \(0\leq\theta\leq0.5\),

\[
\theta-c\leq\frac{\theta^3}{24},
\qquad c\geq\frac{95}{96}\theta.
\]

Using \(1-e^{-x}\leq x\) for nonnegative \(x\),

\[
0\leq e^{-18c}-e^{-18\theta}
\leq\frac{18}{24}\theta^3
e^{-18(95/96)\theta}.
\]

The right-hand side is maximized at \(\theta=3/[18(95/96)]\), giving 0.00017838854. For \(\theta\geq0.5\), the difference is at most

\[
e^{-36\sin(0.25)}\approx0.00013549951.
\]

Thus the normalized halo has the global real-arithmetic bound

\[
\boxed{|H_c-H|\leq1.7838854\times10^{-4}}.
\]

This does not certify Metal's rounded square root/exponential, and it does not bound the disc approximation.

### 4.3 Numerical result

The probe covers 1,162,773 distinct float32 cosine inputs: every one of the 167,773 representable inputs in [float32(0.99), 1], plus a broader grid over [-1, 1]. At the single tested default radius, approximately 0.0046251 radians:

| Quantity | Maximum observed absolute difference |
| --- | ---: |
| Normalized halo | \(1.7314777\times10^{-4}\) |
| Ordinary disc shape | \(1.2516975\times10^{-6}\) |
| Combined coefficient \(0.35H+4D\) | \(6.0601160\times10^{-5}\) |

The combined error must still be multiplied by

\[
\max|sun_{lin}/\pi\cdot sun_{disc}|.
\]

The existing nonnegative-density occlusion multiplier is at most one, so it cannot amplify that contribution. HDR solar color and later image processing can.

**Promotion test:** compare raw solar contribution and final images across the supported diameter range, subpixel sun motion, horizon approach, limb/squash modes, both renderers, and radiance-cubemap generation. Inspect generated code and complete-frame time. A mathematical replacement can still lose if the original instruction is cheap or the new path raises resource pressure.

## 5. M03 — Let uncertainty determine whether cloud relief needs a sample

**Source:** [relief formula][S3] and both consumers in [sky][S4].  
**Evidence:** `noise/cloud_lab.py`, `bounds_control.py`, `coherence_lab.py`.

### 5.1 Write the actual output as a monotone function

Let \(b\) be cloud body density and \(n,m,f\in[0,1]\) the near, middle, and far samples. Define

\[
B=0.38+0.12\,[4b(1-b)]\,
\max(v\cdot light,0)^{12}.
\]

For bounded body and normalized directions, \(0.38\leq B\leq0.50\). The current relief multiplier is

\[
L(n,m,f)=\operatorname{clamp}\left(
0.62+B e^{-1.6(0.65n+0.45m+0.25f)}
+\operatorname{clamp}(1.5(b-n),-0.12,0.20),
0.50,1.12\right).
\]

For fixed body and direction, this function is nonincreasing in each sample. Increasing near density decreases both transmission and the shoulder term. Increasing either other density decreases transmission. Clamping preserves monotonicity.

Evaluate unknown samples at their endpoints to get \(L_{min}\) and \(L_{max}\). Their midpoint minimizes worst-case scalar error over that interval:

\[
\left|L-\frac{L_{min}+L_{max}}2\right|
\leq\frac{L_{max}-L_{min}}2.
\]

This establishes an output bound without assuming that nearby cloud samples are similar.

### 5.2 Propagate the bound through the correct consumer

For the classic deck, let

\[
k=density\,|relief\_weight|\,\max|cloud_{lin}|.
\]

Then the relief contribution has the pre-tonemap bound

\[
E_{RGB}\leq k\frac{L_{max}-L_{min}}2.
\]

The layered path needs its own multiplier:

\[
k_{layer}=\alpha\,|relief\_weight|\,
\max|cloud_{lin}\,lighting\,tower\_shade\,macro\_tone|.
\]

Do not reuse the classic density multiplier there. Subsequent opacity mixtures can attenuate an existing error; errors introduced by multiple layers must still be accumulated. Retain all original cloud densities for silhouettes, cirrus, solar occlusion, and other consumers.

### 5.3 Two useful decisions

**Skip all three queries.** Set all unknown samples to zero and one. The endpoint constants need no per-pixel exponential: the two transmission values are 1 and \(e^{-2.16}\). If the scaled half-width fits the budget, return the interval midpoint.

**Skip only far.** After near and mid are known, a tight endpoint test bounds far between zero and one. However, it needs the base transmission to decide. If far is then required, a naive implementation computes another exponential.

A lower-cost sufficient condition is

\[
\boxed{E_{far}\leq k\frac{B(1-e^{-0.4})}{2}}.
\]

It uses \(e^{-1.6(0.65n+0.45m)}\leq1\) and the nonexpansive outer clamp. If accepted, approximate transmission by

\[
e^{-1.6(0.65n+0.45m)}\frac{1+e^{-0.4}}2.
\]

If rejected, sample far and execute the original single exponential. Thus the decision itself needs no new per-pixel transcendental operation. It gives up some skips to reduce decision overhead.

### 5.4 Numerical screen

The following uses 32,768 float32 coordinates, coverage 0.35, light y = 0.28, a 45-degree light azimuth, cloud color 0.9, relief directionality 1, and budget 0.001. The screen sets forward scattering to its maximum for the chosen body, rather than constructing a physically matching view/light pair for every row. Low octaves are analytic proxies for the real filtered RG16F cache. These are requested evaluations per active cloud point, not GPU calls or projected-frame frequencies.

| View y | Clustering | Original | Tight far decision | Cheaper conservative far decision |
| ---: | ---: | ---: | ---: | ---: |
| 0.40 | 0 | 3 | 2.300 | 2.534 |
| 0.40 | 1 | 3 | 2.691 | 2.809 |
| 0.15 | 0 | 3 | 0.608 | 0.621 |
| 0.15 | 1 | 3 | 1.315 | 1.610 |

The observed linear-RGB errors stayed below 0.001 in these screens. The near-horizon reductions partly reflect the existing fade suppressing relief's contribution. The original code already skips relief when its weight is exactly zero.

A separate stress test sampled one million arbitrary bounded tuples per dtype, with contribution weights up to 1.5. Float32 rounding exceeded the computed endpoint bound by up to \(8.94\times10^{-8}\). A \(10^{-7}\) acceptance margin avoided budget overruns in that CPU screen. This margin is empirical and must not be adopted as a certified Metal margin.

### 5.5 Execution coherence can erase much of the benefit

A second screen uses actual normalized directions in a hypothetical 1920×1080 view, 75-degree vertical FOV, and 20-degree camera elevation. In one centered 256×256 clustered patch, individual active pixels requested 2.331 samples on average, but a hypothetical 1×32-lane grouping issued 2.501 of the three possible sample paths.

That grouping is not a claim about Apple's pixel-to-SIMD mapping. It demonstrates why per-pixel skip counts are insufficient. A lane that needs far can keep that path active for its cohort.

**Decision:** test the cheap bound first, independently from corner sharing. Capture execution cost, available occupancy/register/divergence metrics, and actual sampled image differences. If endpoint calculation and divergence cost more than the omitted density calls, reject the scheduler even when its mathematics is correct.

### 5.6 Derivative and sampler discipline

The detail path currently uses `texture()` on a non-mipmapped linear sampler. Additional varying branches should be verified in the real Metal and Compatibility consumers. For a future mipmapped or anisotropic path, compute gradients before nonuniform control flow or use a suitable explicit-LOD/gradient operation. An explicit LOD-zero candidate may be appropriate for the current single-level cache, but it must be checked against the shader language and engine lowering. The [GLSL specification's derivative restrictions][P2] explain the risk; they do not establish an existing rendering bug in this shader.

## 6. M04 — Use geometry to reject zero-support angular work

**Source:** [sun and moon aureoles, sun disc profile][S4].  
**Evidence:** `angular/angular_lab.py` → `angular_support`.

For directions whose angular separation must exceed \(\theta_0\),

\[
\theta\geq\theta_0\iff\mu\leq\cos\theta_0.
\]

The sun and moon aureole functions return zero at 45 degrees, but compute `acos` first. A conservative dot-product rejection can return zero before that operation. The ordinary disc has analogous zero support outside \(1.1r_s\).

The portable cutoff screen used a global grid plus float32 neighbors near the boundary: 1,002,126 distinct inputs in total. Two-ULP downward guards produced zero observed false culls. The test did not exhaust every float32 input and does not prove the guard for every Metal math mode.

A 45-degree cap covers about 14.64% of a unit sphere. That is a geometric support fraction, not the share of a particular viewport or a speedup prediction.

The existing moon-disc code computes derivative-based antialiasing widths. Do not move a varying early-out ahead of those derivatives. Uniform disabled-effect checks can be moved without creating that divergence, subject to preserving their semantics. Keep the optional solar limb/squash path distinct from the ordinary radial disc.

## 7. Ground: remove redundant coordinate and basis work

**Sources:** [grass surface][S5], [ground shader][S6], [photographic detail helpers][S7].  
**Evidence for this section:** `ground/ground_math_checks.py` and `ground/results.json`.

### 7.1 M05 — Compute the macro-noise footprint once

The macro function samples filtered noise at scales 37, 160, 9, and 60 meters. Under a locally affine screen mapping, constant positive scale \(s\), and translation \(t\),

\[
D(p/s+t)=D(p)/s.
\]

Compute the base footprint

\[
F=\max(\|dFdx(p)\|,\|dFdy(p)\|)
\]

once, then use \(F/s\) at each octave. Source spelling changes eight vector derivative operations and eight vector lengths to two of each, plus scalar divisions. Actual generated code may already share some work.

In 500,000 synthetic float32 quads, half concentrated around existing filter transitions, the maximum difference in combined macro noise was \(9.06\times10^{-6}\); the dry-patch weight changed by at most \(3.50\times10^{-5}\). Differencing rounded transformed coordinates is not exactly the same as transforming their finite differences, so this is a tolerance-based render refactor.

Keep derivatives outside divergent control flow. The shared include has ground, near-grass, and lake-bank consumers. The bank also has an independent 2.8-meter `filtered_vnoise` call; retain a standalone wrapper or update it correctly. Test distant grazing views, large coordinates, shorelines, and near-grass seams.

### 7.2 M06 — Preserve the analytic terrain gradient and simplify its evaluation

Terrain relief already has analytic gradients:

\[
h=A W,\qquad \nabla h=A\nabla W+W\nabla A.
\]

The fragment consumes the two slope components, not the returned height. Compute the three phases and their cosines once, then form both directional derivatives. Where \(\nabla A=0\), the \(W\nabla A\) term vanishes and the three sine evaluations are unnecessary. Where both \(A=0\) and \(\nabla A=0\), skip all waves. The feather regions require the full expression.

The current source spells three sines and six cosines. The proposed path spells three cosines and conditionally three sines before compiler common-subexpression elimination. A 300,000-point float32 screen, including 100,000 nonzero amplitude gradients, found maximum slope-component difference \(7.45\times10^{-9}\) and maximum modeled normal-angle difference \(4.77\times10^{-7}\) degrees.

Keep physics terrain evaluation unchanged. The current `test_ground_terrain.gd` asserts literal shader substrings and also uses a CPU mirror. A legitimate refactor must update the test while preserving surface precedence, edge gradients, and normal-sign checks. A passing string assertion or CPU mirror does not prove GPU equivalence.

### 7.3 M07 — Skip photographic samples whose blend weight is exactly zero

The anti-tiling helper uses

\[
b=\operatorname{smoothstep}(0.15,0.85,\operatorname{fract}(k)).
\]

At \(b=0\) or \(b=1\), one of the two finite texture values has no contribution. For albedo, normal, and roughness, the affected material can request three samples rather than six. Retain the existing explicit gradients and compute them before branching.

A uniform-area 65-meter disk screen put 29.54% of positions at one endpoint. Idealized axis-aligned 2×2 quads were wholly at the same endpoint in 27.60%, 20.03%, and 9.50% of cases for world-space pixel steps of 0.01, 0.05, and 0.12 meters.

These distributions are not a projected image. Branch divergence, predication, and compiler scheduling determine whether requests actually disappear. Near the endpoint, do not replace exact equality with an arbitrary threshold without a separate texture/color error bound.

Where both grass and dirt contribute at the same world position, their anti-tiling noise index, blend, and offset hashes can also be shared even though tile scales differ. Test lake-bank consumers and normal decoding, not just ground albedo.

### 7.4 M08 — Share the grass/dirt tangent frame in overlap pixels

Both photographic materials build a frame from the same base normal. For an orthonormal matrix \(M=[T\ B\ N]\),

\[
\operatorname{normalize}(Mx)=M\operatorname{normalize}(x).
\]

Construct the frame once, normalize each map normal in tangent space, blend there, normalize the blend, project once, and retain a final post-projection normalization. That last normalization is included in the numerical model. Preserve the original dirt-only and grass-skipped paths, including incoming normal magnitude where it matters.

The 400,000-case float32 model found median angular difference \(1.82\times10^{-6}\) degrees, p99 \(6.12\times10^{-6}\), and maximum 0.0001394 degrees. Near-degenerate bases drove the largest difference. The model did not include the actual view transform, texture decode, or GPU.

Verify frame conditioning and the rigid-view-transform assumption. This is an overlap optimization; it does not reduce work in every ground pixel.

## 8. M09–M10 — Native arithmetic reuse inside one physics evaluation

**Sources:** [spatial aerodynamic bridge][S11], [native aero][S12], [GDScript aero][S13], [native math shim][S14], [glow propeller][S15].  
**Evidence:** source dependencies; `native/probes.py` demonstrates two hazards, not an implemented performance gain.

### 8.1 Pass already validated wing-flow results into their consumers

For nonuniform station wind, `spatial_aero_loads` computes reference and spatial wing flows, validates them, then calls `local_loads` for those same inputs. The latter recomputes the corresponding wing flow.

Pass the immutable results to their matching local evaluation. Restrict lifetime to this exact RK evaluation and distinguish reference versus spatial delta inputs. The optional reference wake evaluation may also reuse its matching result when downwash is NaN, after preserving the existing validation sequence.

For six strips, removing two passes removes twelve strip evaluations per qualifying call. With four RK stages and 240 ticks per second, continuous use of this route implies

\[
2\times6\times4\times240=11{,}520
\]

fewer source-level `atan2` evaluations and 23,040 fewer square roots per simulated second. This illustration excludes extra event/substep evaluations and says nothing about CPU time. Uniform spatial input follows a different path.

Do not reuse values across stages, accepted ticks, changed controls, clean/flapped variants, or altered wind inputs. Preserve refusal order, rollback, NaNs, and signed-zero behavior. Prefer a small immutable result parameter over a general cache with invalidation logic.

### 8.2 Lazily prepare flap invariants

Within `_wing_flow`, flap limit, raw shift, and

\[
bounded\_shift=limit\,\tanh(raw\_shift/limit)
\]

are invariant across covered strips. Evaluate that exact sequence once when first needed. For \(C\) covered strips, this removes \(C-1\) repeated tanh evaluations. Keep the strip-specific coverage, gain, cosine, and multiplication order.

In `_local_loads`, the same-stage flap sine, cosine, and squared-sine expressions are also candidates for exact-value reuse. Avoid factoring surrounding products into a new order.

### 8.3 Prepare clean-strip sources outside the receiving-strip loop

For coupled flapped flow, the inner loop recalculates the clean angle, clean stall weight, and clean source factor for every receiving strip. Those preparations depend on source strip \(k\), not receiver \(i\).

With \(N\) strips and \(A\) receivers entering the branch, preparation falls from \(AN\) to \(N\). The \(AN\) map products remain. Accumulate them in the same serial \(k\) order. Lazily initialize the prepared values only if a receiver needs them.

The glow propeller has a smaller analogous candidate: reuse `axial_speed * axial_speed` and `0.5 * rho` across its twelve annuli. Geometry and pitch angles are already prepared. Preserve all checks and the original serial sums; this saves at most eleven repetitions of each product on a full pass.

### 8.4 A realistic Apple-native CPU route

[AArch64 Neon supports two 64-bit floating-point lanes][P3] in a 128-bit vector. A sensible experiment batches independent strip arithmetic in pairs while retaining source-order reductions and the chosen transcendental semantics.

The current research `nk::R` shim explicitly targets GCC/x86-64/SSE2 to preserve operation and NaN operand order. It requires an actual Apple port and platform oracle work; a compiler flag cannot turn it into an arm64 backend.

Do not globally enable fast math to force vectorization. [Apple's SIMD documentation][P4] says some fast double-precision functions can provide as little as 22 bits of accuracy, and default function selection can depend on `-ffast-math`. [LLVM][P5] also distinguishes reordered reductions from ordered reductions that can preserve results on supported targets.

Start with finite independent arithmetic, inspect compiler vectorization remarks, and keep the oracle-visible scalar fallback. Library vector calls may have overhead that is excessive for six strips. The right answer depends on real per-stage cost and the exact replay contract, not an abstract preference for vector APIs.

### 8.5 Two probes show why exactness must be checked

A 10,000-case binary64 quaternion experiment compared the current grouped rotation with a real-arithmetic-equivalent matrix expression. At least one output component differed in 9,673 cases; maximum component difference was \(1.42\times10^{-14}\). That is a reassociation result, not a trajectory error estimate. Intermediate RK quaternions are intentionally used as supplied; normalizing them would change the method.

A fixed signed-zero case also showed that copying all flow components from one formula to another can change bytes. One path preserves a negative-zero arm; another adds positive zero and changes its sign. Their plane-speed squares happened to match in that probe. Reusing the exact `WingFlow` result at its identical call site is a narrower proposition than sharing every intermediate across different formulas.

## 9. M11 — A polynomial for the bounded transmission interval

**Source:** [cloud relief][S3].  
**Evidence:** `angular/angular_lab.py` → `exp_polynomials`.

Here the exponential argument has a fixed real-arithmetic range:

\[
z=1.6(0.65n+0.45m+0.25f)\in[0,2.16].
\]

A bounded domain permits a controlled approximation rather than a generic fast exponential. Set \(a=1.08\), \(x=z/a-1\). The Chebyshev expansion is

\[
e^{-z}=e^{-a}\left[I_0(a)+2\sum_{k=1}^{\infty}(-1)^k I_k(a)T_k(x)\right],
\]

where \(I_k\) is the modified Bessel function. Since \(|T_k(x)|\leq1\), omitted coefficients bound truncation error. The script uses

\[
I_k(a)\leq\frac{(a/2)^k}{k!}
\exp\left(\frac{a^2}{4(k+1)}\right)
\]

and a geometric majorant for the remaining tail.

A degree-five polynomial, in ascending powers of \(z\), has the following rounded float32 coefficients:

~~~text
0.9999735951423645
-0.9990943074226379
0.4949013292789459
-0.15594348311424255
0.031035516411066055
-0.00297039863653481
~~~

Evaluate with Horner's method. On 398,536 distinct float32 inputs, non-FMA evaluation had maximum absolute transmission error \(2.6417046\times10^{-5}\). The exact-coefficient real-arithmetic truncation bound was \(2.6422810\times10^{-5}\). Since \(B\leq0.5\) under the bounded-body/normalized-direction assumptions, the sampled transmission error implies at most half that scalar-relief error, before consumer weights.

Higher degree is not a substitute for rounding analysis:

| Degree | Real truncation bound | Maximum sampled float32 error |
| ---: | ---: | ---: |
| 5 | \(2.64228\times10^{-5}\) | \(2.64170\times10^{-5}\) |
| 6 | \(2.00678\times10^{-6}\) | \(2.05099\times10^{-6}\) |
| 7 | \(1.33833\times10^{-7}\) | \(4.01837\times10^{-7}\) |

The degree-six and degree-seven rounded evaluations exceed their real truncation bounds. The sampled float32 endpoint is approximately 2.160000086, slightly beyond the ideal interval ending at 2.16. Neither the ideal coefficient bound nor this sample establishes an all-input GPU bound.

This remains lower priority than eliminating density work. Five multiply-add stages can be slower than a hardware-supported exponential or can increase register pressure. Test the actual generated Metal path, compare the native exponential, and combine its numerical budget correctly with any relief scheduler.

## 10. Experiments that should not be promoted yet

### 10.1 A local density gradient does not replace displaced cloud relief

The analytic derivative of the float64 cloud proxy matched central differences to maximum \(5.68\times10^{-7}\). Yet replacing the three displaced density samples with a tangent at the body produced scalar-lighting errors up to 0.573 at low sun and 0.126 even at light y = 0.99.

The derivative was not the problem. The displaced samples encode an optical-depth heuristic over finite distances. A local tangent is a different model. Keep this rejection in the record so the same shortcut is not repeatedly rediscovered.

### 10.2 Dropping high octaves needs a footprint model, not only a mean

For the last two octave weights, the normalized residual support width is

\[
A=\frac{0.0625+0.03125}{0.96875}=0.09677419.
\]

For independent uniform lattice values and uniform quintic phase,

\[
Q=\int_0^1[(1-h(t))^2+h(t)^2]\,dt=\frac{181}{231},
\]

\[
\sigma=\frac{Q}{\sqrt{12}}
\frac{\sqrt{0.0625^2+0.03125^2}}{0.96875}
\approx0.01631546.
\]

Let \(L_{\text{low}}\) be the normalized sum of octaves 0–2, and let \(S(x)=\operatorname{smoothstep}(1-C,1.25-C,x)\) for fixed local coverage \(C\). A two-point moment model estimates the thresholded density by

\[
\tfrac12 S(L_{\text{low}}+A/2-\sigma)+\tfrac12 S(L_{\text{low}}+A/2+\sigma).
\]

Across the selected seeds it reduced a conditional-bin bias metric relative to substituting the mean. A uniform-residual integral was worse because the residual distribution is not uniform across its support.

The stronger test compared against 16×16 supersampled square footprints. Active-density RMSE remained roughly 0.039–0.067. Low octaves also vary within the footprint, and the deterministic field has spatial correlation. Therefore the approximation is not ready as a filtered replacement.

The research direction is still useful: represent uncertainty and frequency bands explicitly, then integrate the **thresholded density and lighting** over the pixel footprint. Filtering noise before a nonlinear threshold is generally not equivalent. [Cook and DeRose's wavelet-noise work][P6], [ray differentials][P7], and [analytic Gabor filtering][P8] provide primary starting points. They motivate an alternative field representation, not a drop-in claim of preserved OpenRC cloud appearance. Review implementation licensing before borrowing any published code.

### 10.3 M12 — Unguarded squared-distance parcel ranking changes material identity

Replacing nine distances with squared-distance comparisons and only two final square roots is tempting. In real arithmetic the ordering is preserved. In float32, different squared distances can round to the same square root; the current strict comparison order then matters.

A 70,000-point near-bisector screen found a maximum raw crop-factor difference of 0.283. With the default distance fade and parcel strength, the maximum multiplicative-factor difference was 0.133. These are material-factor differences, not final pixel RGB errors.

A guarded experiment rejected a candidate only when its squared distance was conservatively above the current second distance squared. It retained the original square-root evaluation and comparison order for candidates near the threshold. With an empirical 1.000001 guard, it preserved selected IDs and factors in 250,000 random samples and 70,000 boundary samples, averaging 4.88 roots instead of nine in the random set.

The guard is not a proof for the actual GPU-lowered `distance` operation. Extra branches can outweigh the saved roots. Keep this below the simpler shared-work candidates.

### 10.4 R02 — Analytically integrate terrain waves over a pixel

For constant amplitude and a locally affine pixel footprint, a sinusoidal slope's box average is its center value multiplied by

\[
\operatorname{sinc}(k\cdot d_x/2)
\operatorname{sinc}(k\cdot d_y/2).
\]

The bound \(|\operatorname{sinc}q|\leq\min(1,1/|q|)\) yields an envelope for omitted waves. A synthetic 300,000-quad screen used constant amplitude 0.007 meters, zero amplitude gradient, distance weight 1, and footprint width uniformly sampled over the existing 0.08–0.41-meter fade. With a total 0.001-radian budget split among three terms, it skipped any/all terms in 9.98%/7.68% of cases without a sampled bound violation. These percentages are not scene-visible frequencies.

However, the filtered reference itself differed from the current point-sampled slope by p99 0.00497 and maximum 0.01055. This changes the target image and adds filtering work. Perspective and amplitude-boundary effects need a better model. Use supersampled moving reference images before treating the new filter as preferable.

A simpler pointwise envelope also tested in the kit assumes constant 0.007-meter amplitude and zero amplitude gradient. It skips all waves in only 1.54% of uniformly sampled relief weights under the same total budget. That weak rate does not justify a broad claim of cheap relief.

### 10.5 Fog is a weak pruning argument for the default pilot viewpoint

For final color \(C=T S+(1-T)H\), a bound \(E\) on the entire shaded pre-fog surface change becomes \(TE\). With sampled defaults \(\beta=0.00017\), distance rim 4,800–6,000 meters, and `rim_angular=false`, a linear budget of \(1/255\) permits omission of a term bounded by 0.03 only beyond approximately 5,728 meters.

At 1.7-meter camera height this is about 0.017 degrees of flat-ground depression. At 200 meters it is about 2.001 degrees. Distances here are slant range, so the geometry uses \(\arcsin(h/d)\).

The shader supports other fog/rim settings, and terrain is not always flat. This result does not rule out heavier-fog or aerial applications; it explains why a generic “fog hides the far ground” optimization is low priority for the sampled pilot-view defaults. An albedo error is not automatically a bound on the complete shaded surface color.

## 11. Apple Silicon implementation strategy

### 11.1 Optimize a cost equation, then inspect the machine result

For each candidate, reason about

\[
\Delta C\approx
-C_{omitted\ work}
+C_{decision}
+C_{extra\ live\ data}
+C_{divergence}
+C_{new\ memory}.
\]

This is a decision framework, not an additive hardware timing model. Overlap and latency hiding make actual cost more complex.

For M01, retain four hashes only as long as their three nearby consumers need them. The four-query variant may save more arithmetic and still lose from longer live ranges. For M03, compare the cheap constant bound with the tight transmission bound. For M07, measure coherent endpoint regions rather than counting individual endpoint pixels.

[Apple documents][P9] function constants as a way to specialize shaders and remove unreachable code, and resource usage as a constraint on occupancy. In Godot, verify what the engine exposes and inspect the generated pipeline; do not assume that adding a uniform creates a Metal function constant. A small set of meaningful variants may help; uncontrolled variant multiplication raises compile and maintenance costs.

### 11.2 Use precision by domain, with measured error

A packed/half intermediate may reduce some resource pressure, but hash coordinates, periodic boundaries, thresholds, optical depth, and small angular differences deserve separate analysis. Do not blanket-convert the shader to half. The real C5b cache already quantizes low octaves to RG16F, so any new approximation must be evaluated on top of that baseline.

For CPU simulation, retain float64 and the established oracle. An arm64-native implementation can still remove duplicate work and batch independent operations.

### 11.3 Hardware capabilities must be discovered

Query runtime-supported features. [Apple advises against hard-coding SIMD group size][P10]; use the compute pipeline's execution width or the shader's supported query where appropriate. The 32-lane model in this kit is intentionally hypothetical.

Apple's [newer shader-profiling features][P11] include capabilities associated with M3/A17 Pro and later. Do not make those tools a mandatory M1 gate if the device cannot provide them. Record the counters and tooling actually available and rely on production frame captures, comparable timings, and supported diagnostics.

## 12. Concrete integration and qualification plan

### 12.1 Implementation batches

| Batch | Work | Why separate |
| --- | --- | --- |
| A | M01 coarse corner reuse | Tests exact shared work independently of approximations |
| B | M02 chord solar path; M04 support rejection as a separate toggle | Distinguishes parameterization error from zero-support culling |
| C | M03 cheap scheduler, then tight scheduler if warranted | Exposes decision overhead and divergence |
| D | M05, M06, M07, M08 one at a time | Reveals which ground refactor survives compiler optimization |
| E | M09 and M10 inside native/reference evaluation seams | Requires physics parity rather than image tolerances |
| F | M11 only if profiling supports it | Avoids optimizing an inexpensive exponential while missing larger costs |

### 12.2 Reuse the project's existing tools

The [atmosphere tool contract][S16] describes the real cloud-density/relief probe and L4c capture/profile workflows. Use `shadow_map_probe.gd` and the actual sky consumer for candidate/reference differences, including wrong-seed and disabled-cache cases.

For ground, follow the [graphics tool catalog][S17]: surface/stripe checks, grass and grass-seam checks, and the supersampled linear-light grass/filter capture comparisons. Use the ground terrain test for contract regressions and its rendered capture from an isolated application copy because it has a fixed relative output path.

The portable scripts in this kit fill a mathematical-screening gap. They are not replacement profilers or production shader tests.

### 12.3 Required evidence for a rendering promotion

Record source SHA, engine build, renderer, hardware/OS, active reconstruction mode, actual output and internal dimensions, scene/weather seed, camera, and settings.

First qualify at actual 1920×1080. Auto currently selects Native at that height; hold the mode fixed in paired comparisons. Higher-resolution cases are additional evidence; a 720p result does not qualify the requested 1080p workload.

For each independent candidate:

1. Compare raw quantities at the modified consumer, including seams, boundaries, extreme supported settings, and negative controls.
2. Check both maximum and distributional error. Inspect motion, shimmer, solar edges, cloud silhouettes, normals, and final tone-mapped output.
3. Run paired complete-frame A/B captures with the same warmed workload, stable power/thermal conditions, and no competing campaign.
4. Measure median and tail frame times with repeated pairs. Inspect GPU cost and CPU submission changes separately where tooling supports it.
5. Review generated shader changes and available texture/register/divergence counters.
6. Keep a candidate only if the improvement is reproducible and its image/contract budget passes. Combine winners afterward and remeasure the combination.

Do not sum individual percentage improvements. Their bottlenecks can overlap or shift.

### 12.4 Required evidence for a physics promotion

Compare component bytes and established reference/native oracles before timing. Exercise clean/flapped and tailless paths, nonuniform station winds, zero/reverse flow, malformed inputs, NaNs/signed zero, rejection and rollback, event probes, and same-tape replay. Keep original serial accumulation order.

If a future alternative solver intentionally changes numerical semantics, it needs a separate scientific and replay contract. It should not enter through a performance refactor.

## 13. Reproducible kit and result interpretation

The ZIP is self-contained for the portable probes. It does not include a checkout of OpenRC or require a running game. Each source transcription points to the frozen repository.

~~~sh
python3 -m venv .venv
. .venv/bin/activate
python -m pip install -r requirements.txt
python run_all.py --output-dir reproduced
~~~

The runner copies the probe scripts into the output directory, runs them sequentially, and compares produced JSON with the retained JSON. It preserves the shipped reference files. Different numerical libraries or hardware may produce small differences; a mismatch is a reproducibility finding, not an application regression.

| Directory | Contents |
| --- | --- |
| `angular/` | Solar chord/support, transmission polynomial, and fog-bound probes |
| `noise/` | Shared cells/corners, seams, interval scheduling, coherence, derivatives, and residual-filter controls |
| `ground/` | Footprint sharing, parcel ranking, texture endpoints, normal frames, relief waves |
| `native/` | Signed-zero and quaternion reassociation probes plus source-derived reuse notes |
| `sketches/` | Uncompiled integration sketches for solar and relief decisions |
| `source_manifest.json` | Frozen source identity, URLs, and hashes of source text available to the lab |
| `verification.json` | Packaging/reproduction verification for this delivered kit |

Begin with **M01, M02, and the inexpensive form of M03**, and evaluate **M09/M10** where physics is measurable in the actual frame. The lab has narrowed the search and supplied discriminating experiments; target-Mac measurements decide what ships.

## References

### Frozen OpenRC source

[S1]: https://github.com/bultodepapas/OpenRCsimulator/blob/3df2791752fe2c1faad132fcb11febbb0ae788d1/app/render/cloud_field.gdshaderinc
[S2]: https://github.com/bultodepapas/OpenRCsimulator/blob/3df2791752fe2c1faad132fcb11febbb0ae788d1/app/render/cloud_shadow_map.gdshaderinc
[S3]: https://github.com/bultodepapas/OpenRCsimulator/blob/3df2791752fe2c1faad132fcb11febbb0ae788d1/app/render/cloud_relief.gdshaderinc
[S4]: https://github.com/bultodepapas/OpenRCsimulator/blob/3df2791752fe2c1faad132fcb11febbb0ae788d1/app/render/sky.gdshader
[S5]: https://github.com/bultodepapas/OpenRCsimulator/blob/3df2791752fe2c1faad132fcb11febbb0ae788d1/app/render/grass_surface.gdshaderinc
[S6]: https://github.com/bultodepapas/OpenRCsimulator/blob/3df2791752fe2c1faad132fcb11febbb0ae788d1/app/render/ground.gdshader
[S7]: https://github.com/bultodepapas/OpenRCsimulator/blob/3df2791752fe2c1faad132fcb11febbb0ae788d1/app/render/rc_ground_detail.gdshaderinc
[S9]: https://github.com/bultodepapas/OpenRCsimulator/blob/3df2791752fe2c1faad132fcb11febbb0ae788d1/app/render/reconstruction.gd
[S10]: https://github.com/bultodepapas/OpenRCsimulator/blob/3df2791752fe2c1faad132fcb11febbb0ae788d1/optimization%20help.md
[S11]: https://github.com/bultodepapas/OpenRCsimulator/blob/3df2791752fe2c1faad132fcb11febbb0ae788d1/research/native-kernel/src/nk_wake_spatial_aero.hpp
[S12]: https://github.com/bultodepapas/OpenRCsimulator/blob/3df2791752fe2c1faad132fcb11febbb0ae788d1/research/native-kernel/src/nk_aero.hpp
[S13]: https://github.com/bultodepapas/OpenRCsimulator/blob/3df2791752fe2c1faad132fcb11febbb0ae788d1/app/physics/aero.gd
[S14]: https://github.com/bultodepapas/OpenRCsimulator/blob/3df2791752fe2c1faad132fcb11febbb0ae788d1/research/native-kernel/src/nk_math.hpp
[S15]: https://github.com/bultodepapas/OpenRCsimulator/blob/3df2791752fe2c1faad132fcb11febbb0ae788d1/research/native-kernel/src/nk_glow_propeller.hpp
[S16]: https://github.com/bultodepapas/OpenRCsimulator/blob/3df2791752fe2c1faad132fcb11febbb0ae788d1/tools/atmosphere/README.md
[S17]: https://github.com/bultodepapas/OpenRCsimulator/blob/3df2791752fe2c1faad132fcb11febbb0ae788d1/docs/tools/graphics.md

### Primary technical research

- [P1 — Perlin, *Improving Noise* (2002)](https://www.cs.cmu.edu/~jkh/462_s07/paper445.pdf): continuity properties of the quintic interpolant.
- [P2 — Khronos, GLSL 4.60 specification](https://registry.khronos.org/OpenGL/specs/gl/GLSLangSpec.4.60.html): derivatives and nonuniform control flow.
- [P3 — Arm, Neon](https://www.arm.com/technologies/neon) and [ACLE](https://arm-software.github.io/acle/main/acle.html): vector types, operations, and architecture-specific availability.
- [P4 — Apple, double-precision floating-point vectors](https://developer.apple.com/documentation/accelerate/double-precision-floating-point-vectors): precise/fast variants and compiler-flag behavior.
- [P5 — LLVM, Auto-Vectorization](https://llvm.org/docs/Vectorizers.html): vectorization, reductions, and floating-point ordering.
- [P6 — Cook and DeRose, *Wavelet Noise* (2005)](https://research.pixar.com/docs/2005.SiggraphPapers.CD.pdf): multiresolution noise and filtering.
- [P7 — Igehy, *Tracing Ray Differentials* (1999)](https://visionsystems.stanford.edu/papers/trd/): propagation of image footprints.
- [P8 — Lagae and Drettakis, *Filtering Solid Gabor Noise* (2011)](https://graphics.cs.kuleuven.be/publications/LD11FSGN/): analytical filtering research; associated code has separate licensing terms.
- [P9 — Apple, *Learn performance best practices for Metal shaders*](https://developer.apple.com/videos/play/tech-talks/111373/): function constants and shader resource use.
- [P10 — Apple, *Porting your Metal code to Apple silicon*](https://developer.apple.com/documentation/apple-silicon/porting-your-metal-code-to-apple-silicon): runtime capability and SIMD-width guidance.
- [P11 — Apple, *Discover new Metal profiling tools for M3 and A17 Pro*](https://developer.apple.com/videos/play/tech-talks/111374/): generation-specific profiling capabilities.

[P1]: https://www.cs.cmu.edu/~jkh/462_s07/paper445.pdf
[P2]: https://registry.khronos.org/OpenGL/specs/gl/GLSLangSpec.4.60.html
[P3]: https://www.arm.com/technologies/neon
[P4]: https://developer.apple.com/documentation/accelerate/double-precision-floating-point-vectors
[P5]: https://llvm.org/docs/Vectorizers.html
[P6]: https://research.pixar.com/docs/2005.SiggraphPapers.CD.pdf
[P7]: https://visionsystems.stanford.edu/papers/trd/
[P8]: https://graphics.cs.kuleuven.be/publications/LD11FSGN/
[P9]: https://developer.apple.com/videos/play/tech-talks/111373/
[P10]: https://developer.apple.com/documentation/apple-silicon/porting-your-metal-code-to-apple-silicon
[P11]: https://developer.apple.com/videos/play/tech-talks/111374/


