# RC ground close-view improvement

2026-10-15. Owner: landscape **L9d**, coordinated with RCV presentation, L11 and VQ. Status: audit and plan complete; material implementation pending.

The RC chase/orbit cameras expose ground detail that pilot-distance landscape checks do not cover. Improve compacted dirt first, then grass transitions and near vegetation. Use existing or freely downloadable assets. The [dated audit, native captures and sources](../research/rc-ground-closeup-2026-10-15/README.md) establish the problem; this document owns the implementation sequence.

## Scope and boundaries

Own the new surface asset intake/conversion under `assets/landscape/`, runtime derivatives under `app/assets/landscape/`, and landscape shader integration. Coordinate `app/vehicles/ground/airfield_track_view.gd` with RCV; shared `ground.gd`, ground shader/includes and near-grass placement with L/VQ. Keep source generators authoritative. Do not hand-edit the generated turf PNG.

Keep Compatibility, shared field masks, world-space metres, current track vertices/normals/contact sampler and the 2 mm overlay separation. Preserve runway stripes and flight readability. Large stones, ruts or displaced geometry require a separate physical-terrain proposal. Material normals are cosmetic. Do not change tire grip, surface identity, simulation stepping or camera behavior to make the comparison look better.

The existing L9e-R1 Laplacian experiment remains a separate comparison. First qualify the RC-local dirt candidate; shared grass adoption still requires VQ visibility and combined frame-cost evidence. This plan does not close the global performance or pilot gates.

## Deliveries

| ID | Work | Proof / status |
| --- | --- | --- |
| L9d-01 | Audit actual shaders, imports, placement, current close views and free source options. | Complete: two native static captures, source hashes and primary references in the audit. Motion, low orbit and full target-hardware baseline remain prerequisites for adoption. |
| L9d-02 | Download one dirt and one short-grass candidate, retaining source URL, author, license, exact bytes/hash, map semantics and declared tile dimensions. Produce reproducible 2K/4K variants. | Pending. Compare Dirt against Sandy Gravel 02 only if visible footprints or stones make Dirt unsuitable at RC scale. No custom texture painting or generated replacement of available assets. |
| L9d-03 | Integrate one opaque RC-local dirt material with world-space scale, albedo, normal and roughness. Preserve mesh/contact and existing markings. | Pending. Paired chase/low-orbit/bank captures, motion clips, exact mesh and state comparisons, native shader validation, time/memory report. This is the first independently reviewable implementation. |
| L9d-04 | Match the shoulder to the actual shared turf, then compare downloaded grass detail near the car. | Pending. Both sides of the boundary converge in color, normal and lighting; no rectangular seam or double shading. Preserve mown/runway masks, stripes, distant color and aircraft visibility. |
| L9d-05 | Extend nearby grass coverage for the RC camera only if texture improvement leaves a demonstrated silhouette deficit. Reuse accepted vegetation or a suitable free asset. | Pending with L11 owner. Deterministic bounded chunks, terrain-sampled roots, course/runway/water exclusions, hysteresis and visibility fade; no new physics objects or per-frame full-field rebuilding. |
| L9d-06 | Qualify combined appearance, movement, lifecycle, memory and packaged assets for both RC vehicles and shared flight/Home. | Pending. Publish accepted A/B result or retain baseline; consolidate this plan into the landscape guide after completion. |

## Material implementation decisions

Start with a **2K runtime candidate plus matched 4K comparison**, not an unconditional resolution increase. A 2 m tile at 2048 pixels provides 1024 texels/m (about 0.98 mm/texel); 4K halves that spacing. Preserve the supplier's physical tile dimensions. Inspect stone/blade sizes against the actual tires, especially on banks. Resolution does not fix an oversized noise pattern or a boundary mismatch.

Use diffuse/albedo as sRGB (`source_color`); normal and roughness are linear data. Prefer the supplied OpenGL normal. Use mipmaps, repeat and anisotropic sampling; compare 8x/16x only after recording the effective current level. Retain explicit gradients across anti-tiling offsets and projected-footprint filtering. Do not rotate normal-map UVs without rotating the corresponding normal vectors. Reuse low-frequency world variation; cap texture reads before adding further material layers.

The track mesh currently has no UV or tangent arrays. Implement a coherent world-projected tangent frame on flat and banked surfaces, or add validated UV/tangents without changing positions/indices. Do not assign a tangent-space normal directly to view-space `NORMAL`. Combine fine normals with the accepted geometric normal; test positive/negative banks under opposite light directions. Triplanar mapping is conditional on demonstrated slope stretching, not the default for the entire field.

Preserve vertex alpha as **coverage metadata**, not opacity. It currently means `1 - coverage`, with an additional gravel-shader remap. Blend opaque material properties from that contract. A color lerp to `worn_grass` is insufficient: at the outside shoulder the material must approach the same turf function, world scale, normal and lighting as the ground underneath. Avoid adding alpha-blended ground sheets. Share small existing surface functions where needed rather than copy the entire ground shader.

The grass shader uses custom diffuse lighting and zero specular. Downloading roughness alone will not introduce the expected specular response; any lighting-model change needs a separate paired result. Preserve custom haze/cloud behavior when introducing a shared boundary. Start with normal/albedo detail and conservative dry-soil roughness. Keep wet-margin work conditional on a separate shoreline audit; do not infer new wet physics from a dark material.

Initial planning envelopes, **not measured results**: up to three maps per material; no new full-field pass for L9d-03; incremental resident textures at most 64 MiB for the initial dirt/grass pair. For reference, three 2K RGBA8 maps with full mips occupy about 64 MiB before GPU compression; the 4K equivalent is about 256 MiB. Actual compressed formats and all resident variants must be measured. Do not equate PNG/JPG size or the existing 5.33 MiB turf allocation with GPU-compressed residency.

## Acceptance matrix

Use actual scene captures at 1280x720 and 1920x1080: runway start, access boundary, dirt straight, bank, roller/ramp, rough grass and lake margin. Include Bisonte and MONSTER CAR 2. Freeze light/sky, camera transform/FOV, viewport, state, inputs and source hashes; compare chase (currently 2 m distance / 0.8 m height) and minimum supported low orbit. Audit deliberate 0.15/0.35/0.8 m observer heights as supplemental views, clearly labelled when not ordinary gameplay cameras.

Record stopped, straight motion, steering and banking; daylight, low sun and headlights. Inspect actual pixels and slow clips for texture crawling, seams, normal inversion, scale, repeating landmarks, fade/pop, grazing blur and vehicle readability. Static screenshots cannot pass temporal acceptance. Keep existing distant pilot/overview/Home views in the regression set.

For material-only work, retain one accepted control tape and compare exact state arrays, model/course/solver identities, ticks, contact flags and road samples. Use the existing RCV capture/recording facilities; adopt the [flight logging evidence discipline](../FLIGHT-LOGGING.md) without assuming the fixed-wing `.orfl` CLI supports this RC activity. Do not re-record physics goldens for shading changes.

Measure isolated native baseline/candidate runs on the same target GPU, after warmup, in alternating order (at least five pairs): whole-frame median/P95/P99, GPU timing where supported, draw calls, resident texture memory and cold/warm scene-load times. Proposed rejection threshold: median or P95 frame-time regression greater than 5% or 1 ms, whichever limit is tighter, unless observed noise requires a longer measurement. Record the noise and failures; do not call a render-only measurement a full-session budget pass. Check lower-end hardware separately; RTX 3090 success cannot establish that gate.

After implementation, run the repository parse/check workflow and focused track-view, track-contact, ground/turf, near-grass, field and activity tests appropriate to edited paths. Validate renderer logs in addition to process exit status. Verify imports and bundled license/source records from a fresh clone and packaged build. Require a before/after visual review before adoption; build success is not visual acceptance.
