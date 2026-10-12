# LU08 — Apron wear and RC service details

Status: implemented, geometry-validated and reviewed in native final captures, 2026-10-12. [Final parking view](day/car_park.png), [club](day/postcard_club.png), [service detail](day/pit_service.png).

## Change

The existing gravel apron now uses a deterministic 1.1 m grid clipped to the polygon, with sparse 0.36 m aggregate cells. This removes the long, thin fan triangles and their streaks. A 0.9 m shoulder keeps its original 0.16 m outline wobble; vertex colours ramp from the apron material to the field-grass tone so the edge can blend into the existing ground. All vertices stay on the established 0.02 m worn and 0.04 m gravel layers. No texture, material, scene node, collision shape, cell, draw or placement was added.

Two of the six existing tables in each shelter now carry small RC service props: a charger with a battery pack, screen, indicators and leads, and a handled fuel can with a filler cap. They are static geometry inside the existing shelter batch. Both prefab placements and the pit layout remain unchanged.

The apron fill is original procedural project geometry using the existing `MeshKit` and `Palette` code. The service props are original geometry made from the existing mesh-kit primitives and palette. No external assets or dependencies were used.

## Bounds and cost

An isolated comparison against the pre-edit source produced 2,899 apron triangles versus 21 before, a net increase of 2,878 (within LU08's 4,000 ground-triangle limit). The apron has 400 distinct packed vertex colours, a longest triangle edge of 1.843 m and 793 sub-0.7 m triangles. It stays inside the tested 1.1 m shoulder envelope. Each pit shelter grew from 1,734 to 1,902 triangles, a 168-triangle increase; two placements add 336 triangles total. The shelter still measures 28.85 × 3.48 × 5.91 m against its 29.0 × 3.45 × 5.8 m catalog envelope.

The latest integrated scenery build reports 158,387 triangles and 48 cells. It retains the existing one-surface-per-cell batching and emits no additional motion parts. The full scene remains below the 250,000-triangle scenery limit.

## Validation

- `app/tests/test_scenery_ground_lu08.gd`: passed; checks deterministic apron geometry, triangle budget, ground lifts, color variation, shoulder bounds, service-prop bounds and static shelter geometry.
- `app/tests/test_scenery_build.gd`: passed; verifies catalog bounds, determinism, winding, batching, moving-part counts and total scenery budget.
- Isolated pre/post geometry check: passed; track and contact-shadow vertex, normal and colour arrays were byte-identical; the shoulder's outer vertices resolve back to the field-grass color.
- The lead inspected the final native 1920 × 1080 parking, club and service-detail images. Long stripes are gone; the shoulder is irregular and softer, though its untextured material remains distinguishable from the textured field grass. Matching views add no draws. [Measured performance and remaining limits](README.md).
