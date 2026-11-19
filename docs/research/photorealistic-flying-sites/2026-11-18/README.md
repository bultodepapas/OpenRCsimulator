# Photorealistic flying-site research

Research date: **2026-11-18**. Baseline:
[`f7b348e40aa5a44c4cc091d540fbffb55016e583`](https://github.com/bultodepapas/OpenRCsimulator/commit/f7b348e40aa5a44c4cc091d540fbffb55016e583).
Branch: `plan/photorealistic-flying-sites-2026-11-18`.

The user requested a complete investigation and plan for photographic RC flying
sites, including Godot and native alternatives, on a new OpenRC branch. The
[implementation plan](../../../plans/photorealistic-flying-sites.md) owns the
SC-PHOTO step ledger. This directory preserves dated evidence and design
reasoning; it does not claim runtime implementation or device qualification.

## Read the research

| Document | Question it answers |
| --- | --- |
| [Current architecture](current-architecture.md) | Which actual OpenRC interfaces can be reused, and which are missing? |
| [Approaches and tools](approaches-and-tools.md) | What do other RC simulators do, which representation fits each camera, and which tools/engines are practical? |
| [Godot design](godot-design.md) | How should panorama, occlusion, shadows, lighting, camera restrictions, physics and lifecycle fit together? |
| [Capture and asset pipeline](capture-and-asset-pipeline.md) | How does a real flying site become a calibrated, reproducible, redistributable package? |
| [Validation and budgets](validation-and-budgets.md) | Which experiments, mathematical budgets and hardware evidence determine whether the site is usable? |
| [Primary-source register](sources.md) | Which original sources support the claims, with what version and retrieval limits? |
| [Twenty additional technique investigations](additional-techniques.md) | Which image-based, game-production, terrain, material, lighting and loading methods fit this repository, and what should be tested first? |
| [Two-round search record](search-rounds.md) | What were the exact first ten and second ten queries, why was round 2 selected, and which results were retained or rejected? |

## Findings that change the decision

1. **There are two different products.** Fixed-observer photographic scenery can
   use a panorama, while FPV and free movement require geometry or a separately
   validated novel-view representation. aerofly RC10 explicitly makes this
   distinction ([S01](sources.md#s01)).
2. **A photograph is only one part of a working site.** RealFlight's older manual
   describes invisible depth/collision proxies; the RC10 authoring workshop
   pairs a panorama with starts and terrain/collision data
   ([S02](sources.md#s02), [S03](sources.md#s03)).
3. **Godot has useful building blocks.** Panorama backgrounds and shader depth/
   shadow mechanisms exist. Their exact interaction on OpenRC's pinned build
   still requires an experiment ([G01](sources.md#g01), [G02](sources.md#g02)).
4. **Native physics and scenery rendering have different responsibilities.**
   Source inspection finds native evaluator admission, not a second native
   scenery engine. A new field is outside the inspected Mac stock domain; its
   qualification cannot be inferred from Club field results.
5. **The existing field schema and activity routes matter.** Field v1 is strict;
   visual metadata belongs in a separately validated descriptor. Fixed-wing and
   helicopter use the landscape catalog, while the inspected multirotor and
   airship builders need explicit route work. Ground sampling is not a generic
   photogrammetry heightfield API.
6. **Terrain3D is optional.** Version 1.1.0 advertises Godot 4.5–4.8+ support,
   but its platform documentation leaves full Metal support uncertain. It does
   not establish OpenRC collision integration ([T01](sources.md#t01),
   [T02](sources.md#t02), [T03](sources.md#t03)).

Recommendation: keep the current engine, prove one fixed-pilot photo site first,
and build a small 3D/FPV site as a separately gated extension. Native optimization,
multiple panoramas and Gaussian splats remain evidence-driven follow-ups.

The requested follow-up adds twenty distinct technical investigations and twenty
source records (62 total). It favors calibrated projection, conditional tiled
panoramas, relightable scan preparation, bounded surface detail and material
filtering. It checks existing/rejected OpenRC techniques rather than treating
them as new implementation. Current-main source differences and Godot-version
uncertainties are recorded in the search log. The plan maps the selected
comparisons into its existing steps; no runtime qualification is added.

## Relationship to earlier research

Reuse [landscape selection](../../../plans/landscape-selection.md),
[scenery](../../../SCENERY-PLAN.md), [camera views](../../../plans/camera-views.md),
[shadows](../../../plans/shadows.md), [sky and weather](../../../plans/sky-clouds-weather.md),
and the [earlier engine/world comparison](../../moonshot/engine-world-2026-10-28.md).
This work does not reopen all of those tracks or replace their ownership.

The dated [earlier scenery techniques survey](../../scenery-investigations/04-godot-techniques-and-prior-art.md)
summarized photo fields as losing or breaking collision/depth. That is too broad
for this decision: a bare image supplies no geometry, but authored collision and
occlusion proxies are an established method. Its prior performance and appearance
opinions are not benchmarks for this proposal. Preserve the old record and use
the primary-source qualifications here for the new plan.

## Evidence scope

- Current-code observations were made against the baseline above, using actual
  GDScript, configuration and tracked data. The checkout was sparse; missing
  working-tree assets were read through Git when needed, not classified as absent.
- Public sources were researched on the date above. Published compatibility and
  demonstrations do not establish compatibility with the exact pinned binary.
- The plan, formulas, proposed budgets and acceptance thresholds are engineering
  recommendations. No site was captured, no addon installed, and no runtime,
  export, image-quality or target-device benchmark was executed in this task.
- No third-party imagery, commercial simulator assets, downloaded binaries or
  generated screenshots are committed. Large authoring inputs are future work.

## Initial planning-branch verification

Documentation integration was checked on 2026-11-18:

- Eight new documents and five existing documentation indexes/guides form the
  change. Runtime code, dependencies, imported assets and engine pins are outside
  the changed-path set.
- All 153 relative link occurrences and 63 linked heading anchors in the new
  documents and added integration paragraphs resolved. Tracked source paths were
  checked against the Git tree as well as disk because the checkout is sparse.
- The source register contains 42 unique records. The plan contains 18 unique
  step rows: SC-PHOTO-00…15 plus 04a/04b. Only the research step is complete.
- The texture-memory and horizontal-FOV tables were independently recalculated;
  the extreme 1° vertical view contains approximately 45.5 vertical source texels
  in a 16384×8192 panorama. These are calculations, not image-quality measurements.
- Markdown code fences and whitespace were checked. Git whitespace validation
  passed for the integrated changes.
- A separate adversarial review prompted explicit measured-obstacle authoring,
  paved/turf material admission, full shared World/Atmosphere rollback and
  numerical-versus-visual-replay qualifications. Its final bounded review found
  no additional material issue in the completed plan, design, budgets and source
  register; it did not repeat the external research or execute simulator tests.

No simulator, export, capture or hardware-performance test was run for this
documentation-only branch. The implementation gates above remain unverified.

## Twenty-technique follow-up verification

The follow-up was checked on 2026-11-18 against research commit
`03b028c58d953e603c42323e10529e29926b6fa0` and the separately fetched main revision
recorded in the search log:

- Twenty distinct queries were executed as ten first-round queries followed by
  ten selected after those results. The recorded query tables and twenty PT
  investigation headings agree, with one E01–E20 primary-source mapping each.
- Every investigation contains evidence, current-code fit, a proposed experiment
  and a disposition. The source register contains 62 unique records; the
  implementation ledger retains 18 unique SC-PHOTO rows.
- All 252 relative link occurrences and 129 linked heading anchors resolved in
  the ten owned plan/research documents and the changed research-index paragraph.
  Sparse-checkout paths were checked against Git's tracked tree when absent on disk.
- Seven changed documents are within `docs/`. Whitespace/code-fence checks and
  Git whitespace validation passed. No runtime source, dependency or asset changed.
- Independent review required material-specific roughness/specular controls,
  shared static/crash decal allocation and accounting for the lake's existing
  two-slot reflection atlas. Those corrections were checked against source and
  integrated into the comparisons. The final bounded review found no additional
  material issue; search order and links were checked by the lead separately.

No new simulator, capture, export or hardware benchmark was executed. Existing
historical measurements remain scoped to their own engine, scene and device.
