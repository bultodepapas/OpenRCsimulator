I implemented **two focused CPU optimizations** and prepared a revision-pinned report, an apply-ready patch, and the supporting evidence.

The strongest implemented result is **36–68% lower controller-binding resolution cost across the tested two-to-five-action gamepad configurations**. The audio optimization also improved its measured component, although its absolute contribution is much smaller.

The most important remaining CPU opportunity is spatial wind: the actual reference flight-session benchmark reached a **4.556 ms median batch cost per physics tick** in the 24-mode case on this host, against a **4.167 ms period at 240 Hz**. That gives us a concrete workload to prioritize.

**These are component and headless session results. I did not obtain GPU, displayed-frame, whole-game FPS, or physical input-latency measurements.**

## Deliverables

- [OpenRC-performance-review.html](https://chatgpt.com/library?file_id=libfile_fde3_f-1efac59579d881918613b08060b846a1_ac5d15b10f548191b3cb750779cf7c10&account_id=personal) — the complete report, with equations, source locations, audit reconciliation, limitations, and the validation campaign.
- [OpenRC-performance.patch](https://chatgpt.com/library?file_id=libfile_fde3_f-30e1e7b9f77081918adaf9d69816f281_ac5d15b10f548191b3cb750779cf7c10&account_id=personal) — the two implementations and their regression tests.
- [OpenRC-performance-evidence.zip](https://chatgpt.com/library?file_id=libfile_fde3_f-9040f2f0482881918292ed5da36c1893_ac5d15b10f548191b3cb750779cf7c10&account_id=personal) — raw timings, comparison harnesses, checked test receipts, prototypes, source identities, negative results, and reproduction instructions.

The changes are on the local branch **`perf/math-audit-20261109`**. They have not been pushed or merged. The patch passes an applicability check against both reviewed commits.

## 1. Repository state and what was already done

The main investigation and all local benchmarks use:

**`8fb825a96dbc39fbbf99c1056ba643c9cde49b5d`**

During the review, `main` advanced to:

**`f7b58bd830d4a5eb78901d00514ce1fc18286477`**

I reviewed that successor’s complete 27-file change list and confirmed it remained the latest `main` at the closing check. Despite its evidence-oriented title, it also changes **Timber LOD preservation and custom-paint compatibility**. The controller, oscillator, physics, companion predictor, afterimage, and Stik shadow paths discussed below are unchanged by that successor. The experiments remain explicitly bound to the earlier revision. [Reviewed baseline](https://github.com/bultodepapas/OpenRCsimulator/commit/8fb825a96dbc39fbbf99c1056ba643c9cde49b5d) · [Successor commit](https://github.com/bultodepapas/OpenRCsimulator/commit/f7b58bd830d4a5eb78901d00514ce1fc18286477)

I read **`external Audits/CONSOLIDATED-AUDITS.md` before reviewing the code**, followed its completed-work references, and cross-checked findings against production source. Several tempting recommendations are already implemented: thermal-query reuse, observer datum-wind reuse, pre-step air reuse, bounded telemetry storage, circuit-mesh caching, parked ORM read reuse, conditional humidity fallback, deferred legacy PCM preparation, and the existing native evaluator. They are not new findings in this report. [Consolidated audit](https://github.com/bultodepapas/OpenRCsimulator/blob/8fb825a96dbc39fbbf99c1056ba643c9cde49b5d/external%20Audits/CONSOLIDATED-AUDITS.md)

Two repository-state details matter:

- **Open draft PR #11 is unmerged, but its cache and ORM changes are already ported into `main`.** Treating everything in an open PR as absent would double-count completed work.
- **Current CI is failing before application qualification.** Both reviewed commits fail the generator-orchestration test because its expected command roster is stale. The successor’s log records 125 tests with one failure; downstream application, native, visual, and export jobs are skipped. This is an existing validation gap, not a failure introduced by this patch. [PR #11](https://github.com/bultodepapas/OpenRCsimulator/pull/11) · [Current CI run](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/42648597425)

The repository-wide inventory covers **47,923 tracked paths**, including historical evidence and generated content. The deeper review followed production execution paths through input/UI, fixed-wing and helicopter simulation, native code, wind, companions, audio, shaders, meshes, settings, loading, caching, and recording. I am not claiming every asset or historical file was manually inspected.

## 2. Prioritized results

| Priority | Optimization | Status | Evidence |
|---|---|---|---|
| **P1** | Build one occupied-button index per controller resolution | **Implemented locally** | Exact output comparisons and measured component improvement |
| **P1** | Reuse spatial-wind temporal phase within each stage | **Prototype and integration proposal** | Expensive real reference workload; 38,853 native component checks; candidate untimed |
| **P1** | Avoid negligible offscreen afterimage passes | **Refinement of existing A26 work** | Checked visibility witness; requires GPU and visual-error qualification |
| **P1** | Move eligible F10 bundle hashing off the interactive boundary | **Known A24 work still pending** | Current synchronous path; target recording-boundary measurements needed |
| **P2** | Inline valid-domain engine-voice interpolation | **Implemented locally** | Exact PCM/state checks; measured but small absolute CPU saving |
| **P2** | Reduce companion forecast square roots and repeated turn-rate calculations | **New mathematical proposals** | Source-derived operation counts; replay/rebind qualification required |
| **P2** | Remove overwritten legacy air calculations in native spatial stages | **New source candidate** | Compiler elimination, floating-point environment, parity, and timing still need verification |
| **P2** | Index aircraft shadow masks | **Preparation experiment; synchronous version rejected** | Lower logical geometry storage, but approximately 100 ms extra construction work |

## 3. Implemented: controller resolution does substantially less repeated work

### Where the cost occurs

In [`controller_actions.gd`](https://github.com/bultodepapas/OpenRCsimulator/blob/8fb825a96dbc39fbbf99c1056ba643c9cde49b5d/app/input/controller_actions.gd#L154-L216), `effective_bindings()` calls `_add_automatic_buttons()` after applying saved overrides and AUX reservations.

The original helper scans the current binding map **once for every eligible automatic button**. The built-in map contains 37 actions.

This sits on a repeated input path. In Home-launched flight, [`app_root.gd::_input`](https://github.com/bultodepapas/OpenRCsimulator/blob/8fb825a96dbc39fbbf99c1056ba643c9cde49b5d/app/app_root.gd#L2116-L2187) resolves bindings for restart, rates, generic action identities, flight/UI observers, dispatch, and throttle cut. A stable selected gamepad can pass through **seven resolutions during one event**.

Those resolutions do not necessarily have identical capabilities: flight capabilities depend on the aircraft, while the UI path uses the default airplane set. That is why I added the capability-specific benchmark instead of assuming every aircraft receives the largest improvement.

### Algorithmic change

The original structure is:

```text
For each eligible automatic candidate:
    inspect AUX reservations
    scan every existing binding
    validate it, check its context, compare its button
    insert the candidate if free
```

The implemented structure is:

```text
On the first eligible candidate:
    scan existing bindings once
    record valid occupied flight/both-context button IDs

For each eligible candidate, in the original order:
    inspect the unchanged AUX reservations
    test membership in occupied buttons
    if free, insert the candidate and occupy its button
```

For \(A\) bindings, \(C\) candidates, and \(U\) AUX entries:

\[
O(CA+CU)\quad\longrightarrow\quad O(A+C+CU).
\]

With five candidates, the repeated binding inspections fall from **185 to 37**. With two candidates, they fall from **74 to 37**. The earlier outer binding/AUX work remains.

The additional memory is one short-lived dictionary. There is no persistent cache, stale profile state, or cross-event invalidation protocol.

### Correctness conditions

The implementation preserves:

- Explicit overrides and intentional **Clear** bindings.
- Menu versus flight context rules.
- AUX channel ownership and every button in an AUX switch.
- Rejection of malformed or unknown reservations.
- Declaration order when airplane and helicopter defaults share buttons.
- Detached ownership of returned binding dictionaries.

The helper relies on its existing caller contract: automatic candidates begin unbound unless explicitly overridden. That invariant is now documented in the code. An arbitrary future caller that replaces existing bindings would need occupancy removal or counts.

### Measured results

These measurements time the **complete resolver**, using the pinned Godot executable, 500 warmup calls per variant, nine alternating pairs, and 4,000 calls per batch. The capability follow-up was a separate run.

| Gamepad configuration | Before, µs/call | After, µs/call | Reduction |
|---|---:|---:|---:|
| Rates and restart: two candidates | 202.897 | 129.232 | **36.3%** |
| Smoke, rates, restart: three | 253.006 | 128.678 | **49.1%** |
| Gear, flaps, rates, restart: four | 334.325 | 129.778 | **61.2%** |
| Full airplane capabilities: five | 356.339 | 114.228 | **67.9%** |
| Helicopter capabilities: five | 341.561 | 116.242 | **66.0%** |
| All bindings explicitly overridden | 88.045 | 91.772 | **−4.2%** |
| Radio control path | 75.616 | 77.216 | **−2.1%** |

The explicit-binding and radio controls show **no useful gain**; their ranges overlap, and the small negative medians are retained. The no-equipment case, where restart remains eligible, improved only 2.4%. The AUX-conflict fixture improved 54.2%.

Verification includes **31,244 exact output/input-ownership comparisons**, the new **38-check regression**, and the existing controller action, extended-action, binding-audit, profile, and conditioning tests. The measured implementation and delivered patch have matching source hashes.

This establishes a real reduction in resolver work. It does **not** establish a particular FPS increase or physical input-latency reduction.

A further opportunity is sharing effective bindings within one event, but that needs an explicit snapshot/generation contract because callbacks, restart, device changes, and rebindings can invalidate assumptions. Also, `Input.use_accumulated_input = false` is **already implemented**; I did not present it as a new fix. [Existing input setting](https://github.com/bultodepapas/OpenRCsimulator/blob/8fb825a96dbc39fbbf99c1056ba643c9cde49b5d/app/main.gd#L693-L694)

## 4. Actual physics baseline: spatial wind deserves the deepest next optimization

I ran the repository’s real `FlightSession`/`Simulation.step` benchmark, first in verification-only mode and then in its shortest permitted measured configuration.

**Environment:** AMD EPYC 9V74 host, Linux x86-64 container, eight-core quota, 8 GiB memory limit, official Godot **4.8 beta 2**, editor/debug build, headless/Dummy backend. The host is shared; these are not consumer-hardware or release-build results.

Each weather case completed:

- Three batches of **480 measured accepted ticks**.
- **240 warmup ticks per batch**.
- Nine successful restore checks.
- Identical final state hashes across its batches and the separate verification run.

| Stock Stik workload | Three batch means, µs/tick | Median |
|---|---|---:|
| Legacy steady wind, 3 m/s | 679.610; 618.081; 581.206 | **0.618 ms/tick** |
| Spatial wind, 24 modes, 3 m/s reference wind and 0.3 m/s RMS | 4,555.629; 5,408.696; 4,075.217 | **4.556 ms/tick** |

These are **different weather workloads**, not before/after optimization variants. Three batch averages are not individual-tick percentiles. Rendering and ordinary UI/observer work are outside the timed section.

At 240 Hz:

\[
\Delta t=\frac{1}{240}\approx4.167\text{ ms}.
\]

The spatial case’s median exceeds that period, although one batch falls below it. This identifies insufficient headroom in the tested median configuration; it does not establish sustained FPS or performance on a Mac.

### New opportunity: compute each mode’s time phase once per stage

Both the [GDScript evaluator](https://github.com/bultodepapas/OpenRCsimulator/blob/8fb825a96dbc39fbbf99c1056ba643c9cde49b5d/app/physics/wind_spatial_field.gd#L316-L353) and its [native counterpart](https://github.com/bultodepapas/OpenRCsimulator/blob/8fb825a96dbc39fbbf99c1056ba643c9cde49b5d/research/native-kernel/src/nk_spatial_weather.hpp#L212-L253) repeatedly calculate:

\[
r_i=\operatorname{fposmod}\!\left(\omega_i(t+t_{\mathrm{epoch}}),\,2\pi\right).
\]

At a fixed stage time, this value is identical for the aircraft datum and all station queries. The point-dependent phase is then:

\[
\phi_i=\operatorname{fposmod}
\left(
\operatorname{fposmod}(k_{N,i}N+k_{E,i}E+\phi_{0,i},2\pi)+r_i,
2\pi
\right).
\]

The proposed change retains the exact binary64 value \(r_i\) once per mode and stage.

It **preserves** the spatial and final remainders, all four point-dependent trigonometric evaluations, wall terms, and ordered vector reductions. It does not approximate the wind or reuse full wind samples between RK trial states.

For \(M\) modes, \(Q\) qualifying queries, and \(S\) independently owned groups per tick:

\[
\text{operations removed per tick}=M(Q-1)S
\]

for both temporal multiplications and remainders.

With 24 modes, ten queries, four ordinary RK stages, and 240 accepted ticks/s, that is:

**207,360 temporal multiplications and 207,360 remainders removed per simulated second.**

The reference counting replay observed 24,000 queries over 480 ticks, averaging 50 per tick, including separate pre-step work. Counting savings for that fifth group requires its own correctly scoped implementation.

This removes 90% of the repeated **temporal term** for ten queries. It removes only 30% of the original three-remainder work and none of the four trigonometric calls per point. It is therefore **not a 90% wind-speedup claim**.

### Prototype evidence and remaining gates

The isolated C++ prototype uses **512 bytes of value storage** for 64 doubles, plus metadata. It passed **38,853 component checks with zero unexpected differences**.

It also demonstrates a critical failure condition: **the same pointer and time do not guarantee unchanged coefficients**. The owner must remain immutable for the context lifetime. Stage changes, rebinds, reset, retries, and configuration changes require appropriate new scratch.

The prototype is not wired into the production native stage and has not been timed. A GDScript implementation requires separate integration across the station sampler and environment/provider layers while preserving overridden provider methods and refusal order.

The native evaluator currently targets Linux x86-64. Its prototype does not establish Apple Silicon benefit. The reference implementation is therefore essential to investigate alongside it. [Native platform and compiler contract](https://github.com/bultodepapas/OpenRCsimulator/blob/8fb825a96dbc39fbbf99c1056ba643c9cde49b5d/research/native-kernel/toolchain-lock.json)

## 5. Implemented: exact audio interpolation with less per-sample dispatch

The second implementation changes [`EngineVoice.render`](https://github.com/bultodepapas/OpenRCsimulator/blob/8fb825a96dbc39fbbf99c1056ba643c9cde49b5d/app/render/engine_voice.gd#L59-L74).

The oscillator calls a GDScript interpolation helper for every generated sample. The valid-domain path now evaluates the same expression inline:

```text
index = phase * 4096
lo = int(index)
sample = table[lo] + (table[lo + 1] - table[lo]) * (index - lo)
```

Update order, table values, smoothing, output allocation, and the original `fposmod` phase update remain unchanged.

A block-level guard requires normalized finite phase, finite nonnegative frequency, and a sufficiently large table. Otherwise, the original helper handles the block. This matters: unconditional inlining changed how an invalid phase error propagated, so that version was rejected.

The measured result was:

| Component | Before | After |
|---|---:|---:|
| Rendering one generated audio second | **6.435 ms** | **4.937 ms** |

That is **23.3% lower component cost**, but only approximately **1.5 ms saved per generated second per active voice** on this host. This path serves companions and the player’s legacy soundscape route; it does not represent the entire default soundscape.

Verification includes:

- **868 checks**, including exact PCM/state comparisons over **422 blocks and 122,633 frames**.
- Permanent voice suite: **86/86 passed**.
- Engine-audio integration: **147/147 passed**, including queueing, pause, restore, restart, accepted-state observation, and simulation checkpoint parity.
- Engine-sound suite: **the same one failure out of 27 checks on baseline and candidate**, caused by the existing expected aircraft list omitting `stik-electric-6s`. The complete logs match after restoring the required original WAV assets.

The absolute saving is modest, and duplicated interpolation adds maintenance cost. That is why this ranks below controller resolution and spatial-wind work.

## 6. Further mathematical CPU opportunities

### Companion forecast: reduce squared distances before taking roots

[`pilot.gd::_score_bank`](https://github.com/bultodepapas/OpenRCsimulator/blob/8fb825a96dbc39fbbf99c1056ba643c9cde49b5d/app/ai/companions/pilot.gd) computes 33 forecast distances for each threat and retains the minimum.

For finite, nonnegative, identically computed squared distances:

\[
\min_j\sqrt{d_j^2}=\sqrt{\min_j d_j^2}.
\]

A no-trace path can take **one square root per threat instead of 33**. It should still return the original distance in meters; directly comparing squared scores would change subsequent margins and biases.

At 60 Hz planning, with \(N\) healthy companions each considering the player and the other companions, the clear-path count is:

\[
1980N^2\quad\longrightarrow\quad60N^2
\]

roots per simulated second. At \(N=3\), that is **17,820 → 540**.

The existing clear-traffic shortcut already avoids eleven extra candidate banks; those must not be counted on every plan. Trace output still requires individual distances. NaNs, overflow, ties, thresholds, and fallback behavior need explicit qualification.

The same predictor also repeats bank-to-turn-rate evaluation at clamped interpolation endpoints. Reusing the **exact calculated endpoint results** could reduce 32 tangent/division evaluations to five per candidate without changing heading accumulation. Substituting an algebraic endpoint without preserving floating-point evaluation would be a different proposal.

These changes remain unimplemented. The pilot is source-bound and needs exact decision-state, command, trajectory, replay, and rebind qualification.

### Native spatial stage: avoid calculations whose results are overwritten

In [`nk_stage.hpp:273–296`](https://github.com/bultodepapas/OpenRCsimulator/blob/8fb825a96dbc39fbbf99c1056ba643c9cde49b5d/research/native-kernel/src/nk_stage.hpp#L273-L296), legacy wind and air data are computed before the spatial branch replaces the air result on both success and refusal.

Moving the legacy initialization into the nonspatial branch could avoid one legacy query and an air calculation containing **two square roots and two `atan2` calls** per qualifying stage.

This must first be checked against the actual optimized build: the compiler may eliminate some work already. Libm calls can also affect floating-point exception flags or `errno`, so “the result is overwritten” is not sufficient by itself to prove every environmental behavior identical. No native stage-parity or timing claim is made for this candidate.

## 7. GPU opportunity: an offscreen afterimage can retain a full-screen pass

The afterimage visibility code checks patch alpha without checking whether its projected contribution matters inside the viewport.

A checked fixture using production dose calculations and the exact visibility method produced:

- Viewport: **1920×1080**.
- Vertical FOV: **50°**.
- Patch center: **x = 2,340.09 px**, beyond the right edge.
- Radius: **23.164 px**.
- Nearest viewport distance: **18.136 radii**.
- Layer state: **shown**.

The [shader](https://github.com/bultodepapas/OpenRCsimulator/blob/8fb825a96dbc39fbbf99c1056ba643c9cde49b5d/app/render/sun/sun_afterimage.gdshader#L9-L36) requests a mipmapped screen texture and evaluates up to eight patches. Its mask is:

\[
m_i=\alpha_i e^{-x_i^4/2}.
\]

At that distant witness, the ideal tail is below \(10^{-23490}\). However, it is **mathematically nonzero**, so a finite cutoff requires a validated numerical and visual error budget.

For finite \(0\le m_i\le1\):

\[
1-\prod_i(1-m_i)\le\sum_i m_i.
\]

That provides a conservative way to bound combined alpha, then bound color error using the actual output range and format.

The proposed experiment preserves all patch state and decay, but hides the item when every contribution is below the accepted envelope. It must handle viewport/FOV changes, radius clamps, overlapping patches, uncertain values, pause/seek, and near-edge transitions.

A nominal full-screen pass covers **2.07 million pixels at 1080p** and **8.29 million at 4K**. Hiding the item may also remove a screen-copy/mipmap dependency when other consumers do not require it. An early fragment branch alone does not necessarily remove that dependency. Godot’s documented screen-reading behavior and the pinned engine’s canvas paths support this distinction. [Godot Engine (latest) documentation in English](https://docs.godotengine.org/en/latest/tutorials/shaders/screen-reading_shaders.html?utm_source=chatgpt.com)

This is a concrete refinement of **existing A26 work**, not a newly measured GPU speedup.

## 8. Shadow indexing: useful memory result, rejected synchronous implementation

The current [shadow collector](https://github.com/bultodepapas/OpenRCsimulator/blob/8fb825a96dbc39fbbf99c1056ba643c9cde49b5d/app/render/projected_shadow.gd#L35-L75) expands model faces into an unindexed position-only mesh.

The tested Stik builder produced:

| Representation | Positions | Indices | Logical payload |
|---|---:|---:|---:|
| Current | 495,888 | 0 | 5,950,656 bytes |
| Indexed candidate | 84,428 | 495,888 | 2,996,688 bytes |

That is **49.64% less logical position/index storage**, approximately **2.817 MiB per tested mask**. Deindexing the candidate reproduces the original position bytes before another `get_faces()` conversion; bounds and face streams also match.

But construction measured:

- Current collection: **8.950 ms median**.
- Collection plus indexing/finalization: **108.193 ms median**.

The roughly **100 ms additional preparation cost** makes an unconditional synchronous implementation unattractive for stutter reduction. I did not promote it.

There is also a consumer contract: [`field_projected_shadows.gd`](https://github.com/bultodepapas/OpenRCsimulator/blob/8fb825a96dbc39fbbf99c1056ba643c9cde49b5d/app/render/field_projected_shadows.gd#L154-L165) treats the vertex array as a deindexed triangle stream. Globally indexing the collector would break that interpretation.

A viable next experiment would use an aircraft-specific finalizer or a bounded prepared artifact. Actual RSS, VRAM, upload cost, post-transform cache behavior, and GPU time remain unmeasured. The pinned engine also snaps positions and builds cached triangle-mesh structures inside `get_faces()`, so bypassing it requires preserving more than raw indices. [Pinned triangle-mesh implementation](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/core/math/triangle_mesh.cpp#L108-L184)

## 9. What should happen next

The next implementation should focus on **the reference spatial-wind stage cache**, alongside the native version, because the measured expensive workload currently uses GDScript.

The practical sequence is:

1. **Restore the existing CI gates**, preserving coverage rather than weakening expectations.
2. Run the supplied input/audio patch through normal application integration and physical-controller/audio checks.
3. Integrate temporal-phase reuse with exact provider ownership, refusal, rollback, checkpoint, trajectory, and native/reference tests.
4. Measure the afterimage pass and F10 recording boundaries on actual target hardware.
5. Qualify companion mathematics through the source-bound replay workflow.
6. Evaluate shadow indexing as prepared data, with loading and memory budgets.

Whole-game benefit depends on how much time the optimized component occupies. For component speedup \(s\) and serial-work fraction \(f\):

\[
S_{\mathrm{total}}=\frac{1}{(1-f)+f/s}.
\]

Even the controller’s 3.12× component result becomes approximately **1.073× overall** if it occupies 10% of the relevant work, or **1.205×** at 25%. The actual fraction is unmeasured. A GPU bottleneck can conceal CPU savings in FPS while input processing still becomes cheaper.

### Target measurement campaign

Start at **1920×1080**, recording the effective renderer, output/internal dimensions, MSAA, reconstruction, quality settings, source and native identities, power/thermal conditions, weather seed, aircraft, camera, companions, and cache state.

Use five alternating independent baseline/candidate pairs with **30 seconds warmup and 120 seconds capture**. Measure cold and warm loading separately. Reserve longer sustained runs for candidates that pass the initial screen.

Collect:

- CPU and GPU frame/pass times.
- Physics cost and accepted tick counts.
- Actual displayed/interarrival frame intervals.
- Average FPS, p50/p95/p99/p99.9, maximum intervals, and stall bursts.
- Simulation-time/wall-time ratio.
- Peak and retained memory, plus actual runtime texture/buffer formats.
- Physical input-to-displayed-response latency, not only handler timestamps.

Keep clean timing runs separate from diagnostic profiler runs; profiler overhead and inclusive-versus-self attribution can otherwise distort conclusions. [Godot Engine (latest) documentation in English](https://docs.godotengine.org/en/latest/tutorials/scripting/debug/the_profiler.html?utm_source=chatgpt.com)

The test matrix should include Home-launched gamepads, raw radios, helicopters, spatial wind at 8/24/64 modes, clear and conflicting companion traffic, active-roll shadows, near-ground vegetation, night/cloud transitions, aircraft changes, and F10 start/stop.

One additional constraint emerged from the successor review: graphics quality currently changes some scenery collision inventories when a world is built, while the new project instructions require graphics settings to leave physics unchanged. That needs deliberate reconciliation before treating reduced collision content as an equivalent graphics optimization.

The delivered patch makes two measured CPU improvements now. The strongest next step is to qualify the spatial-wind cache against the real flight-session baseline, then use target GPU captures to decide how much additional benefit comes from eliminating afterimage work and improving loading boundaries.