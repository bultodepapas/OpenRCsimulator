## Main findings

I found **two concrete performance problems**, **two smaller optimization candidates**, and **one secondary visual consistency bug** that were not already described in the audit history.

The strongest Mac-specific finding is that **starting or stopping a qualifying flight recording synchronously hashes the entire application bundle—including its PCK—from the input-handling path**. The other confirmed problem is persistent CPU work: **after a checkpoint restore disables statistics recording, the observer continues constructing statistics samples at every accepted physics tick, then discards them**.

I read `external Audits/CONSOLIDATED-AUDITS.md` before reviewing the implementation and cross-checked the findings against the updated ledger through **A22**, the completed-work ledger, and relevant original audits. I used GitHub tools to inspect source, commit changes, issues, pull requests, release configuration, and CI.

The executed probes used commit **`ece94f9`**. I checked the affected code again against **`347905c`**, which remained the branch head at the closing check. The findings below still apply there.

**Hardware limitation:** the available runtime was Linux x86_64. I ran the project’s exact pinned Godot version in isolated probes, but had no Apple Silicon machine available. Consequently, this review contains **no measured Mac FPS, Metal GPU timings, battery figures, or sustained thermal results**.

The reproducible probes, source hashes, checked logs, and detailed evidence limits are available here:

[openrc-apple-silicon-review-evidence-2026-11-06.zip](https://chatgpt.com/library?file_id=libfile_fde3_f-44b5cd1485688191a669bbc2a1e15322_ac5d15b10f548191b3cb750779cf7c10&account_id=personal)

## 1. Actual engine, renderer, and Mac build configuration

Your project already has a deliberate Apple Silicon path. Recommending a generic migration to Metal would repeat previous work.

| Area | Verified configuration | Implication |
|---|---|---|
| Godot | **4.8 beta 2**, exact executable version `4.8.beta2.official.cafc17a19` | Recommendations must match this development version. |
| Mac editor | `get-godot.sh` downloads the dedicated **ARM64** editor, checks its executable architecture and exact version, and retains the app bundle | The intended development path is native ARM64. |
| Apple Silicon renderer | `renderer/rendering_method.arm64="mobile"` | Native ARM64 selects **Mobile** unless another accepted configuration overrides it. |
| Rendering driver | The pinned engine’s macOS RenderingDevice default is **native Metal** | Mobile on this path does not require MoltenVK. |
| Other default renderer | `gl_compatibility` | Intel/Rosetta execution does not receive the ARM64 renderer override. |
| Mac export | **Universal**, ARM64 and x86_64; official pinned templates; `--export-release` | The export pipeline targets a native Apple Silicon slice and a release template. |
| Simulation | Custom reference solver, **240 Hz**, RK4, float64 simulation data | Rendering optimizations should preserve this numerical contract. |
| Catch-up limit | **12 physics steps per rendered frame**, jitter fix `0.0` | Maximum catch-up per frame represents 50 ms of simulation. |
| Antialiasing | Default `msaa_3d=2`, meaning **4× MSAA** | This belongs in the baseline before considering quality changes. |
| Display defaults | VSync enabled, FPS cap `0`, reconstruction `auto` | An uncapped request does not establish that the application actually renders without synchronization. |
| Native flight evaluator | The NK-3 loader is explicitly **Linux x86_64 only** | The Mac runs the native ARM64 engine with the reference GDScript flight solver. |

The configuration is visible in [`project.godot`](https://github.com/bultodepapas/OpenRCsimulator/blob/ece94f9ede8c90c92652ebce68196f81eded6c70/app/project.godot), [`get-godot.sh`](https://github.com/bultodepapas/OpenRCsimulator/blob/ece94f9ede8c90c92652ebce68196f81eded6c70/app/get-godot.sh#L4-L28), [`export_presets.cfg`](https://github.com/bultodepapas/OpenRCsimulator/blob/ece94f9ede8c90c92652ebce68196f81eded6c70/app/export_presets.cfg), [`export.sh`](https://github.com/bultodepapas/OpenRCsimulator/blob/ece94f9ede8c90c92652ebce68196f81eded6c70/app/export.sh#L116-L139), and [`native_stage.gd`](https://github.com/bultodepapas/OpenRCsimulator/blob/ece94f9ede8c90c92652ebce68196f81eded6c70/app/sim/native_stage.gd#L305-L307). The Metal default is also present in the [exact pinned engine source](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/doc/classes/ProjectSettings.xml#L3387-L3392). Godot’s official beta announcement confirms the `cafc17a19` build. [Godot Engine](https://godotengine.org/article/dev-snapshot-godot-4-8-beta-2/?utm_source=chatgpt.com)

**I did not establish unintended Rosetta execution.** A universal configuration and structural export checks support native execution, but the actual shipped process and loaded libraries still need inspection on a Mac. Apple documents that universal binaries normally select the native slice, while users can explicitly request Rosetta; architecture must therefore be checked on the running game as well as on disk. [Apple Developer Documentation](https://developer.apple.com/documentation/apple-silicon/building-a-universal-macos-binary?changes=la__6__1\&language=objc\&utm_source=chatgpt.com)

## 2. Highest-priority new finding: F10 performs whole-bundle hashing synchronously

**Priority:** high investigation priority for responsiveness.  
**Evidence:** confirmed call chain and portable execution of the production validation helper; Mac frame impact remains unmeasured.

### Affected code

The relevant path is:

- [`main.gd:2033–2042`](https://github.com/bultodepapas/OpenRCsimulator/blob/ece94f9ede8c90c92652ebce68196f81eded6c70/app/main.gd#L2033-L2042): F10 calls flight-log start or stop inline.
- [`flight_log.gd:46–60`](https://github.com/bultodepapas/OpenRCsimulator/blob/ece94f9ede8c90c92652ebce68196f81eded6c70/app/sim/flight_log.gd#L46-L60): start obtains the replay identity.
- [`flight_log.gd:136–150`](https://github.com/bultodepapas/OpenRCsimulator/blob/ece94f9ede8c90c92652ebce68196f81eded6c70/app/sim/flight_log.gd#L136-L150): stop revalidates the qualifying Mac identity before finalizing.
- [`flight_log.gd:382–391`](https://github.com/bultodepapas/OpenRCsimulator/blob/ece94f9ede8c90c92652ebce68196f81eded6c70/app/sim/flight_log.gd#L382-L391): the macOS release route calls `NativePackage.mac_reference_identity`.
- [`native_package.gd:229–248`](https://github.com/bultodepapas/OpenRCsimulator/blob/ece94f9ede8c90c92652ebce68196f81eded6c70/app/app_state/native_package.gd#L229-L248): recursive inventory computes `FileAccess.get_sha256()` for every regular bundle file.

This affects the qualifying packaged Mac reference-recording route. A missing receipt, refused recording, or another recording owner can take a different path.

### Why this matters

Let \(B\) be the total bytes covered by the bundle inventory. Each successful boundary performs work proportional to \(B\), including file traversal and hashing. A start/stop pair therefore processes approximately **\(2B\) bytes**, independently of how few flight-log rows were recorded.

The main thread cannot finish that input callback while the scan is running. Cold storage can add I/O delay; repeated checks still require hashing and memory traffic. That creates a credible source of a noticeable control or presentation interruption on a MacBook.

The recorder’s `observer_usec` does not include this boundary cost: start resets it after admission, and ordinary accumulation occurs in observation callbacks. Wall-frame collection and Instruments can still capture the interruption.

### Portable measurement

I called the unchanged production helper with real synthetic PCK files using the exact pinned Linux Godot editor.

| Synthetic PCK payload | Repeated validations | Median helper duration on the Linux test host |
|---:|---:|---:|
| 16 MiB | 3 | 65.061 ms |
| 64 MiB | 3 | 261.906 ms |
| 256 MiB | 3 | 1,248.429 ms |

The setup created and hashed the files immediately before the repeated checks; it was not a controlled cold-cache experiment. Unchanged files produced stable identities, and same-size PCK mutations were refused.

**These figures demonstrate scaling in the portable test environment. They cannot predict the duration on an M1, M4, or a real release bundle.**

### Concrete improvement

Move the expensive file inventory and hashing into a bounded admission/finalization job, with explicit recording states:

1. **Start requested:** validate asynchronously using owned file-path and receipt data. After successful admission, capture a **fresh** checkpoint on the main thread and begin recording at a defined accepted boundary.
2. **Stop requested:** freeze the intended final tick, events, checkpoint, and writer ownership immediately. Perform final validation asynchronously, then commit the success footer.
3. **Transition handling:** serialize repeated F10, restart, exit, cancellation, and failure paths so completion from an old request cannot affect a new flight.

Preserve both byte-level checks. A startup-only hash, file-size check, or modification-time cache would change the existing replay-identity guarantees.

A reused worker is appropriate for owned file-data work. Active scene access and session snapshots should remain on the main thread; Godot explicitly documents scene-tree and rendering-thread restrictions. [Godot Engine (latest) documentation in English](https://docs.godotengine.org/en/latest/tutorials/performance/thread_safe_apis.html?utm_source=chatgpt.com)

### Validation before adoption

On a valid ARM64 release bundle, measure repeated start/stop operations during representative flight, separating first-use and repeated checks. Record the largest frame interval, accepted ticks, simulation/wall-time ratio, input response, process I/O, and completion/refusal status.

Then compare the asynchronous candidate under the same workload. Background hashing can still compete for storage and memory bandwidth, so removing the main-thread wait does not by itself prove a complete-frame improvement.

**Novelty:** earlier logging documentation discusses bounded row serialization and flush stalls. This finding concerns a separate, whole-bundle read and hash at recording boundaries.

## 3. Confirmed CPU waste: statistics continue sampling after checkpoint restoration

**Priority:** the smallest, most directly actionable improvement.  
**Evidence:** production-source trace plus paired operation-count and state-comparison probes.

### The programming issue

An accepted checkpoint restore sets `_branch = true`, intentionally disabling statistics credit until Restart. However, the observer remains connected and evaluates:

```gdscript
_consumer.call(sample())
```

The full `sample()` executes before the consumer reaches:

```gdscript
if _suspended or _branch or detector == null:
    return
```

The sample includes air-data queries, terrain and wheel observations, contact processing, quaternion/attitude calculations, array slices, and dictionaries. The terminal-contact callback can construct another sample that is discarded for the same reason.

The relevant locations are [`fixed_wing_adapter.gd:38–125`](https://github.com/bultodepapas/OpenRCsimulator/blob/ece94f9ede8c90c92652ebce68196f81eded6c70/app/statistics/fixed_wing_adapter.gd#L38-L125), [`service.gd:140–143`](https://github.com/bultodepapas/OpenRCsimulator/blob/ece94f9ede8c90c92652ebce68196f81eded6c70/app/statistics/service.gd#L140-L143), and [`service.gd:307–345`](https://github.com/bultodepapas/OpenRCsimulator/blob/ece94f9ede8c90c92652ebce68196f81eded6c70/app/statistics/service.gd#L307-L345).

If one discarded sample costs \(c\) microseconds, the wasted work is:

\[
W = 240c\ \text{microseconds per simulated second}.
\]

At a steady 60 rendered frames per second, that corresponds to approximately four such samples per frame. This is an operation-count relationship, not a measured FPS gain.

### What the paired probe established

Two real reference Stik sessions restored the same checkpoint and advanced through the same 30 accepted ticks. A test-only adapter checked service eligibility before invoking the production callback.

| Check | Result |
|---|---|
| Complete samples, baseline/candidate | **30 / 0** |
| Compared serialized physical/contact state after every tick | Equal |
| Each run’s statistics ledger and detector | Unchanged |
| Signal subscription positions | Preserved |
| Accepted restart | Sampling resumed |
| Refused restore | Subscription retained |
| Suspended restart | Remained detached until activity resumed |
| Separate synthetic terminal-contact notification | Discarded sample avoided |

The physical trace contained **zero located events**. The isolated setup used a disclosed no-scenery stub because the sparse checkout omitted scenery assets. This establishes the waste and a promising gating mechanism; it does not establish full-scene crash or reentrancy parity.

### Preferred implementation

Add a **service-owned eligibility callable** to the adapter and check it **before `sample()` in both `_stepped` and `_contacts`**. Keep the existing `_observe` guard for direct calls and reentrancy.

This preserves normal subscription order. Simply disconnecting on restore and reconnecting on restart can move the observer relative to recording, crash, audio, or other listeners. The first probe demonstrated that detachment avoids the work; independent review identified the ordering risk, so the second probe used the earlier eligibility check instead.

Before shipping, cover actual contact/crash events, restart/reload, repeated transitions, listener reentry, and failed-save paths. Confirm that flight logs, damage handling, inputs, and solver state remain unchanged. This optimization should affect only the construction of observations that already have no consumer.

## 4. Smaller CPU candidate: wheel compression is calculated twice in one statistics sample

**Priority:** lower; implement only after a targeted cost measurement and parity test.

The observer first calls `_compressions(s)`. Later, when attitude, angular-rate, and deployment conditions pass, it asks `session.gear_collapsed(s)`. Near the ground, `Ground.collapsed()` calls the compression calculation again.

Each compression pass transforms every wheel contact and samples its terrain. The chain is in:

- [`fixed_wing_adapter.gd:70–106`](https://github.com/bultodepapas/OpenRCsimulator/blob/ece94f9ede8c90c92652ebce68196f81eded6c70/app/statistics/fixed_wing_adapter.gd#L70-L106)
- [`flight_session.gd:3062–3074`](https://github.com/bultodepapas/OpenRCsimulator/blob/ece94f9ede8c90c92652ebce68196f81eded6c70/app/sim/flight_session.gd#L3062-L3074)
- [`ground_contact.gd:444–454`](https://github.com/bultodepapas/OpenRCsimulator/blob/ece94f9ede8c90c92652ebce68196f81eded6c70/app/physics/ground_contact.gd#L444-L454)
- [`ground_wheels.gd:216–233`](https://github.com/bultodepapas/OpenRCsimulator/blob/ece94f9ede8c90c92652ebce68196f81eded6c70/app/physics/ground_wheels.gd#L216-L233)

A staged Stik/Club-field probe reached a valid, supported, controlled three-wheel pose at 0.24 m, below the approximately 0.350599 m gear-reach bound. The two public calls occurred; source inspection establishes that this path performs **six wheel-terrain samples where three results could potentially be shared**.

The improvement should be a ground-owner result reused **within that observation**, containing both compression values and collapse status.

Preserve the invalid-lake behavior, strict `>` travel comparison, clear-air sentinel, short-circuit order, current gear/terrain/track identity, and overridden session methods. Cross-tick caching would introduce substantially more correctness risk.

There is no candidate parity test or timing for this item yet. Its practical importance depends on the fraction of flight time spent in this path.

## 5. Smaller GPU candidate: skip extinction and scintillation for below-horizon stars

**Priority:** low-risk experiment after native shader validation; benefit unmeasured.

The star field contains **5,080 catalogue entries in one MultiMesh**, rather than thousands of individual draw submissions. MultiMesh is already the appropriate batching mechanism, though Godot treats its visibility as a batch rather than independently culling every instance. [Godot Engine (latest) documentation in English](https://docs.godotengine.org/en/latest/classes/class_multimesh.html?utm_source=chatgpt.com)

In [`stars.gdshader:70–95`](https://github.com/bultodepapas/OpenRCsimulator/blob/ece94f9ede8c90c92652ebce68196f81eded6c70/app/render/world/stars.gdshader#L70-L95), a star’s vertices compute:

- Atmospheric extinction with `exp` and `pow`.
- A phase hash.
- Scintillation using `sin`.
- A final multiplication by `step(0.0, dir.y)`.

For the bounded finite input domain, that final factor is zero below the horizon. The extinction and scintillation work has already happened.

**Cloud-density evaluation is already skipped below the horizon. It is not part of the proposed saving.**

A candidate structure is:

```glsl
// Preserve existing center, VERTEX and NORMAL calculations first.
if (dir.y < 0.0) {
    star_light = vec3(0.0);
} else {
    // Original flux, extinction, scintillation, cloud calculation,
    // and final star_light assignment, in their existing order.
}
```

Keep `dir.y == 0.0` on the original path. Preserve geometry, blending, depth behavior, fragment alpha, and the simulation clock.

An important engine-specific detail emerged during review: **avoid a top-level early return from `vertex()`**. The pinned Mobile shader template inserts the user vertex block before its own projection and `gl_Position` assignment. Branching and reconverging allows that engine work to finish. See the [insertion point](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/servers/rendering/renderer_rd/shaders/forward_mobile/scene_forward_mobile.glsl#L470-L475) and [position output](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/servers/rendering/renderer_rd/shaders/forward_mobile/scene_forward_mobile.glsl#L640-L643).

An idealized catalogue calculation puts roughly half the star centers below the horizon in the sampled orientations. That is a geometric count; branch divergence, compiler scheduling, camera displacement, and actual draw execution determine GPU benefit.

Validate shader compilation and images on **Mobile/Metal and Compatibility**, including near-horizon stars, classic/layered clouds, twilight, motion, pause, and rewind. Measure both the star draw and the complete frame.

I also examined hiding the whole flowing-time star field during daylight. That would be a visual-policy change: the shader does not make daytime star output identically zero. It needs exposure and twilight validation before consideration.

## 6. Secondary correctness issue: a frozen Moon-phase edit can leave the stars at the old orientation

This is a **visual consistency bug**, with lower priority than flight responsiveness.

A Moon-phase selection can change the accepted calendar date while preserving local clock time. `World.set_moon_config()` updates the atmosphere, Moon, Sun, and environment, but the existing frozen-time star field retains positions built from the previous sidereal angle. The normal star-rotation path requires an active time flow.

The relevant code is [`MoonConfig.apply_phase`](https://github.com/bultodepapas/OpenRCsimulator/blob/ece94f9ede8c90c92652ebce68196f81eded6c70/app/environment/moon_config.gd#L96-L116), [`Stars.build`](https://github.com/bultodepapas/OpenRCsimulator/blob/ece94f9ede8c90c92652ebce68196f81eded6c70/app/render/world/stars.gd#L116-L163), and [`World.set_moon_config`](https://github.com/bultodepapas/OpenRCsimulator/blob/ece94f9ede8c90c92652ebce68196f81eded6c70/app/render/world/world.gd#L1097-L1145).

The production date/ephemeris helpers produced this numerical witness:

- Initial date: 21 June 2026, 22:30, UTC+2.
- Selected Full Moon date: 29 June 2026, same clock time.
- Local sidereal angle: **213.848466° → 221.733645°**.
- Difference: **7.885179°**.

Both states were below the existing star-build solar-elevation threshold. The production scene/UI transition was source-traced rather than executed.

Store the star field’s build-time equatorial basis, then set its transform from the new accepted basis relative to that fixed reference. Compare the result with a fresh world build for each date. Avoid accumulating successive rotation deltas, which can introduce drift.

## 7. Reproducible Apple Silicon baseline

The portable probes above establish specific code behavior. A native baseline is still required before selecting larger rendering, threading, or build changes.

### Record the environment

Use the existing [`macos_preflight.py`](https://github.com/bultodepapas/OpenRCsimulator/blob/ece94f9ede8c90c92652ebce68196f81eded6c70/tools/godot/macos_preflight.py) and retain:

| Category | Required record |
|---|---|
| Hardware | Mac model, chip, RAM, display, external displays |
| Software | macOS build, Godot version/hash, source commit, template/package identity |
| Execution | Actual game-process architecture and loaded native libraries |
| Rendering | Actual renderer/driver, quality settings, MSAA, reconstruction |
| Dimensions | Requested window size, actual drawable pixels, internal 3D dimensions |
| Presentation | Refresh rate, VSync, FPS cap, window mode |
| Power | AC/battery, Low Power Mode, initial thermal state |
| Workload | Aircraft, field, weather/seed, camera, companions, recording, cache state |

Prioritize **1920×1080**, then larger display outputs, with 720p as a fallback tier. If available, include an 8 GB M1 Air, a higher-memory fanless MacBook, and a ProMotion MacBook. Keep those results separate.

### Start with the existing solo fixture

The existing `research/performance/sustained_flight.gd` provides a controlled Stik/Club/calm workload through the normal simulation path, with automatic 240 Hz stepping. Its technical default selects native reconstruction and 4× MSAA. This is a useful baseline with a narrower scope than the product’s complete interactive configuration.

A screening launch from a complete, imported, frozen checkout can use:

```bash
godot_exe="$(app/get-godot.sh)"
python3 tools/godot/macos_preflight.py --godot "$godot_exe"

mkdir -p "$PWD/tmp"
run_dir="$(mktemp -d "$PWD/tmp/apple-mobile-screen.XXXXXX")"

/usr/bin/caffeinate -dis python3 tools/godot/run_checked.py \
  --resources --resource-interval 1 --resource-max-samples 2500 \
  --out-dir "$run_dir/checks" --timeout 300 -- \
  "$godot_exe" --path app \
  --resolution 1920x1080 --windowed --always-on-top \
  --rendering-method mobile --rendering-driver metal \
  --disable-vsync --max-fps 0 \
  --script "$PWD/research/performance/sustained_flight.gd" -- \
  --frametimes="$run_dir/run-1.json" \
  --sustained-receipt="$run_dir/health-run-1.json" \
  --warmup=30 --t=120 \
  --view=pilot --autozoom=0 --scene_detail=medium \
  --sustained-hash
```

Use the repository’s documented Python environment for resource collection. Preserve the checked status, log, frame stream, and health receipt. The requested resolution must be checked against the observed drawable dimensions.

Once a candidate passes the short screen, use **30 seconds warm-up plus 1,800 seconds sampling**, an appropriate runner timeout, and **three independent runs per baseline/candidate role**. Apply the existing long-duration reducer minima and retain same-stem logs and checked receipts as described in the [performance guide](https://github.com/bultodepapas/OpenRCsimulator/blob/ece94f9ede8c90c92652ebce68196f81eded6c70/research/performance/README.md).

The launch above measures uncapped throughput. Run a separate paced test at **60 Hz**, and at supported higher refresh rates, with VSync and the intended user cap verified.

### Measure the right quantities

| Question | Measurements |
|---|---|
| CPU bottleneck | Script inclusive/self time, physics callback time, main-thread waits |
| GPU bottleneck | GPU duration, individual passes/draws, bandwidth/limiter counters where available |
| Smoothness | p50/p95/p99, maximum interval, missed deadlines, consecutive slow-frame bursts |
| Simulation fidelity | Accepted ticks, simulation/wall ratio, faults, event order, reference-state comparison |
| Memory pressure | Process footprint/RSS, allocation history, Metal resources, compression/swap activity |
| Loading | Cold and repeated entry, shader/pipeline preparation, scene-transition latency |
| Responsiveness | Input-to-present behavior and F10 boundary interruptions |
| Sustained efficiency | First versus final run segments, thermal state, CPU/GPU activity, supported energy observations |

Use Godot’s profiler to locate script costs, keeping inclusive and self time distinct. It adds overhead, so these diagnostic sessions should be separate from the clean performance comparisons. [Godot Engine (latest) documentation in English](https://docs.godotengine.org/en/latest/tutorials/scripting/debug/the_profiler.html?utm_source=chatgpt.com)

For native diagnosis, use Instruments **Game Performance** and **Time Profiler**, plus targeted Metal captures. Apple’s Game Performance template combines thread state, system calls, virtual memory, thermal state, Metal resource activity, GPU execution, and display timing—particularly useful for distinguishing a main-thread hash stall from a GPU-bound frame. [Apple Developer Documentation](https://developer.apple.com/documentation/xcode/analyzing-the-performance-of-your-metal-app/?utm_source=chatgpt.com)

A useful conceptual model is:

\[
T_{\text{frame}}
\approx
\max(T_{\text{CPU critical path}}, T_{\text{GPU}})
+
T_{\text{unhidden waits}}.
\]

CPU and GPU work overlap. Adding broad CPU and GPU counters can therefore misrepresent the frame.

### Preserve the 240 Hz timing contract

At 240 Hz:

\[
\Delta t = 4.1667\text{ ms},\qquad
12\Delta t = 50\text{ ms}.
\]

At steady 60 Hz, approximately four physics ticks occur per frame; at 120 Hz, approximately two. Other refresh rates naturally vary the count while the fixed simulation step remains unchanged.

The configured catch-up bound limits steady real-time progress below roughly 20 rendered frames per second. Godot documents that exceeding the permitted physics steps per frame can slow simulated time. Raising that bound can also increase recovery work, so it should not be used to conceal a blocking operation. [Godot Engine (latest) documentation in English](https://docs.godotengine.org/en/latest/classes/class_engine.html?utm_source=chatgpt.com)

### Include the scenarios the solo circuit cannot cover

Use separate workload identities for:

- F10 start/stop in the **release package**.
- Checkpoint restore followed by resumed flight.
- Near-ground rollout and landing.
- Twilight/night with the star field.
- Dense scenery, clouds, lake, and different camera views.
- Repeated Home → Fly → Home and Workshop transitions.
- Visible pause, unfocused window, and minimized window.
- Companion-enabled flight after its qualification is restored.

These scenarios should preserve their own expected physics and presentation behavior; they should not be silently folded into the solo circuit’s result.

## 8. Memory, high-resolution rendering, power, and existing qualification work

### Unified memory

I did not establish a new resource leak in the inspected paths. Existing cloud-cache, readback, resource-compression, and lifecycle concerns are already represented in earlier audits.

The next native pass should combine the existing texture import/runtime inventories with Instruments allocation history across repeated scene transitions. Run inventories as diagnostics, since resource inspection can itself cause work.

Apple Silicon shares physical memory between CPU and GPU, but storage modes and synchronization still matter. Unified memory does not eliminate resource duplication, temporary buffers, or synchronization costs. Avoid summing process RSS and GPU allocation counters as though they were disjoint totals. [Apple Developer Documentation](https://developer.apple.com/documentation/metal/choosing-a-resource-storage-mode-for-apple-gpus?changes=_1\&utm_source=chatgpt.com)

Also, `import_etc2_astc=true` enables an import target; it does not prove that every runtime-created texture uses a compressed GPU format.

### Resolution and visual quality

Pixel counts explain why drawable dimensions must be recorded:

\[
\frac{2560\cdot1600}{1920\cdot1080}\approx1.98.
\]

That output has almost twice the pixels of 1080p. A linear internal scale of 0.85 produces \(0.85^2=72.25\%\) of the original 3D pixel count, before reconstruction and presentation costs.

These calculations help design comparisons; they do not predict FPS. Validate aircraft silhouettes, control-surface visibility, runway markings, foliage, and motion before accepting a reconstruction or antialiasing change. Your existing MetalFX and renderer work should remain the starting point rather than being reported as a new discovery.

### Paused and background power

Source inspection shows that presentation work can continue after the simulation is paused. Its actual power cost remains a hypothesis because compositor behavior, VSync, App Nap, and window visibility can change execution.

Measure focused flight, visible pause, unfocused, and minimized states separately. If unnecessary work is material, trial a presentation policy that reduces background rendering while preserving controller/menu responsiveness and restoring the accepted display settings before flight resumes.

### CI and benchmark qualification

At the closing check, CI for `347905c` was still running, and its **units 2** job had failed because the companion profiles referenced solver identity `880d1911` while the current identity was `84cac259`. The [job log](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/42312091090/job/128216781941) records the refusal.

The sustained fixture explicitly forces **zero companions**, so this particular mismatch does not block that solo workload. Companion-enabled results require the documented retained-tape comparison and supported rebind or renewed qualification. The build should not be described as CI-clean.

I also reproduced an **existing A1 qualification limitation**: diagnostic collection can remain eligible for a reducer performance pass. A separate synthetic stream showed that percentile and aggregate-time gates can pass one constructed 400 ms interval. Neither is a new observed game hitch. Clean launch verification, maximum intervals, and burst analysis remain necessary alongside the reducer’s boolean result.

## Recommended implementation order

1. **Add the statistics eligibility gate before sample construction.** It has the clearest bounded change and an existing operation-count witness.
2. **Measure the F10 bundle scans on the actual ARM64 release.** If they produce material interruptions, implement asynchronous admission/finalization with recording semantics preserved.
3. **Test the star-shader branch on Metal.** Retain it only if image checks pass and complete-frame results support it.
4. **Consider same-observation wheel-result reuse** after parity testing the terrain, sentinel, and override boundaries.
5. **Correct the frozen Moon/star basis update** as a separate visual consistency change.

The strongest opportunities found in this pass remove work outside the numerical flight model. They preserve the 240 Hz solver, float64 state, aircraft behavior, and input semantics while targeting avoidable CPU work and interruptions that can make a fast simulator feel uneven.