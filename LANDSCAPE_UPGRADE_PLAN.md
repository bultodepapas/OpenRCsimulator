# Landscape upgrade

Status: LU-00–06 implemented, reviewed and delivered, 2026-10-11. Native visual/flight checks pass; combined Linux regression result is 207/208 GDScript tests, with one isolated atmosphere-trim platform discrepancy. Nearby collision-query cost and independent human/hardware acceptance remain open. Owner: environment integration lead. Prefix: LU-. User explicitly requested this root document and implementation. Existing L/SC/FW/TOD/CR plans retain their historical status and human acceptance gates.

## Findings and direction

The installed binary reports `4.7.2.stable.official.ed1daf0bf`; `app/project.godot` selects Compatibility/OpenGL. Keep that exact engine and renderer. The field already has deterministic Quaternius tree cards, detailed turf, near grass, procedural club buildings and people, four licensed car models, four aircraft snapshots, distant landmarks, a generated horizon, two established time-of-day interfaces, and experimental crash effects. This is an integration and quality upgrade, not a replacement engine or asset pipeline.

Baseline production captures on an NVIDIA RTX 3090 show primitive close vegetation/people, regular parking, opaque windows, shallow distant relief and incomplete lamp hardware. All four menu aircraft already have parked snapshots. They must remain catalog-complete after this work. Existing source documents: [landscape](docs/LANDSCAPE-PLAN.md), [visual quality](docs/VISUAL-QUALITY-PLAN.md), [scenery](docs/SCENERY-PLAN.md), [field world](docs/FIELD-WORLD-PLAN.md), [time of day](docs/TIME-OF-DAY-PLAN.md), [ground physics](GROUND_PHYSICS_PLAN.md), [crash](docs/CRASH-DAMAGE-PLAN.md), [tools](docs/TOOLS.md). Retained research: [LU-00](docs/research/landscape-upgrade/LU-00/README.md).

Visual direction: a modest temperate rural RC club, maintained grass runway, informal gravel parking and working pits. Use muted foliage, warm timber/brick, weathered metal and neutral vehicle paint; variation follows species and use. Keep the northern flying box and runway unobstructed. Taller trees/buildings stay behind the pilot line. Add layered ridges with atmospheric depth, irregular vegetation clusters, proportioned relaxed people, physically legible windows and shielded lighting. Avoid excessive saturation, whole-screen bloom, flashing scenery or clutter behind the airplane.

## Ownership and integration

Working tree initially had only unrelated `docs/research/extra-300-realism/`; concurrent edits then appeared in main, atmosphere, scenery, preferences, wind configuration and capture tools. Preserve every external edit. User explicitly confirmed proceeding carefully. No aircraft source/generated geometry edits. No UI redesign, aircraft data retuning or renderer migration. Re-read shared files immediately before each narrow patch; check status/diffs during integration.

| Responsibility | Owner / paths |
| --- | --- |
| Plan, review, terrain/glare/lighting, integration, captures | Lead; this plan, new `app/render/landscape_upgrade/`, narrow `render/world/world.gd`/`render/field.gd` hooks, credit include entry in all three `export_presets.cfg` filters, `tools/landscape/`, LU evidence |
| People, nearby vegetation, parking and fleet | Luna max bounded task; `scenery/prefabs.gd`, new scenery helper module, placement generator and targeted tests; lead owns shared scenery hook |
| Float64 collision detector and session response | Luna max bounded task; new `sim/scenery_collision.gd`, focused session hook and tests; lead composes field/scenery/light inventory and main integration |
| Resource/licensing review, then bounded lighting support | Luna max; LU resource report; implementation only after lead assigns exact paths |

There is no direct messaging endpoint for independent local developers. This file records ownership, visible changes are preserved, and the user confirmed continuing. Subagents communicate interfaces before editing. Draft scripts are checked in an isolated copy before being installed in `app/`.

## Phases and acceptance

| Step | Priority / work | Proof required | Status |
| --- | --- | --- | --- |
| LU-00 | Inspect code/scenes/assets, previous experiments, actual engine and live work; research primary sources; freeze direction and ownership | This plan precedes app edits; baseline captures; source/license audit | Done |
| LU-01 | Layered distant relief and near vegetation: coherent scale, variation, ground detail, restrained deterministic wind, keep clear flight corridors | Four ridge chunks/12,288 triangles; 10 crowns + 6 shrubs; [native pilot/overview evidence](docs/research/landscape-upgrade/LU-06/README.md) | Done |
| LU-02 | Proportioned people with relaxed poses and subtle clock-driven movement; varied parking; every catalog aircraft in pits, Avanti on support with gear-up model | [Population proof](docs/research/landscape-upgrade/LU-02/README.md); 13 people, 11 cars, four rebaked aircraft, clearance checks | Done |
| LU-03 | Warm visible house interiors/window depth, exterior pools, daylight fixture meshes, runway edge/threshold lamps, coherent day/night transitions | [Lighting proof](docs/research/landscape-upgrade/LU-03/README.md); 45 checks; final FW and static TOD native views | Done |
| LU-04 | Tunable sun glare, angular falloff, exposure response and depth-tested solar-disc visibility including passing aircraft | [Ten matched-image checks](docs/research/landscape-upgrade/LU-06/glare-checks.json) pass; one draw, +0.120 ms paired 1080p frame p95 | Done |
| LU-05 | Immutable scenery collision inventory; swept float64 tests and material/severity responses through existing crash event/effects; deterministic reset/checkpoint behavior | [51 detector, 25 session, 22 setup checks](docs/research/landscape-upgrade/LU-05/collision-report.md); native actual flight/wreck/pause/reset 56/0; visual checkpoint 18/0. Nearby query cost exceeds target | Implemented; cost gate open |
| LU-06 | Integration polish, regression checks, measured native performance, screenshot set, licenses/credits and honest limitations | [40 screenshots, raw metrics and limitations](docs/research/landscape-upgrade/LU-06/README.md); 207/208 Linux tests, all later shell gates pass; native atmosphere 140/0; packed resources/credits and flight verified | Done; Linux trim gate qualified below |

## Technical choices

Reuse existing assets and source definitions. New geometry is original procedural repository content under the project license. Existing cars/tree derivatives retain exact package CC0 evidence in [scenery provenance](assets/scenery/PROVENANCE.json) and [landscape provenance](assets/landscape/PROVENANCE.json). Research more sources before downloading; no asset enters the build without exact license and redistribution evidence. [Resource review](docs/research/landscape-upgrade/LU-00/resources.md) records adopted/rejected tools, source URLs and attribution. Maintain a shipped `app/assets/landscape/UPGRADE_CREDITS.md` and source ledger.

Compatibility supports spatial depth textures and MultiMesh; use a small scene-local glare pass sampling the solar disc in the opaque depth buffer, rather than Forward+ compositor effects. Use actual sky sun direction/visibility and existing exposure. Depth occlusion must include opaque aircraft, buildings, terrain and alpha-scissor foliage. Transparent materials are a documented limitation. Cloud attenuation must follow the existing deterministic cloud field. Cap veiling intensity and expose an off/intensity control. Sources: [Godot 4.7 postprocessing](https://docs.godotengine.org/en/4.7/tutorials/shaders/advanced_postprocessing.html), [screen reading](https://docs.godotengine.org/en/4.7/tutorials/shaders/screen-reading_shaders.html), [rendering limits](https://docs.godotengine.org/en/4.7/tutorials/3d/3d_rendering_limitations.html), [MultiMesh](https://docs.godotengine.org/en/4.7/tutorials/performance/using_multimesh.html). Verify shader behavior on the installed build; documentation alone is not runtime proof.

Night fixtures use a few local lights plus instanced emissive heads and hardware; avoid a real light for every runway marker. Rooms use shallow interior geometry, frames and localized warm illumination. Preserve existing solar/sky/fog curves and replay clock. Hook both field-world flow and explicit TOD snapshots: both must produce the same lighting features and allow live update without stale lights. Existing shadows remain coordinated with the concurrent owner's settings changes.

Collision authority stays in 64-bit scalar/PackedFloat64Array simulation math, never Godot rigid bodies. Compose immutable proxy geometry from validated field/scenery/lamp placements. Use spatial cells and swept aircraft probes, earliest time of impact, stable IDs and explicit provenance. Distinguish solid building/vehicle/trunk, flexible foliage and frangible fixtures/parked lightweight models. Severity is an engineering estimate based on approach speed and mass, not calibrated RC structural strength. Reuse existing immutable crash snapshot/event/presentation boundary; do not assert deformable or physically validated damage. Any nonfatal response must avoid repeated impacts/energy creation and reset reproducibly. Collision inventory must be included in checkpoint identity; disabled scenery must have matching collision behavior.

Distant visual ridges remain an explicitly bounded backdrop unless backed by a matching collision sampler. Never silently turn the current ground-contact millimeter relief into meter-scale slopes. The aircraft must hit nearby tangible scenery; any unreachable/backdrop boundary must be documented and tested separately.

## Performance budgets

Targets are estimates to be checked on native hardware at 1280×720, then 1920×1080: 60 fps (16.67 ms frame p95), report median/p95/p99 after warmup and capture GPU/driver/renderer. Compare paired scenes, not headless rendering counters. This host is RTX 3090; it cannot establish the owner's slowest-machine gate.

- Landscape visible-pass budget: ≤300 draws and ≤1 million primitives; all four parked aircraft included. Report directional shadow passes separately and the active aircraft separately.
- Added vegetation ≤24 visible draws; use cell batching/instancing and finite ranges. No per-tree process callbacks; original shader clock/wind contract.
- Glare: one additional draw, nine or fewer fixed solar visibility samples per fragment, target ≤1 ms incremental frame p95. No GPU-to-CPU readback in flight.
- Lighting: maximum 6 spot lights and 2 omni lights affecting local field views, at most 2 shadowed local lights; instanced markers. Keep Compatibility's per-mesh light limits in view.
- New texture allocation ≤32 MiB; prefer original geometry/shared materials and existing atlases. New runtime assets ≤20 MiB compressed.
- Collision query target p95 ≤100 μs on this host; report separately from 240 Hz full physics tick (existing 500 μs target remains open). Static broadphase built once, no scene traversal per tick.

## Validation and delivery

Use the production world builder for daylight/night/club/pits/runway/aerial captures, a native glare transit fixture, and deterministic high-speed collision/session fixtures. Capture both explicit TOD and FW routes; check pause, reset, return Home, repeat build and exposure/glare changes. Measure populated scenes after warmup without concurrent benchmarks. Run relevant old tests and full `app/test.sh` where supported; Windows CRLF shell scripts require a disposable LF checkout for WSL, never normalize other tracks' live files. Capture engine errors even when exit status is zero.

Deliver checked-in English evidence, screenshots, metrics, commands, source hashes and asset credits under `docs/research/landscape-upgrade/LU-06/`. Preserve actual failures and remaining limits. Human flight readability, low-end performance and physical impact calibration are independent acceptance gates; do not relabel software tests as those proofs.

## Final integration findings

Implicit bundled scenery now requires matching default spatial geometry, not only a field ID; an edited field with ID `default` can still fly without misaligned scenery. Explicit scenery files retain full placement validation. Visual attachment and collision composition share this policy. Regression fixtures now explicitly select their intended scenery/shadow mode; trace checks require different collision-world identities while retaining identical unobstructed flight samples and legacy visual-only behavior.

The Linux extreme-atmosphere reset fails after 50 trim iterations with residual 0.16638981173064932. Restoring both collision-owned simulation/session files to `HEAD` reproduces the exact failure; both native Windows variants pass 140/140. This limits attribution to those hooks and does not identify the underlying platform cause. [Baseline comparison](docs/research/landscape-upgrade/LU-06/atmosphere-baseline.md). The full suite is **not** reported as passing.

At 80 m/s and the actual 240 Hz rate, first-hit query p95 is 28 μs in empty air, 470 μs near a car and 431 μs near a shade-tree crown, measured while the Linux suite was active. The nearby 100 μs target remains open. Full-flight frame p95 is 3.896 ms on the RTX 3090. [Measurements](docs/research/landscape-upgrade/LU-06/README.md). No additional external runtime asset or plugin was adopted; the verified source families and MIT/CC0 records remain authoritative.
