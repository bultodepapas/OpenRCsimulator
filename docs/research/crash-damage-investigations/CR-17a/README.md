# CR-17a — Local scenery damage

2026-10-12 · Godot 4.7.2-stable · Compatibility/OpenGL · Status: implemented gameplay behavior; material calibration and Gate CR remain open.

## Result

Aircraft contacts now damage scenery according to a declared material profile. Ordinary flight uses the existing float64 swept-hull detector and aircraft response rules. Destruction commits only after the complete simulation tick succeeds. Rendering reads the committed state; decorative fragments never decide flight physics.

| Object | Outcome |
| --- | --- |
| Timber fence posts/rail bays, orange flightline rails | Local breakup and wood chips. Neighbouring pieces remain. |
| Fence wires | One bay snaps into two hanging ends. |
| Tables, benches, signs, aircraft cradles | Lightweight wooden-prop breakup. |
| Parked aircraft | Bounded fragments from the existing baked mesh; this does not describe the aircraft's measured construction. |
| Hay bales/stacks | Loose straw clumps and a brief chip burst. |
| Bushes | Local shrub removal and leaf debris; animated tips disappear with the base. |
| Cars, lamps, poles, buildings, large trunks | Local mark/chips; the main obstacle retains collision. |
| Tree crowns/hedges | Leaf burst; the standing vegetation remains. |
| People, animals, distant infrastructure | Existing contact response; no destruction profile. |

The near-pilot flightline barrier is now included in the collision inventory. Its walking gap and spaces between rails remain open. Field fences share one beam recipe between rendering and collision; the previous proxy post spacing and wire heights disagreed with the visible mesh. Rails are divided at their actual posts, so one hit cannot remove an entire field boundary.

`scenery/collision_world.gd` assigns stable damage IDs and material profiles. `sim/scenery_damage.gd` owns provisional incident-energy cutoffs: wood 20 J, wire 8 J, lightweight airframe 10 J, straw 25 J, foliage 15 J, metal marks 15 J and masonry marks 20 J. These are gameplay estimates, not physical material or joint strength. No cumulative fatigue or support-collapse propagation is modeled.

`FlightSession` stages the damage during contact resolution and commits it on `Simulation.stepped`. A later continuous-state projection failure discards the pending change. Broken groups are excluded from subsequent collision sweeps and secondary wreck contacts. The immutable source inventory remains intact. Matching v7 checkpoints retain the detached damage records and fingerprint the damage policy; a missing damage field means intact scenery for the same accepted configuration. Restart restores the original collision and mesh resources.

Intact scenery stays merged in cells. `scenery/damage_batches.gd` rebuilds only affected geometry from retained source ranges, preserving adjacent props. Broken-prop shadows are removed, including after lighting changes and checkpoint commits. The aftermath retains at most 24 effect groups, six fragments and 32 particles per group; snapped wire uses eight particles. A pause freezes debris and particles. Settled fragments stop receiving transform updates. Secondary wreck contacts now prioritize distance to the actual impact before applying their existing 160-body cap.

## Verification

- [Session checks](session.log): 51/51, including direct-step damage, collision removal, hard survivors, exact replay continuation, malformed restore rejection and failed-tick rollback.
- [Geometry/presentation checks](presentation.log): 78/78, including wire/rail height alignment, local removal, neighbouring collision, barrier gaps, shadows, bounded effects, pause and exact mesh reset.
- [Production integration](runtime.log): 8/8. An actual production flight with an explicitly synthetic single CG probe strikes the installed wire fence; the accepted tick changes the scene, restores its damaged checkpoint and heals on reset.
- [Existing flight/wreck integration](landscape-runtime.log): 56/56, including engine ray queries against the struck car, building, trunk, lamp and parked aircraft.
- [Regression summary](checks.json) records the frozen integration parse and focused scenery, collision, checkpoint, crash and UI checks. Native gallery [log](gallery.log) records the renderer/device.
- The frozen run checked 465 scripts and 29 focused tests. Four initial qualifications are retained in the summary: a concurrent smoke draft lacked a preload; the app-only snapshot lacked the loader's parent generator path; a scenery build sampled 426 ms during concurrent native work; and Timber's catalog promotion triggered a preview-status-dependent wreck assertion. Updated/isolated live checks pass. The [163 wreck checks](wreck.log) retain delayed releases, energy bounds, ground contacts and lifecycle coverage; the merged Timber geometry rule now follows the model ID rather than menu status.
- The existing transcendental guard exposed a pre-existing bare `sqrt` in the flight-mode diagnostic. Routing it through `M.sqrt_` passes the [guard](math-guard.log) and [42 mode checks](modes.log); no flight-force law was changed.

Synthetic native views: [intact](before.png), [impact](impact.png), [settled](after.png), [restart](reset.png). The intact/restart image comparison and checked source hashes are in [manifest](manifest.json).

Capture reproduction from the repository root, with the pinned native Windows engine:

```powershell
& .tools/Godot_v4.7.2-stable_win64_console.exe --path app --audio-driver Dummy --script "$PWD/research/crash-damage/cr17a/capture.gd" -- --out="$PWD/.tools/scenery-destruction-gallery"
```

Headless tests use `--headless --path app --audio-driver Dummy --script res://tests/test_scenery_damage_session.gd`, `test_scenery_destruction.gd`, or `test_scenery_destruction_runtime.gd` with the same prefix.

## Limits

The detector still sweeps discrete aircraft hull points, not a continuous wing/airframe mesh. Broken-prop fragments are decorative and do not form new flight obstacles. Large structures do not collapse; lamps do not bend. Cosmetic animation phase and old capped aftermath groups are not checkpoint state. Captures and software checks establish implementation behavior, not physical impact accuracy, pilot acceptance or a lower-end frame-time gate.
