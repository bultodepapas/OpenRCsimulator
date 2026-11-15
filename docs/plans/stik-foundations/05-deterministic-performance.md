# P5 — Smooth flight with a measured performance budget

**Status:** proposed implementation plan; no speedup or hardware qualification is claimed. **Planning baseline:** `6616ec37350bf217b58f598c32ea86c58f611586`, 2026-11-15. **Owners/prefixes:** existing VQ-01c/DT-10 performance and delivery owners, GOD benchmark owners, H/Gate P physics, SF/NK numerical/backend owners, and the actual UI/GP/AUD/FL consumer owner of a measured cost. P5/slice labels are navigation, not a new track. The [global performance plan](../global-performance-visual-quality.md), [optimization priorities](../optimization-priorities.md), [GOD TEST plan](../god-test.md) and [main gates](../../../ROADMAP.md#execution-order-and-release-gates) keep their authority.

## Outcome and reason for selection

The Stik should respond consistently through startup, active flight, contact, reset and return Home on a declared hardware profile. An optimization should improve the complete affected workload while preserving the simulation and visible flying cues. Future physical capabilities should have measured cost before their default promotion.

The repository already has fixed-step simulation, exact replay, diagnostics, headless benchmarks, native work and several accepted optimizations. [R15](../../research/ugly-stik-flight-physics-2026-11-15/research-round-02/investigations/r15-fixed-step-and-replay.md), [R16](../../research/ugly-stik-flight-physics-2026-11-15/research-round-02/investigations/r16-integrator-and-actuator-coupling.md), [R22](../../research/ugly-stik-flight-physics-2026-11-15/research-round-02/investigations/r22-profiling-opportunities.md) and [R24](../../research/ugly-stik-flight-physics-2026-11-15/research-round-02/investigations/r24-benchmark-evidence.md) identify the missing decision evidence. Candidate input allocations, stage temporaries and observer copies are hypotheses. Historical improvements cannot be added together or assumed to apply to the next integration commit.

## Preserve these boundaries

1. Keep accepted simulation ticks, their input sampling and their transactional validation authoritative. Graphics settings and quality presets must not change the aircraft equations or physical tick rate.
2. Separate kernel cost, complete session cost, observer cost, process-frame intervals, GPU timing and actual presentation. Their clocks and overlapping work prohibit adding them into a fictitious serial total. Existing process-loop timing is not input-to-photon latency.
3. Reuse accepted state in presentation without losing touchdown, crash, audio or statistical events. Cadence changes need consumer-specific evidence; a universal observer decimation switch is outside this plan.
4. Bound caches by owner, lifetime and size. Never share mutable RK-stage scratch or reuse state-dependent loads across stages. Any cache must define invalidation on aircraft, source mode, weather, setup failure, reset and restore where applicable.
5. Keep exact replay requirements for changes advertised as numerically unchanged. Reordering arithmetic, changing integration or introducing a new physical law requires a separately labeled numerical/physics candidate and P3 evidence.

## Existing implementation seams

| Boundary | Existing home | Use in this plan |
| --- | --- | --- |
| Session and kernel | `app/main.gd`, `app/sim/flight_session.gd`, `app/sim/simulation.gd` | Identify full input → accepted tick → observer cost. A kernel-only timer excludes surrounding work. |
| Frame/resource observation | `app/render/frame_samples.gd`, `app/render/frame_diagnostics.gd`, `tools/godot/` | Keep bounded measurement streams, identity and channel-availability semantics. |
| App orchestration | `tools/godtest/runner.py`, `analysis.py`, `catalog.py`, existing debug bridge | Extend the existing explicit workload modes; preserve normal Home/loading and process ownership. |
| Profiling and traces | [debug tools](../../../tools/debug/README.md), [checked engine tools](../../../tools/godot/README.md), Perfetto export | Attribute first; use instrumentation-off runs for the final comparison. |
| Numerical comparison | [flight logs](../../FLIGHT-LOGGING.md), [native qualification](../../../research/native-kernel/README.md) | Preserve source guards, replay completeness and native/reference admission. |

The [GOD TEST README](../../../tools/godtest/README.md) explicitly leaves fixed-input rendered replay, repeated paired statistics and automatic promotion pending. Its existing adaptive pilot and sampled trajectory remain useful for their own workload. Extending that tool is preferable to another benchmark harness.

## Research questions and decision experiments

| Question | Competing explanations / alternatives | Decision experiment |
| --- | --- | --- |
| What actually causes poor feel or hitches? | Input conditioning, CPU tick/observer cost, loading, GPU/presentation or thermal drift. | Match accepted configuration and record phase-specific streams. Compare profiled attribution with unprofiled repeats; route genuine input delay to P1. |
| Does an allocation or repeated calculation matter? | Leave it; reuse within the same evaluation; cache immutable preparation. | Locate its contribution first, change one cause and measure both component and full workload. Reject a patch whose benefit vanishes outside the helper. |
| Is a presentation cadence change justified? | Same-cadence exact reuse; consumer-specific frame update. | Prove intervening event delivery and pause/reset/restore semantics, then compare motion/audio/statistics and frame distributions. Prefer reuse when adequate. |
| Is more native work needed? | Optimize an attributed GDScript path; qualify the existing native route; expand native scope. | Use actual accepted backend receipts and target budgets. Do not start another port when the current route meets the required workload. |
| Is an apparent gain repeatable? | Real gain, warmup/cache effect, changed workload or observer perturbation. | Balanced baseline/candidate pairs, frozen eligibility and uncertainty method, raw per-run results, failed/partial runs retained. |

## Incremental delivery

| ID / existing owner | Work and likely files | Proof/status |
| --- | --- | --- |
| A — VQ-01c/DT-10, GOD | Freeze one real 1080p Stik workload and measure the current integration baseline using existing manifests/tools. Verify accepted identity and actual dimensions. Inspect existing GOD comparison eligibility before extending it. | Proposed first slice. Named host/build/backend, complete phase coverage, warmup and observer overhead; no optimization claim. |
| B — GOD/FL/SF | Add a bounded fixed accepted-input/tick-intervention workload to the existing rendered runner where missing, plus paired-run summaries in `tools/godtest/analysis.py`. Reuse `.orfl` semantics and source checks; inspect the actual in-app GOD consumer before assigning edits. | Proposed. Complete source/replay identity, deterministic input schedule, explicit changed-solver status; adaptive and visual-path modes keep their distinct meaning. A feedback pilot is never silently relabeled fixed input. |
| C — H or actual UI/GP/AUD consumer owner | Select one attributed cost: same-evaluation scratch/reuse, immutable preparation, one observer calculation or one loading block. Edit only its proven producer/consumer boundary. | Conditional. Relevant numerical/event/failure checks and old-law replay pass; complete-workload improvement meets the owning acceptance gate; no hidden quality or resource regression. A no-change decision is a valid result. |
| D — VQ/DT/GOD, NK if affected | Repeat on the named target/package, record per-regime budgets and a regression comparison recipe. Requalify native source guards if mirrored code changed. Add required CI coverage only where the environment can actually measure the promised property. | Proposed. Raw pairs, uncertainty, worst affected cases and rollback identity retained. Missing hardware is recorded as unqualified, not a passing synthetic substitute. |

## Workload and acceptance contract

Use Basic, Electric in normal finite-pack mode, and one justified comparison aircraft. Extra can control shared control/wash behavior; P-51 can expose higher shared load; select the one relevant to the patch. Keep explicit ideal-electric experiments separate. Broaden family coverage only when shared boundaries change; it is not a reason to rerun every suite after each edit.

The workload includes Home/Fly loading, a stable airborne segment, defined maneuvers, approach/contact where valid, pause/reset and return Home. The same fixed tape can yield different trajectories under changed physics; record that divergence and do not claim equal rendered workload. Use a separate visual-path experiment if needed for renderer attribution, with no physical-flight claim. Benchmark hosts are reserved serially; no concurrent profiling, native builds or captures contaminate pairs.

| Measure / gate | Acceptance rule |
| --- | --- |
| Resolution and settings | Actual 1920×1080 is primary. Record output/internal dimensions, renderer, preset, camera, VSync/cap, refresh, weather, seed, power/thermal conditions and actual backend. Higher resolutions follow; 720p cannot qualify 1080p. |
| Frame and simulation pacing | Apply the owning DT/VQ targets after freezing the supported profile. The current plan proposes process-loop p95 ≤18 ms, p99 ≤25 ms at 60 Hz and simulation/wall ratio 0.99–1.01; these are targets, not observations or presented-frame claims. Attribute repeatable intervals above 50 ms. |
| Physics headroom | Preserve Gate P's 500 µs per 240 Hz tick target with its per-aircraft/regime measurement. Report full session/observer overhead separately; the kernel budget is not additional observer allowance. |
| Experimental design | Start from the global plan's 10 s warmup, 60 s sample and at least three alternating pairs, extending for periodic/thermal events and observed variability. Predeclare practical effect and uncertainty method. Three pairs are a minimum screen, not automatic statistical proof. |
| Adoption | The owning global plan requires a gain beyond paired variation and 5% of the affected complete workload, or removal of a named reproducible hitch/memory defect. Retain stricter owner gates. A microscopic helper improvement alone does not qualify. |
| Correctness and readability | Relevant replay, event, failure, reset/restore and native/source contracts hold. Visual/observer changes also retain attitude, landing and audio cues in matched motion; frame rate alone is insufficient. |
| Loading and retained resources | Preserve DT loading and soak gates from their canonical home. Inspect cold/warm conditions separately and bounded cache growth. Moving startup work into the first controllable frame is not an improvement. |

These numerical targets are inherited from [the global measurement contract](../global-performance-visual-quality.md#4-measurement-and-acceptance-contract), [desktop delivery](../../DESKTOP-DELIVERY-PLAN.md) and [ROADMAP](../../../ROADMAP.md). Freeze the applicable versions again when implementation starts; do not silently weaken a failed gate. Required release CI and hardware qualification stay with their owners.

## Compatibility, rollback and coordination

Add versioned benchmark manifest/report fields only as needed; preserve old workload meaning and mark missing measurements unavailable. Keep previous raw baselines instead of overwriting them. An implementation rollback restores the old exact path and matched source/native receipts; a cache rollback must also clear prepared state. Do not change defaults based on an instrumentation-only result.

[P2](02-aircraft-identity-and-provenance.md) supplies accepted identity and [P4](04-experiment-and-product-evidence.md) supplies truthful completion/coverage. Existing fields suffice for baseline attribution, so neither complete program blocks A. [P1](01-controls-and-feel.md) owns physical controller latency; [P3](03-validated-flight-model.md) owns changed-law correctness. Their prototypes can proceed independently, but a default physics promotion must include the affected whole-flight cost.

The highest risks are optimizing already-repaired work, mixing observers with the measured load, aliasing state through scratch reuse, changing event delivery, and claiming cross-platform numerical equivalence from one host. This plan does not authorize a kernel rewrite, lowered physical tick rate, reduced validation, renderer migration or an unconditional native dependency.

**First PR ready scope:** define the one matched workload/identity recipe in the existing GOD/VQ homes and close the smallest missing collection/comparison boundary from A/B. Choose runtime edits only after attribution. **Exit:** one measured optimization or an evidence-backed no-change decision, plus a repeatable budget check that the next developer can run on the same declared target.
