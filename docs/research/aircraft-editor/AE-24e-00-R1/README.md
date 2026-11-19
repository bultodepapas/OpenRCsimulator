# Sponsor decal Workshop — 60 sequential investigations

**AE-24e-00-R1 · 2026-11-19 · America/Bogota**  
**Branch:** `plan/sponsor-decal-workshop-2026-11-18`  
**Repository source follow-ups:** `0d251cb070a280bab6d6a3251af7955ed0bbec74`  
**Outcome:** a revised implementation handoff and reproducible offline exercises.
The native editor, aircraft rendering and hardware qualification remain pending.

The research followed the requested **10 → 20 → 30** progression: sixty distinct
questions, with a synthesis after 10, after 30 and after 60. Early findings chose
the next questions. The result keeps the requested game-like experience—many
sponsor stickers, movement, proportional size, rotation, explicit flips, copies
and layers—while resolving the contracts needed to implement it in this repository.

## Read the deliverables

| Deliverable | Purpose |
| --- | --- |
| [Updated implementation plan](../../../plans/sponsor-decal-workshop.md) | Ownership, sequence, capacity candidates and first native tasks |
| [Integrated architecture](../AE-24e-00/architecture.md) | Rendering choice, frames/regions, legacy proof route, assets, save/export, LOD and wreck ownership |
| [Updated player interaction](../AE-24e-00/interaction-design.md) | Direct placement, repeat/duplicate, ordering, precision, readable paired copy, input alternatives |
| [Native validation matrix](../AE-24e-00/validation.md) | Pass/fail gates and honest separation of completed/offline versus pending/native work |
| [01–10](investigations-01-10.md) | Renderer bounds, clipping, receiver filtering, topology, picking, undo and event-driven baking |
| [11–30](investigations-11-30.md) | Distortion, normal/color math, charts, LOD, ownership, input, real livery UX, image admission and persistence |
| [31–60](investigations-31-60.md) | Platform math, depth/order/overdraw, resources, actual repository seams, controls, asset policy and measurement |
| [Evidence ledger](evidence-ledger.json) | Every question, query, source, finding, decision, limitation and next question; all three syntheses |
| [Executable exercises](../../../../research/aircraft-editor/sponsor-decals/projection_exercises.py) | 37 standard-library-only mathematical and ownership cases |
| [Exercise results](exercise-results.json) | Exact observations, byte calculations, counterexamples and scope limitations |
| [Existing sponsor register](../AE-24e-00/sponsor-register.md) and [asset pack](../../../../research/aircraft-editor/sponsor-decals/README.md) | Original artwork/provenance and the previously delivered flat interaction study |

## Method and evidence quality

One lead conducted the investigation sequence, interpreting and recording each
question before advancing. Search refinements, opening a result and inspecting
source code belong to that question; they were not inflated into additional
investigations. The first and second syntheses were completed before the next
batch began. Helpers reviewed already gathered evidence and created original
offline exercises; they did not run competing external research sequences.

English queries prioritized official engine documentation, exact upstream source,
research authors, game manuals and developers' firsthand GitHub/forum discussions.
Investigations 44–49 are targeted inspections of the actual OpenRC integration
rather than generic web searches. Final review followed up on the same source-proof
question in the exporter and direct-field consumers; those checks do not create
an investigation 61.

The ledger contains **95 source URLs**, not 95 independent confirmations.
Several sources are revisited for different questions, and related documentation
belongs to the same evidence family. Every entry distinguishes a sourced finding
from a proposed design consequence and states what the source cannot establish.
No survey percentage, measured performance or user-study prevalence is inferred
from forum anecdotes.

For source reads, the ledger records the Git blob when available. OpenRC reads
are commit-pinned; Godot implementation checks use `cafc17a19` where recorded.
Upstream `main`/`dev` and `stable`/`latest` pages are dated snapshots, not immutable
version guarantees. Older 4.5/4.7 API pages support scoped concepts and still need
the pinned 4.8 beta check. A three.js, Unity, Unreal or Babylon technique is a
comparison, not proof that Godot exposes the same API or performance.

## Staged synthesis

### After the first 10 — choose the data contract before the renderer

The first batch kept an ordered, editable sticker document as the canonical
result. Clipped receiver-local geometry became the first rendering candidate
because it can avoid mirrored stock UVs; native projectors remained a bounded
comparison or placement ghost. Dense overlap, thin-surface isolation and actual
cost were made independent acceptance gates. See [01–10](investigations-01-10.md).

Review then corrected three overly easy assumptions. Geometric adjacency alone
does not define an allowed paint region. An ordered document does not prove
ordered pixels. A revision token can reject obsolete publication while a stale
job has already damaged a shared output. These findings directed the second
batch toward semantic receivers, alpha correctness and output ownership.

### After the next 20 — make the assumptions falsifiable

The second batch added explicit normal/reflection transforms, color/alpha
boundaries, unique-chart correspondence and mip padding. It separated image
source bytes from runtime resolution and transient outputs, and required complete
portable dependencies instead of local-cache hashes. The Gran Turismo manual
informed readable opposite-side copying and direct numeric adjustment.
See [11–30](investigations-11-30.md).

A decisive arithmetic check showed why 16 images at a 1024-pixel edge cannot
automatically fit a 32 MiB GPU target. Review also exposed the need to include
the custom base archive, preserve actual legacy source admission, and synchronize
the receiver's real LOD rather than merely matching its labels. Those gaps drove
the final batch's repository and platform checks.

### After the final 30 — define the integration route

The final batch retained the clipped overlay as a **candidate**, with explicit
depth, ordering, region, LOD and wreck gates. It made resource lifetime and
aggregate admission concrete, reused the existing strict JSON/PNG foundations,
and proposed a separate v5 facade instead of casually editing proof-covered
legacy files. It also added visible layer actions, transparent-pixel selection,
discrete gamepad/keyboard routes and per-asset transform capabilities.
See [31–60](investigations-31-60.md).

The resulting design is ready for a bounded native implementation experiment.
The research does not certify a backend, all aircraft, every historical profile,
or the 64-instance capacity target.

## Decisions that changed or became more precise

| Area | Integrated consequence | Evidence |
| --- | --- | --- |
| Surface selection | Authored semantic paint region and rigid owner precede adjacency/facing/depth; preserve valid UV seam crossing without joining gaps | 03–08, 11, 51 |
| Projection | Six-plane clipping, normal/tangent transforms, reflected winding, stable orientation and separate 3D/UV-area checks | 03, 12, 32–34, 50 |
| Dense overlap | Validate 2/8/9/32/33/64 ordered layers; do not regroup A–B–A as A–A–B; physical offset is not layer order | 01–02, 14–18, 35–38 |
| LOD | A shared selection owner or proven geometric invariance must keep receiver and overlay aligned across real threshold changes | 19, 47 |
| Ownership | Each generation owns mutable output; freeze immutable completed state and retain it until all consumers release it | 20, 28, 40, 42–43, 59 |
| Memory | Encoded, decoded, resident and peak budgets are separate; 1024 is conditional, not a free quality switch | 16, 25, 29, 38–39 |
| Base appearance | Freeze exact factory/stock/custom paint plus receiver identity through every preview and flight consumer | 44–49 |
| Old profiles | Separate facade/envelope, actual trusted source verification, unchanged legacy projection and independent new proof package | 26, 41, 45–46 |
| Portability | Include required permitted custom-base archive and sticker bytes; budget complete encoded package before export | 24–27, 44–45 |
| Interaction | Stable layer selection, Duplicate/Stamp, explicit order actions, fine/numeric steps and single-input alternatives | 21–23, 52–55 |
| Sponsor art | Preserve originals and approved derivatives; per-asset operations and source metadata, no invented partnership or blanket license | 56–58 |
| Evidence | Matched native scenes, cold versus warm work, repeated/interleaved captures and raw timing/resource samples | 29–30, 59–60 |

The full entry numbers above are navigable in the three batch reports. The
[architecture](../AE-24e-00/architecture.md) contains the actual revised contract;
this table is the rationale for those changes.

## The compatibility route the developer should test first

The current proof set includes `workshop/presentation.gd` itself. Extending that
file in place can stale the same old companions the new reader is supposed to
preserve. The proposed first experiment keeps legacy proof-covered files intact,
adds a new facade/envelope and supplies each legacy consumer its validated
legacy projection. New visual base/receiver/decal data travels separately.

This is not just a renderer dispatch. Preview invalidation, smoke, lighting,
mechanical audio, thumbnail, store, recovery, trial, bundle, restart/return and
trace sidecars all need an explicit route. Resolve the trusted registry and real
source/package proofs before accepting a profile; a self-consistent fabricated
companion hash is not sufficient. The exporter needs a new proof marker alongside
the existing single-generation legacy marker. [Source audit and proposal: 46](investigations-31-60.md#46-legacy-read-compatibility-requires-preserving-source-proof-paths-not-only-json-bytes).

Preserve profiles already admitted at this baseline. Already stale historical
records stay recoverably unavailable unless their actual dependencies or a reviewed
migration are supplied. Existing rebind has limits and cannot be advertised as
universal migration. Old apps are not promised to import v5. The initial whole-v5
cap remains 65,536 bytes, so a maximal standalone stack and a maximal legacy profile
cannot both be assumed to fit.

## Executable exercises and numerical results

Run from a full checkout with Python 3.11+:

```sh
python research/aircraft-editor/sponsor-decals/projection_exercises.py --check
```

**Recorded outcome: 37/37 named cases pass.** The cases use simple closed-form
geometry, rational alpha results, exact byte arithmetic and an abstract ownership
model. They are not tests of the future production implementation.

Two counterexamples matter to the design. A clipped triangle can retain 3D area
0.5 while its projected UV area is zero. A stale job can mutate accepted and frozen
pixels in a shared target even if its publication token is rejected. Both require
native acceptance cases; neither is solved by schema validation.

| Sixteen unique RGBA8 images with complete square mip chains | Exact payload bytes | Approximate MiB |
| --- | ---: | ---: |
| 256 × 256 | 5,592,384 | 5.33 |
| 512 × 512 | 22,369,600 | 21.33 |
| 1024 × 1024 | 89,478,464 | 85.33 |

These totals exclude alignment, metadata, geometry, custom-base additions, staging
and retained outputs. The proposed +32 MiB aggregate GPU peak needs admission of
the whole incremental live set, not just this column. The 512 tier's texture
payload leaves 11,184,832 bytes before everything else; that is not a measured
guarantee that the feature fits.

Sixteen **separately** Base64-encoded 1 MiB files take **22,369,664 bytes**. Under
24 MiB that leaves **2,796,160 bytes** before JSON, physical source snapshot,
custom-base archive and other metadata. Encoding one concatenated stream would
produce a different padding count and is not the proposed per-file calculation.
[All observations and limitations](exercise-results.json).

The alpha oracle is linear-light source-over, with straight inputs and outputs
and explicit premultiplied intermediate calculations. A browser canvas, encoded
sRGB capture, material lighting or tone mapping needs its own comparison boundary.
No native pixel result is claimed.

## What is completed and what remains open

| Evidence | Status |
| --- | --- |
| 60 distinct investigations; 10/20/30 counts and staged syntheses | Complete |
| Official/upstream/firsthand sources and pinned OpenRC follow-ups | Recorded with scope and limitations |
| Original offline projection/normal/color/budget/ownership exercises | 37/37 pass |
| Integrated plan, architecture, interaction and acceptance documents | Updated by this R1 |
| Original asset pack and flat simulated interaction checks | Previously recorded; see their dated [validation](../AE-24e-00/validation.md) |
| Real browser interaction/layout | Earlier launch attempt blocked; still unqualified |
| Native Godot clipping, lighting, order, LOD, wreck and resource lifetime | Pending |
| 64 layers / 16 images and GPU/CPU/frame-time budgets | Candidate bounds; native qualification pending |
| Production sponsor catalog activation and complete portable v2 | Pending the corresponding implementation steps |

The next tasks are AE-24e-01's two-family native renderer comparison and a bounded
AE-24e-03 facade/source-proof feasibility check. Stop broad research here and use
the [acceptance matrix](../AE-24e-00/validation.md) to resolve the remaining
implementation decisions with actual engine evidence.
