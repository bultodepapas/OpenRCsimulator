# LU-09-R1 — Low runway-edge lights

2026-10-20, America/Bogota. This refinement concerns the default 100 × 12 m RC grass runway and its existing field-light fixtures. It changes presentation data and marker tint, not flight/contact geometry or lighting budgets.

## References and choice

- [Texas Wings RC night-flying notes](https://sites.google.com/site/txwingsrc/club-events/night-fly) say judging ground height on landing is the difficult part of night flight. Two continuous edge lines remain the main cue.
- The [FAA Airplane Flying Handbook, ch. 11](https://www.faa.gov/sites/faa.gov/files/regulations_policies/handbooks_manuals/aviation/airplane_handbook/12_afh_ch11.pdf) describes two parallel runway-edge lines. The [FAA AIM lighting section](https://www.faa.gov/air_traffic/publications/atpubs/aim_html/chap2_section_1.html) informs white edges and directional threshold/end colors. These are visual references, not RC-field standards.
- A [grass-strip lighting discussion](https://vansairforce.net/threads/runway-lighting-for-private-grass-strip.153349/) describes flush solar LEDs on turf-side paving; an [inset edge-light manufacturer](https://ocem.com/en/products/lire/) documents a low overhang. They support the low housing idea, not the chosen 0.12 m RC-scale dimension.
- [Godot 4.7 MultiMesh guidance](https://docs.godotengine.org/en/4.7/tutorials/performance/using_multimesh.html) supports retaining the existing two batched optical rows. [StandardMaterial3D emission guidance](https://docs.godotengine.org/en/4.7/tutorials/3d/standard_material_3d.html) notes that emission alone does not light surrounding geometry; the existing club floods still light the runway surface.

The existing freely sourced stake asset remains available in [night-lighting sources](../../../../assets/landscape/night-lighting/README.md). This small change reuses the already batched fixture hardware and optics instead of adding another model, texture, plugin, or dynamic light.

## Implementation

- The 12 edge markers move from north 9/21 m to 8.6/21.4 m, 0.4 m into the grass beyond both long edges. East positions retain the six 20 m stations per side.
- Edge and threshold marker heads drop from 0.35 to 0.12 m. The existing batched post geometry reads this same field datum; threshold positions stay at east ±51 m.
- Edge data changes from 3000 K warm white to 4000 K neutral white. The Club optical profile is now a warm neutral white; Airfield remains slightly cooler. The existing red/green directional threshold optics, dusk transition, screen-size compensation, depth occlusion and display cap remain.
- Daylight sets optical emission to zero while the low fixture hardware stays in the scene. The Off profile extinguishes the lamps but leaves hardware in place.
- The capture harness reads the threshold's current height from validated field-light data instead of measuring an obsolete hardcoded 0.35 m point.

These dimensions, intensity and optical sizes are art estimates. No runway survey, photometric measurement, physical landing test, or low-end GPU acceptance is claimed.

## Verification

Godot `4.7.2.stable.official.ed1daf0bf` passed `test_landscape_marker_optics.gd` (**34/0**), `test_landscape_lighting.gd` (**54/0**) and `test_world_field_lights.gd` (**86/0**) on the shared working tree. These cover placement and height, day/off gating, dusk/night transitions, binding identity, fixture counts and unchanged flood coverage. The pre-existing maple-tree wind-material warning appeared in the world check; none of these checks failed.

Native Compatibility captures at 1280 × 720 show the [day approach](day/runway_threshold.png), [day runway interior](day/runway_inside.png), [night approach](night/runway_threshold.png) and [night runway interior](night/runway_inside.png). The low housings are visible in grass by day without glowing; the night edge points remain legible from both views. The [day](day/report.json) and [night](night/report.json) reports retain engine, adapter and capture arguments. Each case used 60 warmup frames and four measured frames, enough for visual review but not timing qualification.

The controlled [marker capture](markers/report.json) holds the night sky/exposure fixed and varies only the lamp factor or an opaque blocker. [Pixel results](markers/marker-checks.json) pass **5/5** checks: clear core 18,371 encoded RGB sum, half 12,166, off 0, and blocker 1,156 with peak channel 4 versus clear peak 194. The blocker retains dark background pixels, so the guard checks that its peak stays ≤5 and its sum below 10% of the clear case. [Clear](markers/marker_clear.png), [half](markers/marker_half.png), [off](markers/marker_off.png), [blocker](markers/marker_occluded.png). This is encoded-image evidence, not measured radiance or physical night-flying validation.

[Source hashes](source-sha256.json) bind the data, renderer, shader and verification tools used. The capture host uses Mesa llvmpipe; frame times are diagnostic only. Independent pilot readability and target-GPU review remain open.
