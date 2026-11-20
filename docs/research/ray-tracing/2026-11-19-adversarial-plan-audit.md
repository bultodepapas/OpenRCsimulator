# Optional ray tracing: adversarial plan audit

**Date:** 19 November 2026, America/Bogota.  
**Audited revision:** `bultodepapas/OpenRCsimulator@381d4215b590d09692a090df0fd0fdd43d3a85ba`, branch `ray-tracing`.  
**Disposition:** corrective revision required before treating the plan as a fully specified implementation handoff.  
**Findings:** 16 open — 5 High, 10 Medium, 1 Low.  
**Evidence scope:** source/document review, independent mathematical counterexamples and CPU numerical emulation. No engine build, GPU dispatch, rendered flight, package execution or device-loss experiment was performed for this audit.

The [implementation plan](../../plans/optional-ray-tracing.md) remains the execution owner. This dated report owns the findings against the frozen revision above; the [twenty-investigation record](2026-11-19-twenty-investigations.md) remains historical research. The accompanying plan notice and documentation-index update expose this audit without silently rewriting the contracts being judged.

## 1. Verdict and scope

The architecture remains a reasonable bounded proposal: optional sun visibility, raster fallback, explicit geometry and history ownership, separate capability and execution receipts, and preservation of simulation behavior. Its level of detail does not yet make every acceptance test sound or every transition executable. The principal risks are invalid geometry reaching the native AS API, a reference that falsely certifies itself, history crossing physically distinct surfaces, activation outside qualified configurations, and incomplete recovery after a later crash.

The report distinguishes a **source defect** from a **specification gap** and a **proof failure**. A constructed counterexample establishes that a proposed rule is insufficient; it does not establish that the current game already exhibits the failure. RT is not implemented by the audited documents. Existing tests mentioned in the plan are proposed work, not results.

### Audited artifacts and evidence boundaries

| Artifact | Frozen identity | Audit coverage |
| --- | --- | --- |
| [Implementation plan][P] | Git blob `5870af2f9c406dbb69935075d26c49391d2102f9` | Architecture, phases 00–19, test families, acceptance limits, reducer and release claims |
| [Twenty investigations][R] | Git blob `9413a231063fda11dd1fe1a186e58935bcfdfdf2` | Proposed conclusions and their translation into executable contracts, particularly I12–I15 and I19–I20 |
| Documentation map | Git blob `14ec4330da6062d92b42f9e5f433c3c654072240` | Ownership and status consistency |
| Application and owning contracts | OpenRC `e0a733937e255bacfe95ff09db0fb3838697239f` | Shadow policy, vegetation alpha, recovery guard, advanced-graphics acceptance and referenced ownership |
| Official engine | Godot `cafc17a192acf67903910a68aeb3c076c0907a4b` | RD geometry validation, Vulkan address construction, culling, MSAA resolve, directional PCSS and alpha hash |
| Denoiser | FidelityFX-SDK `c6efa6bf7f2027b3ec94f28578bb5965eabb9e55` | Shadow classifier, moment recurrence and retained input semantics |

The two RT documents were checked against their remote contents. The earlier 52-branch inventory and 20 investigations are inputs to this review; this audit does not claim a second complete review of every branch or every historical commit. Three independent reviewers examined engine boundaries, temporal/numerical correctness, and execution/release contracts; the lead checked the accepted claims against pinned sources.

**Severity:** High blocks the affected implementation or qualification boundary until its contract is corrected. Medium requires a precise correction before the associated milestone can close. Low is a local sequencing defect. No Critical finding or observed production GPU failure is claimed. Unavailable hardware and tests explicitly left unexecuted by the plan are limitations, not findings by themselves.

### Finding register

| ID | Severity | Finding | Boundary affected |
| --- | --- | --- | --- |
| A01 | High | BLAS span arithmetic can wrap before validation | 01–02, every AS producer |
| A02 | High | Successive reference agreement can certify a wrong integral | 00, 11, 14, 17 |
| A03 | High | Temporal identity does not define surface correspondence | 05, 10–11 |
| A04 | High | Runtime admission lacks complete qualified-row matching | 03, 12, 14–19 |
| A05 | High | Active-session crash recovery lacks a durable lifetime contract | 04, 13, 15 |
| A06 | Medium | Alpha-hit representation omits native inputs and hash footprint | 05, 08 |
| A07 | Medium | FP16 moment diagnostics lack a numerical acceptance rule | 11 |
| A08 | Medium | The cost statistic measures a tail shift, not per-state incremental p95 | 00, 14 |
| A09 | Medium | Five-pair interval and extension lack coverage calibration | 00, 14 |
| A10 | Medium | Hard-only delivery and common MSAA prerequisites are ambiguous | 09–15 |
| A11 | Medium | Benefit and native-PCSS calibration lack an executable decision | 00, 11, 14 |
| A12 | Medium | Export qualification can inherit an editor-only verdict | 14–15 |
| A13 | Medium | Owning performance gates are not composed into the reducer | 00, 14 |
| A14 | Medium | Native Soft with zero angular size can become reported RT Soft/actual Hard | 03, conditional 18 |
| A15 | Medium | Full-width caster/receiver masks lack an exact RT mapping | 05–09 |
| A16 | Low | Feasibility ledger is both after and inside 05.4 | 05.4 |

Every finding is **Open** in this audit. A document correction closes a specification gap only after its affected schemas, phases and test roster agree. It does not close the subsequently required engine, image, hardware or package qualification.

## 2. High findings

### A01 — BLAS span arithmetic can wrap before validation

**Type:** confirmed pinned-source defect omitted from the explicit prerequisite repair list. **Affected contract:** [§3.3, point 4][P-scene], 01.2–01.3 and T02.

The [geometry fields][G-geometry] are `uint32_t`. The pinned [BLAS checks][G-blas] evaluate vertex offset plus count times stride, and the corresponding index span, in that width. A 64-byte vertex buffer with offset `0xfffffff4`, vertex count 3 and stride 12 has a mathematical end of 4,294,967,320, but the unsigned expression wraps to 24. The check accepts the span; the [Vulkan driver][G-address] subsequently adds the original approximately 4 GiB offset to the device address. The nonindexed count is a valid multiple of three. The two prerequisite patches identified by the plan do not repair this check.

T02 already names invalid indices and overflow capacity, and the plan correctly requires typed buffer owners. Neither explicitly requires safe BLAS input-span arithmetic. The indexed path also relies on a debug-only maximum-index check; release validation must not assume that a previously recorded maximum describes an initially empty or subsequently updated buffer.

**Required correction:** establish an enforced validation boundary before any native size query or build. Use checked wide arithmetic for represented spans and allocation sizes; validate format width, alignment, buffer ownership and the maximum referenced vertex for the actual generation. Reject invalid geometry to native fallback. The final-element span formula must account for actual format width rather than rely on unchecked count-times-stride arithmetic. If a trusted adapter provides these guarantees instead of a general RD repair, make that boundary mandatory and prove that every RT geometry producer passes through it.

**Closure proof:** debug and release cases for wrapping offsets/counts, invalid actual index values, updated index buffers, format/alignment failures and near-boundary valid inputs. Assert that rejected inputs never reach a native AS query/build. The CPU witness in §7.1 proves the arithmetic issue, not a GPU crash or malformed current OpenRC asset.

### A02 — Successive reference agreement can certify a wrong integral

**Type:** acceptance-oracle failure. **Affected contract:** [§3.6.2][P-reference], section 4 Soft reference, 11.2, 14.1, I15 and later provider comparisons.

The plan doubles deterministic reference samples until the mean change is below 0.005 and p95 absolute change below 0.02. Agreement between finite sample sets does not bound their shared integration error.

For a concrete uniform-solid-angle radial coordinate `u∈[0,1]`, block the interval `0.01 < fract(32u) < 0.5` in every period. The true blocked measure is 0.49, so visibility is 0.51. Midpoint quadrature at 8, 16 and 32 samples returns visibility 1 at every count. Both changes are zero, while absolute error remains 0.49. Annular occluders on a plane normal to the sun axis can realize this angular pattern. The exact rational calculation appears in §7.2. The plan does not specify this particular quadrature, but it also does not prohibit this false certification; increasing the same deterministic node family is insufficient as the only truth criterion.

**Required correction:** separate numerical stability diagnostics from reference accuracy. Freeze reference methods, minimum/maximum budgets and an uncertainty rule before candidate results. Permit analytic or rigorously bounded deterministic references; otherwise use independently randomized or scrambled estimates independent of the product sequence, with stated assumptions and a valid stopping protocol. Cross-check analytically solvable geometry. Candidate acceptance must use an appropriate upper bound on each required ROI error metric that includes reference uncertainty, or a preallocated uncertainty margin whose soundness is proved. Merely making reference uncertainty smaller than the candidate error budget is insufficient. Mark unresolved references inconclusive; randomization alone is not a universal deterministic error proof.

**Closure proof:** known-solid-angle blockers, phase-aligned annuli/sectors or slats, and independently shifted/scrambled sequences. The reducer must reject the zero-change/wrong-answer example. Apply uncertainty to the ROI metrics used for acceptance, not merely one global average. Define “mean visibility error” explicitly, preferably as mean absolute error when that is the intended criterion.

### A03 — Temporal identity does not define surface correspondence

**Type:** missing data and rejection contract. **Affected contract:** [§3.5][P-receivers], [§3.6.1][P-history], 10–11, T09 and I14.

The plan requires material/instance identity and compatible prior depth, normal and epoch, including every bilinear tap. That footprint rule is useful, but compatibility granularity and depth tolerances remain undefined. The [stock classifier][F-class] checks relative depth; it does not supply the missing surface identity.

Two nearby parallel leaves or aircraft surfaces can share one instance and material, have nearly equal normals, and differ in depth by less than the rejection tolerance. When surface B replaces A at a sample, all those checks can pass although their sun visibility differs. The prescribed different-ID 2×2 fixture will not expose a collision within the same instance/material. Topology generations alone do not distinguish two simultaneously existing surfaces.

**Required correction:** specify stable, generation-matched surface correspondence and its current/prior per-tap representation, or reject history when correspondence is not established. Primitive identity is one possible ingredient, not a requirement to reject every legitimate crossing of an edge within a continuous surface. Define the accepted equivalence and derive depth tolerances from the represented precision and motion contract. Include retained guide storage and bandwidth in the feasibility ledger.

**Closure proof:** two same-instance, same-material, almost coplanar surfaces with similar normals, different occlusion and opposing motion; independently poison their prior histories. Exercise both replacement directions, bilinear footprints, pure depth motion and LOD/topology changes. Correctness must survive without a special reset that conceals the ordinary transition; conservative rejection must still satisfy the fixed final quality gates.

### A04 — Runtime admission lacks complete qualified-row matching

**Type:** missing product-admission rule. **Affected contract:** [03.2–03.4][P-policy], [14–15][P-release] and [§9.1][P-verdict].

The plan separates capability, qualification and effective execution. Phase 12 already requires final mode/field/device qualification before player-facing enablement, and 12.2 requires current executability in the UI. The remaining gap is operational: the phase-03 resolver names an admitted engine/device row, while evidence also varies by aircraft model, provider, MSAA, driver and content identity. The final schema requires representable restrictions but leaves untested-driver rollout policy to later documentation. The complete matching and invalidation rule is still undefined.

A field/device/mode receipt could be reused after a model, provider, MSAA or relevant content change unless the runtime matches and invalidates those finer dimensions. That would violate the plan's qualification intent while appearing to pass a coarser admission check. This finding does not claim that the plan permits a wholly unqualified field/mode/device.

**Required correction:** define a versioned admission record bound to the qualified artifact/content identities and all dimensions that actually constrain a row. Specify how matching works for field/model/mode/renderer/provider/MSAA and driver policy; avoid accidental requirements that every irrelevant setting create a new row. Effective activation must require both capability and admission. Unknown combinations need an explicit product rule; conservative native fallback is consistent with the current opt-in contract. A separate experimental path would require its own stated scope and disclosure.

**Closure proof:** capable-but-unqualified field, model, mode, provider and driver-policy cases; runtime field/model/settings changes; stale admission manifests and content revisions. Verify stable reasons, preserved saved requests, no unauthorized active work and correct re-admission after a qualifying change. Documentation-only restrictions do not pass.

### A05 — Active-session crash recovery lacks a durable lifetime contract

**Type:** incomplete persistent-state protocol. **Affected contract:** [§3.8][P-state], 04.4, 13.1–13.2 and 15.2.

The plan persists an activation marker before preparation and promises RT-off recovery after device loss or process crash. It does not say how the marker remains effective after initial confirmation. The analogous existing [MetalFX guard][O-guard] clears its pending activation marker on confirmation. That is evidence about a reuse hazard, not proof that the future RT guard will copy it.

If RT clears its only marker after its first completed frame, an abrupt crash twenty minutes into active flight can leave a saved On request with no durable indication of the unclean RT session. Restart can reactivate the same path. Waiting for a GPU-completed frame fixes premature activation confirmation; it does not cover later crashes.

**Required correction:** specify a durable active-session/unclean-exit latch, or an equivalent restart protocol, that survives for the entire period in which RT can execute. Define persistence failure, clean shutdown, safe deactivation, cancellation, explicit retry and fallback-restart failure. Clear the latch only at the corresponding safe boundary. A conservative unclean-exit fallback need not diagnose RT as the cause of every crash.

**Closure proof:** abrupt termination after a confirmed RT frame and during a long flight, device loss, interrupted preparation, direct-flight restart and a failed fallback restart. Verify bounded retries and native startup while preserving the saved preference. Existing interrupted-activation cases alone cannot close this finding.

## 3. Medium findings

### A06 — Alpha-hit representation omits native inputs and hash footprint

**Type:** incomplete GPU data representation. **Affected contract:** [§3.3 alpha prerequisite][P-scene], 05/08, T08 and I13.

The candidate-hit table explicitly lists surface indices, UVs, material parameters, texture and sampler. The admitted [tree-wind shader][O-alpha] also multiplies alpha by interpolated `COLOR.a` before scissor testing, and [vegetation construction][O-vegetation] enables MultiMesh colors. Texture and material alpha 1, effective color alpha 0.25 and cutoff 0.5 produce a native discard; a UV/texture/material-only evaluator accepts the hit and creates a false shadow.

T08 already mentions color, so a well-designed test can expose the omission. The contract still needs to identify the required representation and cost. For alpha hash, the pinned [Godot threshold][G-hash] depends on object-position derivatives. A texture-mip estimate alone does not define that footprint.

**Required correction:** include generation-matched vertex color, effective instance tint and applicable alpha transformations in the hit-evaluation contract, or explicitly exclude and fall back for unsupported variants. Define/prove the object-space hash footprint and temporal policy separately from texture LOD. Charge retained attributes and descriptors to memory and bandwidth budgets.

**Closure proof:** identical geometry/UV/material with different vertex and instance alpha; hash scale/distance cases; authored overrides; mip transitions and known noncasters. Demonstrate native/RT casting parity for each admitted variant. The numerical example proves a missing-input failure mode, not that current tree instances necessarily use alpha 0.25.

### A07 — FP16 moment diagnostics lack a numerical acceptance rule

**Type:** numerical risk with a reproducible controlled counterexample. **Affected contract:** [§3.6.1][P-history], 11.1–11.3, T09 and I14.

The plan acknowledges count quantization, requires 4,096 submissions and a controlled unit-damping diagnostic near count 2,048, and retains final image gates. It does not set a numerical pass rule for the changed moments format. Finite values and a documented count round trip are insufficient.

The [pinned recurrence][F-moments] retains a running mean, squared-deviation accumulator and count. Emulating FP32 arithmetic with round-to-nearest FP16 stores, unit damping, no reset and no homogeneous-tile shortcut, a repeating eight-lit/two-shadow signal gives:

| Submissions | Stored mean | True sample mean | Stored count | Stored variance proxy | True sample variance |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 2,048 | 0.664063 | 0.800781 | 2,048 | 0.148510 | 0.159609 |
| 4,096 | 0.500000 | 0.800293 | 2,048 | 0.307767 | 0.159863 |
| 8,192 | 0.500000 | 0.800049 | 2,048 | 0.500244 | 0.159990 |

These are CPU witness results, not the complete filter or a GPU result. Stock damping/shortcuts can change the trajectory. The stored mean participates in variance estimation; it is not directly the final visibility. Driver rounding and fused operations require their own qualification.

**Required correction:** predeclare moment/variance error tolerances against an independent float64 recurrence for asymmetric mixed signals, including long-lived histories and a subsequent held lighting change. Couple reachable production histories to the unchanged final visibility/response gates. Keep the artificial unit-damping/no-shortcut run as a representation diagnostic; failure there alone does not mandate redesign if the adapter proves that harmful states are unreachable and bounds the numerical error over reachable histories and transitions. Unbounded reachable error or a failed fixed quality gate requires a bounded storage or recurrence design revision with renewed memory and image proof. Neither finiteness nor silent format widening is acceptance.

**Closure proof:** 4,096/8,192-submission controlled sequences, the existing unit-damping seed case, actual stock-damping trajectories and both directions of held change. The recurrence in §7.3 makes this witness reproducible.

### A08 — The cost statistic measures a tail shift, not per-state incremental p95

**Type:** estimand/claim mismatch. **Affected contract:** [section 4 GPU cost][P-gates], [§5.2][P-statistics], 00.3, 14.2 and I20.

The stated whole-effect incremental p95 gate is implemented as the median across pairs of `p95(B)-p95(A)`. This is a valid statistic for the change in each run's 95th percentile. It is not the 95th percentile of added cost at matching scene states.

Consider 1,000 matched states. Raster costs 6 ms for 900 states and 14 ms for 100. RT adds 8 ms to 100 of the cheap states and 1 ms to the remaining 900. Then raster p95 is 14 ms, candidate p95 is 15 ms, and the plan's pair difference is 1 ms. The p95 of the matched incremental costs is 8 ms. Candidate frames never exceed 15 ms, so an absolute frame gate need not expose the distinction. Repeating this distribution across all process pairs produces a tight interval around the wrong interpretation.

**Required correction:** retain the run-tail shift as a product metric if intended, but name it accurately. If the 2 ms requirement is an effect-cost budget, add a separately defined workload-matched incremental estimator or justified whole-effect timing measure that includes guides, AS work, traversal, filtering and induced synchronization. Define logical-state/time-bin matching; the same input tape alone does not ensure corresponding rendered frames when frame pacing differs. Do not sum overlapping phase p95s.

**Closure proof:** the synthetic distribution in §7.4 must report both quantities with distinct labels. Include variable RT activity and workload-state distributions. Freeze which quantity governs which budget before measurements; changing the interpretation after a result would change the gate.

### A09 — Five-pair interval and extension lack coverage calibration

**Type:** statistical acceptance limitation. **Affected contract:** [§5.2][P-statistics], 00.3, 14.2 and I20.

The recipe requests a two-sided 95% percentile-bootstrap interval for a median from five independent pair differences, using 10,000 resamples, then permits one extension to ten pairs if the interval straddles the limit. A reproducible seed makes this deterministic; it does not establish the advertised coverage.

For independent continuous differences with population median `m`, any interval contained in the minimum and maximum of five observations has coverage at most:

`P(min ≤ m ≤ max) = 1 - 2(1/2)^5 = 0.9375.`

A percentile-bootstrap median interval is contained in that observed range. More bootstrap draws do not remove this small-sample ceiling. This argument concerns the claimed two-sided 95% coverage; it does not by itself prove that the upper-bound release decision has a false-accept rate above 5%. The five-to-ten stopping rule also needs its own calibration. Predeclaring a rule is necessary for reproducibility, but does not establish its statistical properties.

**Required correction:** define the intended one-sided admission confidence/false-accept objective, independent experimental unit, sample size, estimator and stopping rule. Use a finite-sample method with justified coverage or demonstrate the complete protocol's coverage under explicit assumptions. A fixed final sample count avoids this particular optional-extension ambiguity. Keep raw pairs and failed attempts.

**Closure proof:** reducer fixtures plus coverage/false-accept evaluation near the budget boundary, with ties, skew, between-process variation and the full extension decision. Do not bootstrap correlated frames as independent evidence. I20 correctly labels its exact recipe a project proposal; this finding challenges that proposal, not its source attribution.

### A10 — Hard-only delivery and common MSAA prerequisites are ambiguous

**Type:** dependency and milestone ambiguity. **Affected contract:** [09–12][P-modes] and [14–15][P-release].

Phase 10 says a failed Soft guide path leaves Hard available as a research mode. Phase 11 qualifies modes separately, phase 12 accepts at least one proven mode, and phase 14 depends on all of 05–13, including Soft-specific work. The agent cannot tell whether a fully qualified Hard row may become a product while Soft is blocked, or whether both modes are mandatory for core delivery.

A related common prerequisite is late: section 3.5 requires native fallback for mixed MSAA surfaces, while 09.4 requests real-flight Hard evidence before 10.3 explicitly implements sample validity. The pinned [prepass][G-prepass] resolves depth/normal data before the proposed insertion; the [resolve shader][G-resolve] does not preserve all sample identities in a single resolved value. Phase 14 eventually requires T05, so this is an earlier-milestone/dependency defect, not proof that the final release must be wrong.

**Required correction:** state whether Hard-only delivery is allowed. If allowed, separate common, Hard and Soft requirements with mode-specific exit edges; a blocked Soft phase must neither masquerade as passed nor unnecessarily block a valid Hard row. If both are required, state that explicitly. Put shared MSAA validity before Hard's relevant image verdict, or restrict that milestone to MSAA Off until the producer is proven.

**Closure proof:** dependency evaluation for Hard-pass/Soft-blocked, both-pass and both-fail; unsupported-mode UI behavior; thin wing/leaf foreground over differently shadowed background at every admitted MSAA count. Reuse the existing T05 cases and require them at the correct milestone.

### A11 — Benefit and native-PCSS calibration lack an executable decision

**Type:** incomplete product acceptance and comparison control. **Affected contract:** 00.2, [section 4][P-gates], 11.4 and 14.1.

The plan promises a measurable ordinary-flight improvement over tuned native shadows. Its numerical limits constrain RT against a reference, without freezing the native-versus-RT metric, minimum meaningful improvement or decision rule. RT could meet its absolute reference limit while native PCSS is equally good or better. “Improves the predeclared defect” still leaves the reducer and reviewer without a common threshold.

Equal angular UI settings are also not proof of matched penumbrae. The RT sampler uses half-angle 0.265° for diameter 0.53°. At the engine pin, [light storage][G-sun] takes the tangent of the full angular parameter and supplies it to the [PCSS search/filter scale][G-pcss]. The resulting visual-width ratio depends on blocker search, blur and kernel behavior; this audit does not claim a universal twofold width.

**Required correction:** before candidate results, freeze the defect metric, direction of improvement, material delta, uncertainty and pilot-readability review rule per relevant field/mode. Retain an unchanged-settings native control and a separately identified, pre-calibrated matched-penumbra PCSS control using known blocker heights. Record angular/blur/kernel settings and the reason for any calibration. Do not silently retune the baseline after seeing RT output.

**Closure proof:** the verdict rejects equal, worse and negligible native-relative results, and accepts a declared meaningful improvement only with no readability regression. Verify simple blocker/receiver penumbra widths before interpreting real-flight quality. Absolute reference accuracy and comparative benefit must appear as separate required results.

### A12 — Export qualification can inherit an editor-only verdict

**Type:** ambiguous artifact boundary. **Affected contract:** [14–15][P-release], T14 and the scope of I19.

Phase 14 obtains image/performance verdicts. Phase 15 requires exported startup, a fixture and a real flight; “core rendered matrix” does not explicitly bind all quality/activity/performance gates to the exact exported release artifact. I19's complete and internally consistent package roster is valuable, but cannot establish exported behavior or timing by itself.

**Required correction:** identify the production measurement artifact before phase 14, or label editor measurements provisional and specify the affected gates that must be repeated on the export. Bind verdicts to executable/template, resource/import, patch and configuration identities. Avoid duplicating every long test without a changed risk; choosing the actual export early can avoid that work.

**Closure proof:** an editor passes but an export that starts and flies exceeds a budget or changes visibility. The package must fail qualification. The release artifact must pass its applicable image, activity, performance, recovery and content-identity gates; startup or matching hashes alone are insufficient.

### A13 — Owning performance gates are not composed into the reducer

**Type:** incomplete cross-plan acceptance mapping. **Affected contract:** [section 4][P-gates], §5.2, 00 and 14.

The retained [advanced-graphics owner][O-vq] requires process-loop p95 ≤18 ms, p99 ≤25 ms, simulation/wall ratio 0.99–1.01, recurring-stall attribution, existing loading goals and actual-export qualification. RT specifies wall-frame p95 ≤18.333 ms and p99 ≤25 ms, and only expressly says a stricter platform gate wins. Preserving the owner by reference does not tell the proposed reducer how these metrics combine.

**Required correction:** freeze an applied-owner/metric mapping in phase 00. Do not assume process-loop and wall-frame measurements are identical; collect both where necessary. When metrics are equivalent, enforce the stricter applicable threshold. Retain simulation/wall ratio and the relevant loading/stall obligations explicitly in the case roster and verdict.

**Closure proof:** a synthetic row with an applicable owner process-loop p95 of 18.2 ms must not pass merely because the RT wall limit is 18.333 ms; a simulation/wall ratio of 0.95 must not pass through unchanged state checkpoints alone. Verify distinct metric domains and the existing Apple native-panel override. This is a composition gap, not evidence that the owner was intentionally waived.

### A14 — Native Soft with zero angular size can become reported RT Soft/actual Hard

**Type:** conditional policy conflict. **Affected contract:** [soft sampler][P-sampler], 03 and any admitted Mobile/Metal row in 18.

The pinned [shadow resolver][O-policy] can select Soft/Auto PCF outside High while setting angular distance to zero. The RT contract follows effective softness, reads effective angular size, handles zero angle exactly as Hard, and forbids silently reporting rejected Soft as RT Hard. Literal composition can report Soft while producing a hard result.

**Required correction:** define the zero-angle/native-PCF Soft case explicitly. A native-Soft fallback with a stable reason preserves current semantics. A distinct nonzero RT solar disk would require an explicit setting/policy decision and qualification; it must not be invented by the implementing agent.

**Closure proof:** Auto and explicit Soft with zero angle, genuine Hard, and Forward+ Soft at 0.53°. Verify requested/effective mode, appearance and reason. This finding applies when such a row is admitted; it is not a claim that Mobile RT currently ships.

### A15 — Full-width caster/receiver masks lack an exact RT mapping

**Type:** underspecified representation and predicate. **Affected contract:** [§3.3][P-scene], §3.5 and 05–09.

“Preserve layers/light masks” is correct but insufficiently executable. Native [directional caster admission][G-caster], using the [layer intersection][G-layer], takes the same-bit intersection of viewport-visible layers, instance layers and the light's shadow-caster mask, with the other visibility/casting rules. The [receiver lighting mask][G-receiver] is a separate predicate. [Vulkan's instance mask][V-mask] has only eight bits.

For instance mask `0x3`, viewport mask `0x1` and sun shadow-caster mask `0x2`, the triple intersection is zero. Testing the two overlaps independently would incorrectly admit the caster. Copying native layers into the eight-bit RT mask also loses higher bits.

**Required correction:** spell out the full-width caster predicate and apply it per viewport/selected sun before TLAS admission, or prove an equivalent representation. Use the RT visibility mask for its specified purpose; do not truncate native layer semantics into it. Keep receiver-light masking distinct and preserve shadow-only geometry and native visibility rules.

**Closure proof:** a native layer above bit 7, the split-overlap example, shadow-only geometry, different caster versus receiver masks and runtime mask changes. The plan's broad preservation rule remains valid; this finding supplies the missing concrete contract.

## 4. Low finding

### A16 — Feasibility ledger is both after and inside 05.4

**Type:** local sequencing contradiction. **Affected contract:** [§3.3.2][P-feasibility] and 05.4.

The architecture says to create `scene-feasibility.json` “after 05.1–05.4,” while producing that ledger is an exit condition of 05.4. An executor cannot use both statements as a literal completion order.

**Required correction:** say “after 05.1–05.3, as part of 05.4,” with one owning subphase and the existing 06–11 consumption boundary.

**Closure proof:** the phase dependency roster has one ledger producer, no self-dependency, and all required consumers depend on its accepted identity. No engine test is needed.

## 5. Corrective order and research-record reconciliation

Correct the execution owner and its schemas/tests together. Do not expand this into a renderer rewrite, a second denoiser integration or another broad research round. The required order follows the actual dependency:

| Order | Correction boundary | Findings | Required deliverable before proceeding |
| ---: | --- | --- | --- |
| 1 | Acceptance, reference and measurement definitions | A02, A08, A09, A11, A13 | Fixed oracle uncertainty, benefit rule, metric domains and statistical decision protocol, with negative reducer cases |
| 2 | Mode, admission, recovery and package ownership | A04, A05, A10, A12, A14 | Explicit mode DAG, qualified-row policy, persistent-state lifetime and release-artifact identity |
| 3 | Geometry/data contracts | A01, A06, A15, A16 | Checked spans, full caster/receiver semantics, alpha attributes and a noncircular feasibility producer |
| 4 | Temporal representation and precision | A03, A07 | Defined surface correspondence, costed guides, bounded numerical errors and long-history tests |
| 5 | Integrated handoff review | All | Every affected phase references the same contract; each finding has a correction identity and closure evidence |

Independent source-only baseline work may continue. Do not mark an affected implementation/qualification phase complete using the audited faulty criterion. Correcting a paper contract is distinct from executing its proposed native/GPU proof. A closure record should contain `finding_id`, correction commit, changed contract/test IDs, counterexample outcome, evidence scope and any remaining hardware gate.

The investigation record is useful historical evidence. Its source observations should not be rewritten merely to make the audit disappear:

| Research material | Reconciliation required |
| --- | --- |
| I01/I11 integration boundary | Preserve selected-sun insertion; add A10 common MSAA ordering and A15 exact masks to the execution contract |
| I02/I12 AS ownership | Preserve typed buffers, barriers and publication; add A01 checked input spans |
| I03/I13 vegetation/feasibility | Preserve the live workload requirement; add A06 alpha attributes and A16 sequencing |
| I04/I14 denoiser adaptation | Preserve bit packing, per-tap validity and barriers; close A03 identity and A07 numerical acceptance |
| I05/I15 moving-shadow oracle | Preserve independent same-measure comparison and stage isolation; repair A02 reference certification |
| I06/I16 precision/facing | Preserve the unbiased intersection oracle and restricted error envelope; no new general defect accepted |
| I07/I17 Metal and I08/I18 providers | Preserve separate unqualified rows; apply A04 admission and A14 zero-angle policy where relevant |
| I09/I19 package intake | Preserve completeness/loaded-identity checks; add A12 exact-export behavior/performance boundary |
| I10/I20 timing/reducer | Preserve submitted-frame joins and independent process pairs; correct A08/A09 and compose A11/A13 |

A05 additionally comes from comparing the persistent-state promises with the existing guard's confirmation lifetime. The two-round research order, all 20 investigation entries and the original branch inventory remain unchanged by this audit.

## 6. Verification, rejected leads and limits

The audit checked the frozen document contents, inspected the cited pinned sources and reproduced the arithmetic, reference-aliasing, timing and FP16 examples on the CPU. The small-sample coverage limit is an analytic calculation reproduced below. A separate review of this report tightened A02's uncertainty treatment, A07's distinction between diagnostic and reachable failures, and A04's acknowledgement of existing qualification gates. Those checks are sufficient to expose the specified contract failures; they do not measure scene performance or establish a final algorithm design.

Several suspected defects were deliberately rejected or narrowed:

- **Independent directional-shadow LOD per cascade:** not established. The inspected [Forward+ source][G-forward] passes the main-camera transform and LOD multiplier to directional shadow rendering. Conditional shadow-mesh selection and a narrower orthographic case do not justify a general claim about the initial perspective-flight path.
- **Wrong AS-build read access:** not established. The [Vulkan AS build contract][V-build] specifies shader-read access for geometry inputs; the existing dependency matrix should not be replaced on that premise.
- **Necessarily noncoherent mapped TLAS input:** rejected for the inspected [Vulkan allocation][G-vulkan], which requests host-visible, host-coherent memory. This does not eliminate submission/lifetime requirements.
- **Missing per-buffer barrier proves a same-AS scratch race:** rejected. The inspected [Vulkan driver][G-vulkan] includes global AS memory barriers. The audit does not infer a race solely from the absence of a separate buffer barrier; indirect BLAS lifetime remains a correctly identified proof obligation in the plan.
- **The 71.19 MiB image calculation is wrong:** rejected. Seven payloads at 36 bytes per 1920×1080 pixel equal approximately 71.19 MiB. The plan already excludes guides, masks, AS, alignment and simultaneous generations from that subtotal. Actual peak fit remains unmeasured.
- **History-footprint validation, repeated-reduction synchronization or FP32 fallback are entirely absent:** rejected. The audited revision already specifies full nonzero-weight footprint checks, a third shared-reduction barrier and a required proven FP16 path. A03/A07 address the remaining correspondence/precision gaps.
- **Missing hardware evidence is itself an undisclosed failure:** rejected. The documents distinguish source review from unexecuted GPU and package work. Unavailable rows remain unqualified.

No current asset was shown to trigger A01. No full denoiser flight was shown to trigger A07. No existing production RT recovery path was tested, because the proposed feature is not implemented here. Full engine builds, validation layers, native GPU images, statistical performance campaigns, exported-game execution and crash/device-loss injection remain future qualification work.

External pages that could not be retrieved were not used to support a finding. In particular, A09's conclusion rests on its stated finite-sample derivation, not an inaccessible statistics paper. The official Vulkan instance representation and all consequential project/engine/SDK source claims use the retrieved sources below.

## 7. Reproducible CPU witnesses

These small calculations isolate individual claims. They are not a replacement for the future project test families. Each Python block is self-contained and uses the standard library.

### 7.1 Unsigned BLAS span

```python
offset, count, stride, allocation = 0xfffffff4, 3, 12, 64
mathematical_end = offset + count * stride
uint32_end = mathematical_end & 0xffffffff
assert mathematical_end == 4294967320
assert uint32_end == 24
assert uint32_end <= allocation < mathematical_end
print({"mathematical_end": mathematical_end, "uint32_end": uint32_end})
```

The source fields and expression types establish the unsigned operation; this calculation reproduces its value. It intentionally performs no GPU access.

### 7.2 Zero reference change with 0.49 absolute error

Here `u` is normalized solid-angle radial measure, so a uniform integral over `u` is appropriate. Boundary points have zero measure.

```python
from fractions import Fraction as Q

def visibility(n):
    lit = 0
    for i in range(n):
        u = Q(2 * i + 1, 2 * n)
        phase = (32 * u) % 1
        blocked = Q(1, 100) < phase < Q(1, 2)
        lit += not blocked
    return Q(lit, n)

truth = Q(51, 100)
estimates = {n: visibility(n) for n in (8, 16, 32)}
assert set(estimates.values()) == {Q(1)}
assert estimates[8] - truth == Q(49, 100)
print({n: float(v) for n, v in estimates.items()}, "truth", float(truth))
```

This tests the insufficiency of successive agreement. It does not assert that the executing agent must choose these node counts or this quadrature.

### 7.3 FP32 recurrence with FP16 stored moments

This models the controlled recurrence with unit damping and no shortcut/reset. FP32 rounding occurs at the indicated arithmetic steps; stores round each component to FP16. The sample mean/variance on the right are independent binary-signal references.

```python
import json
import struct

def rnd(value, fmt):
    return struct.unpack(fmt, struct.pack(fmt, value))[0]

def f32(value):
    return rnd(value, "f")

def half(value):
    return rnd(value, "e")

m = s = c = 0.0
lit = 0
rows = []
for i in range(8192):
    x = float(i % 10 < 8)
    lit += int(x)
    count = f32(c + 1.0)
    delta = f32(x - m)
    new_m = f32(m + f32(delta / count))
    new_s = f32(s + f32(delta * f32(x - new_m)))
    m, s, c = half(new_m), half(new_s), half(count)
    n = i + 1
    if n in (2048, 4096, 8192):
        mean = lit / n
        rows.append({
            "n": n, "stored_mean": m, "true_mean": mean,
            "stored_count": c, "stored_M2": s,
            "variance_proxy": s / (c - 1),
            "true_variance": n * mean * (1 - mean) / (n - 1),
        })
assert rows[1]["stored_mean"] == 0.5
assert rows[1]["stored_count"] == 2048.0
print(json.dumps(rows, indent=2))
```

The complete classifier's damping, shortcuts, history clamping and final visibility blend are outside this witness. The audit requires testing them rather than equating the stored mean with final image intensity.

### 7.4 Difference of p95s versus p95 of differences

```python
from math import ceil

def p95(xs):
    return sorted(xs)[ceil(0.95 * len(xs)) - 1]

a = [6.0] * 900 + [14.0] * 100
added = [8.0] * 100 + [1.0] * 900
b = [x + d for x, d in zip(a, added)]
assert p95(a) == 14.0 and p95(b) == 15.0
assert p95(b) - p95(a) == 1.0
assert p95(added) == 8.0 and max(b) == 15.0
print({"run_tail_shift_ms": p95(b) - p95(a),
       "matched_increment_p95_ms": p95(added)})
```

### 7.5 Five-observation two-sided coverage ceiling

```python
from fractions import Fraction

n = 5
coverage_ceiling = 1 - 2 * Fraction(1, 2) ** n
assert coverage_ceiling == Fraction(15, 16)
print(float(coverage_ceiling))  # 0.9375
```

The result assumes independent continuous observations and a population median with probability 1/2 on either side. It bounds any interval contained within the five observations' extrema. It is not a claimed bound for every one-sided or sequential release rule.

## 8. Source register

Plan citations below point to the immutable audited commit, so later notices or corrections cannot change what was evaluated. Application, engine and SDK citations use the exact pins listed in §1. Official Vulkan pages are live specifications retrieved for this audit.

[P]: https://github.com/bultodepapas/OpenRCsimulator/blob/381d4215b590d09692a090df0fd0fdd43d3a85ba/docs/plans/optional-ray-tracing.md
[R]: https://github.com/bultodepapas/OpenRCsimulator/blob/381d4215b590d09692a090df0fd0fdd43d3a85ba/docs/research/ray-tracing/2026-11-19-twenty-investigations.md
[P-scene]: https://github.com/bultodepapas/OpenRCsimulator/blob/381d4215b590d09692a090df0fd0fdd43d3a85ba/docs/plans/optional-ray-tracing.md#L162-L177
[P-feasibility]: https://github.com/bultodepapas/OpenRCsimulator/blob/381d4215b590d09692a090df0fd0fdd43d3a85ba/docs/plans/optional-ray-tracing.md#L194-L202
[P-receivers]: https://github.com/bultodepapas/OpenRCsimulator/blob/381d4215b590d09692a090df0fd0fdd43d3a85ba/docs/plans/optional-ray-tracing.md#L219-L230
[P-sampler]: https://github.com/bultodepapas/OpenRCsimulator/blob/381d4215b590d09692a090df0fd0fdd43d3a85ba/docs/plans/optional-ray-tracing.md#L247-L250
[P-history]: https://github.com/bultodepapas/OpenRCsimulator/blob/381d4215b590d09692a090df0fd0fdd43d3a85ba/docs/plans/optional-ray-tracing.md#L269-L293
[P-reference]: https://github.com/bultodepapas/OpenRCsimulator/blob/381d4215b590d09692a090df0fd0fdd43d3a85ba/docs/plans/optional-ray-tracing.md#L295-L305
[P-state]: https://github.com/bultodepapas/OpenRCsimulator/blob/381d4215b590d09692a090df0fd0fdd43d3a85ba/docs/plans/optional-ray-tracing.md#L323-L336
[P-gates]: https://github.com/bultodepapas/OpenRCsimulator/blob/381d4215b590d09692a090df0fd0fdd43d3a85ba/docs/plans/optional-ray-tracing.md#L371-L392
[P-statistics]: https://github.com/bultodepapas/OpenRCsimulator/blob/381d4215b590d09692a090df0fd0fdd43d3a85ba/docs/plans/optional-ray-tracing.md#L431-L451
[P-policy]: https://github.com/bultodepapas/OpenRCsimulator/blob/381d4215b590d09692a090df0fd0fdd43d3a85ba/docs/plans/optional-ray-tracing.md#L525-L535
[P-modes]: https://github.com/bultodepapas/OpenRCsimulator/blob/381d4215b590d09692a090df0fd0fdd43d3a85ba/docs/plans/optional-ray-tracing.md#L588-L632
[P-release]: https://github.com/bultodepapas/OpenRCsimulator/blob/381d4215b590d09692a090df0fd0fdd43d3a85ba/docs/plans/optional-ray-tracing.md#L654-L675
[P-verdict]: https://github.com/bultodepapas/OpenRCsimulator/blob/381d4215b590d09692a090df0fd0fdd43d3a85ba/docs/plans/optional-ray-tracing.md#L779-L783
[G-geometry]: https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/servers/rendering/rendering_device.h#L1373-L1382
[G-blas]: https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/servers/rendering/rendering_device.cpp#L351-L418
[G-address]: https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/drivers/vulkan/rendering_device_driver_vulkan.cpp#L6378-L6393
[G-vulkan]: https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/drivers/vulkan/rendering_device_driver_vulkan.cpp
[G-forward]: https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/servers/rendering/renderer_rd/forward_clustered/render_forward_clustered.cpp
[G-prepass]: https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/servers/rendering/renderer_rd/forward_clustered/render_forward_clustered.cpp#L2219-L2238
[G-resolve]: https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/servers/rendering/renderer_rd/shaders/effects/resolve.glsl#L53-L115
[G-hash]: https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/servers/rendering/renderer_rd/shaders/scene_forward_aa_inc.glsl#L12-L41
[G-sun]: https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/servers/rendering/renderer_rd/storage_rd/light_storage.cpp#L804-L825
[G-pcss]: https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/servers/rendering/renderer_rd/shaders/forward_clustered/scene_forward_clustered.glsl#L2437-L2453
[G-layer]: https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/servers/rendering/renderer_scene_cull.cpp#L2948-L2954
[G-caster]: https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/servers/rendering/renderer_scene_cull.cpp#L3267-L3277
[G-receiver]: https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/servers/rendering/renderer_rd/shaders/forward_clustered/scene_forward_clustered.glsl#L2414-L2421
[F-class]: https://github.com/GPUOpen-LibrariesAndSDKs/FidelityFX-SDK/blob/c6efa6bf7f2027b3ec94f28578bb5965eabb9e55/sdk/include/FidelityFX/gpu/denoiser/ffx_denoiser_shadows_tileclassification.h#L96-L134
[F-moments]: https://github.com/GPUOpen-LibrariesAndSDKs/FidelityFX-SDK/blob/c6efa6bf7f2027b3ec94f28578bb5965eabb9e55/sdk/include/FidelityFX/gpu/denoiser/ffx_denoiser_shadows_tileclassification.h#L368-L427
[O-alpha]: https://github.com/bultodepapas/OpenRCsimulator/blob/e0a733937e255bacfe95ff09db0fb3838697239f/app/scenery/imported_tree_wind.gdshaderinc#L116-L152
[O-vegetation]: https://github.com/bultodepapas/OpenRCsimulator/blob/e0a733937e255bacfe95ff09db0fb3838697239f/app/scenery/imported_vegetation.gd#L219-L239
[O-guard]: https://github.com/bultodepapas/OpenRCsimulator/blob/e0a733937e255bacfe95ff09db0fb3838697239f/app/app_state/renderer_guard.gd#L152-L222
[O-policy]: https://github.com/bultodepapas/OpenRCsimulator/blob/e0a733937e255bacfe95ff09db0fb3838697239f/app/render/shadow_settings.gd#L55-L130
[O-vq]: https://github.com/bultodepapas/OpenRCsimulator/blob/e0a733937e255bacfe95ff09db0fb3838697239f/docs/plans/advanced-graphics.md#L317-L333
[V-mask]: https://docs.vulkan.org/refpages/latest/refpages/source/VkAccelerationStructureInstanceKHR.html
[V-build]: https://docs.vulkan.org/spec/latest/chapters/accelstructures.html
