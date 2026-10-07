# DT-00 — Performance and acceptance

2026-10-07 · **Measurement design; no new performance benchmark executed.**

## Existing capabilities

`app/main.gd` and `app/render/frame_samples.gd` already produce `openrc-frametimes v2`: raw monotonic intervals, percentiles, render settings, adapter, simulation ticks and provenance. Reuse this protocol. Its physics cost is smoothed, not a per-tick distribution or GPU duration. `--scripted` follows a visual path and is unsuitable for proving live flight throughput. The [VQ-01b evidence](../../visual-quality-implementation/VQ-01b/README.md) distinguishes these cases and software rendering from hardware evidence.

`app/project.godot` fixes physics at 240 Hz and allows 12 catch-up steps/frame. The scheduling floor is therefore 240/12 = 20 render frames/s. Godot documents that insufficient frame throughput can slow simulation time. Increasing this limit or lowering physics frequency would change a simulation policy owned by the physics line. [Engine](https://docs.godotengine.org/en/stable/classes/class_engine.html).

The existing Phase H/Gate P work owns the 500 µs/tick budget and any GDExtension decision. Concurrent propwash changes make earlier performance figures historical. Rebaseline a frozen candidate; do not advertise their speed as current desktop acceptance.

## Findings from primary sources

| Finding | Application to this simulator | Source |
| --- | --- | --- |
| Profiling must distinguish CPU and GPU bottlenecks; results vary by hardware | Change one measured cost at a time; keep paired before/after runs | [Godot optimization](https://docs.godotengine.org/en/stable/tutorials/performance/general_optimization.html) |
| 3D scale reduces pixels quadratically; bilinear is supported across renderers, FSR modes require Forward+ | Retain Compatibility; prototype 1.0/0.85/0.75 only if GPU-bound, with aircraft readability evidence | [Resolution scaling](https://docs.godotengine.org/en/stable/tutorials/3d/resolution_scaling.html) |
| Compatibility lacks the modern ubershader/pipeline precompilation path | Investigate first-use shader stalls on hardware; if demonstrated, draw required materials during a bounded loading stage | [Shader compilation](https://docs.godotengine.org/en/stable/tutorials/performance/pipeline_compilations.html) |
| Ordinary resource loading blocks; collecting a threaded load too early also blocks | Split load/instantiate/draw timings before deciding whether background loading helps | [Background loading](https://docs.godotengine.org/en/stable/tutorials/io/background_loading.html) |
| Adaptive/Mailbox modes fall back in Compatibility; driver/platform restrictions apply | Offer only verified VSync controls and readback, then measure actual pacing; a setting is not proof of synchronization | [DisplayServer](https://docs.godotengine.org/en/stable/classes/class_displayserver.html) |

1280×720 → 3840×2160 increases render pixels by **9×** (arithmetic, not a predicted 9× frame-time increase). Fullscreen should not silently imply a high-end graphics preset. Lowering 3D scale may destroy the silhouette of a distant RC model; keep UI crisp and require the visual team's existing blinded attitude/readability assessment before shipping reduced scale.

## Reproducible measurement design

1. Freeze a clean candidate commit and final package SHA-256. Record CPU/GPU/RAM, OS/build, driver, renderer, power mode, display resolution/refresh/DPI, VSync, cap, aircraft, field, scenery and camera. Record thermal state and competing workloads.
2. Measure process launch → interactive Home and Fly → first interactive flight frame separately. Ten fresh-process starts; record every sample, median and maximum. Label cold cache only with a documented OS/driver-cache procedure; a fresh process alone is not cold cache. Include failed/time-out runs.
3. Three fresh processes per steady-state case, each 10 s warm-up + 60 s measurement. Alternate baseline/candidate runs under matching conditions. Preserve all raw intervals; report each run plus a summary, without averaging away the worst run.
4. Separate uncapped/VSync-off capacity tests from normal capped/VSync-on presentation tests. Verify the effective mode; compositor/driver policy can override a request. Use real hardware with a display. llvmpipe and headless results prove tooling only.
5. Run a repeatable visual path for GPU comparisons and a live-physics workload for real-time performance. For the latter, assert physics enabled, not paused/faulted, active catalog aircraft and known inputs. Avoid `--scripted`. Stalls, spin, ground contact and powered flight use physics-team fixtures/replays, not a newly invented aero benchmark.
6. Compute simulation/wall-time ratio using the same sampled frame-end interval: Δticks/240 divided by matching monotonic elapsed seconds. Exclude intentional pauses explicitly. Do not compare a full-run wall clock to a post-warm-up simulation interval.
7. Measure radio-to-visible-response latency using the existing F6 method (high-speed recording, ≥20 trials, median/p95); an engine callback timestamp omits USB and display latency. Coordinate input changes with its owner.
8. Run 30 minutes of use plus 50 Home → Fly → End flight cycles for resource lifetime. Check stable counts after warm-up, native RSS/VRAM where available, audio shutdown and saved state. Never interpret a release-only unavailable counter as zero leakage.

Existing exported-binary logger command (Linux example; visual workload only):

```bash
./openrc-simulator.x86_64 --windowed --resolution 1920x1080 --disable-vsync -- --scripted --frametimes=run-1.json --warmup=10 --t=60 --case=desktop-visual
```

Run against an unpacked package outside the source tree; no `--path app`. Repeat with the same settings for both candidates. Native platform adapters and live-replay cases are future DT-01/DT-10 work.

## Proposed thresholds and decision rules

These are initial engineering targets, not measurements or vendor requirements. DT-01 records named reference hardware and freezes accepted budgets before optimization. A miss requires evidence and an explicit scope/budget decision, not silent threshold relaxation.

| Metric | Initial target | Evidence/limit |
| --- | --- | --- |
| Startup on reference SSD | Interactive Home ≤3 s warm and ≤5 s controlled cold in all 10 runs | Excludes download and OS trust prompts; records native transitions |
| Home → Fly | ≤2 s in all 10 runs; visible acknowledgement ≤100 ms if work is longer | Include scene construction and first draw; do not optimize by starting physics unseen |
| Flight presentation at 60 Hz | p95 ≤18 ms; p99 ≤25 ms; no unexplained interval >100 ms in each measured run | Own tolerance around a 16.67 ms refresh; investigate tails, not mean FPS alone |
| Simulation real time | Ratio 0.99–1.01 over the aligned 60 s unpaused sample | Independent of a smooth scripted visual path |
| Higher refresh | Same raw-report method at 120/144 Hz; optional until a hardware tier is accepted | No implied 144 FPS promise |
| Physics | Existing 500 µs/tick Phase H/Gate P contract | Physics team owns the detailed statistic, fixtures and exceptions |
| Input latency | Existing F6 proposal: median ≤50 ms, p95 ≤70 ms at 60 Hz | Requires real radio/high-speed recording |
| Optimization retention | Relevant median cost improves ≥10% and exceeds observed run variation; no >5% p95 regression elsewhere | Proposed screening threshold; startup, energy and memory fixes state their own metric |
| Idle/minimized cost | Investigate if active-style rendering continues; seek ≥50% CPU/GPU active-time reduction against baseline | Restore immediately on focus; UI confirmation timers still run |
| Memory lifecycle | No continuing retained-node/resource growth after warm-up; RSS plateau explained | Cache growth is distinguished from leaks; no invented universal MB limit |

Optimization order: remove measured redundant work → bounded loading/shader preparation → Home/minimized power use → explicit render-scale/MSAA quality choice with readability review. Preserve double-precision state, physics ticks, radio sampling and goldens. Avoid renderer migration, custom engine builds, executable packers or a native physics port without a separate demonstrated need.

## Package acceptance is a separate proof

Use a clean user account and the downloaded release artifact on each supported OS. Check Home, fullscreen, real radio, Fly, focus pause, restart, End flight, graceful Quit, active trace shutdown and relaunch persistence. Record the package digest and test host. Source/editor tests and package structure checks are prerequisites, not substitutes.

The current [export pipeline](../../../../app/export.sh) runs only the Linux executable, and CI uses Ubuntu. Windows/macOS execution, Gatekeeper/SmartScreen, Retina and native Wayland remain open hardware/OS evidence. Package acceptance does not close Gate 2 (pilot realism/readability) or Gate P (physics headroom).
