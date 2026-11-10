# Wind-driven landscape flag and windsock integration

2026-11-10 · **Detailed implementation plan; runtime implementation has not started.**

Owner: Landscape **L15c**, coordinated with scenery **SC-18**, windsock **L15a**, graphics **VQ-06**, and UI localization. Proposed substeps `L15c-F01…F10` below stay within those existing tracks. [Track ownership](../README.md#tracks-plans-and-step-ids) · [Landscape guide](../LANDSCAPE-PLAN.md) · [Wind contract](../WIND-ATMOSPHERE-REFERENCE.md) · [Research, search ledger and Good Enemy review](../research/landscape-flag-windsocks-2026-11-10.md).

## 1. Decision and scope

Develop a **small two-dimensional CPU cloth model with GPU surface detail** as the preferred Medium/High candidate. Start with 9 × 5 visual particles, a fixed hoist, gravity, relative-wind loading, compliant constraints and bounded mast contact. Render it through one indexed, opaque, two-sided mesh. Low uses a direction-aware procedural surface with calm drape; Static disables motion. Country artwork follows the selected language, with a stable application-session Spanish selection.

This is a physically motivated **presentation model**, not validated aeroelastic cloth or aircraft physics. A two-dimensional model is preferred because different rows can lag, fold and twist independently; a single windsock-like centerline cannot represent those effects well. The existing windsock supplies the integration pattern, fabric resources and optimization lessons, not the flag's shape or coefficients.

The design must pass an early comparison against a simpler procedural candidate. The lattice earns its place through better observed motion at an acceptable measured cost. If it fails, keep the functional Low path and revise the candidate; do not relabel it as High quality or close the visual gate. No engine upgrade, compute requirement, vehicle-kernel changes, broad weather rewrite, new cloth plugin framework, general scene collision solver or runtime network downloads are proposed.

**First deliverable completed by this document:** source analysis, extensive research, alternative selection, independent challenge, pseudocode and validation design. All implementation/capture/performance tasks below remain pending. The investigation made no new visual-quality or speed measurements.

## 2. Current system analysis

### 2.1 Landscape flag

[`Prefabs._flagpole`](../../app/scenery/prefabs.gd) builds an 8 m mast and a 1.5 × 0.9 m colored sheet at local `(0.06, 7.85, 0)`. Its 10 × 4 cells have separate front/back faces: 160 triangles and 480 unindexed vertices. [`MeshKit`](../../app/scenery/mesh_kit.gd) carries positions, normals and colors, not the UV data required for a country texture. Do not add flag-specific complexity to every MeshKit/scenery batch; use a dedicated ArrayMesh builder.

The static mast joins a scenery cell. [`Scenery._motion_node`](../../app/scenery/scenery.gd) already gives the cloth a separate mesh/material under `Motion`, so replacing it need not add a visible draw. Its shader is shared with rotors/other scenery, but its material instance is separate. Existing tests expect four rotors and one flag, including Low. Preserve those contracts or update their structural assertions deliberately while retaining the same content.

[`motion.gdshader`](../../app/scenery/motion.gdshader) uses only `length(wind_vec)`, forces at least 3 m/s, adds one 1 Hz sine wave, and applies a small parabolic sag. Wind direction never changes the orientation. The placement is fixed at heading 315°, north −16 m/east 8.5 m; the generator's description assumes a southwest breeze. The material is vertex-colored, rough and two-sided through duplicated faces, without country art or cloth weave. Its normal accounts for part of the wave but not the full two-dimensional sag/deformation. The mesh AABB grows by a generic 0.6 m.

These are inspectable limitations, not newly measured visual defects. The flag currently has **no projected shadow** and native casting is disabled. The replacement initially preserves that shadow policy. Scenery-off means no flag. Green paradise does not automatically gain Club's flag; a later landscape may opt into the same renderer through explicit data.

### 2.2 Windsock and wind

[`windsock_motion.gd`](../../app/render/windsock_motion.gd) already has a 13-point centerline, seven flexible inextensible tail links, a rigid 3/8-length cage, damped yaw/flex, different inflation rise/fall times and calm gravity droop. It integrates at 120 Hz, clamps visual input speed to 40 m/s, freezes at equal time, and resets on rewind/large gaps. Its 3 kt swivel and 15 kt full-extension references do not validate intermediate extension or response times; those remain estimates.

[`windsock.gd`](../../app/render/windsock.gd) builds a 60 × 32-cell sleeve, shares [`windsock_deformation.gdshaderinc`](../../app/render/windsock_deformation.gdshaderinc) with the projected shadow, and uses existing CC0 Fabric001 maps. Prior work caches view references, bounds and repeated uploads and reuses its build grid. Preserve those gains. A one-flag task does not justify rebuilding the windsock solver or shadow architecture.

The wind service provides actual air velocity **toward** a direction in NED metres/second; meteorological “from” direction is converted by the weather owner. Mean wind, configured gusts and committed turbulence are already combined by the environment/session. Spatial weather can vary with position/height and supply shear and balanced kinematic thermals; ridge lift, terrain rotor and valley channeling are explicitly unavailable. Uniform weather should not be resampled independently for every prop. The authoritative formulas, capability restrictions, seeds and known limitations remain in the [wind reference](../WIND-ATMOSPHERE-REFERENCE.md). This feature consumes that service without altering it or adding a second gust generator.

The relevant existing calculations are:

| Wind component | Current calculation and ownership |
| --- | --- |
| Uniform mean | [`WindField`](../../app/physics/wind_field.gd) converts speed U and FROM angle θ to NED `[-U*cos(θ), -U*sin(θ), 0]`, with exact cardinal branches |
| Periodic gust | After delay, phase `p=(t-delay) mod period`; inside duration D, envelope `g=0.5*(1-cos(2πp/D))`, otherwise zero. Add `g*[-G*cos(θ), -G*sin(θ), -Gup]` to mean |
| Temporal turbulence | [`WindTurbulence`](../../app/physics/wind_turbulence.gd) uses per-axis OU recurrence `a=exp(-dt/tau)`, `x_next=a*x+sigma*sqrt(1-a²)*normal`. Session owns RNG/accepted endpoints; queries interpolate without advancing RNG |
| Spatial weather | Prepared field combines a height-dependent log profile with wall/free-air joins, smooth shear layers, finite gust events with `64*s³*(1-s)³` envelopes, seeded finite harmonic perturbations and optional thermals. It is not another copy of the legacy OU process; v5 requires legacy mean/gust/OU amplitudes zero |

These explain why a flag must consume the accepted combined vector: reconstructing gusts from settings, sampling at the aircraft instead of the pole, or adding fresh random turbulence would produce inconsistent cues.

[`field.gd`](../../app/render/field.gd) caches field windsocks and samples spatial wind at their fixed pole heads. [`main.gd`](../../app/main.gd) supplies accepted session observations through [`PresentationCadence`](../../app/render/presentation_cadence.gd): normally once per rendered frame at the last committed tick, with immediate discontinuity handling and bounded deferral. The windsock integrates the latest held sample internally. Its per-tick test tape does not prove identical runtime cloth at 30/60/144 FPS when those frames observe different samples. `World.update` can query and advance again at render time; consolidating this needs explicit ownership and regression evidence.

Important boundary: a pending weather reset can make session wind invalid. A raw spatial environment callable must not bypass that rejection merely because it can return finite values. Both flag and windsock must freeze on an invalid/unaccepted observation.

### 2.3 Settings and localization

[`SceneDetail`](../../app/render/scene_detail.gd) has Low, Medium, High and Extreme; scenery maps these to low/balanced/high. Auto uses GPU/vendor classification, not an actual performance benchmark. Resolution priority remains **1920 × 1080 first**, then 1440p/4K, then 720p compatibility. New flag settings must preserve existing override precedence and never change the field collision inventory or flight state.

[`display_preferences.gd`](../../app/app_state/display_preferences.gd) stores graphics in `user://display.cfg`. [`languages.gd`](../../app/i18n/languages.gd) has nine supported locales. Startup applies the saved language; Home and Settings ultimately call [`app_root.gd::set_language`](../../app/app_root.gd). Active language changes even if saving preferences fails. Selection must follow that active language, not whether disk persistence succeeded.

## 3. Research and alternative selection

The [dated investigation](../research/landscape-flag-windsocks-2026-11-10.md) contains the complete query ledger, inspected sources, repository findings and review dispositions. It distinguishes primary evidence, engineering inference, historical measurements and unperformed checks.

| Technique | Benefits | Costs/limits | Decision |
| --- | --- | --- | --- |
| Improved vertex-only 2-D modal surface | Very low CPU cost; bounded; easy to scale; compatible renderers | Limited local folds/contact; can remain repetitive or rubbery | Required Low path and comparison baseline |
| Existing windsock centerline adapted to a sheet | Reuses familiar integration; few values uploaded | Extruded sheet tends to move in unison; cannot represent general row-dependent cloth | Not the near-view design; acceptable far simplification |
| Coarse 2-D XPBD + shader surface | Independent row motion, gravity drape, constrained stretch and shear; static render mesh | Constraints, contacts, fixed-step history and uploads require care; local drag is not fluid simulation | Preferred Medium/High candidate, subject to early gates |
| Godot SoftBody3D | Built-in pins, collisions and Area3D wind; less custom solver code | Engine-owned tick/interpolation/lifecycle; harder to align with current accepted visual observations; separate behavior tuning | Isolated comparator if custom contact cost grows; do not switch engine physics globally |
| GPU compute cloth | Larger particle counts without CPU solving | Compatibility lacks compute; additional backend/resource/synchronization path | Rejected for this one-prop baseline |
| Baked vertex/texture animation | Predictable playback cost | Repetition; direction/gust transitions need blends; limited real wind response | Possible low-cost pose source, not main motion |

[XPBD](https://matthias-research.github.io/pages/publications/XPBD.pdf) supports compliant constraints, but does not make finite-iteration error or contacts disappear. [Small Steps](https://matthias-research.github.io/pages/publications/smallsteps.pdf) motivates bounded substeps; it does not prove the proposed timestep is sufficient. [GPU wind techniques](https://developer.nvidia.com/gpugems/gpugems3/part-i-geometry/chapter-6-gpu-generated-procedural-wind-animations-trees) motivate separating large motion and detail. [Godot's renderer matrix](https://docs.godotengine.org/en/stable/tutorials/rendering/renderers.html) excludes compute from the universal path. The [GPU Cloth Sim example](https://github.com/alien-life/gpu-cloth-sim) is a useful MIT implementation reference, but explicitly excludes Compatibility.

Reuse downloaded country artwork and existing Fabric001 textures. Do not hand-draw national emblems, create replacement weave images, or import a large demo wholesale. [flag-icons v7.3.2](https://github.com/lipis/flag-icons/releases/tag/v7.3.2) provides an MIT candidate; artwork proportions must pass the asset gate before production selection.

## 4. Architecture and ownership

### 4.1 Small components, existing owners

Proposed new files (names are planned, not existing API promises):

| Component | Responsibility |
| --- | --- |
| `app/render/flag.gd` | Build indexed cloth; own material, state, bounds and upload cache; no autonomous physics callback |
| `app/render/flag_motion.gd` | Bounded presentation-only cloth state and deterministic response for an explicit observation tape |
| `app/render/flag_deformation.gdshaderinc` | Surface reconstruction, hoist mask and bounded detail; reusable by a future shadow pass |
| `app/render/flag_fabric.gdshader` | Opaque two-sided country/cloth material and deformed basis |
| `app/render/flag_quality.gd` | Validated override and preset resolution; no weather/physics mutation |
| `app/app_state/flag_identity.gd` | Application-lifetime country selection, locale event and bounded resource ownership |
| `app/assets/flags/` | Only selected licensed runtime artwork, manifest and provenance; generated through an offline source pipeline |

Modify the scenery flag branch and field's explicit cue registration. Keep static mast batching and generic rotor shader behavior. Extend the existing field wind seam with a compact cached record containing cue kind, node, fixed observation position, and last accepted receipt. Do not create an autoload weather manager, scan the tree per frame, or convert all scenery to a generic entity framework.

Shared integration edits belong to existing owners: `app/scenery/scenery.gd`, `prefabs.gd`, `app/render/field.gd`, `app/render/world/world.gd`, `main.gd`, `app_root.gd`, display preferences and graphics UI. Verify exact caller paths before editing. Existing airship work is concurrently dirty; do not overwrite it. Add focused tests and shader UID sidecars using the pinned editor. Final accepted decisions should be recorded in DECISIONS during implementation; that shared file was already dirty during planning.

### 4.2 One accepted observation, separate upload

An observation contains `{owner_epoch, accepted_tick, time_s, accepted, uniform_wind_ned, optional_spatial_sampler}`. Reuse existing session validity semantics; the receipt is presentation metadata, not a simulation-state extension. Fixed-wing provides this at its existing cadence. Query each distinct fixed pole position once per receipt when spatial weather is active. Cache only within the field/receipt; never reuse across sessions, configurations or unequal points. The flag sample is at the hoist centre, approximately 7.40 m above its base, rather than at the aircraft or the moving free tip.

Convert NED to render once: `(x,y,z) = (east, -down, -north)`, then into the flag's fixed placement basis. Keep the hoist fixed in world space. Never negate twice for meteorological “from.” The flag and nearby lower windsock may legitimately disagree under spatial shear.

`advance` changes presentation state only. `publish` uploads the current state once for the render frame. In the committed-owner route, `World.update` publishes without a second query/integration. Legacy routes with no committed provider may explicitly observe their supplied wind before publishing. An explicit ownership flag must prevent a valid committed route from silently falling back to a preview sampler.

| Route | Initial behavior |
| --- | --- |
| Fixed-wing flight/Workshop | Accepted session sample and local spatial query; freeze on pending/invalid weather; reset epoch on session reset/restore |
| Helicopter | Use its supported supplied wind/time route; do not introduce unsupported spatial weather capabilities |
| Home | Existing fixed display clock and calm input: attractive settled drape, no invented physical breeze |
| Ground vehicle / airship | Preserve supplied presentation clock/wind; inspected paths currently supply calm. Connecting their physical weather is separate owner work |
| Capture tools | Existing scripted/fixed-time technical routes bypass Main's stepped observer and receive calm through World.update: retain an explicit calm initialization/observation path. Dynamic flag tests require reset plus pre-roll tape; an absolute screenshot time alone cannot reconstruct cloth history |
| Scene cancelled/freed | No registrations, observers, resource callbacks or state survive the field owner |

### 4.3 Cloth model

Use a **fixed vertical hoist**, preserving the existing mounting, rather than silently adding a swiveling flagpole. Five hoist particles have inverse mass zero. The remaining 40 particles span a 9 × 5 sheet. Starting constraint stencil: 76 nearest-neighbor stretch, 64 diagonal shear, 62 two-hop bend-distance constraints, 202 total before skipping pinned-only constraints. Two-hop distances are an approximate bending control, not an angular shell model.

Initial experimental integration: 120 Hz, two fixed constraint sweeps, at most **six substeps per observation**. This is a tuning hypothesis. Compare 60/120/240 Hz and two/four sweeps on controlled tapes before fixing defaults. Use a bounded speed and force policy; reject nonfinite data. The six-step cap bounds one burst to 2,424 distance-constraint evaluations plus bounded contact work, versus 24,240 for a 60-step catch-up. If more time is owed, discard catch-up debt, install a validated pose for the current wind, record a visual reset, and blend presentation over a short bounded interval. Do not slow the aircraft, accumulate debt or silently run unbounded steps. Repeated gap recovery at sustained low FPS fails Detailed qualification on that host; recommend the explicit Basic/Static control, without silently changing the user's requested mode.

Gravity acts on area-weighted particle masses. Per-triangle relative wind applies two-sided normal drag, plus a smaller bounded tangential drag to permit tension while nearly aligned. The constitutive parameters (areal mass, drag, damping and compliances) are explicit **estimated visual inputs**, calibrated in the prototype against motion references and strain limits. No FAA windsock threshold is copied into flag stiffness. Air density may be a fixed declared visual value initially; a new atmospheric query per triangle is unjustified.

Local drag alone omits wake coupling and can settle into motionless alignment. Use a small deterministic flutter excitation dependent on existing wind energy and gust change, with distinct row envelopes and phases. It is fabric detail, not additional weather, and it decays to zero in calm. Macro folds come from the lattice; shader detail must not be asked to disguise an implausible base silhouette.

**Contact scope:** static mast/finial near the cloth, not aircraft or scene collision. Point-only projection is insufficient. Test particle, edge and coarse triangle proximity against a conservative mast capsule/upper-cap proxy. Distribute triangle contact corrections using barycentric inverse-mass weights, retain a previous valid side for zero-distance ambiguity, restore pins after each sweep, and verify after the last correction. High-speed movement needs swept contact or a conservative bounded backtracking step; final-position point tests are not an anti-tunneling solution. If correction cannot produce a finite, nondegenerate, nonpenetrating pose within the work cap, retain the previous valid pose and relax to the safe Basic pose; emit a diagnostic counter. Frequent recovery fails acceptance.

No full self-collision is included initially. Persistent visible intersections, folding through the mast, collapsed faces or obvious rubber stretching fail the visual gate and require a bounded repair or model revision. A normal rotating past 90° is natural cloth motion, not by itself an inverted triangle.

### 4.4 GPU surface and material

Use one regular material uniform array of 45 positions, **not** per-instance array uniforms. Vec3 storage may pad to vec4: budget at least 720 bytes per control-point upload, plus scalar controls. Shader/mesh resources can be shared when immutable; mutable positions/material bindings belong to each flag. Use the current separate cloth draw, with one single-sided topology rendered `cull_disabled`; verify back-face normals and tangent-space handedness instead of drawing a second sheet.

Start surface reconstruction with bilinear interpolation within each coarse lattice cell. It is bounded by its control points and gives explicit derivatives. Start Low at 8 × 4 cells (45 vertices/64 triangles), Medium at 16 × 8 (153/256), High/Extreme at 32 × 16 (561/1,024). These are render grids, independent of the 45 simulation particles. Higher topology only earns value through silhouette/detail; it does not improve coarse physical folds by itself. Smooth normals across coarse cell boundaries from adjacent valid derivatives. Compare a bounded smooth reconstruction only if faceting is visible; unconstrained cubic interpolation can overshoot, stretch and enter the mast.

Fine displacement uses a hoist-zero envelope, varies over both cloth coordinates and remains under a small measured amplitude budget (initial ceiling 5 mm, further reduced near contact, in calm and at distance). Use integrated bounded phase from simulation time, not `speed * sim_clock`. Geometry and shading use the same deformation function. Derive tangents/normals from the final surface, then apply a restrained normal map. Guard degenerate derivatives with the last valid/reference basis.

Use opaque country albedo, rough nonmetallic fabric, modest specular response and filtered hems. Reuse [Fabric001](../../app/assets/landscape/windsock/PROVENANCE.json); avoid multiplying national colors by the windsock's orange/cream-specific darkening rules. Low samples only country color. Medium/High may bind the existing normal/roughness maps if their measured contribution justifies them. Fade high-frequency weave/stitches with pixel footprint; do not turn distant cloth into shimmer. No transparency, refraction, thickness geometry or extra material pass. Backlighting is optional only after renderer/lighting verification; it must not become an unlit glowing flag at night.

Define a conservative local AABB from maximum cloth reach, sag, contact recovery and fine displacement; test its transformed corners over all allowed wind directions. Do not use the old generic 0.6 m margin or a world-sized box. Leave native and projected casting off initially; a future moving flag shadow must reuse the deformation and fit the existing projector budgets, rather than adding a per-frame viewport by default.

### 4.5 Quality, LOD and disabled work

Add one graphics preference **Flag animation**: `auto`, `static`, `basic`, `detailed`. Auto follows resolved scene detail: Low → Basic, Medium/High/Extreme → Detailed with their render-grid/material tiers. Explicit Detailed on Low uses the Medium grid/material as its minimum. Basic and Static retain their cheap fixed profiles. Extreme does not automatically double solver work. Explicit preference survives later preset changes. Proposed precedence: `--flag_animation` > `OPENRC_FLAG_ANIMATION` > saved preference > Auto. Unknown values warn once and fall back to Auto. Missing key migrates without discarding other display settings.

| Mode | Allocated/active work | Result |
| --- | --- | --- |
| Static | One country-textured safe drape mesh; no cloth solver, wind registration or weave maps | Flag and pole remain visible; language changes still work |
| Basic / Low | Small mesh, a few damped heading/sag/twist scalars and two bounded waves; no particle constraints/contact solver/fabric maps | Correct broad wind direction and calm drape; lower fold fidelity |
| Detailed / Medium | 45-point state, bounded solver/contact, 16 × 8 display grid; restrained material | Full broad response at moderate shading cost |
| Detailed / High, Extreme | Same solver by default, 32 × 16 display grid, filtered close-range fabric detail | Better near-view folds and finish; no automatic extra shadow pass |

Apply explicit flag preference changes to the existing field without rebuilding the world. Prepare the needed resources, then switch atomically; free advanced state when leaving Detailed. Language changes preserve motion when dimensions agree; an aspect change uses the bounded geometry transition described below. Changing the broad SceneDetail preset retains its existing next-build semantics for unrelated scenery. The flag must not change physics/contact state during either operation.

LOD uses projected flag size, including zoom, not distance alone. Initial trial thresholds: >120 px High mesh; 35–120 px Medium; <35 px Basic mesh; ±20% hysteresis and at least 0.5 s dwell. First optimize mesh and shading while retaining one model history. Suspend the expensive model only when the entire cue is outside a conservative drawable range long enough to justify it; re-entry uses a bounded pre-roll/safe-pose blend, not hidden catch-up. Camera-dependent state cannot be called exact presentation replay. No alpha crossfade assumption: Godot's visibility fading differs across renderers. Qualify any topology switch at 1080p with camera motion.

Existing hardware Auto supplies the initial suggestion. Use the measured host results from this feature to validate Basic versus Detailed recommendations; do not add a second background benchmark or override a saved user choice. Unknown/unqualified hardware retains a cheap explicit fallback, and evidence must state which recommendation is still unqualified.

### 4.6 Country artwork and language behavior

This is a decorative mapping of supported language choices, not an inference about the player's nationality or location.

| Supported locale | Country |
| --- | --- |
| `en` | United States (`US`) |
| `zh_Hans` | China (`CN`) |
| `fr` | France (`FR`) |
| `pt_BR` | Brazil (`BR`) |
| `de` | Germany (`DE`) |
| `it` | Italy (`IT`) |
| `ru` | Russia (`RU`) |
| `ja` | Japan (`JP`) |
| `es` | Random once per application session from the admitted Spanish-speaking set |

Proposed Spanish set: `AR, BO, CL, CO, CR, CU, DO, EC, SV, GQ, GT, HN, MX, NI, PA, PY, PE, ES, UY, VE`. Admission requires available verified artwork; tests use the final manifest, not an independently duplicated list. This is a product selection set, not a claim that every country's legal language status is identical. Spain, Colombia, Mexico, Argentina and Chile are required initial members. Uniform selection from the admitted list uses a private cosmetic RNG. Cache the chosen Spanish ID until the process ends, including `es → en → es`, Home/Fly/return, landscape changes, save retries and graphics changes. Tests/captures inject a fixed cosmetic seed or explicit country. Never use the simulation/weather/scenario RNG.

Resolve only the nine supported locale codes through the existing registry. Do not expand `zh`, regional aliases or translation support as a side effect of flag selection. Unknown/future unmapped locales use the packaged US fallback until a mapping is added. A known country whose asset fails uses an existing packaged fallback and records one diagnostic; do not retry every frame.

Asset candidate: pin MIT `flag-icons` v7.3.2/commit `400f757bd23943a1a9f00dd12d895a0c668de9b0`, retain its license and record source/per-file hashes. However, its 4:3 icon framing must **not** be stretched blindly onto the current 5:3 cloth. The asset phase must choose existing artwork preserving emblem geometry and a documented physical aspect. Prefer verified natural-aspect source artwork if the icon requires redrawing; the pinned country-flags alternative and its public-domain assertion are examined in the research record. Keep hoist height 0.9 m and derive length from admitted aspect (initial envelope 1.20–1.80 m), recording any commercial-format interpretation. Country changes then atomically update length-dependent rest data and bounds with a safe visual transition; they cannot merely stretch an emblem. If maintaining constant 1.5 m length is chosen instead, document it as a commercial-format flag and validate the artwork composition explicitly. **No distorted source is accepted merely to close the asset step.**

The preferred final asset policy is natural-aspect art with a manifest-defined length; the constant-format option is only a fallback requiring review. Offline processing uses an existing pinned SVG rasterizer/import route, no runtime SVG parsing or network. Package only admitted images, mipmaps and notices. A maximum 1,024-pixel long edge is an initial ceiling, not a requirement to load 1K on every tier; begin at 512 px and verify near-view emblems. Use clamp-to-edge, correct sRGB color and no alpha unless required by the source conversion; rectangular flags should be opaque. Store per-country reverse policy: ordinary single-printed cloth mirrors through the sheet, while countries with different reverse artwork require separately verified assets. In particular, [Paraguay has different emblems on its two sides](https://www2.mre.gov.py/embapar-ecuador/index.php/noticias/14-de-agosto-dia-de-la-bandera-paraguaya?ccm_paging_p=73); admit PY only when both licensed images are available. Select the appropriate face image in the same draw; budget an additional binding/texture for asymmetric flags. Do not force US/Chinese cantons to appear on the same screen side from both directions.

Keep at most current, previous-transition and one in-flight country asset bundle; each bundle owns one shared front/reverse image or a verified two-image pair. No atlas of every country or preload-all constant. One application-level pending bundle request plus a latest desired ID bounds rapid language switching; load a required pair sequentially and commit only the complete pair. Completion must check both request generation and owner lifetime before binding. Country choice can remain cached as strings after texture eviction. Locale change is event-driven: one application notification plus initial sync after attachment, no unconditional per-frame locale polling. Load-status polling exists only while a request is active.

## 5. Detailed pseudocode

The following specifies behavior, not production API syntax. Arrays/buffers are allocated during build and reused. Rendering vectors stay under `render/`; no Vector3 simulation state is added to `sim/` or `physics/`.

### 5.1 Registration, sampling and publication

```text
finish_field_build(job):
    records = existing_windsock_records(job)
    append explicit flag records from finished scenery (none when absent/Static)
    for record: cache node, kind, fixed observation NED, unique mutable model
    publish records only when field build commits; cancelled job owns/frees all

observe_field(receipt):
    if not receipt.accepted or invalid(receipt.time, receipt.uniform_wind):
        freeze models; invalidate any sampler reuse; return
    if receipt identity already consumed: return
    clear reusable per-observation point cache
    for record:
        wind = receipt.uniform_wind
        if receipt has accepted spatial provider:
            wind = sample_once(record.fixed_position, receipt.time, receipt.epoch)
        if wind is finite and has exactly three components:
            record.model.observe(receipt.time, wind, receipt.reset)
    remember receipt identity

publish_field(render_context):
    if explicit legacy-preview owner: observe supplied preview wind/time once
    for record:
        if model revision changed: upload model state to its material
        publish needed phase/interpolation values once
    update existing windsock shadow from the same published state
    # no second weather query, solver step, tree walk or uniform readback
```

### 5.2 Bounded cloth update, forces and constraints

```text
observe(t, wind_ned, reset_requested):
    reject nonfinite time/vector without changing accepted state
    if reset_requested or t < last_observed_time: reset_epoch_and_safe_pose(t, wind); return
    if t == last_observed_time: return  # pause; no phase advance
    held_wind = clamp_length(convert_to_fixed_flag_frame(wind_ned), visual_speed_cap)
    steps_due = floor((t - epoch) / h) - step_index
    if steps_due > 6:
        bounded_reinitialize(t, held_wind); diagnostic_gap_resets += 1; return
    repeat steps_due:
        if not xpbd_step(h, held_wind):
            bounded_reinitialize(t, held_wind); return # explicit new recovery epoch
        phase[j] = modulo(phase[j] + omega_j(filtered_wind_energy) * h, 2*pi)
        step_index += 1
    last_observed_time = t
    revision += 1 only if state/phase actually changed

xpbd_step(h, wind):
    save previous valid positions AND velocities in preallocated buffers
    zero force and per-step constraint lambdas
    for particle i: force[i] = mass[i] * gravity
    for triangle (a,b,c):
        area_vector = cross(x[b]-x[a], x[c]-x[a]) / 2
        area = length(area_vector)
        if area < epsilon: skip aerodynamic force; mark geometry for validation
        n = area_vector / area
        relative = wind - (velocity[a]+velocity[b]+velocity[c]) / 3
        vn = dot(relative, n)
        normal_force = 0.5 * rho * Cd * area * abs(vn) * vn * n
        tangent_force = bounded_tangential_drag(relative - vn*n, area)
        distribute bounded (normal_force + tangent_force)/3 to triangle vertices
    for free particle:
        predicted_velocity = exp(-damping*h)*velocity + h*inverse_mass*force
        predicted = position + h*predicted_velocity
    add small wind-energy-dependent flutter excitation (zero at hoist/calm)
    repeat fixed number of sweeps, fixed constraint order:
        for distance constraint (i,j,rest_length,compliance):
            d = predicted[i] - predicted[j]; len = length(d)
            if len < epsilon: use stored safe direction or fail candidate step
            n = d/len; C = len-rest_length; alpha_tilde = compliance/(h*h)
            denominator = inverse_mass[i]+inverse_mass[j]+alpha_tilde
            if denominator > epsilon:
                delta_lambda = (-C-alpha_tilde*lambda)/denominator
                predicted[i] += inverse_mass[i]*delta_lambda*n
                predicted[j] -= inverse_mass[j]*delta_lambda*n
                lambda += delta_lambda
        bounded_mast_contacts(predicted, previous_positions, fixed_pins)
        restore every hoist coordinate exactly
    if final contacts/finite values/strain/area checks fail:
        restore previous positions AND velocities; return false
    else:
        velocity = (predicted-position)/h
        position = predicted
        return true

bounded_mast_contacts(candidate, previous, pins):
    broad phase: only cloth primitives near mast capsule/finial bound
    test points, edges AND triangles; include swept motion for tunneling risk
    if swept contact occurred even though endpoint is separated:
        conservatively stop/backtrack to time of impact and solve contact,
        or reject the step; a positive endpoint distance cannot accept tunneling
    for contact within fixed work capacity:
        q, barycentric_weights = closest cloth feature to mast proxy
        normal = normalized separation, or previous valid contact side
        C = signed_separation_from_proxy - clearance
        if C < 0:
            weight_sum = sum(inverse_mass[i] * barycentric_weights[i]^2)
            if weight_sum == 0: reject impossible pinned contact
            distribute (-C)*normal using those weights
    final pass verifies all moved features; exhausted capacity rejects step
    # finite budgets never convert an unresolved penetration into acceptance
```

The contact helper is a separate, demanding prototype gate: select/reuse a documented free geometric routine with license and test degenerate cases. It is not considered solved by this pseudocode. Capture diagnostic contacts/strain in test outputs, not an overlay added to normal product flow.

### 5.3 Surface reconstruction and inexpensive path

```text
surface(u,v):
    scaled = clamp(UV, 0, 1) * (8,4)
    cell = min(floor(scaled), (7,3)); (a,b) = scaled - cell
    # UV=1 reads last cell with endpoint weight 1, never outside the 9x5 array
    p00,p10,p01,p11 = four_control_points(cell)
    P = lerp(lerp(p00,p10,a), lerp(p01,p11,a), b)
    dPdu = 8 * lerp(p10-p00, p11-p01, b)
    dPdv = 4 * lerp(p01-p00, p11-p10, a)
    envelope = u*u * contact_clearance_mask * wind_energy * pixel_detail_weight
    detail = envelope * (A1*sin(k1*u + l1*v - phase1)
                       + A2*sin(k2*u - l2*v - phase2))
    add detail in bounded cloth-normal direction; differentiate same expression
    suppress detail where clearance/area is insufficient
    T = safe_normalize(dPdu)
    N = safe_normalize(cross(dPdu,dPdv))
    B = consistently_handed_basis(T,N)
    return P,N,T,B

basic_observe(time, wind):
    advance only a few damped heading/sag/twist values from accepted elapsed time
    retain prior heading near zero horizontal speed (no atan2 jitter)
    rotate/morph validated calm and streaming surface functions about fixed hoist
    all basis functions vanish at u=0; each varies with v
    use two bounded phase-continuous waves; strength -> zero as wind -> zero
    use mast-safe envelope and prevalidated parameter domain
    verify the transition between poses also avoids the mast; bounded backtracking
    or safe relaxation is required when a fixed-hoist reversal would cross it
    # compare calm derivatives: no flattened/zero-area hanging strip

vertex():
    evaluate active surface at UV; write VERTEX, NORMAL, TANGENT, BINORMAL
fragment():
    sample country with source-color conversion
    optionally sample filtered shared weave maps and hem mask
    orient back-face basis consistently; output opaque albedo/roughness/specular
```

No shader uses `TIME`. Integrated per-cue phases are uploaded modulo 2π and do not depend on the global clock wrapping. Invalid-weather freeze includes flutter and interpolation, not just particle positions; the flag therefore cannot use a free-running direct global-clock oscillator. Any later shared oscillator must both prove freeze behavior and use a frequency compatible with the 1,024 s period. Test variable speed and 1,023.99 → 1,024.01 s together. No per-frame random phase.

### 5.4 Quality, language and resource lifetime

```text
resolve_flag_quality(cli, environment, saved, scene_detail):
    choice = first valid explicit override, otherwise Auto
    if choice == Auto: derive Basic/Detailed from resolved scene_detail
    return validated immutable profile (mesh, material features, motion mode)

apply_profile(profile):
    if profile == installed: return
    prepare only required mesh/material resources outside hot solver loop
    transfer current visible pose or validated safe-pose transition
    atomically replace view; unregister/free solver when no longer Detailed
    retain selected country and all simulation/collision state unchanged

resolve_country(supported_locale):
    if supported_locale == es:
        if cached_spanish_id absent:
            cached_spanish_id = admitted_spanish_ids[private_rng.uniform_index()]
        return cached_spanish_id
    return explicit_locale_map.get(supported_locale, US)

on_active_locale_changed(locale):
    country = resolve_country(existing_registry.supported_locale(locale))
    if country == desired_country: return
    desired_country = country; generation += 1
    if texture already cached: commit_if_current(generation); return
    if no request active: start_one_packaged_texture_request(country, generation)
    # otherwise keep only latest desired id; do not queue every intermediate locale

on_request_poll():  # active only while one request exists
    if request still loading: return
    get result only after completed status; never block in threaded_get
    if owner gone: release result; stop polling; return
    if failed: choose packaged fallback; diagnose once
    if request id/generation matches latest desired: bind completed texture
    release obsolete result; request latest desired if necessary
    stop polling when idle; keep bounded current/transition references

on_flag_ready():
    initial identity sync even if locale changed before node entered tree
    subscribe once; never rely solely on a future notification
on_field_cancel_or_free():
    disconnect subscription; remove field registration
    release material/mesh/state and texture references owned by this field
    invalidate completion generation; no callback may bind to a dead owner
```

If an image change also changes physical aspect, prepare the new rest geometry and safe transition before committing both texture and dimensions. Initially map free-particle horizontal coordinates and horizontal velocities by the length ratio while keeping the hoist fixed, then validate contacts/strain. If that remap fails, use a bounded validated pose transition with zeroed recovery velocities and an explicit new visual epoch. At pause, commit a single safe pose and keep it frozen. Do not display new art with old UV/aspect for a frame. Country selection remains stable while loading; flight state is untouched.

## 6. Performance strategy and proposed budgets

Numbers below are **acceptance targets to test**, not predictions or measurements. Measure baseline flag, Basic and Detailed on the same build inputs, wind tape, camera and renderer. First profile one real Club flag plus its existing windsock; use synthetic 8/32-flag cases only to reveal scaling, not as ordinary gameplay requirements.

| Cost | Design and initial gate |
| --- | --- |
| CPU steady state | One observation per receipt; no tree scans/resource loads/mesh rebuilds; preallocated solver buffers. Target incremental p95 ≤0.15 ms for one Detailed flag, ≤0.03 ms Basic on the named qualification host |
| CPU hitches | Six-step cap, bounded contact count, no catch-up spiral. Target incremental p99 ≤0.30 ms; cold resource work measured separately |
| GPU | One opaque cloth color draw, no new shadow/mask pass, bounded vertex reconstruction and 1–3 material samples per fragment; up to four bindings for separate reverse art plus weave. Target incremental p95 ≤0.20 ms at 1080p on qualification hardware |
| Whole frame | Five or more alternating paired runs; report p50/p95/p99, pacing and uncertainty. No statistically meaningful >2% p95 regression in the agreed whole-flight workload; component gates also apply |
| RAM/VRAM | Three small immutable mesh tiers, one mutable state per flag; bounded country bundles, including reverse sides. Initial incremental runtime budget ≤4 MiB for country textures in use + new mesh/state, shared existing weave reported separately; reduce texture size or transition residency if a two-sided bundle exceeds this |
| Draws/pixels | Same one cloth surface in color pass; count actual depth/other renderer passes too. No default 512² mask viewport. Confirm material changes do not break existing batching |
| Loading | Compare fresh and warm Home→Fly→Home→Fly; country resource request must not cause a blocking get or unbounded request queue. Report first-use shader compilation/import separately |
| Disabled/absent | Static allocates no advanced solver/cloth maps; absent flag allocates no flag resources. Common already-loaded windsock textures may remain owned by windsock |

Use the existing [frame diagnosis](../tools/graphics.md#frame-diagnosis), [debug bridge](../../tools/debug/README.md), [ground/windsock tools](../../tools/ground/README.md), [performance harness](../../research/performance/README.md) and resource tools. Extend an existing harness only for missing flag cases after reading its contract. One rendered benchmark process per host; no concurrent research agents, imports or builds during timing. Warm up before sampling; use at least 60 s of steady-state footage per run and a separate long lifecycle soak. Record engine/source hashes, OS/driver/GPU/CPU, renderer, actual output and internal render resolution, preset/override, VSync/frame cap, camera, weather seed/tape and sample count.

Qualification tiers: real low-end/integrated Compatibility host with Basic, midrange integrated/Apple M1 Mobile with Medium, discrete GPU with High; use available actual hosts and state unavailable gates explicitly. M1 access follows the [shared guide](../tools/macos-m1.md). Test 1080p first, then higher resolutions; llvmpipe/headless results establish software behavior only. Low-end failure selects Static/Basic via explicit supported controls and requires revised recommendation evidence, not an unreported reduction of physics quality.

## 7. Implementation phases and evidence

| ID / phase | Tasks and expected result | Main risk | Verification / status |
| --- | --- | --- | --- |
| L15c-F01 — source/research | Map actual flag, windsock, weather, quality, locale and tool seams; compare primary sources | Stale graph/docs or outdated Godot claims | **Completed for planning:** dated findings and search ledger; no runtime proof |
| L15c-F02 — design/challenge | Select candidate, define budgets and independent Good Enemy review | Attractive but impractical solver, invisible lifecycle coupling | **Initial review completed:** dispositions retained; prototype gates remain open |
| L15c-F03 — baseline and assets | Stable source snapshot; baseline 1080p videos/cost; reuse licensed art; verify aspects, emblems, import and export; select reproducible processing | Icons distorted onto cloth; licensing/import or first-load issues | Asset hashes/notices, contact sheet outside Git, exported-resource test, measured baseline |
| L15c-F04 — motion prototype | Isolated Basic and 45-point candidates using same dimensions/wind/material; fixed hoist, contact, phase/strain diagnostics | Rubber motion, settled nonflutter, mast tunneling, costly correction | Calm/gust/reversal videos; numerical refinement; native costs; Good Enemy comparison before integration |
| L15c-F05 — field integration | Explicit registration and accepted observation receipt; no double sample/advance; preserve windsock caches | Pending-weather bypass, caller regression, stale node/sampler ownership | Focused wind/session/cadence tests, all-route lifecycle checks, old windsock state/shadow comparison |
| L15c-F06 — material and rendering | UV mesh, final-surface basis, restrained weave, both faces and safe bounds | Back-face lighting, seams, shimmer, uniform/sampler incompatibility | Pinned Compatibility/Mobile/Forward+ captures; close/oblique/night/far videos; no unknown shader errors |
| L15c-F07 — settings and LOD | Preference persistence/precedence; explicit cheap/static paths; bounded transitions | Allocation when disabled, rapid toggles, LOD pops, silent overrides | Settings tests/UI flow, CPU/allocation traces, collision identity across modes |
| L15c-F08 — language Easter egg | All supported mappings, private stable Spanish RNG, bounded asynchronous resource change | Rerolls, stale texture completion, save failure, restart ambiguity | Seeded selection tests, actual locale UI changes, Home/Fly/rebuild and resource unload cases |
| L15c-F09 — optimize/qualify | Paired 1080p native runs, cold/warm/lifecycle and render quality; adjust measured bottlenecks only | Microbenchmark success hiding whole-scene/pacing regression | Budget table with actual values/uncertainty, independent visual review; missing hardware marked open |
| L15c-F10 — final review/delivery | Good Enemy audit, affected CI, packaged-resource smoke, concise guide/decision updates | Combining individually passing changes into a regressed candidate | Stable candidate identity, passing required checks, accepted motion review; consolidate completed plan later |

Keep drafts outside `app/` until they parse. Each implementation phase should be a small reviewable patch. Runtime tests use the checked Godot runner; engine errors count as failures even with exit code zero. Do not reflexively run full suites per edit; shared-boundary changes and the final stable candidate determine escalation, and focused checks do not replace required CI.

## 8. Risks and mitigation

| Risk/trigger | Response and acceptance boundary |
| --- | --- |
| Cloth stays flat under steady wind | Local drag lacks wake instability; compare bounded nonperiodic-looking modal excitation and references; do not increase random noise indiscriminately |
| Rubber stretching / collapsed calm sheet | Full 2-D hoist and rest constraints; measure edge strain/triangle area; do not reduce width with wind strength |
| Reversal passes through mast | Fixed hoist, edge/triangle/swept contact and bounded rejection; no simplistic whole-sheet yaw shortcut |
| Visible self-intersections | Inspect slow-motion and silhouettes; persistent defects block near-view acceptance; bounded contact/model revision before adding an expensive general solver |
| Contact or stiff constraints spike CPU | Fixed capacities, refinement study, recovery counter; failed stability cannot be hidden by unlimited iterations |
| Gusts counted twice / wrong direction | Consume combined accepted wind once, one NED conversion, analytic direction tests; do not add meteorological noise in the cloth |
| Wind sampling changes with FPS | Compare actual owner cadence on gust/turbulence, not just regrouped identical tapes; report approximation and use bounded updates |
| Pause/rewind/clock wrap jumps | No TIME; explicit epochs, phase state, reset/pre-roll contract and 1,024 s boundary tests |
| Shader looks lit incorrectly | Final-surface derivatives, front/back tangent basis and color-space checks under sun/moon/backlight |
| LOD/quality changes pop or rebuild scenery | Same hoist/UV domain, hysteresis, prepare then switch, bounded pose transfer, no unrelated world rebuild |
| Async locale load binds old country | Generation token, single outstanding request/latest desired ID, live-owner check, bounded fallback |
| Country proportions/emblems wrong | Licensed source plus asset-specific aspect verification; no blind icon stretching; atomic dimension/art transition |
| Performance estimates mistaken | Native component and whole-scene A/B, resolution identity, no claim based on software rendering or agent consensus |
| Shared windsock regression | Keep motion equations and shadow include unchanged unless a separately evidenced defect warrants change; parity tests after sampler refactor |

## 9. Visual goals and acceptance tests

The flag must hang under gravity in calm, lift progressively, develop different folds across its height and show greater freedom near the fly edge. The hoist remains visibly attached. Gusts should tension and release the sheet with lag; a change in wind direction should produce a transient cloth response, not teleport its plane. Strong wind should not resemble a high-frequency vibrating rectangle. The material should read as soft woven fabric without plastic gloss or crawling stitches. At pilot distance it should be a readable wind/country detail that does not distract from the aircraft.

Use near views at approximately 2–5 m, the actual pilot position, medium views around 20–50 m, and distant/zoomed views at 100–300 m, with identical FOV/exposure between comparisons. Evaluate motion clips of 15–30 s, not only still images. Retain reference source/timecode and viewing conditions; research papers and screenshots do not substitute for observed real cloth footage or user visual acceptance.

| Test | Required behavior / evidence |
| --- | --- |
| Calm 0 m/s for ≥20 s | Falls into stable nondegenerate drape; no forced breeze; residual oscillation decays; hoist drift ≤0.5 mm in local numeric checks |
| Light wind 0.2/0.5/1/2 m/s | Smooth gradual response, no heading jitter at near-zero speed; Basic and Detailed both convey direction |
| Steady 5/8/15 m/s and bounded extreme input | Increasing extension/tension without unbounded amplitude; finite state, no repeated recovery; speed cap explicit |
| Gust 0→8→0 m/s and vertical component | Cloth lags and settles; no duplicated gust force; no stale heading or immortal flutter |
| 90°/180° reversal, including calm crossing | Continuous finite motion, pinned hoist, no mast traversal or global-plane teleport; diagnose max tip displacement and contact counts |
| Solver quality | Initial target p95 structural edge strain ≤5%, peak ≤10% over admitted tapes; nonzero geometric triangle/patch area relative to rest and nonsingular surface Jacobian; fixed UV area alone proves nothing. Assess limits under refinement rather than tuning to one shot |
| Spatial field | Two flags at distinct positions can differ; equal points/time reuse a sample; different height from windsock is retained; query has no weather RNG/state mutation |
| Invalid/pending/rejected weather | Both cues retain last valid state; raw sampler cannot bypass invalid receipt; accepted reset installs new epoch once |
| 30/60/144 FPS and cadence 0/default | Exact repeat for identical observation tape on same implementation; separately measure real coalesced-cadence visual error, with no unsupported cross-platform bitwise claim |
| Pause/step/reset/rewind/long hitch | Pause freezes phases; one step advances boundedly; backwards time resets; cap prevents catch-up spike; pre-roll reproduces capture state |
| Distance/zoom and LOD boundary sweeps | No frustum-edge disappearance, obvious normal seams, distracting pop or shimmer; AABB encloses final GPU surface |
| Low/Medium/High/Extreme and explicit overrides | Correct effective mode/precedence, stable texture, no forbidden allocations/collision changes; user override preserved |
| All nine languages | Correct imagery at startup and live Settings/Home change, including change while flight is paused; verify per-country mirrored or distinct reverse art |
| Spanish selection | Seeded tests cover every admitted country, always within set; stable on same-code calls, rebuilds and es→en→es; statistical diagnostic for gross bias without flaky random pass/fail |
| Rapid locale changes / failed import / failed settings save | Latest selection wins; fallback on missing art; no stalled blocking load, stale callback, reroll or crash; active locale honored despite save failure |
| Lifetime | ≥50 Home/Fly/rebuild/cancel cycles plus soak; no monotonic retained-node/resource growth after documented caches settle |
| Existing simulator | Wind/windsock/shadows, scenery counts, landscape loading, vehicle routes and collision identities preserved; representative flight state/log identity unchanged by visual settings |

Existing focused suites to inspect/use: `test_windsock.gd`, `test_windsock_motion.gd`, `test_windsock_shadow.gd`, `test_wind_world_consumers.gd`, `test_presentation_cadence.gd`, `test_scenery_build.gd`, `test_scene_detail.gd`, `test_landscape_collision_setup.gd`, `test_ui_language.gd`, `test_ui_settings_integration.gd`. Add targeted flag tests for uncovered state/geometry/locale/resource behaviors. The [windsock capture checker](../../tools/ground/README.md) supplies a useful pattern, not automatic coverage of the new flag.

Success requires all four: **convincing reviewed motion**, **bounded measured native cost**, **correct product/lifecycle behavior**, and **unchanged simulation contracts**. Physical fabric calibration, absent hardware tests and user visual acceptance remain separate open gates; software passes cannot close them. Documentation-only delivery of this plan does not require a flight simulation rerun.
