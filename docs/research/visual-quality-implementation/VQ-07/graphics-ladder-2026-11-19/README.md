# VQ-07h: graphics-option ladder on the RTX 3090 at 4K (real route)

2026-11-19. One host, the player's route (Home → Fly) on the real 4K display, measured with the
[graphics ladder](../../../../../research/performance/graphics_ladder/README.md). It complements the scripted
[per-setting GPU costs](../knob-costs-2026-11-18/README.md) and the direct-route
[renderer matrix](../rtx3090-matrix-2026-11-17/README.md), and is the Windows counterpart of the M1 ladder
[DT-MAC-03b](../../../desktop-delivery-investigations/DT-MAC-03b/README.md). The
[cross-platform analysis](../ladder-analysis-2026-11-19/README.md) compares both ladders and lists the defects,
improvement plan and follow-up tests.

| | |
| --- | --- |
| Host | Windows 11 Pro 26100, Ryzen 9 5900X (12 cores), 64 GB, GeForce RTX 3090 (driver 617.42, 399 W limit), HAGS off, power plan Balanced |
| Display | Samsung Q90A 3840×2160 at 120 Hz, 150 % scaling; borderless full screen unless a row says windowed |
| Source | `main` at `a8a99f725`, a renamed snapshot (`OpenRC GFX Ladder Win 20261119`) with the native kernel active (`physics_backend: native`) |
| Engine | official `4.8.beta2` (`cafc17a19`): no DLSS, FSR3 or Reflex |
| Campaign | 138 runs, all OK, 00:16–07:19; 53 configurations; 15 reference runs (L09) every ten runs |

## Method

Each run seeds `settings.cfg.display`, launches the app muted, checks the saved and effective settings, the
rendering driver, screen size and refresh rate, measures Home for 8 s, flies the Ugly Stik in a 90 m orbit over the
clubhouse at 40 m, measures two laps (≈48 s) from the same point, then dives into the ground at the pilot station
and measures the crash. VSync is off unless a row says otherwise, so fps is render throughput. The ladder L00 → L14
adds one option group per step (labels in the table); L09 equals the product defaults with Scene detail Medium.
Four ladder passes ran in alternating order; step deltas are paired within each pass with a 95 % interval.
`nvidia-smi` sampled the GPU every second; per-thread CPU time came from `psutil`.

## 1. A 2 Hz main-thread stall (found and fixed)

Every configuration, at Home and in flight, showed exactly **2.0 frames longer than 25 ms per second**. The bridge's
hitch records at a 15 ms threshold put each at `process_ms` 28–47 with no other cause. The source is
[`controller_service.gd`](../../../../../app/input/controller_service.gd): its 0.5 s `refresh()` always took the controller store's cross-process lease
(create a lock directory, write an owner file, read it back, delete both) on the main thread. Timed inside the app:

| `user://` location | Acquire | Release | Stall per refresh |
| --- | --- | --- | --- |
| USB flash, exFAT (`U:`, the campaign profile) | 21–35 ms (once 156) | 4.2 ms | ≈ 26 ms |
| NVMe, NTFS (`C:\Users\…\AppData\Roaming`, a player's location) | 1.0–1.3 ms | 5.3–6.1 ms | ≈ 7 ms |

The refresh now skips the lease when no menu device is selected and no automatic default is pending, the only cases
in which it reads storage. With a menu gamepad selected the locked recheck remains, a follow-up in the
[controller plan](../../../../plans/controller-support.md) (F3-GP-02-R3). `test_controller_auto_defaults.gd` covers
both paths; its new checks fail on the old code.

The A/B ran with `user://` on C:, the original code against the fixed one, in interleaved pairs, three of each:

| Configuration | Code | Clean runs | fps | 1 % low | p99 | >12.5 ms | Longest frame |
| --- | --- | --- | --- | --- | --- | --- | --- |
| L13, VSync off | original | 2 | 269.8–281.9 | 90–99 | 7.3–8.1 ms | 0.07–0.15 % | 15–18 ms |
| L13, VSync off | fixed | 3 | 281.4–293.1 | 127–144 | 5.9–6.9 ms | 0.00–0.02 % | 10–14 ms |
| L09, VSync off | original | 1 | 315.8 | 114 | 5.4 ms | 0.01 % | 14 ms |
| L09, VSync off | fixed | 3 | 282.7–291.9 | 127–140 | 6.3–7.1 ms | 0.00–0.01 % | 10–15 ms |
| L13, VSync 120 Hz | original | 3 | 119.9–120.0 | 60–62 | 15.6–15.8 ms | 1.63–1.73 % | 18–22 ms |
| L13, VSync 120 Hz | fixed | 2 + 2 | 119.9–120.0 | 91–109 | 8.9–9.6 ms | 0.00–0.21 % | 10–15 ms |

- **VSync at 120 Hz.** With the original code, the 7 ms stall missed a refresh twice a second, 1.7 % of frames.
  With the fix, the four runs, which include the two controls from section 6, missed almost none.
- **VSync off.** The 1 % low rises from 90–114 to 127–144 fps. Mean fps differences stay inside the run-to-run
  spread, since the stall costs about 14 ms per second.
- **Excluded runs.** The first pair's L09 and L13 runs overlapped a local test run, and the harness recorded the
  extra engines. Two runs froze for 1.0 s and 1.7 s outside `_process`, one in each arm, and are also excluded.

**Effect on this campaign.** The profile lived on the USB drive, so every window lost ≈52 ms per second to the
stall: mean fps is about 5 % low, and the 1 % low (≈ 39–45 fps), p99 and the >16.7/20/25 ms shares measure the stall,
not the renderer. The stall is the same in every configuration, so the comparisons below stand; the absolute
smoothness numbers are those of the A/B.

### Clean baseline after the fixes (same day, 14:15–14:45)

This baseline is the reference for absolute values on this host. It ran the snapshot with `main`'s `app/` files at
`349958a4b`, with:

- the controller fixes and the Home render budget;
- `user://` on C: (outside AppData);
- no remote session;
- the 4K TV at 120 Hz;
- two passes in alternating order, with the window `host_activity` empty throughout.

| Configuration | Flight fps | 1 % low | p99 | >12.5 ms | Home fps (scale) | Crash: fps, longest frame |
| --- | --- | --- | --- | --- | --- | --- |
| L00 | 388.6–389.7 | 240–242 | 3.7–3.8 ms | 0 % | 239–240 (1.0) | 289–290, 10–12 ms |
| L09 | 317.2–321.1 | 206–211 | 4.3–4.4 ms | 0 % | 136 (1.0) | 203–204, 17–25 ms |
| L13 | 310.8–315.6 | 187–213 | 4.4–4.7 ms | 0 % | 135–137 (×0.85) | 182, 14–16 ms |
| L13, VSync 120 Hz | 120.0 | 108 | 9.0 ms | 0 % | 120.0 (×0.85) | 119.5–119.8, 16–17 ms |
| L09, windowed 1080p | 343.2–348.5 | 204–208 | 4.3–4.4 ms | 0 % | 357 (1.0) | 325–328, 11–12 ms |

- Against the campaign, flight fps is about 17 % higher and the 1 % low is about five times higher.
- The crash's longest frames fell from 38–83 ms to 10–25 ms.
- With the profile on a USB flash drive, every main-thread `user://` write was slower, not only the controller lock:
  flight statistics and the accident record are written at the crash.
- The campaign's comparisons between configurations stand. Its absolute values do not.
- The main thread is still the limit (95 % busy).

## 2. The 3090 at 4K is CPU-bound

| Measure (L09, 4K) | Value |
| --- | --- |
| fps (VSync off) | 273 |
| Busiest thread (main) | 92 % of one core |
| GPU time per frame (root viewport) | 2.16 ms of a 3.7 ms frame |
| `nvidia-smi` utilisation | 70–80 % at 1965 MHz, 340–350 W |
| With VSync at 120 Hz | 117.6 fps, GPU 38 %, 157 W |

Every High configuration keeps the main thread at 89–95 %. Windowed 1080p and 1440p are only 4–10 % faster than
4K, with the GPU 30–46 % busy. Graphics options therefore move flight fps mainly through their CPU cost. MSAA
also shows in flight, because the single-threaded renderer still waits for the GPU in part of the frames.

## 3. Ladder

4K borderless, VSync off. Δ is the step delta paired within each pass, with its 95 % interval; **bold** deltas
are resolved. Pass 1 is excluded. It ran right after the smoke warm-up and still paid first-use costs: −6.6 fps on
average against passes 2–4, and up to −38.7 fps (L01). With it included, L01 and L03 looked 2 and 1 points more
expensive and MSAA 2× unresolved. GPU ms is the root viewport's time per frame in flight.

The same runs give three ladders, each limited by a different resource:

- **Flight** (the two-lap orbit) is limited by the main thread.
- **Home** (8 s) is GPU-bound. It is the most precise ladder.
- **The crash** (dive, impact and 4 s) is mostly GPU-bound: the main thread drops to 62–78 % and the GPU runs at
  82–94 %.

| Step | Adds | Flight fps | Flight Δ | Home fps | Home Δ | Crash Δ | GPU ms | Draw calls |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| L00 | Every option at its minimum | 335.7 | | 229 | | | 1.75 | 311 |
| L01 | Scene detail Medium | 334.1 | −0.4 % (±4.6 %) | 226 | −1.2 % (±2.6 %) | −2.6 % (±12.4 %) | 1.75 | 312 |
| L02 | MSAA 2× | 317.8 | **−4.9 % (±3.3 %)** | 193 | **−14.7 % (±2.1 %)** | −9.0 % (±13.1 %) | 2.01 | 312 |
| L03 | Projected shadows and planar aircraft cue | 296.8 | **−6.6 % (±1.8 %)** | 182 | **−5.9 % (±2.2 %)** | −1.9 % (±8.8 %) | 2.01 | 315 |
| L04 | Native sun shadows, Automatic distance and softness, Low atlas | 294.0 | −0.9 % (±2.5 %) | 175 | **−3.4 % (±2.3 %)** | −2.0 % (±3.7 %) | 2.04 | 455 |
| L05 | Shadow quality Standard | 292.0 | −0.7 % (±1.8 %) | 144 | **−18.1 % (±0.9 %)** | **−10.2 % (±6.0 %)** | 2.08 | 595 |
| L06 | Cloud shadows | 287.4 | −1.6 % (±3.2 %) | 142 | **−1.1 % (±0.5 %)** | −0.7 % (±10.7 %) | 2.08 | 595 |
| L07 | Birds, flags, runway meadow, RC track | 273.0 | −5.0 % (±9.7 %) | 141 | −0.3 % (±1.7 %) | −3.3 % (±12.8 %) | 2.10 | 603 |
| L08 | Lens and impact effects, aircraft lighting Standard | 270.2 | −1.0 % (±4.9 %) | 141 | 0.0 % (±2.2 %) | −1.0 % (±8.2 %) | 2.10 | 603 |
| L09 | MSAA 4× (product defaults with Scene detail Medium) | 273.8 | +1.4 % (±6.3 %) | 130 | **−8.5 % (±0.6 %)** | **−3.5 % (±1.5 %)** | 2.16 | 603 |
| L10 | Scene detail High | 263.4 | −3.8 % (±10.9 %) | 128 | −1.5 % (±2.3 %) | +0.7 % (±3.6 %) | 2.22 | 610 |
| L11 | Shadows High, Far, Soft | 268.8 | +2.2 % (±9.3 %) | 133 | **+4.1 % (±2.6 %)** | +3.0 % (±7.8 %) | 2.21 | 744 |
| L12 | Scene detail Extreme | 267.5 | **−0.5 % (±0.3 %)** | 126 | **−5.1 % (±0.8 %)** | −6.7 % (±7.4 %) | 2.21 | 743 |
| L13 | Shadows Ultra, lens Ultra, lighting High, birds Many, flags Detailed | 268.9 | +0.5 % (±3.2 %) | 105 | **−16.9 % (±0.4 %)** | −4.5 % (±6.8 %) | 2.23 | 743 |
| L14 | MSAA 8× | 252.5 | **−6.1 % (±4.5 %)** | 92 | **−12.2 % (±3.9 %)** | **−9.9 % (±2.9 %)** | 2.69 | 743 |

- **Flight.** The whole ladder costs 20 % (336 → 269 fps), and 25 % with MSAA 8×. Every step still runs above
  250 fps.
  - Turning MSAA on costs 4.9 %. The projected shadows and planar cue (L03) cost 6.6 %. They change neither GPU
    time nor draw calls, so their cost is per-frame script work.
  - The native shadow tiers add 140–420 shadow draw calls and cost nothing measurable in flight.
- **Home is the GPU's ladder.** The tight intervals show what each option costs once the GPU is the limit:
  - MSAA: −15 % at 2×, −8.5 % more at 4×, −12 % more at 8×.
  - Shadow quality Standard −18 %, and the Ultra bundle −17 %.
  - Scene detail Extreme −5 %, and the projected cue −6 %.
  - Scene detail Medium/High, cloud shadows, scenery life and lens effects cost ≤ 1.5 %.
  - Shadows High (4 cascades) is 4 % *faster* at Home than Standard (2 cascades).
- **Home is the heaviest screen.** It falls from 229 to 105 fps at L13 and 92 fps at L14, while flight stays above
  250 fps. So at 4K with every option on, Home does not hold 120 Hz on this GPU ([section 6](#6-experiments)).
- **The crash** responds to the same GPU options as Home: Standard shadows, MSAA. Its p99 rises from 11.6 ms at
  L00 to 29–30 ms from L06 on.

## 4. Renderers, resolution and reconstruction

**Renderer and API** (4K borderless; Δ against High on Vulkan at the same step):

| Profile | L00 fps | L09 fps | L13 fps | Home L13 | Render CPU ms | VRAM L13 | Process RSS L13 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| High, Vulkan (product) | 333.0 | 273.0 | 268.3 | 104 | 0.37–0.50 | 2.36 GB | 2.5 GB |
| High, D3D12 | 317.0 (−5 %) | 242.8 (−11 %) | 249.8 (−7 %) | 121 | 0.33–0.53 | 2.65 GB | 1.5 GB |
| Standard, OpenGL | 243.2 (−27 %) | 185.4 (−32 %) | 177.4 (−34 %) | 168 | 1.24–1.82 | 1.10 GB | 1.5 GB |
| Mobile, Vulkan (not a Windows mode) | 336.8 (+1 %) | 278.0 (+2 %) | 261.4 (−3 %) | 108 | 0.51–0.69 | 1.90 GB | 2.9 GB |

- Vulkan is the right High API on NVIDIA. D3D12 is 5–11 % slower in flight but faster at Home.
- Standard spends 3–4× more render CPU per frame, which is the limit here. It is a compatibility path, never a
  speed choice, on a GPU like this.
- Mobile matches Vulkan Forward+ in flight with fewer draw calls (368 vs 743 at L13, 89 vs 414 shadow calls). Its
  look differs and it stays unqualified on Windows.
- Process RSS counts driver mappings: Vulkan processes hold about 1 GB more than D3D12 or OpenGL.

**Resolution** (High, Vulkan, windowed; Δ against 4K borderless):

| Window | L00 | L09 | L13 | GPU % | GPU ms L13 | Home L13 |
| --- | --- | --- | --- | --- | --- | --- |
| 1920×1080 | 365.7 (+10 %) | 284.2 (+4 %) | 283.6 (+6 %) | 31–35 | 0.91 | 268 |
| 2560×1440 | 350.4 (+5 %) | 280.5 (+3 %) | 283.1 (+6 %) | 39–46 | 1.19 | 182 |
| 3840×2160 borderless | 333.0 | 273.0 | 268.3 | 70–80 | 2.23 | 104 |

Standard, windowed, gives 182–190 fps at both sizes, the same as at 4K: it is CPU-bound everywhere. Windowed mode
adds desktop composition, so these rows are not a pure resolution change. Only Home scales with pixels.

**FSR2** (L13 with FSR2 replacing MSAA 4×; Δ against L13):

| Mode | Internal scale | fps | GPU ms | Process RSS |
| --- | --- | --- | --- | --- |
| MSAA 4× (L13) | 1.0 | 268.3 | 2.23 | 2.5 GB |
| FSR2 native AA | 1.0 | 193.0 (−28 %) | 4.06 | 4.9 GB |
| FSR2 Quality | 0.67 | 247.9 (−8 %) | 2.78 | 4.8 GB |
| FSR2 Balanced | 0.59 | 255.0 (−5 %) | 2.56 | 4.9 GB |
| FSR2 Performance | 0.5 | 263.6 (−2 %) | 2.35 | 4.8 GB |

- FSR2 never pays back on this host. Even Performance, a 1080p internal image, costs more GPU time than native 4K
  with MSAA 4×, and every mode adds 134 draw calls and about 2.3 GB of process memory.
- At L09, FSR2 Quality gives 253.8 fps (−7 %).
- Reconstruction is a tool for GPU-bound hosts. It should not be offered as a speed-up when the main thread is the
  limit.

## 5. Pacing, physics, scenes, soak, crash and load

**Pacing and power** (L13 unless noted):

| Mode | fps | >12.5 ms | Busiest thread | GPU % | Board power |
| --- | --- | --- | --- | --- | --- |
| VSync off | 268.3 | 0.84 % | 92 % | 80 | 350 W |
| VSync at 120 Hz | 117.7 | 1.75 % | 60 % | 38 | 158 W |
| VSync at 120 Hz, L09 | 117.6 | 1.71 % | 57 % | 38 | 157 W |
| Cap 120, VSync off | 115.7 | 1.99 % | 67 % | 37 | 158 W |
| Cap 60, VSync off | 59.8 | — | 47 % | 32 | 98 W |
| Fresh-install display defaults (windowed, Automatic size, VSync) | 117.5 | 1.72 % | 61 % | 28 | 87 W |

- VSync holds 120 Hz with half of the frame time spare. It also cuts board power from 350 W to 158 W.
- Every missed refresh at 120 Hz in these rows, 2.0 per second, is the controller stall from section 1. The
  fixed A/B rows give the clean value.
- The 120 fps cap without VSync paces slightly worse than VSync at the same power.

**Physics.** The native kernel was active in every run except the two GDScript controls, which ran a snapshot copy
without `app/native`. GDScript reference physics costs 10 % at 4K L09 (245.8 vs 273.0 fps) and 15 % at 1080p
windowed (240.8 vs 284.2), where nothing else limits.

**Landscapes and time of day:**
- Green Paradise is 17–19 % faster than the club field: 320 fps at L09 and L13, with fewer draw calls (556/690)
  and a less busy main thread (87 %).
- Night costs nothing: 271 and 273 fps, with GPU time down to 1.7 ms.

**Soak.** Twelve two-lap windows at L13 (14 min) gave 259–271 fps with no trend. The GPU stayed at 60–62 °C and
1960 MHz, and process memory grew 6 MiB.

**Crash.** The dive hits the ground near the pilot station within a few metres in all 138 runs.

| Profile | fps during the crash (L13) | Longest frame, warm | First crash in a fresh configuration |
| --- | --- | --- | --- |
| High, Vulkan | 166 (L00 261, L14 152) | 38–83 ms | ≤ 71 ms |
| High, D3D12 | 164 | 40–51 ms | ≤ 51 ms |
| Standard, OpenGL | 109 | 45–86 ms | 0.7–2.8 s |
| Mobile, Vulkan | 77 | 84–112 ms | 0.14–4.2 s |

- Crash effects cut fps by about 40 % at L13, but never below 109 fps on a product profile.
- Forward+ crashes were compiled by the smoke run and earlier passes. Standard and Mobile compiled crash
  pipelines at first impact for up to 4.2 s.
- The night crash compiled once for 181 ms.
- **Correction (re-measured cold the same afternoon).** These freezes were mostly the shader cache being written to
  the USB flash drive. With a fresh profile on a system drive:

  | Profile | First crash | First Home → Fly |
  | --- | --- | --- |
  | Mobile | 33–48 ms | 3.6–4.4 s |
  | Forward+ | 20 ms | 4.2 s |
  | Standard L13 | 405–766 ms | 12.5 s |
  | Standard L00 | 116–574 ms | |
  | Standard L09 | 47–48 ms | |

  See the [cross-platform analysis](../ladder-analysis-2026-11-19/README.md#8-implementation-results).

**Load.**
- Warm launches took about 16 s to Home, and Home → Fly took 3.4 s.
- First use of a profile was slower: Standard's first Home → Fly took 19.6–40.9 s and Mobile's 10.9–11.8 s. Most of
  that was the USB drive, per the correction above.

**Automatic and fresh install.**
- Every Automatic choice on High at 4K borderless (AUTO) picked Scene detail High and ran at 265.1 fps; its second
  pass, at 229.0, coincided with the host transient noted in Limits.
- The fresh-install display defaults (OOB) open a window at the Automatic size with VSync and run at the 120 Hz
  refresh.

## 6. Experiments

These runs used the fixed controller code with `user://` on C:, in interleaved pairs of two passes each. Their
absolute fps sits above sections 2–5 by the stall's cost and is comparable only within each table.

**Separate render thread.** The snapshot's `project.godot` set `rendering/driver/threads/thread_model=2`, which runs
the RenderingServer on its own thread:

| Configuration | Default (Safe) | Separate | Δ | 1 % low |
| --- | --- | --- | --- | --- |
| L09, 4K | 294.6 (293.1–296.0) | 341.4 (340.5–342.3) | +16 % | 136 → 213–218 |
| L13, 4K | 292.2 (292.1–292.3) | 334.9 (334.7–335.0) | +15 % | 146–148 → 209–215 |
| L09, windowed 1080p | 310.7 (308.9–312.4) | 412.2 (410.7–413.7) | +33 % | 152–153 → 216 |
| L13, VSync 120 Hz | 120.0 | 120.0 | 0 | 105 → 103–105 |

- **Where the frame now goes.** The main thread drops from 96–100 % to 86–98 % and a render thread runs at
  53–61 %. At 4K the GPU reaches 91–92 %, so the 3090 becomes nearly GPU-bound there.
- **Home gains nothing,** because it is GPU-bound: 109.8 → 107.1 fps at L13, with p99 rising from 18.7 to 27.6 ms.
- **Per-frame GPU queries now stall.**
  - Every per-frame RenderingServer getter forces a render-thread sync, and the engine logs a warning each time.
  - In the product, this is `auto_calibration.gd` while calibrating and `frame_diagnostics.gd` when enabled.
  - In the harness, it is the bridge's GPU timing. That made the ladder's Home values under Separate unusable, so
    Home here was measured with GPU timing off.
- **Not a qualification.**
  - Godot documents this model as [experimental](https://docs.godotengine.org/en/latest/classes/class_projectsettings.html#class-projectsettings-property-rendering-driver-threads-thread-model):
    it has known crashes, "especially when using particles or resizing the window", and is not recommended for
    production.
  - Sixteen runs, each ending in a crash, logged no engine errors. That does not qualify the model.
  - Input latency was not measured.

**Power plan.** Windows *High performance* against *Balanced*:

| Configuration | Balanced | High performance | Δ |
| --- | --- | --- | --- |
| L09, 4K | 290.5 (290.3–290.6) | 288.0 (287.6–288.4) | −1 % |
| L13, 4K | 288.9 (287.4–290.4) | 282.7 (279.3–286.0) | −2 % |
| L09, windowed 1080p | 306.8 (301.4–312.1) | 300.6 (299.4–301.8) | −2 % |

High performance gains nothing: Balanced already lets the 5900X boost the main thread. Balanced was restored.

**Home.** At L13 in 4K, Home is GPU-bound at about 110 fps. It takes 8.46 ms of GPU time per frame against
1.86 ms in flight, with 1.14 M primitives against 0.44 M and 809 draw calls. The bridge's A-B-A ablation
attributed the time as follows (root viewport; timestamp freshness unverified):

| Switched off | GPU saved |
| --- | --- |
| Field layer | 7.0 ms (83 %) |
| 3D at half resolution | 5.3 ms (62 %) |
| All shadows | 2.9 ms (35 %) |
| MSAA | 1.8 ms (21 %) |
| Field scenery | 1.0 ms (11 %) |
| Aircraft | 0.6 ms (7 %) |
| Tree line detail | 0.5 ms (6 %) |

- Home's low camera fills the 4K frame with shaded ground, so Home is bound by pixels.
- A flight view near the ground (taxi, landing, low chase) probably costs about as much. The ladder's orbit is mostly
  sky, and such a view was not measured in flight.

## Recommendations

1. **Controller refresh.** Keep the fix and close the menu-gamepad case
   ([controller plan](../../../../plans/controller-support.md)). A 7 ms main-thread stall twice a second is visible
   at 120 Hz on any Windows host.
2. **Automatic on a 3090-class GPU at 4K and 120 Hz.**
   - Every flight option can sit at its highest tier: Scene detail Extreme, Shadows Ultra and the bundle stay above
     250 fps uncapped. Keep MSAA at 4×, since 8× costs 6 % in flight and 12 % at Home.
   - The 120 Hz limit is ground-filling views, not the orbit. Home at L13 needs 8.5 ms of GPU time against the
     8.3 ms refresh budget.
3. **Home.** Render Home's 3D background at a reduced 3D scale or cap Home's frame rate (an owner decision for the
   Home owners). It is the most expensive screen of the product and a menu.
4. **Renderers and reconstruction.**
   - Keep Vulkan for High on NVIDIA. Never pick Standard for speed on such a GPU.
   - Do not offer FSR2 as a speed-up when the main thread is the limit. Reconstruction should follow a measured
     GPU-bound state, not resolution alone.
5. **VSync.** Keep it on by default. It holds 120 Hz here and halves board power (350 → 158 W).
6. **The CPU is the next frontier in flight.**
   - Main-thread work: projected-shadow scripts cost 6.6 %, scenery life up to 5 %, and crash effects 40 % during a
     crash.
   - The separate render thread is worth 15–33 %. It needs an engine-level qualification first: particles, window
     resizing, latency, and calibration's per-frame GPU queries.

## Limits

- One computer and one display; a run qualifies only this host. Uncapped fps measures throughput, not what the
  display shows.
- The campaign's `user://` was on a USB flash drive (section 1). Load times and first-use shader compilation also
  read and write that drive.
- The official engine has no DLSS, FSR3 or Reflex; HAGS was off and the power plan Balanced throughout the
  campaign.
- A host transient at runs 117–118 (REF 242 fps, −10 %) affected AUTO's second pass; otherwise REF stayed within
  266–275 fps. The section 1 A/B saw two freezes of 1.0 and 1.7 s outside the game's frame work, cause unknown.
- The A/B has only one clean original L09 run, so its L09 row is not a comparison.
- Section 6's thread and Home experiments edited the snapshot's `project.godot` and controller file per phase
  and restored them afterwards; the power-plan phases switched the Windows plan and restored Balanced.
- Evidence (run folders, frame data, `nvidia-smi` logs, screenshots) is outside Git:
  `D:\OpenRCsimulator-evidence\gfx-ladder-win-20261119`.
