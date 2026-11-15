# AERIS-120 integration investigation

**Research date:** 2026-11-15. **Track:** A120. **Scope:** documentation, offline reference arithmetic, external-data analysis and engineering preparation for the user's existing 120 cc gasoline 3D aerobatic aircraft. No runtime implementation, new 3D model, real-aircraft test or simulator flight is claimed.

The [active integration plan](../../plans/aeris-120-3d-gas.md) owns milestones and status. This directory preserves the evidence and reasoning behind that plan.

| Document | Purpose |
| --- | --- |
| [Source register](sources.md) | Primary references, exact model/version distinctions, evidence classification and unknowns |
| [Repository integration audit](integration-audit.md) | Pinned source paths, implemented mechanisms and remaining integration gaps |
| [Physics and propulsion](physics-and-propulsion.md) | Frames, mass properties, full-angle aerodynamics, engine/propeller coupling and bounded approximations |
| [Controls and validation](controls-and-validation.md) | Radio/servo semantics, handling criteria, maneuver cards and staged acceptance |
| [Follow-up evidence](evidence-update-2026-11-15.md) | Instrumented RC flights, configuration-specific engine/actuator evidence, identifiability and task-based handling |
| [Developer work packages](development-briefs.md) | Seven bounded briefs with dependencies, observables and discriminating checks |
| [Offline research and acquisition kit](../../../research/aeris-120/README.md) | Reproducible scalar calculations, an identified external transient-data benchmark, existing reducers and a blank pilot-evaluation record |

## Source identity

The source audit uses `main` commit `ad21070798bfb9658785576a9c0b8bfc9a71fc7f`, tree `cca9ad99ee0d1a6b5f70f1a960c8f8f36f488bf8`. The old `codex/m1-native-validation-20261106` branch is contained in that main baseline. The newer `codex/apple-silicon-native-default-20261113` head `f5219d7d682a7f2470bbf2af88c2cf64c1fe7833` diverges: main is one commit ahead and sixteen behind. It was inspected for relevance, not merged; recheck native admission and delivery when implementing on a later base.

The target dimensions, 2.64 m span / 2.60 m length / 1.2408 m² wing area, are prior project design inputs. No AERIS model file was measured during this investigation. Manufacturer aircraft are comparators, not proof of the user's mass properties or aerodynamic coefficients.

## Findings that change the implementation order

- Reuse the existing `VehicleModel`, float64 RK4, aircraft-v2 and coupled shaft/fuel architecture.
- Gasoline is already represented by the legacy `glow_prop` family and `gasoline_bsfc_v1`; adding an unsupported propulsion kind is unnecessary.
- The main 3D blockers are a common gasoline hub-flow model, wing-inclusive propwash and compatible swirl/transport, followed by calibrated control/post-stall response.
- Existing full-angle local laws and separated-wing moment support are useful foundations. They do not establish validated spin/harrier behavior or dynamic stall.
- The Mejzlik prop reference is simulated at 5,000 RPM and has a separate RPM limit; engine headline output cannot be treated as a complete installed propulsion model.
- Correct radio curve ownership, actual surface motion, camera conditions and end-to-end latency are part of handling evaluation.

## Verification scope and continuation

The initial commit was limited to Markdown documentation and its navigation/decision records. Its verification consisted of source inspection, unit/algebra checks, local-link/anchor checking with the repository's existing documentation checker functions, and an independent technical review. Runtime tests, physical measurements, pilot flights, exported-package checks and target-hardware performance remain implementation gates. No generated aircraft data, runtime code, assets, goldens or release behavior is changed.

Documentation checks passed: 44 new local links/anchors resolve; the geometry, stall-sensitivity and propeller-point calculations were recomputed; all 41 named test files in the audit exist at the pinned commit. Independent review corrected the distinction between fixed-carrier shaft dynamics and relative shaft/body coupling, and clarified that the seven-plus-one servo count belongs to the EF donor. No material review findings remained in the final documentation candidate. These checks establish the plan's internal consistency, not aircraft realism.

The follow-up adds instrument/source-limit research, task-specific development briefs and an isolated Python reference study. Its eight focused checks include known-answer/scaling/domain cases and a synthetic in-memory consistency comparison with the existing static-prop reducer. The generated snapshot includes input/calculator identities and explicitly refuses a physical-acceptance claim. Independent review identified and corrected misleading source-point wording for edited calculator inputs. Detailed current verification is recorded in the [kit](../../../research/aeris-120/README.md#verification-of-this-kit); no A120-01…12 or L0–L3 gate is closed by these research checks.

A separately identified CC BY 4.0 small-propeller dataset supplies a reproducible six-row transient comparison. Published source checksums and the full-array coefficient/deviation definitions were checked; originals remain outside Git. This is an external processed-measurement benchmark with explicit filtering/uncertainty limits, not a target-aircraft calibration or a new flight law.

Read the existing [deferred 3D proposal](../flight-mechanics-stall-hover-knife-edge-2026-10-18.md#integration-disposition-2026-10-26) before reusing its equations: historical candidate test counts are not accepted current mechanics or aircraft measurements.
