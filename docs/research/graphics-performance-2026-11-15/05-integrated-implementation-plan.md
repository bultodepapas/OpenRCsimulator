# Integrated implementation work order

2026-11-15 · Advisory plan against `e488ef7653e8dd0f0a2e7db18e396bb4da0aaccc`, strengthened after the user's request for bounded measurement work and 20 implementation investigations. Read the [source findings](01-repository-audit.md), [dynamic-resolution study](02-dynamic-resolution-and-upscaling.md), [latency study](03-latency-reflex-and-boost.md), [RT study](04-ray-tracing-in-godot.md), and [20 external investigations](08-twenty-external-investigations.md). This is a proposed execution contract under existing owners, not a claim that implementation or hardware qualification has happened.

## Product goal and decisions

Offer graphics options that improve real flight smoothness while keeping small aircraft readable and control response predictable. The primary qualification target is 1920 × 1080 at a 60 Hz profile, then higher resolutions, then 720p fallback. Rendering must not change the fixed simulation law, aircraft data, input ownership or recorder. A successful result may be retaining the baseline when a feature fails its cost, clarity or latency test.

Recommended order:

1. Establish the available trustworthy baseline on one current export, repair the timing-owner conflict and document exact build capabilities. Record missing GPU/latency evidence; require fresh GPU association for DRS and physical evidence for physical-latency claims, without blocking unrelated fixed-provider work.
2. Qualify and improve existing fixed reconstruction modes and their history/failure behavior. Attribute repeated settings reconfiguration before attempting an adaptive loop.
3. Prototype dynamic resolution only for a demonstrated pixel-sensitive GPU bottleneck, with a tested internal-resolution floor and one policy owner.
4. Finish latency qualification of the existing Reflex path in parallel once the shared baseline is ready. Add AMD/Linux integrations only when API feasibility and measured need justify them.
5. Spend proven headroom on one optional RT experiment. Keep the Apple producer/denoiser effort in its current DT-MAC plan.
6. Qualify specific exported platform/provider combinations and then expose those combinations as supported. Frame generation retains its separate work and gates.

## Reviewable deliveries

These are proposed slices inside existing track IDs, not new registered step IDs. The acceptance plan is in [06](06-validation-and-benchmark-plan.md).

| Order / owning track | Concrete change | Dependencies and exit decision |
| --- | --- | --- |
| 1 · PT / VQ-01c / VQ-07c | One reference-counted owner for per-viewport GPU measurement; fresh sample identity/age where obtainable; root versus auxiliary rendering, CPU/physics and cap/presentation state; source/engine/package identity in receipts. Reuse `frame_diagnostics.gd`, `debug/render_probe.gd`, existing collectors and checked runners. | Prove concurrent consumers cannot switch one another off. Reject stale/zero/unavailable timing, observe probe overhead on a named GPU, and distinguish CPU-limited from pixel-sensitive GPU-limited scenes. If reliable timing is unavailable, that path remains static. |
| 2 · VQ-07d / FSR completion / DT-MAC / GDU | Finish provider execution, history-reset, failure and dimension evidence; examine the multiple configuration calls in one settings apply. Measure Native, 85% and existing Quality modes before a controller. | Each candidate has a known backend and safe fallback. Validated rendering and history transitions plus moving-aircraft acceptance; investigate atomic configuration/persistent resources only if measurement shows the current lifecycle misses the gate. |
| 3 · VQ-07d / UI / PT | Add a presentation-only deterministic DRS policy, initially off, through the existing reconstruction owner. Separate user request, maximum/floor, target and effective scale; give every suspended state a reason. | Requires orders 1–2 and a measured need. Pass synthetic policy cases and native transitions. Publish a retain-static decision if complete frame behavior or readability fails. |
| 4 · VQ-07h / F6 / DT / GDU | Complete Reflex flash/marker verification and paired Off/On/Boost measurements on the existing fork. Verify exported artifacts and normal player presentation settings. | Functional SDK calls already exist; measure physical RC response separately from PCL/mouse metrics. Only the within-fork mode comparison isolates Reflex. Keep On's existing supported request policy; keep Boost an explicit choice. |
| 5 · VQ-07h / GDU / DT-LNX | Investigate AMD Vulkan Anti-Lag and native Vulkan latency extension routes on specifically named devices; compare a simple cap/VSync configuration first. | No assumption that FSR enables Anti-Lag, a Windows DLL works on Linux, or extension documentation proves driver support. Native lifetime/frame-attribution feasibility precedes implementation. One active pacer per frame. |
| 6 · VQ-04b / VQ-07 / GDU; DT-MAC-13d separately | Prototype bounded directional-sun visibility with a controlled opaque fixture, then exact-once direct-light integration and relevant scene coverage. Reuse upstream RD and the existing Apple lessons. | Requires a pilot-visible defect and measured headroom. Validate both device capabilities and the pinned SBT/AS route. Keep Off if material/deformation coverage, history, memory or full-frame pacing fails. |
| 7 · DT / VQ-07g / DT-MAC / DT-LNX | Package only accepted combinations, with exact editor/template/SDK hashes and matched import data. Extend named-device/lifecycle coverage and player diagnostics. | Unsupported combinations explain why and restore safe static/raster behavior. Software checks, actual SDK execution, visual acceptance, physical latency and release qualification are reported separately. |

These slices are organized into the bounded milestones below. Reflex measurements can run after the shared baseline, without waiting for DRS, but not concurrently with another workload on the same measurement host. New SDK/engine upgrades are independent changes with their own controls; do not combine a provider upgrade, a new DRS controller and a renderer migration in one performance comparison.

## Outcomes, targets and non-goals

The numerical criteria below inherit the [owning acceptance contract](../../plans/advanced-graphics.md#experiment-contract-and-decision-rules) unless explicitly marked as a proposed experiment parameter. They describe expected outcomes, not measured improvements from this audit.

| Objective | Measurable target / protected behavior | Evidence that closes it |
| --- | --- | --- |
| Smoother active flight | Primary 1080p/60 profile: process-loop p95 ≤18 ms, p99 ≤25 ms; simulation/wall ratio 0.99–1.01; recurring >50 ms gameplay intervals attributed. These gates do not guarantee every 16.667 ms refresh. | Matched native complete-workload runs and active-flight/pilot acceptance on the named package/device. |
| Worthwhile optimization | At least the existing 5% gain in the **predeclared complete-workload metric**, exceeding paired-run variation, or removal of a named reproducible hitch/memory defect. | Comparison with both the frozen delivery baseline and latest accepted control. A faster isolated dispatch is attribution only. |
| Useful dynamic resolution | Adapt only where fixed reconstruction misses a declared target because of pixel-sensitive GPU work; improve the chosen complete-workload metric or remove the named recurring miss, with no new attitude-readability loss. | Native versus best eligible fixed mode versus adaptive mode; scale events, floor time, tails and pilot clips. Reaching the floor without reaching the target is reported as a miss. |
| Honest low-latency option | Establish whether Off/On/Boost changes RC response on the chosen transport/display. Declare the smallest useful difference and measurement uncertainty before collection. | Within-build paired mode results, valid SDK integration, physical RC endpoint and thermal/power evidence. No universal millisecond promise. |
| Useful optional RT | Reduce one predeclared sun-shadow defect in the pilot view while preserving the whole-profile budget and complete relevant coverage. | Integrated direct-sun result, moving-scene correctness, matched pilot views and full-frame cost. A ray-hit fixture is an intermediate check. |
| Finite measurement investment | M0 closes after at most five engineering days of instrumentation/initial attribution on one reference configuration; later additions have a named decision and separate one-day review limit. | A repaired existing path and a proceed/static-only/defer decision, followed by a product implementation or explicit retained baseline. |

This program does not build a benchmark application, dashboard, telemetry service, universal profiler, per-vendor collector framework, new physics recorder or new flight replay system. Existing command entrypoints and evidence homes remain the default. The twenty research records are decision inputs; they are not twenty integrations to implement.

## Milestones and decisions

M0–M5 are labels local to this audit, mapped to existing track IDs. All are **proposed / not executed by this audit**. One person can own several roles; an unavailable device is recorded as a dependency, not silently replaced with software rendering.

| Milestone / owner | Deliverable visible to the next engineer or player | Review limit / exit |
| --- | --- | --- |
| **M0 · Measurement repair** · PT / VQ-01c / VQ-07c | Shared timing ownership, explicit sample validity, one reusable native baseline and one selected implementation question. | **Five engineering days maximum total**, with the earlier owning-plan reviews preserved. Close proceed, static-only, or blocked/defer; no automatic instrumentation extension. |
| **M1 · Improve one existing fixed provider** · VQ-07d / FSR / DT-MAC / GDU | One user-visible correction: honest effective provider/fallback, correct history transition, or demonstrated reduction in avoidable settings reconfiguration. | Half-day initial screen and two-day candidate review. Indicative remaining implementation: 4–10 days for the first engine family if justified. Deliver the correction or retain the fixed control with evidence. |
| **M2 · Conditional DRS** · VQ-07d / UI / PT | An initially-off adaptive option, a deterministic controller, preserved user ceiling, bounded integer input sizes, and a useful fallback reason. | Admit only after M0/M1 prove need, timing and legal transitions. Review after two days; estimated 3–5 policy/UI days plus 3–6 initial native qualification days for one family. Close supported-for-row, experimental, or retain static. |
| **M3 · Existing Reflex completion** · VQ-07h / F6 / DT / GDU | Qualified Off/On/Boost behavior and a candid RC-response result on one NVIDIA package/transport/display. | Runs independently of M2 after its relevant baseline. Review setup/marker/flash feasibility within two days; 1–3 weeks is an initial total estimate with hardware available. Missing optical hardware leaves the physical claim open and does not hold M1. |
| **M4 · One optional RT effect** · VQ-04b / VQ-07 / GDU; DT-MAC separately | One bounded directional-sun visibility result, followed only if useful by correct moving-flight integration. | Two-day capability/scene-access decision; two-week visible-result checkpoint within the prior 2–4-week fixture estimate. Stop if no credible pilot benefit/headroom. Full scene integration remains a separate 6–12+ week estimate, never an automatic continuation. |
| **M5 · Exact package qualification** · VQ-07g / DT / DT-MAC / DT-LNX | A reproducible package for each accepted row, usable controls, Keep/Revert and safe unavailable/failure behavior. | Estimate only for the accepted rows. Run required exports, affected combined cases, owner cycles/soak and pilot checks; no support claim from an editor or isolated fixture. |

The dependency graph is M0 → M1 → conditional M2; M0 → M3 independently; M4 requires a named visual gap and measured headroom, not completion of every vendor integration. M5 can qualify one finished feature while the others remain experimental. Hardware comparisons on one host remain serialized.

The [canonical early review limits](../../plans/advanced-graphics.md#8-first-work-packages-and-stopping-rules) still apply: one-day triage, two-day repair/cost review, three-day renderer-parity review, half-day feature screen and two-day finalist review. VQ-07a/b/c prerequisites still gate the acceptance they own. The larger estimates above are possible total effort after those decisions, not permission to postpone the first decision. Hardware/pilot waiting and engine implementation are reported separately from measurement engineering time.

## M0 — Bounded measurement repair

**Purpose:** make existing evidence trustworthy enough to select and verify the first graphics change. Completion does not require a perfect profiler, every GPU vendor, physical latency setup or every rendering pass instrumented. It also does not certify a feature whose required evidence is missing.

### Fixed work budget and file boundaries

The day allocations are proposed ceilings for one experienced engineer on the first available reference host, totaling five days. Reduce scope when a prerequisite is unavailable; do not convert a limit into a promise to pass.

| Work package | Existing code/tools to strengthen | Bounded change and acceptance | Ceiling |
| --- | --- | --- | --- |
| Freeze and reproduce | [Native collectors](../../../research/performance/README.md), [checked runner](../../../tools/godot/README.md), [graphics launch/package tools](../../../tools/graphics/README.md) | Freeze one source/engine/package/profile; use a matching retained 1080p active-flight control plus an unchanged repeat, or two unchanged runs if no matching control exists. Identify the primary question. Use the current host inventory, not a new hardware-discovery tool. | 0.5 day |
| Fix timing ownership | [`frame_diagnostics.gd`](../../../app/render/frame_diagnostics.gd), [`render_probe.gd`](../../../app/debug/render_probe.gd), their existing tests | One viewport-lifetime-aware lease owner; both acquisition/stop orders, repeated release, two viewports and freed/replaced viewport covered. Last consumer disables measurement; another consumer cannot disable it early. A small internal helper is allowed if it is the single owner, not a new executable/tool. | 1.5 days |
| Make samples truthful | Same consumers; [`frame_diagnose.py`](../../../research/performance/frame_diagnose.py), [`native_summary.py`](../../../research/performance/native_summary.py), existing tests | Add compatible validity/scope/generation fields; preserve old report reading. Distinguish poll sequence from completed GPU sample identity. Missing identity stays unverified; no fake completion timestamps, stale-sample reuse or blocking waits. | 1 day |
| Run one discriminating comparison | Existing `--frametimes` / `--frame-diagnostics`, debug `render`/`ablate`, external tool only if useful | Native and one eligible fixed mode under the same active-flight workload, plus a CPU/cap control where needed. Record instrumentation overhead separately. Identify pixel-sensitive GPU cost, another bottleneck, or inconclusive attribution. | 1 day |
| Close and hand off | Existing owning-step evidence and report reducer | One receipt, paired results, supported claims/missing fields, selected M1 or M3 change, and DRS admission verdict. Record total measurement effort. No new report generator or dashboard. | 1 day |

**Minimum sample contract.** Keep one versioned record in the existing reporting path: run/build identity; viewport/configuration generation; process sequence/time; raw render CPU/GPU value; validity and scope; requested/effective provider and integer dimensions where observed; cap/VSync state; scale/change reason when applicable. Completed GPU sample/render ID and age are nullable unless actually supplied and associated by the backend. Poll time, a changing floating-point value and an application frame counter cannot manufacture that association. Auxiliary viewport inclusion needs a fresh-draw claim, not just an enabled update mode. Older receipts remain explicitly limited.

**DRS eligibility is stricter than M0 completion.** A reliable native control and ownership repair can close M0 even if current GPU freshness cannot be established. That row remains static-only; useful fixed-provider repair and Reflex work continue. If a backend can supply the association through a small existing API/patch, use it within the cap. A new engine telemetry subsystem is deferred as a separate dependency, with its cost and smallest missing interface named.

**Overhead control.** Compare existing ordinary frame collection with the added diagnostic mode in matched runs. Proposed screening ceiling: no repeatable added process-loop p95 cost above **0.2 ms**, with paired variation reported; this is an instrumentation budget, not an observed result. Expensive scene census, allocation inventory and trace/capture stay outside timed flight or use existing bounded sampling. If the overhead cannot be bounded, keep intrusive diagnosis off during acceptance runs and do not use an unqualified always-on sample path for DRS. Do not add synchronous GPU fences to make this test pass.

### Required closure, not another measurement sprint

At the limit record exactly one outcome for the first row:

1. **Proceed:** measurement ownership and required timing contract pass; select one M1 correction and, only if warranted, admit M2.
2. **Proceed with static-only scope:** the baseline is usable for fixed comparisons but DRS feedback is unverified/unavailable; implement or qualify the existing fixed option and continue M3 independently.
3. **Blocked/defer:** no trustworthy baseline or a correctness defect prevents the intended claim; identify the exact blocker and keep the affected feature unqualified. Work may continue on a different independent, already bounded correction.

For M0 to close as repaired, the ownership/error contracts must actually pass; the deadline alone cannot close them. If they do not, publish blocked/defer with the smallest failing case. The next delivery is a product change or an explicit retained baseline. A more elaborate graph, extra counter, additional host sweep or new collector is not a substitute.

After M0, permit **at most one engineering day of new feature-specific attribution before review**, only for a written question that changes a decision and cannot be answered by the existing tools. Prefer an existing profiler such as [PresentMon](investigations/R13-presentmon-existing-capture.md) or [Tracy](investigations/R14-tracy-bounded-attribution.md). Reopen a measurement task only when a changed input, concrete failure or new backend requirement demands it. A second unresolved extension of the same question closes the candidate as experimental/deferred until that dependency materially changes. Required correctness evidence is preserved; it is the feature's scope/status that changes.

## Implementation handoffs after M0

### M1 — Fixed reconstruction first

Choose one current provider on one engine family. Record the actual dispatch/fallback and input/output size, exercise one camera cut and settings restore, then measure one scale transition. If multiple settings writes cause avoidable configuration work, correct that transaction under the existing reconstruction owner and verify idempotent reapply. Do not implement a persistent maximum-sized buffer architecture before proving the existing lifecycle misses the gate.

Expected delivery: an exportable correction with moving-aircraft evidence, or an explicit finding that the current fixed mode already meets the declared goal. Study [R01](investigations/R01-godot-dynamic-scaling.md) and [R07](investigations/R07-vulkan-render-target-sizing.md) separate Godot's real reconfiguration behavior from the attractive but nontrivial maximum-allocation pattern.

### M2 — Adapt only the rendering workload

Implement the presentation-only policy through [`reconstruction.gd`](../../../app/render/reconstruction.gd), with one writer and Off as the initial state. Start with the proposed 0.85–1.0 per-axis range at 1080p only where the chosen provider admits it and pilot evidence supports it. Preserve the user's lower fixed ceiling; an empty allowed range rejects adaptation instead of silently changing the requested quality. Quantize to meaningful integer input sizes, use bounded changes/deadband/dwell, and suspend on invalid/stale timing, loading, minimized state or a pending generation reset.

Before subrectangle/persistent-allocation work, verify each provider's active extents, motion/depth alignment, jitter and history contract. The [DLSS study](investigations/R04-nvidia-dlss-dynamic-input.md) identifies why tagging a whole fixed texture does not prove dynamic subrectangle support. [Unity](investigations/R02-unity-dynamic-resolution.md), [AMD](investigations/R03-amd-fsr-integration.md), [Apple](investigations/R05-apple-metalfx-dynamic-input.md) and [Intel](investigations/R06-intel-xess-dynamic-input.md) supply patterns and limits, not drop-in Godot implementations.

Expected delivery: one accepted adaptive row or a documented retain-static decision. Use exactly three initial configurations: Native, the best eligible fixed reconstruction control, and adaptive reconstruction. Screen first; expand only the passing candidate through [06](06-validation-and-benchmark-plan.md). Do not begin with every provider on every operating system.

### M3 — Finish the existing latency path

Use the existing Windows NVIDIA fork first: check token/marker/Sleep ordering and compare Off/On/Boost in the same exported build. Complete the exact SDK flash/vendor verification where available; a missing flash path remains an SDK-qualification gap but does not block a valid comparison using the existing F6 optical patch or ordinary player settings. Run physical RC and software/PCL observations as different endpoints. A CPU-limited result can still justify a latency experiment even when it rejects DRS. Stop after the predeclared comparison and at most one repeat for identified uncertainty; retain an inconclusive verdict instead of sampling until one mode wins.

The descriptive F6 comparison reports the measured physical difference and uncertainty even if it is small. A mode recommendation uses the predeclared useful-effect threshold and no-regression guards; it is not automatically an accepted VQ complete-workload optimization. That formal claim still needs the owning 5% criterion or a named reproducible defect correction unless the owner explicitly revises its gate.

Expected delivery: supported capability/controls and a named-host mode recommendation, including power/thermal tradeoffs, or an explicit unresolved physical-latency claim. [R08–R12](08-twenty-external-investigations.md#latency-and-scheduling--r08r12) distinguish this work from optional AMD, Intel and Linux feasibility studies. Those studies do not become mandatory integrations or block NVIDIA completion.

### M4 — One useful ray-traced result, then a separate continuation decision

Choose a reproducible pilot-visible sun-shadow defect before coding. In two days, decide whether the exact backend exposes the required query/AS route, scene geometry and direct-light insertion point. If not, retain raster. If yes and measured headroom exists, target one correct visible opaque-scope result by the two-week checkpoint, retaining the earlier estimate of 2–4 weeks for a controlled fixture. Do not spend that period on a general scene exporter, new benchmark renderer or denoiser platform.

The first result must apply visibility exactly once to an isolated direct-sun term and show why the feature matters, its cost and missing coverage; multiplying final shaded color is not a valid early result. Normal-flight adoption additionally requires current moving geometry, material/alpha handling, synchronization, production-lighting integration, settings/fallback and package evidence. The proposed ceilings of **2.0 ms additional GPU p95 and 128 MiB incremental peak allocated GPU resources** cover the entire effect, including composite, acceleration structures, scratch, history, denoise, in-flight duplication and SDK-private allocations where observable. Unobservable allocations are a measurement limit, not zero cost; allocated resources are not process RAM or physical residency. These are experiment ceilings on one named device; tighter measured whole-profile headroom and the existing Compatibility budget win. A partial scene uses its controlled fixture only; the normal player viewport keeps complete raster fallback.

Expected delivery: one bounded visual result or a stop decision, followed by a separately justified scene-integration scope only if useful. The 6–12+ week scene estimate remains visible so a successful triangle test cannot disguise the remaining work. [R16–R20](08-twenty-external-investigations.md#ray-tracing--r16r20) identify reusable examples, blocking initialization patterns, alpha limitations and fork maintenance risk.

### M5 — Ship only the rows that passed

Combine the accepted options in the exact export/template/SDK package, rerun affected integration and lifecycle cases, and preserve saved settings and safe recovery. Start with 1080p and one named platform/provider; expand to another qualified row, then higher resolutions, with 720p last. Freeze package identity and record accepted, experimental and unavailable states separately. A feature can remain optional/experimental while a useful fixed-provider correction ships through the existing owners' release process.

## Proposed settings and runtime contract

Retain the existing requested-versus-effective distinction and the current Keep/Revert recovery flow. A compatible menu can expose the following after qualification; a proposed control is not a current UI claim.

| Control | Proposed behavior |
| --- | --- |
| 3D reconstruction | Keep Native, FSR, DLSS or MetalFX entries that the current engine/device admits. Show the effective provider and fallback reason when verified; use unknown/unconfirmed when execution is not established. Auto continues to mean automatic provider/size policy unless explicitly redesigned and renamed. |
| Dynamic resolution | Separate Off/On control. Off preserves current fixed behavior. On requires a valid target and an eligible provider; unavailable timing, unsupported transitions or an invalid user/provider/readability range keeps the fixed choice with a reason. |
| Target frame rate | Target **real** rendered frames, independent of generated output cadence. An unlimited frame cap is not a numeric DRS budget. Clarify any relationship with the existing cap and monitor refresh; do not silently stack limiters. |
| Quality floor and ceiling | Initially propose a tested 0.85–1.0 input/output range for the 1080p prototype where the selected provider admits it. This is an experiment, not a tuned default. Preserve the user's fixed-mode ceiling; if its scale is below the approved floor, explain why adaptive operation is unavailable instead of silently changing quality. Higher-output floors require separate readability evidence. |
| Latency | Keep Off selectable. Enable NVIDIA On/On + Boost only where the SDK proves support; preserve unsupported saved requests as visible but disabled choices and show requested versus accepted states. Keep portable cap/VSync controls separate. Introduce an AMD-specific option only when its actual integration exists. |
| Ray-traced shadows | A later optional experimental control, initially Off, after an actual integrated effect exists. Explain unavailable backend/device/rejected scene/failure. No inactive acceleration structures, per-frame scene scans or persistent effect history when fully disabled beyond any measured shared baseline. |
| Diagnostics | Concise user-facing resolution, provider, real render rate and bottleneck/fallback explanation where independently established; otherwise label an estimate, unconfirmed execution or unavailable measurement. Stale/ambiguous telemetry cannot diagnose a bottleneck. Keep raw SDK tokens and internal patch details in exported diagnostics, not the ordinary settings flow. |

Use one rendering policy to serialize settings preview, resize/Retina output changes, runtime failure, history resets and DRS. A controller writing `Viewport.scaling_3d_scale` independently would fight the existing apply path and misreport metadata. Runtime adaptation must not save preferences every frame or overwrite the user's selected mode.

The detailed controller in [02](02-dynamic-resolution-and-upscaling.md#proposed-controller-contract--pending-proof) intentionally uses conservative starting thresholds and dwell times. They are test parameters. Godot's resource behavior may still make those transitions unacceptable; a longer dwell alone does not close that issue.

## Hardware strategy

OS, GPU vendor, rendering method and graphics API are independent dimensions. AMD is a GPU/platform vendor; it is not an alternative operating system to Windows or Linux.

| Platform family | First useful path | Follow-up and boundary |
| --- | --- | --- |
| Apple Silicon | Reproduce the existing M1 reference with the actual Mobile/Metal and candidate Forward+/Metal paths; qualify Spatial first, then Temporal. | Qualify hardware-accelerated RT and newer MetalFX functionality separately on named newer devices and a verified backend; the pinned stock Metal driver has no RT implementation. M1 Metal API support is not M3-class RT acceleration. Intel/Rosetta and MoltenVK are separate fallback cases. |
| Windows NVIDIA | Official Standard/High baseline plus the existing custom Vulkan package; static FSR2 versus DLSS and within-fork Reflex Off/On/Boost. | Include a less powerful/laptop device as well as RTX 3090 before a broad claim. Do not transfer official beta2 features to the older NVIDIA fork. |
| Windows AMD / Intel | Official engine High/FSR2 where admitted, with Standard recovery and measured native baseline. | The AMD SDK candidate, ML provider, Anti-Lag or Intel XeSS/XeLL are separate integrations; avoid adding them solely to display another brand. |
| Linux | Official Standard and Forward+/Vulkan on a named AMD/Mesa and NVIDIA-driver host; Intel coverage where a target is available. | Record X11/Wayland, compositor, driver and display. Current Windows-specific SDK packaging establishes no Linux support. |

Hardware that is unavailable remains explicitly untested. Select a small first target set and finish its evidence before widening the matrix. The same controller logic can be portable while telemetry, provider lifecycle, packaging and presentation remain backend-specific.

## Effort and stop conditions

These ranges are engineering estimates for an experienced owner with available hardware, not delivery promises. They exclude purchasing, pilot scheduling and unresolved vendor defects; do not sum overlapping rows into a calendar commitment.

- Measurement/ownership foundations: **M0's maximum five engineering days**, including its initial native attribution and overhead checks; no open-ended follow-on measurement stage.
- Static provider and transition work: approximately **4–10 days per engine family**, potentially longer if the renderer needs persistent allocation or a maintained engine change.
- Deterministic DRS policy/UI: approximately **3–5 days after those gates**, plus **3–6 days per available platform family** for the initial native comparisons and further pilot/package evidence.
- Existing Reflex completion and measurement: roughly **one to three engineering weeks on the first named host/transport**, depending on flash support and measurement setup. A new vendor/backend integration can take **2–6+ weeks before broader qualification**.
- A controlled RT fixture: **2–4 weeks after capability proof**. Correct moving-scene/material integration is more plausibly **6–12+ weeks**, followed by noise/settings/platform work. This is a substantial renderer project, not a switch to turn on. A prerequisite exposed by the fixture can invalidate the estimate.

For DRS, stop or retain the fixed baseline when CPU work limits the target, a fixed scaler already meets it with better clarity, timing is stale, or scale transitions add unacceptable spikes. A CPU-limited workload can still warrant a separate Reflex/Boost experiment. For every candidate, retain the baseline if aircraft orientation becomes harder to judge or fallback is unreliable; retain raster if an RT candidate exceeds measured whole-frame headroom. A lower GPU average or a higher generated FPS figure cannot override those failures.

## First implementation handoff

The first reviewable change repairs F02 through the existing consumers and tests. The second adds only the missing validity/scope fields and compatible reducer handling. These can be combined if that is the smallest coherent patch. By M0's closure, publish the first named-host result and select the next **product** change: M1's fixed-provider correction or M3's existing Reflex completion. Admit M2 only if its specific feedback and transition prerequisites pass.

Every milestone ends with a compact record in its existing owner evidence: objective, actual changed files, reference package, chosen metric, completed checks, measured outcome and uncertainty, engineering time spent on instrumentation versus implementation, and **accepted for this row / experimental / retain baseline / inconclusive or blocked**. Do not count created tools, collected counters, research pages or executed test cases as delivered performance.
