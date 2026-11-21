# OPEN RC SIMULATOR — Trailer 2.0 preproduction

**Updated:** 21 November 2026. **Status:** R5 detailed shooting script and first capture-tool increment; proof footage remains pending.
**Branch:** docs/trailer-v2-preproduction-2026-11-21. **Track / owner:** V2 / trailer director-editor.
**Game-source baseline:** 57abea025f62b20233ca281d58d2acbee4ab8b8e. The exact promoted build remains a production decision.
**Previously requested filming host:** Windows PC with NVIDIA RTX 3090; 1080p60 first. No new target-host capture is qualified by this revision.

## Current screenplay and reading order

1. **[Director's shooting script R5](cinematic-script-r5.md)** is the current story and staging authority: **150 seconds / 62 cuts**, with exact cast, skin, preparation, first visible state, route targets, camera targets, action, exit and continuity.
2. **[Machine-readable R5 plan](shot-plan-r5.json)** owns the proposed numeric blocking and identities. It retains the R4 cut IDs. The [150-second storyboard](storyboard-150s.md) owns the unchanged cut boundaries and source classes.
3. **[Shot bible](shot-bible.md)** and [creative treatment](creative-treatment.md) explain composition, sound, concrete skin continuity and fallback decisions. The [lake](diagrams/r5-lake-blocking.svg) and [truck](diagrams/r5-truck-blocking.svg) maps distinguish source geography from proposed targets.
4. **[Phoenix RC / ClearView showcase](import-showcase.md)** specifies 18 provisional previews in ten seconds, a same-model eligible flight and the evidence required for the inactive 300+ variant.
5. **[Integrated opportunities](feature-opportunities.md)** assigns discovered functions to the master or companions. [Field Notes](feature-companion-films.md) remains 90 seconds; [Preflight Ballet and mechanics](mechanical-sequences.md) remain 32 seconds plus the master inserts.
6. **[R5 audit](script-audit-r5-2026-11-21.md)** records source findings, review corrections and focused software verification. [Verification gates](verification-gates.md) keep proposed staging separate from filmed acceptance.
7. **[Capture-tool guide](../../../tools/trailer/README.md#r5-shot-plan-and-livery-finish)** documents the new offline plan checker, exports/maps and opt-in final-livery hold. It also names the adapters still required before automatic capture.

## Decisions carried into R5

- The full master remains **150 seconds / 9,000 intended frames**: 112 s session footage, 15 s genuine UI, 18 s presentation/inspection and 5 s end card. There is no spare timing pool.
- Every cut has a first visible state and an exit. Preparation, native spawn positions, proposed flight targets and editorial omissions are distinguished. NED coordinates, terrain-supported ground markers and relative camera offsets have explicit contracts.
- Stock cast choices now have actual catalog/data/skin bindings. Mustang, Extra and Lumber retain their shipped factory finish. Other selected skins are distributed across the fleet.
- Corsair ground mechanisms use **Coastal Three Tone**. Its continuous ten-second orbit shows all 13 stock skins: twelve 0.75-second holds, then one second of Three Tone into the lake. The existing orbit pivots around the visual model origin, not the center of gravity.
- The six-second lake shot contains shoreline approach, water crossing and exit. The proposed path crosses approximately 74.18 m of the source shoreline polygon, or 3.23 s at nominal 23 m/s. These are geometric estimates, not a flown route or accepted reflection.
- HX-700 collective remains a labelled four-second stopped-rotor inspection. X-Cell is a separate playable helicopter with governed hover established before its four-second shot.
- Imports retain the 15-second chapter: two seconds of Creator, ten seconds of 18 real preview targets and three seconds of the final model's eligible trial. **EXPAND YOUR HANGAR** stays active; **300+ MODELS TO IMPORT** remains gated by an actual deduplicated compatibility count.
- FPV recovery, native-speed controls, engine-out practice, AI, calibrated scenery, storm, smoke/night, Physics Lab, scale and shallow-water driving keep their assigned coverage and proof conditions.

## Work status

| Step | Work | Proof / status |
| --- | --- | --- |
| V2-SCRIPT-01…02 | Skill audit and R3 story/mechanics | Historical input retained. |
| V2-FEATURE-01 | Source investigation | Integrated opportunity ledger retains its implementation references. |
| V2-SCRIPT-04 | R4 timing/import expansion | Retained historical 150-second story foundation. |
| V2-SCRIPT-05 | R5 detailed direction and blocking | Current script, numeric plan, maps, cast/skin decisions and synchronized support documents. Proposed paths remain unflown. |
| V2-IMPL-01 | First capture-tool increment | Offline source/timing/cast/livery checks, coordinate export and maps; opt-in livery hold-last. Focused checks recorded in the R5 audit. |
| V2-SCRIPT-03 | Moving storyboard/animatic readability | Pending actual visual material. |
| V2-IMPORT-COUNT | Numerical import claim | Pending; 300+ is not substantiated by reviewed evidence. |
| V2-TOOLS-01 | Remaining capture routes | Coordinate spawning, camera/state capture and shot-specific adapters remain scoped follow-up work in R5. |
| V2-PROOF-01 | Qualify actual takes | Pending selected build/host, import admission, mechanics, recovery, water/reflection, light and final media. |

The user authorized starting code as well as deeper direction. This revision changes planning documents and tools under tools/trailer; it does not change simulation physics or app runtime. The narrow headless livery test is software evidence, not gameplay footage or renderer/hardware qualification. No new model import batch, music selection or finished video is claimed.

## Historical revisions and retained research

- [R4 screenplay](cinematic-script-r4.md) and [R4 audit](script-audit-r4-2026-11-21.md) preserve the story expansion; R5 now owns current staging and direction.
- [R3](cinematic-script-r3.md), [90-second storyboard](storyboard-90s.md), [R3 audit](script-audit-r3-2026-11-21.md) and [R2](cinematic-script-r2.md) are historical input.
- [AI video skills research](research-ai-video-skills-2026-11-21.md) and [vendor manifest](vendor-skills-manifest.json) preserve five MIT upstream and four original OpenRC skills. [Idea bank](ideas-from-ai-film-skills.md) records their application.
- [Music research](research-music-and-trailers.md) remains an un-auditioned candidate list; R5 owns current sound placement.
- [Windows RTX3090 study](windows-rtx3090-capture.md) preserves implementation options and historical evidence with their original scope.

Some skills still mention R2 by filename. Read this index first; those links do not restore old timings. No skill files or licensed upstream text change in R5.

## Existing foundation

[Previous film plan](../cinematic-trailer.md), [v9.13 review](../../research/cinematic-trailer/revision-9-2026-10-29.md), [capture tools](../../../tools/trailer/README.md), [v9.13 delivery identity](../../research/cinematic-trailer/delivery-v9-2026-10-29.json).

The October English/Spanish film was recorded as a local export. Its documents inform this plan; the final MP4 was not newly inspected. Historical results retain their original source/build/host scope.
