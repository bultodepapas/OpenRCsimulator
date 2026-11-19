# Verification and production acceptance

**AE-24e-00 · baseline `cf03e401` · R1 review 2026-11-19.** This branch prepares
the feature; it does not integrate image decals into Godot. Offline checks are
bounded evidence. The production matrix remains open even when a
schema/arithmetic example passes. The [R1 research](../AE-24e-00-R1/README.md)
records 60 sequential investigations and three syntheses; see the batch reports
for [01–10](../AE-24e-00-R1/investigations-01-10.md),
[11–30](../AE-24e-00-R1/investigations-11-30.md), and
[31–60](../AE-24e-00-R1/investigations-31-60.md).

## Reproduce the offline checks

From a full checkout with Python 3.11+, the development dependency in the
[requirements](../../../../research/aircraft-editor/sponsor-decals/requirements.txt)
and Node 18+:

```sh
python research/aircraft-editor/sponsor-decals/build_catalog.py --check
python research/aircraft-editor/sponsor-decals/validate_pack.py --self-test
node research/aircraft-editor/sponsor-decals/check_study.cjs
python research/aircraft-editor/sponsor-decals/projection_exercises.py --check
```

The first three commands reproduce the pack and study checks. The original
results remain in the **historical 2026-11-18 record**; their separate rerun for
the 2026-11-19 logo intake is recorded below. R1 itself did not rerun that suite.
The last command runs 37 closed-form synthetic exercises;
the [recorded results](../AE-24e-00-R1/exercise-results.json) are 37/37 for
that offline exercise only. They do not execute Godot, the GPU, a browser,
native geometry, real resource lifetimes or performance workloads. The small,
well-conditioned examples do not establish production tolerances or a
near-singular cutoff. Finite in-range UVs do not prove nonzero projected area
or correct semantic surface selection.

| Check | Scope |
| --- | --- |
| Reproducible source pack | 12 image assets and 14 generated files: eight exact external originals, OpenRC's master and three original geometric fixtures. Source/output hashes and true image dimensions/type are recorded. No website access is needed to reproduce the pack |
| Catalog | 17 external organizations after the 2026-11-19 source intake: eight with existing reference images and nine with source/delivery leads. Only OpenRC and the three test fixtures enable study placement; this is not approval to ship external marks as player decals |
| Proposal examples | Empty and three-layer proposals bind to the exact synthetic receiver, model, factory paint and image identities. Neither is accepted by the current production Workshop |
| Invalid proposals | Unknown/missing keys, duplicates, unsafe/missing/reference-only assets, stale hashes, unknown/out-of-bounds receivers, invalid frames, dimensions/aspect, angle, numeric booleans, nonfinite values, opacity, layer count, duplicate JSON keys, NaN and byte bounds |
| Appearance selector | Real stock IDs and `custom_` plus 24 lowercase hex characters; malformed custom IDs refused. Schema checks do not load a skin |
| Coordinate reference | Rest/translated/rotated bindings, 90° local hinge, 10%/500% root scale, and non-axis-aligned normal/tangent recovery under nonuniform scale. These are reference calculations, not engine animation proof |
| Capacity | 64 layers accepted structurally and the 65th refused. This does not qualify memory, latency, GPU layer order or rendering at that count |
| Study state/events | Catalog readiness, repeated placement, transforms/flips, layer actions, one-gesture history, cancellation, field focus, export shape, reload and the 64-instance boundary in a deliberately small DOM/event simulation |
| Draft preservation | Exact raw originals retained when catalog/images are missing or data is malformed, oversized, future-version, has unknown fields, invalid dimensions or duplicate instance IDs. Pending image checks block mutation/export; valid key order differences remain accepted |
| R1 synthetic exercises | Six-plane clipping, degeneracy/zero-UV-area counterexample, normal transforms/reflection, linear-light alpha arithmetic, texture-budget arithmetic and abstract output ownership. No engine or GPU qualification |

The validator does not prove full footprint clipping, real receiver binding,
GPU composition, runtime admission or migration. The synthetic fixture is a
concrete handoff contract, not a replacement for GDScript tests against the
actual Workshop paths. The study harness simulates image completion/failure;
it does not exercise a browser decoder, native pointer capture or download UI.

## Logo intake verification — 2026-11-19

The focused intake review passed `build_catalog.py --check`,
`validate_pack.py --self-test` and `node check_study.cjs`: **12 exact assets**,
**two valid proposal examples**, **27 rejected invalid-input cases** and
**25/25 simulated editor checks**. The 12 image files and `asset-lock.json`
are byte-identical to branch parent `8c3f230a1f1f5cf5ba8f036808dc4678a8f45ce1`;
their aggregate image payload remains **233,118 bytes**. No new logo binaries
were added to the public pack.

The expanded catalog has 21 entries: four enabled project/test entries,
17 external references and, within those references, nine metadata-only entries.
The new source receipt records 11 verified download variants for eight
organizations and one unresolved ProModeler lead. Receipt hashes and byte counts
were checked against the exact downloaded source responses. FEETECH's embedded
bitmap and Hiwonder's viewBox-only SVG limitations are recorded explicitly.

The reference-only validator case now supplies the correct Savox hash and aspect
and requires the admission-specific error. This prevents a different failure
from disguising accidental brand activation. An in-memory mutation enabling
Savox makes that guard fail. The study also asserts that every external entry
remains unavailable for placement; the corresponding activation mutation fails
that guard too. The new ProModeler, FEETECH and Hiwonder cards have no local image.

These are offline metadata, byte-integrity and simulated interaction results.
This intake did not rerun the unchanged 37 projection exercises or establish
browser layout, Godot/native rendering, new image decoder compatibility, frame
time or a production permission/admission result. The production matrix remains
open.

## R1 package verification — 2026-11-19

The lead verified consecutive investigation IDs 01–60, the 10/20/30 batch counts,
three synthesis boundaries and complete evidence/decision/limitation fields.
All 60 query records are distinct; the ledger contains 95 source URLs, without
claiming independent corroboration. The generated exercise result exactly matches
a fresh execution of all 37 cases. All 103 local Markdown links and 15 referenced
heading anchors resolve against the proposed files and the audited branch tree.
The R1 update contains seven new and six modified handoff files. These checks do
not rerun the historical asset/study suite or establish any native result.

## Historical browser attempt and restored-file verification

A real Playwright attempt could not open a page. The installed package's bundled
headless browser was absent. System Chromium then failed at startup with
`process_singleton_posix.cc:297`, `socket() failed: Operation not permitted`, and
exited. An independent helper reproduced the failure. No permissions were
escalated. No screenshot, browser layout/accessibility pass or browser-rendered
interaction result is claimed.

The initial validated package passed 27 negative proposal cases, five base-selector
cases, six known-coordinate cases, two nonuniform frame cases and 24 simulated
study checks. During publishing the workspace restarted. The six uploaded feature
documents were recovered from their exact Git blob IDs, and the remaining research
files were restored from the reviewed design/test material. The restored code and
fixtures are not claimed byte-identical to their lost draft. The final branch's
own commands and image lock govern its verification and reproducibility.

**2026-11-18 restored-package record: PASS.** At that time the lead reran the
original three commands: 12 exact
image outputs / 14 generated files; two examples; 27 refusal cases; five appearance
selector cases; six coordinate cases; two nonuniform frame cases; and 24 simulated
interaction/recovery checks. Images total 233,118 bytes. Seven raster files passed
Pillow integrity/dimension checks; five SVGs parsed with no script or external
href. All 66 local Markdown links/anchors resolved. The same three commands passed
again from an isolated Git export containing the 47 necessary handoff/source files,
with no `.git` directory. Staged whitespace checks also passed. These are offline
results and do not close the browser, Godot or hardware matrix below.

Automatic publication review rejected re-uploading three broader pre-existing
project documents as part of this change. The published scope therefore contains
only the new feature plan, research and pack; existing global indexes, parent AE
plan and decisions record remain untouched. The dedicated plan and architecture
retain all decisions and implementation steps. Private-source relationship
summaries were also removed from every published file after automatic review;
entries without public relationship evidence remain source-intake candidates.

Native browser review still needs 1920×1080, compact desktop layout, keyboard focus,
actual drag capture/cancellation, field editing, clipping/overflow, unavailable
storage and downloaded JSON. With a saved draft, remove the catalog, then restore
it and separately remove a referenced image. Both failures must retain the exact
stored original and pause edits/export. Malformed, oversized and future-version
drafts must also survive without silent replacement.

The flat board intentionally allows positions outside the aircraft silhouette.
It does not demonstrate 3D picking, curved clipping, orbit, paired surfaces,
controller support, flight, import or renderer cost. Its format and 100-entry
study history are separate from production's proposed document and existing
shared 32-entry Workshop history.

## Review findings addressed

The lead reviewed independent architecture/source and study findings. The handoff
now accepts real custom-skin IDs; specifies receiver bind-local coordinates and
both normal-transform directions; keeps unresolved raw drafts intact; refuses
destructive normalization of invalid dimensions/IDs; reports blocked Clear actions
truthfully; labels unavailable image cards; and keeps rounded rotation canonical
across reload. The exact engine source resolved stale Compatibility guidance.
The Hitec original's actual WebP signature is preserved with a corrected copy
extension. These findings remain independent of production qualification.

## First runtime spike: AE-24e-01

Use the pinned engine and owning source pipelines for **Ugly Stik** and
**Vantage Jet**. They are qualification fixtures, not runtime dispatch IDs.
Compare native projectors with clipped overlay geometry before building the
whole editor. Retain failed comparisons as well as the chosen path's captures.

| Dimension | Required cases / acceptance |
| --- | --- |
| Count/order | 0, 1, 2, 8, 9, 32, 33 and 64 instances; repeated and distinct images, overlapping on one receiver as well as separated across the model. Preserve ordered overlap while moving the camera; no missing, regrouped or camera-dependent layers |
| Surface | Flat wing, curved body, thin fin, top/bottom, hinge edge, nearby disconnected or opposite panel and transparent canopy. Test an authored, connected face region split by a UV seam: permitted crossing must remain continuous. Separately refuse crossing a real gap, opposite skin or different rigid owner; do not globally weld coincident vertices. Clip to the intended opaque receiver and refuse unsupported surfaces |
| Transform/geometry | Tiny/large proportional copies, arbitrary rotation and canonical boundaries, both flips, readable opposite-side copy, nonuniform transforms with negative determinant/reflection, and 10/100/500% virtual size. Check normal/tangent direction and winding, singular and near-degenerate cases, 3D area **and projected UV area** independently; reject an unusable zero-area projection even when 3D area is nonzero. No double scale or reversed normal |
| View/material | Front/back/top/bottom, grazing view, close/far mips, representative day/night. Compare unlit color and alpha against the independent linear-light oracle below. No projection bleed, hovering edges, z-fighting, unintended emission or lost base material channels |
| Motion | Control deflection limits and intermediate angles, whole-aircraft plus hinge motion, propeller/blur excluded. No bridging a moving gap or attachment to an old rest pose |
| Renderer/LOD | Compatibility on supported desktop hosts; Apple Silicon Mobile/Metal; every admitted model LOD and Low/Normal/High route. Test automatic LOD thresholds in both directions and secondary viewports. Verify a shared LOD owner/selection or geometry invariance across all admitted LODs: matching thresholds, labels or bias alone do not prove the receiver and separately rendered overlay choose the same LOD. Lower texture quality preserves composition |
| Other effects | Ground-mark pool, scenery and concurrent effects share native budgets. Cosmetic meshes must not affect bounds, contact, or wreck grouping |
| Isolation | Two instances with different designs; source geometry/UVs/materials/custom archives unchanged. Picking adds no flight physics bodies |

Use the step's normal evidence home. Keep large raw videos/captures in ignored
temporary output; retain compact representative comparisons and measurements.

### Independent color and alpha oracle

For red then blue half-alpha layers, use linear-light RGB and straight inputs;
composite source-over in premultiplied form and convert to straight output once.
Over opaque white the expected straight RGBA is `(1/2, 1/4, 3/4, 1)`; reversing
the order gives `(3/4, 1/4, 1/2, 1)`. Over transparent, the corresponding
results are `(1/3, 0, 2/3, 3/4)` and `(2/3, 0, 1/3, 3/4)`. Check zero-alpha
edges too. Compare unlit native captures using a declared readback encoding and
renderer tolerance: convert sRGB-encoded RGB to linear before comparing with
these values, while coverage alpha stays linear. A linear RGB value of `0.5`
encodes to approximately `0.735357` in sRGB; raw encoded pixels are not the
linear oracle. Test lighting and tone mapping separately. The exercise is a
mathematical reference, not a passed native pixel test.

## Integration and lifecycle acceptance

| Owner / step | Proof still required |
| --- | --- |
| AE-24e-02/03: contract/migration | Test real valid/stale/missing receiver maps, strict malformed input and representative **baseline-admitted** v1–v4 profiles with their exact proof-covered source files and companions. Verify actual source against the trusted registry **before** the profile validator; preserve the existing one-proof-version marker, add a separate v5 marker/facade, and check unchanged legacy rendering in source and exported PCKs. Changed/missing source dependencies remain explicit; never silently rehash, rebind or assume smoke-bearing records can all be rebound. The proposed first v5 envelope caps the **whole profile at 64 KiB (65,536 bytes)**, including its embedded legacy profile. Verify baseline-admitted old profiles in the new implementation; forward compatibility of older apps with v5 is not promised |
| AE-24e-03/05: physical separation | With physical recipe and aircraft scale fixed, metamorphic off/on cases change decal image, position, size, rotation, flip, order or compatible visual base while retaining identical compiled bytes, model/dependency hashes, physical trial ID and fixed-tick solver results. Compare crash bounds, collision inputs and wreck grouping too, before and after breakup; matching hashes alone cannot rule out scene-derived changes. A changed canonical visual document changes composite identity. Require pixel changes only with discriminating visible asymmetric art, differently colored overlapping alpha layers or a genuinely different base; symmetric flips, nonoverlapping order and hidden edits may look unchanged |
| AE-24e-04: interaction | Place/select/move/scale/rotate/flip/reorder/hide/lock/delete; repeats; one gesture = one shared undo; Escape/focus-loss cancellation; numeric editing; camera arbitration; UI input consumption; keyboard/controller and EN/ES review |
| AE-24e-05: one result | Factory/stock/custom bases agree across preview, immutable save, thumbnail, Test Flight, restart, return and admitted ordinary flight. Missing custom bytes remain recoverable |
| AE-24e-06: storage and jobs | Save/reopen/copy, detached invalid buffer, failed/partial writes and process boundaries retain last accepted revisions. Give each asynchronous job owned output storage: accept B, freeze/undo-retain B, finish stale A and then accept C; verify actual pixels and handles show that A can neither publish nor write over B or C. Retire resources only after current, undo/redo, recovery, frozen-trial and in-flight consumers release them. Revision-token rejection alone does not protect a shared mutable GPU target |
| AE-24e-07: portability and admission | A clean-install round-trip includes every distributable required byte: exact custom `.orskin` base archive, admitted unique sticker assets and referenced built-in revisions, with content hashes; otherwise identify an explicit external dependency. Missing/modified base bytes remain recoverable, never silently become factory paint. Check the complete encoded package and decode peak before export/import, including JSON and the base. Reuse/extract the existing `StrictJSON` and custom-skin PNG pre-decode admission with regression parity; add bounded still-image/APNG, chunk/CRC and aggregate sticker limits without silently changing legacy skin limits. Renamed/missing files, bad signatures, oversized decoded dimensions, animation, hostile SVG/path and duplicate package entries cannot partially publish a design |
| AE-24e-08: lifecycle | Qualified LOD owner changes, breakup/section mapping and re-clipping, unchanged crash bounds/groups/contact, repair/reset and aircraft switch. No ghost, doubled, stale-parent or leaked overlay; retain one logical layer identity when a wreck section splits its fragments |
| AE-24e-09/10: release | Target hardware/native captures and interface acceptance; admitted source/scope/credit/transform flags; exact package manifest; required final brand previews; player docs describe the delivered subset |

## Measurement record and proposed budgets

Record source/image/receiver/visual identities, engine hash, OS, GPU/driver,
renderer, graphics tier, image and instance counts, input sequence, camera/seed,
output size, drawable size and internal 3D size. Start ordinary desktop review at
1920×1080. Apple Silicon Retina follows the native physical-panel exception in
the repository instructions; report all three pixel sizes. Use existing
debug-bridge/testqueue/capture entry points from [TOOLS](../../../TOOLS.md).

Compare matched zero-decal and decorated scenes at every listed count. Include
tiny separated marks, large separated marks and large stacked marks at fixed
**actual output pixels** so overdraw and screen coverage are measured separately
from instance count. Fix camera path, assets, lighting and renderer; record cold
construction separately from warmed runs, repeat/interleave alternatives and
retain samples and captures. Measure CPU/GPU separately, p50/p95/p99 frame time,
worst placement/commit/save/load hitch, draw calls, triangles, textures and
actual steady/peak CPU/GPU memory. Mark unavailable GPU timing as unavailable,
not zero.

Initial normal-tier targets on each declared host are **+1 ms p95**, **+64 MiB
steady CPU**, and **+32 MiB aggregate feature GPU peak** over the matched empty
scene. The GPU target includes artwork, outputs, concurrent or retained/frozen
revisions and GPU-side staging; record CPU staging and temporary copies in the
CPU measurements too. These are proposed targets, not measurements or native
acceptance. All native performance qualification remains pending. Revise texture
tiers or the 64-instance/16-image candidate bounds only with evidence while
preserving player designs.

The [R1 arithmetic](../AE-24e-00-R1/exercise-results.json) calculates full square
RGBA8 mip payloads for 16 unique images. It excludes alignment, metadata, staging,
retained outputs, other resources and driver behavior; fitting this column alone
does not prove the aggregate target fits.

| Image size | Mip levels | Bytes per image | Bytes for 16 images | Payload alone vs. 32 MiB |
| --- | ---: | ---: | ---: | --- |
| 256 × 256 | 9 | 349,524 | 5,592,384 | Below |
| 512 × 512 | 10 | 1,398,100 | 22,369,600 | Below, with 11,184,832 bytes before other allocations |
| 1024 × 1024 | 11 | 5,592,404 | 89,478,464 | Exceeds by 55,924,032 bytes |

Sixteen full-resolution 1024-square RGBA8 mip chains therefore cannot meet the
proposed aggregate 32 MiB target. Measure the actual resident formats and bounded
active set instead of assuming PNG file compression reduces GPU memory. For
portability, 16 separately Base64-encoded 1 MiB files alone take 22,369,664 bytes;
the candidate 24 MiB bundle cap would leave 2,796,160 bytes for JSON, the custom
base and everything else, before accounting for decode peaks.

Check post-warmup stability over 20 Workshop/flight/return/reset cycles,
cancellation and stale callbacks. Existing broader 50-cycle/30-minute release
lifecycle gates remain separate where applicable. Empty/disabled decals allocate
no feature-specific nodes, picking structures, decoded images, jobs or per-tick
work. This research-only branch does not claim full application/native gates.
