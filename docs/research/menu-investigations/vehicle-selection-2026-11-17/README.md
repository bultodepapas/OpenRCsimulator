# Vehicle selection, skins and loading investigation

**Date:** 2026-11-17; expanded with twenty targeted investigations. **Scope:** source audit and implementation planning; no runtime optimization or new performance benchmark is delivered by this branch.

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
| [Twenty investigations: T01–T20](techniques/README.md) | Individual research notes with actual search terms, primary evidence, OpenRC application, counterexamples, recommendation and controlled experiment |
| [Benchmark protocol](benchmark-protocol.md) | Existing tools, measurement definitions, controlled experiments and regression matrix |

The broader [menu redesign](../../../plans/menu-redesign.md), [global performance plan](../../../plans/global-performance-visual-quality.md), [aircraft contract](../../../AIRCRAFT_CONTRACT.md) and [Creator plan](../../../plans/aircraft-creator.md) retain their ownership. This investigation narrows their vehicle browsing and appearance work; it does not claim their other gates are complete.

## What is known

- The audited source exposes **13 vehicles**: eight airplanes, one helicopter, one quad, one airship and two cars. The 49 built-in appearance choices counted across those entries include defaults; they are not 49 different vehicle models. No boat is registered in this source snapshot.
- The catalog constructs one text button per vehicle. The existing skin gallery has static preview support, but only the Corsair has checked-in gallery thumbnails in this snapshot.
- A skin change calls the same Home preview request path as a vehicle change. A previously unseen vehicle/skin pair normally constructs another visual and consumes a full model-cache slot.
- The caches have count limits, not complete byte or GPU-residency budgets. Pending work, copied geometry, skin decoding, old and candidate visuals, retained resources and queued destruction can overlap.
- Idle flight-scene preparation deliberately pauses preview-broker admissions. Its lifecycle workaround must be preserved while testing a browsing-aware scheduling policy.
- Historical measurements show why feedback and completion must be separated. They do not establish current 4.8-beta2 timings or performance on the user's computer.
- The expanded audit verifies synchronous transactional selection saves, Creator's explicit extension restrictions, BasisU import recipes on two representative models and existing pipeline-compilation counters. Each is a specific measurement/compatibility boundary, not proof of a current bottleneck.

## What the twenty investigations add

The [research index](techniques/README.md) groups twenty distinct mechanisms across catalog/UI, preparation/scheduling, memory/cache lifetime, storage/asset delivery and first-use rendering/persistence. It documents the terminology used to search for mechanisms, evaluates transfer from other engines and original papers, and maps every recommendation to UI-VS and a controlled experiment.

The plan now distinguishes immediate thumbnail, optional proxy and full visible readiness; work admission versus retained-cache policy; observed owner release versus estimated GPU retirement; stock-format experiments versus Creator admission; and in-memory selection versus durable preference publication. Counterexamples prevent attractive shortcuts from silently adding startup cost, delayed disposal stalls, stale assets, lost settings or memory growth.

During expansion, main advanced to `16acd44`. The [scoped drift check](techniques/README.md#source-pin-and-drift-check) found the cited selector, builder, persistence, importer and sidecar paths unchanged. This branch retains runtime `3c91936`; a newer-main merge is not implied by this documentation update.

## Evidence classification

**Verified current-source fact** means checked against the pinned source above. **Historical measurement** means taken from an existing dated report with its original engine, host and resolution. **Hypothesis** means a code path has a plausible cost that needs attribution. **Proposed target** means a product/engineering acceptance objective, not an achieved result. These categories are kept distinct throughout the packet.

This review used repository files, the existing performance and UI reports, official Godot documentation and pinned engine source, and the engine vendors' own asset-management documentation. It did not run the simulator, capture a new UI image, measure the user's machine, import assets, change physics, or qualify an exported package.

## Delivery verification

The initial delivery at `4b750f4` added six documents and five index updates. Its scoped parser/anchor check passed 105 new local references. That is the historical first delivery, not the scope of the twenty-investigation expansion.

The expansion adds twenty technique notes and their index, and updates the plan, audit, UX, engine overview, benchmark and navigation/decision records. Verification uses the parsing and target/anchor functions in `tools/ci/check_docs.py` against the candidate Git tree, covering every link in the new notes/index and newly added links in modified documents. The final publication receipt below records the checked scope. This local check does not repair inherited links or replace required hosted CI. External source URLs are outside the local-target check.

**Expansion verification:** 29 Markdown paths relative to `4b750f4`: 20 technique notes, one research index and eight modified documents. All **146 new local links and anchors** passed; fences are balanced across all 29 paths and `git diff --cached --check` passes. T01–T20 are present exactly once as individual notes and all map into the plan and E0–E18 protocol. The check excludes 395 unchanged link occurrences rather than claiming a repository-wide link repair. No runtime code or assets changed, and no native performance, simulation or package tests were run.

Independent source and architecture reviews checked the loading, identity, launch, memory, persistence and import assumptions. Their corrections include visible-first-draw ordering, incompatible requests for the same engine path, finite retirement/pressure policy, low-tier dependency closure, durable-state checks and generation ordering across settings writers. Runtime suites remain future implementation gates, not tests claimed for this documentation-only review.
