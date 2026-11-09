# Supplied ground-realism audit — 2026-11-09

User-provided external research and art direction. Its recommendations are proposals, not native capture or performance evidence. Original attachment SHA-256: d5dbd8e60f8f13defb1978601d46190440b21dcc83490ae3708f0688d32a8b8a. The original audit cites an older repository state; the L9b-R1 evidence in this folder records the implementation actually reviewed.

---

The next visual upgrade should focus on the ground around the runway
I completed a focused follow-up covering 24 investigations and 27 external references, including real RC flying fields, turf research, game-development presentations, and forum discussions.

My recommendation is to make the Club field feel like one attractive, maintained place with a history of use: related shades of green, finer turf detail, restrained wear, believable access paths, uneven growth at fences, and a convincing transition into the RC track.

The complete 20-page illustrated brief includes real photographs, the generated concept board, current repository findings, implementation priorities, and acceptance criteria.

OpenRC_Ground_Realism_Runway_200m_2026-11-09.pdf

I audited source at commit f47d1dc6cccb141936407d0217eafdc465558190. The concept is an art-direction target; it is not an implemented engine result. This pass did not change simulator code or produce a new native 1080p capture.
1. The most important finding: OpenRC already has much of the necessary groundwork
The current Club field already uses photographic grass detail. The field setup enables it, and the shader uses that texture to modulate the underlying field palette. Imported grass plants follow a separate material path.

That changes the recommendation: the first work should examine base color, photographic detail, mowing brightness, and plant color separately, then bring them into agreement. Simply enabling another grass texture would not address that relationship. See the pinned Club ground setup and ground shader.

Several other features also exist already:
Area	What is already present	What I would improve
Runway	Directional mowing, subtle touchdown wear, and a mown-to-rough boundary	Their visual strength, continuity, and relationship to surrounding grass
Nearby vegetation	Separate imported grass, fallback blades, and runway-meadow systems	Ground agreement, silhouettes, grouping, and placement
Fence line	Bounded grass/clover planting around flightline posts	Variation between posts, openings, and less-used sections
RC circuit	A terrain-sampled track mesh, dirt coverage, surface detail, and vegetation exclusions	The appearance of the outer grass-to-soil transition
Paths	Authored pedestrian tracks, vehicle tracks, and gravel shoulders	Connections to destinations, edge color, and overly regular bands
Countryside	Cultivated parcels with crop rows and tramlines	Crop-to-soil contact, headlands, access, and field boundaries


These findings come from the current runway meadow, flightline planting, RC field integration, ground features, and countryside implementation record.

My main diagnosis is therefore an integration problem to investigate: different surface and vegetation systems can each contain useful detail while still producing an artificial-looking whole.

The specific “C” shapes remain unresolved. I have not identified their generating layer in a current native image, so I would not label them a confirmed noise, texture, or placement bug yet.
2. What the real photographs suggest
The strongest references were actual flying clubs and RC tracks. They show how maintained turf, human activity, and surrounding vegetation coexist.
A maintained runway can remain convincingly green
RC Wingers describes a regularly mown grass runway surrounded by hay. Triad and Dare County also document maintained grass flying areas. These are useful references for preserving a cared-for club atmosphere. rcwingers.com

The Brackenheim aerial photograph is particularly useful because the runway, pilot area, access road, and neighboring agricultural rows all have distinct visual structure within one landscape. mfvb.de
The strongest wear belongs around activity
The Stoney Creek photograph shows a clear relationship between parking, shelters, benches, fencing, and the access route. That is the kind of spatial logic I would carry into OpenRC. The photograph alone does not establish the cause of every pale patch. Home

Turf research also distinguishes damage to the plants from longer-term soil compaction. Several stresses can produce similar appearances, which is why the art should suggest plausible use without assigning a complicated explanation to every color change. umass.edu
RC track edges need their own treatment
The Arnprior track photograph shows exposed soil, sparse edge plants, and more established vegetation occupying different parts of the scene. It is a strong visual reference for an irregular transition with a clearly usable driving surface. Arnprior Radio Control Club

The direction I take from these references is a predominantly green field, with variation concentrated where mowing, traffic, boundaries, and cultivation give it meaning.
3. The changes I would prioritize visually
A. Give the grass a coherent family of greens
I would establish a restrained palette with several related roles:
- A dominant natural green for maintained turf.
- Slightly lighter or more olive variation within mown areas.
- Deeper greens in selected rougher pockets.
- Small amounts of pale or dry blades.
- Soil color where grass coverage actually becomes thin.
The important relationship is between those roles. A patch of turf, a nearby tuft, and the grass at a fence should look as though they belong to the same place and lighting.

I would review the base ground, photo modulation, runway brightness, imported grass, and meadow independently under a fixed camera and sun. The existing material separation makes that a more useful first experiment than a broad scene-wide color adjustment. The inspected ground path also has no general grass specular lobe, so the initial investigation should concentrate on color, scale, filtering, and plant integration. Current material implementation.
B. Find the repeated shapes before adding more variation
The current base system combines a repeating tile, translated samples, and several scales of procedural variation. That means a recognizable shape could come from a source texture, a blend, a broad procedural component, or their interaction. The distant parcel function begins well outside the first 200 m, so it should not automatically be blamed for a nearby mark. Grass surface implementation.

I would use one exact view containing the reported “C” and compare:
1. The normal material.
2. Reduced or neutralized broad color variation.
3. The existing detiling contribution changed in isolation.
4. Near photographic detail changed in isolation.
5. Relevant vegetation layers hidden.
The result should identify which component owns the shape. Only then would I alter that component’s contrast, source material, or spatial pattern.

This matters because extra noise can leave the original repetition visible while making the rest of the field busier.
C. Make close grass look fine-grained
The near surface should communicate a mixture of small blades, gaps, and occasional dry material. I would judge the texture’s apparent scale against known objects: runway width, benches, fence posts, and the RC vehicles.

At a low camera position, the surface can show individual detail. From the pilot position, that detail should combine into believable turf. Farther away, mowing and coverage should carry the image.

I would also avoid making every visible plant a conspicuous decorative tuft. The grass immediately outside a maintained strip needs a progression of heights and coverage, with taller clumps reserved for suitable locations.

The current photographic and procedural detail paths already have distance and footprint filtering, so this is a calibration task within an existing system. Turf detail and near material sampling.
D. Make mowing bands quieter and more responsive to the view
Real mowing stripes depend partly on leaf orientation, reflected light, and the observer’s position. Their apparent brightness is therefore more complex than alternating paint colors. Turfgrass Science

OpenRC already includes directional behavior. I would tune it using matched views from both ends of the runway and under different sun angles.

The target is:
- A runway that remains easy to recognize.
- Modest tonal differences within the same grass family.
- Plausible changes as the camera moves.
- No dominant fluorescent bands or overly crisp rectangular pattern.
This should retain the pleasing order of a mown flying field.
E. Add the restrained central wear you described by refining the existing wear
The shader already contains touchdown-related wear. I would start there and compare a slightly more natural treatment:
- Interrupted thinning through plausible used areas.
- Small amounts of fine soil showing between blades.
- Less uniform coverage within individual worn patches.
- Green turf continuing between those patches.
For the runway’s middle, I would test a subtle used strip that becomes clearer at close range. It should remain visually subordinate to the grass runway as a whole.

The wear should also be appropriate to the activity. Foot traffic around a gate, RC vehicle use on a circuit, and aircraft use on a flying strip should have distinct appearances.
F. Give the runway edge a gradual transition in height, coverage, and color
The shoulder is one of the highest-value places to improve because it is visible from the pilot and from low views.

I would coordinate four elements:
Element	Intended appearance
Mown turf	Short, relatively continuous grass
Outer shoulder	Small variations in coverage and tone
Fringe	Unequal small plants and slightly greater height
Rougher grass beyond	More varied groups, with open gaps


The transition should remain recognizable as a maintained mowing boundary. Its small irregularities should not form repeated scallops, identical crescents, or an uninterrupted dark outline.

OpenRC’s meadow already defines a mown lip and fringe, so the first step is to inspect that system together with the ground material. Existing meadow implementation.
G. Integrate the RC track through both material and vegetation
For the RC circuit, I would aim for this progression:

Used dirt surface → irregular mixed fringe → established grass.

The mixed fringe is where several changes need to agree:
- Soil coverage.
- Grass density.
- Surface color.
- Small-scale normal detail.
- Plant height and contact with the ground.
A soft color blend alone can still look artificial if the grass stops abruptly elsewhere. Equally, adding clumps will not fix a mismatched soil boundary.

The existing circuit uses a separate surface sampled from track and terrain data. Vegetation clearances must continue to follow that authority. The right experiment is to inspect straight sections, bends, and access transitions before changing the outer verge—not to relax every exclusion globally. Track integration and track mesh.
H. Make paths and marks connect actual destinations
I would trace a person’s plausible route through the existing Club layout:

Parking and access → shelters or benches → gate → pilot or runway area.

Then I would check that the authored paths actually connect those destinations.

Useful details include localized thinning where people stand, a more used gate opening, and modest variation around bench feet. Vehicle marks should follow the course or access route and have an appropriate scale.

This is also a good place to inspect the current path edges: some authored ground features use a fixed approximation of the field color, which could require adjustment if a mismatch is reproduced under the active lighting. Authored ground features.
I. Make fence growth uneven and believable
The flightline already has grass/clover planting around posts. I would vary that treatment selectively:
- A few posts with denser growth.
- Some relatively clear stretches.
- Shorter or thinner turf at regularly used openings.
- Occasional small soil exposure.
- Different group shapes and orientations.
Fence-line vegetation can vary with maintenance, so every fence segment does not need the same continuous tall border. blog-crop-news.extension.umn.edu

The result should preserve the openings and sightlines while making the fence feel established in the ground.
J. Improve roots, leaves, and small contact details
I would pay particular attention to the bottom of each grass clump. If the roots are visibly a different color from the ground, the plant can look placed on top of the terrain.

For a demonstrated mismatch, I would test a modest contribution from local ground color near the roots, fading toward the tips. Species and tip variation should remain visible.

This has a useful precedent in the REDengine 3 development presentation, which describes a terrain pigment map with a bottom-up influence on grass. It is inspiration for a bounded experiment in OpenRC. media.gdcvault.com

A few small leaves or dry blades could help near selected posts, benches, or tree edges. Their scale, contact, and distribution matter more than their quantity. I would keep these details quiet from the pilot’s normal view.
K. Use small shrubs and flowers as localized accents
A small shrub can add character at an outer fence corner, a less-maintained boundary, or a suitable transition toward the wider landscape.

I would place these accents deliberately and vary the surrounding grass with them. A shrub should look rooted in a small habitat pocket, with appropriate ground cover and space around it.

Near the runway, the composition should stay open. Small clover or flower accents can contribute to richness without producing a repeated scatter of bright dots.
L. Refine crops after the immediate Club ground works
Crops remain part of the plan, but the current source already includes substantial countryside work outside the central flying area.

The useful questions are now:
- Do the visible plants meet the intended cultivated soil?
- Do rows relate sensibly to parcel shape?
- Are field entrances and turning areas plausible?
- Do borders look managed?
- Does each parcel have a coherent plant state?
USDA material describes field borders as functional perennial vegetation that can support machinery movement and habitat. Those functions are useful design references; their regional dimensions and species prescriptions should not be copied automatically into OpenRC. nrcs.usda.gov
4. What other games and developers contribute
The useful lesson across these sources is to coordinate systems around a common landscape intent.
Source	Relevant lesson	Application to OpenRC
REDengine 3 / CD Projekt RED	Terrain color can influence grass from the roots upward	Test local root agreement where imported plants visibly separate from the ground
Call of Duty terrain rendering	Hiding repetition can require additional texture samples and different treatment at distance	Diagnose the current repetition first; measure the cost of any retained sampling change
Delta Force terrain and biome technology	Shared spatial information can coordinate terrain and vegetation; blending may need different behavior at distance	Reuse common field intent across grass, soil, and plants
GIANTS Editor	Field definitions, terrain, and foliage need to align	Treat cultivated parcels as coherent agricultural units
Riders Republic	Routes are designed in relation to terrain and intended use	Connect OpenRC’s paths and wear to the actual site layout


These are source-specific techniques and workflows. They do not establish OpenRC’s implementation cost or justify adopting another engine’s terrain system. media.gdcvault.com

The Polycount and Epic discussions were useful for recurring practical problems: mismatched ground colors, oversized clumps, obvious texture repetition, and grass transitions around roads. I treated these as artist observations that suggest experiments. polycount

One technical qualification matters: height-aware blending can help certain material joins, but it needs suitable height information. The official O3DE tutorial illustrates that approach; OpenRC’s retained grass/dirt set does not by itself establish a validated height map. Open 3D Engine
5. The 24 investigations completed in this focused pass
Each investigation in the report includes the current evidence, a recommended experiment, and an acceptance condition.
Group	Investigations
Color, pattern, and scale	1. Coherent green family; 2. reported C-shaped patterns; 3. detail scale
Mowing and runway wear	4. mowing response to light; 5. restrained central wear; 6. runway shoulder
Textures and plants	7. photographic detail strength; 8. map alignment and blending; 9. root-to-ground agreement
RC track and access	10. RC verge; 11. appropriate surface marks; 12. connected paths
Fence and nearby nature	13. fence and gate growth; 14. meadow grouping; 15. small contact details
Agriculture	16. current crop/soil integration; 17. headlands and row direction; 18. field borders
Distance and motion	19. the 200 m priority area; 20. filtering and temporal stability; 21. wind and plant identity
Delivery and validation	22. actual renderer behavior; 23. data reuse and budget; 24. realism and flight usability


6. How I would organize the implementation
First delivery: one connected, convincing part of the Club
I would use the pilot area, gate/fence, runway shoulder, and an RC track shoulder as the first review area.
Stage	Work	Required outcome
1. Establish the current reference	Capture matched native views; locate the C pattern; separate material and vegetation contributions	Each visible issue has a supported owner
2. Tune the field appearance	Adjust the responsible color/detail controls, mowing contrast, and existing wear	A convincing normal pilot view and reverse view
3. Integrate the edges	Refine RC verge, path connections, gate/post variation, and plant contact	Ground, plants, and routes agree from pilot and low-camera views
4. Validate and extend	Check motion, renderers, and performance; then refine farm details	An accepted first area before expanding coverage or species


I would keep this within the existing ground, grass, scenery, and RC code paths. The report maps the responsibilities to the exact repository files.
Treat 200 m as an art priority
For planning, these are useful viewing bands:
Approximate range	Detail that deserves attention
0–25 m	Fine turf, plant roots, small soil exposure, fence/gate contact
25–80 m	Coverage, clump grouping, mowing, paths, and surface transitions
80–200 m	Broad field structure, coherent color, rough/mown organization, and landscape composition


These are review bands, not proposed hard draw-distance rings. Camera height, field of view, zoom, and driving views can change which detail matters.

The existing near-grass patch is pilot-relative, while the meadow and RC views have different requirements. That distinction must remain visible in implementation planning. Near-grass source.
Define success through native images and motion
The first comparison should establish that:
- The field stays pleasantly green.
- Repeated shapes stop attracting attention.
- The runway remains easy to recognize.
- Wear looks localized and purposeful.
- Plants meet the ground naturally.
- Grass and soil transition convincingly around the RC circuit.
- Slow pans, zoom, and low driving views remain stable.
- Aircraft visibility and usable track space remain clear.
The current project uses multiple renderer paths, so the actual build, renderer, reconstruction setting, and input resolution need to be recorded with comparisons. The repository’s current stack and renderer decisions are the controlling references.

Performance qualification should retain the existing project gates, including the shared initial allowance of +0.5 ms at frame p95 for all new visual work, rather than allocating that amount independently to each grass improvement. No such timing result was measured in this audit. Global visual-performance plan.

The first milestone I would prioritize is a continuous, believable transition from the pilot’s turf to the fence and gate, across the runway shoulder, and into the RC track’s outer verge. That gives the project a concrete place to judge the qualities you asked for: finer grass, natural greens, modest wear, convincing soil contact, and an attractive landscape that feels used and maintained.