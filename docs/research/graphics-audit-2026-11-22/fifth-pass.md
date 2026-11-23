# Graphics and FPS audit — fifth pass into uncovered paths

**Source: [main `0f859b5f358f4807877ec8bd7fe8009bc3856d3f`](https://github.com/bultodepapas/OpenRCsimulator/commit/0f859b5f358f4807877ec8bd7fe8009bc3856d3f), integrated into `graphics-audit`.** This pass adds nine conditional optimization investigations in paint assets, input dispatch, acoustic propagation, mechanical audio and first-rain preparation. Some extend established owning tracks into a newly traced boundary; none is presented as a newly measured FPS bottleneck. V01–V09 are local audit labels, not implementation-track IDs.

The strongest new hitch hypothesis is a gap between lens setup warm-up and the first spatial rain-streak construction. The most consequential new content tradeoff is the JETI paint's resource and mesh-LOD policy. Repeated input and audio work is source-confirmed but needs attribution before being prioritized over the retained Linux terrain cost. No production optimization is implemented, no graphics quality is reduced, and no new FPS gain is claimed.

## Reports

| Report | Purpose |
| --- | --- |
| [Paint assets, ownership and LOD](fifth-pass-assets.md) | V01–V03: synchronous selected-paint loads, live resource references and stripe-preserving geometry bias |
| [Input sampling and dispatch](fifth-pass-input.md) | V04–V06: action metadata, unused quad keyboard axes and conditional repeated absolute throttle |
| [Audio propagation and mechanical endpoints](fifth-pass-audio.md) | V07–V08; explicit continuation of already-tracked glow-worker work |
| [First rain and lens lifecycle](fifth-pass-lens.md) | V09, tier arithmetic, first-use measurement gap and rejected dry-work shortcut |
| [Latest main, Linux evidence and caps](fifth-pass-current-main.md) | New source, corrected host attribution, effective caps and qualification limits |
| [Evidence and source inventory](fifth-pass-evidence.json) | Exact Git blobs/SHA-256, source-data counts, GitHub observations, review disposition and actual checks |

The previous [fourth pass](fourth-pass.md), its [Nitro sampler component experiment](rig-sampler-experiment.md), and [third-pass findings](README.md#third-pass-snapshot) remain dated evidence. Their results are not rerun or silently reassigned to this main.

## Additional findings and investigation priority

Priority here means which uncertainty to resolve first, not a prediction of FPS gain.

| ID | Source-confirmed work or policy | Trigger and limitation | Smallest useful next step |
| --- | --- | --- | --- |
| **V09** | First positive rain synchronously creates a separate spatial MultiMesh, identity buffer, material and node; setup warm-up covers 2D lens channels instead. | First use per stack, potentially during startup or a paused sky edit. Shader resources/caches may already be warm; no measured hitch. | Attribute construction, buffer assignment, scene insertion and first rendered/presented frame separately. Then compare selective warm-up or bounded resource preparation. |
| **V01** | Home preloads the selected aircraft GLB, while JETI paint application performs four distinct synchronous texture-path loads inside the model-build unit. | Model-cache miss and selected paint. Godot caches can make loads cheap; source calls do not prove disk or GPU stalls. | Cold/warm selected-paint spans and first-visible timing; extend the existing bounded engine loader only if those lookups matter. |
| **V03** | JETI requests `lod_bias=16` for fuselage and fixed tail at all Scene detail levels. Their GLB source totals 37,810 base triangles. | Deliberate protection of narrow UV stripes. Source triangles are not actual imported/selected LOD or draw counts. | Count actual selected LODs and full-frame GPU/CPU work, then test a lower safe bias or source-generated UV-preserving LOD. |
| **V02** | Four JETI atlases contain 41,943,040 base texels; paint copies retain original materials, and bounded Home livery roots can coexist with flight construction. | Resource references are confirmed, actual unique residency and pressure are not. Mips and GPU compression already exist. | Enumerate unique texture/material identities, formats and peak/steady residency across selection, flight, eviction and release. |
| **V07** | Acoustic propagation walks retained source history and performs 40 refinement iterations after finding a bracket. | Fixed-wing/helicopter soundscape with delay enabled and valid voice/history. Existing prefix and same-tick protections remain. | Time complete propagation plus caller. If material, compare a batched native exact loop; preserve newest-crossing and all history semantics. |
| **V04** | A qualifying shell key/joy event with the complete map invokes 37 metadata duplicates and 30 flight/both binding duplicates in generic identity synchronization. | Initialized service, no ground activity, non-echo event. Event-local profile/map caches already exist. Event frequency is unmeasured. | Attribute the router; compare scalar metadata access and conditional detached-identity replacement before considering a larger binding cache. |
| **V08** | A normal mechanical-audio frame with a newly drained endpoint can read actuator angles/gear twice and normalize matching-tick rows again. | Same endpoint only if mutable inputs/session stay unchanged; near/far and accepted-cadence guards differ. | Measure accepted collection, presentation projection and normalization separately, then share only proven same-endpoint immutable values. |
| **V05** | The quad's built-in reader still performs eight keyboard flight-axis state reads when a connected radio/pad supplies the flight axes. | E/M/F shortcuts remain necessary; custom reader Callables and source changes must preserve their behavior. | A narrowly tested built-in shortcut path, after complete-sampler attribution. This is a small-work hypothesis. |
| **V06** | An armed, valid fixed-wing absolute radio throttle can be normalized three times during an ordinary callback. | Gamepad, hold, calibration, unarmed and invalid branches differ; rate callbacks and throttle cut make blind reuse incorrect. | Lower priority: measure first, and reuse only within a proven unchanged no-callback span or with an exact dependency proof. |

The [domain reports](#reports) retain entry points, source lines, guards, counterexamples, relevant existing tests and platform experiments. All nine are opportunities to investigate; the table intentionally does not equate a duplicated operation with a dominant frame cost.

## What the counts mean

The lead independently read pinned Git objects and verified the input declarations, PNG headers and GLB accessors. The [JSON receipt](fifth-pass-evidence.json) contains 42 hashed source/data entries and the exact arithmetic. There was no import, rendering or engine execution in this pass.

For V04, the declaration contains 7 menu, 29 flight and 1 both-context actions. Thus the complete map executes 37 metadata duplicate calls and 30 binding duplicate calls in that synchronization loop. At an observed event rate \(E\), those two categories contribute \(37E\) and \(30E\) calls/s. They are calls, not measured allocations or USB reads; route-specific branches can perform other work. No device event rate is invented.

V05's eight reads would be 1,920 calls/s at 240 qualifying samples/s. V06's three normalizations would be 720/s at 240 qualifying callbacks/s. Neither expression supplies the time per call, the affected critical path or input latency. A native boundary added around a tiny built-in call may lose more than it saves.

The four JETI maps are two 4096² and two 2048² images: 40 MiTexels at base level and 55,924,052 texels in a complete mathematical mip chain. Hypothetical 4×4 blocks would occupy 26.67 MiB at 8 bytes/block or 53.33 MiB at 16 bytes/block, including small tail blocks. These are alternative layouts, **not observed formats, bounds on VRAM, or a sum with the original images' residency**. Shared textures/RIDs, imports, residency and unified-memory accounting require a runtime inventory.

V09's Ultra capacity is \(14{,}000\times4=56{,}000\) instances. Twelve float32 transform entries yield 672,000 elements or 2,688,000 logical bytes in the final buffer. Doubling reaches 786,432 elements before the final resize. That is an algorithmic length calculation, not measured peak memory, upload traffic, time or visible-instance count. Existing doubling and bulk MultiMesh assignment are already efficient native-engine operations.

For all candidates, use time rather than adding percentage promises. In a simplified serial workload with removable fraction \(p\) and component speedup \(s\), Amdahl's bound is \(1/((1-p)+p/s)\). With overlapping CPU/GPU work, a useful first model is frame time near the larger of CPU-critical-path time and GPU time, plus scheduling/presentation costs. A CPU micro-optimization may leave a GPU-bound frame unchanged. First-use latency is a separate outcome from steady FPS.

## Native implementation preference, applied to these paths

**Keep existing engine capabilities where they fit.** ResourceLoader, resource sharing, generated mesh LODs, MultiMesh buffers and recorded audio already execute substantial work in Godot. V01 and V09 first need attribution and correct preparation timing, not a new C++ loader or a per-instance extension wrapper. Godot's [threaded loading reference](https://docs.godotengine.org/en/latest/classes/class_resourceloader.html#class-resourceloader-method-load-threaded-get) specifically warns that retrieving an unfinished request blocks; requesting background work alone is insufficient.

**Use a coarse native boundary when a loop is measured.** V07 is the clearest new candidate for comparing an exact native batch: search and refine packed history in one call while preserving current scalar/Vector3 precision, results and full caller semantics. A binary search, quadratic replacement, fewer bisections or changed sampling policy is a different algorithm and needs separate proof. Godot's [procedural audio guidance](https://docs.godotengine.org/en/latest/classes/class_audiostreamgenerator.html) supports considering native generation for expensive synthesis; it does not prove a win for this particular propagation loop or for the already-threaded glow producer.

**Avoid crossing costs for tiny operations.** For V04–V06 and V08, test scalar/typed or already-native container paths first. Compare the full boundary, including marshalling, copies, locks, callbacks and result construction. Keep the GDScript reference/fallback and prove actual backend selection in target runs. No recommendation reduces the 240 Hz simulation, changes float64 simulation math, weakens accepted-tick atomicity, or bypasses rollback/checkpoint identity.

Godot's [LOD reference](https://docs.godotengine.org/en/latest/classes/class_geometryinstance3d.html#class-geometryinstance3d-property-lod-bias), [MultiMesh guidance](https://docs.godotengine.org/en/latest/tutorials/performance/using_multimesh.html) and [GPU optimization guide](https://docs.godotengine.org/en/latest/tutorials/performance/gpu_optimization.html) support the API interpretation and hardware attribution strategy. They were retrieved on 22 November 2026. These moving official references do not substitute for the repo's pinned engine, generated shader or hardware evidence.

## Current-main evidence has higher-priority work too

The new Linux report attributes a substantial part of the earlier long loading freeze to the host's ALSA-null setup, and gives direct retained evidence of expensive terrain shading on UHD 630. It also shows that Low scene detail did not materially improve that Vulkan workload. The [current-main report](fifth-pass-current-main.md) explains these source and measurement distinctions, including why overlapping ablations cannot be added and why a 30 ms terrain-material ablation is not an accepted visual optimization.

The same report distinguishes the user's FPS/VSync cap, the existing 240 Hz/12-step slow-motion ceiling, frame-generation admission and resource capacity. There is no basis to remove those bounds indiscriminately or report generated presentation frames as additional simulated time.

## Independent review and rejected claims

Three bounded investigators followed [the repository's subagent guide](../../SUBAGENTS.md): assets/imports, input/dispatch and audio/scheduling. Input and audio drafts received independent cross-review, and the root lens investigation was challenged by two helpers. The lead read the original code, resolved the objections, independently verified source-data counts and owns integration/publication. Requested helper settings were `gpt-6.1-terra`/`max`; effective runtime model/effort was not exposed and remains unverified.

Material corrections incorporated:

- **Novelty:** glow full-queue snapshot copying and the grass pilot-anchor calculation are explicitly already tracked in the Apple Silicon plan. They are not counted among V01–V09. AUD-11 history-prefix optimization is also acknowledged; V07 examines the retained scan/refinement boundary, not a rediscovery of the old copy repair.
- **Input semantics:** map construction differs for no device, unconfigured profile and configured profile. Raw throttle is read after throttle-cut handling; a stick-rate cut resets its accumulator. A rate-change listener could reenter, but the inspected production recorder only records the change. The built-in quad fast path needs its own coverage; a replaced reader only tests fallback.
- **Audio attribution:** 40 propagation refinements happen only after a bracket. Mechanical getters are GDScript, and `last_mechanical_update_usec` excludes the accepted-endpoint collection at the start of the callback. Historic main-thread glow timings do not measure the current worker.
- **Rain state:** dry wind integration contributes to the first visible streak phase, even before any rain has appeared. Skipping it is not equivalent. First-rain construction is once per stack, can occur paused, survives a reset, and is absent when the relevant effect is disabled. Full eager allocation on dry flights would shift cost and alter the existing setup contract.
- **Assets:** caches are bounded; imported source materials remaining referenced are not proof of a leak. Higher LOD bias is an intentional visual tradeoff, not proof that all 37,810 source triangles are rendered. New Timber shader branches already respect detail guards.

Other screened paths include controller profile-change guards, hot-plug cadence, native recorded quad/airship audio, bounded wildlife/thunder queues, frame-generation polling and dirty-guarded lens drops. Their current protections are retained in the reports; no unsupported bottleneck is manufactured for each vehicle.

## Validation and remaining work

This pass performed source/Git inspection, deterministic metadata arithmetic, independent review and focused documentation/evidence checks. The exact final checks and GitHub snapshot are in [the evidence receipt](fifth-pass-evidence.json). Source observations establish reachable work; they do not certify runtime cost. No application/engine, full test suite, GPU trace, physical controller or audio-device benchmark was run.

Implementation candidates should use the existing owning test seams listed in each report and the admitted performance route. Record actual source/binary/native-backend identity, device/driver/API, audio backend, focus and drawable state, output/internal size, active caps, cold/warm state and completed phases. Measure Windows/Linux at 1080p and Apple Silicon on the native Retina display, with the relevant renderer and power/thermal conditions. Keep callback timing, presented-frame p50/p95/p99, worst first-use interval, input-to-photon and simulation/wall pace separate. For V09 and V01, the cold transition is required; a steady benchmark after six seconds cannot close it. For V02/V03, capture unique resources and selected LODs; source counts alone cannot close them.
