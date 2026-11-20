# Imported aircraft quality: audit and phased plan

Status: active plan, created 2026-11-20; progress in [§7](#7-progress), next improvements in [§8](#8-re-audit-after-iaq-03b-and-next-improvements-2026-11-20). This file owns `IAQ-00` through `IAQ-08`. It audits how imported aircraft (Creator sources: generic STL/GLB, ClearView conversions and the new Phoenix import) look, fly, control and present in OpenRC today, and orders the work that turns them into first-class aircraft. Format-specific work stays with its owners: [Aircraft Creator](aircraft-creator.md) (AC), [ClearView](clearview-aircraft-import.md) (AC-CV), [Phoenix](phoenix-aircraft-import.md) (AC-PX). This plan sequences and measures their shared player-visible quality; it does not reassign their steps.

## 1. Method and evidence limits

| Evidence | What it covers |
| --- | --- |
| Static code audit (two independent read-only reviews plus lead spot checks, 2026-11-20) | Flight path, compiler domain, packages, bindings, effects gating, materials, shadows, cameras; file:line references below |
| Local Phoenix 5.5.k corpus (owner install) | 220/220 models convert and pass Creator admission; domain fit of 116 fixed-wing models measured from decoded definitions |
| Blender 5.2 renders of converted GLBs | Easystar, J-3 Cub, Fokker Dr.I, Beech 58, Blade Nano CP X: geometry, metric scale, colour and decal orientation |
| Focused tests | `test_creator_phoenix_readers` 84/0, `test_creator_language`, `test_creator_clearview_ui` |

**Not done:** a live rendered flight audit. `debugctl launch` refuses `app/.godot` because it is a junction on this host, and the MCP `sim_launch` did not respond for 30 minutes. IAQ-00 restores that path first. Static reading is not flight evidence; nothing below claims measured handling, frame time or physical realism.

## 2. Audit scorecard

Grades: **A** player-ready, **B** usable with visible gaps, **C** placeholder or partial, **D** missing. The grades are the 2026-11-20 audit baseline; rows marked *updated* reflect delivered steps, and [§7](#7-progress) holds the evidence.

| Area | Grade | Current state | Evidence |
| --- | --- | --- | --- |
| Import coverage (Phoenix) | A | 220/220 stock models decode, convert and are admitted in ≤1.5 s; frame, metres and datum pre-filled | [stock formats](../research/aircraft-creator/phoenix-stock-format-2026-11-20.md) |
| Geometry and textures | B | Correct shape, scale, colours and decals. GEO normals are kept. Unindexed triangle lists (3× vertices); shared simulator textures (glass, white, rotor disc) are absent | `phoenix/glb_writer.gd`; renders |
| Materials | C | Phoenix: constant roughness 0.6, metallic 0, opaque, single-sided; GEO specular/opacity parsed but unused, so canopies render opaque. ClearView maps opacity (`alphaMode BLEND`), shininess and emission | `glb_writer.gd:92-106`, `clearview/converter.gd:588-616` |
| Texture filtering | C | Imported GLBs get engine defaults; stock paint sets anisotropic mipmapped filtering explicitly | `visual_builder.gd` (no filter calls); `vehicle_paint.gd:213` |
| Moving parts | D (Phoenix) / C (others) | Bindings are manual. Phoenix nodes have no pivot transform, so a bound surface turns about the model origin. Binding v1: four control roles plus one propeller, at most two parts per role, cardinal axis only | `visual_parts.gd:17-22`; `visual_builder.gd:13-17`; `glb_writer.gd:274` |
| Flight physics | C | One estimated conventional package: borrowed UltraStick25e coefficients plus closed forms; single tractor/pusher electric prop; `gear=locked_up`, `flaps=not_simulated`; airborne/hand-launch starts only; `gdscript_reference` backend; AC-12 numerical gate not passed | `compiler.gd:394-403`, `trial.gd:35`, `packages.gd:326`, [AC plan](aircraft-creator.md) |
| Domain fit (Phoenix) | D | At most 28 of 116 fixed-wing models (21 trainer, 7 park-flyer) pass the wing-level domain checks; failures: taper (58), mass (57), span (51), wing loading (49), aspect ratio (29), propulsion (22). Tail and static-margin checks would lower the count further | `airframe-conventional-*-estimated-v1.json`; corpus measurement |
| Phoenix flight data use | B (*updated*) | Packages derived per model from decoded weight, CG, airfoil polars, surfaces, propellers and jet thrust; layout from the decoded wing, tails and hub. Rates/expo, inertia factors and tuning stay notes; section moment, side force and battery stay borrowed | `phoenix/physics.gd`; [decision](../DECISIONS.md#phoenix-aeroplanes-fly-on-packages-derived-from-their-own-data) |
| Controls and feel | C | Throws and servo time exist; no rates, expo or dual rate for Creator records (radio-side rates still work) | `compiler.gd:427-435`; `flight_session.gd:4173` |
| Propulsion breadth | D | Six fixed electric packages; no twin, turbine, EDF, glow/gas, glider (no-power) authoring | `packages.gd:15-26` |
| Ground handling | D | No gear, runway start or taxi for Creator aircraft | compiler capabilities |
| Smoke | D | Profile and legacy smoke are disabled for Workshop trials and donor flights | `main.gd:1210`, `main.gd:1226` |
| Other effects | B/C | Propeller blur works when a propeller is bound; crash director, lens effects and propulsion-keyed audio apply; no aircraft lights, pilot, streamers or companions | `main.gd:1201,1281-1331,3223,3535` |
| Shadows and LOD | C | Full-mesh projected cue shadow (stock proxy excluded); no LOD | `main.gd:3480-3484,3630`; `shadow.gd:132-144` |
| Cameras | B | Chase distance follows mesh bounds; cockpit/FPV for Creator aircraft not verified | `main.gd:3527,3555` |
| Helicopters and multirotors | C | ClearView helicopters fly with a donor (X-Cell .60) appearance; Phoenix rotorcraft are preview/draft only | `clearview/heli_donor.gd`; `donor.gd:42-43` |
| Guards and persistence | C | ClearView sources pin a provider installation; Phoenix sources behave as generic GLBs. Saved/Home flight of imported sources remains gated by AC-18/19 and AC-12 | `source_installation.gd:10-26` |
| Workshop UX | C | One `.mod` per import through the file dialog; no installation browser, thumbnails, variants or paint schemes | `aircraft_creator.gd` import flow |
| Replay and flight logging | C (unverified) | Plan lists Creator crash/replay/log/statistics as open; FLIGHT-LOGGING has no Creator case | [AC plan](aircraft-creator.md) |
| Performance budgets | C | Admission limits (200k triangles, 16 images ≤4096 px) are policy, not measured 1080p capacity | `limits.gd:3-38` |

**Summary.** Appearance is the strong point: every Phoenix aircraft imports with the right shape, size and livery. The weak points are, in order of player impact: physics that is not the aircraft (one borrowed trainer model, three in four Phoenix aeroplanes outside its domain), static control surfaces, opaque canopies and flat finish, no smoke or lights, and no ground handling.

## 3. Principles

1. **Honest estimates.** Decoded Phoenix values are *source data*; Phoenix tuning factors are never OpenRC coefficients. Every flight shows whether it uses an estimated package, a donor or a qualified model.
2. **Capability first, never per-aircraft branches.** New behaviour enters through `VehicleModel`, v2 capabilities and Creator packages. The kernel stays free of importer or aircraft-ID branches. Pinned physics sources are wrapped, not edited.
3. **One shared pipeline for all providers.** Materials, bindings, smoke mounts, guards and browser features serve generic GLB, ClearView and Phoenix alike.
4. **Measure every phase.** Each step has a numeric acceptance on the local corpus and a 1080p-first visual or frame-time check. Third-party bytes never enter the repository.
5. **Graphics never change physics.** Visual quality scales with presets; disabled features allocate nothing.

## 4. Phased plan

Effort is rough lead-days for one senior developer with helpers; dependencies name the owning steps.

### Phase 0 — Evidence harness (IAQ-00, 1–2 days)

- Restore a live audit path: run the debug bridge from a U: sparse worktree (no `.godot` junction) or extend the debugctl path policy with the host owner.
- Add an opt-in local corpus probe (never CI, never committed bytes): convert all installed Phoenix models, record admission, conversion time, triangle/texture counts and domain fit as JSON in the evidence folder.
- Capture a 1080p golden set: six classes (trainer, warbird, twin, glider, helicopter, multirotor) in chase and close views, with frame-time samples.

**Acceptance:** one command reproduces the 220-model table; six 1080p captures plus `frames` percentiles exist for one imported and one stock aircraft.

### Phase 1 — Visual fidelity quick wins (IAQ-01, 3–5 days; AC-PX-04, AC-CV-02)

1. **Materials:** map GEO opacity/specular and material names (`*glass*`, canopy) to `alphaMode BLEND`, roughness and a clear-coat-like finish; resolve shared simulator textures (glass, white, rotor disc) from the selected installation's `resources/textures` with the same bounded reader.
2. **Filtering:** set mipmapped anisotropic filtering on imported materials in `visual_builder.gd`, following the stock paint precedent; respect the texture-quality preset.
3. **Geometry:** index vertices (position+normal+UV weld) in the Phoenix writer to cut vertex memory by roughly 3×; keep exact-consumption checks.
4. **Investigate** the J-3 Cub half-white wing with a Phoenix-side reference (scheme tint versus texture content) before changing anything.

**Acceptance:** canopies are transparent in the six-class captures; GPU memory per imported aircraft falls measurably; no admission regressions (220/220).

### Phase 2 — Moving parts (IAQ-02, 1–2 weeks; AC-PX-05 / PX-R3, AC-17)

1. Build hinge-aligned pivot nodes from `controlSurfaces[].root_pivot/tip_pivot` and propeller `pivot`, preserving the neutral pose exactly.
2. Auto-propose bindings from Phoenix surface `Input` and geometry names (ailerons, elevator, rudder, propeller spin geometry); show them for confirmation in the parts panel.
3. Version the binding contract (v2): arbitrary axis, more than two parts per role, flaps and elevons as presentation roles, with Trial/Store readers updated together.

**Acceptance:** at least 90 % of Phoenix fixed-wing models get correct neutral/end poses for every declared primary surface; propeller blur attaches automatically; endpoint tests on synthetic oblique hinges.

### Phase 3 — Fly from decoded data (IAQ-03, 2–3 weeks; AC-PX-06/07, AC-12)

1. **Phoenix setup proposer:** map decoded wing, tails, mass, CG and propeller to Creator definition fields (`wing/*`, `horizontal_tail/*`, `vertical_tail/*`, `controls/*_deg`, equipment positions) as *borrowed* values with provenance, then complete missing values with the existing estimators.
2. **Package selection** by size, mass and propeller (park-flyer vs trainer; nearest power package), with a clear domain report naming each failing limit.
3. **Provider guard:** replace the hard-coded `openrc_clearview` namespace with a small provider registry (ClearView, Phoenix) used by `source_installation.gd`, `trial.gd`, `source_resolver.gd` and `compiled_publication.gd`. This is owner-reviewed shared work.
4. **Donor fallback** for out-of-domain models: extend `donor.propose` beyond ClearView so every Phoenix aeroplane can at least fly as an explicitly labelled donor (trainer, X8 for elevons, X-Cell for helicopters).

**Acceptance:** every in-domain model (initially ≤28) compiles and passes the hands-off climb-out; every other aeroplane flies as a labelled donor; flight logs replay exactly for two sample models.

### Phase 4 — Controls and feel (IAQ-04, 1 week)

Map Phoenix `Controls` (`Low_Rate`, `Expo`, `Servo_Speed`, travel) to v2 `controls.rates`/expo/servo time for Creator records; add a dual-rate switch; keep radio-side rates authoritative when present.

**Acceptance:** rate/expo curves match the decoded values within the documented quantization; controller and radio tests unchanged.

### Phase 5 — Effects and presentation (IAQ-05, 1–2 weeks)

1. **Smoke:** allow profile smoke for Creator aircraft through a validated mount (Phoenix `exhaust` position or a player-placed mount) and decoded `Display_Smoke_Colour`; remove the trial/donor exclusion only for validated mounts.
2. **Lights:** nav/strobe/landing lights through the existing light rig with Creator-authored positions.
3. **Pilot and cameras:** use decoded `pilots`/`cameras` for a pilot figure and cockpit/FPV station where the camera rig supports it.
4. **Streamers** through the cloth/windsock observer if it generalizes; **contact dust/spray** shared with ground effects.
5. **Crash:** wreck and debris behaviour of bound parts.

**Acceptance:** smoke, lights and cockpit view demonstrated on three imported aircraft at 1080p; disabled effects allocate nothing (object census).

### Phase 6 — Physics breadth (IAQ-06, multi-month; owners: physics, AS, energy, GP)

Each item is its own capability project with preregistered validation, entering through the shared kernel:

| Order | Capability | Phoenix models unlocked (approx.) |
| --- | --- | --- |
| 1 | Wider fixed-wing packages: 3D foamy, scale warbird, low-taper and heavy airframes | Most of the 88 out-of-domain aeroplanes |
| 2 | Gear and runway starts (AC-21/25) | Nearly all scale and training aeroplanes |
| 3 | Gliders (no propulsion, slope/thermal) | 7 gliders + powered gliders |
| 4 | Twins and multi-propulsion | Beech 58, B-17 and other twins/multis |
| 5 | Turbine/EDF | 10 turbine + EDF models |
| 6 | Helicopters from decoded rotor data (beyond the X-Cell donor) | 96 helicopters |
| 7 | Multirotors | 8 multirotors |

**Acceptance:** per capability, an AC-12-style numerical campaign and flight-log evidence; no change to stock golden flights.

### Phase 7 — Workshop UX and library (IAQ-07, 2–3 weeks; AC-13/18/19, AC-PX-08)

Installation browser (choose the Phoenix folder once; list every model with class, outcome and a Creator-rendered thumbnail; filters by class and flight status); variants (`.var`) and paint schemes; batch conversion with cancel; saved revisions, Home launch and bundles; LOD generation and per-preset geometry/texture budgets.

**Acceptance:** browse and import any of 220 models without the file dialog; save, reopen and launch from Home; budgets measured at 1080p on the reference PC.

### Phase 8 — Qualification and release (IAQ-08)

Native-backend qualification for Creator aircraft, the AC-12 gate for each released package, 1080p (then higher, then 720p) performance qualification, packaged Windows/Linux/macOS evidence, and a player guide in every website language (following the ClearView guide).

## 5. Priorities and KPIs

| KPI | Now | After phase 3 | Target |
| --- | --- | --- | --- |
| Phoenix models imported with correct appearance | 220/220 | 220/220 | 220/220 |
| Fixed-wing models with working moving parts | 0 | ≥90 % | 100 % of declared surfaces |
| Aeroplanes that fly (estimated or labelled donor) | generic estimates only | 116/116 | 116/116 with class packages |
| Aeroplanes flying with source-derived geometry | 0 | 110/114 compile with Phoenix-derived packages (105 airborne starts) | majority after phase 6 |
| Imported-aircraft frame cost at 1080p | unmeasured | measured | within the preset budget |

Recommended order for the next sprint: **IAQ-00 → IAQ-01 → IAQ-02 → IAQ-03**. They are the cheapest changes with the largest visible effect (transparent canopies, moving surfaces, every aeroplane flyable with honest labels), and each reuses existing systems.

## 6. Risks

- **Fidelity expectations.** Players may expect "the Phoenix aircraft". The UI must say estimated or donor, never imply equivalence to Phoenix behaviour.
- **Domain pressure.** Widening limits without numerical campaigns would hide bad flight; widen only through new packages with evidence.
- **Shared-file contention.** Guards, bindings and `main.gd` effects seams are shared; coordinate through the [ownership registry](../README.md#tracks-plans-and-step-ids).
- **Native kernel staleness.** Physics-side work can silently disable the native backend; requalify after any physics change.
- **Rights.** Stock content stays on the player's machine; only code and metadata are committed.

## 7. Progress

| Step | Date | Delivered | Evidence | Still open |
| --- | --- | --- | --- | --- |
| IAQ-01 | 2026-11-20 | Phoenix glass and alpha materials (`alphaMode BLEND`, tinted clear glass, RGBA textures); shared installation textures (`resources/textures/aircraft`, `misc`); welded vertices (indexed geometry); mipmapped anisotropic filtering for every imported GLB in `visual_builder.gd` | `test_creator_phoenix_readers` 97/0; `test_creator_visual` 231/0, `test_creator_clearview_visual` 94/0, `test_creator_clearview_motion` 225/0, `test_creator_import` 0 failures; Beech 58 EEVEE render shows translucent cabin glass | GEO specular unused; J-3 Cub half-white wing; ClearView/generic material parity review |
| IAQ-02 | 2026-11-20 | Hinge-aligned pivot nodes from decoded `root_pivot`/`tip_pivot` (right side mirrored) and the propeller pivot; automatic Creator bindings applied on import (player still confirms in Moving parts) | Local corpus: 220/220 converted, 116/116 fixed-wing models get bindings that pass `validate_bindings` (437 control roles, 101 propellers), slowest 2.9 s; Blender renders with 30° deflection show surfaces turning on their hinges | Binding v2 (more than two parts per role, flaps, elevons); helicopters; live in-app check (IAQ-00) |
| IAQ-03 (first slice) | 2026-11-20 | Phoenix wing, tail, fin, propeller hub and control throws mapped into Creator layout fields (structural frame from the main-wing root leading edge) and applied as labelled estimates over the scaled starting values, with the estimated inventory; a tractor hub sets the fuselage nose and axis | Local corpus with the real Creator sequence: 8/114 fixed-wing models compile on the trainer package (Super Cub float, S.E.5a, Corsair, FunCub, Apprentice 15e/S15e, High-wing Trainer, Tutor 40); all 8 pass the airborne start gate, 5 also the hand launch. Refusals: taper 29, span 25, battery balance 12, other 26 | Park-flyer/pusher package choice, battery balancing (reuse `_fit_estimates`), provider guard and donor fallback, wider packages (IAQ-06) |
| IAQ-03 (provider route) | 2026-11-20 | Phoenix aeroplanes registered as a recognised provider (`openrc_phoenix_aeroplane`); `phoenix/setup.gd` proposes size class, scaled span, fitted planform, limited throws and pusher/biplane flags from the decoded receipt; `Authoring.apply_clearview_setup` reused (optional `layout`, `pusher`, `owns_scale`); provider-specific flight/publish texts; ClearView geometry functions refuse other providers | All 32 Creator tests pass (Phoenix 114/0 incl. setup, ClearView setup 56/0, donor 17/0, source installation 89/0, published trial 62/0, source reference 240/0, language 0 failures). Local corpus, real propose+apply+compile sequence: 110/114 aeroplanes and gliders compile (27 scaled, 85 fitted planforms, stacked wings as one equivalent wing, decoded pusher hubs kept where the package can carry them); 110/110 airborne starts available, 45 hand launches. Refused: Typhoon canards (2), one loader refusal, one nose range. Good Enemy review: no requirement violation; pusher-hub, biplane-reference and donor-guard findings fixed | Live in-app flight check (IAQ-00); `app_root.gd` donor/airship request checks still use `required()` (UI-guarded; change with the AFC-02 manifest renewal); `owns_scale` infers the import default from metres at scale 1; helicopters and multirotors; Phoenix-specific packages (IAQ-06) |
| IAQ-03b (Phoenix physics) | 2026-11-20 | Each Phoenix aeroplane flies on airframe and power packages derived from its own decoded data (`phoenix/physics.gd`, [decision](../DECISIONS.md#phoenix-aeroplanes-fly-on-packages-derived-from-their-own-data)): polar-based lift, drag and stall, Phoenix span efficiency, body drag from the frontal area, control-surface effectiveness, aileron roll power, mass and CG (source-mass items and balance target), propellers (Froude-scaled RPM, multi-engine equivalent, 2.3 × weight thrust cap), jet thrust equivalents and a glider launch motor; content-addressed ids re-derived on draft restore; setup texts in nine languages say the configuration is derived from the Phoenix data | Local stock corpus, real propose+apply+compile+start sequence: 110/114 compile, 105 airborne starts, 21 hand launches (EasyStar 0.70 kg, Vs 4.9 m/s, level 8.7 m/s at half throttle; A-10 turbine T/W 2.19; Habu 2 T/W 1.32 vs Phoenix 1.36). Refused: two canard Typhoons, a pusher ahead of its CG, HBZ Stratos (own propeller under 0.3 × weight). `test_creator_phoenix_readers` 144/0; all 32 Creator suites pass. Good Enemy review: identity, untrusted-block validation, derive-failure, source-mass re-run, pitch-ratio and registry findings fixed | Live flight audit (IAQ-00); five aircraft (B-17, P-47, UM Spitfire, 4-Site, Grasshopper) need over half throttle at the start speed; jets fly an equivalent propeller (torque and gyroscopic effects present); polars beyond the main wing; mean-chord definition in the CG target; scale changes after setup do not re-derive |
| IAQ-03c (honest import) | 2026-11-20 | Phoenix helicopters and multirotors get an explicit appearance-only note (no fixed-wing set-up); the appearance-only note is kept only for aeroplanes without a usable layout; dropped textures beyond the 16-image GLB limit are reported; reopened Phoenix drafts rebuild their notes from the receipt (`Converter.source_notes`); a scale change after set-up blocks compile ("use Set up for flight again"); a draft whose derivation an earlier version made reopens on its base packages instead of being refused; installation sub-folders are matched case-insensitively for copied installs. Nine-language texts | `test_creator_phoenix_readers` (texture limit, rotorcraft and reopened notes, size change, outdated derivation, copied-install case); language test; all 32 Creator suites. Good Enemy review: no hole in restore or gating; seven smaller findings fixed (aileron edge cases, notes after set-up, tuning key casing, thrust-angle note, texture count, double engine tuning, diameter note) | A Phoenix helicopter donor (needs the Phoenix frame and rotor mapping; step 7) |
| IAQ-00 (tools) | 2026-11-20 | `research/aircraft-creator/phoenix/creator_corpus.gd` (opt-in: the Creator sequence and both start checks over a local installation, `corpus.json`, compiled records with `--export-trials`) and `flight_cards.py` (flies each record through the flight-test card via its new `--record` option and tabulates stall, level speed, cruise throttle, climb, glide, roll rate and hands-off behaviour) | EasyStar card on the derived packages: stall 5.15 m/s, level maximum 25.2 m/s, climb 7.1 m/s, glide ratio 12, roll 155 °/s with inherited ailerons (fixed in IAQ-03d), hands-off spiral 442° in 30 s. Full 110-model baseline and IAQ-03d candidate cards are local evidence on U: | Live rendered audit path (debugctl junction, MCP launch); exact replay of two models |
| IAQ-03d (tuning) | 2026-11-20 | Phoenix `Fine_tuning` lift, control-power, thrust and engine multipliers; inactive (zero-length) ailerons; propeller down/right thrust; `DERIVATION_VERSION` 4 ([decision](../DECISIONS.md#phoenix-aeroplanes-fly-on-packages-derived-from-their-own-data)) | Local corpus: 110/114 compile, 105 airborne starts, 21 hand launches (unchanged totals; Minimag gains a hand launch, the rudder-steered Radian loses it); stall speed moves on the lift-tuned models (F-4 13.6→10.3 m/s, Su-22 16.1→14.3, T-28 6.7→5.9); `test_creator_phoenix_readers` 168/0 | Rudder-steered models (EasyStar, Radian) fail the hands-off hand-launch check; card comparison of baseline and candidate |

## 8. Re-audit after IAQ-03b and next improvements (2026-11-20)

Since the §2 audit, IAQ-01/02/03/03b delivered materials, moving parts, the provider route and flight on packages derived from each model's Phoenix data (§7). This re-audit measures what the stock definitions carry that the importer still ignores, and re-orders the remaining phases by player impact. Evidence: a census of the 220 decoded local definitions (research script, nothing committed), an independent read-only code audit and lead verification of each claim used below.

### 8.1 What the stock models carry

| Decoded content | Models | Used today |
| --- | --- | --- |
| Classes | 107 fixed-wing, 7 gliders, 96 helicopters, 8 multirotors, 2 others | Fixed-wing and gliders only |
| Landing gear (`gear[]` with wheel collision primitives) | 97 fixed-wing: 80 with a steerable wheel, 21 retractable, 7 on floats | Presence only; Creator records compile `gear = locked_up`, airborne/hand starts |
| Gear doors and other `widgets` driven by "Retract Gear" | 13 | No |
| Controls per channel (`Low_Rate`, `Expo`, `Servo_Speed`, `Trim`, mixes) | 212 | No (throws only) |
| Exhaust smoke mounts with colour (`Display_Smoke`) | 46 | No; profile smoke is gated off for Workshop trials (`main.gd:1210`) |
| Streamers / pilot figures / onboard cameras | 108 / 68 / 67 | No |
| Paint schemes (`<model>#<Scheme>.bmp`) / `.var` presets | 36 schemes on 22 models / 29 models | No |
| `level` (Beginner 46, Intermediate 113, Advanced 61) and `style` | 220 | No |
| Helicopter rotor heads (diameter, chord, blades, pitch range, RPM, gyro, governor) | 96 | No; rotorcraft import as plain GLBs |
| Airfoil polars | 21 library files | Main wing only |

### 8.2 Findings

| # | Finding | Impact | Evidence |
| --- | --- | --- | --- |
| F1 | Phoenix helicopters and multirotors get no provider marker, so they open as generic GLBs: no refusal, no donor offer, and the player can hand-build a fixed-wing configuration for a helicopter | 104 models (47 %) silently mis-handled | `phoenix/converter.gd:23` (`AEROPLANE_TYPES`), `source_installation.gd` `provider()` |
| F2 | Every import still shows "Only the Phoenix appearance is imported… define its flight configuration separately" next to the Set-up note | Contradicts the delivered route | `converter.gd:42,173` |
| F3 | Textures beyond the 16-image GLB limit are dropped silently | Wrong colours without a note | `converter.gd:106-107` |
| F4 | Reopening a saved Phoenix draft rebuilds notes through the ClearView path, so Phoenix notes are lost | Missing explanations after reopen | `aircraft_creator.gd:591,599` |
| F5 | Changing the scale after "Set up for flight" keeps packages derived for the old size | Silent physics mismatch | `authoring.gd` setup loop; §7 IAQ-03b |
| F6 | No runway take-off, landing or taxi although the kernel already flies fixed/retractable tricycle and taildragger records | The most visible realism gap for 97 aeroplanes | `compiler.gd:400`; stock `f4u_corsair_250.json`, `jensen_ugly_stik_60.json` |
| F7 | One file at a time through a dialog, an explicit set-up step, no browser, schemes or presets | Slow discovery of 220 models | `aircraft_creator.gd:617-791` |
| F8 | Binding v1: four control roles, one propeller, two parts per role; flaps, elevons, V-tails and extra propellers stay static | Twins, B-17, deltas look wrong | `visual_parts.gd:17-22`, `converter.gd:465-480` |
| F9 | Inertia stays the scaled UltraStick value; compile warnings report 0.4–2.9× deviations | Pitch/yaw response off on scale and heavy models | corpus probe warnings |
| F10 | No flight evidence: the live path (IAQ-00) is still blocked, so derived physics is compile- and start-gate-tested only | Physics quality unknown in flight | §1 |
| F11 | Test gaps: Creator UI import/adopt/cancel of a `.mod`, shared texture folders, the 16-texture limit, rotorcraft handling; resource sub-folder lookup is case-sensitive on copied installs | Regressions and Linux/macOS failures go unseen | `test_creator_phoenix_readers.gd`; `converter.gd` folder helpers |

### 8.3 Next improvements, in order

| Order | Step | Work | Effort | Acceptance |
| --- | --- | --- | --- | --- |
| 1 | **IAQ-03c — honest import hardening** | F1: mark Phoenix rotorcraft (`openrc_phoenix_rotorcraft`), refuse fixed-wing set-up for them with a clear note and offer the existing helicopter donor; F2: replace the appearance-only note; F3: a diagnostic naming dropped textures; F4: Phoenix notes kept on reopen; F5: re-derive (or ask) on a scale change; F11: UI import-path, shared-texture and case tests, case-insensitive resource lookup | 2–3 days | Phoenix tests cover each case; 96 helicopters show the rotorcraft note; no stale text in nine languages |
| 2 | **IAQ-00 — evidence harness** | Fix the live path (U: worktree or debugctl policy); commit the opt-in corpus probe as a tool (local install path argument, JSON report, never stock bytes); a scripted per-model flight card from flight logs: stall speed, level speed at half throttle, climb, roll rate, glide ratio | 3–4 days | One command produces the 114-model card; two models replay exactly; physics changes are compared against the card |
| 3 | **IAQ-06a — gear and runway** | Derive wheel contact points from `gear[].sides[].collision`, steerable `isGuide` wheels, tail/nose layout and `isRetractable` into the existing gear capabilities; bind gear doors (`widgets`) to the retract input; floats stay airborne-start | 1–2 weeks | 80+ aeroplanes take off from and land on the runway; taildraggers ground-loop plausibly; retracts animate |
| 4 | **IAQ-07a — library flow** | Installation browser (scan once; list with Phoenix thumbnails, class, level, style and flight status); "Import and set up" in one action; paint-scheme picker (22 models) and `.var` presets (29) | 1–2 weeks | Any of the 220 models imported and flying in two clicks; schemes switch without re-conversion |
| 5 | **IAQ-04 — controls and feel** | Phoenix rates, expo, servo speed and dual rate into v2 controls; binding v2 for flaps, elevons, V-tail and every propeller; tail polars; inertia from the mesh and item layout instead of the scaled donor; a start policy for the five models that need more than half throttle | 1–2 weeks | Decoded curves reproduced; inertia warnings gone; all propellers and surfaces move |
| 6 | **IAQ-05 — presentation** | Smoke from the 46 decoded exhaust mounts and colours (lift the Workshop gate only for validated mounts); streamers; pilot figures; onboard cameras as cockpit/FPV stations; engine sound chosen from the Phoenix engine category | 1–2 weeks | Smoke and cockpit view on three imported aircraft at 1080p; disabled effects allocate nothing |
| 7 | **IAQ-06b — Phoenix helicopters** | Derive a helicopter package from the decoded rotor heads on the existing helicopter kernel (X-Cell research record as base), replacing the donor appearance swap; then the 8 multirotors | 3–5 weeks | Helicopter AC-12-style campaign; 96 helicopters hover and fly with their own rotor data |
| 8 | **IAQ-07b/08 — saved flight and release** | Home and published flight for derived packages once AC-18/19 and the AC-12 gate pass; Linux/macOS copied installs; community PKG import (AC-PX-01); LOD and 1080p budgets | multi-week | Phoenix aircraft launch from Home; packaged three-platform evidence |

Steps 1 and 2 come first: they remove misleading behaviour and give every later physics change a measurement. Gear (3) is the largest single gain in realism and reuses kernel capabilities that already fly stock aircraft. Phase 6 items 3–5 (gliders, twins, turbines) now have estimated equivalents from IAQ-03b; their own capability work stays in IAQ-06.

| KPI | Now (2026-11-20) | After steps 1–4 | After step 7 |
| --- | --- | --- | --- |
| Phoenix models with an honest route (flight, donor or clear refusal) | 110 of 220 | 220 of 220 | 220 of 220 |
| Aeroplanes with runway take-off | 0 | 80+ | 80+ |
| Models flying on their own decoded data | 110 | 110 | 200+ |
| Clicks from installation to flight | file dialog + set-up + confirm + fly | 2 | 2 |
| Models with a per-model flight card | 0 | 114 | 210 |

### 8.4 What the installed game and Phoenix Builder add

The Builder's user guide gives each field its meaning ([field table](../research/aircraft-creator/phoenix-stock-format-2026-11-20.md#36-field-meanings-from-phoenix-builder)). Four facts change the plan:

1. **Phoenix tunes most models with `Fine_tuning` multipliers that Creator ignores.** Lift is changed on 49 models (75–175 %), elevator and aileron power on 25, engine power or thrust on 34. Applying them to the derived lift, control effectiveness and power is cheap and brings each aircraft closer to how Phoenix flies it. This becomes step 2b below.
2. **Phoenix models propeller wash per airfoil (`Wash`, 456 airfoils).** That is the mechanism OpenRC lacks and the reason for the 2.3 × weight thrust cap. A kernel propeller-wash capability (physics owners) would remove the cap and fix low-speed rudder and elevator authority. Until then the cap stays.
3. **Flaps (19 models), down and right thrust (110 propellers) and spool response are decoded.** Stock OpenRC records already fly `flaps = simulated`, so flaps join the gear step. Thrust angles join the power derivation.
4. **The player's installation holds a preview image for every model and the engine sounds.** `<model>_preview.bmp` serves the library browser. `.pxe` throttle-to-volume/pitch curves over the player's own WAV samples can drive engine audio at runtime, loaded locally like textures and never redistributed.

Added step: **2b. IAQ-03d — Phoenix tuning and thrust angles (2–3 days).** Apply `Fine_tuning` lift, control-power, thrust and engine multipliers, plus `Down_thrust`, `Right_thrust` and idle RPM, inside `phoenix/physics.gd` under a new `DERIVATION_VERSION`. Acceptance: the per-model card from step 2 shows the expected direction of change on the 49 lift-tuned models, and nothing changes for models at 100 %.
