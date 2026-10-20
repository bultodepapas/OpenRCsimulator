# TT-21 — Turbo Lumber visual optimization

Measured 2026-10-20 with the pinned Godot 4.7.2 engine. This pass optimizes only the Turbo Lumber presentation added in [TT-20](../TT-20/README.md). The original aircraft geometry, flight physics, controls, collision definitions, damage decisions and cost calculations are unchanged.

## Results

| Measurement | Baseline | Optimized | Scope |
| --- | ---: | ---: | --- |
| Repeat aircraft finish construction | 551.6 ms | 22.3 ms | Median of six alternating same-process pairs; about 96% less CPU construction time after warming the caches |
| Full-aircraft visible draw calls | 165 | 143 | 22 fewer submissions, or 13.3%, in the isolated front/rear/20 m views |
| Airborne visual observer | 98.8 µs | 59.3 µs | Same-process paired median ratio 0.602, about 40% less CPU time |
| Contact-dust work without compressed wheels | 47.0 µs | 9.3 µs | Paired median ratio 0.197; loaded-contact effects are unchanged |

The isolated first candidate finish build took 567 ms; this is a repeat-build improvement, not a faster first startup. Taxi, cable deformation and loaded-contact timing showed no meaningful improvement. Native timing samples were collected on a shared active desktop with an RTX 3090; these scoped results do not establish a whole-game FPS increase or a target-hardware guarantee.

## Implementation and ownership

[Visual details](../../../../app/aircraft/timber_visual_details.gd) cache the expensive painted-surface analysis and fuselage lettering samples. Eight paint-template entries and 256 sample entries bound retention. Keys include source mesh data, current material names, root-relative transform and repair configuration. Templates retain no node or material references; each aircraft receives its own mesh and finish materials. The cache preserves arrays before renderer packing so rebuilding a cached mesh does not accumulate attribute rounding. The measured steady-state logical array payload was 1.88 MB; eviction pressure held eight entries and 2.58 MB. These are observed payload sizes, not a hard byte budget.

The 24 hub-bolt instances become two meshes under the same wheel parents, using the original transformed triangles and steel material. The existing `TimberHubFasteners` groups and `crash_no_bounds` exclusions remain. No detail, texture, light, control surface or animation is removed, and no distance-based simplification is introduced.

[Visual motion](../../../../app/aircraft/timber_visual_motion.gd) stops unnecessary dust contact evaluation during pause or when no wheel has positive compression. Loaded-wheel slip reads existing telemetry directly. Suspension solving, wheel contact height, dust thresholds, cable/coil reconstruction and crash-copy behavior remain unchanged. A vertex-buffer-only experiment was rejected because the pinned engine left CPU mesh arrays, duplicate geometry and AABBs stale; a shallow-copy experiment was removed after paired timing showed no benefit.

## Evidence

- [Construction profile, cache invalidation and eviction](details/README.md), including exact native cold/warm mesh/material/label parity.
- [Motion profile and 41 runtime checks](motion/README.md), including six exact pose/geometry/AABB snapshots and input immutability.
- [Cold native render comparison](render/cold/summary.json) and [warm comparison](render/warm/summary.json): all 30 baseline/candidate RGB pairs are pixel-identical at 1280 × 720. Primitive counts match. The close gear view falls from 154 to 132 calls; the nose view, where one wheel is culled, falls from 143 to 132.
- [Visual isolation](visual-isolation.json): 164 checks pass, including exact source triangles and winding, articulation, factory lights, and prepared Wreck section boxes and centers. The count is 22 lower than TT-20 because there are 22 fewer detail mesh nodes to check; no invariant was removed.
- The original model contract passes all 452 checks, and generated detail resources match their source inputs. The source GLB remains SHA-256 `d75ae605aa3afdf3f417a0ec535c3bd3126c2a5a4eb7827393727152245c6722`.

The final native [ground/takeoff/flight sequence](takeoff/report.json) and [severe crash sequence](crash/report.json) each completed 660 review frames with zero engine errors, warnings, simulation faults or render-state mutations. Review covered [loaded gear](takeoff/takeoff-120.png), [banked flight](takeoff/takeoff-659.png), [separated components](crash/crash-039.png) and the [settled wreck](crash/crash-609.png). All twelve captured flight-state, command and compression arrays, both final flight states, and the complete severe-crash decision report match TT-20 exactly; [the comparison receipt](flight-equivalence.json) records the checks. The severe crash retains nine detached groups and ten sleeping wreck bodies.

The review fixture now tracks audio playback with weak references and waits at most one second after scene teardown, outside the review and measured intervals. This reuses the project's loading-probe pattern: quitting after a single frame could precede the audio mixer's release callback. Both final runs release all ten tracked playbacks and pass with warnings treated as errors. Production audio and teardown logic are unchanged.

The [delivery manifest](manifest.json) binds the final runtime sources, retained artifacts and checked engine logs. Independent read-only review found no mesh/material ownership, cache invalidation, simulation/economy leakage or Wreck-bounds defect.

## Reproduction

Use the pinned engine and checked runner from [TOOLS](../../../TOOLS.md). All capture output directories must be new. The [render probe](../../../../research/timber/optimization/render_profile.gd) loads the preserved baseline helper alongside the candidate, alternates order over five views and three pairs, and retains 24 measured frames after 12 warmup frames per view. Warm mode mounts, draws and defers destruction of its warmup model before measuring the next instance, matching the engine's deferred material lifecycle.

```powershell
python tools/godot/run_checked.py --out-dir tmp/timber-checks --label render --timeout 240 -- .tools/Godot_v4.7.2-stable_win64_console.exe --path app --audio-driver Dummy --disable-vsync --max-fps 120 --script C:/DEVELOPMENT/OpenRCsimulator/research/timber/optimization/render_profile.gd -- --out=C:/new/timber-render --mode=production --warm=true
python research/timber/optimization/analyze_render.py C:/new/timber-render
```

Omit `--warm=true` for the cold candidate. The construction and motion reports link their respective paired harnesses. Flight/crash review uses the unchanged [TT-20 fixture](../../../../research/timber/visual-upgrade/review_flight.gd). The [aircraft guide](../../../../assets/aircraft/turbo-lumber-evolution/README.md) remains authoritative for authoring; inherited source proportions and physical-validation limits remain as recorded in TT-20.
