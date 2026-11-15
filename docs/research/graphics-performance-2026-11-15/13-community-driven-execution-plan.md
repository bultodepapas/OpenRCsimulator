# Community evidence: decisions and the next implementation slices

2026-11-15 · Continuation from `3dc343bb5d3654c75eee6e4078da1bb0f6e9d9ff` on the existing audit branch. The application baseline remains `e488ef7653e8dd0f0a2e7db18e396bb4da0aaccc`. This round adds **17 practical case studies** to the earlier [20 investigations](08-twenty-external-investigations.md): first-person developer reports, maintainer discussions, failed suggestions, reported outcomes and primary-source checks. It advances the implementation handoff without introducing another measurement executable.

**Next action remains the bounded M0 repair, followed by one demonstrated fixed-provider correction or the existing Reflex comparison.** The case studies refine which regression to add and which explanation to reject. They are not 17 SDK integrations, 17 independent projects, or proof that any reported failure occurs in OpenRC. [05](05-integrated-implementation-plan.md) owns this audit's milestones, [06](06-validation-and-benchmark-plan.md) its acceptance protocol, and [11](11-test-and-execution-playbook.md) its actual command/prerequisite cards. Existing track plans retain authority.

## 1. What the forum round changes

| Case | Evidence and implementation consequence | Existing slice |
| --- | --- | --- |
| [C-DRS-01](community/01-resolution-and-upscaling-cases.md#c-drs-01--fullscreen-and-a-scaler-coincided-with-persistent-frame-drops) | Unresolved fullscreen/scaler report: isolate fixed-scale window transitions before attributing a DRS hitch. | Selected M0 screen or M1 transition correction. |
| [C-DRS-02](community/01-resolution-and-upscaling-cases.md#c-drs-02--object-motion-vector-resets-are-not-camera-history-resets) | Terrain3D/API discussion: object motion vectors and accumulated camera history have separate reset obligations. | M1 history regression, if that boundary changes. |
| [C-DRS-03](community/01-resolution-and-upscaling-cases.md#c-drs-03--moving-camera-ghosting-survived-an-unreal-fsr2-plugin-workaround) | Unresolved Unreal FSR2 case: distinguish a normal pan, disocclusion and a true cut; do not transplant near/far workarounds. | Existing M1 motion/cut review. |
| [C-DRS-04](community/01-resolution-and-upscaling-cases.md#c-drs-04--additive-billboards-shimmer-under-fsr2) | Open Godot additive-content report: include the simulator's actual small bright/transparent content in finalist review. | M1 image/readability check. |
| [C-DRS-05](community/01-resolution-and-upscaling-cases.md#c-drs-05--unsupported-metalfx-request-left-temporal-jitter-active) | Historical unsupported-backend fix: verify effective/fallback status; the report is not an Apple-device failure. | Existing MetalFX policy and selected native fixture. |
| [C-DRS-06](community/01-resolution-and-upscaling-cases.md#c-drs-06--above-native-fsr2-fell-back-to-bilinear-but-kept-the-wrong-type) | Historical above-native fallback fix: current product temporal choices stay at or below 1.0. | Conditional policy regression when the table changes. |
| [C-LAT-01](community/02-latency-and-pacing-cases.md#c-lat-01--where-the-limiter-waits-can-change-the-physical-result) | Gamescope/Deck observation: record the actual cap/presentation path; do not stack independent pacers. | Existing M3 matched conditions. |
| [C-LAT-02](community/02-latency-and-pacing-cases.md#c-lat-02--a-clock-regression-can-confound-a-boost-comparison) | Reported Linux FG clock bug and driver fix: clocks/thermals can confound Boost; FG remains outside this package. | Existing M3 attribution and F6 comparison. |
| [C-LAT-03](community/02-latency-and-pacing-cases.md#c-lat-03--wine-translation-once-lacked-a-working-vulkan-reflex-path) | Translated Vulkan sample failure and later fix: native Linux, Wine/Proton and native Windows have different integration identities. | Capability/failure check; no new Linux port. |
| [C-LAT-04](community/02-latency-and-pacing-cases.md#c-lat-04--mouse-triggered-stutter-varied-with-the-compositor-path) | Unresolved compositor/input stutter: distinguish input type, active flight, menu, focus and presentation path. | Relevant existing lifecycle/F6 checks. |
| [C-LAT-05](community/02-latency-and-pacing-cases.md#c-lat-05--present-call-spacing-is-not-display-spacing) | Streamline display discussion: process, Present, displayed-frame and optical endpoints are different. | Existing report interpretation, M3/F6. |
| [C-LAT-06](community/02-latency-and-pacing-cases.md#c-lat-06--an-off-to-on-transition-can-expose-missing-frame-association) | Delay draw N until the main thread owns N+1; request Off → On and verify N's captured-token render/present callbacks finish before options apply. This is not GPU completion. | RX-04 fake SDK and native smoke. |
| [C-RT-01](community/03-ray-tracing-cases.md#c-rt-01--nvidia-push-constants-failed-while-an-amd-run-appeared-correct) | Cross-driver shader-parameter failure, already fixed upstream: add a differential parameter check; no redundant engine patch. | RT-01 capability fixture. |
| [C-RT-02](community/03-ray-tracing-cases.md#c-rt-02--reported-fast-rt-did-not-solve-deforming-geometry) | Reported static-scene timing and animation limits: distinguish rigid transforms, vertex deformation and complete caster coverage. | RT-03/04, conditional M4. |
| [C-RT-03](community/03-ray-tracing-cases.md#c-rt-03--a-lightmapgi-timeout-was-initially-confused-with-memory-pressure) | Fixed offline-bake timeout: bound actual work and classify the failure before changing memory or timeout policy. | RT-05/06; no copied baking synchronization. |
| [C-RT-04](community/03-ray-tracing-cases.md#c-rt-04--self-intersection-attribution-and-an-external-allocation-improvement) | OptiX numerical/allocation investigation: reuse a numerical reference only with its inputs and assumptions. | RT-02/03 plus attribution if needed. |
| [C-RT-05](community/03-ray-tracing-cases.md#c-rt-05--cross-viewport-texture-sharing-remained-unresolved) | Unresolved compositor sharing: borrowed buffers need matching identity, usage, extent and producer order. | RT-05 and admitted M2 transitions. |

The individual chapters contain report dates, software/hardware details where provided, status at inspection, sources, OpenRC paths and falsifiable test outcomes. A favorable follow-up, issue closure and merged change are recorded separately. Missing information is not filled with hardware from another thread. External timing numbers retain their original scope and are not converted into an OpenRC forecast.

## 2. Objectives, outputs and stop decisions

| Objective | Concrete output for the senior developer | Success or stop |
| --- | --- | --- |
| **Make the existing evidence dependable** | The existing M0 lease/validity patch, focused regressions, frozen 1080p control and unchanged repeat, one discriminating native screen and compact decision. | Five engineering days **total**. Proceed, static-only or blocked/defer. Unknown completed GPU identity cannot drive DRS. |
| **Deliver one better existing graphics option** | One reproduced transition, history, fallback or settings defect corrected in its owning app/engine family; affected existing tests and matched images/motion. | The failure disappears and protected frame/physics/readability gates hold. A formal performance-improvement claim additionally uses the established ≥5% full-workload criterion or named hitch/memory correction, with variation. |
| **Finish the existing Reflex question** | Same-build Off/On/Boost acceptance, ordered token/marker evidence, separately collected presentation diagnostics and physical F6 observations. | Report functional, SDK, presentation and physical results separately. Missing/insufficient physical evidence yields inconclusive; it does not become a numerical latency benefit. |
| **Decide whether the first RT effect is useful** | After defect/headroom admission: correct known-triangle/parameter fixture, exact-once selected-sun lighting, explicit coverage and bounded resource cost. | Two-day feasibility decision; useful correct opaque fixture by the two-week checkpoint or retain raster/defer. Full flight and other devices remain separate qualifications. |

These outputs fit the [existing reviewable work sequence](12-senior-developer-handoff.md#proposed-reviewable-change-sequence). The initial 1080p control is one named available native configuration. Apple, Windows, Linux, AMD and NVIDIA are addressed by their actual engine/backend/device rows, not by multiplying every case over all vendors before useful work starts. Higher resolutions follow 1080p; 720p remains the later compatibility target.

### A bounded next reviewable change

1. Implement the shared timing-interest/lifetime repair and compatible sample validity already specified in [09](09-timing-and-drs-design.md). Use the existing diagnostics, render-probe and collector/reducer tests. The community cases do not enlarge this patch to providers, RT or input physics.
2. In M0's already allocated native day, answer one product decision. If transition cost is the selected question, C-DRS-01 supplies a fixed-scale/resize control; otherwise it waits for the selected M1 provider. Keep the observer overhead screen inside the same budget. Do not require every new case before closing M0.
3. Choose a demonstrated M1 defect or the independent M3 comparison, reuse the case-specific negative control, and make that change concrete. Historical fixes already in the chosen engine need a regression only when their boundary is relevant; they do not generate local patches.
4. Extend qualification only for the finalist and the changed boundaries. Preserve owner-required export, lifecycle, soak and hardware gates, but do not repeat them for each document edit. A source-only report cannot close any native gate.

Further attribution gets at most one engineering day before review as already agreed. One predeclared repeat may resolve a named uncertainty. A repeated unresolved result closes experimental/defer; it does not justify a second profiler or a new benchmark subsystem. The [38-test DRS reference](../../../research/performance/graphics_handoff/README.md) remains the existing disposable software model. This forum round neither changes nor reruns it because its implementation inputs are unchanged.

## 3. Pseudocode for choosing and closing a case

This is **workflow pseudocode**, not a new script, API, CI requirement or runtime gate. Use it in the existing owning issue/receipt. The case chapters and 11 contain the specific tests; this rule prevents an old forum report from silently becoming an engine change.

```text
for the ONE selected implementation question:
    freeze candidate + engine/template/patches + content + native environment
    read original report, subsequent replies, fixing source and actual pin

    if the trigger is outside the current product or selected backend:
        record not_applicable_now and a concrete future trigger
        stop this case

    if the relevant correction is already present:
        reuse a matching existing regression if its boundary is being changed
        otherwise record already_addressed_in_source; no duplicate patch

    state expected result independently of the implementation
    run the smallest applicable existing test/fixture on the selected candidate
    preserve failure, logs, identity and incomplete/unknown fields

    if the report does not reproduce within the predeclared screen:
        retain the candidate and record not_reproduced_on_named_configuration
        stop; this is not a universal pass and does not prove the report wrong

    if it reproduces:
        choose one discriminating negative/control case
        make one focused correction in the owner
        show the regression catches the faulty behavior
        compare the changed boundary and protected complete-workload metrics
        close as corrected, retain_baseline, or experimental/defer
```

The native observation must follow the actual transaction. A request, an encoded call and a completed result remain distinct. If a required device, provider or sample identity is unavailable, record unavailable rather than taking the `not_reproduced` branch. Do not postpone independent fixed-provider or Reflex work until every DRS dependency is solved.

### Temporal event routing to prepare in the selected existing fixture

[C-DRS-02/03](community/01-resolution-and-upscaling-cases.md) make the existing history tests more discriminating. This ordering is a proposed test contract; it is not code added to normal flight:

```text
ordinary smooth presentation:
    update rendering transforms and camera
    preserve valid motion vectors and accumulated temporal history

declared object teleport / relaunch:
    install the final presentation transform first
    invoke the exact engine's supported object-motion reset at that boundary
    verify relevant visual descendants/visibility; do not assume a counter proves it

actual camera cut, world replacement, or provider reset condition:
    after final placement, apply that provider's actual history lifecycle
    if existing history needs a reset:
        submit the scoped reset once and verify its dispatch/consumption
    if an empty generation is proven and placement preceded its first draw:
        preserve the provider's initial-history path without an extra request
        verify its first encode/reset behavior and separately its completion scope

unsupported reset path:
    report unavailable and retain the known qualified option
```

The object path must be checked against the chosen engine and existing node lifecycle. In official beta2, a visible in-tree `VisualInstance3D` forwards the reset notification to `instance_teleport`; a renderer may have further motion-data requirements. A global history reset does not prove every object vector is correct. The current [MetalFX reset policy](../../../app/render/reconstruction.gd#L437) deliberately reports `initial_history` without submitting an extra request for its proven empty-generation path; [existing tests](../../../app/tests/test_reconstruction_history.gd#L260) protect this. Do not invent a submitted serial or require a duplicate reset. Missing readiness/proof remains unavailable/fallback, and only the selected native path can establish actual GPU completion. Normal movement must not trigger continuous resets, and render-side tests must leave simulation/replay/input state unchanged. The exact object source and scope are linked in C-DRS-02.

### Minimal result record

Use the current owner report and existing capture metadata. Record only fields needed for the decision: case ID; candidate/control identities; applicability; expected versus observed result; exact checks/artifact references; completeness; unknowns; correction or retain/defer outcome; engineering time; next owner action. Keep numeric frame streams compatible with their existing schema. Do not inject this textual case record into `FrameSamples` or write a new per-frame log.

## 4. Newer main checkpoint and retained project results

At **2026-11-15 21:55 UTC**, the GitHub API reported `main` at [`273a7e4c0617fdf4cacc39c360796fd79afa5f2c`](https://github.com/bultodepapas/OpenRCsimulator/commit/273a7e4c0617fdf4cacc39c360796fd79afa5f2c); a later Git fetch agreed. This is a dated observation, not a promise that main stops moving. It is two commits beyond the [earlier handoff checkpoint](12-senior-developer-handoff.md#publication-checkpoint-and-parallel-main-changes). The audit branch remains on its application baseline and no unrelated main changes are merged.

The new comparison adds Extra 300S visual/content work, aircraft-import planning, test-queue operator recovery, and more Apple evidence. A full diff from the application baseline still shows **no changes in the inspected graphics seams**: `app/render`, `app/input`, `app/ui`, `app/debug`, Main/AppRoot, the engine getter, `tools/graphics`, `tools/godot` and CI workflows. `tools/testqueue` now differs, so use the candidate's actual tool contract when implementing. The prior simulation/statistics/companion changes and these aircraft changes still require a newly frozen complete-workload control; matching renderer source does not make old flight measurements current.

The immutable [DT-MAC-11a owner report](https://github.com/bultodepapas/OpenRCsimulator/blob/273a7e4c0617fdf4cacc39c360796fd79afa5f2c/docs/research/desktop-delivery-investigations/DT-MAC-11a/README.md#r3-package-warm-product-trial-and-native-intake-follow-up) now reports source-native correctness on combined candidate `b4442e6a86b58489d67683f56f39623353480a0d`, including numerical/mutation/domain controls and production-path stage, lifecycle and exact replay. It also reports editor/template/signature binding checks and portable export/measurement controls. Those are useful retained results to reuse. The report explicitly leaves actual paired package execution and automatic-default qualification open; the R3 ZIP still uses its older clean19/reference combination. The custom CPU lane measures callback time per tick and a reference/native ratio, **not FPS**. This round read the changed owner report and source identities; it did not retrieve its payloads or independently rerun native tests. Its numbers do not become audit-branch results.

The new [test-queue contract](https://github.com/bultodepapas/OpenRCsimulator/blob/273a7e4c0617fdf4cacc39c360796fd79afa5f2c/tools/testqueue/README.md) permits a specific operator abandonment with unconfirmed cleanup only through an explicit operator decision and its checks. It records an infrastructure failure and incomplete evidence. Nothing in this research uses that exception, releases a host, or treats administrative closure as a passing run. Normal ownership and cleanup requirements remain in the existing playbook.

## 5. Completion evidence and remaining work

The [community validation receipt](evidence/community-validation.json) records the actual source and documentation checks, case IDs, relevant immutable upstream identities and the inspected main checkpoint. The three case chapters and this plan are the new deliverable; README, source record, test playbook and senior handoff link to them. Existing evidence is retained as historical evidence, not overwritten to imply a new run.

This continuation performs no application, engine build, GPU, physical radio/display, export, endurance or runtime-CI test. It adds no production code, SDK dependency, graphics option or measurement tool. The next developer has concrete rejection cases and expected outcomes, but smoother flight, lower input latency and a useful RT image still require the scoped implementation and native evidence specified above.
