# DT-MAC-00-R1: Apple Silicon hardware and memory investigations

**Retrieved:** 2026-10-24. Primary Apple and Godot sources opened on this date. This is desk research only; no OpenRC Mac performance, thermal, or memory result was measured.

**Hardware clarification after research:** the user confirmed a MacBook Air M1 with 8 GB. Conditional host-identification proposals below retain the research reasoning; the current plan now uses that confirmed low-memory/fanless host. GPU core count and macOS remain pending.

## I01 — M1 floor: GPU SKU, memory, and chassis

**Question:** What must be identified before calling the available M1 the plan's floor host?

**Findings:** Apple's [M1 MacBook Air specifications](https://support.apple.com/en-us/111883) list an 8-core CPU, either a 7- or 8-core GPU, and 8 GB unified memory configurable to 16 GB. Apple describes the M1 Air as [fanless](https://www.apple.com/newsroom/2020/11/introducing-the-next-generation-of-mac/). The Air is only one M1 chassis; Apple's M1 launch included a [Mac mini and 13-inch MacBook Pro](https://www.apple.com/newsroom/2020/11/introducing-the-next-generation-of-mac/), and its later [M1 Pro/Max](https://www.apple.com/newsroom/2021/10/introducing-m1-pro-and-m1-max-the-most-powerful-chips-apple-has-ever-built/) and [M1 Ultra](https://www.apple.com/newsroom/2022/03/apple-unveils-m1-ultra-the-worlds-most-powerful-chip-for-a-personal-computer/) announcements describe much larger GPU/memory tiers. “M1” alone does not establish the hardware floor.

**Plan consequence:** Retain “M1 Air, 8 GB” as the desired floor coverage, but identify the available unit before describing it that way. Record model identifier, chip/GPU core count, installed memory, macOS build, power state, and display setup before DT-MAC-03. If the available M1 differs, start the baseline on that named host now and keep the 8 GB/fanless gap explicit.

**Specific test:** Identify the Mac in About This Mac/System Information, then run its 1080p baseline and a 30-minute active-flight soak. If it is a 7-core Air with 8 GB, it also covers the desired floor; otherwise schedule that coverage separately. Label any 8-core Air, Pro, or mini result precisely.

**Limits:** Apple specifications establish configuration options, not OpenRC frame rate or sustained behavior. The user has confirmed Air/8 GB; GPU core count, exact model identifier and macOS version remain unverified.

## I02 — M2 differences relevant to optimization

**Question:** Which M2 changes make its measurements non-interchangeable with M1 results?

**Findings:** Apple says M2 has a 10-core GPU, 50% more memory bandwidth than M1, and supports up to 24 GB unified memory in its [M2 announcement](https://www.apple.com/newsroom/2022/06/apple-unveils-m2-with-breakthrough-performance-and-capabilities/). In the [13-inch M2 Air specification](https://support.apple.com/en-us/111867), GPU configurations are 8 or 10 cores, memory is available as 8, 16, or 24 GB, and bandwidth is listed at 100 GB/s. Apple maps M1 and M2 to distinct GPU families, Apple7 and Apple8, in its [Metal capability table](https://developer.apple.com/metal/capabilities/). These changes can shift memory pressure and GPU limits, but do not predict this simulator's result.

**Plan consequence:** Keep M2 as its own named comparison tier. A future compatibility claim should record the exact Mac model, M2 GPU core count, memory capacity, chassis, and OS instead of treating “M2” as one target. Do not replace the M1 floor with M2 results.

**Specific test:** On named M1 and M2 hosts, compare the same 1080p scene, project/export, renderer, OS build, and power/display state. Record the M2's 8- or 10-core GPU and repeat separately if comparing both configurations.

**Limits:** Apple chip and product specifications do not characterize sustained OpenRC load or cooling differences between specific Macs.

## I03 — M3 GPU architecture and capabilities versus M1

**Question:** What changed in M3 that could affect rendering paths or invalidate assumptions from M1?

**Findings:** Apple assigns M1 to GPU family Apple7 and M3 to Apple9 in the [Metal feature table](https://developer.apple.com/metal/capabilities/). Apple's [M3 announcement](https://www.apple.com/newsroom/2023/10/apple-unveils-m3-m3-pro-and-m3-max-the-most-advanced-chips-for-a-personal-computer/) describes a redesigned GPU with Dynamic Caching and introduces hardware-accelerated ray tracing and mesh shading to Mac. The [M3 Air specification](https://support.apple.com/en-gb/118551) lists 8- or 10-core GPUs, up to 24 GB unified memory, and 100 GB/s bandwidth. These are capability and configuration differences, not evidence that OpenRC's existing scenes use those paths.

**Plan consequence:** Keep the initial M1 renderer and scene parity baseline common across generations. Consider advanced GPU paths only if Godot 4.7.2 and the project actually select them and profiling shows a relevant bottleneck; retain an equivalent common-feature comparison first.

**Specific test:** Run the same native 1080p raster workload on identified M1 and M3 systems with the same Godot build, macOS build, and renderer settings. Record actual driver and GPU configuration; test an advanced feature only as a separate candidate with visual parity and effective-path evidence.

**Limits:** Dynamic Caching is hardware-managed, not a project switch to enable. Mesh shading and ray-tracing availability do not establish that Godot/OpenRC uses those paths. None of these facts predicts a simulator speedup; Apple-reported application comparisons are not OpenRC benchmarks.

## I04 — M4 capabilities and scaling

**Question:** How should M4 evidence be represented across base and higher M4 tiers?

**Findings:** Apple's [M4 Air specification](https://support.apple.com/en-ie/122209) lists 8- or 10-core GPU configurations, hardware ray tracing, 120 GB/s bandwidth, and 16/24/32 GB unified memory. The [Metal table](https://developer.apple.com/metal/capabilities/) maps M4 to Apple9, the same family as M3. Higher tiers change scale materially: Apple's [M4 Pro/Max announcement](https://www.apple.com/newsroom/2024/10/apple-introduces-m4-pro-and-m4-max/) lists up to 64 GB and 273 GB/s for M4 Pro, and up to 128 GB and 546 GB/s for M4 Max. Chip generation alone therefore hides GPU size, memory capacity/bandwidth, and chassis differences.

**Plan consequence:** Report base M4, Pro, and Max as separate configurations. Do not add an M4-specific rendering path or promise a gain from the name alone; select work only after the named Mac's 1080p profile identifies a bottleneck.

**Specific test:** For any M4 support claim, run the frozen 1080p workload on the actual target configuration and label GPU cores, memory, chassis, OS, and external-display state. Compare Pro/Max only as separate scaling cases against the same scene and settings.

**Limits:** Published bandwidth/capacity and feature availability do not translate directly to frame time. The Metal-family match with M3 is not a statement that the chips perform alike.

## I05 — M5 capabilities in Apple's current published Mac line

**Question:** Which M5 configurations are actually documented as of 2026-10-24?

**Findings:** Apple's opened 2026 product specifications show distinct variants, not one “M5 Mac” tier:

| Verified Mac and chip | Published configuration example |
| --- | --- |
| Base M5: [13-inch MacBook Air (2026)](https://support.apple.com/en-us/126320) and [14-inch MacBook Pro (2025)](https://support.apple.com/en-nz/125405) | Air: 8/10-core GPU; 14-inch Pro: 10-core GPU. Both list 153 GB/s and 16–32 GB unified memory; Apple's [Air announcement](https://www.apple.com/newsroom/2026/03/apple-introduces-the-new-macbook-air-with-m5/) describes the Air as fanless. |
| [16-inch MacBook Pro, M5 Pro/Max (2026)](https://support.apple.com/en-au/126319) | M5 Pro: 20-core GPU, 307 GB/s; M5 Max: 32/40-core GPU, 460/614 GB/s; configurations reach 64/128 GB. |
| [Mac mini, M5 Pro (2026)](https://www.apple.com/newsroom/2026/09/the-new-mac-mini-and-mac-studio-are-available-today/) | Up to 20-core GPU, 64 GB unified memory, 307 GB/s. |
| [Mac Studio, M5 Max/Ultra (2026)](https://support.apple.com/en-gb/128107) | Max: 32/40-core GPU, 460/614 GB/s, up to 128 GB; Ultra: 64/80-core GPU, 1.2 TB/s, up to 512 GB. |

**Plan consequence:** State compatibility by exact M5 variant and Mac model. Use a base M5 as a base-tier comparison and Pro/Max/Ultra as separate scaling evidence; do not claim one result qualifies all M5 Macs.

**Specific test:** Freeze and test each named target configuration at the 1080p gate, recording GPU core count, memory, chassis, power, macOS build, and effective renderer.

**Limits:** This table is a compact set of verified configurations, not every configure-to-order SKU or an OpenRC benchmark. Current support pages establish options, not application performance.

## I06 — Metal GPU family, API, and OS matrix

**Question:** Do Metal 3/4 hardware capability and OS selection vary across M1–M5?

**Findings:** Apple's [Metal feature table dated May 21, 2026](https://developer.apple.com/metal/capabilities/) maps M1→Apple7, M2→Apple8, M3→Apple9, M4→Apple9, and M5→Apple10; each series is listed for Metal 3 & 4. The table says Metal 3 is available across Apple GPU families and Metal 4 starts at Apple7, so the listed M1–M5 families meet its hardware-family floor. Godot's [4.7 rendering architecture documentation](https://docs.godotengine.org/en/4.7/engine_details/architecture/internal_rendering_architecture.html) says its Metal 4 path requires macOS 26 or later and automatically falls back to Metal 3 on older macOS. Thus OS and engine version affect the effective path even with the same chip.

| Mac GPU series | Apple GPU family | Apple Metal models listed |
| --- | --- | --- |
| M1 | Apple7 | Metal 3, Metal 4 |
| M2 | Apple8 | Metal 3, Metal 4 |
| M3 | Apple9 | Metal 3, Metal 4 |
| M4 | Apple9 | Metal 3, Metal 4 |
| M5 | Apple10 | Metal 3, Metal 4 |

**Plan consequence:** Freeze Godot 4.7.2 and macOS for renderer comparisons; treat macOS 26+ Metal 4 and older-OS Metal 3 as different test conditions.

**Specific test:** On each named host/OS, launch the same native ARM64 build and record the effective driver/API from engine diagnostics where exposed; otherwise record it as unavailable. Verify the expected Metal 4/3 path.

**Limits:** Apple's feature table describes API capability floors, not Godot feature use or performance; confirm effective support at runtime.

## I07 — Unified memory, residency, compression, and 8 GB pressure

**Question:** How should shared memory limits and texture compression affect the M1 floor and later-chip comparisons?

**Findings:** Apple describes Apple Silicon's CPU and GPU as sharing physical memory in its [architecture overview](https://developer.apple.com/videos/play/wwdc2020/10686/); Apple's [Metal storage-mode reference](https://developer.apple.com/documentation/metal/setting-resource-storage-modes) says shared storage is the default for Apple Silicon GPU buffers and textures. This avoids a separate VRAM pool: graphics allocations compete for the same installed memory as macOS and the app. [Activity Monitor](https://support.apple.com/guide/activity-monitor/view-memory-usage-actmntr1004/mac) exposes system memory pressure, compressed memory, and swap. Metal exposes GPU device allocations such as [`currentAllocatedSize`](https://developer.apple.com/documentation/metal/mtldevice/currentallocatedsize) and an approximate recommended working set; [residency sets](https://developer.apple.com/documentation/metal/simplifying-gpu-resource-management-with-residency-sets) organize when GPU allocations are resident but do not add capacity. Apple's [texture guidance](https://developer.apple.com/documentation/metal/optimizing-texture-data) describes conditional lossless compression on Apple GPU family5+; the [feature table](https://developer.apple.com/metal/capabilities/) separately lists lossy texture compression from Apple8 (M2+) and universal texture compression at Apple10 (M5).

**Plan consequence:** Measure memory first on the available M1 and record whether it covers 8 GB, tracking whole-system pressure and resource growth. Retain separate 8 GB acceptance if needed. Inspect effective imported GPU formats and allocations before proposing texture changes; neither unified memory nor a newer compression feature proves a saving in Godot.

**Specific test:** During the 1080p soak and repeated world transitions, sample Activity Monitor pressure/compression/swap and process/GPU allocation diagnostics where exposed. Compare after warm-up and at the final window; check for monotonic retained-resource growth.

**Limits:** `recommendedMaxWorkingSetSize` is approximate, and system, process, and GPU metrics can overlap. Texture-family support does not prove Godot uses a given compression path; no 8 GB pressure result was measured here.
