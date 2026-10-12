# Research index

`docs/research/` contains investigation reports and step evidence. This index points to the best starting document for each topic; detailed test records remain beside their step. Write new research in English. Older Spanish reports are translated when revised. See the [documentation map](../README.md) for document roles and the [initial research notebook](initial-notebook.md) for pre-Gate 1 background.

## Two folders, one rule

| Location | Purpose | Example |
| --- | --- | --- |
| `docs/research/` | Reports, sources, measurements, probes and step evidence | [VQ-04a](visual-quality-implementation/VQ-04a/README.md) |
| root `research/` | Reproducible scripts, input data and aircraft measurement pipelines | [Extra 300S derivation](../../research/extra-300/ex05/derivation.md) |

Some tools use local-only material from `references/`; their reports say when a fresh clone cannot reproduce the original measurement. Commit the resulting evidence and source identity, not private reference files.

## Whole-project audit

- [Branch integration, 2026-10-10](branch-integration-2026-10-10.md) records merge decisions and clean-checkout checks.
- [PT1h release-readiness audit](release-readiness/PT1h/README.md) reconciles code, documents and rc6 evidence; [tool workflows](../TOOLS.md) lists current commands and measurement limits.
- [Project technical audit](project-audit-2026-10-06/README.md) reviews physics, runtime, tests, export and roadmap at its recorded commit. Its recommendations are planning input, not proof that issues are fixed.
- [Graveacre asset workflow review](graveacre-ai-workflow-2026-10-09.md) records primary links, access limits and practical asset-pipeline findings.

## Entry points per track

### Ground physics

[GP-00–05 evidence index](ground-physics/README.md) covers terrain, per-wheel contact, spin and suspension, profile/session integration, traces, numerical checks and remaining physical calibration. The [integrated ground model](ground-physics/GP-05/README.md) records current scope and open gates.

### Aircraft standardization

[AS-00–05 evidence index](aircraft-standardization/README.md) covers the fleet audit, v2 contract/schema, source migration, authoring template and verification. The [aircraft data contract](../../AIRCRAFT_CONTRACT.md) defines current authoring; measured aircraft mass properties and physical validation remain separate work.

### Extra 300S flight realism

[EX-06/08/09 realism audit](extra-300-realism/README.md) links the manual/source audit, corrections, behavior matrix, regression results and remaining physical gaps. The [Extra 300S plan](../EXTRA-300-PLAN.md) owns aircraft implementation; the research records realism findings and remaining physical gaps.

### Turbo Timber Evolution

[TT-00](timber-integration/TT-00/README.md) starts the CAD/import and code-seam review. Follow-ups are in [TT-00-R1](timber-integration/TT-00-R1/README.md); the [integration plan](../TIMBER-INTEGRATION-PLAN.md) owns the model and electric-flight handoff.

### Desktop delivery

Start with [DT-00](desktop-delivery-investigations/DT-00/README.md), then see [DT-00-R1](desktop-delivery-investigations/DT-00-R1/README.md) and [DT-00-R2](desktop-delivery-investigations/DT-00-R2/README.md) for platform, installer, display, performance and native-test research. The [desktop delivery plan](../DESKTOP-DELIVERY-PLAN.md) tracks acceptance.

### Roadmap knowledge base (all phases)

[Roadmap investigations](roadmap-investigations/README.md) collects pre-work research for numerics, aerodynamics, propulsion, ground handling, radio, weather, validation, aircraft data and presentation. Read the relevant phase brief before starting its implementation step.

### Crash and damage

[Crash investigation index](crash-damage-investigations/README.md) covers contact diagnostics, structural-source work and presentation evidence. The [crash and damage guide](../CRASH-DAMAGE-PLAN.md) separates implemented experimental effects from structural validation and damaged-flight work.

### Flight model and simulation

Use the [flight-model audit](flight-model-robustness-audit.md), [repair implementation record](flight-repair-implementation.md) and [D8b-R2 pull-up investigation](flight-robustness/D8b-R2/README.md) for the main handling history. Current implementation boundaries are in [STACK](../../STACK.md); the [roadmap](../../ROADMAP.md) owns remaining gates.

| Topic | Evidence entry points |
| --- | --- |
| Aerodynamics and wake | [D11d induced flow](aero-consistency/D11d/README.md), [E0a2a/b downwash](aero-consistency/E0a2b/README.md), [D11f yaw damping](aero-consistency/D11f/README.md), [D11g rate derivatives](aero-consistency/D11g/README.md), [E0b1 actuator-disc wake](propwash/E0b1/README.md), [E0b6 swirl](propwash/E0b6/README.md), [E0b6p cost work](propwash/E0b6p/README.md), [E0b7 observation preparation](propwash/E0b7/README.md) |
| Simulation state, replay and cost | [H4–H5 profiling](simulation-state/H4-H5/README.md), [H8 checkpoints](simulation-state/H8/README.md), [H9 tolerance replay](simulation-state/H9/README.md), [H11 contacts](simulation-state/H11/README.md), [H12 local-strip aero](simulation-state/H12/README.md), [H13 slipstream](simulation-state/H13/README.md), [H14 tilted shaft](simulation-state/H14/README.md), [H15 attached flow](simulation-state/H15/README.md), [Gate P native-kernel comparison](simulation-state/Gate-P/README.md) |
| Ground handling and circuits | [E5a taildragger breadth](ground-contact/E5a/README.md), [E3b2 runway equilibrium](ground-contact/E3b2/README.md), [E3c1a landing baseline](ground-contact/E3c1a/README.md), [E3c2a circuit](ground-contact/E3c2a/README.md), [E4a replay regression](ground-contact/E4a/README.md), [PT2 pilot preparation](ground-contact/PT2/README.md) |
| Propulsion | [G1a1 propeller sources](propulsion/G1a1/README.md), [G1b1 operating range](propulsion/G1b1/README.md), [G2a coupled shaft](propulsion/G2a-RK4/README.md), [EL1a-R1 sources](propulsion/EL1a-R1/README.md), [EL1a-R2 implementation research](propulsion/EL1a-R2/README.md), [EL2a-P3 optimization](propulsion/EL2a-P3/README.md), [EL2a-E1 ground scenarios](propulsion/EL2a-E1/README.md); see the [electric propulsion plan](../ELECTRIC-PROPULSION-PLAN.md) |
| Validation and data | [VAL-3 reference dashboard](validation/VAL-3/README.md), [VAL-5a weighing](validation/VAL-5a/README.md), [VAL-6a inertia](validation/VAL-6a/README.md), [VAL-7a propeller](validation/VAL-7a/README.md), [VAL-7b throttle](validation/VAL-7b/README.md), [VAL-7c uncertainty](validation/VAL-7c/README.md), [VAL-8a ground-run video](validation/VAL-8a/README.md), [VAL-8b roll video](validation/VAL-8b/README.md), [DATA-1 freshness](aircraft-validation/DATA-1/README.md), [DATA-4a schema checks](aircraft-validation/DATA-4a/README.md) |
| Weather and input | [wind implementation](wind-implementation/README.md), [M5-W04a turbulence](wind-implementation/M5-W04a/README.md), [M5-ATM-1 density kernel](atmosphere/M5-ATM-1/kernel/README.md), [D6b-R2 calibration rearming](radio-input/D6b-R2/README.md), [F1 diagnostics](radio-input/F1/README.md), [F3b1 event cost](radio-input/F3b1/README.md), [F6a latency capture](radio-input/F6a/README.md), [F6b latency reduction](radio-input/F6b/README.md) |
| Integrity checks | [C7-R2 trace metadata](trace-integrity/C7-R2/README.md), [D4-R2 trim integrity](trim-integrity/D4-R2/README.md), [DATA-3 input identity](aircraft-validation/DATA-3/README.md) |

### Ugly Stik

Start with the [source and local-reference map](ugly-stik-resources.md), [model investigations](ugly-stik-investigations/README.md), [current model record](ugly-stik-model-v4.md), and [engine v5 evidence](ugly-stik-engine-v5.md). Visual and authoring work is indexed under [visual investigations](ugly-stik-visual-investigations/README.md) and [tooling investigations](ugly-stik-tooling-investigations/README.md). See the [Ugly Stik plan](../UGLY-STIK-PLAN.md) and reproducible [model pipeline](../../research/ugly-stik/).

### Extra 300S

Read the [family research](extra-300-family-research.md), [integration audit](extra-300-integration-audit.md), [realism audit](extra-300-realism/README.md), and [generated physics derivation](../../research/extra-300/ex05/derivation.md). Shared authoring tools are in [extra-aircraft-tooling](extra-aircraft-tooling/README.md). The [EXTRA-300-PLAN](../EXTRA-300-PLAN.md) owns aircraft implementation.

### Avanti S

Start with [family research](avanti-s-family-research.md), the [integration audit](avanti-s-integration-audit.md), and [AV-06 physics model](avanti-s-av06-physics-model.md). For appearance, see the [latest contour refinement](avanti-s-refinement-v4.md); generated measurements and viewers remain in [research/avanti-s](../../research/avanti-s/). The [Avanti S plan](../AVANTI-S-PLAN.md) owns implementation.

### P-51D

Use [family research](p51-family-research.md), the [P-51 flight-realism brief](p51-flight-realism.md), and the [P51-15 airborne results](p51-realism/P51-15/airborne-results.md) with its [ground results](p51-realism/P51-15/ground-results.md) and [source/physics audits](p51-realism/P51-15/physics-audit.md). Silhouette and finish reviews are [P51-02](../../research/p51/p51-02/silhouette/README.md), [visual review v1](p51-visual-review-v1.md) and [visual review v2](p51-visual-review-v2.md). See the [P-51 plan](../P51-PLAN.md), [realism plan](../P51-REALISM-PLAN.md), and [physics derivation](../../research/p51/p51-05/derivation.md).

### Menus and product shell

[Menu investigations](menu-investigations/README.md) is the index for UI- and input-focused probes. Start with [UI-06d](menu-investigations/UI-06d/README.md) for the current interactive launch profile and [UI-20](menu-investigations/UI-20/README.md) for the shell audit. The [menu plan](../MENU-PLAN.md) and [redesign plan](../MENU-REDESIGN-PLAN.md) own follow-up work.

### Visual quality and landscape

Current implementation guidance is in the [visual quality guide](../VISUAL-QUALITY-PLAN.md), [landscape guide](../LANDSCAPE-PLAN.md), and [landscape-upgrade plan](../../LANDSCAPE_UPGRADE_PLAN.md). Evidence entry points:

- Direction, sources and baseline: [landscape research](landscape-research.md), [visual tools](visual-quality-tools-2026-10-05.md), [tree resources](tree-resource-review-2026-10-06/README.md), and [asset-source catalog](asset-sources-catalog-2026-10-06.md).
- Readability and rendering: [VQ-01a/b capture protocol](visual-quality-implementation/VQ-01a/README.md), [L6c blinded owner kit](visual-quality-implementation/L6c/README.md), [VQ-04a projected silhouette](visual-quality-implementation/VQ-04a/README.md), [L9e filtered turf](visual-quality-implementation/L9e/README.md), and [L15b tree motion](visual-quality-implementation/L15b/README.md), [L15d cloud shadows](visual-quality-implementation/L15d/README.md).
- Field details and upgrade evidence: [L10c barrier](visual-quality-implementation/L10c/README.md), [L10d contact cue](visual-quality-implementation/L10d/README.md), [landscape improvements](landscape-improvement-2026-10-07/README.md), [LU-00–07 upgrade evidence](landscape-upgrade/README.md), and [LU-05 collision report](landscape-upgrade/LU-05/collision-report.md).
- Scenery source rationale: [field imagery](scenery-investigations/05-landscape-image-review.md), [tree review](tree-resource-review-2026-10-06/README.md), and the [landscape research index](landscape-investigations/README.md).

### Time of day

The [time-of-day guide](../TIME-OF-DAY-PLAN.md) owns selectable time, editing and progression. Begin with [TOD-00 architecture and sources](time-of-day-investigations/TOD-00/README.md), then [TOD-09b lighting updates](time-of-day-investigations/TOD-09b/README.md) and [TOD-09c1 clock/checkpoint evidence](time-of-day-investigations/TOD-09c1/README.md). Primary field-world sources are in [2026-10-10 research](field-world/web-research-2026-10-10.md); the related world-flow and night kit are indexed below.

### Scenery and field life

The [scenery guide](../SCENERY-PLAN.md) records current default-on behavior and open acceptance. Research starts with [prop sources](scenery-investigations/01-prop-asset-sources.md), [flora and ambience](scenery-investigations/02-flora-and-ambience.md), [field-layout references](scenery-investigations/03-rc-field-layout-references.md) and [Godot techniques](scenery-investigations/04-godot-techniques-and-prior-art.md). Implementation evidence: [SC-01](scenery-implementation/SC-01/README.md), [SC-02a](scenery-implementation/SC-02a/README.md), [SC-03](scenery-implementation/SC-03/README.md) and [SC-25](scenery-implementation/SC-25/README.md).

### Field world (time of day and night)

The [field-world guide](../FIELD-WORLD-PLAN.md) owns composition and night acceptance. Key evidence: [FW-02 parity](field-world/FW-02/README.md), [FW-20 ephemeris](field-world/FW-20/README.md), [FW-23 night rendering](field-world/FW-23/README.md), [FW-24 stars](field-world/FW-24/README.md), [FW-35 aircraft/field lights](field-world/FW-35/README.md), and the [world tools](../../tools/world/README.md).

### Immersive audio

The [audio guide](../AUDIO-PLAN.md) owns the current soundscape. Read [AUD-01 sources and licenses](audio/AUD-01/sources.md), [AUD-02 asset record](audio/AUD-02/assets.md), [AUD-03 integration](audio/AUD-03/README.md), [AUD-04 acceptance](audio/AUD-04/README.md), and [AUD-05 export qualification](audio/AUD-05/README.md). The earlier [G3b engine-audio research](audio/G3b/README.md) is a separate responsive-engine path.

### Smoke

The [smoke guide](../SMOKE-PLAN.md) records the unintegrated feature and its probe-first constraints. Research entry points are [exhaust smoke](rc-exhaust-smoke.md), [smoke investigations](smoke-investigations/README.md), and the [Godot emission probe](smoke-investigations/godot-evidence/README.md).

### Wind

The [wind guide](../WIND-PLAN.md) tracks physical wind and visual response. Begin with [primary sources](wind-physics-primary-sources.md), [implementation evidence](wind-implementation/README.md), [M5-W04a turbulence](wind-implementation/M5-W04a/README.md), and the [investigation index](wind-investigations/README.md). Atmospheric density research is in [M5-ATM-1](atmosphere/M5-ATM-1/kernel/README.md) and [M5-ATM-2/3](atmosphere/M5-ATM-2/README.md).

### Cross-aircraft

[Aircraft reference index](aircraft-reference-index.md) maps the owner-supplied local references by aircraft identity; the source files themselves are local only.

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
