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
render. Hardware is merged by cell. There are **zero new dynamic Light3D nodes**,
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
