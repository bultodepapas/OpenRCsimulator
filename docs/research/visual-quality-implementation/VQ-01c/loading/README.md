# DT-11a — reuse unchanged lake geometry

Follow-up: [generated default buffers reduce cold loading](cold/README.md). The
measurements and manifest below remain the original in-memory-cache campaign.
Next follow-up: [exact grain precomputation and package repairs](grain/README.md).
Latest follow-up: [night-kit geometry extraction and integrated package checks](night-kit/README.md).
Audio/lifecycle follow-up: [bounded probe teardown and 50-cycle diagnostics](audio/README.md).
Latest repeated-build repair: [default ground-image byte reuse](ground-image/README.md),
with exact mip/ownership checks and five additional frozen-source loading pairs.

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
