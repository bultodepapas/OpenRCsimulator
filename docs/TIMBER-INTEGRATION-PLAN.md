# Turbo Timber Evolution — external-model integration plan

2026-10-08 · Revision 2 · Step prefix: **TT-**

**Status: TT-00 complete; r1 delivery review TT-00-R1 in progress. Application integration has not started.**

Independent aircraft track. This plan owns Timber work; it does not change ROADMAP priorities or the other aircraft developers' plans. Research: [TT-00 evidence](research/timber-integration/TT-00/README.md), [primary sources](research/timber-integration/TT-00/sources.md), [runtime seams](research/timber-integration/TT-00/code-audit.md).

External model-author communication: [Blender aircraft delivery letter](BLENDER-AIRCRAFT-HANDOFF.md), covering Timber corrections and a reusable handoff convention for future models.

Latest delivery: [r1 review](research/timber-integration/TT-00-R1/README.md). Independent binary checks confirm a neutral 64,291-triangle GLB, 36 surfaces and 13 consistent articulation pivots. r1 supplies the proposed handoff structure; reconstruction paths, mass evidence, length and redistribution terms remain open. The v12 inventory below is historical and must not be mistaken for the current export.

## 1. Recommended delivery

Integrate the supplied **Turbo Timber Evolution** through a curated Blender → GLB → Godot pipeline and a small aircraft-specific adapter. Keep the existing custom float64 flight simulator as the sole authority for motion. The first deliverable is an isolated neutral viewer, followed by articulation; the next is a catalog preview; the third is an experimental electric airplane starting in flight. Ground handling and flap/STOL behavior follow with their own evidence.

The folder is substantially more useful than a static mesh: it contains a Blender scene with stored rig relationships (not yet evaluated), CAD geometry, per-part meshes, hinge/gear metadata and partial construction scripts. It is not a complete physical specification. The biggest implementation dependencies are **electric propulsion** and **flight flaps**, both shared capabilities whose development must be coordinated with the physics and input owners.

Baseline proposal: wheels installed, flaps up, slats off, one documented battery, no receiver stabilization, in-air start. Confirm the hardware revision before producing physics data. The manufacturer's B revision is the research reference, not an assertion that the supplied geometry depicts that exact revision. A viewer needs no decision about the battery or ESC.

Deferred: floats/water, thrust reverse, SAFE/AS3X emulation, battery thermal/degradation models, flexible wings, articulated multibody suspension, detachable damage and a general plugin system for aircraft. These are independent features, not conditions for seeing or testing this model.

## 2. Original v12 package inventory

Snapshot and hashes: [inventory.json](research/timber-integration/TT-00/inventory.json). Sizes below are decimal; counts describe the audited source, not a Godot runtime import.

| Resource | Finding | Decision |
| --- | --- | --- |
| `turbo_timber_evolution_v12.blend` | 32.5 MB; header identifies Blender 5.2; 171 objects, 130 mesh datablocks, 20 materials; seven cameras, two lights; two actions; 26 objects with drivers, ten with constraints | Primary authoring candidate. Open with a verified compatible Blender build; make a curated export copy. Preserve the original. |
| `turbo_timber_evolution_v12.step` | 41.2 MB; Open CASCADE/build123d AP214 header | Measurement/repair reference. Keep out of `res://`; do not make CAD a runtime dependency. |
| `turbo_timber_evolution_v12_step.zip` | 9.34 MB; contains the byte-identical STEP | Delivery archive only; avoid maintaining two canonical CAD copies. |
| 112 STL parts | 1,134,030 triangles; every part has a material label in `escena.json` | Fallback geometry and measurement inputs. Do not ship the complete CAD tessellation. |
| `piezas_stl_v12/escena.json` | Seven hinge definitions, six linkage records, contacts, gear pivots, component placeholders, motor angles and control limits | Convert into a versioned manifest with units, frames and evidence. Cross-check against Blender; do not treat it as app physics JSON. |
| `tren_aterrizaje_v12.py` | build123d gear construction from photo-derived dimensions; different longitudinal datum from the exported sidecar | Useful design intent and parametric repair source. Requires a pinned CAD environment and missing full-airframe context for faithful regeneration. |
| `auditoria_tren.py` | Clearance/geometry audit requiring external `.brep` cache, `ok.json` and `analisis.json` | Preserve as a reference. Missing inputs prevent reproducing its original results; it does not validate spring stiffness or real landing dynamics. |

No GLB, standalone image texture files, explicit asset license, full aircraft generator, aerodynamic polar or installed propulsion measurements were found. Blender contains only the `Render Result` image datablock; this is not an evaluated shader/export audit.

**Concrete cleanup targets:** springs contain 765,356 triangles (67.5% of all STL triangles); slat supports add 103,736. There are 26 exactly zero-area STL triangles. The Blender mesh datablocks total 1,432,290 stored faces, including studio/helper content; this count is not the runtime triangle count. Optimize the springs and small hardware before reducing the wing/tail silhouette.

**Dimensional discrepancy:** assembled STL bounds suggest 1,548.1 mm span and 1,116.2 mm longitudinal extent. The current manual gives 1,555 mm span and 1,040 mm length. Span differs by −0.45%, length by +7.3%. Establish matching endpoints, poses and revision before any scaling. Scaling the whole aircraft to fix length would spoil the span. [Manufacturer reference and limits](research/timber-integration/TT-00/sources.md)

## 3. Ownership and resource organization

Current delivery writes only this plan, its evidence/scripts and additive documentation-index entries. The supplied folder remains intact because it is the external handoff and was changing during initial inspection. TT-01 freezes its accepted hashes before creating derived assets.

Proposed paths below do not exist until their implementation step:

```text
assets/aircraft/turbo-timber-evolution/
  README.md                 # origin, license, chosen hardware/configuration
  source-manifest.json       # immutable source hashes and authoring tool identity
  source/                   # accepted original .blend, .step, sidecar, scripts
  authoring/                # curated Blender export scene; original stays intact
  geometry.json             # datum, anchors, areas, contacts, uncertainty
  export-map.json           # source names → runtime roles; exclusions
research/timber/
  tt00/                     # read-only inventory scripts delivered now
  tt02/                     # datum/measurement and coordinate checks
  tt03/                     # export/simplification script and tool lock
  tt07/                     # mass/aerodynamic derivation and --check
app/assets/aircraft/turbo-timber-evolution/
  timber.glb                # curated runtime artifact, no authoring tools needed
app/aircraft/
  timber_model.gd            # builder and pose adapter
  timber_geometry.gd        # generated numeric visual anchors
  verify_timber.gd           # model/pose contract checks
app/data/aircraft/
  eflite_turbo_timber_evolution.json  # generated, only after physics readiness
app/tests/test_timber_*.gd   # aircraft-specific verification
docs/research/timber-integration/TT-<step>/
  README.md                 # command, configuration, result, limitations
```

Timber owns only its new named paths. Shared changes stay small and pass through their owners:

| Owner | Shared integration request | When |
| --- | --- | --- |
| Aircraft/render adapter owner | Add `build`, `datum` and surface dispatch for one ID; preserve `airplane`, `propeller`, `*_hinge` contracts | TT-06 |
| Menu owner | Catalog preview/experimental metadata, selection persistence, translated status strings and eventual flap controls | TT-06, TT-10, TT-14 |
| Physics owner | Electric propulsion schema/trim/session/telemetry; Timber data; contacts; later flap dynamics | TT-08–11, TT-14 |
| Visual/audio owner | Electric sound, shadow mask, capture scenario and measured render cost | TT-12–13 |
| Test/export maintainer | Required Timber checks, per-ID packaged smoke, clean-import packaging | TT-10, TT-17 |

Do not edit existing aircraft geometry, regenerate their data, or re-record their goldens as part of Timber integration. Re-read current code and `git status` before each shared patch. Keep drafts outside `app/`; its harness parses every script. Do not move the incoming folder until references are searched and the accepted source snapshot is stable. If storage or ignore rules change, prove the resulting pipeline from a fresh clone with authoring assets acquired by the documented method.

## 4. Authoring and runtime contract

### Source selection and export

Prefer an explicit `.glb` artifact: direct `.blend` imports invoke Blender during Godot import, coupling every clean checkout and CI build to the DCC installation. Use a pinned Blender build compatible with this 5.2 file, its exporter and export settings; record the executable hash. No Blender application was available for TT-00, so successful open, driver evaluation and GLB export are still TT-01/03 work. [Godot import documentation](https://docs.godotengine.org/en/4.7/tutorials/assets_pipeline/importing_3d_scenes/available_formats.html)

Export a named aircraft collection only. Exclude `Suelo`, reflectors, studio cameras/lights, `CG_estimado`, `CG_rango_recomendado`, controller empties and presentation actions. Retain semantic pivots even when visual hardware is simplified. Do not export a sampled control animation that fights live servo poses. Preserve the detailed source for future close inspection.

Blender's driver and constraint relationships are not the runtime flight controller. Establish the neutral, uncompressed aircraft pose explicitly; rebuild the small required kinematic relationships in the render adapter. Linkage animation can be deferred after surfaces work. Reimport must never overwrite hand-authored gameplay behavior: keep that behavior in the wrapper/adapter, not generated imported scenes.

Merge fixed geometry only when it shares material and motion. Keep separate ailerons, flaps, elevator, rudder, rotor and wheels. Reduce springs to a coarse visual representation; omit hidden electronics/hardware in the flight asset. Preserve markings that distinguish top/bottom and left/right. Check smooth normals, winding, thin decals, transparency, roughness and emission under the project's Compatibility renderer. No extra real-time lights are needed merely because the source includes LED materials.

Proposed first optimization targets, **engineering budgets, not measurements**: at most 100k visible triangles and 40 aircraft mesh surfaces/draw submissions in the close-view baseline. Revise against measured silhouette loss and the project's target-machine frame budget; importer LOD alone does not remove object/material overhead. Measure actual draw calls and frame times rather than equating Blender object counts with runtime cost.

### Units, datum and pose

The sidecar/STL frame is inferred as millimetres, +X aft, +Y right, +Z up. The app model frame is metres, +X right, +Y up, +Z aft. Candidate direct CAD mapping is:

```text
model_position_m = 0.001 * (source_y, source_z, source_x)
model_axis       = normalize(source_dy, source_dz, source_dx)
```

This is a proper axis permutation, not a reflection. The Blender object translations are already in metres; its scene has metric units and scale length 1. Do not apply the CAD millimetre conversion to Blender a second time. Standard Blender→glTF conversion adds another axis mapping, so verify the complete chain with asymmetric markers rather than applying this formula blindly to GLB nodes.

The stored Blender root already has a 0.253613 m vertical offset and 0.171404 rad Y rotation (~9.82°), consistent with a posed ground presentation. Remove the presentation pose from the curated aircraft root; keep the physical gear positions in the aircraft frame. Audit parent inverse matrices and rest transforms during evaluated export. Source gear code places the wheel at X=250 mm while the exported manifest gives X=8 mm: the inferred 242 mm datum shift must be explicit before using both in one measurement pipeline.

Derive root leading edge, thrust origin, CG frame, root chord, span and wheel contacts in one `geometry.json`. Compare independent landmarks before exporting generated constants. Suggested conversion tolerances: 0.5 mm at pivots/contacts and 1 mm at external landmarks after round-trip; these prove conversion fidelity, not fidelity to the real kit. Resolve the manual-length discrepancy separately.

### Moving-part mapping

| Source role | Runtime role and behavior |
| --- | --- |
| `TurboTimber_Evolution` | neutral root named `airplane`; visual root follows simulated pose relative to the model CG |
| `Bisagra_aleron_der/izq` | `aileron_right_hinge` / `aileron_left_hinge`; retain separate rest frames with opposite dihedral components |
| `Bisagra_elevador`, `Bisagra_timon` | `elevator_hinge`, `rudder_hinge`; all moving markings and horns follow their surface |
| `Bisagra_flap_der/izq` | independent optional flap hinges; both retracted in the initial flight configuration |
| `Eje_motor` | fixed tilted shaft frame; new child `propeller` rotates around local Z for the existing render call |
| `Eje_rueda_der/izq/cola` | wheel-spin pivots aligned with the adapter's local X contract; tail spin nested under steering |

The source's `Eje_motor` parents the propeller **and motor mount/bank**. Do not rotate that entire group. Keep fixed supports outside the rotor; blades, spinner and appropriate rotating hardware belong under `propeller`. The outer frame preserves the authored down/right thrust angle while `_airplane.propeller.rotation.z` drives spin. Angles remain provisional until measured.

Add an explicit Timber branch in `AirplaneBuilder.apply_surfaces()` that delegates to `Timber.apply_surfaces()` using a documented `{node, axis, rest}` hinge record and deflections from `surface_degrees()`. The generic direct-Euler path must not handle Timber. Use axis/rest transforms like the existing Avanti adapter; avoid flattening the Timber's tilted hinges to generic Euler axes. The sidecar's aileron member lists omit horns, while Blender parents those horns to the hinges: reconcile both sources in `export-map.json`. Do not let separately exported paint/hardware remain behind as a surface moves. Instantiate two airplanes to prove that changing one pose cannot mutate the other's node state.

## 5. Physics readiness

### Data and evidence

Hardware/loadout is one explicit configuration: revision, battery type/mass/position, propeller, slats, flap state and receiver-assist state. The current manual is a baseline: 2.190 kg with the recommended 4S 3200 mAh pack, CG 60 ± 5 mm behind root LE without slats, 800 Kv motor and three-blade 11×7.3 propeller. These values are from the B revision; the older manual differs in mass and ESC. [Source comparison](research/timber-integration/TT-00/sources.md)

The package's 674 g component sum omits much of the structure. Neither that sum nor uniformly dense CAD solids gives flight mass or inertia. Build a component mass ledger, reconcile the total to the selected configuration, estimate structural distribution, and retain uncertainty bounds. Require positive-definite physically plausible inertia in the simulator's sign convention. Use the existing weighing/inertia tools when real measurements become available.

Derive wing/tail areas, aerodynamic reference chord, spans, incidence, dihedral, CG and lever arms from measured geometry with stated definitions. Treat camber/polars, drag, damping derivatives and stall behavior as estimated or borrowed unless independently measured. Geometry does not determine a trustworthy post-stall polar. Parameter sweeps must cover uncertain CG, inertia, stall behavior, drag and propulsion; keep the label experimental until independent evidence exists.

The manual expresses throws in **millimetres**, while `escena.json` stores **degrees** and a 0.7 differential. Compute trailing-edge displacement at the manual's defined station by rotating the actual hinge geometry, then solve for the angle. Do not copy 33 mm as 33°, assume the authored 22° is correct, or turn a transmitter compensation percentage directly into elevator degrees. Resolve rates/expo/mixing at one stage so an EdgeTX radio and the simulator do not apply them twice.

Every app numeric value uses `{value, unit, kind, source}`. Generated data must have a deterministic `--check`, source hashes and a derivation report. Invalid/unready data must refuse flight, never silently fall back to Ugly Stik values.

### Shared electric capability

Today the loader accepts `glow_prop` and `turbine`; it does not implement an electric powertrain. Coordinate with ROADMAP **EL1–EL6** and the physics owner rather than creating a separate Timber solver. The minimal first-flight capability is an explicit electric motor/ESC model with a stated ideal/fixed battery voltage, proper shaft load and the selected propeller. A later model may add voltage sag, capacity and cutoff. Nominal 14.8 V is not a measured loaded voltage, and Kv alone is not a thrust model.

Reuse the existing propulsion research and state contract. Measure or bound winding resistance, no-load current, propeller thrust/torque and transient response; test units, motor power balance, throttle-zero behavior and numerical convergence. The stock three-blade propeller cannot silently borrow the Stik's APC two-blade table. If a borrowed prop map is necessary for an experiment, record the mismatch and uncertainty; do not call it validation. [Existing propulsion research](research/roadmap-investigations/05-propulsion-engines-motors.md)

A Timber preview can ship while electric work is pending. A powered experimental flight depends on shared electric support passing its own tests. Do not present a glow-engine surrogate as a flyable electric Timber. Optional offline power-off analysis remains a research scenario, not the product baseline.

### Ground and high-lift stages

Use the existing contact model with **three contacts** derived from left/right main wheels and tail wheel. The two 2D `contactos_mm` entries alone are insufficient. Wheel radius and placement inform geometry; spring rates, damping, travel, friction and steering behavior need independent estimates or measurements. The crossed spring geometry does not directly supply an equivalent vertical spring constant. First use fixed visual struts and honest point-contact dynamics. Wheel spin is an inspector-only feature in the first flight/ground baseline: the live app has no wheel-angle simulation state and does not call `apply_gear()`. TT-11 must wire tailwheel steering from the same signed contact command into the render adapter, including a check against the existing taildragger steering convention; leave rolling angles zero. A later visual-wheel feature must define velocity/radius integration, pose interpolation, pause/restart behavior and state ownership before enabling rolling. Strut deflection driven by simulation compression is also deferred; neither is evidence of multibody suspension physics.

Flaps require more than `set_flaps()`: pilot/auxiliary input, deterministic servo state, traces/restart, lift/drag/pitch increments, affected strips, stall changes and downwash/tail response. Coordinate with Avanti AV-09 and the input owner. Test symmetry, flap deployment in flight, trim at each setting, go-around, stall progression and recovery. Slats need distinct geometry and aerodynamic evidence; filenames currently identify supports, not full slats. No STOL distance claim until a matched configuration is validated.

SAFE/AS3X are receiver control behavior, distinct from airframe dynamics. First acceptance uses assist-off references. A stabilized BNF flight video is not direct evidence for unassisted aerodynamic damping. Future assist work needs explicit modes and identified gains/limits; do not claim proprietary controller equivalence.

## 6. Steps and exit proofs

Each row is one bounded change, with an evidence folder named for its ID. Shared prerequisites remain owned by their existing tracks. All rows except TT-00 are planned.

| ID | Step / deliverable | Dependencies | Proof / exit condition | Status (date) |
| --- | --- | --- | --- | --- |
| TT-00 | Inventory, source research, code seams and this plan | Supplied folder | Hash manifest; static Blender/STL counts; official references; integration risks recorded | Complete (2026-10-08) |
| TT-00-R1 | Review external game delivery r1 against the handoff letter | TT-00; new r1 package | Independent GLB/metadata audit, source-pipeline review and isolated Godot import/pose evidence | In progress (2026-10-08) |
| TT-01 | Freeze accepted source and identify variant/loadout | Owner/model-author facts | Stable hashes, asset-origin/license record, exact Blender build, successful visual open, original preserved; missing CAD inputs listed | Planned |
| TT-02 | Normalize datum and measure anchors | TT-01 | Axis-marker test; span/length discrepancy resolved or explicitly bounded; hinge/CG/contact tables; no double scaling | Planned |
| TT-03 | Minimal curated GLB and isolated Godot viewer | TT-02 | Clean import without Blender installed on consumer; neutral assembled model in six views; required nodes/materials survive export | Planned |
| TT-04 | Reduce CAD detail and clean materials | TT-03 | Before/after mesh/surface counts, identical critical anchors, silhouette comparisons; no visible missing parts or coplanar flicker | Planned |
| TT-05 | Articulate controls, rotor and wheels in viewer | TT-03; TT-04 for accepted asset | Neutral/extreme/combined poses, sign and pivot checks, attached horns/markings, stationary motor mount, two-instance isolation; reimport repeatable | Planned |
| TT-06 | Register one preview ID, proposed `eflite-turbo-timber-evolution` | TT-04/05; model/menu owners | Catalog → correct builder/datum; preview cannot fly; scripted preview works; existing aircraft still resolve | Planned |
| TT-07 | Derive first mass/inertia/aerodynamic dataset | TT-02 and selected configuration | Provenance-complete generated inputs; reconciled mass; valid inertia; sensitivity report; throws measured at defined stations | Planned |
| TT-08 | Connect shared electric capability to Timber configuration | TT-07; physics EL1/state/trim readiness | Loader/trim/shaft/session tests; declared voltage/prop limits; finite state and timestep convergence; all old propulsion cases unchanged | Planned |
| TT-09 | First isolated trimmed electric flight | TT-05/07/08 | 30 s level trace, commanded turns/climb/glide, finite bounded response, repeatable restart; tolerance sheet fixed before tuning | Planned |
| TT-10 | Expose experimental in-air flight in the app | TT-06/09; menu/test owners | Home/select/fly/pause/restart/end/reselect; keyboard and fake radio; identity/hash/propulsion metadata correct; no sessions leak | Planned |
| TT-11 | Three-point ground configuration | TT-09; contact owner | Static load sum, compression/damping, taxi/steering and tailwheel render sync, touchdown, bounce/prop-strike behavior and timestep checks; rolling/strut visuals explicitly static | Planned |
| TT-12 | Electric sound and presentation completion | TT-10; audio/visual owner | Appropriate motor/prop sound, idle/stop/pause behavior; no generic combustion buzz; prop spin respects tilted frame | Planned |
| TT-13 | Pilot visibility, shadow and performance | TT-04/10; visual owner | Ground-pilot captures at 20/50/100 m, top/bottom/turn attitudes; correct extents/shadow; human orientation check and target-machine cost | Planned |
| TT-14 | Shared flight-flap capability and Timber calibration | TT-09; physics/input owners; Avanti AV-09 coordination | Input → servo → forces → render/trace agreement; restart/pause; per-setting trim, lift/drag/pitch behavior; manual displacement checks | Planned |
| TT-15 | Wheels/flaps approach and STOL envelope | TT-11/14 | Matched-loadout takeoff/landing runs, stall/go-around/recovery traces, sensitivity; no unsupported slat/float claims | Planned |
| TT-16 | Independent physical validation | TT-09; TT-15 for ground/STOL claims | Real mass/CG, propulsion data and matched flight observations; error/uncertainty table; owner radio playtest; unresolved discrepancies listed | Planned |
| TT-17 | Packaged experimental release | TT-10/12/13; export owner | Full regression suite; clean-clone import/export; packaged Timber smoke plus current aircraft; no source-folder/caches required | Planned |
| TT-18 | Optional slats/advanced configurations | TT-15/16; separately agreed scope | Geometry and data specific to each variant; independent comparisons; water/reverse/assists remain separate capability work | Deferred |

TT-07 can advance alongside the visual work after TT-02. TT-17 may release the documented flaps-up, in-air experimental baseline before TT-11/14–16. It must not advertise the incomplete capabilities. Shared integration order is **preview → electric readiness → own data/trim → experimental flight → ground/flaps → independent validation**.

## 7. Acceptance, evidence and stop conditions

**Gate TT-A — asset:** correct units and datum, curated hierarchy, signs/limits, materials, no studio content, reproducible export and reimport. Required review: model/render owner. Stop if root transforms, hinge membership or source revisions disagree.

**Gate TT-B — experimental flight:** electric support verified, dataset attributed, stable trim, input/arming/pause/restart safe, correct trace identity, no other-aircraft regressions. Required review: physics and menu owners. Stop if any successful flight depends on another aircraft's data, undocumented coefficients or silently saturated propulsion tables.

**Gate TT-C — field/physical acceptance:** matched-configuration independent data, credible ground/flap envelope, owner radio playtest and target-machine performance. Numerical tests alone do not authorize a realism claim. Owner records the result; failed or missing evidence keeps the aircraft experimental.

For each integrated step: run its narrow verifier, generated-data `--check` where applicable, then `app/test.sh`. Keep parser/runtime errors fatal and use timeouts for probes. Goldens verify repeatability; record new Timber goldens only after reviewing trajectories and never use them as physical truth. Test pause/resume and identical inputs at 30/60/144 fps through the actual session path.

Reserve external observations before tuning. Predeclare mass/CG, voltage, atmosphere, initial speed, inputs, measurement uncertainty and tolerances for each physical comparison. Prefer weight/CG and static propulsion first, then trimmed speed, glide, roll response and stall/approach. Distinguish model-derived targets from independent measurements in every report.

On a GLB/path/import change, test a fresh clone and a packaged build: neither `.godot` cache, Blender, STEP/STL inputs nor the incoming folder may be required at runtime. Inspect export contents and launch the packaged Timber ID explicitly; the existing default-aircraft smoke does not prove this one ships correctly.

## 8. Open facts to resolve during implementation

1. Which hardware revision and battery does the author intend? Are slats absent deliberately? Baseline remains provisional until TT-01.
2. What explains the length discrepancy, and what datum shift generated the sidecar? Do not rescale before TT-02 resolves this.
3. Can the full CAD generator, original photo references and prior mechanical-analysis outputs be recovered? Their absence does not block the viewer.
4. Which asset redistribution terms apply? Record them before distributing source/assets with the repository; local inspection and planning are already useful.
5. Which motor/propeller, mass/inertia and assist-off flight measurements can be collected? Missing measurements limit confidence and labeling, not honest experimental work.

**Next concrete step after the r1 review:** close TT-01 provenance/configuration and reproducible-generation gaps, resolve or bound TT-02 dimensional discrepancies, and reuse r1’s curated GLB for TT-03. Axis/name/sign adaptation belongs in the simulator adapter. Electric propulsion and flight flaps remain later shared prerequisites.
