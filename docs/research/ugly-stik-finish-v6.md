# Ugly Stik · covering and surface shading (US-V09a)

2026-10-13 · US-V09a · Code in `b19f6a4` on geometry v3, appearance v4 (atlas now 2048 px) and engine v5. These are visual changes only: mass, inertia, aerodynamics, contacts and golden flights are untouched.

## Audit

The audit used the 28-image showcase (`research/ugly-stik/model-v4/capture-detail.sh`), production flight captures (close-up/chase, fixed day and golden hour) and a new bench that renders the model under the production atmosphere. Findings at HEAD `9a3dda9`:

| Area | Finding | Action |
| --- | --- | --- |
| Covering | Matte paint (roughness 0.48, specular 0.16). Under sky light the film read like flat plastic, with no sky sheen. | Glossy heat-shrink film: roughness 0.2, specular 0.5 (F0 ≈ 0.04). These are artistic estimates, not a measured BRDF. |
| Fuselage | Octagonal chamfers with flat normals, so facets showed on the underside and on the nose corners. | Each chamfer becomes a quarter arc (4 segments). It is tangent at the old chamfer ends, so the measured half-width, top and bottom remain the envelope. Normals are smooth around the section; per-bay normals along the length keep the creases at every measured station. |
| Hinge lines | With gloss, the vertical hinge-gap faces mirrored the sky as a bright, aliased dashed line along the wing, elevator and rudder. | Gap faces get their own surface: atlas colour × 0.1, roughness 1, specular 0. A narrow slot sees little sky. The tint stays below the crash chip luminance threshold, so gaps never become debris colours. |
| Fin/rudder | The 17- and 16-point traced polylines showed polygon corners close up. | A centripetal Catmull-Rom spline through every traced point (4 subdivisions). Root and hinge lines stay straight, and no point crosses the hinge line. |
| Propeller | Flat-shaded blade facets. | `SurfaceTool.generate_normals()` on the blade surface. The zero-thickness LE/TE round off. |
| Tyres | 28-segment flat facets. | 40-segment lathe with smooth profile normals (existing `_turned` helper). |
| Markings | 1024 px atlas, so cross edges blurred in close views (≈1.4 mm/texel on the wing). | `atlas_size_px` 2048 through `compile_appearance.py`. The artwork stays in its 1024 viewBox, and the editor import and runtime raster still match byte for byte. VRAM cost: about 22 MB RGBA8 with mipmaps (was about 5.5 MB). |

## Evidence

Left = before (`9a3dda9`), right = US-V09a, with the same cameras, light and frame. The [flight hashes](ugly-stik-finish-v6-evidence/flight-SHA256SUMS) and bench hashes ([before](ugly-stik-finish-v6-evidence/bench-before-SHA256SUMS), [after](ugly-stik-finish-v6-evidence/bench-after-SHA256SUMS)) are recorded.

- Flight, fixed day, close-up camera at t = 1.5 s: [pair](ugly-stik-finish-v6-evidence/flight-day-closeup-ab.png). The wing and fuselage now carry sky sheen and rounded-corner highlights. Hinge lines read as fine dark lines.
- Flight, golden hour: [pair](ugly-stik-finish-v6-evidence/flight-golden-closeup-ab.png). The difference is subtle because time-of-day lighting disables sky reflections (see limits).
- Bench (production atmosphere, engine shadows on): [tail](ugly-stik-finish-v6-evidence/bench-tail-ab.png), [nose](ugly-stik-finish-v6-evidence/bench-nose-ab.png), [hinge](ugly-stik-finish-v6-evidence/bench-hinge-ab.png), [underside](ugly-stik-finish-v6-evidence/bench-under-ab.png), [quarter](ugly-stik-finish-v6-evidence/bench-quarter-ab.png).
- Red covering pixels, mean luminance (0–255), before → after: underside 36.9 → 65.8, quarter 46.0 → 79.5, side 48.3 → 62.8. Saturation falls (mean G 1.5 → 35.6 underside) because the sky reflection adds to the red. Glossy film does the same; pilot readability is still unjudged.
- Bench repeatability: two runs at `LP_NUM_THREADS=1` gave identical hashes for all 7 views.
- Checks: `aircraft/verify_model.gd` 807 checks, 0 failed. `compile_appearance.py --check` and `compile_geometry.py --check` pass. `check_atlas.py` passes: 2048² editor/runtime byte match, and the stale SVG is rejected. `model-v3/check_dimensions.py` passes.
- `model-v4/check_mutations.py` still detects the inverted-winding mutation ("807 checks, 1 failed"). The script then aborts on its own `Parse Error` guard: its temporary app copy is not imported, so `timber.glb` (Timber track) fails to preload. The tool limitation is independent of these files and was not rerun on `9a3dda9`.

Reproduce the bench with `research/ugly-stik/finish-v6/capture.sh <new dir> [--app <other checkout>/app]`. For the flight captures, run the app with `--capture --t=1.5 --view=closeup --time_of_day=<day|golden_hour> --hud=overlays --out=<png>` under Xvfb ([TOOLS](../TOOLS.md)).

## Limits and open findings

- **Engine shadow acne (global, not Stik-specific).** With PSSM engine shadows on (the interactive default), the wing shows a diagonal crosshatch. It disappears with `OPENRC_ENGINE_SHADOWS=off`, and the glossier film makes it more visible. Sun bias settings belong to the atmosphere/world owners (`render/atmosphere.gd`, L3).
- **No sky reflections in time-of-day lighting.** `apply_state_to_environment` sets `REFLECTION_SOURCE_DISABLED` (exposure double-application, FW-23). The Home default `evening` therefore shows only the sun highlight of the film. Any fix belongs to the world track.
- The fixed hinge bevel (0.874–0.888 chord, about 25°) is traced geometry. At flight distance it can still sparkle as a thin highlight, because Compatibility has no specular antialiasing.
- llvmpipe software renders establish pixels and repeatability, not target-GPU cost or readability. The owner's 20/50/100 m orientation scoring (US-06) should be repeated with this finish.
