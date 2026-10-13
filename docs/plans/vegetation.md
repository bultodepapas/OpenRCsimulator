# Vegetation and rural landscape improvement

Date: 2026-10-13. Owner: landscape integration lead. Prefix: **LU-22–27**, continuing the [landscape track](../../LANDSCAPE_UPGRADE_PLAN.md). Status: planned before application edits. Scope: a coherent temperate rural RC field, with beautiful layered planting, readable flight views and reproducible rendering.

## Visual direction

Create a maintained airfield within a living countryside: short mown turf transitions into loose meadow grasses, seed heads, clover and scattered wildflowers; darker hedges shelter mixed shrubs and young trees; mature broadleaf trees frame the club; farm plots carry distinct green and golden crops. Let foliage vary in height, silhouette, density, age and colour. Use sage, olive, fresh yellow-green, deep woodland green and warm straw, with small white, yellow, pink, violet, blue and red flower accents. Species grow in patches with quiet gaps, rather than an even confetti distribution.

Keep the runway, its approach corridor, pilot line, paths, slabs, parking and aircraft clear. Tall additions belong behind the pilot or at the distant farm. Low herbs in the flying area stay below the existing 1.5 m scenery limit. Preserve the field's established geography, horizon, lighting, four parked aircraft and physical ground surfaces. Aim for credible plant structure and attractive composition; neither species accuracy nor photorealism is an acceptance claim.

## Resources at hand

| Resource | Available evidence / intended use |
| --- | --- |
| Existing Quaternius tree sources | Three glTF trees, bark and alpha-leaf maps in `assets/landscape/trees/source/`; exact archive CC0 evidence in [provenance](../../assets/landscape/PROVENANCE.json). Preserve the proven distant atlas. Evaluate source detail against close silhouettes; avoid treating every current Quaternius pack as CC0. |
| Existing tree, shrub, flower and grass builders | `app/scenery/vegetation.gd`, `flowers.gd`, `mesh_kit.gd`, `palette.gd`, `app/render/near_grass.gd` and grass shaders. Reuse cell batching, MultiMesh, deterministic placement, themed colours, terrain clearance and simulation-clock wind. |
| Resource research and source pipelines | [Tree resource review](../research/tree-resource-review-2026-10-06/README.md), [LU resource review](../research/landscape-upgrade/LU-00/resources.md), [trees](../../tools/trees/README.md), [grass](../../tools/grass/README.md). Record a fresh selection review beside this pass's evidence. |
| Original botanical geometry | Author tapered curved blades, broad leaves, seed-head stems, differentiated flower heads and crop rows in repository source. No added runtime dependency or texture-license ambiguity. |

The primary [MegaKit page](https://quaternius.com/packs/stylizednaturemegakit.html) describes trees, plants, flowers, grass and bushes; the **exact downloaded Standard archive's license**, rather than a general marketing label, remains the adoption authority. [Godot MultiMesh guidance](https://docs.godotengine.org/en/stable/tutorials/performance/using_multimesh.html) supports instancing but explains whole-batch visibility: group plants into bounded spatial cells.

## Ownership and sequence

Lead owns this plan, habitat placement/source, herb/flower/crop meshes and shader, the narrow `scenery.gd` hook, capture views, regression integration, resource credits and final native evidence. One Luna Max helper may own only `app/scenery/vegetation.gd` and a new private tree/shrub helper, drafting outside `app/` first. Resource review is read-only. Preserve unrelated helicopter and LEARNINGS edits observed at start. Do not alter aircraft, UI, flight physics or numerical baselines.

| Step | Work | Acceptance evidence / status |
| --- | --- | --- |
| LU-22 | Audit available sources and current composition; freeze plan and baseline | Plan written first; exact resource/license selection; matched native club, meadow, close vegetation, farm and pilot views. Pending |
| LU-23 | Improve existing trees and shrubs: irregular crowns, branches, leaf structure, species/age colours and several silhouettes | Existing collision-envelope/wind bounds; no new solid obstacle without matching collision authority; attractive native near/medium views. Pending |
| LU-24 | Introduce recognizable low botanical families | Fine meadow grass, broadleaf herbs/clover, seed-head grass, daisies, buttercups, pink/violet spikes, cornflowers and sparse poppies; shared meshes/material and bounded wind. Pending |
| LU-25 | Compose habitat bands and crop plots | Clear mown edges; clustered meadow and shrub underplanting; green crop rows and golden grain by the existing farm; variation by habitat, deterministic geometry and clearance checks. Pending |
| LU-26 | Integrate themes, quality tiers and rendering | No scattered per-plant nodes; low/balanced/high use stable subsets; off/default-field guards; daylight/dusk/night and motion/pause/reset checks. Pending |
| LU-27 | Review native images and performance, record sources and limits | Matching 1080p captures, frame median/p95/p99 and draw/triangle counts; relevant app tests; final evidence in `docs/research/landscape-upgrade/LU-22/`. Pending |

## Implementation and budgets

Prefer one shared botanical material and cell/species MultiMeshes. Leaves are tapered or cupped geometry, flowers have species-specific head shapes, and ground transitions remain irregular. Use `sim_clock` and `wind_vec`, never wall-clock `TIME`, for small rooted motion. Shader displacement and instance bounds must agree. Keep additions non-solid only when they are soft ground cover; retain existing solid trunk/branch and flexible crown response for trees. Crop ground colour and plant rows are visual overlays, not changes to wheel friction or terrain.

Retain the existing **600k scenery triangles**, **300 visible draws**, **1M rendered primitives** and **16.67 ms native frame p95** limits at 1920×1080. Target added p95 at most 1.5 ms and at most 24 visible vegetation draws. Work within the current roughly 60k-triangle scenery headroom before increasing density. Quality tiers must reduce detail without relocating surviving plants. Capture timing runs sequentially on the same GPU; report host limitations honestly. The existing Linux atmosphere-trim discrepancy, collision-query cost and independent pilot/low-end-hardware gates remain owned by their current reports.

## Definition of done

The production landscape contains visible variation in trees, shrubs, grasses, herbs, flowers and cultivated vegetation; close planting has recognizable shapes and believable scale; broad views remain composed and flight-readable. Native images, deterministic exclusions, themes, quality, pause/reset and performance evidence pass the bounded targets. Every adopted external source retains its exact license and generator provenance. Update step status from measured results, and retain pending work explicitly if an asset or hardware gate cannot be satisfied.
