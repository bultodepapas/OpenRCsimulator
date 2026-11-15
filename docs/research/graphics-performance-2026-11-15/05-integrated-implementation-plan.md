# Integrated implementation work order

2026-11-15 · Advisory plan against `e488ef7653e8dd0f0a2e7db18e396bb4da0aaccc`. Read the [source findings](01-repository-audit.md), [dynamic-resolution study](02-dynamic-resolution-and-upscaling.md), [latency study](03-latency-reflex-and-boost.md), and [RT study](04-ray-tracing-in-godot.md) for evidence. This sequence proposes work under existing owners; it does not mark their steps accepted or complete.

## Product goal and decisions

Offer graphics options that improve real flight smoothness while keeping small aircraft readable and control response predictable. The primary qualification target is 1920 × 1080 at a 60 Hz profile, then higher resolutions, then 720p fallback. Rendering must not change the fixed simulation law, aircraft data, input ownership or recorder. A successful result may be retaining the baseline when a feature fails its cost, clarity or latency test.

Recommended order:

1. Establish trustworthy CPU/GPU, real-frame and latency evidence on the current exported builds; repair the timing-owner conflict and document exact build capabilities.
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

The first three slices can be separately reviewed without waiting for RT. Reflex measurements can run after the shared baseline, but not concurrently with another workload on the same measurement host. New SDK/engine upgrades are independent changes with their own controls; do not combine a provider upgrade, a new DRS controller and a renderer migration in one performance comparison.

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

- Measurement/ownership foundations: approximately **2–4 engineering days**, then native attribution and overhead checks.
- Static provider and transition work: approximately **4–10 days per engine family**, potentially longer if the renderer needs persistent allocation or a maintained engine change.
- Deterministic DRS policy/UI: approximately **3–5 days after those gates**, plus **3–6 days per available platform family** for the initial native comparisons and further pilot/package evidence.
- Existing Reflex completion and measurement: roughly **one to three engineering weeks on the first named host/transport**, depending on flash support and measurement setup. A new vendor/backend integration can take **2–6+ weeks before broader qualification**.
- A controlled RT fixture: **2–4 weeks after capability proof**. Correct moving-scene/material integration is more plausibly **6–12+ weeks**, followed by noise/settings/platform work. This is a substantial renderer project, not a switch to turn on. A prerequisite exposed by the fixture can invalidate the estimate.

For DRS, stop or retain the fixed baseline when CPU work limits the target, a fixed scaler already meets it with better clarity, timing is stale, or scale transitions add unacceptable spikes. A CPU-limited workload can still warrant a separate Reflex/Boost experiment. For every candidate, retain the baseline if aircraft orientation becomes harder to judge or fallback is unreliable; retain raster if an RT candidate exceeds measured whole-frame headroom. A lower GPU average or a higher generated FPS figure cannot override those failures.

## First implementation handoff

The recommended first code change is the bounded timing-owner correction from F02, with overlap and viewport-lifetime tests, accompanied by a source-identical 1080p baseline. Then produce a transition-cost report for one current provider. Those results decide whether the first DRS implementation should use the existing setter, needs an engine patch, or should remain a fixed-scale option. This keeps the next engineering decision concrete and independently reviewable.
