# TT-20 — Turbo Lumber visual finish

Visual review dated 2026-10-20, Godot 4.7.2, native Windows Compatibility renderer on an NVIDIA RTX 3090. The [aircraft guide](../../../../assets/aircraft/turbo-lumber-evolution/README.md) owns the runtime and authoring instructions; [reference notes](references.md) record the manufacturer photographs, B-revision manual and inspected official flight footage.

## Scope and implementation

The production catalog builder adds a Timber-only presentation layer to the existing r2 aircraft:

- Restrained EPO and tire microtexture using downloaded CC0 normal/roughness maps, separate painted foam, canopy, metal and rubber finishes, and corrected overlapping paint assignments. The original triangle positions, winding and extents remain unchanged.
- Curved fuselage lettering, visible extension-spring coils, wheel-hub fasteners and hidden torn-foam/carbon-spar details that the existing crash renderer reveals with separated parts.
- Main-leg articulation and deforming cable/spring attachments driven by the existing contact state. The existing wheel spin, tail steering and axle contact height are retained. A 6° visual hinge limit respects the source author's wire/bracket clearance advisory; it does not qualify mechanical travel.
- Small dust cues at loaded, slipping tires on loose ground. The effect reads the production contact evaluator and stops during pause/crash; it adds no force, friction or contact rule.
- Paired lower-cowl landing lamps, wingtip navigation lenses and dorsal/ventral red beacons. Their locations follow the existing parts. The generic orientation strips and unsupported tail/tip lamps are disabled for this aircraft.
- A localized aircraft identity and red accent in the existing accident report, plus a compact large-text layout for short windows. Estimates, unknown-price warnings, breakdown rows and actions still use the existing report and calculator.

The generated [detail specification](../../../../assets/aircraft/turbo-lumber-evolution/visual-upgrade/visual_detail_spec.json) is separate from the unchanged source delivery and flight-data pipeline. [Texture provenance](../../../../app/assets/aircraft/turbo-lumber-evolution/visual-upgrade/PROVENANCE.json) pins the free source maps. Manufacturer images and video remain research references rather than shipped textures.

## Isolation and checks

The presentation helpers do not write flight state, controls, collision definitions, damage decisions or prices. New detail meshes carry `crash_no_bounds`; the verifier compares the prepared wreck groups, centers and bounds against the raw aircraft. The per-instance paint repair may change material grouping and normals, but exact original triangle positions and winding are checked.

| Check | Result |
| --- | --- |
| Original imported model contract | 452 checks passed |
| Visual geometry, controls, lighting and wreck isolation | 186 checks passed |
| Contact-driven motion, resource isolation, reset and dust gating | [41 checks passed](motion-runtime-checks.json) |
| Aircraft data / ground / handling | 10 / 23 / 36 checks passed |
| Shared crash sections / night kit / aircraft light controls | 37 / 34 / 151 checks passed |
| Accident-report behavior and layout | 101 checks passed |
| Baseline versus candidate flight trace | All 1,201 numeric CSV rows identical over five seconds; metadata differs with the working-tree build identity |
| Original source and generation | Source manifest, geometry builder/compiler, asset check and physics derivation `--check` passed |

The trace is a numerical preservation check, not a physical-validation claim. No golden flight was re-recorded. The source GLB remains SHA-256 `d75ae605aa3afdf3f417a0ec535c3bd3126c2a5a4eb7827393727152245c6722`.

Release follow-up, 2026-10-21: the generic night-kit test assumed both navigation lamps sit beyond the outermost mesh vertex. TT-20 places its lamps on authored wingtip lenses at x = ±0.7579 m, 0.0149 m inside the 0.7728 m half-span. The test now verifies a lamp matches each authored anchor and remains within 4% of the modeled tip; aircraft without anchors retain the outside-bounds check. The focused native Windows suite passes 86/86. No visual asset, flight state or collision data changed.

The retained machine-readable evidence includes [visual isolation](visual-isolation.json), [focused regression checks](focused-checks.json), [flight equivalence](flight-equivalence.json), [source-pipeline checks](source-pipeline-checks.json), [script parsing](script-parse-check.json) and [fresh-materialization generation](fresh-pipeline-check.json). The paint-assignment spatial index produced the same 178 remaps over 12,030 white triangles and reduced one measured headless finish-construction pass from 5,048 ms to 601 ms; this is construction time, not a frame-rate measurement. The [performance and exact-pixel repair evidence](visual-detail-performance.json) records the method and hashes.

## Retained visual review

The [native review manifest](native-review.json) records engine checks and artifact hashes. Each production sequence has six full-resolution stills and a state report. The videos are silent 30 fps encodes of every second frame from the fixed 60 Hz review clock; their playback duration is not a wall-clock performance measurement.

| Review | Retained evidence |
| --- | --- |
| Twelve close and orthographic views | [Capture manifest](inspection/manifest.json), [nose and spring detail](inspection/inspection_nose_left.png), [front-quarter airframe](inspection/inspection_oblique_front_left_full.png), [gear](inspection/inspection_gear_front.png), [underside](inspection/inspection_bottom.png) |
| Ground movement, takeoff and banked flight | [Video](takeoff/review.mp4), [ground contact](takeoff/takeoff-120.png), [airborne](takeoff/takeoff-659.png), [state report](takeoff/report.json) |
| Dusk lighting through the same flight sequence | [Low flight](dusk/takeoff-240.png), [banked flight](dusk/takeoff-659.png), [state report](dusk/report.json) |
| Moderate flown crash, class 3 | [Video](crash-c3/review.mp4), [impact aftermath](crash-c3/crash-045.png), [settled wreck](crash-c3/crash-615.png), [state report](crash-c3/report.json) |
| Severe flown crash, class 4 | [Video](crash-c4/review.mp4), [impact aftermath](crash-c4/crash-039.png), [settled wreck](crash-c4/crash-609.png), [state report](crash-c4/report.json) |
| Exposed wing-root foam and carbon after separation | [Left root](fracture/wing_left-fracture-close.png), [right root](fracture/wing_right-fracture-close.png), [camera-ray and rendered-pixel proof](fracture/fracture-reveal-report.json) |
| Contact animation and controlled loose-ground slip | [Loaded gear](../../../../research/timber/visual-upgrade/timber-gear-motion.png), [dust capture](../../../../research/timber/visual-upgrade/timber-rough-ground-taxi.png), [fixture limitations and measurements](rough-ground-taxi.json) |
| Existing cost display, English and Spanish at large text | [English](cost-en/cost-report.png), [Spanish at 1280 × 720](cost-es-large/cost-report.png), [calculator fixture evidence](cost-es-large/review.json) |

Daylight takeoff, dusk takeoff and both crash sequences each completed 660 review frames with no engine errors, warnings, simulation faults or render-state mutations on the final snapshot. The severe impact was detected at tick 38 and 37.1 m/s; its nine detached groups and ten active wreck bodies settled to sleep. Close inspection covered the nose, canopy seams, paint boundaries, wing and tail construction, springs, hubs and lamp placement. Flight inspection included the existing control-surface and propeller animation; crash inspection included separation, dust, detached components and the settled wreck.

The final crash-only correction projects the hidden fracture face beyond the measured source wing closure, then exposes the carbon end 0.8 mm ahead of the foam. Full camera rays originally found the source wing approximately 76 mm ahead of the misplaced reveal. New foam triangles now consistently use Godot's clockwise front-face convention, with degenerate wedges omitted and two winding checks added. The final self-occlusion audit finds foam and carbon first at their respective aircraft-mesh witnesses; hiding the foam changes 625/625 sampled pixels on the left and 458/625 on the right. Full-scene intersections are retained separately because a below-ground inspection camera can intersect scenery that does not appear in the rendered view. All twelve intact inspection PNGs remain byte-identical after these corrections. This pass does not edit crash pose logic, separation thresholds or collision bounds.

## Repeat the review

Use the pinned native engine described in [TOOLS](../../../TOOLS.md), an unused output directory and `tools/godot/run_checked.py` to reject engine errors as well as nonzero exits. The inspection script supports `--finish=source` for the original finish.

```powershell
python assets/aircraft/turbo-lumber-evolution/visual-upgrade/build_visual_details.py --check
.tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy --script "$PWD/research/timber/visual-upgrade/verify_visual.gd"
.tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy --script "$PWD/research/timber/visual-upgrade/verify_motion_runtime.gd"
.tools/Godot_v4.7.2-stable_win64_console.exe --path app --audio-driver Dummy --script res://aircraft/inspect_timber.gd -- --output-dir=C:/new/timber-inspection --suite=inspection
```

The production review fixture is [review_flight.gd](../../../../research/timber/visual-upgrade/review_flight.gd). Run it with `--aircraft=turbo-lumber-evolution --quick-flight --scenery=off`, plus:

- Taxi/takeoff: `--start=runway --review-case=takeoff`.
- Flown crash: `--start=airborne --review-case=crash`. The fixture installs a steep dive into a fully initialized airborne session; starting it with runway auxiliary state is invalid.
- Severe flown crash: the crash arguments plus `--review-crash-speed=38`.
- Dusk: the takeoff arguments plus `--time-of-day=18:20 --date=2026-03-20`.
- Every run: `--review-out=C:/new/review-directory`; add `--review-record` for 30 fps JPEG frames.

The fixture supplies a fixed input tape, disables physical-controller takeover and resumes only empty-reason focus-loss pauses caused by review windows. It compares simulation arrays before and after rendering. These are fixture operations; production input and pause behavior are unchanged.

The [cost fixture](../../../../research/timber/visual-upgrade/review_cost.gd) uses the existing incident and calculator to produce a deterministic propeller-strike report. Its manufactured scenario is identified in its evidence. The [rough-contact fixture](../../../../research/timber/visual-upgrade/capture_timber_rough_taxi.gd) separately exposes the tire-dust effect; it must not be described as a validated landing or measured tire experiment.

## Limits

The r2 source's approximately 1.116 m overall length still differs from the manual's 1.040 m. This pass preserves the established physical geometry and collision behavior; it does not resolve that source-model discrepancy. The source's wire/bracket clearance advisory, model redistribution terms, physical flight validation and wider target-hardware gates remain with their existing owners. Beam intensity, flash cadence, cosmetic fracture appearance and dust intensity are visual interpretations rather than manufacturer measurements.
