# Native visual audit — 28 November 2026

Ten specialist reviews produced ten admitted shader improvements across ten production files. The independent verifier reviewed all nine other reports and every proposed source change. Numerical shader checks pass; complete visual and target-hardware acceptance remains open. This is a review candidate, not a claim of improved FPS.

This evidence belongs to [VQ-07](../../plans/advanced-graphics.md). [Issue #23](https://github.com/bultodepapas/OpenRCsimulator/issues/23) tracks the work on [`audit/native-visual-cohesion-2026-11-28`](https://github.com/bultodepapas/OpenRCsimulator/tree/audit/native-visual-cohesion-2026-11-28). The immutable comparison baseline is `71306784a250d634854f0c8bab3a927cc46a61b8`.

## Scope and decision

The requested simulator is this repository's OpenRC Simulator. Its actual stack includes the existing Godot host, native C++ modules and custom compiled shaders. Production changes in this audit are confined to those shader paths. No new engine subsystem, production script, simulation tick, aircraft force model, user preset or renderer migration is introduced. Godot's renderer source is inspected to establish the existing host contract; graphics techniques are implemented directly in project shaders.

The visual direction is a believable RC club with legible aircraft, consistent daylight and weather, restrained material contrast, and detail that survives distance and motion. The [research review](research.md) connects that direction to real flying fields, aviation references, primary rendering literature and selected game imagery. Visual taste and photometric correctness have separate acceptance criteria: a source-level counterexample does not prove that the present game looks bad.

### Implemented candidates

| Finding | Native change | Established evidence | Remaining acceptance |
| --- | --- | --- | --- |
| N1, lake absorption | Use bounded camera-ray length for Beer attenuation; retain an orthographic projection control | Thirty numerical samples, including perspective/orthographic and depth bounds | Oblique/central shoreline frames, foreground controls, hardware cost |
| N2, lens curtain | Square the signed Gaussian rim distance by multiplication | Nine signed samples; removes GLSL's undefined negative-base `pow` input | Full engine compilation and held-curtain images on each backend |
| M1, roof normals | Use relative UV conditioning and signed tangent-frame checks in both roof shaders; supply continuous texture gradients | Forty executable helper cases; independent 10,000-case frame comparison including mirrored UVs | Close/remote roof images, degenerate and flat-map controls |
| M2, Moon detail | Compute texture footprint from both projected-plane derivatives, retaining the original radial footprint as a lower bound | A symmetric four-pixel quad selects baseline mip 0 and candidate mip 6.692645; the conservative floor also preserves the original filtering at a representative diagonal limb | First native close-up exposed sharper limb steps; corrected native close/wide pairs, subpixel motion and supersampled comparison remain acceptance gates |
| P1, inactive Moon | Move the uniform zero-radiance return before projection and derivatives | Source control-flow review; active derivative flow remains uniform | Identical inactive images and real sky-pass timing before crediting speed |
| L1, RC dirt lights | Honor the light's `SPECULAR_AMOUNT` in the custom GGX accumulation | Three scalar controls; the active spot's 0.35 setting supplies a native factor of 0.70 | Isolated lit dirt with zero/partial/full specular, diffuse controls |
| PBR-01, countryside palette | Reuse the existing backend-aware sRGB helper once per vertex for the proven authored palette | Fourteen transfer samples; independent inspection of all 7,168 triangles found no mixed-color interpolation | Forward+/Compatibility field images; unchanged photo-sampler controls |
| PBR-02, windsock | Derive the conical tangent from radius taper rather than diameter taper | Three rigid-section samples; default normal angle corrects from 6.164° to 3.091° | Fabric highlights, flexible-section limits, geometry/shadow controls |
| PBR-03, Aserradero veneer | Integrate periodic seam coverage over the unfolded pixel footprint | 168 executable samples and independent whole-period integration checks | Close view, minification and a stable pan of the selected skin |
| ATM1, distant rain | Keep wrapped coordinates but pass unwrapped gradients to the fine texture sample | A 500×2 numerical grid removes a false wrap-boundary mip spike | Actual storm-sheet seams, image filtering/compositing and motion |

The changes add no production textures, render targets, passes, geometry, or resource bindings. They do add or rearrange shader arithmetic. The countryside conversion runs per vertex, the lens square replaces `pow`, and the dark-Moon guard may skip work; none is a measured speedup. The relative roof check deliberately restores normal mapping in cases that previously skipped it, so its local cost can increase. Frame-rate parity must be measured.

### Findings that were not changed

The [verification ledger](verification-ledger.json) contains all 24 reported dispositions: **17 validated, six conditional and one rejected**. The 17 include two corroborating duplicates and a measurement limitation; they are not 17 distinct visual bugs. There are 14 unique validated source defects/opportunities, ten implemented above and four deferred below.

| Finding | Independent conclusion | Why the source remains unchanged |
| --- | --- | --- |
| L2 / W2 | Already-lit lake-bed color is fed back through lit albedo | A naive emission replacement mishandles Compatibility exposure/tone mapping. Needs backend-specific radiometry fixtures |
| W3 | Water GGX density/visibility clamps differ from the native model | Removing clamps can create intense and temporally unstable glints. Requires a bounded HDR solution and matched motion |
| AVI1 | HX-700 rotor-blur color is multiplied twice | The ordinary repair belongs to the existing script mesh builder. Creating an unnecessary native subsystem would conflict with this audit's bounded native-only delivery |
| AVI2 | Stationary vegetation receives the aircraft-position wind sample under shear | Needs a separate field-position input while preserving aircraft-local effects and accepted simulation state |

Six hypotheses remain conditional: flight-line composition/readability, two optional paint tints at dusk, low-elevation cloud composition, lake Fresnel/roughness calibration, Moon-disc versus veil attenuation, and cloud/shadow registration away from the supported pilot origin. They lack the matched imagery or defined acceptance criterion needed to justify a change. The verifier rejected extrapolating software-renderer timing to target-GPU performance.

## Reproducible evidence

The pinned engine is `4.8.beta2.official.cafc17a19`, obtained and checksum-verified through `app/get-godot.sh`. The system-wide 4.7.2 executable was not used. The local host exposes no physical GPU or display and disallows the sockets required for a virtual display. It can run the pinned headless engine and a separate surfaceless Mesa OpenGL context.

### Numeric shader probes

[`shader_math_probe.py`](../../../tools/graphics/shader_math_probe.py) extracts the current production formulas, compiles them into a floating-point OpenGL framebuffer, and compares them to independent scalar/integral oracles. Run from the repository root:

```sh
python3 tools/graphics/shader_math_probe.py --out tmp/native-visual-audit-math-new.json
```

The [passing receipt](evidence/shader-math.json) records **nine groups / 1,271 samples**, source SHA-256 values and the exact renderer: Mesa 25.0.7 llvmpipe, LLVM 19.1.7, OpenGL 4.5, EGL 1.5. One thousand samples belong to a single rain-gradient grid; these are not 1,271 independent scenes or benchmarks. The independent verifier matched all recorded source hashes to the candidate.

| Probe | Result |
| --- | --- |
| Water ray length / absorption | Maximum absorption error 2.70×10⁻⁸ against the oracle |
| Signed lens rim | All values finite; maximum error 7.37×10⁻⁷ |
| Palette conversion | Maximum error 1.18×10⁻⁸ |
| Rigid windsock taper | Maximum error 5.18×10⁻⁸ |
| Periodic veneer coverage | Maximum error 3.22×10⁻⁶; full-board mean 1.1/43 |
| Roof tangent helper | Maximum error 5.48×10⁻⁸ |
| Dirt specular control | Maximum error 9.36×10⁻¹² |
| Rain derivative footprint | Expected mip 3.619178; old wrap spike 10.991318; candidate maximum error 6.74×10⁻⁵ |
| Moon center footprint | Baseline mip 0; candidate 6.692645; oracle error 5.01×10⁻⁹ |

The [initial probe attempt](evidence/shader-math-initial.json) is retained. Its lunar fixture straddled two derivative quads, invalidating the zero-radial-derivative baseline oracle. Moving the same symmetric sample to a single quad corrected the fixture. This was a test-fixture error, not evidence of an additional game defect. Rain and lunar probes expose pre-fetch LOD calculations; they do not evaluate texture content, compositing or final game images.

### Integration and image checks

The checked runner records process exit, error/warning counts, completion and log hashes. All nine candidate gates pass: eight suites report 2,407 assertions and zero failures, and the roof gate checks geometry and material bindings separately. [Integration receipts](evidence/integration.json) distinguish baseline and candidate tests and retain two initial missing-asset failures resolved by hydrating the sparse checkout. The [raw headless archive](evidence/headless-raw.tar.gz) preserves the exact logs and checked reports for all 19 recorded attempts, including the unsuccessful attempts; its [manifest](evidence/headless-raw-manifest.json) identifies all 38 files and their hashes. One windsock test used reference physics because the native stage library is unavailable; the headless lens test skips packed GPU buffer layout. Headless checks validate resource consumers and project logic; they do not establish rendered shader correctness or frame rate.

The [dedicated workflow](../../../.github/workflows/native-visual-audit.yml) runs the [matched capture tool](../../../tools/graphics/native_visual_audit.py) against OpenGL Compatibility/llvmpipe and Vulkan Forward+/lavapipe. Each workload uses a clean disposable checkout, the exact baseline/candidate shader bytes, the same pinned engine, fixed profiles/scene conditions and verified 1920×1080 PNGs. Actual runtime file hashes, camera/lighting manifests, observed renderer identity, checked logs and raw intervals are retained. Twelve offline tooling tests cover restoration, source scope, missing timing, renderer identity, matched conditions, active materials/controls and real nested-process completion/error handling.

```sh
python3 -m unittest discover -s tools/graphics -p test_native_visual_audit.py
python3 tools/graphics/native_visual_audit.py --renderer gl_compatibility --workload field:lake_shore --plan
python3 tools/graphics/native_visual_audit.py --renderer forward_plus --workload detail:roofs --plan
```

The field campaign uses six separate scene jobs per renderer. Each job retains A/B/B/A process order on the same VM, with 60 warm-up frames and 30 retained intervals per launch. The six detail groups each use A/B order; detail images do not supply timing comparisons. The roster contains 30 before/after views per renderer, including seeded storm rain, the selected Aserradero skin, seven [isolated dirt/lens controls](../../../tools/graphics/capture_native_shader_controls.gd), and two close roof views with runtime material and UV-footprint witnesses. The roof witnesses intersect the selected mesh on the CPU and verify that the old absolute determinant threshold is crossed; the resulting image must also establish that the target is visible.

The controls exercise the production dirt material under an isolated spot and the production lens stack at exact seeded ages over a fixed chart; those chart images are component evidence, not a game scene. Shared test-harness copies resize existing SubViewports to 1080p; the paint harness also records camera, active-shader identity and native image hashes. Production scripts stay unchanged. The tool explicitly enumerates unexercised conditions, including temporal stability. It checks source, camera, lighting, adapter and decoded pixel identity before producing image differences. A changed-pixel count is evidence of a difference, not a visual-quality score.

The [first Forward+ attempt](evidence/hosted-initial-forward-plus.json) recovered 20 complete baseline images, including all five original roof views. Its roof process remained alive after publishing the completion manifest and was killed at the 900-second deadline; the exact blocked operation is unknown. No candidate block ran. The six-scene field launch took about 19 minutes, so a monolithic campaign also risked exhausting the job deadline. This evidence prompted workload sharding without reducing quality, warm-up or sample count. For image-only fixtures, the revised helper permits a recorded forced cleanup after a 30-second grace only when all native metadata and every expected, fully decoded PNG have been verified and remain unchanged. It preserves stdout/stderr through EOF for the independent checked runner and rejects genuine nonzero exits and engine errors. Imports and measured field launches still require normal completion. [Independent protocol review](evidence/capture-protocol-review.json)

### Lunar regression found during native review

The first complete Compatibility image set at `f066ef26` (production shader bytes identical to `9d456931`) exposed a localized close-Moon regression risk that the numerical center probe could not detect. Independent art and verification reviews found 141 pixels with a maximum channel difference of at least eight levels, all within the limb annulus; 34 changed by at least 64. At image pixel (1166, 390), a pale baseline edge pixel `[181, 182, 187]` became `[37, 58, 88]`, close to the surrounding sky. The [native-scale and enlarged edge comparison](evidence/images/moon-limb-initial.png) preserves this rejected first result. The radial coverage expression had not changed. The two-axis texture footprint could nevertheless select a finer mip than the old radial estimate along a diagonal, changing relief normals and their grazing-angle lighting.

The revised shader uses `max(plane_footprint, aa)`. This retains the center-footprint repair while preventing a sharper-than-baseline mip under the same filter rule. A source-bound scalar probe preserves the center's corrected mip and restores the old mip at an approximate version of the observed limb sample; it is not a rendered acceptance result. The [follow-up receipt](evidence/moon-limb-followup.json) records the rejected first image, geometric reasoning and predeclared native-image checks.

The follow-up workflow reruns both lunar views and all six A/B/B/A field workloads on each backend at the revised source. This smaller routing is permitted only for a push whose entire `app`, `assets` and `tools` difference from `9d456931` is the lunar include. All other source changes and all manual runs retain the full workload roster. Earlier detail evidence remains attributed to its actual source revision; it is not relabeled as a final-source capture.

### Performance acceptance

Hosted software timing, when available, is scoped to that named software installation. Render-loop FPS is derived from post-draw wall intervals. Viewport CPU counters are narrower than whole-game CPU time. Positive GPU polls have unverified age; zero readings remain unavailable. In the sharded campaign, each process CPU/RSS measurement includes startup and that job's selected scene; the initial monolithic receipt spans all six views. Engine video-memory accounting is not physical GPU memory. These quantities are reported separately, following [Vulkan asynchronous query semantics](https://docs.vulkan.org/spec/latest/chapters/queries.html).

Target acceptance requires the same A/B/B/A campaign on a named physical GPU with fixed resolution, driver, renderer, AA, display/present settings, scene, clock, flight backend and an idle host. The supplied hosted runner deliberately forces and verifies a software device; physical qualification needs an explicit hardware profile instead of that software-only policy. Preserve all runs and raw frame-time distributions, CPU scope, GPU query/trace attribution and memory scope. Report variation between launches before claiming a small difference; see [Kalibera and Jones](https://kar.kent.ac.uk/33611/). Attribute actual GPU work with an appropriate profiler such as [Nsight GPU Trace](https://docs.nvidia.com/nsight-graphics/UserGuide/gpu-trace-overview.html). No target FPS, GPU time or memory improvement is asserted by this audit's local receipts.

### Broader PR checks

Ordinary PR CI tests a synthetic merge with newer main-branch changes; the dedicated campaign above tests the frozen audit runtime directly. The [independent CI receipt](evidence/ci-triage.json) attributes the merged visual-capture errors to a runtime shader-global helper added on main, and reproduces four fixture source-pin mismatches already present at the audit baseline that block both shaft and weather publication checks. A session-reach test hit its existing 60-second wall limit after reporting no mismatches in the completed portion; its result remains incomplete. A separate Windows deadline assertion failed by floating-point rounding and passed on a focused retry at the same merge commit. No fixture goldens, runtime limits or production scripts were changed to make these checks pass.

## Independent review and team

All ten requested specialists ran as separate `gpt-6.2-astra` agents with `ultra` reasoning, in batches constrained by four concurrent slots. The verifier reviewed each intake, rejected unsupported interpretations, examined the implementation independently, and retained missing acceptance evidence per finding. The [independent review](independent-review.md) is separate from the implementation report.

| Role | Contribution |
| --- | --- |
| 1. Art director / references | RC field composition, material and game reference research |
| 2. Native rendering architect | Actual host/native/shader paths, bounded integration |
| 3. Graphics mathematician | Derivatives, numerical conditioning, roof and Moon implementation |
| 4. Lighting / GI | Native light semantics and water transport limitations |
| 5. PBR / microtextures | Color transfer, fabric normals and periodic filtering |
| 6. Water / reflections | Ray length, Fresnel and roughness hypotheses |
| 7. Atmosphere / effects | Rain gradients, cloud and lunar visibility |
| 8. Aviation physicist | Rotor rendering and spatial wind consistency |
| 9. Game / GPU performance | Matched capture tooling, timing and memory attribution |
| 10. Independent verifier | Every finding disposition, source review and independent checks |
