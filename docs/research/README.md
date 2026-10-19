# Research index

`docs/research/` contains investigation reports and step evidence. This index points to the best starting document for each topic; detailed test records remain beside their step. Write new research in English. Older Spanish reports are translated when revised. See the [documentation map](../README.md) for document roles and the [initial research notebook](initial-notebook.md) for pre-Gate 1 background.

## Two folders, one rule

| Location | Purpose | Example |
| --- | --- | --- |
| `docs/research/` | Reports, sources, measurements, probes and step evidence | [VQ-04a](visual-quality-implementation/VQ-04a/README.md) |
| root `research/` | Reproducible scripts, input data and aircraft measurement pipelines | [Extra 300S derivation](../../research/extra-300/ex05/derivation.md) |

Some tools use local-only material from `references/`; their reports say when a fresh clone cannot reproduce the original measurement. Commit the resulting evidence and source identity, not private reference files.

## Whole-project audit

- [Godot performance and visual review, 2026-10-14](godot-global-review-2026-10-14.md) compares current source and retained native evidence with Godot 4.7 documentation, repositories and community reports. Its [second round](godot-global-review-2026-10-14.md#9-second-research-round-creative-directions) adds 24 creative experiment ideas; the [execution plan](../plans/global-performance-visual-quality.md) sequences work under existing track owners. No new runtime benchmark or implementation is claimed.
- [Branch integration, 2026-10-10](branch-integration-2026-10-10.md) records merge decisions and clean-checkout checks.
- [PT1h release-readiness audit](release-readiness/PT1h/README.md) reconciles code, documents and rc6 evidence; [tool workflows](../TOOLS.md) lists current commands and measurement limits.
- [Project technical audit](project-audit-2026-10-06/README.md) reviews physics, runtime, tests, export and roadmap at its recorded commit. Its recommendations are planning input, not proof that issues are fixed.
- [Graveacre asset workflow review](graveacre-ai-workflow-2026-10-09.md) records primary links, access limits and practical asset-pipeline findings.

## Entry points per track

### Cinematic trailer

[TRA-00 source investigation, 2026-10-17](cinematic-trailer/2026-10-17.md) records vehicle/capture/economics boundaries, 16 expanded web investigations, five music candidates, code-effect references and video-skill comparisons. [TRA-01…07 production evidence](cinematic-trailer/production-2026-10-17.md) records the first delivery and source identities; [revision 6](cinematic-trailer/revision-6-2026-10-17.md) removes the abrupt ending reset for a 58-second cut, retaining the cinematic feature titles, MONSTER CAR 2 jump, twilight Lumber, two Extra rolls, formation opening and continuous score. The [production plan](../plans/cinematic-trailer.md) retains creative targets and remaining release gates.

### Flight logging

- [FL-01…04: flight logging design, sources and verification](flight-logging/FL-01/README.md); [current manual](../FLIGHT-LOGGING.md). Bounded fixed-wing recorder, exact replay, explicit candidate experiments and CSV analysis.

### Controller support

[Controller review, 2026-10-14](controller-support-2026-10-14/README.md) records the original gamepad/radio audit, Godot 4.7.2 and SDL sources, and subsequent implementation evidence: explicit device ownership, V2 profiles, safe transitions, menu navigation, free glyphs and native Windows checks. The [implementation plan](../plans/controller-support.md) retains Xbox/DualSense physical and package qualification and optional feedback as open gates. API/synthetic checks do not establish hardware support.

### Random failures and emergency practice

[EM-00 source review](failure-mode/EM-00/README.md) records RC receiver/servo/ESC/engine manuals, numerical and damaged-aircraft references, documented one-wing RC landings, and the original session/control limitations. [EM-01 implementation evidence](failure-mode/EM-01/README.md) records software verification of the initial logical-control/throttle mode. [EM-05 evidence](failure-mode/EM-05/README.md) adds capability-bound glow/electric source loss, historical-plan compatibility and transactional replay. [EM-03a evidence](failure-mode/EM-03a/README.md) records the shared actuator kernel, accepted-surface observation, healthy parity and aircraft-specific availability screen. The [failure-mode plan](../plans/failure-mode.md) owns current scope, probability, menus, remaining mechanisms and acceptance. Software verification does not establish physical or pilot validation.

### Natural Random flight

[NR initial implementation](natural-random/README.md) records the stock-only scenario generator, menu/lifecycle checks, numerical flight matrix and native captures. [Active plan](../plans/natural-random-flight.md) retains pilot/readability acceptance and future sky, runway and catalog work.

### Aircraft Workshop

[AE-01–10 initial implementation](aircraft-editor/AE-01-10/README.md) records shared compiler/store/descriptor/trial/UI checks, native captures and the remaining acceptance scope. The [current guide](../AIRCRAFT-WORKSHOP.md) documents supported experiments; the [AE plan](../plans/aircraft-editor.md) owns engine-family editing and fleet continuation.

### RC monster truck

[RCV-00](rc-monster-truck/README.md) records the repository/session/menu audit, primary vehicle-physics references, T-Maxx scale and mechanism evidence, free asset candidates and measurement gaps. The [active plan](../plans/rc-monster-truck.md) owns the proposed ground-vehicle integration, physics laboratory, playable course, acceptance gates and Blender developer letter. This is planning evidence; no truck runtime or physical validation is claimed.

### Ground physics

[GP-00–05 evidence index](ground-physics/README.md) covers terrain, per-wheel contact, spin and suspension, profile/session integration, traces, numerical checks and remaining physical calibration. The [integrated ground model](ground-physics/GP-05/README.md) records current scope and open gates.

### Aircraft standardization

[AS-00–05 evidence index](aircraft-standardization/README.md) covers the fleet audit, v2 contract/schema, source migration, authoring template and verification. The [aircraft data contract](../../AIRCRAFT_CONTRACT.md) defines current authoring; measured aircraft mass properties and physical validation remain separate work.

### Extra 300S flight realism

[EX-06/08/09 realism audit](extra-300-realism/README.md) links the manual/source audit, corrections, behavior matrix, regression results and remaining physical gaps. The [Extra 300S plan](../EXTRA-300-PLAN.md) owns aircraft implementation; the research records realism findings and remaining physical gaps.

<a id="avanti-s-flight-realism"></a>

### Ventage Jet flight realism

[AV-14…17 realism investigation](avanti-realism/README.md) records the A200/P100-RX source audit, geometry and mass-property corrections, full-session behavior checks, and remaining physical-validation gaps. The [Ventage Jet plan](../AVANTI-S-PLAN.md) owns pending aircraft work.

[AV-17-R1 keyboard pitch and dive recovery](avanti-realism/AV-17-R1/README.md) records the 2026-10-14 manufacturer/parameter audit, accelerated-stall reproduction, progressive keyboard response, before/after traces and regression evidence.

[AV-17-R2 gamepad pitch and progressive stall](avanti-realism/AV-17-R2/README.md) records the reproduced pure-elevator roll departure, source-based estimated wing polar, fixed gamepad travel, paired traces and remaining physical-validation limits.

[AV-17-R3 rudder release](avanti-realism/AV-17-R3/README.md) records the yaw-moment reference correction, progressive Normal gamepad rudder, paired release traces and preserved pitch behavior.

[AV-18 fuel-turbine source review](turbine-realism/AV-18/README.md) compares identified JetCat revisions, Xicoy and KingTech manufacturer data with original engine experiments, and fingerprints the current propulsion/fuel gaps. The [turbine realism plan](../plans/turbine-realism.md) owns detailed response, ECU, fuel/mass and integration work.

[AV-18…20 implementation](turbine-realism/AV-20/README.md) records continuous turbine RPM, explicit model selection, checkpoint/trace guards, analytic and paired-flight proofs, and remaining physical/ECU/fuel gates. The [AV-10b reference](../../research/avanti-s/av10/README.md) verifies open-system mass mechanics separately from production fuel integration.

### Turbo Lumber Evolution (Timber)

[D6e-R1 climb investigation](flight-dynamics/climb-trim/README.md) records five-aircraft equilibrium and power-step checks, the unresolved reported hands-off Timber climb at 25% power, and the separately verified manual elevator-trim improvement.

[TT-00](timber-integration/TT-00/README.md) starts the CAD/import and code-seam review; [TT-00-R1](timber-integration/TT-00-R1/README.md) reviews the r1 delivery. [TT-01](timber-integration/TT-01/README.md) freezes the r1 bytes, [TT-02](timber-integration/TT-02/README.md) measures the imported scene and resolves the forward-extent discrepancy, [TT-03](timber-integration/TT-03/README.md) puts the GLB in the app with its model contract and captures, [TT-05](timber-integration/TT-05/README.md) proves the articulation signs, propeller sense, gear wrappers and clearances, and [TT-06](timber-integration/TT-06/README.md) registers the catalog preview entry with the shared test sweep. [TT-07–12](timber-integration/TT-10/README.md) enables experimental electric flight, product controls, runway start and sound with bounded software proofs. The [integration plan](../TIMBER-INTEGRATION-PLAN.md) owns the model and electric-flight handoff.

### Desktop delivery

Start with [DT-00](desktop-delivery-investigations/DT-00/README.md), then see [DT-00-R1](desktop-delivery-investigations/DT-00-R1/README.md) and [DT-00-R2](desktop-delivery-investigations/DT-00-R2/README.md) for platform, installer, display, performance and native-test research. The [desktop delivery plan](../DESKTOP-DELIVERY-PLAN.md) tracks acceptance.

### Roadmap knowledge base (all phases)

[Roadmap investigations](roadmap-investigations/README.md) collects pre-work research for numerics, aerodynamics, propulsion, ground handling, radio, weather, validation, aircraft data and presentation. Read the relevant phase brief before starting its implementation step.

### Crash and damage

[Crash investigation index](crash-damage-investigations/README.md) covers contact diagnostics, structural-source work and presentation evidence. The [crash and damage guide](../CRASH-DAMAGE-PLAN.md) separates implemented experimental effects from structural validation and damaged-flight work.

### Flight model and simulation

Use the [flight-model audit](flight-model-robustness-audit.md), [repair implementation record](flight-repair-implementation.md) and [D8b-R2 pull-up investigation](flight-robustness/D8b-R2/README.md) (with the [D8b-R2d analog evidence: measured Ultra Stick 120 lift retention and roll damping, scoring bench and candidate results, 2026-10-19](flight-robustness/D8b-R2/analog/README.md)) for the main handling history. Current implementation boundaries are in [STACK](../../STACK.md); the [roadmap](../../ROADMAP.md) owns remaining gates.

| Topic | Evidence entry points |
| --- | --- |
| Aerodynamics and wake | [D11d induced flow](aero-consistency/D11d/README.md), [E0a2a/b downwash](aero-consistency/E0a2b/README.md), [D11f yaw damping](aero-consistency/D11f/README.md), [D11g rate derivatives](aero-consistency/D11g/README.md), [elevator root-cause investigation, closed 2026-10-18](flight-dynamics/elevator-repair-2026-10-13.md), [D10-R2 Ugly Stik lateral-directional stability: predicted fin-efficiency/fuselage Cnβ adopted against flight-identified Stiks, reference-based recovery criteria, R02 induced operator (2026-10-18)](flight-dynamics/stik-lateral-directional-2026-10-18/README.md), [D10-R4 developed spin and post-stall lift retention against measured RC data (2026-10-19)](flight-dynamics/spin-post-stall-2026-10-19/README.md), [D10-R5 Ugly Stik roll due to sideslip across the load regimes: wing-body couple (2026-10-19)](flight-dynamics/stik-roll-sideslip-2026-10-19/README.md), [E0a2c/D11i/D11j regime consistency of the generated aircraft](aero-consistency/E0a2c/README.md), [E0b1 actuator-disc wake](propwash/E0b1/README.md), [E0b6 swirl](propwash/E0b6/README.md), [E0b6p cost work](propwash/E0b6p/README.md), [E0b7 observation preparation](propwash/E0b7/README.md), [M5-GE-1 ground effect](ground-effect/M5-GE-1/README.md) |
| Simulation state, replay and cost | [simulation foundation SF-00…09 and SF-04b (kernel contract, event locators, substeps, environment, law harness)](simulation-foundation/README.md), [H4–H5 profiling](simulation-state/H4-H5/README.md), [H8 checkpoints](simulation-state/H8/README.md), [H9 tolerance replay](simulation-state/H9/README.md), [H11 contacts](simulation-state/H11/README.md), [H12 local-strip aero](simulation-state/H12/README.md), [H13 slipstream](simulation-state/H13/README.md), [H14 tilted shaft](simulation-state/H14/README.md), [H15 attached flow](simulation-state/H15/README.md), [Gate P native-kernel comparison](simulation-state/Gate-P/README.md) |
| Ground handling and circuits | [E5a taildragger breadth](ground-contact/E5a/README.md), [E3b2 runway equilibrium](ground-contact/E3b2/README.md), [E3c1a landing baseline](ground-contact/E3c1a/README.md), [E3c2a circuit](ground-contact/E3c2a/README.md), [E4a replay regression](ground-contact/E4a/README.md), [PT2 pilot preparation](ground-contact/PT2/README.md) |
| Propulsion | [G1a1 propeller sources](propulsion/G1a1/README.md), [G1b1 operating range](propulsion/G1b1/README.md), [G2a coupled shaft](propulsion/G2a-RK4/README.md), [EL1a-R1 sources](propulsion/EL1a-R1/README.md), [EL1a-R2 implementation research](propulsion/EL1a-R2/README.md), [EL2a-P3 optimization](propulsion/EL2a-P3/README.md), [EL2a-E1 ground scenarios](propulsion/EL2a-E1/README.md); see the [electric propulsion plan](../ELECTRIC-PROPULSION-PLAN.md). Battery: [BAT-00 sources](battery/BAT-00/README.md), [BAT-04 specification](battery/BAT-04/specification.md), [BAT-05 cell fits and packs](battery/BAT-05/README.md), [BAT-06…13 integration](battery/BAT-10/README.md), [BAT-14/15 telemetry overlay](battery/BAT-15/README.md); see the [battery plan](../plans/battery-realism.md) |
| Two-stroke and four-stroke glow engines | [NITRO-00 manufacturer sources and limits](glow-engines/NITRO-00/README.md), [NITRO-01 standalone mean-cycle/profile proof](glow-engines/NITRO-01/README.md); separate family milestones and acceptance belong to the [RC glow engine realism plan](../plans/RC_NITRO_ENGINE_REALISM_PLAN.md) |
| Fuel, mass and balance | [FUEL-00 audit and sources](fuel-systems/FUEL-00/README.md): fleet CG shift and static margin from full to empty, glow variable-mass law check, consumption and feed numbers, fuel densities, tank placement and balance practice, JSBSim tank model; work belongs to the [fuel, mass and balance plan](../plans/fuel-mass-balance.md) |
| Validation and data | [VAL-3 reference dashboard](validation/VAL-3/README.md), [VAL-5a weighing](validation/VAL-5a/README.md), [VAL-6a inertia](validation/VAL-6a/README.md), [VAL-7a propeller](validation/VAL-7a/README.md), [VAL-7b throttle](validation/VAL-7b/README.md), [VAL-7c uncertainty](validation/VAL-7c/README.md), [VAL-8a ground-run video](validation/VAL-8a/README.md), [VAL-8b roll video](validation/VAL-8b/README.md), [DATA-1 freshness](aircraft-validation/DATA-1/README.md), [DATA-4a schema checks](aircraft-validation/DATA-4a/README.md) |
| Weather and input | [wind implementation](wind-implementation/README.md), [M5-W04a turbulence](wind-implementation/M5-W04a/README.md), [M5-ATM-1 density kernel](atmosphere/M5-ATM-1/kernel/README.md), [D6b-R2 calibration rearming](radio-input/D6b-R2/README.md), [D6e dual rates and expo](radio-input/D6e/README.md), [F1 diagnostics](radio-input/F1/README.md), [F3b1 event cost](radio-input/F3b1/README.md), [F6a latency capture](radio-input/F6a/README.md), [F6b latency reduction](radio-input/F6b/README.md) |
| Integrity checks | [C7-R2 trace metadata](trace-integrity/C7-R2/README.md), [D4-R2 trim integrity](trim-integrity/D4-R2/README.md), [DATA-3 input identity](aircraft-validation/DATA-3/README.md) |

### Ugly Stik

Start with the [source and local-reference map](ugly-stik-resources.md), [model investigations](ugly-stik-investigations/README.md), [current model record](ugly-stik-model-v4.md), [engine v5 evidence](ugly-stik-engine-v5.md) and the [US-V09a covering/shading pass](ugly-stik-finish-v6.md). Visual and authoring work is indexed under [visual investigations](ugly-stik-visual-investigations/README.md) and [tooling investigations](ugly-stik-tooling-investigations/README.md). See the [Ugly Stik plan](../UGLY-STIK-PLAN.md) and reproducible [model pipeline](../../research/ugly-stik/).

### Extra 300S

Read the [family research](extra-300-family-research.md), [integration audit](extra-300-integration-audit.md), [realism audit](extra-300-realism/README.md), and [generated physics derivation](../../research/extra-300/ex05/derivation.md). Shared authoring tools are in [extra-aircraft-tooling](extra-aircraft-tooling/README.md). The [EXTRA-300-PLAN](../EXTRA-300-PLAN.md) owns aircraft implementation.

<a id="avanti-s"></a>

### Ventage Jet

The [AV-09 landing-gear evidence](avanti-gear/AV-09/README.md) covers the Blender retract mechanism, runtime actuator, runway support, steering, brakes, replay and exported-package captures.

The [AV-09-F flap evidence](avanti-flaps/AV-09/README.md) covers the manufacturer's detents and elevator mix, estimated aerodynamic model, sampled travel, keyboard/controller/AUX integration, paired input-tape comparisons and exact replay.

The simulator name is Ventage Jet; the source aircraft is the SebArt Avanti S (A200). Start with [family research](avanti-s-family-research.md), the [integration audit](avanti-s-integration-audit.md), and [AV-06 physics model](avanti-s-av06-physics-model.md). The current imported model, turbine installation, control rig, collision witnesses and Windows package proof are in [AV-31 Blender integration](avanti-blender/AV-31/README.md), with regeneration in the [asset guide](../../assets/aircraft/avanti-s-a200/README.md). The [v4 contour study](avanti-s-refinement-v4.md) describes the superseded visual blockout. Generated measurements and viewers remain in [research/avanti-s](../../research/avanti-s/). The [Ventage Jet plan](../AVANTI-S-PLAN.md) owns implementation.

### P-51D

Use [family research](p51-family-research.md), the [P-51 flight-realism brief](p51-flight-realism.md), and the [P51-15 airborne results](p51-realism/P51-15/airborne-results.md) with its [ground results](p51-realism/P51-15/ground-results.md) and [source/physics audits](p51-realism/P51-15/physics-audit.md). Silhouette and finish reviews are [P51-02](../../research/p51/p51-02/silhouette/README.md), [visual review v1](p51-visual-review-v1.md) and [visual review v2](p51-visual-review-v2.md). See the [P-51 plan](../P51-PLAN.md), [realism plan](../P51-REALISM-PLAN.md), and [physics derivation](../../research/p51/p51-05/derivation.md).

### Menus and product shell

[Menu investigations](menu-investigations/README.md) is the index for UI- and input-focused probes. Start with [UI-06d](menu-investigations/UI-06d/README.md) for the current interactive launch profile and [UI-20](menu-investigations/UI-20/README.md) for the shell audit. The [menu plan](../MENU-PLAN.md) and [redesign plan](../MENU-REDESIGN-PLAN.md) own follow-up work.

### Flight overlays

[HUD-01…10 evidence](flight-overlays/HUD-01-10/README.md) records the overlay tests, trace identity with overlays on and the per-frame cost. The [flight overlays plan](../plans/flight-overlays.md) owns open work.

### Visual quality and landscape

Tree/forest follow-up: [source and current-code audit, 2026-10-17](tree-forest-quality-2026-10-17.md), with [25 additional investigations](tree-forest-quality-2026-10-17.md#second-round-25-additional-investigations). The [first implementation evidence](visual-quality-implementation/L6a-R1/README.md) records seven retained CC0 forms, a downloaded realistic sapling comparison, same-count irregular forest placement, imported-tree wind, source validation and native checks. The [tree/forest quality plan](../plans/tree-forest-quality.md) retains remaining qualification gates; no tree geometry was modeled.

Grass-specific follow-up: [44 source investigations, 2026-10-17](grass-quality-2026-10-17.md), comprising the original 20 plus 24 additional studies of Godot documentation, free assets, papers, libraries, forums and Reddit. The [grass quality plan](../plans/grass-quality.md) maps findings to implementation steps, triggers and acceptance criteria. [Opt-in implementation evidence](visual-quality-implementation/grass-quality/README.md) covers shared photographic turf, species allocation, imported wind and the remaining full-session/owner gates.

Current implementation guidance is in the [visual quality guide](../VISUAL-QUALITY-PLAN.md) and [landscape guide](../LANDSCAPE-PLAN.md). The [landscape-upgrade evidence index](landscape-upgrade/README.md) preserves LU-00…27 verification and remaining limits. Evidence entry points:

- Direction, sources and baseline: [landscape research](landscape-research.md), [visual tools](visual-quality-tools-2026-10-05.md), [tree resources](tree-resource-review-2026-10-06/README.md), and [asset-source catalog](asset-sources-catalog-2026-10-06.md).
- Readability and rendering: [VQ-01a/b capture protocol](visual-quality-implementation/VQ-01a/README.md), [L6c blinded owner kit](visual-quality-implementation/L6c/README.md), [VQ-04a projected silhouette](visual-quality-implementation/VQ-04a/README.md), [VQ-05 propeller blur](visual-quality-implementation/VQ-05/README.md), [L9e filtered turf](visual-quality-implementation/L9e/README.md), and [L15b tree motion](visual-quality-implementation/L15b/README.md), [L15d cloud shadows](visual-quality-implementation/L15d/README.md).
- Field details and upgrade evidence: [L10c barrier](visual-quality-implementation/L10c/README.md), [L10d contact cue](visual-quality-implementation/L10d/README.md), [landscape improvements](landscape-improvement-2026-10-07/README.md), [LU-00–07 upgrade evidence](landscape-upgrade/README.md), and [LU-05 collision report](landscape-upgrade/LU-05/collision-report.md).
- Scenery source rationale: [field imagery](scenery-investigations/05-landscape-image-review.md), [tree review](tree-resource-review-2026-10-06/README.md), and the [landscape research index](landscape-investigations/README.md).

### Time of day

The [time-of-day guide](../TIME-OF-DAY-PLAN.md) owns selectable time, editing and progression. Begin with [TOD-00 architecture and sources](time-of-day-investigations/TOD-00/README.md), then [TOD-09b lighting updates](time-of-day-investigations/TOD-09b/README.md) and [TOD-09c1 clock/checkpoint evidence](time-of-day-investigations/TOD-09c1/README.md). Primary field-world sources are in [2026-10-10 research](field-world/web-research-2026-10-10.md); the related world-flow and night kit are indexed below.

### Scenery and field life

The [scenery guide](../SCENERY-PLAN.md) records current default-on behavior and open acceptance. Research starts with [prop sources](scenery-investigations/01-prop-asset-sources.md), [flora and ambience](scenery-investigations/02-flora-and-ambience.md), [field-layout references](scenery-investigations/03-rc-field-layout-references.md) and [Godot techniques](scenery-investigations/04-godot-techniques-and-prior-art.md). Implementation evidence: [SC-01](scenery-implementation/SC-01/README.md), [SC-02a](scenery-implementation/SC-02a/README.md), [SC-03](scenery-implementation/SC-03/README.md) and [SC-25](scenery-implementation/SC-25/README.md).

### Field world (time of day and night)

The [field-world guide](../FIELD-WORLD-PLAN.md) owns composition and night acceptance. Key evidence: [FW-02 parity](field-world/FW-02/README.md), [FW-20 ephemeris](field-world/FW-20/README.md), [FW-23 night rendering](field-world/FW-23/README.md), [FW-24 stars](field-world/FW-24/README.md), [FW-35 aircraft/field lights](field-world/FW-35/README.md), and the [world tools](../../tools/world/README.md).

[FW-MOON-00 moon audit and sources](field-world/FW-MOON-00/README.md), 2026-10-19, audits the current moon, measures the ephemeris against the NASA SVS 2026 hourly table, surveys where the pilot can see the moon, and registers texture, photometry, earthshine, orientation, extinction, halo, night-vision and eclipse sources ([manifest](field-world/FW-MOON-00/sources.json); local copies in the ignored `references/moon/`). The [moon plan](../plans/moon.md) owns the proposed FW-MOON-01…14.

[FW-76 sky/cloud planning research](field-world/FW-76/README.md) compares free Godot cloud resources, renderer constraints, tutorials, first-hand Reddit reports and primary storm/wind references, including night lightning, reusable bolt VFX and CC0 thunder recordings. The [implementation plan](../plans/sky-clouds-weather.md) owns proposed FW-76–90, with electrical-storm delivery in FW-84a–e; this source review is not an addon, performance or physical-validation result.

[FW-78/82 implementation evidence](field-world/FW-78/README.md) records the sky editor, preferences, deterministic transport and checkpoint contracts. [FW-79](field-world/FW-79/README.md) retains the initial native nine-profile and night-storm gallery; [FW-83](field-world/FW-83/README.md) records the subsequent world-anchored distant cloud bank, rain curtain, CC0 texture intake and day/dusk/moonlit views. [FW-84](field-world/FW-84/README.md) records the electrical event/mesh/audio slice and free-resource provenance. Spatial storms/tornadoes and final flight/performance/export qualification remain open.

### Immersive audio

The [audio guide](../AUDIO-PLAN.md) owns the current soundscape. Read [AUD-01 sources and licenses](audio/AUD-01/sources.md), [AUD-02 asset record](audio/AUD-02/assets.md), [AUD-03 integration](audio/AUD-03/README.md), [AUD-04 acceptance](audio/AUD-04/README.md), [AUD-05 export qualification](audio/AUD-05/README.md), and the [AUD-06/07 bench and first fixes](audio/AUD-06/README.md) for the [audio realism plan](../plans/audio-realism.md). The earlier [G3b engine-audio research](audio/G3b/README.md) is a separate responsive-engine path.

### Smoke

The [smoke guide](../SMOKE-PLAN.md) records the unintegrated feature and its probe-first constraints. Research entry points are [exhaust smoke](rc-exhaust-smoke.md), [smoke investigations](smoke-investigations/README.md), and the [Godot emission probe](smoke-investigations/godot-evidence/README.md).

### Wind

The [wind guide](../WIND-PLAN.md) tracks physical wind and visual response. Begin with [primary sources](wind-physics-primary-sources.md), [implementation evidence](wind-implementation/README.md), [M5-W04a turbulence](wind-implementation/M5-W04a/README.md), and the [investigation index](wind-investigations/README.md). Atmospheric density research is in [M5-ATM-1](atmosphere/M5-ATM-1/kernel/README.md) and [M5-ATM-2/3](atmosphere/M5-ATM-2/README.md).

The [2026-10-19 wind, thermals and vortices source collection](flight-dynamics/rc-validation-library-2026-10-18/wind-weather/README.md) adds acquired atmospheric studies, terrain benchmarks, selected UAV/lidar numeric files and Earth dust-devil observations, with measured, inferred and modeled evidence kept explicit.

### Helicopter and shared rotor foundations

[HELI-01](helicopter/HELI-01/README.md) records the aircraft and source survey. [HELI-03a/04](helicopter/HELI-04/README.md) supplies the steady inflow reference and published crossflow seams; [HELI-04-R1](helicopter/HELI-04-R1/README.md) qualifies dimensional transient flow with prescribed events. [HELI-05/05a](helicopter/HELI-05/README.md) verifies main-rotor loads/flapping and the fixed-body joint stage; [HELI-06a](helicopter/HELI-06/README.md) verifies the standalone linearized tail. [HELI-13](helicopter/HELI-13/README.md) verifies the pure swash kernel. [HELI-25a](helicopter/HELI-25/README.md) audits and exports the supplied HX-700 Blender visual. The [helicopter plan](../plans/helicopter.md) owns remaining aircraft, session and acceptance work.

[HELI-06b/c](helicopter/HELI-06b/README.md) records the passive airframe extension, source-sign audit, joint aerodynamic stand and unresolved cost gate. [HELI-07/08](helicopter/HELI-07/README.md) audits drivetrain/rotor-momentum ownership and remaining finite-startup/freewheel requirements.

[HELI-09](helicopter/HELI-09/README.md) records the immutable prepared aerodynamic stage, parity and invalid-input tests, and paired compact-hover timing.

[HELI-20](helicopter/HELI-20/README.md) records the implemented flat-pad trainer, passive static skid support, low-RPM/stop lifecycle, 30 repeated ground flights, checkpoint/phase replay, separate laboratory FBL profile and remaining performance/physical gates.

[HELI-30-NIGHT](helicopter/HELI-30-NIGHT/README.md) records the dedicated RC helicopter night kit, blade-side orientation cues, ground lamp, automatic/manual modes, native captures and presentation verification.

### Drone racing (shared-foundation review)

[DR-01](drone-racing/DR-01/README.md) records the identified quadrotor models and datasets, small-propeller data limits, Betaflight rate and mixer semantics, racing formats and timing systems, FPV camera and OSD facts, Compatibility-renderer limits and the code-seam map for a multirotor. The [drone racing plan](../plans/drone-racing.md) consumes HELI's shared inflow evidence; multirotor flight and racing remain proposed.

### Cross-aircraft

[Aircraft reference index](aircraft-reference-index.md) maps the owner-supplied local references by aircraft identity; the source files themselves are local only. [RC-class aerodynamic data sources](flight-dynamics/rc-aero-data-sources.md) registers flight-identified and wind-tunnel data of other RC airframes (Ultra Stick 25e/120 incl. NASA FASER, ShowTime 50, scale Cessna) with URLs and hashes.

[RC flight-dynamics validation library, 2026-10-18](flight-dynamics/rc-validation-library-2026-10-18/README.md) expands the scientific source collection with Stik-family studies, other RC airplanes, jets, helicopters, sailplanes, flying-wing research, real flight logs, low-Reynolds polars and propeller/slipstream experiments. Downloaded originals remain local-only under ignored `references/`; topic manifests and the searchable catalogue retain provenance and comparison limits.

The [2026-10-19 further aircraft and flight recordings](flight-dynamics/rc-validation-library-2026-10-18/more-flight-models/README.md) add Mini Talon, Sky Surfer/Skysurfer, RC Cessna 182, Cyclone tailsitter, experimental-aircraft studies and selected multirotor numeric records, distinguishing processed measurements, published plots and inaccessible originals.

## Naming

| Pattern | Use | Example |
| --- | --- | --- |
| `<track>-<topic>.md` | Topic report | `extra-300-integration-audit.md` |
| `<track>-model-v<N>[-<part>].md` | Model revision | `ugly-stik-model-v3-wing.md` |
| `<track>-<topic>-YYYY-MM-DD.md` | Dated snapshot | `visual-quality-tools-2026-10-05.md` |
| `<track>-investigations/NN-<topic>.md` | Numbered research, indexed by its README | `landscape-investigations/04-trees-and-impostors.md` |
| `<area>-implementation/<STEP-ID>/` | Step evidence | `visual-quality-implementation/L6b/` |
| `research/<track>/<step-id>/` | Reproducible scripts and data | `research/extra-300/ex05/` |

## Adding research

1. Put reports in `docs/research/` and scripts/raw data in root `research/<track>/<step>/`. Record date, sources and licenses, method, result, limits and reproduction command when available.
2. Keep evidence beside the report or in its step folder. Link the report from the owning guide and this index; merge reusable lessons into [LEARNINGS.md](../../LEARNINGS.md#keeping-this-useful).
3. Do not link local-only `references/` or ignored `app/captures/` as repository artifacts. Third-party assets need redistribution-compatible licenses and a `sources.json` with author, URL, license and hash.
