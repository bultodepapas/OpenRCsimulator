# T11 — Scan-resistant admission for retained previews

**Research date:** 2026-11-17. **Status:** proposal; no runtime measurements. [Twenty-investigation index](README.md).

**Question.** Once a requested visual is ready, can a small probation policy preserve useful repeat selections during a long browse better than the existing recency order, without increasing memory or delaying the selected preview? This is a retention decision, not permission to reject the user's current selection.

## Search and evidence

Actual queries on 2026-11-17: `TinyLFU admission cache frequency sketch scan resistant paper Einziger Friedman Manes arxiv`; `S3-FIFO FIFO queues ghost cache quick demotion original paper SOSP 2023`.

- [Einziger, Friedman and Manes, TinyLFU](https://arxiv.org/abs/1512.00727), 2015 preprint, compares an arriving item with a victim using recent estimated frequency. Its results concern the paper's cache traces, not vehicle previews.
- [Yang et al., FIFO Queues are All You Need for Cache Eviction](https://juncheng.seas.harvard.edu/publication/sosp23-s3fifo.pdf), SOSP 2023, describes a small probation FIFO, larger main FIFO and metadata-only ghost history. It explicitly identifies patterns where a second access just outside the small queue loses to ordinary recency. Its published queue proportions are experimental choices, not OpenRC defaults.

Both are primary research, accessed 2026-11-17. Their trace populations, often millions of objects and different object costs, do not establish benefit for a three-entry menu cache. A simple two-queue idea is transferable; a frequency sketch, ghost queue or full S3-FIFO implementation is not automatically justified.

## OpenRC seam and candidate

[HomeScene](../../../../../app/ui/home_scene.gd) retains up to three vehicle/skin model roots in `_preview_models` and updates `_preview_order`; [HomePreviewResources](../../../../../app/ui/home_preview_resources.gd) separately retains at most two `PackedScene` resources. The latter owns and drains the existing threaded request. They are different caches with overlapping resource owners. The [plan](../../../../plans/vehicle-selection-performance.md#9-ram-vram-and-cache-accounting) preserves both count limits until byte accounting is qualified. In a future 100-item catalog, scanning **metadata** need not build any model; the pollution risk occurs only when players actually select or bounded prediction prepares distinct full visuals.

First implement nothing beyond instrumentation. If repeated-selection traces show one-off completed previews evicting repeatedly revisited ones, trial a bounded probation/protected policy **within the existing owners**. Every explicit selected request completes normally subject to the separate reservation gate. While visible or accepted for launch it remains pinned. When no longer selected, its completed visual is probationary; a repeat confirmed selection while retained can promote it, and a new one-off completion competes with the probationary victim before a protected recent model. Store at most bounded IDs/byte costs; do not retain one node per catalog record. Only completed, verified, still-current results can be retained; obsolete active requests still drain and their stale callbacks do not publish. The resource broker and visual cache need one coordinated policy with explicit ownership, not a third cache.

Use the same candidate key as the preview identity, including content revision, vehicle, skin and compatibility inputs. A cached object still needs the current revision/appearance checks and independent launch validation; cache presence is not validation. Share immutable resources only and keep mutable materials private. This policy does not set the byte budget, determine hysteresis, pool nodes, or delete user sources.

## Falsifiable comparison

After UI-VS-00 and UI-VS-05, compare (A) current recency and (B) the small probation policy at the **same** count caps, measured byte budget, pins, concurrency and warmed/cold setup. Run recorded or explicitly scripted A→B→C→A, a favorite repeatedly interspersed with distinct selections, a one-time fleet scan, and a delayed second-visit sequence that can favor recency. Include heterogeneous large/small stock and admitted imported visuals; use the same immutable revisions and selection input times. Reserve a separate trace for evaluation and predeclare the decision margin based on repeated baseline variation.

Record selected-request-to-first-correct-draw p50/p95/p99, input-frame p95/p99, completed useful retention hits, bytes and work reloaded, main-thread policy overhead, unique estimated/reserved bytes and observed process/renderer peaks, as well as stale-display/validation failures. Count a hit only if it saves work and preserves the requested identity. Measure interaction and recovery after reverse direction; 100/1,000 metadata enumeration alone is not a full-preview workload.

**Reject** B if it fails to improve the relevant return-selection distribution beyond baseline variation, regresses sequential/recent selection or frame tails outside the predeclared tolerance, exceeds the same pressure limits, or changes validity/identity. No paper's hit ratio establishes a product speedup.

**Recommendation and step:** keep existing recency as baseline. Add only the trace counters in UI-VS-00; consider the small policy under UI-VS-05 after the ledger and real workload evidence. UI-VS-10 speculation stays separately gated. No OpenRC performance test was run for this note.
