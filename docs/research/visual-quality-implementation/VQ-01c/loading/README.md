# DT-11a — reuse unchanged lake geometry

2026-10-15 construction follow-up: [native helicopter canopy transforms](heli-canopy/transforms/README.md)
reduce geometry extraction by 14.6%, preserving 60 real geometry/kit comparisons.
Non-indexed surfaces now handle Godot's null index slot. Complete-kit timings are
mixed; full loading, FPS and lifecycle qualification remain open.

2026-10-15 presentation follow-up: [reuse unchanged helicopter optic gains](heli-updates/README.md)
preserves 5,245 native update-state comparisons and reduces stable-light CPU
updates by about 19 µs. Six permanent transition checks are added; changing dusk
has mixed process results. Native integration retains the two texture shutdown
errors reproduced on the reference. This is separate from loading and FPS claims.

Follow-up: [generated default buffers reduce cold loading](cold/README.md). The
measurements and manifest below remain the original in-memory-cache campaign.
Next follow-up: [exact grain precomputation and package repairs](grain/README.md).
Latest follow-up: [night-kit geometry extraction and integrated package checks](night-kit/README.md).
Audio/lifecycle follow-up: [bounded probe teardown and 50-cycle diagnostics](audio/README.md).
Repeated-build repair: [default ground-image byte reuse](ground-image/README.md),
with exact mip/ownership checks and five additional frozen-source loading pairs.
Construction repair: [conservative grass-mask filtering](grass-masks/README.md),
with exact native instance output; the new Home/Fly attempt contains paused
samples and does not qualify interactive-loading gains.
Construction repair: [native shadow geometry transforms](shadow-geometry/README.md),
with exact face/bounds parity in 1,206 native pairs and focused current-tree tests.
This is a shadow-construction measurement, not a new Home/Fly or FPS campaign.
Construction repair: [fallback shadow blur indexing](shadow-blur/README.md),
with 100 exact native image/carrier pairs and about 50% less carrier construction
time. The first generation also improves; no cache or complete-loading claim.
Latest construction repair: [horizon azimuth reuse and index preallocation](horizon-build/README.md),
with 40 exact native mesh pairs and about 20% less mesh construction time. A
separate combined native test reproduces texture shutdown errors on the baseline;
that diagnostic remains open and is not counted as a clean native pass.

2026-10-15 follow-up: [fallback shadow pixel reuse](shadow-mask-cache/README.md)
preserves independent images/textures with one fixed CPU mip-byte cache. Repeated
carrier construction measures 16.266→0.853 ms with 100 exact native output pairs;
first-generation and complete-loading non-regression remain open.

2026-10-15 follow-up: [batch population shadow transforms](population-shadow/README.md)
preserves exact geometry in 72 real-cell and 768 synthetic pairs. Repeated
three-cell collection measures 29.990→27.708 ms; full loading remains unqualified.
Field regressions pass; the report retains separate P-51 contract and Home exit
diagnostics from the wider checks.

2026-10-15 follow-up: [helicopter canopy intersection rejection](heli-canopy/README.md)
preserves contour/kit geometry and reduces measured kit construction from 1.753 s
to 0.494 s. Headless integration checks pass; a native texture shutdown diagnostic
reproduces on the reference and remains open. Full loading is not qualified.
The [batched-contour follow-up](heli-canopy/README.md#follow-up-reuse-cuts-for-four-profiles)
then reduces kit construction from 465.734 to 127.429 ms in its own paired campaign,
with exact geometry and six additional permanent contour checks.

2026-10-15 follow-up: [native aircraft-light geometry transforms](night-kit/transforms/README.md)
reduce measured extraction by 15–49% across five fixed-wing families, with 300
exact native geometry/kit pairs. Full-kit gains are smaller and do not qualify
complete loading. The standalone night-kit test now registers shader globals
before model creation and passes headless/native without shader warnings.

2026-10-15 follow-up: [shared upper/lower wing cuts](night-kit/wing-slices/README.md)
reduce measured two-skin construction by 46–51% and complete kit construction by
25–33% across five families. Three permanent ownership checks and 300 exact native
fleet pairs pass; complete loading and isolated hardware qualification stay open.

2026-10-15 follow-up: [bounded fuselage light station scans](night-kit/belly-stations/README.md)
reduce measured complete-kit construction by 15–23%, preserving 300 native
contour/kit pairs. Four boundary regressions and native night-kit checks pass.
Home cache assertions pass with four audio shutdown leaks reproduced on both
reference and candidate; lifecycle and full-loading qualification remain open.

2026-10-15 follow-up: [bounded wing light station scans](night-kit/wing-stations/README.md)
preserve 300 native skin/kit pairs and reduce two-skin construction by 15–28%.
Three endpoint/order regressions pass. Extra's small full-kit difference remains
inconclusive across processes; Home still reports four audio objects at shutdown.

2026-10-15 follow-up: [direct light-contour edge traversal](night-kit/edge-walk/README.md)
removes temporary edge arrays, preserving 300 native contour/kit pairs and reducing
complete-kit pooled medians by 2–8%. Focused lights and Home-cache checks close
cleanly in this run; the earlier intermittent audio shutdown diagnostic remains open.

2026-10-15 follow-up: [single-pass aircraft light geometry](night-kit/geometry-pass/README.md)
preserves 300 native geometry/kit pairs and reduces combined extraction by 17–43%.
Three filter/order/ownership regressions pass. Direct native face extraction is
rejected for different surface semantics; Home's audio exit diagnostic remains open.

2026-10-14. Implemented a bounded CPU geometry cache in `app/render/lake/lake_terrain.gd`.
Source baseline `22b3e482`; Godot 4.7.2-stable, Windows, RTX 3090 / Ryzen 9 5900X.
[Manifest](evidence-manifest.json) pins sources, engine binaries and raw evidence;
[runtime diff](runtime.patch) records the adopted change and regression coverage.

## Attribution and implementation

The actual Home/Fly probe established a loading miss. A disposable copy of the field
builder then attributed 2.77–2.96 s of 3.42–3.88 s total world construction to lake
attachment. A second isolated run separated the basin grid (2.22–2.64 s, 13,205 vertices)
and water (0.75–1.05 s, 57,024 vertices). These are headless CPU construction timings,
not GPU cost. See [field phases](field-phases.log) and [lake phases](lake-phases.log).

Cache exactly one basin array set keyed by serialized `(lake, surface table)` and one
water array set keyed by the full serialized lake. Compare complete bytes; the caller's
identity label cannot conceal changed geometry. A miss replaces the previous entry.
Every build still creates fresh meshes, materials, nodes, reflection probe and lighting
state. Geometry sampling, operation order, triangles and shaders are unchanged. No
worker, delayed launch, scene reuse or physics cache was introduced.

This trades bounded retained CPU arrays for repeated construction. Serialized returned
geometry is about 4.14 MB for the default lake; that is **not a resident-memory measure**.
The first build still pays the original sampling cost. Changed definitions rebuild.

## Measurements

[Builder comparison](geometry-parity.json): eight alternating serial reference/candidate
comparisons, all with identical geometry hashes. Cases include unchanged cold/warm
inputs, water level, bed profile, shoreline, bank and ground-table changes. Lake edits
retain the same identity string deliberately. First default build: 3.508 s reference,
3.431 s candidate; the two warm comparisons: 2.960 / 2.781 s reference versus
4.814 / 4.501 ms candidate. No cold-build improvement is claimed.

Native [before](loading-before.json) / [after](loading-after.json), real Home Fly and
End flight, first post-draw boundary, 1280×720, 4× MSAA, VSync, 60 fps cap, Dummy audio:

| Cycle | Fly first draw before / after, s | Return Home first draw before / after, s |
| --- | --- | --- |
| 1 | 6.233 / 2.653 | 4.336 / 1.190 |
| 2 | 8.691 / 1.769 | 7.486 / 1.114 |
| 3 | 6.004 / 1.730 | 4.014 / 1.127 |

These are one before and one after fresh process, three cycles each; not three randomized
process pairs. Desktop/background activity and OS/import/shader caches were uncontrolled.
Initial Home from app-resource load was 10.695 / 7.821 s, so cold loading is still open.
First Fly still exceeds the proposed 2 s limit. Both processes reported identical live
node counts (878 in flight, 546 at Home), zero orphan nodes at all three Home returns,
unpaused first flight draws and tick 12. Verbose logs closed without engine errors or
ObjectDB retention warnings. This does not close the earlier intermittent exit finding,
the 50-cycle/30-minute soak, display qualification or exported-package gates.

## Verification

- Lake world: **27/27**, including exact warm buffers, independent resources, mutation
  of returned meshes, same-identity lake changes and isolated surface-table changes.
- Disposable defects: identity-only keys and an omitted surface-table key are both
  detected by the new regression checks; retained mutation logs intentionally fail.
- Field integration: **39** passing checks, including failed-start restoration and
  independent Home/flight resources. World presentation context: **17/17**.
- Workshop trial: **36/36**; its frozen-presentation rejection warning is expected.
  Lake surface: **52** passing checks. Offline performance tools: **44/44**.
- Changed/new GDScript files parse; no unexpected engine errors in retained check logs.

The full Linux `app/test.sh`, visual capture suite and exports were not run. Exact
geometry equality supports preserving appearance; it does not replace pilot readability,
native frame pacing, physical validation or platform acceptance. No goldens were changed.

## Reproduce and continue

[Tool commands and contracts](../../../../../research/performance/README.md#homefly-loading-and-lake-geometry).
Extract `app/render/lake/lake_terrain.gd` from `22b3e482` as the reference outside `app/`.
The recorded Windows copy uses CRLF; its normalized content was checked against Git.
Loading runs used `--verbose` and `--cycles=3`; the manifest retains compressed logs.
For phase attribution, decompress the four `.gd.gz` snapshots together outside `app/`
and run `field_driver.gd` with `--headless --path app --script <absolute-driver-path>`.
They contain only attribution timers and local redirects to the copied builders.

Next DT work: attribute the remaining cold Home and first Fly costs, then collect
qualified process pairs and package/soak evidence. LU-10-R1 remains unmodified: this
measurement identified construction work, not a collision-query correction. Visibility,
shader, texture and profile acceptance stays with the ordered global plan.
