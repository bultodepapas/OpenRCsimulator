# SC-13-R1: nearest farm tractor

2026-11-09. Implemented a bounded visual improvement from the landscape review:
the nearest tractor in the default field uses a downloaded model with retained
PBR materials. Source identity, checks, image hashes and raw frame samples are
in [evidence.json](evidence.json). No screenshots are committed.

## Source and integration

[Tractor by Grab3D](https://grab3d.com/models/vehicles/tractor/) is CC0-1.0.
The exact 1,687,044-byte GLB, original notice and upstream manifest are retained
with [provenance](../../../../assets/scenery/farm_tractor/PROVENANCE.json).
The source contains 32,784 triangles; the generated derivative contains 3,994
triangles, five opaque material surfaces and 1K mipmapped S3TC PBR textures.
The self-contained `.res` is 672,869 bytes. Generation and checks are documented
in the [scenery tool guide](../../../../tools/scenery/README.md).

Only group `tractor`, placement 0, at N/E −27/326 m and heading 250° changes.
It is uniformly fitted inside the existing 2.35 × 2.35 × 3.6 m proxy;
the visual bounds are 1.806 × 2.300 × 3.285 m. The imported front is rotated
from +Z to −Z. The other two tractors retain the procedural representation.
The complete normalized default scenery and canonical field must match;
custom fields and explicitly selected scenery files retain their own visuals.

The existing ornament filter runs before the mesh can load. Low removes this
placement; Medium, High and Extreme retained it in the measured default layout.
The static node has no controller, processing callback, engine shadow caster
or distance cutoff. `--farm_tractor=off` restores the procedural appearance.
The source archive stays outside the application; all three desktop export
presets include the derivative metadata and CC0 notice.

The collision world, metal contact policy and `prop:tractor:00` damage identity
are unchanged. A normal metal impact marks the tractor and retains the existing
scar presentation. Reset restores its appearance. The bounded tyre grounding
adjustment affects the mesh only: maximum 0.0271 m, with a 0.04 m rejection limit.

## LOD failure and correction

An early material-first merge produced a mesh with valid bounds but missing
front wheels. Godot 4.8-beta2's meshoptimizer path enables disconnected-island
pruning; after all tyres were merged, one coarse index set contained no front
wheel triangles. The engine retries without pruning only when the entire
simplification becomes empty. This mechanism is visible in the pinned
[ImporterMesh implementation](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/scene/resources/3d/importer_mesh.cpp#L717-L763).

The accepted bake simplifies each physical source part separately, then merges
identical complete material descriptions. Combined LODs retain each part's last
valid representation. Ground contact is checked on actual indexed vertices of
all four tyre regions at every retained LOD. Material signatures include PBR
channel selectors, texture filtering, UV transforms and texture image contents.

`ImporterMesh.from_mesh` also discarded existing ArrayMesh LOD buffers in this
pipeline. The bake now carries explicit part LOD dictionaries, and signature
and package checks inspect the reloaded serialized ArrayMesh buffers. The
rejected preview is excluded from the accepted evidence.

## Verification

All listed checked runs completed with zero engine errors or warnings.

| Boundary | Evidence |
| --- | --- |
| Final native asset/integration test | 81 checks passed: materials, UVs, textures, saved LODs, every wheel contact, routing, transform, damage/reset, source budget and identical on/off collision worlds. A final headless run in the current shared app also passed all 81 checks. |
| Fresh Low process | 3 checks passed, including no mesh/texture load after ornament removal. |
| Reproducible derivative | Real-renderer `--check` matched source/recipe identities and saved mesh/material/texture/LOD contents. |
| Existing scenery consumer | All `test_scenery_build.gd` checks passed. Cells 167,668 + tractor 3,994 = 171,662, below the unchanged 175,000 source allowance. Warm builds 609.2/245.6 ms; cold 1,143.2 ms leaves the existing 800 ms cold target open. |
| Existing collision policy | 25 checks passed in `test_landscape_collision_setup.gd`. |
| Independent runtime copy | Fresh sparse git clone, candidate runtime files overlaid into a minimal project, clean import, no original app cache: 60 asset checks passed. |
| Isolated export | An `all_resources` Windows Desktop PCK with the production metadata/license filters loaded from an empty root: 60 asset checks passed. This checks asset portability, not a full release export. |
| Independent review | Good Enemy reviewed the final source and close/rear images; no actionable tractor blocker found. The reviewer did not run engines or tests. |

Shared HEAD advanced during this work. Native comparisons and consumer checks
used a frozen source copy; evidence records source, recipe, content and file
hashes. Later shared-tree changes to the capture harness and an unrelated
ground-material metadata entry do not redefine these captures.

## Native 1080p review and measured cost

Godot 4.8-beta2 `cafc17a192acf67903910a68aeb3c076c0907a4b`, Compatibility,
NVIDIA RTX 3090, driver 617.42, 1920×1080. One renderer ran at a time.
The matched High pair uses the same frozen scene, birds off, 60 warmup frames
and 360 measured frames per view. Quality diagnostics use 60 measured frames;
actual root mesh LOD thresholds are Low 4, Medium 2, High/Extreme 1 pixels.
These are render-only postcards, with no flight simulation workload.

| Matched High view | Draws off → on | Raw primitive delta | p95 off → on (ms) |
| --- | ---: | ---: | ---: |
| Pilot, 55° FOV | 285 → 290 | +3,116 | 3.831 → 3.061 |
| Pilot zoom, 3.5° FOV | 47 → 52 | +3,494 | 2.363 → 1.828 |
| Close | 23 → 28 | +3,718 | 2.184 → 1.844 |
| Rear | 386 → 391 | +3,718 | 3.728 → 3.207 |
| Aerial | 18 → 23 | +3,494 | 2.194 → 2.230 |

Every matched view adds five draw submissions and zero shadow draws. The
renderer video-memory counter rose by 121,828 bytes; this counter is not a
measurement of every CPU/GPU allocation. Primitive values are raw engine
counters, with no instancing correction claim. One ordered pair cannot
establish a speedup or isolated GPU cost; the lower on-run frame times include
measurement noise and are not an optimization claim.

The final close/rear images show the retained cab, bonnet, exhaust, rims and
all visible wheels. The zoom view retains the front wheels at distance.
At the actual pilot's ordinary 55° FOV the tractor is only a small landmark;
this pass primarily benefits zoom and nearby aircraft views. Low, Medium,
High and Extreme captures were reviewed for the expected quality filtering
and mesh appearance. Local reports and images remain under
`tmp/tractor-intake-20261109/`; their hashes are retained in the JSON evidence.

Required CI, full platform release exports, complete-flight Gate SC review,
lower-end hardware and other renderers remain unqualified by this evidence.
The broader combined performance gate remains open.
