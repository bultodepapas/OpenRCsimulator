# SUN-10: implementation examples and acceptance experiments

2026-11-15 · Proposed engineering work · [Plan](../../../plans/sun.md) · [Audit](README.md) · [Sources](sources.md)

These examples make SUN-11…19 reviewable. They are **design sketches, not installed features or executed Godot tests**. Numbers marked proposed are starting points for a controlled comparison. Existing behavior, source-derived expectations, arithmetic checks, native captures and owner flight judgments remain separate evidence.

## 1. Experiment sequence

Start with E1 and the existing baseline capture routes. E2/E3 then make cloud light and visibility agree; E4/E6 tune the resulting view response. E5 is optional and follows those contracts. Instrument during the early phases. Do not wait for the final performance phase to discover that a moving camera refilters the whole sky every frame.

### E1. One cloud field in world space

**Question:** can the sky, cloud mirror, bank placement and surface shadows refer to the same cloud as the camera translates?

For a flat deck at world height `h`, an observer or receiver at `P`, and a normalized ray `d` pointing toward the sample/source, intersect the plane:

```text
distance = (h - P.y) / d.y
Q = P + distance * d
cells = positive_mod(Q.xz / scale_m + accepted_offset_cells, period_cells)
```

Here `scale_m` is metres per noise cell and the current field period is 64 cells. `accepted_offset_cells` comes from the existing accepted cloud transport, with the established sign convention. It is not generated from wall-clock shader `TIME`. The sky ray and receiver-to-sun ray can hit different points in the same field: coherence means equal results for equal positions/rays/state, not equal transmission everywhere.

The adapter must reject nonfinite inputs and nonpositive scale. A nearly horizontal ray needs the owner's bounded horizon policy, not an unbounded division or a hard-coded physical claim. A negative intersection distance is behind the observer and must not become a false cloud in front. Views above or inside a deck need explicit policy; a flat deck cannot reproduce a finite volume's interior. Keep that limitation visible until an optional volumetric backend supplies thickness.

**Worked coordinate check:** let `P = (100, 2, 200) m`, `h = 1002 m`, `d = (0.6, 0.8, 0)`, `scale_m = 500`, and offset zero. The ray travels 1250 m to `Q = (850, 1002, 200) m`, giving cells `(1.7, 0.4)`. Translate the observer 200 m along X with the same direction: the sampled cell advances by 0.4. Conversely, aim a second observer at the same `Q` and it must recover that same cell. Do not add the observer position twice when passing already-world-space receivers.

| Probe | Required observation |
| --- | --- |
| Pilot station, translated chase and onboard cameras | The cloud's position and parallax follow the declared mapping; no camera-centred shadow texture. |
| Same `Q` from two observers | Intrinsic field density at `Q` agrees. Compare CPU/GPU transmission for each ray separately: different path lengths/view angles may legitimately give different transmissions. Record floating-point tolerance near a coverage threshold. |
| Cardinal wind, zero wind, negative coordinates and period seam | Transport has the same sign and phase in sky, glare, stars, ground and bank placement. |
| 63.99 → 0.01 wrapped phase | Interpolation follows the short accepted unwrapped motion, not a sweep across almost 64 cells. |
| Ground, elevated aircraft and camera above the deck | Receiver height is honored; invalid/behind-plane intersections follow explicit policy. |
| Large coordinates or origin rebasing, if supported by the current world | No coordinate-frame mismatch between cloud caches, scene transforms and visual consumers. |

Test the visible background and lighting cubemap independently. Updating camera-position uniforms may invalidate sky radiance even if the shader branches on `AT_CUBEMAP_PASS`. Compare (a) the shared sky with bounded update policy and (b) a separate visible-cloud representation plus a slower lighting representation. Measure reflections and total cost before choosing. See sources G09/T02 and FW-81-R1.

### E2. Transmission and scattering

**Question:** can thin cloud soften the sun, a thick cloud suppress it, and the lit rim/body remain part of the same shape?

For extinction coefficient `sigma_t` in inverse metres and path length `ds` in metres, optical depth is dimensionless:

```text
tau = integral(sigma_t * ds)
T = exp(-tau)
tau_total = tau_1 + tau_2 + ...
T_total = T_1 * T_2 * ...
```

This is beam transmittance, as described in [PBRT, R01](sources.md#3-light-transport-and-production-references). A density/coverage mask can control an authored extinction model, but coverage is not a path length. Preserve `legacy` as the identity of today's `exp(-8 * opacity_proxy)` mapping while comparing a new version. CPU and GPU need the same version, parameters, field coordinates and accepted transport.

| Optical depth | Transmission | Interpretation in this illustrative model |
| --- | --- | --- |
| 0 | 1.0000 | No extinction |
| 0.1 | 0.9048 | Most direct light remains |
| 1.0 | 0.3679 | Substantial attenuation |
| 3.0 | 0.0498 | Little direct light remains |
| 0.4 + 0.7 | 0.3329 | Same result as `exp(-0.4) * exp(-0.7)` |

If a newly authored parameter explicitly means **beam opacity over a reference path**, it can define `tau_ref = -log(1 - alpha_ref)` with a finite upper bound near one. The current cloud display alpha has no such contract and cannot be converted silently. Likewise, a storm sprite's composite alpha is a visual transmission proxy unless the new optical model defines more.

For a small forward-scattering prototype, use the Henyey–Greenstein phase function with an explicit direction convention:

```text
v = normalized direction from camera to scattering sample
s = normalized direction from scattering sample toward sun
mu = clamp(dot(v, s), -1, 1)
p(mu, g) = (1 - g*g) / (4*pi * (1 + g*g - 2*g*mu)^(3/2))
```

With these definitions a sample in front of the sun has `mu = 1`, and positive `g` emphasizes forward scattering. PBRT's both-directions-point-away convention writes the equivalent denominator with the other sign; copying it without changing the vectors reverses the lobe. For the first experiment, bound `g` away from ±1 (for example `abs(g) <= 0.9`, proposed), and bound extinction, scattering albedo and accumulated radiance. The phase function is not an independent white glow to add without accounting for light transmission and scattering weight.

In the affordable 2.5D path, use a few bounded samples through the existing relief to approximate solar self-shadowing. Measure whether that creates a readable illuminated rim and shaded body while preserving the same cloud silhouette. Clearly label it an approximation: one scattering lobe and a relief surface do not reproduce full multiple scattering, cloud interiors, rainbows or all ice-crystal halos. A stylized broad halo under cirrus is an art decision, not a claim of a complete atmospheric-optics simulation.

Evaluate zero density, thin cirrus, broken cumulus, overlapping layers and dense overcast with matched settings. Increasing extinction along a fixed path must not increase its direct transmission. Cloud radiance may change differently because scattered light is a separate term. Preserve ambient sky fill when direct light falls.

### E3. Visibility, transparent clouds and composition

**Question:** do the visible source, instantaneous glare, lens ghosts and accumulated dose respond to the same obstruction model?

A first scalar approximation is:

```text
source_visibility = cloud_transmission
                  * opaque_disc_visible_fraction
                  * transparent_bank_transmission
```

Use each factor once. If the bank is already part of a unified optical field, it does not also supply an independent multiplier. Eyewear then modifies the appropriate eye response; it is not a world-shadow factor. Surface direct-light transmission is evaluated from the receiver toward the sun, not copied from the camera's visibility.

For partially covered solar discs, multiplying independently averaged factors can be wrong because their masks are correlated. The more accurate finite-sample reference is `mean(T_cloud_i * visible_opaque_i * T_bank_i)` over the same solar-disc samples, with declared disc-radiance weights if limb darkening matters. Compare a cheap centre/scalar approximation against that reference before adopting it. Record undersampling on small silhouettes instead of asserting nine samples resolve every aircraft transit.

The current storm bank is transparent and does not write opaque depth. Its actual transform, camera-facing orientation and texture-alpha convention must enter a shared visibility approximation, or a GPU visibility path must explicitly render/integrate its opacity. Opaque depth and the usual pre-transparent screen copy cannot infer it. A storm-opacity texture must not force a synchronous full-frame readback every frame.

| Candidate | Advantage | Proof needed before choosing |
| --- | --- | --- |
| Bounded render-derived CPU proxies for selected blockers | Retains current cross-renderer CPU dose state and can reuse existing skyline fallback | Compare proxy/disc masks against rendered meshes over aircraft orientation, scale and distance. Collision shapes alone are not the visual surface. |
| GPU-resident source visibility and afterimage state | Can keep depth/opacity and response close to the rendered view without a CPU readback loop | Beta-compatible integration, transparent contribution, resize/MSAA, pause/reset policy, resource lifetime, readback-free gameplay and supported-renderer fallback. |
| Small asynchronous visibility readback, only if necessary | Can bridge a GPU mask to retained CPU state | Measure latency/cost; use camera, projection, source, accepted-time and scene-generation identity; reject stale results. Reuse current readback investigations. |

Previous afterimages can persist after the sun becomes fully occluded; new dose must cease according to the chosen visibility model. Test this distinction instead of demanding instant erasure of all history. The aircraft stays rendered and simulated even when contrast is lost. Never hide its mesh or alter physics to manufacture dazzle.

Record the actual pass sequence for each renderer: opaque/sky, transparent scene, SUN veil/ghosts, tone mapping/glow, afterimage canvas, `LensStack`, HUD and menus. These labels describe contributions, not a guaranteed universal order. A Mobile/Forward+ `POST_TRANSPARENT` compositor callback is before built-in post-processing, and resolved color/depth must be requested when required by MSAA. Compatibility needs its supported presentation path. See G07/G08 and T03/T04.

### E4. Dazzle, dose and short recovery

**Question:** does a brief solar crossing reduce local aircraft visibility convincingly and then allow prompt reacquisition at different frame rates?

The existing constant-input model is:

```text
dD/dt = e * (1 - D) / tau_on - D / tau_off
k = e / tau_on + 1 / tau_off
D_equilibrium = (e / tau_on) / k
D_next = D_equilibrium + (D - D_equilibrium) * exp(-k * dt)
```

`D` is bounded dose, `e` is a nonnegative game-relative illumination input, and both time constants are positive. Sanitize nonfinite values before evaluation and retain the existing pause/seek/restart policy outside this equation. This is the exact solution for **constant `e` during the interval**. It is not a reason to add another simulation tick or to claim exactness when a moving sun image changes `e` inside the frame.

With no new exposure, `D(t) = D(0) * exp(-t / tau_off)`. Today's `tau_off = 8 s` leaves 36.79% of the initial dose after 8 s; a 90% reduction takes about 18.42 s. Perceived detail recovery also depends on the patch size, blur, maximum masking, background and aircraft contrast. Changing only the named time constant is not a complete gameplay tuning method.

**Proposed moving experiment:** define one continuous camera-relative solar trajectory, crossing ±5° at 10°/s, followed by a 40° look-away and recovery. The “look-away” is a continuous bounded camera motion, not a history reset. Sample this same time-defined path at 30, 60 and 120 fps, plus an irregular sequence with one declared 100 ms interval. Repeat with the same moving opaque blocker and cloud state. Preserve angular/FOV conventions and log actual accepted times.

Compare peak dose, angular position of retained patches, integrated masking and time to the same contrast-recovery threshold. A provisional numerical screen is ≤5% relative change in peak dose/masking integral where the signal is appreciable and ≤0.2 s recovery-time difference; report absolute error near zero. Freeze or revise these limits from the first baseline, rather than silently loosening them after a failure. Use an oversampled trajectory as a convergence reference, not as a human-perception oracle. If the material error is in input sampling, evaluate bounded presentation-history integration and account for its cost.

Pair actual aircraft images with effects-off/hidden-model captures so sky brightness changes do not masquerade as recognition loss. Measure contrast relative to the matched effects-off image and report the aircraft's projected pixel size. A proposed normal-play target is recognizable detail within roughly **2–4 s after a brief crossing**; choose the numerical contrast threshold before the comparison and confirm it in SUN-08 owner flights. This is gameplay tuning, not a medical exposure/recovery model. Retain the current stronger profile as a comparison and provide separate Reduced/Off controls.

Specify the aircraft trajectory as well as the sun/camera trajectory: include a controlled case where the projected model overlaps the retained patch after looking away, and an off-patch control. Otherwise apparent “recovery” may be immediate simply because the target moved out of the affected region. The controlled fixture isolates the effect; a repeatable production flight separately establishes tracking/reacquisition without changing the aircraft's simulation to manufacture the result.

Pilot-eye views use the local veil and temporary afterimage. Camera/lens views use their own veil, starburst and ghost behavior without inheriting pilot afterimages. Camera cuts, FOV changes and returning to pilot view need an explicit history policy rather than accidental reuse of a texture from another view.

### E5. Optional cloud-aware shafts

**Question:** does light appear in haze only where both the viewing path and sun path allow it, at an acceptable full-frame cost?

An illustrative single-scattering integral is:

```text
L_shaft = integral_along_view(
    T_view * sigma_s * phase * L_sun * T_sun * visibility_geometry * ds
)
```

`T_sun` must include cloud extinction from each scattering sample toward the sun. A shadow sampled only where the ray reaches the ground is not a substitute. `T_view` accounts for extinction from the sample to the camera. Keep geometric shadow visibility distinct from cloud transmission so neither is counted twice.

Native Forward+ volumetric fog supplies a useful nearby scattering system, but its public density/scattering controls do not automatically insert the custom sky's cloud light-path mask. First establish whether a supported fog/material integration can express the required term; otherwise compare a bounded custom scattering pass. Do not promise this as a single FogVolume checkbox. Any temporal reprojection must be inspected under quick RC pans, aircraft transits and camera cuts.

Required negative controls: zero scattering density, zero source energy, complete cloud blockage along the light path, and an opaque foreground blocker. Inspect the relevant path/region in each; a blocked region must not glow simply because the sun's screen position remains nearby. Compare cloudy and clear volumes, offscreen source support, low sun, and weather transitions. Use SUN-16's provisional budget and retain a complete effect-off fallback. This experiment is not required for SUN-11…15 to deliver a better sun.

### E6. Exposure, glow and highlight shape

**Question:** can the sun feel brighter and the clouds retain shape without a doubled exposure loop or an oversized white screen?

For a scene-linear candidate, the intended radiance relationship is conceptually `L_visible = L_scene + L_veil`, followed by the chosen exposure/tone response. The current calibrated overlay uses a display-oriented contrast mapping; it must be compared, not simply added again as a second veil. Existing emissive, sky and direct-light units are not automatically physical lux/nits.

Keep `World.adapt` as the baseline exposure owner. A Forward+ native-exposure experiment must disable or replace its overlapping adaptive contribution, and coordinate the exposure signal consumed by SUN and other presentation code. `CameraAttributesPractical` avoids the geometry overrides of a camera's Physical attributes. Verify zoom, clipping and aspect behavior explicitly.

Capture a clear disc, thin cloud edge, dark aircraft silhouette, bright aircraft paint, lake reflection, lit runway marker and HUD in the same comparison. Record the scene-linear diagnostic values where available and the final displayed result. Calibrate glow separately on Compatibility, Mobile and Forward+ because their available controls/range differ. A brighter halo is accepted only when it improves the chosen image and preserves local contrast away from the sun; no single “bloom intensity” is proposed as universally correct.

## 2. Existing tools and runnable entry points

Use the [tool index](../../../tools/README.md), [graphics guide](../../../tools/graphics.md) and each tool's current contract. The commands below illustrate **future implementation verification** and were not executed for this documentation change. A fresh checkout needs the pinned engine's normal resource import before standalone scripts. The text-only research checkout is not a qualified rendered workspace.

Submit compatible independent headless checks through the existing [test-pool admission route](../../../../tools/testqueue/README.md#mcp-checked-batches). For example, pass these argument objects to the named tools, replacing the example request ID with a fresh stable ID for the candidate:

```text
sim_test_launch: {"request_id":"sunoptics_sun10_example","jobs":[{"script":"res://tests/test_sun_optics.gd","require":["0 failed"],"timeout":120}]}
sim_test_status: {"request_id":"sunoptics_sun10_example"}
```

Keep the candidate stable until the source is frozen; retain the request and checked receipts. Use `sim_test_recover` with the same ID after an interruption, not a new launch that duplicates uncertain work. The default preserves the caller's OS; select another platform only for the intended reviewed coverage. When MCP is unavailable, use the guide's `testctl.py pool` CLI. The [checked runner](../../../tools/shared.md#one-godot-script) remains the underlying verdict/log contract; it is not an admission bypass for a shared host.

The current landscape capture script accepts explicit dimensions and existing case names. Run it on an owned native graphical session, using a fresh absolute output directory; do not add `--headless` to this frame-post-draw capture. This postcard compares a fixed aircraft target, not moving-flight acceptance. The contrast checker requires at least **six complete angle groups**, so the example generates all four controls at six angles retained in the [historical model check](../SUN-01-05/day-glare-contrast.json). That history does not predict a pass on the new engine/host:

```sh
mkdir -p "$PWD/tmp"
sun_capture_dir="$(mktemp -d "$PWD/tmp/sun-baseline-1080p.XXXXXX")"
sun_cases=""
for sun_angle in 1 2 3 5 8 12; do
  for sun_suffix in "" _off _hidden _hidden_off; do
    sun_cases="${sun_cases:+$sun_cases,}glare_offset_${sun_angle}${sun_suffix}"
  done
done
python3 tools/godot/run_checked.py --timeout 600 -- \
  "$(app/get-godot.sh)" --path app --audio-driver Dummy \
  --script res://tests/capture_landscape_upgrade.gd -- \
  --out="$sun_capture_dir" --width=1920 --height=1080 --frames=120 \
  --cases="$sun_cases"
"$(app/tests/visual-env.sh)" tools/landscape/glare_contrast.py "$sun_capture_dir"
```

Check the retained report for engine, dimensions and requested cases, and inspect the checked verdict before interpreting the reducer. **At the audited commit the capture script hard-codes its `renderer` field to `gl_compatibility`.** That field cannot prove the effective renderer, especially on Mobile/Forward+. SUN-10 must retain an independent runtime renderer receipt or first repair and qualify that diagnostic; see audit L. Select High through the existing [profile launcher](../../../../tools/graphics/README.md), then verify the effective renderer rather than assuming a profile name proves Forward+. Reuse the [debug bridge](../../../../tools/debug/README.md) for production-flight setup, frames, GPU views and exact session identity.

| Concern | Existing seam to extend only when implementation requires it |
| --- | --- |
| Optical math and CPU mirror | `app/tests/test_sun_optics.gd` |
| Flight integration, pause, lens, restart and eyewear | `app/tests/test_sun_flight.gd` |
| Static skyline and known rendering exclusions | `app/tests/test_sun_skyline.gd` |
| Moon handoff and night regression | `app/tests/test_world_moon_glare.gd` |
| Transport, copied caches and disabled consumers | `test_cloud_transport.gd`, `test_cloud_shadow_map.gd`, `test_cloud_cache_disable.gd` under `app/tests/` |
| Time updates and legacy fixed sky | `test_time_of_day_render_update.gd`, `test_sky_render.gd` under `app/tests/` |
| Pixel contrast and obstruction fixtures | `tools/landscape/glare_contrast.py`, `verify_glare.py`, current capture script |
| Cloud capture, receiver shadows and full-world parity | [Atmosphere tools](../../../../tools/atmosphere/README.md), [shadow tools](../../../../tools/shadows/README.md), [world tools](../../../../tools/world/README.md) |

The current contrast checker mirrors the model's expected ratio. Passing it confirms that scoped contract, not the independent correctness of the optics or comfortable player tracking. Its reported CPU strength does not include the shader's additional dynamic-depth visibility. Investigate closer partial-disc transits as E3 mask experiments with suitable visibility diagnostics, rather than assuming this unchanged oracle resolves them. Confirm expected case coverage: a verifier that checks only present images must not turn a missing case into a pass. SUN-10 should add diagnostics at these seams only where necessary, instead of creating a second capture framework.

## 3. Evidence and measurement contract

Every accepted comparison should retain the commit and worktree/diff identity, exact engine string, OS/driver/GPU, effective renderer and graphics profile, preset/overrides, output and internal pixel dimensions, scaling/reconstruction, AA/MSAA, aircraft/material, field, camera/FOV/aspect, accepted time, weather seed/layers, cloud optical-model version/transport and effect controls. Include screenshots or sequences, original reports and the command/configuration used. Hash source-sensitive inputs with the established tool's receipt format.

Use equal accepted camera/flight trajectories for baseline and candidate. Do not compare unrelated free flights or a static postcard with a live-physics scene and attribute the whole difference to the shader. Record source angle, per-factor transmission, dose/mask, exposure and receiver-light diagnostics when testing those factors. Diagnostic runs and clean timing runs are separate.

Follow the [plan's sampling and budgets](../../../plans/sun.md#11-acceptance-and-performance): 1080p first, whole-frame cost as well as incremental CPU/GPU cost, burst statistics and native sustained evidence. Averages alone hide stalls. Headless/llvmpipe evidence is useful within its scope and does not qualify native Metal/Vulkan/OpenGL hardware. Existing physics/replay checks must establish that presentation settings do not change accepted simulation results when runtime changes land.

## 4. Acceptance matrix

All cases below are **pending**. Case numbers are local evidence labels, not additional plan ownership IDs. Start with a named representative field/aircraft, then extend only to resolve concrete material, platform or visibility risks.

| Case | Controlled scene / action | Acceptance evidence |
| --- | --- | --- |
| 01 · Clear sun | Noon and low sun; pilot/chase; fixed angular size at two FOVs | Coherent disc/aureole, monotonic local veil, stable projection and no duplicate exposure. Keep the calibrated Day pair. |
| 02 · Thin and thick cloud | Cirrus, broken cumulus, overlapping layers, overcast | Declared transmission model agrees across CPU/GPU; clear/thin/dense direct-light order; rim/body shape without a sharp sun leaking through an opaque region. |
| 03 · Translated observer | Pilot station, chase translation and altitude changes under fixed weather | E1 world-space agreement; reflection/sky costs recorded; above/inside-deck limitation explicit. |
| 04 · Transparent storm bank | Sun behind actual lobe centre, edge and gap | Alpha/transmission reference and view state match; attenuation is applied once; no depth-only claim of transparency coverage. |
| 05 · Moving aircraft transit | Repeat one continuous crossing at 30/60/120 fps and a declared hitch | E3 disc-mask and E4 dose/recovery comparisons; aircraft drawn throughout; difference bounds and limitations reported. |
| 06 · Tracking contrast | Dark/light paint, small/large projected target, brief crossing then look-away | Matched off/hidden-model images, dose and recovery curve, projected pixels, normal/Reduced/Off controls, owner reacquisition judgment. |
| 07 · Terrain and foliage | Partial tree/ridge obstruction, near horizon, source enters/leaves screen | Correct declared skyline/depth fallback; no unjustified new dose under complete blockage; no stale view result or abrupt support cull. |
| 08 · Lens and effect stack | Chase/orbit; source offscreen while ghosts still overlap view; rain/impact/grime; menus | Stable ghost support; no pilot afterimage in lens mode; correct canvas/HUD order and no unnecessary extra screen copies. |
| 09 · Direct light and receivers | Moving cloud over ground, runway, grass, aircraft, buildings and water | Inventory says which receivers are implemented; directional diffuse/specular response coherent; ambient/local/emissive light preserved; low-sun cue policy explicit. |
| 10 · Time and weather | Noon → golden hour → twilight → moon; accepted accelerated time and weather edit | Continuous source/color/exposure handoff; no one-frame cloud phase change, flashing shadow or unjustified history reuse. |
| 11 · Lifecycle and settings | Pause/resume, zoom, aspect/resize/MSAA, camera switch, replay seek, restart, new seed, setting preview/revert | Defined history policy; stable physics/replay; saved override preserved; no stale cache publication or growing GPU allocations. |
| 12 · Optional shafts/backend | Cloud openings, complete blockage, zero density/energy, fast pan, active weather | E5 negative controls; measured reprojection/trailing; explicit resource/budget/fallback result; advanced branch can be rejected. |

For scalar transmission, require finite values in `[0, 1]`. For a fixed extinction path, require monotonic attenuation and multiplicative layering. For complete opaque coverage, the sampled direct visibility should be zero and no new source dose should enter through that covered path; partial/undersampled cases carry declared error. Clear-air and zero-effect controls must not acquire a spurious dark overlay. These are numerical invariants, not a substitute for inspecting flight sequences.

SUN-19 closes only the cases actually implemented and qualified on the named supported routes. Retain unresolved hardware/owner gates explicitly. Optional SUN-16/17 experiments can finish with a documented rejection while the core improvement ships.
