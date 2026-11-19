# Verification and production acceptance

**AE-24e-00 · 2026-11-18 · baseline `cf03e401`.** This branch prepares the feature;
it does not integrate image decals into Godot. Offline checks are bounded evidence.
The production matrix remains open even when a schema/arithmetic example passes.

## Reproduce the offline checks

From a full checkout with Python 3.11+, the development dependency in the
[requirements](../../../../research/aircraft-editor/sponsor-decals/requirements.txt)
and Node 18+:

```sh
python research/aircraft-editor/sponsor-decals/build_catalog.py --check
python research/aircraft-editor/sponsor-decals/validate_pack.py --self-test
node research/aircraft-editor/sponsor-decals/check_study.cjs
```

| Check | Scope |
| --- | --- |
| Reproducible source pack | 12 image assets and 14 generated files: eight exact external originals, OpenRC's master and three original geometric fixtures. Source/output hashes and true image dimensions/type are recorded. No website access is needed to reproduce the pack |
| Catalog | 14 external organizations: eight with reference images and six with source/delivery leads. Only OpenRC and the three test fixtures enable study placement; this is not approval to ship external marks as player decals |
| Proposal examples | Empty and three-layer proposals bind to the exact synthetic receiver, model, factory paint and image identities. Neither is accepted by the current production Workshop |
| Invalid proposals | Unknown/missing keys, duplicates, unsafe/missing/reference-only assets, stale hashes, unknown/out-of-bounds receivers, invalid frames, dimensions/aspect, angle, numeric booleans, nonfinite values, opacity, layer count, duplicate JSON keys, NaN and byte bounds |
| Appearance selector | Real stock IDs and `custom_` plus 24 lowercase hex characters; malformed custom IDs refused. Schema checks do not load a skin |
| Coordinate reference | Rest/translated/rotated bindings, 90° local hinge, 10%/500% root scale, and non-axis-aligned normal/tangent recovery under nonuniform scale. These are reference calculations, not engine animation proof |
| Capacity | 64 layers accepted structurally and the 65th refused. This does not qualify memory, latency, GPU layer order or rendering at that count |
| Study state/events | Catalog readiness, repeated placement, transforms/flips, layer actions, one-gesture history, cancellation, field focus, export shape, reload and the 64-instance boundary in a deliberately small DOM/event simulation |
| Draft preservation | Exact raw originals retained when catalog/images are missing or data is malformed, oversized, future-version, has unknown fields, invalid dimensions or duplicate instance IDs. Pending image checks block mutation/export; valid key order differences remain accepted |

The validator does not prove full footprint clipping, real receiver binding,
GPU composition, runtime admission or migration. The synthetic fixture is a
concrete handoff contract, not a replacement for GDScript tests against the
actual Workshop paths. The study harness simulates image completion/failure;
it does not exercise a browser decoder, native pointer capture or download UI.

## Browser attempt and restored-file verification

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

**Final restored package: PASS.** The lead reran all three commands: 12 exact
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
| Count/order | 0, 1, 8, 9, 32 and 64 instances; repeated and distinct images; nine overlapping on one receiver; dense separated logos across the model. No missing or camera-dependent layers |
| Surface | Flat wing, curved body, thin fin, top/bottom, seam, hinge edge, disconnected panel behind the selected part, transparent canopy. Clip to the intended opaque receiver and refuse unsupported surfaces |
| Transform | Tiny/large proportional copies, arbitrary rotation and canonical boundaries, both flips, readable opposite-side copy, mirrored imported nodes, nonuniform source transforms and 10/100/500% virtual size. No double scale or reversed normal |
| View/material | Front/back/top/bottom, grazing view, close/far mips, representative day/night. No projection bleed, hovering edges, z-fighting, unintended emission or lost base material channels |
| Motion | Control deflection limits and intermediate angles, whole-aircraft plus hinge motion, propeller/blur excluded. No bridging a moving gap or attachment to an old rest pose |
| Renderer/LOD | Compatibility on supported desktop hosts; Apple Silicon Mobile/Metal; every admitted model LOD and Low/Normal/High route. Lower texture quality preserves composition |
| Other effects | Ground-mark pool, scenery and concurrent effects share native budgets. Cosmetic meshes must not affect bounds, contact, or wreck grouping |
| Isolation | Two instances with different designs; source geometry/UVs/materials/custom archives unchanged. Picking adds no flight physics bodies |

Use the step's normal evidence home. Keep large raw videos/captures in ignored
temporary output; retain compact representative comparisons and measurements.

## Integration and lifecycle acceptance

| Owner / step | Proof still required |
| --- | --- |
| AE-24e-02/03: contract/migration | Real valid/stale/missing receiver maps; strict malformed input; real v1–v4 historical profiles and changed companion-source pins. Appending empty fields must not silently alter legacy identity |
| AE-24e-03/05: physical separation | Same compiled bytes, model/dependency hashes, physical trial ID and fixed-tick solver results with decals off/on. Visual identity changes when image/transform/order/base changes |
| AE-24e-04: interaction | Place/select/move/scale/rotate/flip/reorder/hide/lock/delete; repeats; one gesture = one shared undo; Escape/focus-loss cancellation; numeric editing; camera arbitration; UI input consumption; keyboard/controller and EN/ES review |
| AE-24e-05: one result | Factory/stock/custom bases agree across preview, immutable save, thumbnail, Test Flight, restart, return and admitted ordinary flight. Missing custom bytes remain recoverable |
| AE-24e-06: storage | Save/reopen/copy, detached invalid buffer, failed/partial writes and process boundaries retain last accepted revisions. Undo/recovery retain reachable image bytes; originals remain intact |
| AE-24e-07: portability | Fresh-install round-trip includes admitted nonbuilt-in bytes. Renamed/missing files, bad signatures, enormous decoded dimensions, animation, hostile SVG/path and duplicate package entries cannot partially publish a design |
| AE-24e-08: lifecycle | LOD switches, breakup/section following, bounds/groups/contact comparison, repair/reset and aircraft switch. No ghost, doubled, stale-parent or leaked overlay |
| AE-24e-09/10: release | Target hardware/native captures and interface acceptance; admitted source/scope/credit/transform flags; exact package manifest; required final brand previews; player docs describe the delivered subset |

## Measurement record and proposed budgets

Record source/image/receiver/visual identities, engine hash, OS, GPU/driver,
renderer, graphics tier, image and instance counts, input sequence, camera/seed,
output size, drawable size and internal 3D size. Start ordinary desktop review at
1920×1080. Apple Silicon Retina follows the native physical-panel exception in
the repository instructions; report all three pixel sizes. Use existing
debug-bridge/testqueue/capture entry points from [TOOLS](../../../TOOLS.md).

After warmup compare zero decals with the same scene at each count. Measure
CPU/GPU separately, p50/p95/p99 frame time, worst placement/commit/save/load hitch,
draw calls, triangles, textures and actual steady/peak CPU/GPU memory. Initial
normal-tier targets are **+1 ms p95**, **+64 MiB steady CPU**, and **+32 MiB steady
GPU** on each declared host. These are proposed targets, not measurements.
Revise texture tiers or the 64-instance/16-image candidate bounds only with
evidence while preserving player designs.

Check post-warmup stability over 20 Workshop/flight/return/reset cycles,
cancellation and stale callbacks. Existing broader 50-cycle/30-minute release
lifecycle gates remain separate where applicable. Empty/disabled decals allocate
no feature-specific nodes, picking structures, decoded images, jobs or per-tick
work. This research-only branch does not claim full application/native gates.
