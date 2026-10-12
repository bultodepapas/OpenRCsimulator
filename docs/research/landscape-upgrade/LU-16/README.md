# LU-16–20 — Image-led landscape refinement

Status: **implemented and integrated, 2026-10-12**. [LU-15 critique](../LU-15/README.md) selected this work before changes. The owner's rejection of the old population expanded the pass into [LU-21](../LU-21/README.md), which holds the combined captures, budgets and validation.

| Step | Change and proof |
| --- | --- |
| LU-16 | Distant ridges now share the world's directional atmospheric haze. Fixed-camera no-rim/no-ridge controls identified missing warm scattering on ridge materials, rather than the ground rim, as the dark dusk band. Four chunks and 12,288 triangles retained; 37 integration checks pass. [Blue hour](../LU-21/evidence/final-blue-hour/pilot_north.png), [raised view](../LU-21/evidence/final-blue-hour/horizon_raised120.png) |
| LU-17 | Smaller staggered crown lobes, smooth normals and species habits; stem/leaf/petal flowers replace polygon mounds. Initial spherical cores were rejected during native review. Maximum 1,463 triangles across 192 tree theme/seed builds, within revised 1,500 gate and existing collision envelopes. [Club](../LU-21/evidence/final-after-day/postcard_club.png), [flowers](../LU-21/evidence/final-details/flower_border.png) |
| LU-18 | Narrower gravel shoulders, rounded access-track bends and worn walking connections; derivative-filtered distant grass octaves. Building/gravel exclusions reduce near grass from 4,794 to 4,488 clumps with no footprint centers inside covered surfaces. [Exclusion design/tests](grass-exclusion.md), [entry](../LU-21/evidence/final-details/entry_path.png) |
| LU-19 | Plaster basecourse, slab/timber variation, daytime glass response and slightly wider existing entry-light pools. No new lights or stronger night-energy cap. Car tint and primitive person pose tweaks were superseded by real LU-21 assets. [Night](../LU-21/evidence/final-after-night/postcard_pavilion.png) |
| LU-20 | Integrated native day/night/dusk, glare, distance LOD, movement, pause/reset, physical collision and performance review. [Combined acceptance](../LU-21/README.md) |

These changes are original project MIT work. Physical runway surfaces, atmospheric ephemeris, aircraft geometry and flight dynamics are unchanged by these rendering refinements. Support-height collision alignment is separately documented in LU-21. Flowers and near vegetation retain bounded simulation-clock movement. The new art remains stylized; cloud grouping, richer architecture and a wider species library are future visual work.
