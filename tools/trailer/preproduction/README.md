# OPEN RC SIMULATOR — Trailer 2.0 preproduction

**Updated:** 22 November 2026. **Current revision:** R7, *A SKY WITHIN REACH*. **Track / owner:** V2 / trailer director-editor and lead developer.
**Source branch:** `docs/trailer-v2-preproduction-2026-11-21` at `42d0cf573`. **Game-source baseline:** `57abea025f62b20233ca281d58d2acbee4ab8b8e`. Exact promoted build remains a production decision.
**Status:** reorganized directing specification and bounded capture/title tools; actual game footage and soundtrack remain pending. Requested filming host: Windows / NVIDIA RTX 3090, 1080p60 first. Linux software and synthetic graphics checks do not qualify that host.

## Start here — one current production package

| Need | Current authority |
| --- | --- |
| Read the film, shot by shot | **[Director's shooting script R7](cinematic-script-r7.md)** — story, exact cast/skins, preparation, action, proposed positions, camera and exit; all 62 detailed cards derive from the numeric plan. |
| Inspect the order and duration | **[Storyboard R7](storyboard-r7.md)** and **[edit/lighting map](diagrams/r7-edit-map.svg)** — 150 seconds, 62 cuts, 9,000 frames. |
| Change numeric instructions | **[Shot plan R7](shot-plan-r7.json)** — single numeric authority for order, cast, geometry, lighting, axes, next cuts and source pins. Regenerate dependent cards/maps/recipes. |
| Understand cameras, day-parts and transitions | **[Direction and continuity](direction-and-continuity.md)** — source API, entrances/exits, screen orientation, real reflection and capture boundaries. |
| Change on-screen copy or timing | **[Title plan R7](title-plan-r7.json)** — 23 global cues, three main headlines, continuous source/qualification labels and full five-second invitation. |
| Review implemented typography | **[Synthetic R7 study](review/r7/typography-study.mp4)**, [contact sheet](review/r7/typography-contact.jpg) and [provenance](review/r7/study-summary.json) — 22.75 seconds of selected title windows on a neutral background; **no game footage**. Actual placement and phone reading remain pending. |
| Understand decisions, research and checks | **[R7 audit](script-audit-r7-2026-11-22.md)** — actual software verification scope, independent findings, applied inspiration and remaining work. |
| Prepare or accept takes | **[Verification gates](verification-gates.md)**, [capture-tool guide](../README.md#r7-cinematic-titles-and-camera-recipes) and [Windows/RTX3090 guide](windows-rtx3090-capture.md). |

[Creative treatment](creative-treatment.md), [shot bible](shot-bible.md), [mechanical sequences](mechanical-sequences.md), [import showcase](import-showcase.md) and [feature opportunities](feature-opportunities.md) expand the current plan. The [lake map](diagrams/r7-lake-blocking.svg) and retained [truck geometry](diagrams/r5-truck-blocking.svg) distinguish source geography from unflown targets.

## R7 directing decisions

The cut moves from **morning play → race and recovery → rotor/ground mechanisms → control and practice → tuning and scale → world/weather → golden Corsair/lake → sunset shore → Creator → final night flight → invitation**. These are separate sessions; neutral Creator UI deliberately separates the sunset shore from its later daylight trial.

The ten-second Corsair orbit remains intact at **105–115 s**, with all **13 stock liveries** and a final one-second Coastal Three Tone hold. The **115–121 s** lake take keeps that skin and golden setting. Its north-bank parallel camera now aims at the source water plane with vertical FOV 34°, leaving room for a real aircraft/reflection pair. A moving-aircraft mirror needs active High and non-headless Forward+ planar rendering; the default cubemap does not supply it. The Bisonte shore follows at **121–126 s**.

The opening jet and electric Stick now have closer parallel cameras. The tiny Stick keeps a proposed close view, but composing that camera with its real 10% Workshop trial remains separate work: the current stock recipe guard correctly refuses a Workshop runtime identity. The final imported trial's camera is on the right side so its nose matches the last preview; the following stock Turbo Lumber is explicitly labelled at **141–145 s**.

The import chapter is still **2 s Creator + 10 s / 18 distinct previews + 3 s same-last-model eligible trial**, now **126–141 s**. Phoenix RC and ClearView labels remain continuous through their respective nine cuts. Actual source artifacts, texture identity and trial eligibility are still to be accepted. **300+** remains inactive pending a compatible, deduplicated count.

Only three main titles are used: **A SKY WITHIN REACH**, **FEEL EVERY INPUT**, **EXPAND YOUR HANGAR**. Functional labels increase from 38 px to 52 px at 1080p; that is a readability improvement to evaluate on real footage, not a legibility certificate. The lake stays free of added text. The end card remains fully settled for five seconds and inherits no unverified beta badge, old slogan or soundtrack credit.

## Implementation and evidence boundaries

| Step | Current work | Remaining boundary |
| --- | --- | --- |
| V2-SCRIPT-07 | New chapter order; explicit source classes, axes, cut handoffs, lighting sessions; regenerated 62-shot script and storyboard. | All source-media in/out and real take acceptance. |
| V2-IMPL-04 | Source-bound water-plane aim; vertical-FOV contract; frame/tick freshness; R7 title/assembly revision binding; chapter/source-time validation and generated maps. | Actual rendering, flight, reflection, exposure, import/Workshop integration and hardware qualification. |
| V2-REVIEW-07 | Independent editorial, code/camera and inspiration reviews; focused checks recorded in the audit. | Full film playback, source sound and final mix. |
| V2-PROOF-01 | Plan for mechanics, recovery, trajectory/clearance, imports, real title placement and sound. | Pending real takes on the chosen build/host. |
| V2-IMPORT-COUNT | Numerical import claim. | Pending; do not publish 300+. |

Allocation remains **112 s sessions + 15 s genuine UI + 18 s presentation/inspection + 5 s end card = 150 s**. Each shot retains its prior duration and source class. Every reviewed Home roster/configuration entry remains covered; that internal 13-entry count is not a claim of 13 different airplane designs. There is no spare time reserve.

The app's simulation, aircraft data and runtime are unchanged by R7. Code changes stay in `tools/trailer`. Camera recipes do not fly, spawn, scale or repaint an aircraft. Model-attached span labels still need an accepted source or a separately qualified tracked-callout route. The website had an HTTP identity/availability check on 22 November 2026; actual browser, download, installation and runtime delivery flows remain unverified and must be checked before release.

## Historical material and research

- **R6 is historical:** [script](cinematic-script-r6.md), [shot plan](shot-plan-r6.json), [old storyboard](storyboard-150s.md), [title plan](title-plan-r6.json), [audit](script-audit-r6-2026-11-22.md), [typography study](review/r6/typography-study.mp4). These retain the original times and evidence; do not combine them with R7 commands.
- [R5 script](cinematic-script-r5.md), [plan](shot-plan-r5.json) and [audit](script-audit-r5-2026-11-21.md), plus [R4](cinematic-script-r4.md), [R3](cinematic-script-r3.md), [R2](cinematic-script-r2.md) and the [90-second storyboard](storyboard-90s.md), preserve earlier decisions.
- [Zoom-through-text research and prototype](research-text-window-transition-2026-11-22.md) remains an **optional synthetic study**, not a transition already placed in the 150-second master.
- [AI video skill research](research-ai-video-skills-2026-11-21.md), [vendor manifest](vendor-skills-manifest.json) and [applied ideas](ideas-from-ai-film-skills.md) retain sources and licenses. The [skills directory](../skills/) holds one copy of each guide and its accompanying license where applicable.
- [Field Notes 90 s / Preflight Ballet 32 s](feature-companion-films.md) retain deeper feature and mechanism coverage outside the master. [Music research](research-music-and-trailers.md) remains an un-auditioned candidate list. [v9.13 evidence](../history/revision-9-2026-10-29.md) keeps its original build/host scope.

Read this index first. Old filenames, examples and skills do not reinstate an earlier edit or a past acceptance claim.
