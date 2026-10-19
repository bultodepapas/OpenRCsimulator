# Tree and forest completion evidence

2026-10-18. Native Godot 4.7.2 Compatibility on Windows / NVIDIA GeForce RTX 3090. This continuation adds source-material foliage identity and restrained patch variation, completes composition diagnostics, and exercises the retained tree changes through reproducible flight, visual and export fixtures. No tree geometry or replacement source texture was authored.

## Implemented tree behavior

The field retains 1,680 cards: the original 480 near coordinates and 1,200 far trees arranged in twelve irregular habitat patches. The imported scenery selects eight downloaded mature forms across the existing close-tree placements: seven retained Quaternius forms and one lauris71 oak. Bark maps have qualified mip chains; ordinary leaf mips remain rejected. Supported imported materials animate from shared session wind, while the oak preserves its static BLEND material fallback. Spatial cells remain optional and disabled by default.

The new foliage mask comes from the exact downloaded glTF material assignments. It replaces the color-channel heuristic and keeps bark out of the foliage palette. Smooth 180 m world-space variation contributes ±3.5% value plus restrained color balance; individual variation contributes ±2%. The original color atlas, alpha silhouette, instance identity, placement and contacts are unchanged by this material slice. [Reproducible aligned bake, hashes and mip checks](../../L6b-R2/foliage-mask/README.md).

## Evidence boundaries

| Evidence | What it establishes |
| --- | --- |
| [Layered groundcover](groundcover-transition/README.md) | Current v3 margins: 220 plants, 472 habitat triangles and five batches. Complete scenery: 648,435 triangles. Bounded terrain cache and native/export checks; cold 800 ms scenery-build gate remains unresolved on this host. |
| [Mixed understory refinement](vegetation-refinement/README.md) | Subsequent v2 margins mix ferns, tall grass and fewer flowering shrubs with downloaded CC0 litter. Historical v2 total: 649,951 triangles; prior captures and timings below remain historical evidence of the preceding version. |
| [CPU optimization follow-up](optimization/README.md) | Equivalent woodland batches with lower construction cost, skipped zero-contribution daylight exposure queries, focused regressions and three combined Home/Fly cycles. Component timings do not establish an FPS gain. |
| [Habitat diagnostics](habitat/README.md) | Deterministic placement, spacing, full-envelope exclusions, geometric density/skyline proxies and source inventory. |
| [Woodland margins](woodland-edges/README.md) | Four source-derived decorative shrub/grass clusters, native composition review and independent geometry/placement checks. Straight-row and ring trials were rejected. |
| [World and wind replay](world/README.md) | Six complete exact replays; render wind controls preserve sampled state. Different forest worlds remain explicitly identified. |
| [Final woodland replay](world-final/README.md) | Two additional complete exact replays preserve the oak-era world identity, 4,980 proxies and sampled states after the R3 decoration. |
| [Native palette readback](palette/README.md) | All 3,360 production shader values match the CPU reference, including a translated MultiMesh parent. |
| [Paired aircraft matrix](readability/README.md) | 640 static cases per build, matching cameras; no daylight invisible targets and identical existing night failures. Human recognition remains separate. |
| [Prescribed camera tracks](motion/README.md) | Six 192-frame clips at 720p/1080p cover oak approach, field-card orbit and forest panorama; close aerial card flatness remains visible. |
| [Active-flight clips](temporal/README.md) | Ten native 720p/1080p clips exercise normal input, banks, chase views and camera cuts with deterministic simulation ticks. |
| [Existing impostor baker](../../L8b/2026-10-18/README.md) | Pinned downloaded tool works in Compatibility; its bounded candidate fails the appearance screen and is not adopted. |
| [Native lifecycle](lifecycle/README.md) | Twenty fixed-wing Home/Fly cycles, stable node counts, zero orphans and released audio/settings on shutdown. |
| [Final lifecycle](lifecycle-final/README.md) | Final R3 candidate completes twenty fixed-wing cycles and twenty RC garage/reset cycles, with stable counts and clean shutdowns. |
| [Suite and package verification](verification/README.md) | Frozen tree suite passes 990 script parses and 528 unit scripts; final woodland overlay passes focused checks and Linux/Windows/macOS export-resource checks. |
| [Frozen comparison](comparison/README.md) | Reconstructed control and candidate share the same application revision; retained overlays and hashes identify their nine visual differences. |
| [Final comparison](comparison-final/README.md) | Inherits that shared runtime and isolates the accepted R3 woodland addition; earlier row/ring trials are not final timing inputs. |
| [Five paired live flights](comparison-final/README.md#active-flight-comparison) | Ten complete native runs at 720p meet frame-time and simulation/wall targets under the recorded desktop load; raw samples and process census are retained. |
| [Prior source/material intake](../../L6a-R1/README.md) and [mature oak](../../L6a-R1/mature-oak/README.md) | Download provenance, source fidelity, bounded geometry, material fallback and earlier static controls. |
| [Bark filtering](../../L6b-R2/README.md) | Accepted bark-only filtering and rejected ordinary foliage mip treatment. |

The comparison uses two frozen copies of the same shared runtime. Only the baseline restores historical field placement, card shaders, imported-tree alias selection and texture import policy; environment selectors disable baseline imported-tree wind. Unused new assets remain in both copies. This is a reconstructed visual control, not a historical complete application. No physics, aircraft tuning or golden flights are changed for the comparison.

Readability, motion and temporal evidence use the original oak-era tree candidate. The final comparison adds the R3 decorative margins and records a new source fingerprint; its world replay, lifecycle and performance evidence are identified separately. Concurrent grass development is not silently included in the tree-only comparison or qualified by its results.

Review movies use the pinned [FFmpeg binary receipt](ffmpeg-proof.json), obtained through `imageio-ffmpeg==0.6.0`. It is an offline evidence tool, not an application dependency; original image/AVI identities remain separate from lossy MP4 review copies.

## Final measured performance

Five alternating baseline/candidate pairs each use 10 seconds of warm-up and 60 seconds of live flight at 1280×720, 60 fps cap and 4× MSAA on the RTX 3090. Every candidate run meets p95 ≤18 ms, p99 ≤25 ms and simulation/wall ratio 0.99–1.01. The worst candidate p95/p99 are 17.807/19.464 ms. Paired p95 differences range from −0.134 to +0.075 ms, with a +0.036 ms median; all five meet the +0.5 ms visual-change allowance. These are monotonic frame intervals, not the capped engine-delta value.

Both builds exhibit isolated long frames; percentile compliance is not a claim of hitch-free delivery. The process census records sustained Task Manager CPU use, intermittent editor activity and a short graph-tool burst, with no competing Godot or FFmpeg run. The existing Blender process remained at low CPU activity. Keep the results scoped to these observed desktop conditions, this GPU, resolution, camera/input route and default grass. They do not qualify an idle host, 1080p live timing, lower-end hardware or the concurrent enhanced-grass implementation. Per-run costs, maxima, memory estimates, source identities and contention bounds are in the linked flight report.

## Conditional work and acceptance

The existing LU 650,000-source-triangle ceiling leaves 81 triangles after the retained oak replacement and four small woodland margins (48 reused shrub cards and 12 downloaded grass clumps, adding 1,956 triangles). These are decorative and do not add collision proxies. Increasing field density by 25% would exceed the 1,680-tree loader contract and add 2,520 card triangles to the separately counted field representation; it needs an explicit shared-budget decision. It is not adopted. More spatial batches previously increased submissions; no new default is justified. Supplier oak LOD1/LOD2 remain in source provenance but their different envelopes and prerendered foliage are not qualified for runtime replacement.

The three far-card forms and eight imported forms are separate populations, not automatic mesh/card LOD pairs. Close aerial captures expose crossed-card limitations; the implementation does not claim full 3D forest parallax. The pinned existing impostor baker was evaluated on one unchanged source: its fast full-sphere candidate fails the tool's appearance screen (24.75% bad pixels against a 10% threshold) and consumes 42.331 MiB of decoded image data for one form. It is not adopted. Expanding the atlas or adopting another mature family requires a measured benefit within shared budgets. Unavailable LOLIPOP downloads were replaced by the documented free-source comparisons; they are not represented as downloaded or integrated.

The retained owner kit remains the independent [100 m attitude-recognition review](../README.md). Automated metrics, fixed-step videos and successful builds do not supply an owner's flight score or establish photorealism. Gate L/SC and hardware-specific acceptance stay distinct from completed software work.
