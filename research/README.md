# Research tools and inputs

This directory holds reproducible experiments, measurement reducers, source data and aircraft generators. Reports and accepted evidence live in the [research index](../docs/research/README.md). The [ownership registry](../docs/README.md#tracks-plans-and-step-ids) assigns tracks and step IDs; [TOOLS](../docs/TOOLS.md) owns setup and commands.

## Find the right collection

Folder names can differ between tools and reports. Use this map rather than renaming historical paths. A linked folder contains several experiments; read the selected step's README or report before running it.

### Physics, data and validation

| Tools and inputs | Purpose | Evidence / authoritative home |
| --- | --- | --- |
| [aero](aero/) | Aerodynamic consistency experiments | [Aerodynamics and wake](../docs/research/README.md#flight-model-and-simulation) |
| [d1](d1/) | Early stall-model checks | [Flight repair history](../docs/research/flight-repair-implementation.md) |
| [aircraft-data](aircraft-data/) | Data preparation, stall search and schema checks | [Aircraft validation](../docs/research/aircraft-validation/), [aircraft contract](../docs/AIRCRAFT_CONTRACT.md) |
| [aircraft-standardization](aircraft-standardization/) | Model manifests, migration and conformance | [AS evidence](../docs/research/aircraft-standardization/README.md) |
| [flight-dynamics](flight-dynamics/) | Elevator, climb/trim and power-step probes | [Flight-dynamics reports](../docs/research/flight-dynamics/) |
| [flight-modes](flight-modes/) | Modal identification and response studies | [Validation tools](validation/README.md), [VAL evidence](../docs/research/validation/) |
| [flight-robustness](flight-robustness/) | Pull-up, regime and reference-comparison experiments | [D8b-R2](../docs/research/flight-robustness/D8b-R2/README.md) |
| [flight-test](flight-test/README.md) | Standard flight card, pilots and fleet comparisons | [FT baselines](../docs/research/flight-test/) |
| [sensitivity](sensitivity/) | Parameter sensitivity sweeps | [Validation research](../docs/research/roadmap-investigations/08-validation-flight-testing.md) |
| [validation](validation/README.md) | Weighing, inertia, propeller, RPM, video and uncertainty reducers | [VAL evidence](../docs/research/validation/) |
| [propulsion](propulsion/) | Propeller import, shaft/electric coupling and operating-range studies | [Propulsion evidence](../docs/research/propulsion/) |
| [propwash](propwash/) | Wake geometry, flow, measurements and optimization candidates | [Propwash evidence](../docs/research/propwash/) |
| [glow-engines](glow-engines/README.md) | Two-/four-stroke profiles, installation generators and verification | [Glow operating guide](../docs/GLOW-ENGINES.md), [NITRO evidence](../docs/research/glow-engines/) |
| [battery](battery/README.md) | Cell fits, pack data and integration verification | [Battery evidence](../docs/research/battery/) |
| [fuel-systems](fuel-systems/) | Fuel-source data, tank/installations and mass/balance experiments | [Fuel standard](../docs/FUEL-SYSTEM.md), [FUEL evidence](../docs/research/fuel-systems/) |
| [ground-contact](ground-contact/) | Taildragger and contact experiments | [Ground-contact evidence](../docs/research/ground-contact/) |
| [ground-physics](ground-physics/README.md) | Terrain, suspension, wheel and gear audits | [GP evidence](../docs/research/ground-physics/README.md) |
| [landing](landing/) | Circuit and landing replay/sensitivity experiments | [Ground-handling evidence](../docs/research/README.md#flight-model-and-simulation) |
| [performance](performance/README.md) | Session/native timing and texture inventory reducers | [VQ evidence](../docs/research/visual-quality-implementation/), [performance commands](../docs/TOOLS.md#native-performance-experiments) |
| [native-slipstream](native-slipstream/) | Isolated native slipstream comparison | [Gate P evidence and limits](../docs/research/simulation-state/Gate-P/README.md) |
| [physics-audit-2026-10-14](physics-audit-2026-10-14/) | Audit probes and bounded remediation experiments | [Dated physics audit](../docs/research/physics-audit-2026-10-14/README.md) |

### Aircraft and other vehicles

| Tools and inputs | Evidence / authoritative home |
| --- | --- |
| [ugly-stik](ugly-stik/) | [Stik sources and model history](../docs/research/README.md#ugly-stik), [current guide](../docs/UGLY-STIK-PLAN.md) |
| [extra-300](extra-300/) | [Extra research](../docs/research/README.md#extra-300s), [current guide](../docs/EXTRA-300-PLAN.md) |
| [avanti-s](avanti-s/) | [Ventage Jet research](../docs/research/README.md#ventage-jet), [current guide](../docs/AVANTI-S-PLAN.md) |
| [p51](p51/) | [P-51 research](../docs/research/README.md#p-51d), [current guide](../docs/P51-PLAN.md) |
| [timber](timber/) | [Timber integration evidence](../docs/research/timber-integration/), [current guide](../docs/TIMBER-INTEGRATION-PLAN.md) |
| [helicopter](helicopter/) | [HELI evidence](../docs/research/helicopter/), [experimental session guide](../docs/HELICOPTER.md) |
| [drone-racing](drone-racing/) | [DR evidence](../docs/research/drone-racing/), [remaining plan](../docs/plans/drone-racing.md) |
| [rc-monster-truck](rc-monster-truck/README.md) | [RCV evidence](../docs/research/rc-monster-truck/README.md), [remaining plan](../docs/plans/rc-monster-truck.md) |

### Input, product and incident analysis

| Tools and inputs | Evidence / authoritative home |
| --- | --- |
| [input](input/) | [Radio/input evidence](../docs/research/radio-input/) |
| [radio-latency](radio-latency/README.md) | [F6b latency reduction](../docs/research/radio-input/F6b/README.md) |
| [aircraft-editor](aircraft-editor/) | [Workshop guide and evidence map](../docs/AIRCRAFT-WORKSHOP.md) |
| [flight-overlays](flight-overlays/) | [HUD evidence](../docs/research/flight-overlays/HUD-01-10/README.md) |
| [natural-random](natural-random/) | [NR evidence](../docs/research/natural-random/README.md) |
| [crash-damage](crash-damage/) | [Crash/damage evidence](../docs/research/crash-damage-investigations/README.md) |
| [crash-economics](crash-economics/) | [Replacement-cost evidence](../docs/research/crash-damage-investigations/README.md), [aircraft cost contract](../docs/AIRCRAFT_CONTRACT.md) |

### Presentation, environment and literature

| Tools and inputs | Evidence / authoritative home |
| --- | --- |
| [audio](audio/) | [Audio evidence](../docs/research/audio/), [current guide](../docs/AUDIO-PLAN.md) |
| [camera-views](camera-views/) | [Camera audit](../docs/research/camera-views/CAM-AUD-2026-10-24/README.md), [CAM-23…27 fixes](../docs/research/camera-views/CAM-23-27/README.md), [CAM-02b/17/29](../docs/research/camera-views/CAM-02b-17-29/README.md), [remaining plan](../docs/plans/camera-views.md) |
| [field-world](field-world/) | [World evidence](../docs/research/field-world/), [current guide](../docs/FIELD-WORLD-PLAN.md) |
| [time-of-day](time-of-day/) | [TOD evidence](../docs/research/time-of-day-investigations/), [current guide](../docs/TIME-OF-DAY-PLAN.md) |
| [wind](wind/) | [Wind evidence](../docs/research/wind-implementation/README.md), [current guide](../docs/WIND-PLAN.md) |
| [sun](sun/) | [SUN evidence](../docs/research/sun/), [remaining plan](../docs/plans/sun.md) |
| [scenery](scenery/) | [Scenery evidence](../docs/research/scenery-implementation/), [current guide](../docs/SCENERY-PLAN.md) |
| [visual-quality](visual-quality/) | [Visual evidence](../docs/research/visual-quality-implementation/), [current guide](../docs/VISUAL-QUALITY-PLAN.md) |
| [reference-library](reference-library/) | [Literature manifests, CSV/BibTeX conversion and original-file verification](../docs/research/flight-dynamics/rc-validation-library-2026-10-18/README.md) |

### Early standalone comparisons

- [Float32/float64 integration](float32_vs_float64_integration.mjs): pre-Gate 1 numerical experiment; context in the [initial notebook](../docs/research/initial-notebook.md).
- [Static propeller comparison](compare_static_propeller.py): early model comparison; source interpretation in the same notebook. Current reducers and validation boundaries live in [validation](validation/README.md).

## Preserve reproducibility

Read the step's inputs, pinned dependencies and output policy before execution. Some probes write beside their script by default; choose an explicit fresh scratch directory where supported and preserve accepted results. [TOOLS](../docs/TOOLS.md) owns clean-checkout, mutation and generated-output rules. [test-tools.sh](test-tools.sh) runs the bounded offline regression set; it is not every experiment or physical acceptance.

Ignored `references/` originals are absent from a Git clone. Their source manifests retain URLs, acquisition limits and hashes. Keep raw sources separate from derived CSV, plots and model coefficients; regenerate outputs through the owning pipeline. Do not infer production adoption from an experiment folder or change a historical receipt to match today's source.
