# Vehicle selection, skins and loading investigation

**Date:** 2026-11-17. **Scope:** source audit and implementation planning; no runtime optimization or new performance benchmark is delivered by this branch.

**Audited source:** [OpenRC Simulator main at 3c91936ab8f9064daa798311b5fb3e89e28d3754](https://github.com/bultodepapas/OpenRCsimulator/tree/3c91936ab8f9064daa798311b5fb3e89e28d3754). Engine: Godot 4.8-beta2, cafc17a19; Compatibility by default, Mobile on Apple Silicon. Read the source identities below before comparing this report with a later main branch.

## Recommendation

Make browsing a lightweight catalog operation, and make a compatible skin change an appearance transaction on an already prepared vehicle. Extend the existing loading owner, preview cache and validation contracts. Move repeatable preview preparation into generated metadata; admit retained resources by measured memory cost; load only useful selected and near-future content.

The current implementation already has asynchronous selected-resource loading, a three-model preview cache, latest-request ownership, a direct paint gallery, and selected flight preparation during Home idle time. Adding another generic loader would miss the remaining work. Full visual construction, fitting, skin processing and resource ownership after loading are the more useful investigation boundaries. Actual dominance on 4.8-beta2 remains to be measured.

## Reading order

| Document | Purpose |
| --- | --- |
| [Implementation plan](../../../plans/vehicle-selection-performance.md) | Authoritative proposed steps, ownership, dependencies, architecture and acceptance gates |
| [Code audit](code-audit.md) | What exists, exact source locations, fleet and skin inventory, likely costs and evidence limits |
| [Interface specification](ux-spec.md) | Catalog layout, clear vehicle/skin identity, input behavior and loading/error states |
| [Loading research](loading-research.md) | Primary engine sources, game loading techniques, RAM/VRAM policy and rejected shortcuts |
| [Benchmark protocol](benchmark-protocol.md) | Existing tools, measurement definitions, controlled experiments and regression matrix |

The broader [menu redesign](../../../plans/menu-redesign.md), [global performance plan](../../../plans/global-performance-visual-quality.md), [aircraft contract](../../../AIRCRAFT_CONTRACT.md) and [Creator plan](../../../plans/aircraft-creator.md) retain their ownership. This investigation narrows their vehicle browsing and appearance work; it does not claim their other gates are complete.

## What is known

- Main currently exposes **13 vehicles**: eight airplanes, one helicopter, one quad, one airship and two cars. The 49 built-in appearance choices counted across those entries include defaults; they are not 49 different vehicle models. No boat is registered in this source snapshot.
- The catalog constructs one text button per vehicle. The existing skin gallery has static preview support, but only the Corsair has checked-in gallery thumbnails in this snapshot.
- A skin change calls the same Home preview request path as a vehicle change. A previously unseen vehicle/skin pair normally constructs another visual and consumes a full model-cache slot.
- The caches have count limits, not complete byte or GPU-residency budgets. Pending work, copied geometry, skin decoding, old and candidate visuals, retained resources and queued destruction can overlap.
- Idle flight-scene preparation deliberately pauses preview-broker admissions. Its lifecycle workaround must be preserved while testing a browsing-aware scheduling policy.
- Historical measurements show why feedback and completion must be separated. They do not establish current 4.8-beta2 timings or performance on the user's computer.

## Evidence classification

**Verified current-source fact** means checked against the pinned source above. **Historical measurement** means taken from an existing dated report with its original engine, host and resolution. **Hypothesis** means a code path has a plausible cost that needs attribution. **Proposed target** means a product/engineering acceptance objective, not an achieved result. These categories are kept distinct throughout the packet.

This review used repository files, the existing performance and UI reports, official Godot documentation and pinned engine source, and the engine vendors' own asset-management documentation. It did not run the simulator, capture a new UI image, measure the user's machine, import assets, change physics, or qualify an exported package.

## Delivery verification

The branch contains six new documents and five small updates to the existing menu, research, ownership and decision indexes: eleven Markdown paths, with no runtime changes.

Local verification reused the parsing and target/anchor validation functions in tools/ci/check_docs.py against the candidate Git tree. All **105 new local links and anchors** passed: every local link in the six new documents, plus newly added links in the five existing guides. New-document code fences are balanced, and git diff --cached --check passes. This scoped check does not claim to repair inherited documentation links or replace the required hosted CI policy. External research citations were reviewed as evidence; their URLs are outside this local link check.

Independent source and architecture review checked the loading, identity, launch, memory and import assumptions before delivery. Runtime suites are implementation gates listed in the benchmark protocol, not tests claimed for this documentation-only review.
