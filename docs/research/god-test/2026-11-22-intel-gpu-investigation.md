# Intel UHD 630 performance investigation — 22 November 2026

Owner: VQ-07h-A2-R1 (renderer/workload), PT1h-R15 (measurement) and GOD-12/13
(tour evidence). Source reviewed: `91d7d6ddcb2182422a496036825e9113f82d2433`.
Branch: `investigate/intel-gpu-performance-2026-11-22`.

This is a source, retained-evidence and primary-source investigation. **No new
Intel benchmark was run for this branch.** The reviewed code already contains
GFX-IGPU-01/02. Their earlier results are not improvements made by this branch.
The [experiment protocol](2026-11-22-intel-gpu-experiments.md) specifies work on
the existing Intel installation; the [evidence ledger](2026-11-22-intel-gpu-investigation.json)
retains input hashes, transcribed measurements, calculations and verification.
The [automatic-graphics plan](../../plans/automatic-graphics.md) remains the
product policy owner.

Follow-up: [sixteen render-internals investigations](2026-11-22-intel-render-internals.md)
extend the source audit on this branch with auxiliary-target scheduling,
vegetation/shader costs, pinned-engine readback paths and loading/UI candidates.
They add hypotheses and acceptance checks, not new Intel benchmark results.

## 1. Engineering conclusion

The retained evidence supports **a rendering workload that exceeds this UHD
630's budget, compounded by specific test-environment problems**. It does not
establish a defective GPU, a general Intel driver failure, or a PCI-passthrough
mistake. The measured path is Linux LXC with direct access to the Intel render
node, Mesa iris/ANV and a headless Weston compositor. It is not the separate
Linux VM that renders in software.

The newest result matters more than the original alarming screen. With the
already implemented Automatic bundle, megatron's reported circuits ran at
**47.4 / 38.0 / 38.2 FPS**, with simulation/wall time **1.00**, for the Stik, jet
and Corsair. The reported Weston/window configuration is 1920×1080 with 75%
bilinear internal 3D scale, nominally **1440×810**. Actual drawable and internal
pixels were not independently verified from raw receipts. This does not
establish native-1080p 3D. The jet and Corsair case data were
reported valid; the Stik case remained ineligible at first Home. Each is one
exploratory pass. No complete, repeated, presentation-qualified result follows
from this table. [E2]

Three questions therefore have different answers:

| Question | Supported answer | Remaining uncertainty |
| --- | --- | --- |
| Is Proxmox sending this benchmark through an emulated/software GPU? | The retained rendered studies identify the UHD 630 with iris/ANV and a directly shared DRM node. | Fresh receipts must still verify the actual adapter and compositor on each launch. |
| Is the environment completely innocent? | No. The reports identify ALSA-null audio starvation, Wayland cleanup/suspension problems, and memory-pressure stops; host sharing and cooling are additional concerns. | Their contribution to each steady-flight result has not been isolated in one synchronized experiment. |
| Is the GPU simply too slow? | Native-resolution, antialiased Forward+ workloads overwhelm this configuration; a lower-pixel Compatibility workload already runs in real time. | The remaining software headroom, driver-version effect, and exact limiting GPU unit are not quantified. |

**Implementation priority:** preserve the working Automatic profile; establish
an explicit, repeatable Intel baseline; reduce the ground-heavy Home workload;
separate first-use compilation from recurring loading work; then investigate
Mobile HDR and a controlled Mesa comparison if those can change a decision.
All tests in this investigation use the existing hardware.

## 2. What evidence was actually available

| ID | Retained source | What it establishes | What this review could not recheck |
| --- | --- | --- | --- |
| E1 | [20 November UHD comparison](../visual-quality-implementation/VQ-07/igpu-uhd630-2026-11-20/README.md) | Three interleaved warm scripted runs per renderer on megatron, 1080p, High scene/grass, Mesa 25.0.7; Frigate stopped. | Raw `run.json` and `engine.log` are referenced at `U:\OpenRC\tmp\igpu-bench\`, outside Git. Their frame series, adapter receipts and validity cannot be independently re-reduced here. |
| E2 | [22 November Intel tours and ablations](2026-11-22-linux-uhd630-comparison.md) | Later real-flight screens, host investigations, audio/display fixes, minimal-profile experiments and the implemented Automatic profile. | The report is retained; its raw campaign/trace bundle is not present with it. Headline valid/ineligible labels are reported outcomes, not new verification. |
| E3 | [21 November stutter map](2026-11-21-stutter-map.md) | Native-backend M1 and Intel tour observations, with phase failures and different source identities. | Raw runs/frame streams are outside Git; the cross-machine configurations are not matched. |
| E4 | [M1 graphics ladder](../desktop-delivery-investigations/DT-MAC-03b/README.md) | Earlier M1 option costs, source/backend identity, external mirrored 1080p, and substantial thermal/remote-capture confounding. | Different source, GDScript physics, route and measurement population from E2; no valid Intel/M1 speed ratio. |
| E5 | [PRIMIS plan](../../plans/primis-intel-test-host.md) and [operating guide](../../tools/primis-testlab.md) | Intel hardware-rendering admission and historical functional-lane memory constraints. | Current deployment/configuration is not implied by dated documentation; its memory limits changed in later E2 runs. |
| E6 | [Current source and tools](../../../tools/godtest/PERFORMANCE_TOUR.md) | Implemented renderer/settings selection, timing semantics, native identity and resource-coverage requirements. | A prepared plan is not a hardware execution receipt. |

Older committed logs mentioning the i5-10500 were also inspected, including
[ground-contact recording](../ground-contact/E4a/record.log) and
[atmosphere timing](../atmosphere/M5-ATM-2/cost-baseline-calm.json). They record
physics/checkpoint or tick-cost evidence, not this Intel GPU campaign. A CPU
model match is insufficient to promote those files into GPU evidence.

The private HomeLab CT206 creation record was cross-checked read-only against
E1's render-node/Mesa/compositor description. Private addresses, credentials and
guest inventories are not reproduced here. The current workspace has no pool
connector; `testctl.py pool hosts` fails because its local configuration is
absent. No host was contacted or reconfigured, and no service was stopped.

## 3. Quantitative reading of the retained results

### 3.1 The older scripted High workload

Values below are **medians of the three reported run medians**, not newly pooled
per-frame percentiles. FPS is `1000 / median frame milliseconds`, not an
arithmetic mean of observed FPS. [E1]

| Renderer | Frame p50, ms | Reciprocal p50 rate | GPU-poll p50, ms | Reported render CPU p50, ms | Engine memory counter, MiB |
| --- | ---: | ---: | ---: | ---: | ---: |
| Compatibility / iris | 47.8 | 20.9 FPS | 46.2 | 1.5 | 737 |
| Mobile / ANV | 58.0 | 17.2 FPS | 56.3 | 0.5 | 1,046 |
| Forward+ / ANV | 76.0 | 13.2 FPS | 74.1 | 0.8 | 1,234 |

Mobile's reported GPU median is 21.9% higher than Compatibility; Forward+'s is
60.4% higher. The exact percentages differ slightly from E1's rounded summary
because this table explicitly chooses the median of run medians. Lower CPU
submission time and fewer draws did not make Mobile faster overall.

The GPU/frame agreement is strong aggregate evidence of a GPU-heavy workload.
It is **not a 97% utilization measurement**. Godot's viewport GPU poll can be
an earlier reading, with no completed-frame identity or age. The current
[frame diagnostic contract](../../../research/performance/README.md#cpu-gpu-and-memory-diagnosis)
and [bridge guide](../../../tools/debug/README.md#frame-pacing-and-stutter-captures-pt1h-r15)
preserve that limit. Engine video-memory counters are allocation estimates,
not physical residency, free VRAM, process RSS or total container memory.

The slower warm-up with Frigate active is not a valid paired estimate of
Frigate's cost: warmup/cache/order and workload sharing changed together.

### 3.2 Later flight results and the simulation floor

| megatron workload | Stik | Jet | Corsair | Interpretation |
| --- | ---: | ---: | ---: | --- |
| Forward+ Medium, fixed tour | 11.4–12.4 FPS | 8.3–8.7 FPS | 8.0–8.4 FPS | Heavy fixed workload; simulated time falls behind wall time. |
| Compatibility Low, before the complete reduced-pixel bundle | 22.8 FPS | 17.7 FPS | 17.5 FPS | Circuits complete, but jet/Corsair sim/wall is 0.88. |
| Automatic bundle, Compatibility Low, 75% internal scale | 47.4 FPS | 38.0 FPS | 38.2 FPS | Reported sim/wall 1.00 for all; first Stik Home still ineligible. |

These rows change multiple settings and sometimes host setup. They demonstrate
different workable configurations; they do not measure a single optimization's
speedup. Full identities and limits remain in E2.

[project.godot](../../../app/project.godot) fixes physics at 240 Hz with at most
12 physics steps per rendered frame. The ideal catch-up capacity is
`12 × render_fps` ticks/s: below **20 FPS**, even fully consuming that allowance
cannot sustain 240 ticks/s. At 9 FPS the ceiling is 108 ticks/s, or 0.45 real
time, consistent with the reported slow motion. Twenty FPS is a necessary
theoretical floor under these settings, not a smoothness or real-time guarantee
when hitches/other work intervene. Keep the 240 Hz model; measure sim/wall and
frame tails instead of masking the problem by changing the clock.

### 3.3 What resolution scaling can and cannot promise

At 75% of each dimension, pixel count is `0.75² = 0.5625`: 43.75% fewer internal
pixels. The ideal throughput multiplier for a completely pixel-proportional
workload is `1 / 0.5625 = 1.778`. E2's frozen minimal Compatibility flight moved
from 26.2–26.5 to 40.0 FPS, approximately 1.51–1.53×. That is consistent with
substantial pixel cost plus work that does not scale with resolution; it does
not isolate bandwidth from ALU, filtering or fill rate. Native-resolution UI
and output remain distinct from internal 3D quality.

Home has its own [adaptive budget](../../../app/render/home_render_budget.gd).
It can multiply the player's native/bilinear scale by 0.85 or 0.7 during a
visit. Therefore a saved 75% setting alone does not establish Home's actual
internal dimensions. Record the runtime viewport and budget state during each
phase; do not compare a dynamically reduced Home against a fixed reference.

## 4. Proxmox, drivers and the physical Intel configuration

### Direct rendering is present; resource isolation still matters

The relevant path is Godot → Mesa in the container → shared DRM render node →
host i915 → UHD 630, plus Weston and, in later tests, Xwayland. LXC shares the
host kernel; it does not emulate a GPU or run a separate guest graphics kernel.
The host still schedules CPU, accounts memory and serves other GPU clients.
Proxmox documents both direct host-resource access and cgroup isolation. [P1]

Consequently VM-specific CPU models, Q35/OVMF, PCIe passthrough, virtual display
RAM and IOMMU toggles are not a supported diagnosis for this LXC experiment.
The right evidence is the actual adapter/BDF, DRM-node mapping, Mesa library
versions, compositor renderer, cgroup limits/events and host workload during the
same interval. A valid Intel adapter line excludes a simple software fallback;
it does not prove that the driver is optimal or that the host has headroom.

### Memory capacity, bandwidth and accounting are separate

E2's introductory claim that both hosts use dual-channel DDR4-2667 conflicts
with its later inventory: megatron has 16+4 GB at 2400 MT/s, while PRIMIS has
8+8 GB at 2667 MT/s. Treat the per-host inventory as a correction and reacquire
it with a timestamp before a campaign.

Intel's Comet Lake datasheet describes Flex memory as symmetric interleaved
and asymmetric single-channel zones. If the reported 16/4 GB modules occupy
opposite channels, the capacity split is nominally 8 GB interleaved and 12 GB
single-channel. That does not reveal where a particular GPU allocation resides
or imply a fixed FPS loss. A 4 GB container limit does not constrain its physical
pages to the first 4 GB of DRAM. [P2]

This is a credible contributor, not a demonstrated explanation of the
host-to-host FPS difference. This investigation does not prescribe replacing
memory. It calls for reading the existing topology/speed, reducing unnecessary
application allocations, and measuring memory pressure and traffic.

The older PRIMIS guide describes iGPU memory as outside the CT limit; E2
reports charged `shmem`. Neither should be generalized to every allocation.
Record host `MemAvailable`/PSI, process RSS, and the actual container's
`memory.current`, `memory.stat`, `memory.events`, swap and limits. Shared/file
memory is accounted separately from anonymous process memory; counters can
overlap, so do not add RSS, `shmem` and engine VRAM as independent totals.
Kernel cgroup documentation explains reclaim/OOM events and the categories. [P3]

### Clocks, thermal headroom and competing clients

E2 reports PRIMIS at 1100 MHz, 62–69 °C and 29 W package power. Its statement
that 1100 MHz is both GPUs' maximum needs correction: Intel lists up to
**1.15 GHz** for the i5-10500's GPU. Read actual/requested/max/RP0 values before
classifying 1100 MHz as a cap or throttling. Even the ideal fully
frequency-proportional 1100→1150 MHz increase is only 4.55%, far smaller than
the gap between the old workload and 60 FPS. [P4]

The reported megatron temperature, 92 °C package / up to 94 °C core at 39 W,
was recorded with Frigate alone. It is a strong reason to inspect existing
cooling and retain thermal/throttle counters during a tour, not proof that
the benchmark throttled. CPU, GPU and memory share power/thermal resources.
Maximum frequency also does not establish render-engine utilization. Frigate
can use media/compute resources; capture individual engines and shared-memory
traffic rather than equating its frequency with 3D saturation. [E2] [P5]

### Driver comparison: isolate it, do not assume a magic switch

Mesa 25.0.7 with iris/ANV was hardware-accelerated in the reports. No controlled
same-source version comparison is retained. Thus neither “the driver is bad”
nor “no driver can improve this” is established. A candidate Mesa user-space
build on the same Intel device can be compared with the same kernel, source,
effective graphics, compositor and separately labelled warm caches. Record
the actual loaded library versions; changing an OS image alone is not proof.
Kernel changes affect all containers and belong to a separate operator-owned
experiment only if evidence points there.

Do not force `xe` onto UHD 630; the kernel's Xe platform design begins at
Tiger Lake. Do not change GuC/HuC, GPU minimum clocks, power limits or global
cache policy as speculative FPS fixes. Mesa diagnostic flags, shader-cache
statistics and optional draw-timestamp instrumentation can help attribution;
their overhead belongs in a separate diagnostic run. Their availability must
be checked against the installed version, not inferred from rolling docs.
`mesa_glthread` addresses CPU submission and is a low-priority hypothesis when
the retained render CPU time is already small. [P6] [P7]

## 5. Rendering opportunities in the actual code

### 5.1 Terrain shading: highest-value targeted experiment

The [ground shader](../../../app/render/ground.gdshader) and
[shared grass surface](../../../app/render/grass_surface.gdshaderinc) combine
anti-tiling samples, macro variation, surface masks, near detail, relief, haze
and optional cloud/RC effects. The surface loop is bounded and includes spatial
early-outs; it is not correct to assume every pixel always executes all 32
rectangles. Existing guards/caches must be inspected before proposing another
cache.

E2's exploratory Home ablation reports roughly 30 ms saved by a plain ground
material, while its frozen flight experiment reports only 1.8–3.7 ms. Those
figures are scene/renderer-specific and may include indirect pass work; they
are not additive with MSAA or resolution changes. They justify investigating
Home first, not promising the same flight gain.

Candidate: a bounded Low ground-material variant or a selectively cached static
mask/noise term that preserves runway/mown boundaries, the horizon, night
lighting and readable aircraft contrast. Change one expensive term at a time;
compare the existing shader at identical geometry and resolution. Shader
variants can increase first-use compilation and maintenance, while textures
can trade ALU for bandwidth, memory and seams. Prefer the measured winner.
Intel's **Gen9** guide supports controlling shader/register, texture and
render-target cost; a “quarter throughput for textureGrad” figure from another
GPU generation is not a measured UHD 630 multiplier. [P8]

Lowering [Scene detail](../../../app/render/scene_detail.gd) alone mainly
changes props, tree geometry, mesh LOD and worn-path turf; it does not simplify
all main-ground work. Prop selection can also change ornament collision at the
next world build. Hold scene detail and collision identity fixed when
attributing a material-only change. Preserve detached rendering state and the
accepted simulation clock.

### 5.2 MSAA and internal scale: already effective, record the real state

[AutoGraphicsPolicy](../../../app/render/auto_graphics_policy.gd) already
selects Compatibility, Low detail, MSAA off, projected Low shadows, fewer birds,
no runway meadow, and 75% scale for this recognized weak integrated GPU.
[Reconstruction](../../../app/render/reconstruction.gd) applies the scale with
Native/bilinear reconstruction. Existing saved user overrides are preserved;
an updated installation need not equal a fresh-install benchmark.

The numeric setting is easy to misread: `msaa_3d=2` in `project.godot` is
**Viewport.MSAA_4X**. The technical environment string `OPENRC_MSAA=2` instead
selects **2×**. E2's fixed-tour “2×” label must be checked against its retained
runtime identity, not retroactively changed to 4× from today's source. E1
states “defaults” without an effective-AA receipt in Git. Persist enum and
human sample count together in future evidence.

Use 100%, 85%, 75%, 67% and 50% as controlled existing scale choices at 1080p
output; begin with the current 75% baseline. Do not promise 60 FPS from a pixel
formula. Bilinear softness and distant-aircraft readability are acceptance
criteria. FSR/TAA/DLSS/MetalFX are different algorithms and capability paths;
they do not make a native-scale comparison or a free speedup.

### 5.3 Mobile's HDR buffer is an unresolved tradeoff

[viewport_color.gd](../../../app/render/viewport_color.gd) explicitly sets
`use_hdr_2d=true` on Mobile to preserve faint night values. Godot documents
that this changes Mobile's normal packed 32-bit color target to RGBA16F,
increasing affected color-buffer traffic; the pinned engine's
`RenderSceneBuffersRD::get_base_data_format()` and Forward Mobile code support
this reading. Twice the bytes per affected color surface does not mean twice
total bandwidth or half the FPS. [P9] [P10]

A same-Intel Mobile HDR-on/off experiment is worthwhile after establishing
the Compatibility baseline. It must include day/night captures and the
existing linear-HDR readback contract. Globally removing the setting would
discard the reason it exists. The old renderer ranking does not prove this
buffer caused the ranking, and “Mobile” is not a universal fastest-iGPU mode.

### 5.4 Loading and preparation are a separate backlog

E2 identifies three distinct mechanisms: ALSA-null busy mixing during loading,
cold OpenGL program compilation, and recurring Home scene/resource work. The
runner's [audio_output()](../../../tools/godtest/runner.py) now selects Dummy
when Linux has no accessible playback device. Keep this existing fix in the
baseline; muted audio is not the same as disabling mixing.

[graphics_preparation.gd](../../../app/render/graphics_preparation.gd) adds
messages and per-stage identity markers. It is an explanation of a wait,
not an asynchronous compiler or proof that every future shader is cached.
The earlier ALSA-dominated cold/warm comparison did not rule out the later
reported shader stalls. Isolate process state, Godot's cache, Mesa's cache and
OS/import-cache state in separate experiments. Never erase shared caches to
manufacture a cold run.

Godot's pipeline-precompilation/ubershader guidance excludes Compatibility.
Its legacy visible-material warmup can move work into loading, but cannot
guarantee a responsive loading frame during a synchronous driver compile.
For recurring stalls, split scene/resource construction only after timing
the actual blocking stage. Report both time-to-ready and longest frozen frame;
a preparation label or shorter average loading time does not settle either.
[P7] [P11]

### 5.5 Calibration and telemetry need explicit limits

The [first-flight calibration](../../../app/render/auto_calibration.gd) can
adjust scene detail and reject Forward+, but cannot reduce render scale or
step below Low. Its 20-second sampling window requires 300 positive GPU polls,
so a very slow run may produce no verdict. Unknown/family-only GPU matches
also keep 100% scale intentionally. A future measured scale fallback needs
settling, reliable timing/coverage, user-override preservation and visual gates;
it should not directly follow possibly stale viewport GPU samples.

The current [GPU sampler](../../../tools/godtest/hardware.py) has NVIDIA,
Apple and AMD backends, **no Intel utilization backend**. Missing data remains
unavailable, not zero. An Intel extension should reuse the existing bounded
owner-clock/coverage machinery, carry DRM device identity and per-engine scope,
handle permissions/missing counters, and demonstrate observer overhead.
External Intel observations do not automatically satisfy GOD TEST's current
monitoring validator. [E6] [P5]

## 6. Why the M1 result is plausible

“Both are integrated and reasonably recent” is not a graphics equivalence.
The Intel device is UHD 630, a Gen9-family design, not Iris Xe or Arc. The
retained M1 is a 7-core Apple GPU with a native Metal path. Apple describes
its tile-based deferred architecture and on-chip tile processing; Godot's
Mobile path is designed around different tradeoffs from Compatibility and
Forward+. This makes differing sensitivity to color-buffer traffic, antialiasing
and passes plausible. It does not assign a numeric advantage to the M1. [P8] [P9] [P10] [P12]

The newer M1 tour reports 97 / 79 / 74 FPS in its Stik/jet/Corsair circuits,
but also loading and menu freezes, and lower Home FPS. It used a different
source and Mobile/Metal. The earlier M1 ladder used GDScript physics and
external mirrored 1080p; remote capture and thermal state materially changed
its results. Those studies establish that the M1 path can run well. They do
not diagnose Intel by subtraction or qualify the M1's native Retina output.
Reuse their rendering lessons; conduct discriminating experiments on the
existing Intel device. [E3] [E4]

## 7. Decision sequence and completion criteria

| Priority | Action | Decision it enables |
| --- | --- | --- |
| P0 | Recover the retained raw bundles and verify source/engine/effective settings; use the explicit Compatibility Automatic tour plan. | Distinguish the product baseline from an intentionally heavier technical workload. |
| P0 | Capture actual device, renderer, dimensions, clocks, CPU/memory pressure and clean completion on the existing Intel host. | Attribute a slow interval to workload, scheduling/reclaim, co-tenancy or a driver fault; retain unknowns. |
| P1 | Repeat the current Automatic three-aircraft screen and paired scale/MSAA diagnostics. | Establish real-time pace and repeatable quality/performance behavior without changing physics. |
| P1 | Investigate a bounded terrain variant in fixed Home and flight views. | Find a local optimization with measured benefit and acceptable visuals. |
| P1 | Separate cold first-use work from repeated Home/flight work. | Choose warmup, cache retention or scene-construction changes for the correct cause. |
| P2 | Isolate Mobile HDR and then one Mesa user-space change if justified. | Determine whether either can beat or stabilize the current path with acceptable visuals. |
| P2 | Add Intel measurement coverage through the existing sampler. | Make future monitoring complete without inventing zero counters or new evidence semantics. |

The [protocol](2026-11-22-intel-gpu-experiments.md) defines controls, interpretation,
admission and required artifacts. A performance improvement needs repeated
same-host/reference/candidate evidence, preserved output quality, complete
cases and sim/wall pace. An isolated headless Python check or software-rendered
CI capture cannot qualify Intel performance.

This branch deliberately makes no unmeasured production-renderer change. Its
deliverable is an evidence-backed diagnosis and executable-plan review, with
specific follow-up decisions; host measurements and runtime candidates remain
explicitly pending.

## 8. Verification and independent review

The lead inspected the reported evidence and relevant code, and integrated
three bounded independent assignments: Intel/Proxmox primary-source research,
render-path inspection, and a Good Enemy evidence review. Accepted corrections
include the newer Automatic baseline, RAM/clock inconsistencies, asynchronous
GPU timing, output/internal resolution, automatic-renderer selection, missing
Intel telemetry, and separate loading causes. Generic VM tuning, blanket
driver conclusions and cross-machine speed ratios were rejected.

The explicit existing GOD TEST dry-run expands to nine complete cases
(three aircraft × three repeats), with Compatibility/OpenGL, Automatic
graphics, Low detail and a 1920×1080 requested output. It launches no engine.
The ledger records verification commands/results and input SHA-256 values.
Documentation links and whitespace are checked before publication. Full CI,
rendered acceptance and new target-hardware performance are not claimed.

## Primary sources

Checked 22 November 2026. Rolling documents describe current contracts; exact
application behavior above was checked against the pinned repository. Vendor
guidance supports hypotheses, not promised OpenRC FPS.

- **P1 — Proxmox container model:** [official `pct` source documentation](https://github.com/proxmox/pve-docs/blob/master/pct.adoc), introduction and resource controls.
- **P2 — Intel Comet Lake memory:** [10th Generation Core datasheet, 615211-008](https://cdrdv2-public.intel.com/615211/615211-008.pdf), §2.1.3–2.1.4, pages 21–22: Flex zones and channel timing.
- **P3 — Linux memory/CPU controls:** [cgroup v2](https://docs.kernel.org/admin-guide/cgroup-v2.html), `memory.stat`, `memory.events`, `memory.pressure`, `cpu.stat`; read current cgroup and ancestors.
- **P4 — Exact processor:** [Intel i5-10500 specifications](https://www.intel.com/content/www/us/en/products/sku/199277/intel-core-i510500-processor-12m-cache-up-to-4-50-ghz/specifications.html), UHD 630, 1.15 GHz maximum dynamic GPU frequency and two memory channels. Advertised ceilings are not observed clocks/bandwidth.
- **P5 — Intel engines and DRM observations:** [kernel driver UAPI](https://docs.kernel.org/gpu/driver-uapi.html), i915 engine classes; [DRM usage statistics](https://docs.kernel.org/gpu/drm-usage-stats.html), optional per-client counters, units and identity.
- **P6 — Xe platform scope:** [kernel Xe merge/platform design](https://docs.kernel.org/6.8/gpu/rfc/xe.html), Tiger Lake and newer; it supplies no UHD 630 migration recommendation.
- **P7 — Mesa:** [environment-variable documentation](https://docs.mesa3d.org/envvars.html), shader-cache controls/statistics and Intel diagnostics. Verify support in installed 25.0.7 before use; diagnostic flags can perturb observations.
- **P8 — Intel Gen9 optimization:** [Graphics API Performance Guide v2.5](https://cdrdv2-public.intel.com/671201/graphics-api-performance-guide-2-5.pdf), §2.3 and §4.1/4.5. Hardware-level guidance; its Linux driver implementation is not specifically covered.
- **P9 — Godot renderer architecture:** [4.7 architecture documentation](https://docs.godotengine.org/en/4.7/engine_details/architecture/internal_rendering_architecture.html), Mobile/Compatibility, color formats and subpasses; not a benchmark of 4.8-beta2.
- **P10 — Pinned Godot implementation:** [`render_scene_buffers_rd.h`](https://github.com/godotengine/godot/blob/cafc17a19/servers/rendering/renderer_rd/storage_rd/render_scene_buffers_rd.h), `get_base_data_format`; [`render_forward_mobile.cpp`](https://github.com/godotengine/godot/blob/cafc17a19/servers/rendering/renderer_rd/forward_mobile/render_forward_mobile.cpp), preferred color format and HDR pipeline format.
- **P11 — Shader stutter:** [Godot pipeline compilation guide](https://docs.godotengine.org/en/stable/tutorials/performance/pipeline_compilations.html), explicit Compatibility exclusion and legacy preload/draw advice.
- **P12 — Apple architecture:** [Apple GPU tile-based deferred rendering](https://developer.apple.com/documentation/metal/tailor-your-apps-for-apple-gpus-and-tile-based-deferred-rendering), architecture explanation; not an M1/UHD benchmark.

[E1]: ../visual-quality-implementation/VQ-07/igpu-uhd630-2026-11-20/README.md
[E2]: 2026-11-22-linux-uhd630-comparison.md
[E3]: 2026-11-21-stutter-map.md
[E4]: ../desktop-delivery-investigations/DT-MAC-03b/README.md
[E6]: ../../../tools/godtest/PERFORMANCE_TOUR.md
[P1]: https://github.com/proxmox/pve-docs/blob/master/pct.adoc
[P2]: https://cdrdv2-public.intel.com/615211/615211-008.pdf
[P3]: https://docs.kernel.org/admin-guide/cgroup-v2.html
[P4]: https://www.intel.com/content/www/us/en/products/sku/199277/intel-core-i510500-processor-12m-cache-up-to-4-50-ghz/specifications.html
[P5]: https://docs.kernel.org/gpu/driver-uapi.html
[P6]: https://docs.kernel.org/6.8/gpu/rfc/xe.html
[P7]: https://docs.mesa3d.org/envvars.html
[P8]: https://cdrdv2-public.intel.com/671201/graphics-api-performance-guide-2-5.pdf
[P9]: https://docs.godotengine.org/en/4.7/engine_details/architecture/internal_rendering_architecture.html
[P10]: https://github.com/godotengine/godot/blob/cafc17a19/servers/rendering/renderer_rd/storage_rd/render_scene_buffers_rd.h
[P11]: https://docs.godotengine.org/en/stable/tutorials/performance/pipeline_compilations.html
[P12]: https://developer.apple.com/documentation/metal/tailor-your-apps-for-apple-gpus-and-tile-based-deferred-rendering
