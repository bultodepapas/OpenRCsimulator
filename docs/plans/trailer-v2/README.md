# OPEN RC SIMULATOR — Trailer 2.0 preproduction

**Updated:** 22 November 2026. **Status:** R6 cinematic direction, global-frame titles and camera-recipe implementation; real proof footage remains pending.
**Branch:** `docs/trailer-v2-preproduction-2026-11-21`. **Track / owner:** V2 / trailer director-editor and lead developer.
**Game-source baseline:** `57abea025f62b20233ca281d58d2acbee4ab8b8e`. The exact promoted build remains a production decision.
**Requested filming host:** Windows PC with NVIDIA RTX 3090; 1080p60 first. Linux software and synthetic typography checks do not qualify that capture host.

## Current authorities and review material

1. **[Director’s shooting script R6](cinematic-script-r6.md)** owns story, direction and shot intent. It retains **150 seconds / 62 cuts** and adds the cinematic copy, camera grammar and concrete implementation boundaries. Its complete shot-card block is generated from the numeric plan and checked for drift.
2. **[R6 shot plan](shot-plan-r6.json)** owns cast, skins, preparation, proposed positions, camera settings, action, exit and continuity. **[The storyboard](storyboard-150s.md)** owns the unchanged R4-prefixed cut IDs, frame boundaries and source classes.
3. **[R6 title plan](title-plan-r6.json)** owns the three main titles, continuous functional qualifications and full five-second invitation. **[The typography study](review/r6/typography-study.mp4)** and **[contact sheet](review/r6/typography-contact.jpg)** show the implemented lettering and timing on a neutral background. They contain **no game footage**; [their summary](review/r6/study-summary.json) records inputs, dependencies and output hashes.
4. **[The lake map](diagrams/r6-lake-blocking.svg)** shows the source shoreline, proposed aircraft corridor and new parallel camera marks. The unchanged [truck map](diagrams/r5-truck-blocking.svg) retains its R5 geometry. Both distinguish proposed targets from actual trajectories.
5. **[Shot bible](shot-bible.md)**, [creative treatment](creative-treatment.md), [mechanical sequences](mechanical-sequences.md) and [import showcase](import-showcase.md) expand composition, sound, mechanisms and the 18-model preview casting.
6. **[R6 audit and tool research](script-audit-r6-2026-11-22.md)** records implementation, independent review, actual verification scope and remaining evidence. **[Verification gates](verification-gates.md)** own capture and publication acceptance.
7. **[Capture-tool guide](../../../tools/trailer/README.md#r6-cinematic-titles-and-camera-recipes)** owns executable commands, title/media manifests, camera recipes and restrictions.

## Decisions in this revision

The master keeps **112 s session footage + 15 s genuine UI + 18 s presentation/inspection + 5 s end card = 150 s / 9,000 intended frames**. There is no spare time pool and no change to the established 62 cuts.

The new main copy is deliberately sparse: **A SKY WITHIN REACH** at 14.25–17.50 s; **FEEL EVERY INPUT** at 60.25–64.75 s; **EXPAND YOUR HANGAR** at 125–127 s. Warm-white Barlow typography, brief fades and slight settling replace the old luminous green feature-card treatment. Real HUD, model identities and necessary disclosures remain legible requirements. The lake has no added title.

The Corsair ground mechanisms use **Coastal Three Tone**. The continuous **ten-second orbit** still shows all 13 stock liveries, ending with a one-second Three Tone hold. Its existing visual-model-root orbit anchor is preserved. The following **six-second lake shot** keeps the same skin and now uses a parallel north-bank camera: N145/D−1, east = actual displayed CG east−8 m, FOV 42°. The nominal aircraft corridor remains N128/E55→124→193/D−2.55. These are proposed marks; the capture tool does not fly or spawn the aircraft along them.

The import chapter remains **2 s Creator + 10 s / 18 model previews + 3 s same-last-model eligible trial**. Phoenix RC and ClearView labels stay continuous through their respective nine cuts. The final flight must show its actual estimated/donor physics basis. **300+** remains inactive pending a compatible, deduplicated count.

The end card holds **OPEN RC SIMULATOR / PLAY FREE / official destination** for five complete seconds. It inherits no old beta badge, slogan, four-aircraft description or soundtrack credit. The destination returned HTTP 200 and the matching project page title on 22 November 2026; browser, download, installation and runtime flows were not tested. Recheck before publication.

## Implementation status

| Step | Work | Scope |
| --- | --- | --- |
| V2-SCRIPT-05 / V2-IMPL-01 | R5 staging, source/cast validation and livery hold-last | Retained foundation; R5 remains historical evidence. |
| V2-SCRIPT-06 | Cinematic copy, coherent camera intent and generated shot cards | Current R6 authorities; physical marks remain unflown. |
| V2-IMPL-02 | Camera-only recipe export and composed capture adapter | Fixed-world and parallel-east eyes follow actual presented CG; capture records camera state and rejects interrupted sessions. No flight/spawn automation. |
| V2-IMPL-03 | Global-frame title renderer and cinema assembler | Bounds/coverage checks, continuous labels, explicit new end card, source/font/output cache identities and synthetic review exports. |
| V2-REVIEW-06 | Independent source review and focused software/media checks | Results and limitations in the R6 audit; no target-host footage acceptance. |
| V2-PROOF-01 | Qualify real takes and source windows | Pending mechanics, recovery, trajectory/clearance, reflection, imported models, actual title placement, sound and final film. |
| V2-IMPORT-COUNT | Numerical import claim | Pending; 300+ is not substantiated by this revision. |

The simulator’s physics, aircraft data and app runtime are unchanged. Capture and editorial tools under `tools/trailer` are the code scope. Model-attached size labels for the comparator still require a qualified source or a separately implemented tracked-callout route; the new title renderer provides its static disclosure only.

## Historical work and retained research

- [R5 script](cinematic-script-r5.md), [R5 plan](shot-plan-r5.json) and [R5 audit](script-audit-r5-2026-11-21.md) preserve the prior staging and initial implementation evidence. R6 is current.
- [R4](cinematic-script-r4.md), [R3](cinematic-script-r3.md), [R2](cinematic-script-r2.md) and the [90-second storyboard](storyboard-90s.md) remain historical inputs.
- [AI video skill research](research-ai-video-skills-2026-11-21.md), [vendor manifest](vendor-skills-manifest.json) and [idea bank](ideas-from-ai-film-skills.md) preserve the previously selected skills. No skill files or upstream licensed text change in R6.
- [Feature opportunities](feature-opportunities.md), [90-second Field Notes](feature-companion-films.md) and the [32-second Preflight Ballet](mechanical-sequences.md#separate-32-second-idea--the-preflight-ballet) retain detailed coverage beyond the master.
- [Music research](research-music-and-trailers.md) remains an un-auditioned candidate list. [Windows RTX 3090 study](windows-rtx3090-capture.md) and [v9.13 evidence](../../research/cinematic-trailer/revision-9-2026-10-29.md) retain their original source/build/host scope.

Read this index before older skills or filming notes. Historical file names do not restore old timings, copy or acceptance.
