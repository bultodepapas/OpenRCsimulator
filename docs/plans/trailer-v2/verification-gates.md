# Trailer 2.0 — feature claims, release gates and work queue

**Status:** documentation review only. Implemented-in-source does not mean filmed, tested on Windows RTX3090, or available in public v0.3.0.

## Strict source-to-trailer claim matrix

| Hero claim | Verified code/project basis | Truth boundary and film gate |
|---|---|---|
| All 13 selectable vehicles | [Vehicle roster](../../../app/app_state/vehicle_roster.gd), [catalog](../../../app/app_state/aircraft_catalog.gd) | Current menu: 8 airplane configurations + helicopter + quad + blimp + 2 trucks. Hidden research configs do not count. Verify exact filming version. |
| Bisonte and MONSTER CAR 2 | [Nitro truck integration](../../../research/rc-monster-truck/monster-car-2/README.md) | Two cars, different propulsion; nitro has no reverse. No verified normal car race/time trial. |
| Corsair skins and lake mirror | [Lake planar renderer](../../../app/render/lake/lake_planar_reflection.gd), [RTX3090 jet lake experiment](../../research/visual-quality-implementation/VQ-07/planar-lake-2026-10-22/README.md), [v9.13 Corsair livery](../../research/cinematic-trailer/revision-9-2026-10-29.md) | A **Corsair** mirror has not yet been confirmed. Planar default off. Skin montage from matching flight/presentation states, not an in-game player skin-swap feature. |
| Small and giant | [Workshop compiler](../../../app/workshop/compiler.gd) | 10–500% for supported Ugly Stick, not every plane. 0.1524m / 1.524m / 7.62m approximate spans need true perspective. |
| Night lights and smoke | [Old cinema capture guide](../../../tools/trailer/README.md) | Only aircraft profiles that support it; night must be actually visible, not postproduced fantasy. |
| Import models | [Creator UI](../../../app/ui/aircraft_creator.gd), [public v0.3.0 release](https://github.com/bultodepapas/OpenRCsimulator/releases/tag/v0.3.0) | ClearView/STL/GLB, newer Phoenix .mod on main. Preview vs trial are distinct; saved Creator aircraft not flyable from Home. |
| Broken/cracked camera glass | [Lens stack](../../../app/render/lens/lens_stack.gd) | Lens crack after valid near fast closeup/FPV impact. This isn't structural canopy glass. |
| Blood on camera | [Lens settings](../../../app/render/lens/lens_settings.gd), [contact logic](../../../app/render/lens/lens_stack.gd) | Requires person/pilot strike and enabled impact effect. A crash onto grass should NOT show blood. Non-bloody alternate required. |
| Highest graphics on RTX3090 | [Graphics guide](../../../tools/graphics/README.md) | High Forward+; Extreme scene / Ultra lens where supported; separate optional planar environment. Stock official engine != special DLSS NVIDIA fork. |
| FPV gate racing | [Drone racing plan](../drone-racing.md) | Local races only, no multiplayer/online ranking claim. |
| AI planes and formations | [v9.13 audit](../../research/cinematic-trailer/revision-9-2026-10-29.md) | Actual AI pilots fly circuits; cinematic same-frame multi-plane formations must be disclosed as choreography. |
| Cinematic replay | [Old cinema capture guide](../../../tools/trailer/README.md) | This is production tooling, not a built-in editor available to player. |

## Hard creative and production acceptance gates

**G0 — Docs/feature approval:** confirm title, ship-target build, full 13 roster, exact footage priorities and current gameplay claims. All authoring is docs only.

**G1 — RTX3090 filming readiness:** approved beta2 Godot executable/build, driver, High Forward+, Extreme where stable, lens Ultra where relevant, native movie dimensions and full 60fps output verification; no silent renderer fallback. Commit/build hashes retained.

**G2 — Corsair lake signature:** two different Corsair skins demonstrably show a moving, correctly colored reflection in water on a real Windows take. Retain full clip, timing and flag receipt. If it fails, invoke documented honest jet fallback, never artificially mirror the aircraft.

**G3 — 13-choice roster:** exactly 13 independent identifiable moving clips, each containing matching UI/name/visual variant and at least one meaningful action; player recognizes each at phone size.

**G4 — Hero feature coverage:** day/sunset/blue hour/night lights, real Workshop control then flight results, Creator format/preview/test-flight distinction, two different car jumps and lighting, FPV course, true dirt/water/crack effects, optional actual person-strike effect.

**G5 — Music and assets:** actual auditions and measurable cue sheet, synchronization/license proof, complete model and livery origin rights, attribution, platform/content compatibility. No unpublished track copied into repo.

**G6 — Editorial picture:** main ≈90s, gameplay-first ≥80%, first 5s compelling, few readable feature labels, action-driven transitions, no fabricated interface/replay/multiplayer, no silent accidental slow or frozen frames.

**G7 — Film QA:** 1080p60 source and final frame count, full decode, 48kHz source/stereo delivery, source and final sound balance, no dark disappearing plane or muddy grade, reflection frame spot-check, no artifact license gaps; review on phone muted and with headphones.

**G8 — Marketing release:** correct download URL, clear free/open-source + early alpha status, English and Spanish copies, 30 s / 6 s versions, no-blood option, actual final poster frame. Publication is OUTSIDE this docs branch.

## Future execution queue — not started

| Priority | Ticket | Work | Evidence required |
|---|---|---|---|
| P0 | V2-01 | Approve creative/claim list | story cut and source status |
| P0 | V2-02 | Audition Simulacra, Escape Velocity, Pursuit, Vanguard | licensed listening notes + 90s beat map |
| P0 | V2-03 | Requalify capture tools for beta2 Windows High | native frame/tick/audio receipts |
| P0 | V2-04 | Corsair over lake: planar flag on/off + two skins | moving original frames, compare reflections |
| P0 | V2-05 | True glass crack and red person/pilot effect triggers | contact event and 60fps original frames |
| P1 | V2-06 | Confirm Creator imports and eligible source models | exact format/preview/trial matrix |
| P1 | V2-07 | Bisonte and MONSTER CAR 2 jump, daytime + lights | jump-to-landing, engine audio, LEDs |
| P1 | V2-08 | All 13 fleet microshots | accepted independent roster clips |
| P1 | V2-09 | 10/100/500% Stick, same landmark and camera | true size evidence |
| P1 | V2-10 | Four times of day, RGB, storm/wet lens | legible original day/night samples |
| P2 | V2-11 | Silent animatic then two score drafts | complete timeline and cue sheet |
| P2 | V2-12 | Picture lock, edit, grade, audio, credits and variants | final film deliverables/rights |

## Provenance and status update rule
Every future test must record date, source SHA, exact engine executable, CLI/profile, shots, screenshots/original footage hashes, assertions tested, pass/fail and remaining limitations. Use distinctions: **verified in source**, **observed in older build**, **observed in current Windows film run**, and **available in public release**. Do not mark this docs branch as an actual gameplay/camera qualification.

### Public research used
[Steamworks trailer guidance](https://partner.steamgames.com/doc/store/trailer) · [Derek Lieu pacing](https://www.derek-lieu.com/blog/2020/11/16/how-to-think-about-pacing-in-a-trailer) · [Godot Movie Maker](https://docs.godotengine.org/en/stable/tutorials/animation/creating_movies.html) · [Godot renderer overview](https://docs.godotengine.org/en/stable/tutorials/rendering/renderers.html) · [Scott Buckley library](https://www.scottbuckley.com.au/library/) · [Pixabay license](https://pixabay.com/service/license-summary/).
