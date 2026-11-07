I continued with **five concrete optimization techniques**, and built three reproducible probes to test the most important assumptions.

The strongest new investigation is **avoiding a GPU-to-CPU round trip when preparing the Ugly Stik’s illuminated covering**. The smallest targeted cleanup is **removing audio calculations whose results are immediately discarded**. The cloud and lens-flare work are more conditional: their implementation details look promising, but they need a native Metal capture before adoption.

I checked the updated [consolidated audit ledger](https://github.com/bultodepapas/OpenRCsimulator/blob/181d7ca638285f24c1ec9e5089ed07b35b7ea418/external%20Audits/CONSOLIDATED-AUDITS.md) and reviewed source at **`181d7ca`**, the v0.2.0 preparation commit. The earlier recording, statistics, wheel-query and star findings are now tracked there. This continuation focuses on different code paths and clearly identifies refinements of existing investigations.

**Reproducible evidence:** [openrc-apple-silicon-followup-probes.zip](https://chatgpt.com/library?file_id=libfile_fde3_f-f9295e6b4e9c8191b99088f3e522c7a0_ac5d15b10f548191b3cb750779cf7c10&account_id=personal)

The archive contains the probe code, relevant source snapshots, complete results, checked Godot logs, mathematical derivations and reproduction instructions.

## Configuration and evidence boundaries

These techniques target the project’s existing **Godot 4.8-beta2**, engine commit **`cafc17a19`**, and its **universal macOS export**. The ARM64 project override selects **Mobile**, with the project’s intended native **Metal** path. A real performance run still needs to record the effective renderer, because configuration alone does not prove which fallback or driver actually ran. The simulation remains configured for **240 physics ticks per second**, up to **12 catch-up steps per rendered frame**, with its own interpolation. See [project configuration](https://github.com/bultodepapas/OpenRCsimulator/blob/181d7ca638285f24c1ec9e5089ed07b35b7ea418/app/project.godot#L42-L75) and [macOS export configuration](https://github.com/bultodepapas/OpenRCsimulator/blob/181d7ca638285f24c1ec9e5089ed07b35b7ea418/app/export_presets.cfg#L50-L70).

**No native Mac benchmark was run.** The executable probes used the pinned Linux Godot build or a float32 CPU model. Production repository files remain unchanged.

| Technique | What this investigation established | Next decision |
|---|---|---|
| Preserve compact CPU samples for Stik lighting | **28 checks passed**, including complete pixel and mipmap equality across **20 combinations** | Compare against actual Metal texture readback and measure creation stalls |
| Evaluate audio humidity fallbacks conditionally | **10 cases passed** for selected-value equality and fallback call counts | Validate production conversions, filters and audio behavior |
| Defer legacy audio loops after bank selection | Source confirms construction followed by discarding in successful-bank paths | Measure startup allocations and preserve audio admission/lifecycle |
| Restrict lens-ghost work to its mathematical support | **Nine pixel-grid cases**, with no missed nonzero contributions | Test generated Metal and complete GPU frame times |
| Read the cloud tile asynchronously | Pinned engine source confirms a synchronous stall path and an available asynchronous API | Establish whether the current readback causes a material hitch |

The results establish specific mechanisms and correctness properties. They do not establish an FPS, battery-life or sustained-performance improvement.

## 1. Preserve a small CPU representation before uploading the Stik atlas

**Affected code:** [`ugly_stik_finish.gd:56–71`](https://github.com/bultodepapas/OpenRCsimulator/blob/181d7ca638285f24c1ec9e5089ed07b35b7ea418/app/aircraft/ugly_stik_finish.gd#L56-L71) and [`lighting_skins.gd:361–413`](https://github.com/bultodepapas/OpenRCsimulator/blob/181d7ca638285f24c1ec9e5089ed07b35b7ea418/app/render/lighting/lighting_skins.gd#L361-L413).

### The avoidable round trip

The stock Stik finish currently:

1. Rasterizes its generated SVG into a CPU `Image`.
2. Generates mipmaps.
3. Creates an `ImageTexture`.
4. Retains the texture for reuse.

When an eligible illuminated covering is configured later, the lighting helper calls `albedo_texture.get_image()`, converts the result to RGBA8, samples it into a **512 × 512** composition, applies the structural mask and tint, generates mipmaps, and uploads the resulting texture.

That creates a useful optimization boundary: **the CPU originally possessed the exact source image that the later lighting operation needs.**

Godot documents that `Texture2D.get_image()` obtains texture data from the GPU and creates an image copy. This can be costly when used excessively, including during resource preparation. [Godot Engine (latest) documentation in English](https://docs.godotengine.org/en/latest/classes/class_texture2d.html?utm_source=chatgpt.com)

The pinned engine adds a relevant distinction. Its RenderingDevice texture storage has a CPU image-cache shortcut under `TOOLS_ENABLED`; the retrieval path populates that cache under an actual editor-hint context. A non-tools export template has no such shortcut. Consequently, a warmed editor-side test can conceal work that an exported build performs. Merely launching a game with the editor executable does not establish that the shortcut is active. See the pinned [texture retrieval implementation](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/servers/rendering/renderer_rd/storage_rd/texture_storage.cpp#L1912-L1964).

### The proposed technique

While the original CPU atlas exists, retain **only the source samples that the lighting composition will consume**.

For an input image of width \(W\) and height \(H\), the existing composition chooses:

\[
x_s=\min\left(W-1,\left\lfloor \frac{xW}{512}\right\rfloor\right),
\qquad
y_s=\min\left(H-1,\left\lfloor \frac{yH}{512}\right\rfloor\right).
\]

Store those RGBA bytes in a compact array:

\[
S[x,y,c]=I[x_s,y_s,c].
\]

The retained data size is:

\[
512\cdot512\cdot4
=1{,}048{,}576\text{ bytes}
=1\text{ MiB}.
\]

The later composition can consume that array directly. Its numerical operation order should remain unchanged:

```gdscript
var source_r: float = float(samples[out_index]) / 255.0

output[out_index] = clampi(
    roundi(source_r * tint.r * mask_amount * 255.0),
    0,
    255
)
```

This is a sampling substitution, with the existing tint, mask, rounding, alpha and mipmap behavior preserved. In particular, it should not introduce a different resize filter or replace the existing sample coordinates with a visually similar approximation.

### What the probe demonstrated

The isolated Godot probe used the **actual generated Stik SVG** and the **production geometry-based structural-mask helper**.

It compared the original composition arithmetic with the compact-sample version for:

- The stock 2048 × 2048 atlas.
- A 1 × 1 image.
- Asymmetric 513 × 257, 511 × 777 and 2047 × 127 images.
- Four tint cases per image, including the stock covering tint and diagnostic colors.

**All 20 comparisons matched every base-image byte and every generated mipmap byte.** The complete probe passed **28 checks**. A deliberate one-pixel shift in the source sampling produced a mismatch, confirming that the comparison detects that error.

The observed CPU data lengths were:

| Data | Bytes |
|---|---:|
| Stock atlas, including its mip chain | 22,369,620 |
| Proposed sampled RGBA buffer | 1,048,576 |
| Composed lighting image, including mipmaps | 1,398,100 |
| Structural mask | 262,144 |

These are buffer lengths from the probe, not measurements of resident memory or GPU allocation.

### The tradeoff and remaining validation

**Retaining the sample buffer adds 1 MiB of live CPU data compared with the current implementation.** Its value would come from avoiding later readbacks and temporary work. Total-memory and loading-time improvements remain unmeasured.

The static atlas can outlive a lighting helper. The implementation therefore needs an explicit owner and lifetime: keep the samples associated with the exact atlas, invalidate them if that texture changes, and retain the existing fallback for custom, replaced or unsupported textures. Releasing the buffer after its first consumer would leave later configurations needing regeneration or readback again.

The next native test is decisive: compare the original CPU samples with the bytes returned by **the actual Metal texture after upload**, then compare complete composed outputs and rendered motion. The CPU probe does not establish that GPU round-trip equivalence.

For MacBooks, this is attractive because it targets a synchronization boundary during creation or reconfiguration. Shared memory still has producer/consumer dependencies; it does not automatically let CPU and GPU operations access a resource in any order. Apple’s synchronization example explains why shared resources can still stall processors. [Apple Developer Documentation](https://developer.apple.com/documentation/metal/synchronizing-cpu-and-gpu-work?utm_source=chatgpt.com)

## 2. Remove discarded humidity calculations in the audio path

**Affected code:** [`soundscape.gd:536–546`](https://github.com/bultodepapas/OpenRCsimulator/blob/181d7ca638285f24c1ec9e5089ed07b35b7ea418/app/audio/soundscape.gd#L536-L546), [`flight_audio.gd:293–311`](https://github.com/bultodepapas/OpenRCsimulator/blob/181d7ca638285f24c1ec9e5089ed07b35b7ea418/app/audio/flight_audio.gd#L293-L311), and [`soundscape_model.gd:61–64`](https://github.com/bultodepapas/OpenRCsimulator/blob/181d7ca638285f24c1ec9e5089ed07b35b7ea418/app/audio/soundscape_model.gd#L61-L64).

### The issue

The path-filter code supplies a function call as the default argument to `Dictionary.get()`:

```gdscript
snapshot.get(
    "humidity_molar_pct",
    Model.humidity_molar_pct(...)
)
```

That default expression is evaluated **before** `get()` chooses its result.

The airplane audio snapshot already supplies `humidity_molar_pct`, so the fallback calculation is performed and discarded. The helper contains two `pow()` operations. This also happens on intervening updates where the absorption target is not recomputed.

There is a second instance of discarded work in `flight_audio.gd`: it computes reference humidity, then immediately overwrites that result when the atmosphere is custom and pressure is positive.

### A concrete improvement

Use key presence to decide whether to evaluate the fallback:

```gdscript
var humidity: float

if snapshot.has("humidity_molar_pct"):
    humidity = float(snapshot["humidity_molar_pct"])
else:
    humidity = Model.humidity_molar_pct(
        Model.REFERENCE_RELATIVE_HUMIDITY_PCT,
        temperature_k,
        pressure_pa
    )
```

For the producer, select the existing custom-atmosphere branch before calculating the reference formula:

```gdscript
var humidity: float

if not session.atmosphere_is_reference() and pressure_pa > 0.0:
    humidity = (
        100.0
        * float(atmosphere.get("vapor_pressure_pa", 0.0))
        / pressure_pa
    )
else:
    humidity = SoundscapeModel.humidity_molar_pct(
        SoundscapeModel.REFERENCE_RELATIVE_HUMIDITY_PCT,
        temperature_k,
        pressure_pa
    )
```

These are narrow candidate changes for valid accepted atmosphere inputs. They preserve the selected formula and its arithmetic.

### What the probe demonstrated

The pinned-engine probe compared the eager lookup with the explicit presence check for ten cases: absent, positive, positive zero, negative zero, null, NaN, infinity, false, an invalid string and an invalid array.

The results were:

- The original expression called the fallback **once in every case**.
- The conditional expression called it **only for the absent key**.
- The selected raw `Variant` serialized identically in all ten cases.

That confirms the language behavior. It does **not** prove equivalence of production `float()` conversions, filter output or audible sound.

There is a compatibility detail to resolve: skipping arithmetic can also skip an error or nonfinite result caused by malformed temperature or pressure, even when humidity is supplied. Production validation should preserve the intended behavior for those inputs.

### Why this is a useful small change

This is a source-proven reduction in discarded calculations, with a narrow implementation scope. Its effect on complete frame time may be small.

Keep the absorption target’s existing refresh clock and priming behavior, and keep the per-update smoothing. The next checks should compare the entire target/cutoff sequence through reference and custom atmospheres, refresh boundaries, absorption toggles, pause/resume and re-entry. Then measure an audio-enabled release workload.

I would treat this as a small CPU cleanup whose value must be assessed in the complete scene.

## 3. Investigate asynchronous readback for the cloud tile

**Affected code:** [`cloud_shadow_map.gd:235–303`](https://github.com/bultodepapas/OpenRCsimulator/blob/181d7ca638285f24c1ec9e5089ed07b35b7ea418/app/render/cloud_shadow_map.gd#L235-L303).

**Audit status:** This is a proposed technique for the existing **DT-MAC-06b** investigation. The cloud tile and its readback are already documented; they are not new findings.

### What the source trace establishes

For a newly admitted seed, the code:

1. Creates a 2048 × 2048 HDR `SubViewport`.
2. Waits three process frames.
3. Calls `viewport.get_texture().get_image()`.
4. Validates seed-specific samples.
5. Converts the image to RG16F.
6. Creates a stable `ImageTexture` for consumers.

The process-frame delay does not establish that rendering has completed.

Following this through the pinned RenderingDevice implementation exposes the relevant synchronization. The ordinary non-CPU-readable texture-readback path schedules a copy and calls `_flush_and_stall_for_all_frames()` before mapping the result. See the pinned [readback implementation](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/servers/rendering/rendering_device.cpp#L2786-L2801).

That is a concrete synchronization mechanism. Its duration and visibility to a MacBook user remain unmeasured.

### The data volume matters

For the ordinary HDR attachment path:

\[
2048^2\cdot8\text{ bytes}
=32\text{ MiB}
\]

for RGBA16F source data.

The final two-channel RG16F tile is:

\[
2048^2\cdot4\text{ bytes}
=16\text{ MiB}.
\]

The retained tile’s size therefore understates the logical source readback size. These calculations exclude alignment, staging and other temporary allocations.

### The candidate design

Godot exposes `RenderingDevice.texture_get_data_async()` at the pinned engine version. A candidate could keep the analytic fallback active while the readback completes, validate the returned data, and publish the same stable texture afterward.

However, Godot explicitly warns that large asynchronous downloads can remain expensive, and larger staging buffers exchange memory for transfer capacity. The pinned implementation can also flush and stall when staging allocation is exhausted. [Godot Engine (latest) documentation in English](https://docs.godotengine.org/en/latest/classes/class_renderingdevice.html?utm_source=chatgpt.com)

The implementation would need to handle:

- The actual viewport proxy and underlying RD texture.
- Correct render-thread access and completed rendering.
- Exact dimensions, format and conversion.
- Viewport and RID lifetime until completion.
- Seed and generation checks before publication.
- Cancellation, stale callbacks and lack of progress.
- Existing validation, retry, failure and analytic-fallback behavior.

Moving `get_image()` into an arbitrary worker thread would not establish these properties.

### A prior experiment constrains the solution

The existing Mac research records a direct `ViewportTexture` path that produced black data in the Mobile/Metal sky; the validated copied `ImageTexture` resolved that tested path. That is a reason to preserve the stable published texture while investigating how its bytes arrive. See [DT-MAC-06b’s retained diagnosis](https://github.com/bultodepapas/OpenRCsimulator/blob/181d7ca638285f24c1ec9e5089ed07b35b7ea418/docs/research/desktop-delivery-investigations/DT-MAC-00-R4/README.md#dt-mac-06b-c5b-float-noise-tile-corrected-c5-diagnosis-and-default-on-2026-11-05).

The smallest useful Mac experiment is a fresh-process, uncached-seed run with timestamps around bake, readback, validation and publication, correlated with a short Metal trace. Compare warm reuse of the same seed.

Record the cache diagnostics: the process-lifetime cache has four entries, including failures. A later seed can use the analytic fallback without starting a bake. That case must not be mistaken for faster asynchronous loading.

## 4. Restrict lens-ghost work to pixels that can contribute

**Affected code:** [`sun_glare.gdshader:95–114`](https://github.com/bultodepapas/OpenRCsimulator/blob/181d7ca638285f24c1ec9e5089ed07b35b7ea418/app/render/landscape_upgrade/sun_glare.gdshader#L95-L114) and [`157–204`](https://github.com/bultodepapas/OpenRCsimulator/blob/181d7ca638285f24c1ec9e5089ed07b35b7ea418/app/render/landscape_upgrade/sun_glare.gdshader#L157-L204).

**Audit status:** This is a narrower application within the existing A1/A2/A7 shader and glare investigations. It remains an experiment.

### The mathematical opportunity

The secondary lens pass draws five ghost shapes. For ghost \(g\), the shader uses:

\[
c_g=s+(0.5-s)p_g,
\]

where \(s\) is the projected source position and \(p_g\) is the ghost’s position factor.

Its normalized radius is:

\[
r_g=
\frac{
\left\|(u-c_g)\odot(a,1)\right\|
}{
R_g
},
\]

where \(u\) is the pixel coordinate, \(a\) is aspect ratio and \(R_g\) is the ghost radius.

For valid finite inputs, the ghost’s contribution is zero when \(r_g\ge1\). A circle is contained in its bounding box, so any contributing pixel must satisfy:

\[
|(u_x-c_{g,x})a|<R_g,
\qquad
|u_y-c_{g,y}|<R_g.
\]

A conservative union of five boxes can therefore reject pixels before executing the original ghost work.

The current fragment function evaluates disc visibility before selecting the veil or ghost path. That creates an opportunity to place the support check earlier **for the secondary ghost pass**, while preserving the veil and final fragment outputs.

### What the CPU screen found

The float32 probe tested nine complete pixel-center grids, including 1080p, portrait, 1440p, ultrawide and offscreen source positions.

It found **zero missed nonzero alpha or tinted-channel contributions** in those cases.

Selected 1920 × 1080 results:

| Projected source | Original nonzero pixels | Pixels inside the padded guard |
|---|---:|---:|
| `(0.50, 0.50)` | 13,200 | 17,424 |
| `(0.00, 0.50)` | 19,700 | 26,408 |
| `(-0.05, 0.50)` | 19,694 | 26,362 |

The experimental guard used a radius margin of `radius × 1.001 + one vertical pixel`. That margin is not a proven bound for Metal floating-point behavior, rasterization or MSAA.

### Two reasons this might not help

First, the nine depth samples occur only when source scale is positive, the projection is valid and the on-screen blend weight is positive. An offscreen source can use the skyline prior without executing those reads.

Second, all fragments sample the same disc coordinates. Those reads may cache or coalesce efficiently. Adding box tests, branches and registers can offset the saved work.

Apple’s GPU-counter guidance specifically distinguishes coherent execution from divergent SIMD execution and recommends examining the actual arithmetic, texture and occupancy limiters. A small geometric support does not translate directly into a proportionate shader-time reduction. [Apple Developer](https://developer.apple.com/videos/play/wwdc2020/10603/?utm_source=chatgpt.com)

### Offscreen source culling would be incorrect

The probe found **19,694 contributing pixels with the source already outside the left edge**.

There is also a useful analytic constraint. Positive edge fade places each source-coordinate component in \((-0.1,1.1)\). The ghost with position factor \(0.8\) then has:

\[
c=0.2s+0.4\in(0.38,0.62).
\]

Its center remains inside the image. Simply hiding the ghost pass when the sun leaves the frame would remove visible content.

The candidate should preserve the original projected positions, colors, veil, blending and common outputs, and execute the original path for uncertain inputs. The depth-texture dependency remains present.

The next step is an actual Metal A/B test: inspect the generated ghost draw, compare texture/ALU activity and GPU duration, then run clean whole-frame trials. Include on-screen and offscreen sources, sun and moon, moving opaque occlusion, FOV changes and resize transitions.

## 5. Prepare only the legacy audio loops that can be used

**Affected code:** [`soundscape.gd:130–194`](https://github.com/bultodepapas/OpenRCsimulator/blob/181d7ca638285f24c1ec9e5089ed07b35b7ea418/app/audio/soundscape.gd#L130-L194) and [`253–304`](https://github.com/bultodepapas/OpenRCsimulator/blob/181d7ca638285f24c1ec9e5089ed07b35b7ea418/app/audio/soundscape.gd#L253-L304).

### The startup work

The soundscape creates legacy motor and propeller voices before attempting the installed recorded powertrain bank.

When the recorded bank succeeds, it clears those legacy streams, apart from the gasoline propeller coast layer. Thus the successful electric, rotor and turbine bank paths discard two prepared legacy loops; gasoline discards the motor loop and retains its propeller coast layer.

Preparation includes loading a WAV and constructing a guarded loop. The PCM path reads `source.data` twice; Godot documents that the returned array is a copy. [Godot Engine (latest) documentation in English](https://docs.godotengine.org/en/latest/classes/class_audiostreamwav.html?utm_source=chatgpt.com)

This is startup and transient-allocation work. Its effect on loading time, footprint and sustained flight remains unmeasured.

### A constrained implementation

Keep the indexed player nodes and defer their stream preparation:

1. Create the existing voice slots in their current order.
2. Attempt recorded-bank configuration at its existing boundary.
3. On failure, populate the required legacy streams.
4. On success, populate only the legacy streams still needed, including gasoline coast.

The actual bank result must drive the decision. `PowertrainAudio.configure()` can succeed with a single loaded layer; checking that a manifest exists would not reproduce its admission rule. See [bank configuration](https://github.com/bultodepapas/OpenRCsimulator/blob/181d7ca638285f24c1ec9e5089ed07b35b7ea418/app/audio/powertrain_audio.gd#L47-L77).

Preserve all fourteen voice slots, initial positions and phase offsets, seeded ambience, procedural glow behavior, partial-bank behavior and teardown. The existing 64-frame loop guard also remains necessary to the project’s wrap-continuity behavior.

Skipping a previously attempted load can suppress a missing-source diagnostic, so that observable difference needs an explicit decision.

The targeted validation matrix is full bank, partial bank, malformed bank and no usable layers, followed by gasoline cut/coast/restart and repeated Home/Workshop/flight transitions. Compare startup allocations and first-audio latency only after those behaviors match.

## How I would qualify these on Apple Silicon MacBooks

The next baseline should use an unchanged release-equivalent build at **actual 1920 × 1080 output**, followed by higher resolutions and supported refresh rates.

Record the MacBook model, chip and core counts, memory, macOS, engine and template identity, effective renderer, drawable and internal resolution, MSAA/reconstruction, VSync and frame limit, scene, aircraft, seed, audio/lighting configuration, power source, Low Power Mode and thermal conditions.

Use separate diagnostic and clean measurement runs:

| Experiment | What should be measured |
|---|---|
| Stik CPU-sample handoff | Actual readback parity, configuration duration, synchronization, retained/peak footprint, repeated lifecycle behavior |
| Audio conditional evaluation | Target/cutoff sequence, audio continuity, complete CPU workload |
| Audio loop deferral | Allocations, loading time, first-audio timing, fallback and coast behavior |
| Ghost support guard | Generated Metal, fragment/texture work, GPU duration, complete frame-time distribution, image equivalence |
| Cloud asynchronous readback | Complete bake-to-publication latency, frame spikes, staging/peak memory, fallback and cancellation behavior |

Apple’s Metal tools provide resource views and usage information that can help distinguish useful retained resources from assets that are no longer used. That is especially relevant to the proposed retained sample buffer and any future cache expansion. [Apple Developer](https://developer.apple.com/videos/play/wwdc2022/10106/?time=614\&utm_source=chatgpt.com)

For steady scenes, a practical starting protocol is 30 seconds of warmup followed by at least 60 measured seconds, with alternating baseline/candidate order and repeated pairs. Cold-load trials need fresh processes and recorded cache state. Follow promising candidates with a separate sustained run of roughly 20 minutes; the duration alone does not establish thermal equilibrium.

Report CPU and GPU times, presented-frame intervals, maximum interval, missed-budget counts and consecutive misses. At 60 Hz the frame budget is **16.67 ms**; at 120 Hz it is **8.33 ms**. Keep AC and battery runs separate, and compare efficiency at the same cadence and advancing simulation time.

**My implementation order would be:** the narrow audio conditional cleanup, native qualification of the Stik sample handoff, audio-loop deferral, attribution of the cloud-readback hitch, and finally the lens-ghost GPU experiment. That order combines inexpensive source improvements with progressively stronger hardware evidence, while keeping the flight model and responsive controls intact.