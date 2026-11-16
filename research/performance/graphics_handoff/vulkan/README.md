# Pinned Vulkan prerequisite patches

2026-11-15, America/Bogota · Prepared under existing VQ/GDU M4 on `audit/graphics-performance-technologies-2026-11-15`, from OpenRC commit `4c00738feac422ad8ed1bde23faf442201f5b3c3`. These are actual, optional research patches for **Godot `cafc17a192acf67903910a68aeb3c076c0907a4b`**, the project's official `4.8.beta2.official.cafc17a19` source pin. They are not installed by a production builder, getter or launcher. The application baseline remains `e488ef7653e8dd0f0a2e7db18e396bb4da0aaccc`.

**Status:** both patches apply to the verified pin, both changed C++ translation units compile through Godot's SCons with real headers, and the focused compiled controls pass. A linked editor/template pair, actual Vulkan execution, selected-sun image and flight qualification remain pending. The [validation receipt](../../../../docs/research/graphics-performance-2026-11-15/evidence/vulkan-prerequisite-validation.json) records those distinct results. The [native fixture work order](../../../../docs/research/graphics-performance-2026-11-15/ray-tracing/03-vulkan-fixture-work-order.md) still controls the next device experiment.

## What the patches change

| Patch | Changed upstream source | Implemented behavior |
| --- | --- | --- |
| [0001 · AS address and creation](0001-as-address-and-creation.patch) | `drivers/vulkan/rendering_device_driver_vulkan.cpp` and `.h` | Loads the AS-address entry point; queries and caches the actual BLAS address before returning its ID; propagates recoverable storage/native-create/address failures; guards scratch-size narrowing; releases owned resources on failure. Repairs two allocation/bind failure cleanup paths in the extra-GPU-tracking branch of `buffer_create`. |
| [0002 · TLAS instance reservation](0002-tlas-instance-reservation.patch) | `servers/rendering/rendering_device.cpp` | Rejects non-TLAS targets and invalid incoming BLAS references before changing dependencies; checks instance-buffer arithmetic; reserves the first written range; uses subtraction-based available-space checks. |

The patch pair changes **three source files, 80 insertions and 27 deletions**. Public RD signatures, query-only/SBT behavior, engine defaults and application physics are unchanged. The private creation helper now reports success/failure; existing public RD wrappers reject an invalid driver ID before publishing an RID.

### Address and failure ownership

The old instance writer uses a backing-buffer address. Vulkan requires the AS address obtained from [`vkGetAccelerationStructureDeviceAddressKHR`](https://docs.vulkan.org/refpages/latest/refpages/source/vkGetAccelerationStructureDeviceAddressKHR.html), which may differ. The patch stores that result in the live native object's metadata. A recreated or compacted destination AS needs its own query; caching does not extend resource lifetime.

Native creation writes into a **local** handle. The patch takes ownership only after `VK_SUCCESS` and a non-null result, so failure cannot turn an undefined output value into a handle to destroy. A later zero address frees the successfully created object and its storage, then returns failure. The conservative cleanup order is AS, backing buffer, wrapper; this is not a claim that the previous order alone violated Vulkan. Actual pending GPU uses must finish before either object is released. See [runtime error outputs and object lifetime](https://docs.vulkan.org/spec/latest/chapters/fundamentals.html).

The extra-GPU-tracking cleanup is a small but broader change: its allocation failure now destroys the already-created buffer, and its bind failure also releases the successful VMA allocation. This branch serves non-AS buffers too. It needs native qualification alongside the AS path. Godot's paged host allocator and container-allocation OOM behavior remain upstream; these patches do not promise general host-OOM recovery.

The scratch interface stores a 32-bit size although Vulkan reports a 64-bit value. The patch rejects a padded size outside that interface's range before allocation, rather than silently narrowing it. The boundary check uses synthetic values in software; no multi-gigabyte allocation was attempted.

### Rejected rebuilds preserve the previous dependency set

The new prevalidation pass matters independently of the reservation correction. Consider a valid TLAS using BLAS A, followed by a requested rebuild containing valid B and then an invalid instance. The old loop removes A's dependency before discovering the invalid instance, without queuing a replacement build. The new pass rejects that request before changing the old input or dependency set. A valid request then follows the existing render-thread-owned update path.

The first input range now counts as consumed. A second same-frame build uses a later range or another buffer, rather than overwriting the first range before consumption. This is CPU bookkeeping correctness. It does not prove Vulkan barriers, scratch reuse, base-address alignment or GPU completion.

## Run the focused controls

Requirements: Python 3.10+, Git and a C++17 compiler; the recorded run used Python 3.12 and GCC 14.2.0 on Linux. Start from the OpenRC repository root. Supply a **pristine** pinned Godot source tree; the three complete source files are checked against fixed SHA-256 values before use:

```sh
OPENRC_GODOT_SOURCE_DIR=/absolute/path/to/pristine-godot-cafc17a19 \
  python3 -B -m unittest discover \
  -s research/performance/graphics_handoff/vulkan \
  -p 'test_prerequisites.py' -v
```

The test copies those files into a disposable directory, checks and applies the two patches there, and reuses the existing [balanced C++ extractor](../../../../tools/graphics/metalfx/test_engine_patch.py). It removes inherited Git directory/work-tree overrides, disables global/system Git configuration for patch application, and uses checked whitespace, bounded subprocesses and cleanup even if setup fails. It does not patch the supplied source tree or launch Godot.

The [Python controls](test_prerequisites.py) and [C++ stand-ins](controls.cpp.in) execute actual extracted functions, not a separately rewritten implementation. The final run passed **six test methods**, **19 positive executable cases**, **five original-source runtime-negative cases**, and a changed-source hash rejection check. The same run used deliberately invalid `GIT_DIR`/`GIT_WORK_TREE` values to check application isolation.

| Control | Independent expectation |
| --- | --- |
| AS versus backing-buffer address | Give the two queries different values; the written instance must contain the AS value. Inactive instances keep zero. |
| Missing entry points and creation failures | No call through an unavailable function; failed storage/native creation/address resolution returns an invalid driver ID and releases only successfully owned objects. A native-create failure deliberately poisons its output. |
| Public RD wrapper | Actual extracted BLAS/TLAS wrapper functions reject failed driver results before the fake owner creates an RID; successful paths create one. |
| Scratch range | Oversized or invalid alignment inputs reject; the last representable padded size succeeds in the mocked allocation path. |
| Same-TLAS input | Two queued descriptions preserve different IDs/transforms in nonoverlapping byte ranges. |
| Rejected rebuild | A valid A-dependent TLAS survives a rejected B/invalid request with both dependency directions and original bytes intact. |
| Create/map failure and frame age | Failed new input allocation/map preserves old state; a simulated retired frame reuses the expected range. Frame counters here are not GPU-fence evidence. |
| Tracked-buffer failure block | Failed allocation destroys the successful buffer; failed bind destroys the buffer and frees the successful allocation, once each. |

For the negative controls, the original address writer, original TLAS build function, and original tracked-allocation block are compiled into otherwise equivalent controls. They fail the expected runtime assertions for address selection, range overlap, dependency loss, allocation cleanup and bind cleanup. A compiler error is not accepted as proof that a behavioral defect was caught.

**Control limits:** Vulkan types/layout, VMA/native calls, resources, containers and RID ownership are stand-ins. The BLAS factory/wrapper control uses empty geometry to isolate creation behavior. The tracked-allocation test executes the actual changed block inside a stand-in enclosing function. These are not ABI, geometry-validity, real allocator, thread-safety or GPU tests. Real struct/header compatibility is additionally checked by the full translation-unit compilation below; GPU behavior still needs the native fixture.

## Exact-source compilation performed

A separate, disposable full Godot checkout was fetched at the exact commit. Its three relevant pristine files matched the earlier inspected hashes. Both patches passed `git apply --check --whitespace=error` and were applied there. The following **two complete translation units** then compiled successfully through SCons 4.10.1 / GCC 14.2.0, including their real headers and required generated/third-party dependencies:

```sh
python3 -m SCons -j2 \
  platform=linuxbsd target=editor dev_build=yes \
  debug_symbols=no optimize=none vulkan=yes wayland=no accesskit=no \
  bin/obj/drivers/vulkan/rendering_device_driver_vulkan.linuxbsd.editor.dev.x86_64.o \
  bin/obj/servers/rendering/rendering_device.linuxbsd.editor.dev.x86_64.o
```

Run this command from the **patched disposable Godot checkout**, with SCons 4.10.1 available to Python. The recorded environment installed SCons in a separate tool directory and supplied it through `PYTHONPATH`. `wayland=no` and `accesskit=no` describe this compile configuration; they are not product changes or platform qualification. The Linux configuration compiled the RT-enabled branch, confirmed by the source guard and new address-query/failure strings in the object. Both ELF object hashes, exact compiler commands, changed-source hashes and log identity are in the receipt. No object or engine source snapshot is committed to OpenRC.

This was targeted compilation, **not a linked editor, template, release build or ABI validation run**. Windows and exported packages need their own build and runtime evidence. Do not run the native fixture with the unrelated Godot 4.6.3 installation available in the research environment.

## Remaining gates and the next step

These patches are sufficient preparation for the next bounded native investigation; they do not establish a generally correct or qualified RT backend. Keep the first fixture at one or two nonempty instances and one build before completion until the following constraints are checked:

- **Device limits:** the new arithmetic check in `tlas_build` is separate from the required physical-device `maxInstanceCount` check before the earlier Vulkan build-size query. The existing creation route does not gain that limit validation here. See [the Vulkan size-query contract](https://docs.vulkan.org/refpages/latest/refpages/source/vkGetAccelerationStructureBuildSizesKHR.html).
- **Input address and formats:** verify the actual instance-buffer device address plus offset is 16-byte aligned, and query real AS vertex-format support. A 64-byte instance stride or an aligned offset alone does not prove the base address. See [the AS build specification](https://docs.vulkan.org/spec/latest/chapters/accelstructures.html).
- **Zero capacity:** the inherited zero-capacity TLAS / zero-byte instance-buffer path remains outside this fixture and is not repaired by the reservation change.
- **GPU ordering and lifetime:** validate BLAS→TLAS→query dependencies, repeated-build scratch ordering, in-flight input retention, fences, partial submissions and teardown on actual hardware. The simulated frame-age test proves only the existing bookkeeping rule.
- **Query-only devices:** the existing real-pipeline/SBT prerequisite is unchanged. Require both capabilities for the initial positive witness; use safe negative cases for unavailable paths.

The next engineer should link a matching experimental editor/template pair from this exact candidate, then execute the known-answer Vulkan fixture under validation layers on the admitted NVIDIA or AMD host. Reuse the [14 geometry/five energy cases](../rt_fixture_README.md), existing checked runner and host admission; then integrate one selected-Sun image only after the geometry witness passes. The [existing two-day feasibility and two-week useful-fixture checkpoints](../../../../docs/research/graphics-performance-2026-11-15/15-ray-tracing-fixture-handoff.md#4-next-reviewable-work-packets) remain controlling. This work adds no measurement collector or product option.

The patches retain their exact upstream paths and provenance. Godot's [MIT source license](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/LICENSE.txt) and matching build/source identities remain part of any later engine delivery.
