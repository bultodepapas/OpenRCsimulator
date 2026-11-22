# Graphics, FPS and native performance audit — 2026-11-21

**Latest follow-up, 22 November:** the [current-main audit](../graphics-audit-2026-11-22/README.md) integrates main `7940a408`, reviews the new tests/stutter map/CI, adds vehicle and menu opportunities, and reproduces a phase-attribution defect. Read its disposition ledger for current status; this document retains the original snapshot below.

**Continued investigation:** the [second-pass report](second-pass.md) adds 16 scoped opportunities, a pinned-engine Nitro audio component measurement, independent cross-review, and a newer-main CI/source cross-check. The original missing-UID preflight failure below remains historical: release preflight passes at the newer `6b2228c…` revision, while broader CI was still running in the retained snapshot. Read the second pass for follow-up status; no production optimization or FPS gain is claimed.

**Repository:** `bultodepapas/OpenRCsimulator` · **Audit branch:** `graphics-audit` · **Application baseline:** [`57abea025f62b20233ca281d58d2acbee4ab8b8e`](https://github.com/bultodepapas/OpenRCsimulator/commit/57abea025f62b20233ca281d58d2acbee4ab8b8e) · **Engine:** official `4.8.beta2.official.cafc17a19`.

This audit finds reproducible automatic-graphics policy problems, recurring CPU work that can limit frame rate, and cold-construction/GPU-transfer paths that deserve targeted stutter measurements. It also finds a qualification gap: the audited main commit's CI fails before the application, graphics and native jobs. The reports separate confirmed behavior, synthetic counterexamples, historical measurements, mathematical bounds and hardware hypotheses. **No FPS improvement or new platform qualification is claimed.**

The most promising native investigation is to reduce work outside the already-native player stage: repeated Nitro source-identity reads, reference-only companion evaluators and accepted-state observers. On GPU-limited machines, sky/water/pass cost and synchronization need separate attribution; a faster C++ physics stage cannot by itself remove them. Current source and later owner decisions supersede several older platform descriptions, especially Mac native admission.

Three specialists followed the repository's subagent guide, then independently challenged each other's findings. The lead inspected source, GitHub run/job logs and a real CI artifact, executed isolated policy checks with the pinned engine, and reproduced analytical cost bounds. This environment had no native display/GPU or configured test-pool access. Windows/Linux/Mac hardware follow-ups are concrete experiments in the validation plan, not silently omitted work.

## Read the reports

| Report | Main question |
| --- | --- |
| [Calibration and measurement](calibration-measurement.md) | Can Automatic reuse a measurement for the wrong workload, or classify incomplete timing as sufficient? |
| [Runtime and native routes](runtime-native.md) | Which per-tick/observer work remains interpreted, repeated or outside the headline meter? |
| [Rendering and landscape](rendering.md) | Which construction, resource, transfer and shader paths may cause hitches or sustained GPU cost? |
| [Native priorities](native-priorities.md) | What should use existing native/built-in seams first, and what requires a larger contract change? |
| [GitHub and CI evidence](ci-evidence.md) | What actually passed, failed or was skipped at each source identity? |
| [Cost models](cost-models.md) | What follows mathematically from clocks, buffers, cadence and workload sizes? |
| [Platform validation](platform-validation.md) | Which devices, routes, metrics and correctness checks resolve the open questions? |
| [Review and validation](review-and-validation.md) | What was executed, what failed, and which reviewer objections changed the conclusions? |
| [Primary sources](sources.md) | Which engine/vendor/project sources support the mechanisms and their limits? |

Reproduction scripts live under [`research/performance/graphics-audit-2026-11-21`](../../../research/performance/graphics-audit-2026-11-21/README.md). Retained data: [policy receipts](policy-checks.json), [CI inventory/excerpts](ci-evidence.json), [native CPU artifact extract](native-ci-specimen.json), and [arithmetic](cost-models.json).

## Strongest conclusions

### 1. Automatic graphics has residual workload-identity defects

The pinned-engine probe confirms that a stored High rejection can remain active after AA or internal-resolution changes, even when the workload matcher correctly says that the old record is incompatible. Once Automatic starts Standard, its separate renderer slot does not overwrite the High veto. AA-only is a reachable Standard settings path; reconstruction controls and restart timing impose the qualifications explained in C2. Explicit High and restoring defaults remain escape routes.

Native at scale 1 with MSAA off and FSR2 Native AA also produce identical stored workload fields despite different reconstruction modes. The probe confirms the dictionary collision and suppressed remeasurement; it does not run either GPU algorithm. Independently, the source allows a calibration to retain samples across pause/settings changes and label the combined set with only its final workload. These are the first policy repairs to specify and test, not grounds to force High on every device. See [C1–C3](calibration-measurement.md).

### 2. A native player does not mean the complete flight is native or cheap

Companion sessions default to the reference evaluator and advance serially after the player step. The common planning snapshot is inside `step_usec`; the later prepare/advance is outside it. Contact/statistics/audio observers add further work, and `step_usec` is smoothed. A small displayed value can coexist with an expensive full callback. Expanding individual native admission is a plausible experiment, but track/spawn/platform refusal and fleet ordering must be preserved. Cross-agent RK4 batching would require a larger coordination design. See [N2/N3/N4/N6](runtime-native.md) and [native priorities](native-priorities.md).

The Nitro ground vehicle additionally rereads and compares two artifact files for identity checks at its callback cadence, even when a cached digest exists. Current source sizes imply up to 480 logical opens and 29,866,560 logical bytes read per second at 240 successful checks/s. That is not physical disk bandwidth or a measured current frame cost. RCV-41 already optimized this deliberate guard, so the next proposal must preserve live-mutation/checkpoint refusal rather than add an unsafe filename cache. See [N1](runtime-native.md#n1-nitro-vehicle-performs-artifact-reads-on-every-240-hz-callback).

### 3. Cold construction and synchronization need tail-focused measurements

Staged loading yields between units, but a whole lake cut, meadow phase or shadow preparation can still occupy an indivisible main-thread unit. Low meadow builds/scans the full candidate set before density selection; only capped-species entries are sorted. Projected shadows are prepared before an Off/Native policy disables their output. An existing meadow switched Off remains allocated for possible reuse. These are confirmed code paths with lifecycle tradeoffs, not measured leaks or guaranteed expensive stalls. See [R1–R4](rendering.md).

Cold/new-seed cloud publication reads a 2048² viewport texture back to an Image, validates it, converts it and creates an ImageTexture. A cache hit and ordinary drift are different paths; the readback is not periodic steady-flight work. Four ready RGH tiles would hold 64 MiB of logical base texels, excluding transients and real driver allocation. Hardware traces must determine whether readback, conversion, upload or other construction causes a visible hitch. See [R5](rendering.md#r5-cloud-tile-publication-performs-a-gpu-readback-and-cpu-conversion-on-a-completion-frame).

### 4. The measurement can itself perturb the workload

The optional frame stream synchronously serializes, writes, flushes and hashes each 512-sample chunk. At 60 retained process samples/s this happens about every 8.53 seconds; at 144, every 3.56 seconds. Its small `observer_poll_usec` span does not include that work. A causal hitch claim needs alignment and on/off controls. Root GPU polls also lack fresh-completion identity and complete secondary-viewport coverage. Process intervals, GPU work and display presentation remain separate metrics. See [N7](runtime-native.md#n7-the-diagnostic-stream-can-generate-periodic-hitches), [C4/C5](calibration-measurement.md) and [cost models](cost-models.md).

### 5. CI is valuable, but its current scope is narrower than FPS qualification

The audited main [run 44833680915](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/44833680915) failed on thirteen absent tracked UID sidecars; graphics/native/app jobs were skipped. The prior successful [44747723262](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/44747723262) belongs to a different SHA. Its visual job used llvmpipe. Its downloaded Linux-native artifact contains one 0.1 s warmup/1.0 s sample pair per case, with actual native calls and lower callback means, but no rendered FPS or full-app observer scope. That is useful smoke evidence, not current hardware acceptance. See [CI evidence](ci-evidence.md).

## Finding register

Priority indicates investigation/decision value, not a measured speed ranking. **P0** blocks trustworthy current-source qualification; **P1** should be resolved or attributed first; **P2** is a bounded optimization/clarity experiment. IDs are local to this dated audit, not new project tracks. Performance work remains under existing PT/VQ/NK/AFC/RCV owners.

| ID | Finding | Evidence class | Priority / next decision |
| --- | --- | --- | --- |
| E1 | Current core CI stops on 13 missing UID sidecars | CI log + local reproduction | P0: restore source gate and rerun current identity |
| C1 | Calibration can combine pre/post-settings samples | Confirmed reachable source path | P1: invalidate/restart on material effective-workload change |
| C2 | High veto survives incompatible AA/internal size | Reproduced synthetic policy | P1: compare intended High workload and guarded retry policy |
| C3 | Native/FSR2 Native AA share calibration identity | Reproduced synthetic policy | P1: persist bounded effective-provider identity |
| C4 | Positive root GPU polls do not prove fresh whole frames | Confirmed measurement boundary | P1: scope/quality state plus platform corroboration |
| C5 | Automatic's 60 Hz floor does not qualify higher refresh | Intentional policy + arithmetic | Owner decision: explicit pacing target |
| C6 | Settings formatter can show raw heuristic over planned mode | Source + pure formatter witness | P2: distinguish recommendation, plan, active mode and prior record |
| N1 | Nitro guard rereads complete artifact bytes | Confirmed source + arithmetic; older measurement | P1: current attribution, stronger immutable identity contract |
| N2 | Companion sessions remain reference; post-step work is serial | Confirmed source | P1: per-agent native admission experiment, exact ordering |
| N3 | Accepted-state contact work is repeated by observers | Confirmed source | P1: profile and share only identical accepted-state results |
| N4 | Audio separately samples wind and spatial air | Confirmed source | P2: existing helper parity experiment |
| N6 | `step_usec` excludes later observers and smooths spikes | Confirmed source + arithmetic | P1: complete callback/tail attribution |
| N7 | Diagnostic chunk flush can induce its own spikes | Confirmed mechanism; impact unmeasured | P1: on/off alignment, bounded writer if material |
| N8 | 240 Hz / 12-step cap implies a 20-engine-fps real-time threshold | Analytical constraint | Measure sim/wall; preserve the physics contract |
| R1 | On-built meadow remains allocated after Off | Confirmed lifetime, no leak proven | P2: committed-disable resource accounting |
| R2 | Low meadow still generates/scans High candidate universe | Confirmed construction | P2: compact two-pass representation with exact membership |
| R3/N5 | Staging cannot interrupt an oversized construction unit | Confirmed structural risk; historical stalls only | P1: cold/warm stage attribution then split one unit |
| R4 | Projected shadow preparation precedes effective Off/Native policy | Confirmed, known F35 continuation | P2: lazy preparation versus live-toggle contract |
| R5 | Cloud miss publication performs GPU→CPU→GPU transfer | Confirmed path; device cost unmeasured | P1: trace cold/seed changes and validate alternative publication |
| R6 | Full-resolution layered sky/relief may be GPU-heavy | Source-backed GPU hypothesis | P2: pass attribution then built-in lower-resolution experiment |
| R7 | Water screen/depth dependencies may add copy/resolve cost | Source-backed GPU hypothesis, known F32 | P2: compiled cheap variant only if it removes real work |
| R8 | Fallback grass collapse occurs after batch vertex submission | Source-backed GPU hypothesis, known F30 | P2: culling/batch tradeoff on affected route |
| R9 | High bundles SSAO/sky reflection choices | Confirmed control limitation | P2: independent controls only after isolated cost/visual evidence |
| R10 | Opt-in planar reflection adds a second active viewport | Confirmed optional route | P2: full-frame cost and bounded resolution/cadence |
| E2/E3 | Prior CI software visuals and short CPU smoke do not qualify current FPS | Retrieved artifacts and logs | P1: source-bound physical-host lane and metric semantics |
| V1 | Existing calibration test leaks a test-owned Node | Strict runner failure + source | P2: separate test cleanup; no production leak inferred |

## What was ruled out or deliberately qualified

The old cloud-cache slot-eviction cascade and exact-zero sky-opacity work are already repaired. Output/internal/MSAA matching and secondary-viewport tracking also have existing repairs; this report identifies narrower residual cases. Planner cadence is already reduced, and several visual/audio consumers already use accepted-frame deferral. Loading already has threads/staging/caches; there is no justification for rebuilding that framework without attributing the remaining unit. Graphics quality does not demonstrably change the current physical collider inventory merely because an old comment says so.

Hidden resources do not prove continued drawing, cached positive GPU readings do not prove staleness, and a 60 Hz policy is not a broken promise of 120 Hz. Current Mac source admission differs from public-package qualification. These distinctions materially changed the review and prevent obsolete or exaggerated findings from entering the work queue.

## Recommended execution sequence

1. **Repair the evidence baseline.** Resolve the owning UID change and the existing test-owned Node cleanup; obtain exact-source required jobs. Keep historical and new results separately identified.
2. **Correct measurement identity.** Implement specified C1–C3 behavior with focused regression cases, clarify scope/target, and establish full-callback plus presentation-aware baselines on representative hosts.
3. **Measure the recurring CPU candidates.** Start with Nitro identity cost, 0–3 companions and accepted-state observers. Use existing native seams and helpers; prove exact refusal, ordering, replay/checkpoint and fallback behavior.
4. **Measure cold and GPU paths.** Attribute loading units and cloud publication, then sky/water/grass/independent effects on the constrained devices. Prefer existing engine/native operations; retain visual and physical invariants.
5. **Qualify the complete result.** Repeat physical-display Windows/Linux 1080p and native-panel Apple Silicon tests, then higher resolutions, Intel Mac/fallback and sustained cases as appropriate. Retain failures, paired variation and instrumentation controls.

The final isolated probe has **24/24 assertions and zero engine warnings**. The unchanged calibration regression has **94/94 assertions but one cleanup warning**, so its strict gate remains failed. Production preflight remains failed at the audited baseline, and there is no new rendered/hardware result. These are the audit's actual verification outcomes, preserved in [review and validation](review-and-validation.md).
