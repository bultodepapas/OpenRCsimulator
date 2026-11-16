# Ray-tracing fixture handoff: tested oracles and native prerequisites

2026-11-15 · Initial fixture continuation from `92a16af2ddb5b26951ce4067484a79fb26a7014a` on `audit/graphics-performance-technologies-2026-11-15`. Application baseline remains `e488ef7653e8dd0f0a2e7db18e396bb4da0aaccc`; official Godot remains `4.8.beta2.official.cafc17a19` / `cafc17a192acf67903910a68aeb3c076c0907a4b`. The initial read-only `main` checkpoint was `273a7e4c0617fdf4cacc39c360796fd79afa5f2c`, separate from this branch. The first handoff added offline executable preparation and a proposed native work order. The [later patch preparation](#6-prepared-engine-patches-and-compiled-controls) supplies actual engine diffs and compilation evidence; a simulator RT effect remains unimplemented.

**Decision:** prepare the first correct Vulkan visibility result before adding a denoiser or exposing a graphics option. The deeper inspection found a concrete AS-address contract mismatch and two additional source risks in the exact engine pin. Resolve those prerequisites in an isolated engine candidate, then compare a tiny GPU witness against the independent answers supplied here. Continue toward one useful sunlight-shadow fixture only if that gate and the existing visible-defect/headroom decision pass.

The [quality plan](14-ray-tracing-quality-and-delivery-plan.md) still ranks pilot-visible benefit. The [integrated plan](05-integrated-implementation-plan.md) still controls milestones: **M0 is five engineering days total**, with no extra measurement project; M4 has a **two-day feasibility decision** and **two-week useful opaque-fixture checkpoint**. These work packets divide that admitted work, not extend its budget. VQ/GDU/PT/DT retain their existing ownership.

## 1. What is ready to use

| Deliverable | Actual state | Boundary |
| --- | --- | --- |
| [Offline geometry and light-energy reference](../../../research/performance/graphics_handoff/rt_fixture_README.md) | Standard-library Python module, **26 passing focused test methods**, **14 geometric cases** and **five lighting cases** with independently recorded expected values. | No Godot, GPU, network, telemetry, physics, settings or production adapter. |
| [Vulkan fixture work order](ray-tracing/03-vulkan-fixture-work-order.md) | Source-specific sequence for engine prerequisites, device admission, real SBT allocation, buffer/instance packing, compute query, witness decoding and lifetime. | Proposed native implementation; shader compilation and execution remain unperformed. |
| [Validation receipt](evidence/rt-fixture-validation.json) | Actual software checks, seven deliberate-regression checks, source identities, documentation checks and unperformed work. | Passing offline arithmetic is not native qualification or a performance result. |
| Existing [20 investigations](08-twenty-external-investigations.md), [community cases](13-community-driven-execution-plan.md) and [vendor/cloud guides](14-ray-tracing-quality-and-delivery-plan.md) | Retained and linked to the same implementation decisions. | They are not a request for more collectors or twenty SDK integrations. |

The code lives outside `app/` under `research/performance/graphics_handoff/`. Run the actual new check from the repository root:

```sh
python3 -B -m unittest discover -s research/performance/graphics_handoff -p 'test_rt_fixture_reference.py' -v
```

The prior 38-test DRS reference is unchanged; its command now selects `test_drs_reference.py` explicitly so the two focused suites retain distinct scope. Its historical result was not rerun merely because RT documents changed.

## 2. Exact-engine findings that change the first implementation

These findings are tied to inspected source at the pin. None is reported as a reproduced GPU crash, validation error or frame-time regression.

| Finding | Source evidence | Required response |
| --- | --- | --- |
| **BLAS reference uses the backing-buffer address.** | The [Vulkan instance writer](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/drivers/vulkan/rendering_device_driver_vulkan.cpp#L6470) assigns `buffer_get_device_address(blas_info->buffer)` to `accelerationStructureReference`. Khronos requires the AS address obtained through `vkGetAccelerationStructureDeviceAddressKHR`; a bottom-level AS address may differ from its buffer start. The pinned driver/header do not expose that query entry point. | Load the actual AS-address function; after successful BLAS creation query, validate and cache its address before returning the ID. The void instance writer uses that cache. Keep native AS/storage alive; recreate the address when recreating the AS. A stock hit on one device does not prove a portable contract. |
| **Creation errors can be hidden from the caller.** | The pinned [creation helper](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/drivers/vulkan/rendering_device_driver_vulkan.cpp#L6499) returns `void`, dereferences the new buffer without a local allocation check, and can return after failed native creation while BLAS/TLAS callers still return their allocated wrapper. | Propagate allocation/creation failure through both callers; propagate BLAS address failure before its ID becomes visible. Clean up partial ownership in a verified order. Test forced failures and actual engine errors rather than accepting an apparently valid RID. |
| **Repeated builds of the same TLAS may overlap instance input.** | In pinned [`tlas_build`](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/servers/rendering/rendering_device.cpp#L539), a new mapped buffer's first write uses offset zero but leaves `used_size` zero. A second build of that same TLAS in the same frame can reuse it before the GPU consumes the first. This concern is not about two separate TLAS objects. | First witness: one build before completion. Before relying on multiple queued builds, reserve the first consumed range and verify range arithmetic, failure and retirement. Use two different queued transform/ID descriptions and distinct output witnesses; a second CPU-blocking build alone cannot expose the suspected overlap. |

The authoritative address contract is in the [AS-instance reference](https://docs.vulkan.org/refpages/latest/refpages/source/VkAccelerationStructureInstanceKHR.html), [AS-address query reference](https://docs.vulkan.org/refpages/latest/refpages/source/vkGetAccelerationStructureDeviceAddressKHR.html), and [acceleration-structure specification](https://docs.vulkan.org/spec/latest/chapters/accelstructures.html), including build VUID `vkCmdBuildAccelerationStructuresKHR-pInfos-12281`. The proposed corrections must be reviewed and compiled in an exact-pin-based source tree; no editor getter or release template is silently upgraded here.

Two additional constraints make the recipe less likely to produce false success. RD's enum check does not establish AS vertex-format support: inspect the actual physical device's `VkFormatProperties2.formatProperties.bufferFeatures` for `VK_FORMAT_FEATURE_ACCELERATION_STRUCTURE_VERTEX_BUFFER_BIT_KHR`, through a verified native seam. A texture-format query is not equivalent. Also, the pin's vertex/storage creation paths ignore `_buffer_initialize`'s returned error. The fixture therefore creates empty buffers, checks explicit `buffer_update` calls outside command lists, checks engine errors, and requires a changed output sentinel. These are source-derived precautions, not observed upload failures.

The existing query-only/SBT concern remains separate. Initially require query **and** ray-tracing-pipeline capability, a valid minimal pipeline and a genuinely allocated/initialized SBT range. Safe capability inspection and negative checks can use the stock pin; the positive portability witness depends on the source corrections above. Do not call an unavailable pipeline entry point or invent a nonzero SBT range to make validation pass. The [native work order](ray-tracing/03-vulkan-fixture-work-order.md) gives the exact allocation and cleanup sequence.

## 3. Why the small reference is discriminating

The [case data](../../../research/performance/graphics_handoff/rt_fixture_cases.json) is hand-specified separately from the evaluator. A raised identity triangle gives t=2 and custom ID 7; transformed near/far instances give t=6/10 and IDs 66051/73. The far instance is listed first. A mask selects only the far instance; a non-unit direction gives t=3 while physical distance remains 6 metres. A tilted triangle makes the nonuniform local Y scale observable: correct t=6.75, versus 6.25 if that scale is ignored. A small separate blocker tests whether an excessive receiver-origin offset deletes a relevant nearby occluder. These answers challenge integration choices, not just setter/getter behavior.

Inputs are rounded to binary32, matching the fixture's declared GPU inputs. The reference then uses exact rational affine/plane/barycentric arithmetic and nearest ordering; output numbers are float64 approximations. Independent review found that the first float64-only draft could misclassify exact non-axis endpoint, edge and equal-distance cases. The retained regression cases now correctly raise `AmbiguousFixture`. This deliberately strict acceptance domain excludes those exact boundaries; it does not claim that all Vulkan edge behavior is unspecified. It also does not model GPU rounding or derive a universal native epsilon. Declare a float32 tolerance for the bounded interior corpus before the native run, using the [Vulkan traversal contract](https://docs.vulkan.org/spec/latest/chapters/raytraversal.html).

For lighting, the ideal reference separates ambient, emission, already-treated other lights, unshadowed Sun diffuse and unshadowed Sun specular. It applies effective selected-sun visibility and cloud transmission once to both Sun components. Full blockage leaves the independent non-Sun contribution intact. Partial shadow opacity and fade-to-lit are tested. The old raster value is recorded as future adapter context but deliberately not consumed by this pure function; therefore these tests alone cannot prove that a native shader replaced the raster term correctly.

The pinned Forward+ shader unpacks eight-bit shadow visibility, applies opacity and its blur policy before `light_compute`. The ideal reference does not implement that packing, the BRDF, exposure or final-image processing. The native image test must define its replacement seam and tolerances, then verify raw visibility, direct light components and visible output separately. The existing raster-only `test_shadow_energy.gd` is a reusable control, not an RT result.

An independent read-only numerical review reran the 26 tests and injected seven isolated defects. Every mutation caused assertion failures, with no import/syntax errors:

| Deliberate defect | Failed assertions/subtests |
| --- | ---: |
| Ignore instance masks | 3 |
| Return first candidate rather than closest | 5 |
| Truncate custom instance index to 16 bits | 5 |
| Normalize direction without preserving the ray parameter | 5 |
| Apply cloud transmission twice | 5 |
| Drop direct Sun specular | 5 |
| Ignore the transform's local Y scale | 1 |

These counts are checks of the final reference's sensitivity to those faults, not code-coverage percentages or native renderer evidence. The receipt binds them to the reviewed module/data/test hashes. No broader fuzzing or new framework is needed before the next implementation decision.

## 4. Next reviewable work packets

| Sequence / owner | Concrete change | Evidence and stop condition |
| --- | --- | --- |
| **Prerequisites · GDU/VQ** | Review and build the [prepared exact-pin patches](../../../research/performance/graphics_handoff/vulkan/README.md), including address/error handling and repeated-build input. Keep matching editor/templates and patch identities. | Focused source controls and both changed translation units now pass; linking, native failure paths and device behavior remain pending. An unbuildable or unbounded dependency closes the two-day feasibility decision as blocked/defer. The patches are research artifacts, outside production builders. |
| **Geometry witness · VQ/GDU** | Extend the existing graphics-test home with one actual local-RD Vulkan fixture. Use 36-byte vertex data, 48-byte push data, a 32-byte sentinel/result buffer, real SBT ownership and the recorded cases. | Verify device/format/compile/build/lifetime and hit/miss/t/custom/primitive fields on the actual target. Local submit/sync/readback is permitted only for this diagnostic; no per-frame CPU wait enters flight. No device is unavailable, never a pass. |
| **Selected-sun image · VQ** | Once geometry works, extend the existing shadow-energy test with one bounded opaque receiver/caster and the actual designated-Sun engine hook. Replace its raster visibility and preserve opacity/fade, diffuse/specular, cloud and other lights. | Raw and integrated answers agree within declared tolerances; include an off-camera caster, moving rigid caster, ambient/emission and second directional light. No image or useful defect/headroom means retain raster. Show the useful fixture and cost by the existing two-week checkpoint or stop. |
| **Flight decision · VQ/PT/DT** | Only after that fixture, justify the remaining scene producer/material/temporal coverage and use the existing 1080p comparison/capture tools. | Complete relevant normal-flight geometry, masks, alpha/deformation and resource lifetime; pilot readability and measured cost must pass. Proposed incremental GPU p95 ≤2 ms / allocated resources ≤128 MiB are ceilings, with actual headroom stricter. Missing relevant coverage keeps the whole viewport raster. |

A first successful witness is specific to its GPU/driver/backend/engine. NVIDIA and AMD need their own native rows; Windows/Linux and export packages do not inherit another row's result. Apple remains under its separate Metal owner and existing diagnostic evidence. Do not attempt denoising, soft multi-sample lighting, RT lake reflections or a settings toggle merely to make an incomplete witness look like a shipping feature.

The next engineer should start with the **address/error prerequisite**, then the already specified witness. There is no new collector to implement first. Keep the existing checked runner, test-queue admission, graphics capture and frame diagnostics. When native tests own these independent answers, consolidate them and retire the duplicate Python reference. Rendering remains an observer of accepted presentation state and `sim_clock`; no change to 240 Hz float64 physics, inputs or flight data is involved.

## 5. Initial fixture evidence boundary

The initial [fixture receipt](evidence/rt-fixture-validation.json), published at `4c00738feac422ad8ed1bde23faf442201f5b3c3`, recorded no engine patch build, shader compilation, native Vulkan query, validation-layer run, GPU address observation, rendered comparison, SDK integration, flight benchmark, physical latency test or export qualification. It remains unchanged as historical evidence. The later compilation below is a separate result and does not retroactively change that receipt.

## 6. Prepared engine patches and compiled controls

Continuation from `4c00738feac422ad8ed1bde23faf442201f5b3c3`, 2026-11-15 America/Bogota. The [patch home](../../../research/performance/graphics_handoff/vulkan/README.md) now contains two actual diffs against the exact engine pin: address/creation ownership and TLAS input reservation. They change three upstream source files, with 80 insertions and 27 deletions. This is implementation preparation outside `app/` and the production engine builders; no installed engine or runtime default is changed.

The implementation review found and addressed three closely related hazards in addition to the original address/range findings: a failed native create can leave an undefined output handle, a 64-bit scratch requirement can narrow into a 32-bit interface, and a rejected rebuild can erase a previously valid TLAS's BLAS dependencies. The new code owns a native handle only after successful creation, rejects unrepresentable padded scratch sizes, and validates incoming instances before replacing dependencies. Two small extra-GPU-tracking buffer cleanup paths were also corrected; they apply to non-AS buffers and are part of the stated patch scope.

**Actual new evidence:** both patches passed clean-source application checks and independent byte comparison; six focused test methods passed with 19 positive executable cases and five original-source runtime-negative cases; both complete changed Godot translation units compiled through SCons 4.10.1 and GCC 14.2.0 on Linux with the RT branch enabled. The compiled controls extract real functions and a real allocation block but use explicit resource/native-call/container stand-ins. Their simulated retirement case is not a fence observation. Full translation-unit compilation uses the real headers, but no complete editor/template was linked and no Vulkan device was run. Exact identities and results are in the [new receipt](evidence/vulkan-prerequisite-validation.json).

The read-only `main` checkpoint advanced to [`cfb5acd5cfbcbf83f7f9220116c67fa082e8f27b`](https://github.com/bultodepapas/OpenRCsimulator/commit/cfb5acd5cfbcbf83f7f9220116c67fa082e8f27b) during this continuation. Relative to the previous checkpoint it adds ClearView import/creator work and Extra 300s appearance/model changes. Inspected rendering, engine getters, graphics-build/patch tools, test-queue and CI paths remain unchanged across those checkpoints. Aircraft/material/workload identities must still be frozen again for a native flight comparison. This branch does not merge the newer application changes.

The next concrete step is a matching linked experimental editor/template and the known-answer native fixture. Physical-device limits, actual instance-buffer address alignment, zero-capacity behavior, graph/scratch ordering and GPU retirement retain explicit gates in the patch home. The same M0/M4 deadlines apply. No new collector, denoiser, settings option or wider renderer project is required before that decision.
