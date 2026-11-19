# VQ-07h: what the two graphics ladders teach (M1 and RTX 3090)

2026-11-19. A cross-platform analysis of the two real-route ladder campaigns:

- [M1 at 1080p, DT-MAC-03b](../../../desktop-delivery-investigations/DT-MAC-03b/README.md): 139 runs on Mobile/Metal,
  GPU-bound.
- [RTX 3090 at 4K, VQ-07h](../graphics-ladder-2026-11-19/README.md): 138 runs plus 54 experiment runs on Forward+/Vulkan,
  CPU-bound in flight.

This document derives the model behind the numbers. It lists the defects found, proposes the improvement work
with owners, and specifies the extra tests that would settle what is still open. It does not repeat the reports'
tables. Status and acceptance stay in the owning plans; the step names below are proposals until an owner adopts
them.

## 1. The model: one route, three bottlenecks

Each run measures three workloads, and on both hosts they are limited by different resources:

| Workload | M1, 1080p, Mobile/Metal | RTX 3090, 4K, Forward+/Vulkan |
| --- | --- | --- |
| Flight (two-lap orbit, mostly sky) | GPU, 98 % busy | main thread, 89–97 % of a core; GPU 2.2 ms of a 3.7 ms frame |
| Home (low view, ground fills the frame) | GPU: 52.6 fps at product defaults | GPU: 8.46 ms per frame at L13, about 110 fps |
| Crash (dive, impact, 4 s of effects) | GPU: 70 → 38 fps over the ladder | mostly GPU: main thread 62–78 %, GPU 82–94 % |

**Consequence 1: an option has no single cost.** Its cost depends on what limits the view in which it is
measured. The same campaign therefore gives a CPU ladder (3090 flight) and three GPU ladders (3090 Home, M1 flight,
M1 Home). Step deltas, in % of the previous step:

| Step | 3090 flight (CPU) | 3090 Home (GPU) | M1 flight (GPU) | M1 Home (GPU) | Class |
| --- | --- | --- | --- | --- | --- |
| Scene detail Medium | −0.4 ns | −1.2 ns | +0.1 ns | **−2.1** | free |
| MSAA 2× | **−4.9** | **−14.7** | **−3.6** | **−9.5** | GPU fill, everywhere |
| Projected shadows and planar cue | **−6.6** | **−5.9** | **−1.3** | **−2.8** | **CPU** (script) plus GPU |
| Native sun shadows, Low atlas | −0.9 ns | **−3.4** | **−1.8** | **−7.9** | GPU |
| Shadow quality Standard | −0.7 ns | **−18.1** | **−1.4** | **−2.7** | GPU, much dearer on NVIDIA |
| Cloud shadows | −1.6 ns | **−1.1** | 0.0 ns | **−2.6** | small |
| Birds, flags, meadow, RC track | −5.0 ns | −0.3 ns | −0.5 ns | **−1.0** | CPU, unresolved |
| Lens/impact effects, aircraft lighting | −1.0 ns | 0.0 ns | +0.1 ns | 0.0 ns | free in a daytime orbit |
| MSAA 4× | +1.4 ns | **−8.5** | **−3.2** | **−10.1** | GPU |
| Scene detail High | −3.8 ns | −1.5 ns | **−2.3** | **−1.6** | small |
| Shadows High, Far, Soft | +2.2 ns | **+4.1** | **−1.8** | **−9.4** | GPU, opposite signs |
| Scene detail Extreme | **−0.5** | **−5.1** | +0.1 ns | **−14.6** | GPU, ground views only |
| Ultra bundle | +0.5 ns | **−16.9** | **−6.2** | **−17.6** | GPU |
| MSAA 8× | **−6.1** | **−12.2** | −0.1 ns | −0.1 ns | GPU (on the M1 it measured as 4×) |

**Bold** marks a step resolved by its paired 95 % interval, and "ns" marks a step that is not significant. The
3090 columns exclude the first-use pass; the M1 columns pair four (flight) and five (Home) passes.

**Consequence 2: costs differ by GPU architecture, not only by speed.**

- On the 3090, shadow-atlas quality is the dearest GPU option at Home (Standard −18 %). On the M1's tile-based GPU
  it costs 3 %.
- Shadows High (four cascades) is 4 % *faster* than Standard on the 3090 and 9 % slower on the M1.
- Scene detail Extreme costs 15 % on the M1 at Home and 5 % on the 3090.

A single ranking of options, or one cost table scaled by a GPU score, would mis-order choices on one of the two
hosts. Automatic needs per-family costs (tile-based versus immediate-mode, at least), measured on a GPU-bound
view.

**Consequence 3: scenes and time of day flip sign with the bottleneck.**

- Night saves GPU time on both hosts: 2.16 → 1.66 ms on the 3090, and +26 % fps on the M1. The 3090 shows none of
  it in flight (±1 %), because the CPU is the limit there.
- Green Paradise is CPU-lighter (6,950 against 8,148 objects) and GPU-heavier. It is +17–19 % on the 3090 and
  −10 to −22 % on the M1.

A landscape or lighting result from one host does not transfer to the other.

**Consequence 4: views near the ground are the real GPU budget.** Home is the heaviest screen on both hosts. The
3090 Home ablation attributes 83 % of its GPU time to the field layer, and 62 % disappears at half resolution, so
Home is pixel-bound on ground shading. The orbit is mostly sky, so the flight ladder understates what a landing,
a taxi or a low chase view costs. No such view has been measured in flight yet (T3).

## 2. Measurement lessons

1. **A rate that is identical in every configuration is periodic work.** All 53 Windows configurations showed
   2.0 frames over 25 ms per second, which was the controller lease
   ([learning](../../../../LEARNINGS.md#measure-under-conditions-that-support-the-claim)). `analyze.py` now reports
   `over_25ms_per_s`.
2. **The location of `user://` is part of the measurement.** The app does `user://` file I/O on the main thread.
   The same 0.5 s lease cost 26 ms on a USB flash profile and 7 ms on NVMe. The harness takes `--profile` and the
   README says to keep it on the system drive.
3. **The first pass is a warm-up, whatever the smoke run covered.** Pass 1 ran −6.6 fps on average below passes
   2–4, and up to −38.7 fps (L01). It inflated L01 and L03 and hid the cost of turning MSAA on. Exclude it
   (`exclude_passes_from_deltas` in `conditions.json`) or run a discarded warm-up per configuration.
4. **CPU-bound measurements are 3–5× noisier than GPU-bound ones.**
   - The 3090 flight deltas have a median paired SD of 4.7 fps (1.6 %). With three passes the 95 % interval is
     ±3–11 %. Resolving ±2 % takes about six clean passes (t·SD/√n ≤ 6 fps at n ≈ 6).
   - GPU-bound ladders resolved ±0.2–2 % with three or four passes: the M1 flight ladder and the 3090 Home ladder.
   - Put GPU questions on a GPU-bound view. Give CPU questions more passes, not more configurations.
5. **The host drifts in ways its sensors do not report.**
   - The M1 lost up to 30 % fanless while reporting `fair`, and an attached RustDesk viewer cost 8 %.
   - The 3090 had one −10 % REF transient and two 1.0–1.7 s freezes outside `_process` in 54 runs, cause unknown.
   - REF runs every ten runs and campaign segments caught all of them. Keep both.
6. **The measuring tool is part of the load.**
   - The pilot sends 24 bridge requests per second.
   - Each bridge request is a new TCP connection, so a Windows campaign accumulated about 2,200 sockets in
     TIME_WAIT and needed a retry for WSAEADDRINUSE.
   - Under the separate render thread, the bridge's per-frame GPU timing forces a render-thread sync. That made
     Home unmeasurable until the timing was switched off.
7. **Contamination must be detected during the window, not only at its start.** `host_activity` is sampled at
   launch. A local test started mid-run was caught only because the next run's start saw it.
8. **Kill everything the harness starts.** Killing a campaign left two `nvidia-smi -lms 1000` streams running for
   about eight hours. They turned out not to be the stall, but they are an uncontrolled load.
9. **A cumulative ladder measures marginal costs.** MSAA 8× measured the same as 4× on the M1's Mobile/Metal
   path. Shadows High is measured on top of Standard, not against no shadows. Standalone costs come from the
   scripted knob measurements ([knob costs](../knob-costs-2026-11-18/README.md)), not from this ladder.

## 3. Defects and risks found

| # | Finding | Hosts | Evidence | Status, owner |
| --- | --- | --- | --- | --- |
| D1 | Controller refresh took the cross-process store lease every 0.5 s on the main thread: 7 ms on NVMe, 26 ms on USB flash; missed a 120 Hz refresh twice a second | Windows (APFS is fast) | [report §1](../graphics-ladder-2026-11-19/README.md#1-a-2-hz-main-thread-stall-found-and-fixed) | Fixed (F3-GP-02-R3), including the menu-gamepad case (I1, [§8](#8-implementation-results)) |
| D2 | Home is GPU-bound below the refresh rate: M1 52.6 fps at product defaults (60 Hz), 33.6 fps at L13; 3090 105 fps at L13 4K (120 Hz) | both | Home ladders, 3090 ablation | Fixed by I2: M1 51 → 58–60 fps, 3090 4K L13 97 → 119 fps ([§8](#8-implementation-results)); Retina panel not measured |
| D3 | The crash shader warm-up runs only on Compatibility ([`shader_warmup.gd:9`](../../../../../app/render/crash/shader_warmup.gd)). Mobile's first crash froze 3.4–4.2 s on Windows; the M1, whose Standard is Mobile/Metal, froze up to 520 ms. Compatibility still froze 0.7–2.8 s at L00/L13, so its warm-up misses variants | both | report §5, DT-MAC-03b | Re-measured cold (T4, [§8](#8-implementation-results)): mostly a USB-cache artifact; Compatibility keeps 0.4 s |
| D4 | First use of a profile is slow: Compatibility's first Home → Fly took 20–41 s and Mobile's 11–12 s. Caches were on USB flash, so this is unverified on NVMe | Windows | report §5 | Re-measured on NVMe (T4): Compatibility 12.5 s, Mobile 3.6–4.4 s |
| D5 | Crash frames reach p99 29–30 ms from L06 on at 4K, GPU-bound; at 60 Hz such frames miss a refresh | 3090 | crash ladder | Open: crash with VQ |
| D6 | Projected shadows and the planar cue cost 6.6 % of flight fps in the ladder, with no draw-call change | 3090 | ladder L03 | Re-measured at about 2 % with no runtime culprit (I5, [§8](#8-implementation-results)) |
| D7 | Product code reads RenderingServer GPU/CPU timing every frame ([`auto_calibration.gd`](../../../../../app/render/auto_calibration.gd), `frame_diagnostics.gd`). Under the separate render thread each read is a blocking sync | latent | engine warning, [Godot server wrappers](https://github.com/godotengine/godot/blob/master/servers/server_wrap_mt_common.h) | Open: VQ-07h before any thread-model change |
| D8 | FSR2 adds about 2.3 GB of process RSS at 4K in every mode, while its VRAM report drops | 3090 | report §4 | Located (T12, [§8](#8-implementation-results)): private memory outside Godot's heap from FSR2 set-up |
| D9 | Native physics still costs 0.41 ms per 240 Hz tick, about 10 % of the main thread in flight (GDScript: 0.74 ms) | 3090 | `perf.sim_step_usec` | Profiled (T15, [§8](#8-implementation-results)): a third is GDScript glue in pinned files; physics owners |
| D10 | Host freezes of 1.0–1.7 s outside `_process`, and a −10 % REF transient | 3090 | A/B and REF tables | Unexplained (T10) |
| D11 | D3D12 is 5–11 % slower in flight but 15–17 % faster at Home than Vulkan | 3090 | report §4 | Unexplained (T11) |
| D12 | Harness defects: leaked `nvidia-smi` streams after a kill; `host_activity` checked only at launch; the bridge's `render measure=true` stalls (77–89 ms frames) under the separate render thread | tools | this campaign | Open: harness (I10) |

## 4. Improvement plan

Ordered by player impact and certainty. Each item names its owner, its acceptance evidence and the test that
settles it.

| Priority | Item | Owner | Acceptance |
| --- | --- | --- | --- |
| P1 | **I1** Close D1's menu-gamepad case: skip the locked recheck while connection generations and the store files' size and modification time are unchanged | Controller (F3-GP-02-R3 follow-up) | T1: no periodic long frames at Home and in flight with a menu pad connected |
| P1 | **I2** Home render budget: render Home's 3D at a reduced 3D scale, or cap Home to the refresh rate. Prefer the scale: Home is pixel-bound, and half resolution removed 62 % of its GPU time | Home/UI with VQ-07h | T2: Home holds the refresh at product defaults on the M1 (60 Hz) and at L13 4K on the 3090 (120 Hz), with a reviewed look |
| P1 | **I3** Crash warm-up on Mobile (Apple Silicon's Standard), and the variants Compatibility misses (MSAA level, lens and impact tiers) | Crash (CR-22c follow-up) | T4: first crash in a fresh configuration ≤ 100 ms on M1 Mobile/Metal, Windows Mobile and Compatibility |
| P2 | **I4** Automatic classifies the bottleneck before choosing. Calibration already measures root GPU ms against frame ms. When the GPU is the limit, pull MSAA, shadow-atlas quality, Extreme and reconstruction. When the CPU is the limit, keep visual options and never offer reconstruction as a speed-up. Use per-family cost tables (tile-based versus immediate-mode) from GPU-bound views | VQ-07h ([automatic plan](../../../../plans/automatic-graphics.md)) | T6/T13 data; a decision recorded in DECISIONS |
| P2 | **I5** Projected-shadow script cost: profile `projected_shadow.gd` and the planar cue per frame, then update at a lower rate, cache, or move off the frame (the CR-22e `WorkerThreadPool` pattern) | Shadows owners | Flight L03 delta ≤ 2 % at six passes (T6) |
| P2 | **I6** Ground-view budget: measure, then reduce ground shading cost at full-frame coverage (LOD distance, shader cost) | VQ / landscape owners | T3 |
| P2 | **I7** Separate render thread as a candidate. First replace per-frame RenderingServer getters with low-rate reads (D7), then run T5's qualification. Track Godot [#119000](https://github.com/godotengine/godot/issues/119000), whose exit error is reported to stop the pipeline cache being written, PR [#123391](https://github.com/godotengine/godot/pull/123391), and [#123417](https://github.com/godotengine/godot/issues/123417), a startup crash on macOS arm64 | Godot upgrade (GDU) with PT/DT | T5. No product change while Godot marks it experimental |
| P3 | **I8** FSR2 memory: explain the 2.3 GB RSS before FSR2 becomes an Automatic choice anywhere | VQ reconstruction | T12 |
| P3 | **I9** Physics tick cost: split the 0.41 ms per tick into kernel, adapters and observers (the Gate-P lesson) | Physics / PT | T15 |
| P3 | **I10** Harness: (a) kill orphan `nvidia-smi` at campaign start; (b) sample `host_activity` every 2 s during windows and flag the run; (c) one discarded warm-up run per configuration; (d) a ground-view window and a Home GPU-timing sample per run; (e) keep the bridge's GPU timing off under the separate thread model; (f) reuse one bridge connection | Ladder harness | the next campaign runs without manual exclusions |

## 5. Extra tests, precisely

Every test uses the [graphics ladder](../../../../../research/performance/graphics_ladder/README.md) with
`user://` on the system drive. Pairs are interleaved A B A B. Each needs at least three clean pairs plus a
discarded warm-up run, and the tables give the decision rule.

| # | Question | Setup | Metric and decision |
| --- | --- | --- | --- |
| T1 | Does a menu gamepad bring the stall back, and does I1 remove it? | 3090, Xbox pad connected and selected for menus. L13 4K VSync 120: Home 60 s, then two laps | `over_12_5ms` per second. Pass: no 2 Hz pattern (≤ 0.1 per second) |
| T2 | Which Home budget holds the refresh at an acceptable look? | Home only, 3090 L13 4K and M1 L09 1080p. 3D scale 1.0 / 0.75 / 0.5, MSAA off at Home, and a cap at the refresh. Screenshots of each | Home GPU ms, fps, board power, plus a side-by-side visual review. Choose the largest scale that holds the refresh |
| T3 | What does a view near the ground cost in flight? | New ladder window: a pass at 5 m over the runway and a taxi in chase view. L09 and L13 at 4K/VSync 120 (3090) and 1080p/60 (M1) | Missed refreshes per second and GPU ms against the orbit. Sets the real GPU budget for Automatic |
| T4 | How long does a first crash freeze in a fresh configuration? | Delete the shader and pipeline caches before each run. Forward+ Vulkan and D3D12, Compatibility and Mobile (Windows), Mobile/Metal (M1), each at L00, L09 and L13; before and after I3 | First-crash max frame and first Home → Fly time. Pass for I3: ≤ 100 ms |
| T5 | Is the separate render thread usable? | 60 min per renderer (Vulkan, D3D12, Compatibility; Metal on the M1). A crash every 2 min; alt-tab, minimise, window resize and full-screen toggles every 30 s; quit and relaunch 20 times (pipeline cache written?) | Zero crashes and engine errors, warm second launch, fps and 1 % low gains held. Input-to-photon latency, with a 240 fps camera filming stick and screen, within one frame of Safe |
| T6 | What do CPU-side options really cost? | 3090 flight, L06 → L07 (scenery life), L09 → L10 (Scene detail High), L02 → L03 (projected cue, before and after I5), six passes after warm-up | Paired Δ with ±2 % interval |
| T7 | Where does Automatic's CPU/GPU split move on a weaker CPU? | 3090 host with `powercfg` maximum processor state at 100 / 70 / 50 % (restore 100 %); L09 and L13 at 1080p and 4K | fps, main-thread %, GPU %. Find the CPU speed at which flight becomes GPU-bound |
| T8 | Does the display path change pacing? | Exclusive full screen against borderless; G-SYNC/VRR on with a cap of 117 fps against VSync; HAGS on (owner action, reboot) | `over_12_5ms` %, p99, 1 % low at 120 Hz. Keep the product default unless a variant removes missed refreshes |
| T9 | Do NVIDIA driver options matter? | NVIDIA app, set by hand (owner): Low Latency Mode Ultra, Threaded Optimization on/off, global frame cap | Same metrics as T8. A driver setting is advice to players, not a product change |
| T10 | What are the 1–1.7 s freezes? | 60 min of orbit at L13 with Windows Performance Recorder (CPU, disk, DPC/ISR) running; again with `nvidia-smi` polling off; LatencyMon alongside | Attribute each freeze to a process, driver or DPC. Decide whether the harness or the host causes them |
| T11 | Why is D3D12 faster at Home but slower in flight? | `render` and `ablate` at Home and in flight under both drivers, L13 4K | Per-pass GPU ms and render CPU ms. If D3D12's Home advantage is ground shading, file it for the driver choice in Automatic |
| T12 | Where do FSR2's 2.3 GB go? | 4K L13, MSAA 4× against FSR2 Quality. Godot memory monitors, `video_memory_mib`, process RSS and private bytes (VMMap) | Explain it, or file it upstream |
| T13 | Do the thresholds hold between the extremes? | Smoke plus two ladder passes on a mid-range NVIDIA (RTX 3060 class), an AMD GPU, an Intel iGPU (Iris Xe/Arc) and a Steam Deck class device, as hardware allows | The three-ladder table per host. Calibrates I4's per-family costs |
| T14 | M1 follow-ups | M1 with the controller fix: Home at product defaults, first crash on Mobile/Metal after I3, lock timing on APFS (expected well under 1 ms) | Confirms D2/D3 on the platform where they matter most |
| T15 | Where do 0.41 ms per physics tick go? | Bridge `profile` with the native kernel in flight, Ugly Stik, L09 | Kernel, adapters and observers per tick. Target: the main-thread share of physics |

## 6. Learnings

Reusable lessons belong in [LEARNINGS](../../../../LEARNINGS.md); this campaign added the periodic-stall lesson
there, and the M1 campaign the host-drift lesson. The rest are specific to this kind of measurement and live here:

- **Measure a graphics option in a view that its resource limits.** A CPU-bound flight hides GPU costs; a GPU-bound
  Home shows them with ±1 % precision. Report both before ranking options.
- **Do not transfer option costs between GPU families.** Tile-based and immediate-mode GPUs disagree on shadow
  cascades, atlas quality and scene density, sometimes in sign.
- **Reconstruction only helps a GPU-bound frame.** MetalFX spatial gave the GPU-bound M1 +28 %. FSR2, in every
  mode, slowed the CPU-bound 3090 (−2 to −28 %) and cost memory.
- **VSync is also a power setting.** At 120 Hz the 3090 drew 158 W instead of 350 W for the same displayed frames.
- **The render thread model is the biggest CPU-side lever measured.** It gave +15–33 %, while every graphics option
  moved flight by at most 6.6 %. It is gated by an experimental engine feature and by our own per-frame
  RenderingServer reads.
- **The power plan is not a lever** on a current desktop CPU. High performance was −1 to −2 % against Balanced.

## 7. Corrections to the reports

- **First-pass bias, 3090 report.** Its first version included the first-use pass in the ladder deltas. It
  overstated Scene detail Medium (−2.6 %, now −0.4 %) and the projected cue (−7.9 %, now −6.6 %), and missed the
  resolved MSAA 2× cost (−4.9 %). The report now uses passes 2–4.
- **The single-thread wait.** The 3090 report first said that options move flight fps "only through their CPU
  cost". MSAA also shows in flight, because the single-threaded renderer waits for the GPU in part of the frames.
- **M1 Home.** DT-MAC-03b reported Home as slower than flight. This analysis makes it a product defect (D2): at
  the M1's product defaults, Home runs below the 60 Hz refresh.

## 8. Implementation results

Afternoon of 2026-11-19, P1 items.

During these runs the 4K display was off and the host was driven through RustDesk with a 1080p/60 Hz virtual
display, so no Windows 4K measurement was possible. The M1 runs used its external 1080p/60 Hz display.

**I1: menu-gamepad lease, done (`198141d58`).**

- The service caches the last locked eligibility verdict under a key of every input it reads: device records,
  the active profile, and a lock-free store signature.
- The signature is stat only: existence, modification second and a commit count. It is never cached while a
  file is less than 3 s old, git's "racily clean" rule.
- The signature costs 0.15 ms; the lease cost 6 ms (27–42 ms on USB flash).
- Tests: 61 checks, including another process's write that removes the pad from menus. The caching checks fail
  on the previous code.

**I2: Home render budget, implemented.**

- **What it does.** `app/render/home_render_budget.gd` watches Home's frame intervals in rolling 90-frame windows
  while Home is the focused top screen. Frames over 4× the target, such as stalls or pauses, do not count. After
  two slow windows it lowers the 3D scale to ×, then ×. A step that does not cut the mean interval is undone,
  and the budget stops for the visit.
- **Where it acts.** Only on bilinear and FSR 1 scaling.
- **Ownership.** It owns the scale only while the viewport holds its value under the same reconstruction policy
  object, so a Settings apply is recognised even when it writes the same value.
- **Covering and leaving Home.** A screen over Home, focus loss or minimising restores the player's scale.
  Uncovering Home under the same setting re-applies the kept step without measuring again. Leaving Home forgets the
  visit.

M1 results, product defaults, VSync at 60 Hz, on the external 1080p display:

| Home | fps | p50 | p95 | 3D scale |
| --- | --- | --- | --- | --- |
| Without the budget (3 runs) | 51.–1.5 | 18.–9.0 ms | 2–7 ms | 1.0 |
| With the budget (5 runs) | 57.–9.5 | 16.–6.6 ms | 2–5 ms | 0.85 or 0.7 |

- **M1 behaviour.** Some runs held at ×. Others went to ×, kept it when it helped, or returned to × when
  it did not. About – % of Home frames still miss the refresh at any scale, so that share is not GPU work.
- **Flight.** It always started at the player's scale.
- **Windows.** At 1080p Home ran at 266 fps and the budget held at 1.0.
- **Not yet measured.** The M1's native Retina panel, which the platform rules make its target. The 3090 at 4K
  follows below.
- **Decision rule.** Two earlier variants of the rule failed on the M1, and the final rule incorporates both lessons:
  - A one-shot decision taken about 3 s after launch missed that Home grows heavier once its preview loads.
  - A 5 % miss-share threshold chased the non-GPU misses and gave the resolution back.
- **Review.** A Good Enemy review found the stale-state, coincident-write, focus, outlier and flapping gaps, now
  fixed and covered by 36 checks in `test_home_render_budget.gd`.
- **Evidence.** The ladder now records the budget's decision (`home_render_budget`, `home_scale`) with every run's
  Home frames.

**I2 and T3 on the RTX 3090 at 4K, 120 Hz VSync (later the same day, with the TV added to the desktop next to
the remote session's virtual display).** Each launch measured Home, then a runway start: the pilot station's view
of the aircraft on the ground, a ground-filling flight view. These are A/B pairs plus one discarded warm-up.

| Configuration | Home without budget | Home with budget | Runway (flight, player's scale) |
| --- | --- | --- | --- |
| L09 (product defaults) | 112–113 fps, GPU 7.6 ms | 120.0 fps at ×0.85, GPU 6.0 ms | 118.5–119.9 fps, GPU 5.4–5.9 ms, 1 % low 60–71 |
| L13 (every option on) | 96–99 fps, GPU 8.7–9.2 ms | 118.9–119.1 fps at ×0.85, GPU 7.2 ms | 115–116 fps, GPU 7.2 ms, 1 % low 56–63 |

- Even product defaults missed 120 Hz at Home on the 3090; the budget holds it at both levels.
- A view near the ground costs 2.5–3.3× the orbit's 2.2 ms of GPU. At L13 it sits at 87 % of the 8.3 ms budget
  and misses about 4 % of refreshes; L09 holds. This is the GPU budget Automatic must plan for at 4K/120 Hz (I6).

**I5: projected shadows, investigated, not optimised.**
- **The ladder's cost shrank.** Under the corrected conditions (fixed controller code, profile on C:), L02 → L03
  costs about 2 % of orbit fps (≈278 → ≈272 over six alternating windows), not the ladder's 6.6 %.
- **No runtime node holds it.** Hiding and stopping the field projectors, the aircraft shadow, or both changed fps
  by less than ±1 %.
- **Redraw rates.** The aircraft silhouette redraws 7–8 times a second, so its reuse works. The windsock
  silhouette (512²) redraws every frame, 238 times a second, because of its flutter. Stopping it cost nothing
  measurable on this CPU. It stays a candidate for weak CPUs only.

**I3: crash warm-up on Mobile, not shipped.** T4 re-measured the first crash with Godot's shader cache cleared
and the profile on a system drive, A against B (warm-up also on Mobile):

| Host, renderer | First crash, longest frame | First Home → Fly |
| --- | --- | --- |
| Windows, Mobile/Vulkan L00 and L13 | A 33–48 ms, B 33–42 ms | 3.6–4.4 s |
| Windows, Compatibility L13 (warm-up active) | 405 ms | 12.5 s |
| Windows, Forward+ L09 | 20 ms | 4.2 s |
| M1, Mobile/Metal L09 | A 78 ms, B 62–71 ms | 4.0–4.7 s |

- The campaign's 3.4–4.2 s Mobile stalls and 20–41 s Compatibility loads came from the shader cache living on the
  USB flash drive.
- The Mobile warm-up showed no measurable benefit on either host, so it was not added.
- What remains is Compatibility's 0.4 s first crash in spite of its warm-up, an open item for the crash owners.
- Apple's own Metal cache stayed warm on the M1, so a first launch after an OS update is not covered.

**Compatibility first crash, bisected (cold, fresh profile per run, 4K).** Where the first crash's longest
frame goes:

| Configuration | First crash, longest frame | Impact |
| --- | --- | --- |
| L09 | 48 ms, 47 ms | lamp mast, fence |
| L00 | 116 ms, 574 ms | airframe contact, prop strike and nose gear |
| L13 | 405 ms, 766 ms | prop strike and nose gear, lamp mast |

- The stall is rendering work: `process_ms` ≤ 29 ms and physics ≤ 2.6 ms in those frames, and nothing is logged
  even with `--verbose`. That fits OpenGL compiling shaders on the main thread.
- The lens stack and the CR-22c crash warm-up both run on Compatibility, yet a gap remains. It depends on the
  settings and the impact type, and possibly on NVIDIA's own GL shader cache, which runs share.
- **Hand-off to the crash owners:** a deterministic crash (`checkpoint` + replay) and a per-effect check under each
  settings level.

**I9: main-thread physics and audio (GDScript profile, circling flight, native kernel, L09 4K).**

- **Physics.** `simulation.gd` `step` is about 10 % of the frame at 275 fps. About a third of each tick is GDScript
  glue around the native kernel: `_kernel_pre_step`, `_array_is_finite` (≈400 calls per tick),
  `lake_surface.is_valid_definition`, and the terrain micro-relief sampling. Those files are in the pinned
  `app/physics`/`app/sim` set, so this is a candidate for the physics owners (solver identity renewal), not done
  here.
- **Audio.** The glow engine's procedural voice (`glow_voice.gd` `render_telemetry`, `_exhaust_wave` about 24,000
  calls a second) runs on its own worker thread (`glow_audio_pump.gd`). It costs about 6 % of another core, which
  is the second-busiest thread in every ladder run, and takes nothing from the frame. It also runs when the app is
  muted.

**I8: FSR2's memory (L13 4K, two pairs, MSAA 4× against FSR2 Quality).**

| Flight, after 8 s | MSAA 4× | FSR2 Quality |
| --- | --- | --- |
| Process private bytes | 5.1–5.3 GB | 7.4–7.7 GB |
| Godot static memory | 565 MiB | 620–630 MiB |
| Godot video memory | 2.32–2.36 GB | 2.02 GB |
| `nvidia-smi` memory used | 5.8–5.9 GB | 5.59 GB |

- FSR2 adds 2.3–2.5 GB of private memory outside Godot's heap, while GPU memory falls.
- It is already there at Home, so it comes with FSR2's set-up: driver-side pipelines or shader permutations, to
  confirm with a minimal project.
- Until explained, Automatic should not choose FSR2 on hosts with 16 GB or less.

**I10: harness, partly done.** `ladder.py` now:

- kills orphaned `nvidia-smi` streams at start;
- samples competing engines and remote sessions every 10 s during each window;
- continues once, and records it, when a cold load lost focus and AppRoot opened Pause.

One real Windows run checked these changes:

- the orphan kill ran (it found none);
- the in-window sampling recorded the active RustDesk session;
- the Home budget's decision was recorded.

The resume-after-Pause path has not yet triggered in a real run.

Learned on the way:

- The Microsoft Store Python redirects new folders under `%APPDATA%` to its package `LocalCache`. A profile there
  survives a `rm -rf` of the `%APPDATA%` path, which silently invalidated a "cold" series. Keep `--profile`
  outside AppData.
- A process filter that matches its own command line kills the shell running it.

## Evidence

- Windows: `D:\OpenRCsimulator-evidence\gfx-ladder-win-20261119`. It holds the run folders, `summary-v2.*` with
  pass 1 excluded and the Home and crash ladders, the A/B, thread, power, Home render and ablation JSON, and the
  experiment plans.
- M1: `D:\OpenRCsimulator-evidence\gfx-ladder-20261118` (`summary-v2.*`).
- Godot facts on the thread model and shader compilation were checked on 2026-11-19 against the class reference,
  the engine's `server_wrap_mt_common.h` and the issues linked above, at master, not the 4.8-beta2 tag. The
  OpenGL shader compilation path is described in Godot
  [#86731](https://github.com/godotengine/godot/issues/86731).
