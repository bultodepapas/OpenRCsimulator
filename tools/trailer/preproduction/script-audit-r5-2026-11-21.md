# Trailer 2.0 — R5 direction and first-code audit

**Date:** 21 November 2026. **Track / owner:** V2 / trailer director-editor and lead developer.
**Input:** trailer branch at `55935b5bb31a5178fdf767b430ba35ad852be256`; R4's 150-second screenplay, source research and the user's request for specific positions, vehicles, skins, starts/exits, cameras and incremental implementation.
**Game-source baseline:** `57abea025f62b20233ca281d58d2acbee4ab8b8e`. The plan remains pinned to this source identity; a newer main branch or release does not silently requalify it.
**Output:** [R5 shooting script](cinematic-script-r5.md), [numeric shot plan](shot-plan-r5.json), [lake](diagrams/r5-lake-blocking.svg) and [truck](diagrams/r5-truck-blocking.svg) maps, synchronized support documents, [offline plan tool](../shot_plan.py) and a small [capture-director](../flight_director.gd) change.

## What R5 changes

The edit remains exactly **150 seconds / 9,000 intended frames at 60 fps / 62 cuts**. R4-prefixed IDs remain stable. The 90-second Field Notes and 32-second Preflight Ballet remain companions. This pass adds direction and an executable plan contract without expanding the timeline.

Every master cut now has a named cast and skin, environment, preparation, first visible state, subject markers, camera framing, actions, exit, transition, continuity and acceptance conditions. Numerical positions are proposed rehearsal targets. UI and inspector shots use their actual native frames instead of invented world coordinates. Imported models retain explicit unresolved local identity and admission fields.

The plan contains 33 cast records: 13 stock selections, 18 import candidates, the separate HX-700 inspector and editorial content. Thirty-two source files are SHA-256 pinned. The human script and machine-readable plan are synchronized; the storyboard retains the cut boundaries and source classes.

The filmmaking principles carried forward from the nine reviewed skills are applied concretely: an understandable action before a cut, preparation outside the edit, fixed reference surfaces for mechanisms, a consistent paint across continuity shots, a held visual payoff after rapid cuts, authentic source classes, and sound motivated by the vehicle or event. The [idea bank](ideas-from-ai-film-skills.md) and [research provenance](research-ai-video-skills-2026-11-21.md) retain that background; no skill installation or licensed-text change occurred here.

## Source findings that changed the direction

| Finding | R5 decision and evidence |
| --- | --- |
| A selected lake chord is shorter than a six-second nominal pass | N128, E55→193 at configured 23 m/s covers 138 m. The [actual shoreline](../../../app/data/fields/lake.json) intersects approximately 74.18 m of that line: 3.225 s nominally over water. The six seconds therefore show approach, crossing and exit. This is horizontal geometry, not flight or clearance evidence. |
| Existing orbit centers on the rendered model origin | [Director](../flight_director.gd) and [aircraft rendering](../../../app/render/airplane.gd) distinguish visual root from simulated CG. The script preserves the actual seven-metre root-relative orbit and marks that exception to the proposed CG-relative camera convention. |
| Default livery cycling wraps before the intended final hold ends | With 13 skins, from/every 0.75 s, the old modulo schedule returns to the first skin at simulation time 9.75 s. Opt-in hold-last keeps `three_tone`. It leaves the existing default looping behavior intact. |
| The simulation and edited movie have different clock origins | Actual `sim_time_s` and presented livery must be checked per recorded frame. Hold-last fixes the final identity but does not by itself guarantee twelve presented 45-frame intervals and a final 60-frame interval. |
| Several selected aircraft have one shipped finish | Mustang, Extra and Turbo Lumber retain factory appearance. Vantage, trucks, electric/glow Sticks, MoonRunner, blimp, X-Cell and Corsair have specific supported selections. The [cast ledger](shot-bible.md#skin-and-continuity-ledger) records them. |
| Ground coordinates are not supported aircraft CG coordinates | `NE_surface` is a plan-view marker. Ground reset/support must supply actual CG, wheel loading and attitude; a fallback airborne reset cannot pass ground acceptance. NED and render conversion are explicit. |
| Existing fixed-wing spawn is not a live teleport | [Main](../../../app/main.gd) and [flight session](../../../app/sim/flight_session.gd) apply external airborne starts before the scene/session runs; height can be terrain/lakebed-relative. The arbitrary lake-origin adapter is still required. |
| Existing helicopter helpers do not implement the new mechanical and pad shots | The [old inspector capture](../capture_hx700_mechanism.gd) includes 12 rpm/cyclic motion. R5 requires stopped collective. [Vehicle capture](../capture_vehicles.gd) starts X-Cell airborne and has no livery option. R5 uses manual pad/skin selection and governed preroll, then begins already hovering. |
| Generic flight capture disables failures | [capture_flight.gd](../capture_flight.gd) supplies `--failures=0`. Engine-out practice therefore needs the ordinary supported UI flow or a separately reviewed adapter. No capture success is inferred from the generic script. |
| Native mechanism travel exceeds some inserts | Corsair wing spread is about 8 s; canopy and flap travel about 2.5 s. The master selects acknowledged native-speed end excerpts. Wheels stay loaded and gear stays down. No unsupported cockpit-stick/pedal animation is promised. |
| Giant and mini trials cannot both be readable at one fixed scale of framing | The 10% trial uses a deliberately closer view with a size label and field context. Only the disclosed presentation trio holds equal depth. Its chosen Honeybee paint still needs adapter work. |
| Ground water evidence is local | Bisonte's proposed southbound route stops at N138/E125; a deeper overshoot is rejected. A point-depth estimate does not qualify every wheel or an entire shoreline crossing. |

The active import wording remains **EXPAND YOUR HANGAR**. The requested 300+ variant still needs its actual deduplicated compatibility evidence. R5 does not replace provisional import sources with invented accepted assets.

## First implementation increment

`tools/trailer/shot_plan.py` uses Python's standard library to validate, inspect, export and map the plan. It reads local source; it does not launch Godot, download/import models, mutate game state or control a flight. Explicit output files are created exclusively and never overwritten.

Validation covers source hashes and selected JSON assertions; literal stock catalog bindings between selectable ID, data path and visual family; skin membership/default-selection values; exact storyboard IDs/bounds/classes; 18 preview intervals totaling 600 frames; and the R5 livery order with twelve 45-frame holds plus 60 final frames. Changes in unsupported catalog source shape fail rather than guessing. Catalog membership is not flight eligibility.

Exports add render coordinates only to actual NED records. Ground surface markers remain markers. Club-field maps use the pinned lake/runway/pilot geography and, for truck shots, the actual tabletop footprint/deck. Their framing is local to the shot; the legend names only the source context shown. They expressly identify proposed targets rather than recorded paths.

`--livery-hold-last` is the only behavior change in the existing capture director. Its effect is limited to presentation mesh selection. No app runtime file, simulation law, aircraft physics data, asset binary or input mapping changed.

## Focused verification and review

| Check | Observed result and scope |
| --- | --- |
| Offline Python tests | **15 tests passed.** Independent polygon cases include finite-segment clipping and a concave shoreline; NED conversion and unconverted surface markers; malformed/source-drift/reference failures; wrong valid vehicle ID, hidden entry, data/family mismatch, wrong skin/order/cadence; CLI output refusal; map world/source constraints and tabletop context. |
| Actual R5 plan | **62 shots / 9,000 frames / 32 verified source hashes.** Nominal line 138 m, water interval 74.18181818187 m, nominal water time 3.22529644269 s. |
| Capture-director schedule | Pinned **Godot 4.8.beta2.official.cafc17a19**, Linux headless, checked runner: **31 checks, 0 failures**, process exit 0, no error/warning diagnostics, required completion marker present. Uses actual director selection/mesh-swapping code with controlled test meshes; no rendered stock GLB or flight acceptance. |
| Schedule evidence identity | Checked-run capture ID `ff47136d-e5e6-4144-af6e-bfc868929450`; engine log SHA-256 `c22523deee74a07a16ec941af1b9a1ecf50441db8077925e0e99d6d90299162d`. Raw output remains temporary; the reproducible command lives in the [tool guide](../README.md#r5-shot-plan-and-livery-finish). |
| Actual CLI output | `show R4-40` resolves `three_tone` and render entry `(55, 2.55, −128)`; `export` emits all 62 shots to a fresh output directory. |
| Document integrity | 21 changed/new Markdown files: 366 relative links and 29 heading anchors checked, with no missing targets. `git diff --check` clean. |
| Maps | Both SVGs regenerated from the accepted plan/source inputs, rendered to temporary PNGs and visually inspected. Lake boundary, truck tabletop, proposed marks and readable local legends are present. |
| Independent review | Final review reported no remaining material findings. Corrected visual-root versus CG anchoring, catalog-binding and livery-rhythm validation gaps, source-class-specific acceptance, the mini shot's intentionally different camera, map context and the X-Cell setup/adapter distinction. |

Source review, focused software tests and diagram inspection do not establish physical validation, pilot acceptance, 1080p60 performance or final moving-image quality. No broad game test suite, gameplay capture, new asset import batch or target Windows/RTX3090 qualification occurred in this pass.

## Remaining production work

The [R5 implementation section](cinematic-script-r5.md) orders the next increments: source-bound session/camera setup; recorded actual state and frame identity; single-shot proof takes; then staged captures and edit. Exact flight paths, clearances, mechanism readability, recoveries, supported import trials, water/reflection, lighting and audio remain open under the [gates](verification-gates.md).

Any promoted-source change requires deliberate plan requalification. Do not simply replace pinned hashes or substitute a historical take to make validation pass. Keep accepted source identities, preparation and measured outcomes with the actual footage.
