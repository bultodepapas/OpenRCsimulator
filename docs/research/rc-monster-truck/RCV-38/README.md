# RCV-38 — MONSTER CAR 2 lighting

2026-10-15. The supplied GLB's twelve lens/strip meshes now have independently controlled headlights, running markers, auxiliary LEDs/fog lamps, brake lamps and green underbody neon. Four painted body meshes also receive a restrained neon-linked accent, replacing their always-on source emission. The [vehicle guide](../../../../research/rc-monster-truck/monster-car-2/README.md) owns controls and defaults. No source geometry, textures, physics, fuel model or animation data changed.

## Implementation and research

[`monster_car_2_lights.gd`](../../../../app/vehicles/ground/monster_car_2_lights.gd) prepares nine per-instance material copies, preserving shared source materials, textures and non-emissive housings. Repeated accepted inputs skip material and light setters. Brake intensity changes independently of the headlight switch. A hidden body suppresses all five light nodes. The activity uses restrained glow with zero full-screen bloom; shared aircraft and Bisonte environments are unchanged. The green neon palette includes the spoiler edge; the original multicolored livery texture is retained with lower emission. GroundEffects detaches its owned grime overlays on exit before releasing their resources.

| Lighting role | Light nodes | Range | Distance fade begin → end |
| --- | ---: | ---: | ---: |
| Left/right low beams | 2 spots | 7 m | 18 → 26 m |
| Roof/front auxiliary beam | 1 spot | 11 m | 22 → 32 m |
| Downward neon wash | 1 spot | 0.8 m | 6 → 10 m |
| Rear brake/position wash | 1 spot | 0.9 m | 8 → 12 m |

All five spots are prepared once, hidden at zero energy, excluded from baking and use no dynamic shadows. Multiple authored auxiliary LED faces share one forward beam. This keeps the additional lighting bounded; it does not reproduce every individual LED's photometry. The model is flattened, so beam origins use the delivered headlight anchors and transformed vertex bounds, not mesh-node pivots.

Godot's [4.7 lighting guidance](https://docs.godotengine.org/en/4.7/tutorials/3d/lights_and_shadows.html) documents the Compatibility limit of eight spotlights per mesh, the cost of dynamic shadows and distance fading. The rig keeps within that vehicle budget without raising project-wide renderer limits. Other world lights can still consume the remaining per-mesh capacity. [Light3D](https://docs.godotengine.org/en/4.7/classes/class_light3d.html) defines the fade/culling controls. Emission makes a lens bright but does not directly light the road; the spots supply that contribution. [Environment guidance](https://docs.godotengine.org/en/4.7/tutorials/3d/environment_and_post_processing.html) documents simplified Compatibility glow. Sources consulted 2026-10-15 against the project's Godot 4.7.2 runtime.

## Evidence and reproduction

Godot 4.7.2 official source runtime, Windows, Ryzen 9 5900X, RTX 3090, Compatibility/OpenGL 3.3, 1440×900. The [native receipt](native/capture-receipt.json) completes twelve captures with identical before/after parked-state hashes and no engine errors. Visually inspected cases include [daytime](native/day-front.png), [sunset with all lights](native/sunset-all-lights.png), [low beams](native/lamps-low-beams.png), [auxiliaries](native/lamps-auxiliary-on.png), [brake lamps](native/rear-stop-on.png), [neon](native/side-neon-on.png), and the [illuminated ramp](native/road-beam-overview.png) against its [all-off view](native/road-beam-overview-all-off.png). The unlit midnight preset is intentionally very dark. Some native frames still omit parts of the HUD/text, as observed in RCV-37; these captures qualify vehicle/road lighting, not font rendering.

Five sequential [focused regressions](checks/verification.json) pass with **698 checks, zero failures and clean engine logs**: lighting 108, existing ground effects 91, Nitro grime/exhaust 376, Nitro activity 99 and Bisonte activity 24. The new [lighting test](../../../../app/tests/test_rcv38_lights.gd) covers per-instance/source material isolation, directions, distance fading, the five-light bound, independent braking, malformed input, unchanged-input caching, hidden-body behavior, reset persistence and English/Spanish garage routing. It also exercises normal teardown. The full repository suite and release export were not run.

| Warmed observer CPU measurement | Median time per call |
| --- | ---: |
| Unchanged controls, switches and night weight | 0.845 µs |
| Alternating all lighting inputs | 8.562 µs |

Each result is the median of five 4,000-call rounds after 500 warmup calls, alternating case order. This is a within-version state-cost comparison, not a baseline speedup or FPS claim. The retained receipt includes source hashes, switch states and counters. Night/day transitions update existing resources; stable inputs allocate no new lights or materials.

The [native harness](../../../../research/rc-monster-truck/monster-car-2/rcv38/capture_lights.gd) uses the production airfield activity, with live input, audio and physics disabled. Each capture preserves the parked float64 state at tick zero. The rear stop image supplies a brake value only to the presentation observer; it is not a driving or braking-physics experiment.

Run the native capture without `--headless`, from the repository root, with a fresh output directory:

```powershell
& .tools/Godot_v4.7.2-stable_win64_console.exe --path app --script ../research/rc-monster-truck/monster-car-2/rcv38/capture_lights.gd -- --output=C:/path/to/captures
python research/rc-monster-truck/monster-car-2/rcv38/verify.py --godot .tools/Godot_v4.7.2-stable_win64_console.exe --out C:/path/to/checks
```

Timing in this harness measures only warmed observer CPU work. It excludes GPU rendering, frame scheduling, loading and the unchanged vehicle solver. Shadowless beams can illuminate occluded geometry; these artistic light levels are not measured real-lamp photometry. Full-frame performance on other hardware and a release export remain outside this change.
