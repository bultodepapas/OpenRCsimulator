# Ugly Stik · covering, shading, linkage, propeller, weathering, gear flex, broken propeller and contact scuffs (US-V09a–h, US-V10–V12)

2026-10-13 · US-V09a · Code in `b19f6a4` on geometry v3, appearance v4 (atlas now 2048 px) and engine v5. These are visual changes only: mass, inertia, aerodynamics, contacts and golden flights are untouched.

Scope checked 2026-10-19: the original subsections retain their dated captures, counts, runtime findings and integration failures. Current scope/acceptance belongs to the [model guide](../UGLY-STIK-PLAN.md), commands to the [asset guide](../../assets/aircraft/ugly-stik-60/README.md). The recheck below supersedes current-status readings of the old test blockers; it does not replace their original evidence.

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

## US-V09b · film over structure

2026-10-13. Owner photo C shows the red film revealing ribs and spars ([photo brief](ugly-stik-visual-photo-brief.md)). The v4 atlas only drew faint rib lines at an assumed 2 in pitch, with opacity 0.035. US-V09b removes those lines and adds a tangent-space normal map generated at load from `appearance.json` → `film_structure`.

- **Structure source:** Jensen oz1253 sheet 2, bottom view of the left wing, measured from column and row darkness profiles of the local 100 dpi raster. Main ribs (centre line in inches): W1 0, W2 1.88, W3 5.58 and 9.22, W4 12.86/16.48/20.12/23.75, W5 27.68. They are scaled so W5 equals the geometry `tip_start` (factor 0.980, the known scan-scale residual). W6 false ribs sit midway between main ribs, from the leading edge to the secondary spar.
- **Chord stations:** chord fractions are normalised to the drawing's leading edge and scallop tips, then rescaled so the drawn hinge (0.907) equals `hinge_fraction`. Leading-edge stock ends at 0.030, the secondary spar spans 0.103–0.117 and the main spar 0.292–0.310, and the 1/8 in trailing-edge sheet starts at 0.748. The sheet, the 1/4 in sheet aileron and the sheet tip stay flat.
- **Sag:** each open bay gets a sin × sin dent, inward on both skins. Its depth is 1.0 mm × (short side / 90 mm)², an artistic estimate; it gives at most about 2° of tilt. Geometry, contacts and aerodynamics are unchanged. Slopes are stored ×8 in RGB8 and the material's `normal_scale` is 1/8, which keeps byte quantisation near 0.06° instead of 0.45°.
- **Tangents:** wing, fuselage and fin/rudder covering surfaces call `SurfaceTool.generate_tangents()`. Without it, Godot fills an arbitrary orthonormal frame, so the contract compares each triangle's UV-derived dP/du with the stored tangent.
- **Hinge bevel:** the traced 4 mm, 25° bevel ahead of the aileron now shades with the adjacent skin normal; its geometry is unchanged. With glossy film its sun glint had aliased into a dashed white line in the default close-up view.

Evidence (left `b19f6a4`/US-V09a, right US-V09b; [hashes](ugly-stik-finish-v6-evidence/v09b-SHA256SUMS)): [flight close-up](ugly-stik-finish-v6-evidence/v09b-flight-day-closeup-ab.png) (faint rib bands, no hinge dashes), [bench quarter](ugly-stik-finish-v6-evidence/v09b-bench-quarter-ab.png) and [bench hinge](ugly-stik-finish-v6-evidence/v09b-bench-hinge-ab.png); both bench pairs have engine shadows off. Two scratch probes rendered one bay under grazing light from +x and from +z. In both, the half facing away from the light was brighter (28.7 vs 25.1 and 27.9 vs 26.0), so the sag renders concave on both axes. The visual contract adds the following film checks, still within `verify_model.gd` (807 checks, 0 failed): normal map size and mips, flat on fin, dorsal, ribs, trailing sheet and tip, concave and mirrored between ribs and between spars, maximum tilt below 3°, gain restored, gaps without a normal map, and tangents following U. The mutation results on a disposable copy:

| Mutation | Detected |
| --- | --- |
| Inverted sag | yes |
| No wing tangents | yes |
| No fuselage tangents | yes |
| `normal_scale` not restored | yes |
| No fin/rudder tangents | no |

The undetected case is harmless: the map is flat there, and Godot's default frame already matches dP/du on those planar faces.

## US-V09c · throttle linkage

2026-10-13. The v4/v5 carburettor lever, gas servo and pushrod were a static installation cue: the lever was baked into `engine_assembly`, and the render interface had no throttle signal.

- **Lever:** the lever is now its own node, `carburetor_throttle_arm_hinge`, turning about +X with the barrel. `AirplaneBuilder.apply_throttle(airplane, 0..1)` maps the command to ±30° around the built pose, which is half throttle. The command is `session.surfaces().throttle`; `main.gd::_render_pose` calls it after `apply_surfaces()`. Other aircraft ignore the call. It is visual only.
- **Linkage:** the throttle is a `direct` mechanism like the tail surfaces. The 12 mm gas-servo arm is solved for a constant-length pushrod (`Controls.set_throttle`). The servo station, arm and 60° travel are estimates for a generic .61.
- **Routing:** the lever moved from +X to −X. On +X the new clearance probe showed the pushrod passing through the exhaust casting between 0 and 0.8 throttle; the old static rod already did so at its neutral pose. No servo shift found in a 7-case search cleared both the cooling fins and the header. On −X there is no exhaust, fuel or pressure line.
- **Contract:** `verify_controls.gd` (376 checks, 0 failed) sweeps 21 throttle values. It checks closure, no node allocation, lever angle against command, the tip moving up and aft, and that the lever stays at least 15 mm behind the propeller plane. A clearance probe tests the rod axis and four 1.3 mm parallels against every engine and nose-gear triangle in millimetres, with a positive control (see [LEARNINGS](../LEARNINGS.md)). It caught both forced-collision mutations of the servo station. `verify_model.gd`: 817 checks, 0 failed. The render contract, catalog, propeller blur, smoke, crash, controls and projected-shadow tests pass, and the production flight capture runs without engine errors.

Evidence: [idle vs full throttle, left engine view](ugly-stik-finish-v6-evidence/v09c-throttle-idle-full.png) ([hashes](ugly-stik-finish-v6-evidence/v09c-SHA256SUMS)). Reproduce with `research/ugly-stik/finish-v6/capture.sh <dir> --view throttle --throttle 0` (or `1`).

## US-V09d · varnished wooden propeller

2026-10-13. The blades were flat, untextured matte tan (`wood`, roughness 0.64), so they read as plastic in the Home preview and in close views. They now use a varnished-wood material: roughness 0.26 and dielectric specular, an estimate. A procedural grain texture is generated once from deterministic hash noise.

- **UVs:** U runs tip to tip through the hub, because the propeller is one blank. V is the absolute chord offset (widest chord = 0..1), so the straight grain runs out at the edges toward the narrowing tips instead of converging. A first version normalised V per station and showed uniform converging "corduroy" lines (committed as `b41cf37`, refined here).
- **Grain:** irregular latewood lines with varying spacing and strength, broad heartwood bands and fine pores. The texture only darkens, within 0.79–1.0, with a mean above 0.86. `propeller_blur.gd` builds its disc from `albedo_color`, which is unchanged, so the spinning disc keeps the measured blade colour within a few percent (`test_propeller_blur.gd` 114/0).
- **Contract (`visual_checks.gd`, within `verify_model.gd` 817/0):** the grain material is in use, the texture range and mean hold, and the UVs stay in range with U following the blade side. Two mutations on a disposable copy, the texture removed and U reversed, were each detected.

Evidence (left `218361d`, right US-V09d; [hashes](ugly-stik-finish-v6-evidence/v09d-SHA256SUMS)): [propeller view](ugly-stik-finish-v6-evidence/v09d-propeller-ab.png), [blade zoom](ugly-stik-finish-v6-evidence/v09d-blade-zoom-ab.png). Reproduce with `research/ugly-stik/finish-v6/capture.sh <dir> --view propeller`.

## US-V09e · glow-oil exhaust residue

2026-10-13, at the owner's request. A flown glow two-stroke leaves oily residue streaming aft from the silencer. The muffler outlet in the engine build sits 25 mm outboard of the right (+X) side just ahead of the firewall, at y = −0.023 m, pointing aft, down and outboard.

- **Atlas space:** the fuselage sides and belly previously sampled one red texel. They now unwrap into free atlas rows 280–520 (`appearance.json` → `fuselage_unwrap`). U runs along the fuselage at about 0.5 mm/px at 2048; V is the skin arc length from the belly centre line, positive on the exhaust side, about 0.6 mm/px. The flat top keeps the dorsal region, and the fuselage end caps stay plain red.
- **Residue (`exhaust_residue`, an artistic estimate):** `compile_appearance.py` draws the residue in metres on the skin, using the measured fuselage stations and the builder's rounded-corner section. It starts at the outlet height, eases down to the bottom corner by z = 0.02 m, then runs inboard along the belly to z = 0.56 m, widening from 7 to 34 mm half-width and fading out. It has three stacked washes with user-space gradients, 70 flow streaks and 45 droplets near the outlet, all seeded (5175) so the output is reproducible. Set `exhaust_residue.enabled` to `false` and recompile for a factory-clean finish.
- **Contract (`visual_checks.gd`, within `verify_model.gd` 817/0):** the unwrap holds every side/belly vertex inside its rows, and +X skin maps to the exhaust half; a mirrored-unwrap mutation was detected. The atlas is darkened behind the outlet on +X (red channel 0.37 against 0.78 clean), while the mirrored −X point and the tail stay exact red. `check_atlas.py` still passes (2048² editor/runtime byte match, stale SVG rejected); its disposable compiler copy now includes `geometry.json`.

Evidence (left `f64900a`, right US-V09e, engine shadows off; [hashes](ugly-stik-finish-v6-evidence/v09e-SHA256SUMS)): [right side](ugly-stik-finish-v6-evidence/v09e-exhaust_side-ab.png), [belly](ugly-stik-finish-v6-evidence/v09e-belly-ab.png). Reproduce with `capture.sh <dir> --view exhaust_side` or `--view belly`.

## US-V09f–h · tail spray, hatch seams and field wear

2026-10-13, at the owner's request. These three steps follow US-V09e in the same atlas pipeline.

- **US-V09f, stab spray:** the stabiliser and elevator now use the covering atlas. Their undersides map to free rows 532–636 (`stab_unwrap`, prism-local x span and z from the hinge, about 1.1 × 1.8 mm/unit); top faces and edges sample plain red. `exhaust_residue.stab` paints a light oil film on the right underside, from the root to x = 0.21 m: a gradient wash strongest at the leading edge, 34 tapered chordwise streaks and 60 droplets.
- **US-V09g, hatch:** Jensen sheet 1 shows a 1/4 in sheet hatch from the fuselage front to 5.40 in aft, ahead of the fixed top piece bevelled into the wing saddle. The plan places the wing leading edge at 6.98 in, which matches the model's 0.176 m. The rear seam coincides with fuselage station 1, so the first top bay maps to its own region (x 914–1014, rows 646–986, about 0.4 mm/px). A 0.6 mm seam follows the front, the rear and both flat-top edges.
- **US-V09h, field wear (`belly_wear`, an artistic estimate, `enabled` toggles it):** 160 grass and soil spots thrown by the nose wheel fade aft to the main gear; 26 light scuffs run between the gears and 18 tail-strike scrapes sit at the tail end. Seed 939.
- **Contract (`visual_checks.gd`, within `verify_model.gd` 817/0):**
  - Stab and elevator undersides sample the stab rows while their tops stay plain.
  - The hatch spans the first bay, its lid triangles sample the hatch region, the rear seam is drawn and the lid centre stays clean.
  - Spray appears only on the right stab underside.
  - Wear sits behind the nose wheel, with a clean mid-belly.

  Mutations on a disposable copy (hatch mapped to dorsal, stab underside unpainted, stab spray mirrored) were each detected. `check_atlas.py` passes.

Evidence (left `f64900a`, which predates US-V09e, so the pairs show e–h together; engine shadows off; [hashes](ugly-stik-finish-v6-evidence/v09fgh-SHA256SUMS)): [stab underside](ugly-stik-finish-v6-evidence/v09f-stab-under-ab.png), [hatch](ugly-stik-finish-v6-evidence/v09g-hatch-ab.png), [front belly](ugly-stik-finish-v6-evidence/v09h-belly-front-ab.png). Bench views: `stab_under`, `hatch`, `belly_front`.

## US-V10 · landing-gear flex

2026-10-13, at the owner's request ("gear with some flexibility like the real ones"). `render/ground_gear.gd` already lifts each wheel pivot by the physics contact compression along world up. The legs stayed rigid, so the leg end poked past the hub even at the 16–23 mm static sag. The Stik's main gear is a bent 0.090 in 2024-T3 aluminium strap (Jensen sheet 1); the nose gear is a wire leg.

- **Shape:** `app/aircraft/ugly_stik_gear_flex.gd` bends each leg as a clamped cantilever whose tip follows the axle, N(t) = (3t² − t³)/2 along the leg from the fuselage clamp (0) to the axle (1). Axle hardware within 20 mm of the main axle (16 mm at the nose) moves rigidly, like the strap end clamped by the axle bolt. The main straps are now 12 segments, so the bend has interior vertices. The nose gear was rebuilt as a sprung wire in [US-V10b](#us-v10b--sprung-nose-gear), so the cantilever bend now applies to the main legs only.
- **GPU deformation:** each leg carries three relative blend shapes, unit X, Y and Z, so any attitude-dependent "world up" maps onto the leg at zero CPU cost per frame. The node runs after `GroundGearMotion` (`process_priority` 10) and never writes simulation state. Compatibility 4.7.2 renders the blend shapes, confirmed in the bench and the production scene.
- **Magnitudes:** the bend uses the physics compression unchanged: 18 mm static sag, about 0.10 m at a 2 m/s sink and 0.12 m maximum, from `jensen_ugly_stik_60.json`. That contact is the equivalent compliance of leg plus foam tyre, softened for the 240 Hz stability rule, so the drawn bend includes the tyre's share. The axle moves straight up as the contact does; a real strap also splays the track outward, which the contact model does not represent.
- **Proof:** `app/tests/test_gear_flex.gd`, 18/0, rebuilds the deformed meshes on the CPU (base + Σ weight × blend offset). It checks that the clamp is fixed, the axle follows the wheel, mid-span equals 5/16 of the tip (an analytic value, independent of the code under test), the legs are independent, an attitude-tilted contact direction is honoured, a steered nose strut follows the axle in root space, the fork rides with its wheel, release restores the built legs, and the node is ordered after GroundGear. Mutations on a disposable copy (linear shape, no rigid axle hardware, wrong process order) were each detected. `verify_model` 818/0; render contract, propeller blur, projected shadows, crash and ground-contact tests pass.

Evidence ([hashes](ugly-stik-finish-v6-evidence/v10-SHA256SUMS)): [bench, front view at 0 / 18 / 80 mm](ugly-stik-finish-v6-evidence/v10-gear-flex-0-18-80mm.png) (`capture.sh <dir> --view gear_front --gear-compression 0.08`); [production scene resting on the runway, before/after](ugly-stik-finish-v6-evidence/v10-runway-rest-ab.png) (physics compressions 0.017/0.016/0.023 m; a scratch script started `main.tscn` with `start_choice = "runway"`, because CLI launches are always airborne).

## US-V10b · sprung nose gear

2026-10-13, from the owner's reference photo of a sprung nose gear (compression spring above a collar, torsion loop, single-sided wheel). The Jensen plan (sheet 1) shows the same family: a 5/32 in wire through nylon bearings just aft of F1, a collar and steering arm inside, a torsion coil below the fuselage and a single-sided 2-3/4 in wheel. The previous model used a fixed curved wire with a two-sided fork, and US-V10 bent that wire like a cantilever. Neither matched.

- **Geometry (estimates in the photo's proportions):** a nylon bearing sits where the wire leaves the fuselage. Below it are a 55 mm, 9-turn compression spring, a collar with set screw, and a one-turn torsion coil tangent to the wire (stepping away from the wheel). Then comes a straight leg and an axle stub through the hub with an outboard collar. The whole wire steers about its own axis, so the steering pivot is on the wire and the wheel hangs 17 mm beside it, centred on the physics contact (x = 0). At the 20° steering limit the wheel swings ±5.8 mm, as on the real gear.
- **Springing:** the physics nose contact is already a spring-damper (440 N/m, 16.5 N·s/m, 23 mm static sag). The wire now telescopes through its bearing and the spring shortens by the same amount, up to its 43 mm working travel; a few-N/mm spring in series with the wire takes essentially all of it. Past solid, the leg below the coil bows aft while its ends approach (half-sine column geometry, a = 2·√(L·Δ)/π, so the axle stays on the wheel), capped at 15 mm, where linear vertex offsets still read as a round wire. Only near the soft contact's 0.12 m breaking compression does the remaining excess drive the solid spring, collar and wire up into the fuselage, as a yielding gear mount would.
- **Proof:** `test_gear_flex.gd`, 27/0, covers spring travel below free length; slide = compression up to travel; spring length = free − slide; axle = slide + bend = compression; bow = 2√(LΔ)/π against an independent leg length; the bow cap and mount excess at 0.12 m; the steering frame; and release. Mutations on a disposable copy (no bow, spring never slides, bow forward) were each detected. `verify_model` 827/0, with the spin/steering check split because the steered axle now swings about the wire axis (17 mm radius, checked). `verify_controls` 376/0, its throttle-rod probe now also covering the bearing and spring. The render contract, propeller blur, shadows, crash and ground-contact tests pass.

Evidence ([hashes](ugly-stik-finish-v6-evidence/v10b-SHA256SUMS)): [before/after at 0 and 23 mm](ugly-stik-finish-v6-evidence/v10b-nose-before-after-0-23mm.png) (left pair: `HEAD` fork design; right pair: sprung gear), [spring sequence at 23 / 50 / 80 mm](ugly-stik-finish-v6-evidence/v10b-nose-spring-23-50-80mm.png). Bench: `capture.sh <dir> --view nose_gear --gear-compression 0.023`.

## US-V11 · broken propeller after a prop strike

2026-10-14, from the owner-approved Stik audit. Since E3d2, a prop strike hid the whole `propeller` node: blades, hub, washers and nut vanished from a running engine. A wooden propeller that strikes the ground snaps near the hub, leaving two short stubs with a pale, splintered fracture on the shaft.

- **Geometry:** `ugly_stik_equipment.gd` builds a hidden `propeller_stubs` mesh with the blades' own planform and section, so the stubs share the blades' chord, twist, camber and grain UVs. The break stations are 27 % and 21 % of the tip radius. Each break runs obliquely across the chord (slant up to ±0.09 of the radius, roughness ±0.008), and five short slivers per blade (4–14 mm) stand out along the grain. The fracture faces and slivers use unvarnished wood (`d8bd8f`); the stubs keep the varnished blade finish. All of these are seeded presentation estimates, not a fracture model.
- **Logic:** `render/crash/prop_break.gd` is the shared rule. Nodes with meta `prop_strike_breaks` hide, nodes with meta `prop_strike_reveal` show, and the propeller carries `blades_broken`; `restore()` undoes it on restart. A propeller that declares neither meta still disappears whole, so other aircraft are unchanged. The director applies the rule on the flying model. The wreck applies it to its twin, which shows the same stubs after a later crash. The blur (`propeller_blur.gd`) keeps the blades hidden while broken, adds no disc, and never measures the stubs as blades.
- **Proof:** `test_prop_strike_feedback.gd` 16/0 in the production scene covers:
  - blades shown and stubs hidden before the strike;
  - after the strike, the hub and stubs visible and the blades hidden, including through the blur at 9000 and 0 rpm;
  - the wreck twin showing the stubs after a later crash, with conserved mass;
  - restart restoring the model and the twin.

  Four mutations on a disposable copy were each detected: the blur ignoring the break, the wreck forgetting it, the stubs never shown, and restart keeping the break. Also passing: `verify_model` 919/0, `verify_controls` 376/0, propeller blur 114/0, crash wreck 219/0, breakup 30/0, fracture 24/0, prop strike 24/0, soft contact 10/0, catalog 88/0.

Evidence ([hashes](ugly-stik-finish-v6-evidence/v11-SHA256SUMS)), rendered identically from a disposable copy and from `app/`: [hub close-up](ugly-stik-finish-v6-evidence/v11-broken-prop-hub.png) and [propeller view](ugly-stik-finish-v6-evidence/v11-broken-prop.png). Bench: `capture.sh <dir> --view prop_hub --prop-broken`.

## US-V12 · scuffs from soft contacts

2026-10-14, from the same audit. A soft hull contact that continues the flight (E3d1: wingtip brush, belly touch) left a mark and dust on the field only. The airframe stayed spotless.

- **Method:** `render/crash/airframe_scuffs.gd`. The Compatibility renderer has no `Decal` node, so each scuff is a small transparent mesh fitted onto the struck skin:
  - A ray from 4 cm below the contact up to 16 cm above finds the lowest visible airframe surface. Propeller, gear, wheel, light-kit and transparent meshes are skipped. Geometry3D runs in millimetres because of its epsilon.
  - A contact past a rounded tip retries up to 5 cm toward the centre.
  - A 6 × 3 grid along the slide is projected onto every nearby airframe triangle, so it follows a curved leading edge and straddles wing panels. Points past the skin's edge move halfway toward the centre until they land, so the mark narrows at an edge instead of floating past it.
  - The scuff is a child of the struck mesh, so it rides on a deflected aileron, and it is lifted 0.6 mm against depth fighting.
  - Size grows with the contact's normal speed and slide (3.5–18 cm long, 2–5 cm wide).
  - Colour follows the field surface: mown grass stain `#40541f`, rough-ground soil `#54452b`, runway abrasion `#b8b5ad`. These are estimates. A streaked procedural texture thins toward the trailing end.
  - Scuffs are capped at 24, the oldest recycled first, and restart clears them.
- **Director:** `_touch_feedback()` adds one scuff per new field contact. Lake contacts, which carry `normal_ned`, are skipped. One scuff cost 9–17 ms on llvmpipe, once per contact.
- **Proof:** `test_airframe_scuffs.gd`, 14/0, on the real Stik covers:
  - belly touch → fuselage underside within 1.5 mm, facing down, long axis along the slide;
  - wingtip → left wing underside, across panels;
  - near the leading edge, every vertex within 1 mm of the curved skin;
  - trailing edge near the tip → the aileron carries the scuff when deflected;
  - nothing away from the airframe; runway lighter than grass; fallback colour; the cap; clear.

  `test_soft_contact_feedback.gd` gains "the brush scuffs the low wing" and "restart removes the airframe scuffs". It passed 12/0 on the pre-merge tree. It now renders the pose before the director reads it, as `main._process` does. On the current `HEAD` it cannot run: `main.gd` calls a `World.set_night_options()` and a 6-argument `World.build()` that origin commit 60a2be0d never shipped in `render/world/world.gd`.

  Mutations on a disposable copy were each detected: no projection, off-skin points left floating (both by the curved-skin check), no inward retry, no cap, unoriented normal, director never scuffing, restart keeping scuffs.
- **Limits:** the crash wreck's twin is prepared before the flight and shows no scuffs. Texture and colours are not measured. Scuffs do not fade or weather.

Evidence ([hashes](ugly-stik-finish-v6-evidence/v12-SHA256SUMS)), with a fixed set of four touches (belly on grass and soil, left wing on grass and runway): [wing underside](ugly-stik-finish-v6-evidence/v12-scuffs-wing-under.png), [wing toward the leading edge](ugly-stik-finish-v6-evidence/v12-scuffs-wing-le.png) and [belly](ugly-stik-finish-v6-evidence/v12-scuffs-belly.png). Bench: `capture.sh <dir> --view wing_under --scuffs`.

## Limits and open findings

- **Engine shadow acne (global, not Stik-specific).** With PSSM engine shadows on (the interactive default), the wing shows a diagonal crosshatch. It disappears with `OPENRC_ENGINE_SHADOWS=off`, and the glossier film makes it more visible. Sun bias settings belong to the atmosphere/world owners (`render/atmosphere.gd`, L3).
- **No sky reflections in time-of-day lighting.** `apply_state_to_environment` sets `REFLECTION_SOURCE_DISABLED` (exposure double-application, FW-23). The Home default `evening` therefore shows only the sun highlight of the film. Any fix belongs to the world track.
- Rounded fuselage corners (8 mm radius) still produce a thin, sometimes dashed sun glint at flight distance. Compatibility has no specular antialiasing; FXAA or a renderer preset (VQ-06) would treat it globally.
- The stabiliser, fin, rudder, elevator and fuselage are sheeted (Jensen sheet 1: stab "1/16 sheet top & bottom" over 1/8 × 3/16 in diagonal ribs; 1/4 in sheet fin, rudder and elevator; 1/4 in sides, 1/8 in top, 3/32 in bottom). Their film therefore stays flat; only the open wing bays carry structure.
- llvmpipe software renders establish pixels and repeatability, not target-GPU cost or readability. The owner's 20/50/100 m orientation scoring (US-06) should be repeated with this finish.

## 2026-10-19 documentation recheck

Godot 4.7.2 official, native Windows; focused checks in the current working tree. Before/after hashes of the Stik model sources and render adapter were unchanged during these runs. This is not a fresh-package or uninterrupted full-suite qualification.

| Check | Observed result |
| --- | --- |
| Geometry / appearance compilers (`--check`) | Pass; source, generated geometry/data and SVG are current. |
| Model manifest / Workshop descriptor generators (`--check`) | Pass; all eight Workshop descriptors are current. |
| Atlas checker with explicit native engine | Pass in a clean temporary import project: 2048² imported/runtime pixels match; a stale SVG mutation is rejected in a disposable tree. |
| `verify_model.gd` | 919 checks pass; this includes the built control-linkage sweep. |
| `test_stik_grain.gd` / grain bake `--check` | Seven checks pass; every procedural pixel and mip byte matches the baked resource. |
| `test_gear_flex.gd` | 27 checks pass. |
| `test_prop_strike_feedback.gd` | 16 checks pass. |
| `test_airframe_scuffs.gd` / `test_soft_contact_feedback.gd` | 14 / 23 checks pass; the historical production-scene blocker above does not occur in this run. |
| Reserved-station dimension helper | Pass in a minimal disposable tree; its report writer did not overwrite the retained v3 evidence. |

All six native verifier/test scripts above exit 0 without engine errors (1,006 checks). The current scripts/data establish software behavior; the original mesh counts are dated observations, not current budgets.

Local links/anchors and literal guide paths pass. Bash and PowerShell example syntax pass. The capture runners are LF in Git but CRLF in this Windows checkout, where Bash syntax fails; disposable LF copies pass syntax and both v4 help routes. Use the documented Linux LF checkout for rendering.

Full orientation/bench renders, winding/rod mutation runs, owner readability scoring, installed measurements, export and target-GPU timing were not repeated. Those gates remain open in the model guide. This visual recheck does not qualify the active D8b-R2 pull-up/wing-polar research.
