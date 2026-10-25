# I15–I20 — Runtime, tools and cross-generation qualification

2026-10-24 · DT-MAC-00-R1 · Internet research, not native measurements. The user confirms a MacBook Air M1 with 8 GB is available; GPU core count and macOS remain unidentified. [Investigation index](README.md) · [Execution plan](../../../plans/apple-silicon-performance.md).

## I15 — CPU scheduling, threading and loading without numerical drift

**Question.** How can more capable M-series CPUs help while retaining the M1 baseline and the 240 Hz float64 kernel?

**Findings.** Apple recommends describing work with QoS and allowing the OS to schedule heterogeneous cores. Static equal-sized work partitions and active spin waits can perform poorly on asymmetric processors. This supports profiling and bounded tasks, not pinning the flight thread to a guessed performance core. [Apple Silicon tuning](https://developer.apple.com/documentation/apple-silicon/tuning-your-code-s-performance-for-apple-silicon/).

Godot does not make active scene-tree access thread-safe; its separate rendering-thread mode has documented limitations. Background resource loading is available, but retrieving a resource before completion can block the caller. Neither feature automatically parallelizes OpenRC's own simulation. [Thread-safe APIs, 4.7](https://docs.godotengine.org/en/4.7/tutorials/performance/thread_safe_apis.html), [background loading, 4.7](https://docs.godotengine.org/en/4.7/tutorials/io/background_loading.html).

**Plan consequence.** Optimize measured allocation/validation/contact costs first. Only move independent resource preparation to existing workers after profiling; publish into the scene through the existing owner thread and retain failure/cancel semantics. Do not enable physics-server threading as a supposed accelerator for the custom kernel. A native evaluator remains subject to the [SF backend policy](../../../STACK.md#boundaries-and-data-flow), including fallback and parity.

**Test.** On the available M1, compare CPU stacks, loading p95, audio underruns, tick cost and same-input exact replay before/after one change. Repeat scheduling-sensitive work on a later-generation Mac; do not equate logical CPU count with worker count.

**Limit.** No worker-pool change or ARM64 speedup has been measured. Native QoS advice is not evidence that GDScript exposes or needs a new scheduling API.

## I16 — Retina, ProMotion, frame pacing and responsiveness

**Question.** How can a faster Mac still feel worse, and which display settings should vary?

**Findings.** Godot separates jitter, stutter and input latency. Its documented double-buffering option trades lower queue latency for less tolerance when a display deadline is missed. Therefore a swapchain reduction is a conditional experiment, not a universal optimization. [Godot jitter/stutter guide](https://docs.godotengine.org/en/4.7/tutorials/rendering/jitter_stutter.html).

Apple's `CAMetalDisplayLink` supports display-synchronized timing and variable-rate displays; its documented availability begins with macOS 14. This describes an engine integration facility, not proof that the pinned Godot export uses it or that it should be reimplemented in OpenRC. [Apple display-link API](https://developer.apple.com/documentation/quartzcore/cametaldisplaylink).

**Plan consequence.** Freeze 1080p **drawable** pixels and 60 Hz first; record logical window size, internal 3D dimensions, refresh/VSync mode, render cap and composition state. Qualify Retina/native-panel resolution and 120 Hz separately after 1080p. Preserve the project's existing custom camera interpolation; generic advice to enable another interpolation layer is not directly applicable.

**Test.** Compare windowed and native fullscreen, then external-display connection/migration and sleep recovery. On a ProMotion-capable host test fixed 60 Hz and variable/high refresh with the same route. Use presented intervals plus pilot/controller response, not average FPS alone. Run buffer-count experiments only after consistent budget headroom is established.

**Limit.** No display API change is proposed for the initial implementation. M1 models differ in displays; an external high-refresh result does not qualify every built-in panel.

## I17 — Thermal behavior, power modes and Game Mode

**Question.** How should settings remain usable across Air, Pro, mini and Studio chassis and battery states?

**Findings.** Apple exposes nominal/fair/serious/critical thermal states and recommends reducing discretionary CPU/GPU/I/O work when thermals become severe. State is system-wide; it does not identify OpenRC as the cause or provide a temperature measurement. [Thermal guidance](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/RespondToThermalStateChanges.html).

Game Mode is available on Apple Silicon with macOS 14+ and compatible native macOS fullscreen. It changes CPU/GPU priority and wireless-accessory behavior. Its effective state must be recorded instead of assuming that a maximized window or borderless presentation activates it. [Apple Game Mode requirements and behavior](https://support.apple.com/en-us/105118). Power-mode availability is model/OS-specific. [Apple power modes](https://support.apple.com/en-us/101613).

**Plan consequence.** Keep AC, battery, Low Power Mode and Game Mode conditions explicit. Default to a measured fixed visual preset; any future automatic quality adaptation changes presentation only, with hysteresis and user override. Never slow the solver or silently hide collidable obstacles to save power.

**Test.** Run matched 30-minute sessions from comparable starting conditions, recording early/late timing, memory, power and available thermal telemetry. Test actual fullscreen with Game Mode on/off as a separate factor, plus minimize/resume and Bluetooth/USB controls. If the available M1 is actively cooled, leave fanless acceptance open.

**Limit.** No promised battery-life multiplier. Unsupported thermal telemetry is unavailable, not a fabricated nominal reading. Game Mode is not a substitute for meeting the baseline budget.

## I18 — Free profiling tools and their coverage boundaries

**Question.** Which existing tools identify the cause of poor performance without building another profiler?

**Findings.** Instruments Game Performance/Metal System Trace correlates CPU activity with GPU work and display intervals. Xcode's Metal tools expose pass/resource/counter inspection; a gap on the GPU timeline can originate on the CPU. [Apple performance analysis](https://developer.apple.com/documentation/xcode/analyzing-the-performance-of-your-metal-app), [Metal tools](https://developer.apple.com/metal/tools/).

Apple's WWDC26 session introduces Game Performance Overview, `metalperftrace` analysis/JSON and runtime-state correlation. These newer workflows require verification of installed OS/Xcode/tool availability; they are optional diagnostics, not a reason to raise the product OS floor or add automatic telemetry. [WWDC26 performance tools](https://developer.apple.com/videos/play/wwdc2026/388/).

**Plan consequence.** Keep three observation levels: release frame/resource receipts; short Instruments/HUD attribution; a targeted GPU capture with validation. Record tool version, available counters and observer overhead. Use the existing debug bridge and frame reducers as the application interface. GPU-capture runs cannot establish uninstrumented release throughput.

**Test.** Produce one M1 CPU-attributed hitch, one GPU-attributed capture and an observer-on/off comparison for the same scene. Correlate capture time with Home/Fly/Workshop and pause markers. Test bounded collection and incomplete outputs before relying on the 30-minute report.

**Limit.** Tool features/counter availability differ across GPU generations and OS releases. A new GPU profiler feature advertised for later silicon is not required on M1; use the supported timeline/CPU tools when a counter is unavailable.

## I19 — Native exports, dependency slices and CI versus hardware

**Question.** What proves the optimized app actually runs natively on the whole requested Mac range?

**Findings.** Godot's official macOS exports use Universal 2 bundles, with ARM64 and x86_64 support. Exporting and signing are distinct from native execution and performance. Distribution must preserve executable permissions and complete nested dependencies. [Godot macOS export guide](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_macos.html).

Debugger attachment can require the `get-task-allow` entitlement, which Godot documents as incompatible with the normal notarization path. Keep any profiling build identity distinct from shipping bytes. [Godot Mac debugging](https://docs.godotengine.org/en/4.7/engine_details/development/debugging/macos_debug.html). GitHub currently lists ARM64 Mac VMs with resource allocations unlike a full physical Mac; runner labels/specifications can change. [GitHub hosted runners](https://docs.github.com/en/actions/reference/runners/github-hosted-runners).

**Plan consequence.** Retain the existing universal delivery while qualifying its ARM64 execution. Validate every optional native library, engine/template identity, minimum OS and final downloaded package. Add native CI as software coverage; reserve display, thermals, USB/audio and full-flight acceptance for physical machines. Do not require five separate chip-specific executables or compile globally for M5 instructions.

**Test.** Native M1 launch from the final package, dependency/slice audit, golden/H9 checks, debug-bridge smoke and release soak; repeat the same package on named M2–M5 hosts. A debugger-friendly candidate must be followed by uninstrumented final-release checks.

**Limit.** This research installs no runner and starts no paid service. Signing/notarization remain DT-owned release work; neither a CI pass nor a valid ARM64 slice proves M1–M5 qualification.

## I20 — Capability-based presets and a defensible M1–M5 claim

**Question.** How can one product scale across the five generations without guessing performance from the chip name?

**Findings.** Apple recommends querying both GPU capabilities and software/API availability. Features can vary within a GPU family, so the family number alone is insufficient for every optional path. [Detecting GPU/software features](https://developer.apple.com/documentation/metal/detecting-gpu-features-and-metal-software-versions). Godot's feature tags identify platform, architecture, build context and some texture capabilities; they are not a benchmark or thermal-quality tier. [Godot feature tags](https://docs.godotengine.org/en/4.7/tutorials/export/feature_tags.html).

**Plan consequence.** Separate capability selection from quality selection. A shared ARM64 release chooses only supported renderer/reconstruction paths; conservative measured defaults and existing user preferences choose quality. Unknown combinations inherit the tested baseline where capabilities permit. A faster chip may use higher quality only after workload evidence. Keep requested and effective modes visible, with Native reconstruction and Standard recovery.

**Test.** Maintain rows for M1, M2, M3, M4 and M5, with exact chip variant, chassis, RAM, OS/build, driver, package hash and result. For each available host, run the same 1080p reference circuit, numerical checks, shader/lifecycle smoke and sustained test. Include one small-memory/fanless class and one actively cooled class across the final claimed coverage. Capability-denial, old/unknown preferences and failed initialization must recover without changing physics.

**Limit.** The product objective covers all five generations; measured support initially covers none until the available M1 is tested. Representative generation coverage reduces risk but cannot prove every SKU/OS combination. Publish tested rows and untested scope rather than a generation-wide speed guarantee.

## Method and source access

All six investigations used online primary sources on 2026-10-24. Apple DocC pages that returned JavaScript-only HTML were read through their linked Markdown representations; ordinary pages and the WWDC transcript were opened directly. Recommendations/tests are project proposals, distinguished from sourced API facts. No application code, machine settings, benchmark baselines or hardware were changed.
