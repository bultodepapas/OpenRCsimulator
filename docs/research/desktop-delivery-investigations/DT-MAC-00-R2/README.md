# DT-MAC-00-R2 — Apple Silicon integration audit

2026-10-28 · Research and production implementation design. Three **Terra 6.1 Max** specialists worked in parallel on Apple technologies, pinned Godot compatibility and repository architecture; the lead reconciled their findings into the [authoritative execution plan](../../../plans/apple-silicon-performance.md). No renderer, engine pin, runtime dependency or physics behavior was changed by this task. No Mac benchmark, GPU capture, thermal run or release qualification was performed.

## Reports and scope

| Report | Coverage |
| --- | --- |
| [Apple technologies](apple-technologies.md) | Metal/Metal 4; spatial, temporal, neural, interpolation and denoised MetalFX; GPU-family/OS distinctions; M1–M5 and newly documented M6; unified memory, TBDR, tensors, shader compilation, presentation, power and 2026 diagnostic tools |
| [Godot compatibility and delivery](godot-compatibility.md) | Exact 4.8-beta1 source and public APIs, Metal driver construction, capability/scale/fallback behavior, native-extension boundaries, Mac tooling/export/CI gaps, beta defects and final-package gates |
| [Repository audit](repository-audit.md) | Renderer launcher, High effects, preferences/recovery, reconstruction/history, Auto scene detail, frame/soak/resource collection, shader/reflection/transparency/pipeline risks and existing test seams |

Primary Apple documentation, dated feature tables, WWDC25/26 sessions, current product/release records, Godot releases and exact source were consulted. Context7 supplied documentation orientation; exact pinned source takes precedence where it conflicts. The reports link the supporting pages beside each claim, and distinguish Apple API availability from engine integration and measured application behavior. Earlier [R1 investigations](../DT-MAC-00-R1/README.md) remain dated evidence, not current engine instructions.

## Findings that change implementation

| Finding | Consequence / work package |
| --- | --- |
| OpenRC now pins official 4.8-beta1; the older Apple plan still assumed 4.7.2 | Keep the authorized current pin and matching templates; refresh all platform assumptions. DT-MAC-02a/03a |
| Pinned Godot creates an **MTL3 command driver**, despite 4.7 documentation describing automatic Metal 4 selection | Native Metal and Metal 4 command submission are separate claims. Integrate existing MetalFX first; use a separately pinned upstream engine project for DT-MAC-10 |
| MetalFX Spatial/Temporal exist in the engine but have no OpenRC provider; current adapter treats every non-Native provider as temporal and gates all on High | Add provider-specific method/device/scale/AA policy, Mobile spatial eligibility, UI and tests. DT-MAC-07a–c |
| Engine refusal/internal fallback can differ from requested or property-reported scaling | Check support/range before apply; establish the actual pass with backend evidence. Unsupported requests resolve honestly to Native; unknown effective pass blocks qualification |
| At audited `b56eb5f`, camera notifications submit resets only to the experimental DLSS backend; concurrent provider-advertisement/FSR changes are unqualified here | Verify MetalFX reset/context lifecycle through the engine; neither path's notification count is MetalFX SDK acknowledgement. DT-MAC-07b |
| Diagnostics already record effective driver, but continuous frame collection is limited to 300 seconds | Extend current instrumentation rather than duplicate it; implement continuity/completion for real 30-minute runs. DT-MAC-02b |
| Scene-detail Auto already maps `apple m` to Medium and unknown GPUs to High | Explicit migration and regression tests are needed for a capability/measured policy. DT-MAC-06a |
| Darwin editor acquisition, native Mac CI and final downloaded-app trust are not supplied by universal cross-export | Add native tooling and package gates; retain current beta template correction and check post-tag engine fixes separately. DT-MAC-02a/03a/08b |
| 2026 Apple additions are newer than the pinned engine's verified integration | Separate neural inputs, interpolation and engine features into conditional DT-MAC-11–13; no checkbox or GPU-name heuristic establishes support |

The Metal driver conclusion is based on the exact [driver factory](https://github.com/godotengine/godot/blob/4d10419cacd6d3009976e8f9fd3abd970fd58018/drivers/metal/rendering_context_driver_metal.cpp) and [MetalFX callback code](https://github.com/godotengine/godot/blob/4d10419cacd6d3009976e8f9fd3abd970fd58018/servers/rendering/renderer_rd/effects/metal_fx.cpp). The [compatibility report](godot-compatibility.md) retains the contrary documentation and source-access limits rather than hiding that discrepancy.

## Source identity and limitations

Initial HEAD was `c953c8c848db7acac4ed33e606ba580e213d4244`. Another workstream advanced the shared tree to `b56eb5fa3e08ffdb53860a656be7e431b3e2b547` during the audit and continued editing camera/reconstruction/native graphics paths. The specialists inspected current source and recorded that identity; line references can move. No performance baseline was frozen, and this task preserved unrelated edits. Freeze the actual combined source, dirty diff and artifact hashes before implementation or testing.

Graph-first discovery was used; its incomplete coverage of newer GDScript graphics files required direct current-source inspection. External references were checked as dated primary evidence, not instructions. Apple's feature tables/DocC and Godot documentation/source have differing dates and sometimes conflicting descriptions; runtime capability and final binary verification remain mandatory. The source report also records a shell tag-lookup discrepancy rather than treating the web viewer as independent binary verification.

The historical plan records that an M1 Air with 8 GB is available, but this session had no configured Mac access. GPU core count, exact OS/model, baseline measurements and all newer-host acceptance remain open. Universal export structure, Windows software checks, vendor demonstrations and agent agreement do not qualify Apple Silicon flight performance.

## Verification of this documentation change

The lead reviewed all three reports against the updated plan, reconciled the Metal 4/documentation contradiction, and checked relative document/file targets and the documentation diff. The eight owned documentation files passed a relative-file-target and trailing-whitespace check; `git diff --check` passed for the four tracked edits. Research links are embedded in the specialist reports; no downloaded assets, benchmark images or large traces were added. This is documentation-only work, so the [contribution rules](../../../../CONTRIBUTING.md#make-a-change) require link/content checks rather than a simulation rerun. Implementation and its native acceptance remain explicit open work in the plan.
