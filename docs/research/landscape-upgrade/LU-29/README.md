# LU-29 — Regional dusk and night lighting

2026-10-20. Native Godot 4.7.2 Compatibility implementation for the default Club
field. Rendering only; this work does not change the simulation or establish
photometric or aviation compliance.

## Research and implementation

The [FAA obstruction-lighting guidance](https://www.faa.gov/air_traffic/publications/atpubs/aim_html/chap2_section_2.html)
and [AC 70/7460-1N](https://www.faa.gov/documentLibrary/media/Advisory_Circular/2026-07-13_AC_70_7460-1N_Obstruction_Marking_and_Lighting_FINAL_CLEAN.pdf)
inform red nighttime obstruction markers, high nacelle placement and synchronized
flashes. The four existing turbines receive a common 2 s cycle driven by
`sim_clock`. Two communications antennas receive top flashes and dimmer steady
intermediate markers. These are artistic site layouts, not certified installations.

The [DarkSky/IES principles](https://darksky.org/resources/guides-and-how-tos/lighting-principles/)
inform sparse, warm, downward-facing fittings with dusk control. The
[Signify CityVario](https://www.signify.com/global/prof/outdoor-luminaires/urban/signify-cityvario/LP_CF_BDS300_EU/family)
and [Area Star](https://www.signify.com/global/prof/outdoor-luminaires/sports-and-area-floodlighting/area-and-recreational-floodlighting/philips-area-star/LP_CF_BVP252_EU/family/page/4)
product families provide examples of real street/area lighting and downloadable
photometry. No IES file is simulated here: color, screen intensity, spacing and
ground footprints are appearance estimates.

Twelve reused village houses form three small hillside clusters. Their generated
placements refer to the current SRTM-derived **visual** mountain mesh and its
source hash. Warm rooms use stable seeded occupancy, not random flickering.
Exact geometry samples the ridge's actual triangles rather than bilinear heights.
Buildings remain vertical. Two-tier foundations cover the local slope; the
maximum terrain variation under a house is 0.714 m and the maximum foundation
height is 0.814 m. The houses and foundations total 2,376 triangles.

The installed lattice mast is [Radio tower by Poly by Google](https://poly.pizza/m/d1zYJG7rJGY),
CC BY 3.0, uniformly scaled to 65 m. The original GLB and embedded texture are
unchanged. [Runtime attribution](../../../../app/assets/landscape/regional-lighting/LICENSES.md)
and [source provenance](../../../../assets/landscape/regional-lighting/RADIO_TOWER_PROVENANCE.json)
retain its exact identity. A Quaternius roof-style TV antenna was downloaded and
rejected after native review: enlarging it produced implausibly large panels.
Its source/license record remains outside the runtime application.

Beyond turbines, antennas and hillside houses, the following additional details
are installed:

| Detail | Purpose |
| --- | --- |
| Existing village-house windows | A few inhabited rooms among dark houses |
| Shielded house porch fittings | Small warm sources at facades |
| Upper farmhouse rooms | A second floor with independently dimmed glazing |
| Barn loading lamps | Downward light at the large working door |
| Silo access lamps | A low service point by the ladder |
| Paired farm-gate bollards | Mark the existing openings without blocking them |
| Rural junction lamps | Identify selected farm/highway connections |
| Village street-end lamps | Small pools at the settlement's two ends |
| Church nave windows | Restrained warm glazing on the actual side windows |
| Church entrance fitting | A low source above the front entrance |
| Club shed work lamp | A fitting above the existing door |
| Turbine/antenna base service lamps | Small maintenance-area cues below the red beacons |

Full-size airport approach/PAPI/taxiway systems and rail signals were researched
but not added: the current scene has neither that airport infrastructure nor a
rail crossing. Power pylons are not mislabeled as communications antennas.

## Cost and integration

`regional_lighting.gd` batches optics in 600 m cells, sharing three materials.
[Godot MultiMesh guidance](https://docs.godotengine.org/en/stable/classes/class_multimesh.html)
motivates spatial grouping so distant instances do not force the whole region to
render. Hardware is merged by cell. The nearby shed uses the retained Innerscene
CC0 lamp head; distant heads use a ten-triangle envelope derived from that
asset's measured bounds. This keeps fixture geometry at 3,418 triangles instead
of 119,338. There are **zero new dynamic Light3D nodes**,
shadow maps or per-object frame callbacks.

The existing airfield dusk controller updates the three shared materials.
Optics are hidden during daylight. The club's light switch does not turn off
regional obstruction lights or homes. Explicit scenery layouts and other fields
do not inherit these default-region additions.

Windows retain real facade orientation and depth testing; distant optical cores
retain terrain/building depth testing. The pixel-size floor is a readability
approximation. Ground pools are bounded additive footprint meshes on the flat
plain, not deferred lights or global illumination; no flat pool is placed on a
mountain slope. Houses and antenna landmarks are visual-only, like the existing
mountain mesh, and do not add collision terrain.

## Reproduction and evidence

Generate hillside placements with `python tools/scenery/bake_hill_settlements.py`.
Import the project before running standalone native tests/captures.
`test_regional_lighting.gd` checks installation counts, bounded batches, dusk
behavior and the independence of regional lighting from the club switch.

Native captures use `capture_landscape_upgrade.gd`, `--time_of_day=night` or
`--time-of-day=18:15`, and `--botanical_clock=0.25` for the on phase.
`--botanical_clock=1.0` samples the off phase.
`--regional_lighting=off` hides only the new region for matched timing captures;
the canonical lake, vegetation, scenery and camera remain identical.

Accepted [night](night/), [dusk](dusk/), [noon](noon/) and [flash-off](flash-off/)
captures retain their native reports. The [pixel check](flash-check.json) finds
all four turbine flashes: peak red values fall from 93–219 in the on phase to
11–32 in the off phase. The visible antenna top falls from 201 to 0.
Rotor geometry and view-dependent occlusion can partially hide a beacon.

The installed addition contains **157 optical instances in 39 spatial/material
batches** and **9,492 triangles** including optics, two towers, houses and
fixtures. Not all batches are visible from each camera.

Three alternating matched pairs, 60 warm-up plus 360 measured frames per view,
RTX 3090 / Compatibility / 1280×720 / 4×MSAA:

| Night view | Median p95, hidden → visible | Draws, hidden → visible |
| --- | --- | --- |
| Pilot north | 1.717 → 2.039 ms | 97 → 119 |
| Farm | 1.436 → 1.551 ms | 40 → 71 |
| Turbines | 1.211 → 1.237 ms | 12 → 21 |
| Raised north horizon | 1.226 → 1.553 ms | 51 → 72 |

[Measurements](performance.json) and [raw per-frame reports](bench/) retain
the spread between runs. These are wall-clock frame intervals, not isolated GPU
timings; they do not qualify a slower GPU. Matching checks retain identical
canonical lake identity/geometry and existing plant/population counts.

Checked results:

- Regional lighting: 182 headless checks; 251 native checks, including custom
  instance buffers that the dummy headless renderer does not retain.
- Existing airfield lighting: 54 checks; marker optics: 33 checks.
- Landscape scenery eligibility: 7 checks; landscape/Home/flight switching:
  49 checks.
- Hillside helper: 57 checks; generator `--check` matches retained JSON.
- Native import, shader compilation and the accepted captures pass the checked
  runner. The pre-existing unsupported-maple-wind warning remains.

Logs/verdicts are retained under [checks](checks/); [source identities](source-identity.json)
record the implementation used for capture. These focused checks do not replace
the complete physics/export suite.
