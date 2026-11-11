# OpenRC Simulator — FPV racing drone development handoff

**Prepared and extended:** 11 November 2026. **Settings follow-up:** 34 Betaflight/INAV investigations, 99 proposed setting/integration cases and a scoped 14-evaluation throttle-source probe; see 07–09. **Simulator follow-up:** 28 distinct approaches, 22 consumer-facing products/editions, 23 coded community discussions, 12 proposed experiments and 13 proposed acceptance cases; see 10–12. **Open-source follow-up:** 25 code projects/approaches, exact license/source pins, 19 discussion records, eight excluded or scoped examples and 21 proposed cases; see 13–15. **Audience:** senior Godot, simulation and gameplay developers. **Status:** implementation proposal supported by source audits, executed software probes and dated research. The proposed drone activity remains unimplemented.

**Repository:** [bultodepapas/OpenRCsimulator](https://github.com/bultodepapas/OpenRCsimulator). **Frozen review commit:** [`7bff78490f9af5c1664f47c8ba865a92b3430920`](https://github.com/bultodepapas/OpenRCsimulator/tree/7bff78490f9af5c1664f47c8ba865a92b3430920). **Plan reviewed:** [`docs/plans/drone-racing.md`](https://github.com/bultodepapas/OpenRCsimulator/blob/7bff78490f9af5c1664f47c8ba865a92b3430920/docs/plans/drone-racing.md), revised 21 October 2026. **Engine actually used for the focused probes:** `4.8.beta2.official.cafc17a19`, obtained and hash-verified by the repository's own getter.

## Recommendation

Deliver one experimental, fixed-pitch quad-X FPV racer through the existing float64 `VehicleModel`/`Simulation` architecture. Resolve the controller transaction first, then deliver headless Acro plus complete replay, then a usable free-flight activity, and then a local three-lap race. Keep selected-build physical validation and advanced wake/inflow work as explicit later promotions. Preserve the existing DR-00…41 ownership and step IDs.

The most valuable next change is **DR-16a: pure sampled feedback plus explicit stage access to checkpointed controller output across tick, reset and restore**. The current plant stores motor duties on an object outside the kernel transaction. This review reproduced the resulting mismatch. Adding a PID directly to that object would expand the same problem to integrals, filters, arming and replay.

## Reading order

| File | Purpose | Start here if you own… |
| --- | --- | --- |
| [01_FPV_MASTER_PLAN.md](01_FPV_MASTER_PLAN.md) | Product scope, decisions, dependencies, DR mapping, delivery gates, risk and first implementation sequence | Overall implementation and review |
| [02_ENGINEERING_CONTRACTS.md](02_ENGINEERING_CONTRACTS.md) | Proposed callback ABI, fixed state layouts, strict data, sample ordering, lifecycle, replay and atomic race composition | Kernel, sessions, data or controller integration |
| [03_FLIGHT_DYNAMICS_AND_RESEARCH.md](03_FLIGHT_DYNAMICS_AND_RESEARCH.md) | Pinned Actual-rate math, allocation, shaft/body coupling, four-motor bus, datasets, geometry and provenance | Flight dynamics and controls |
| [04_FPV_RACING_INPUT_AND_PRESENTATION.md](04_FPV_RACING_INPUT_AND_PRESENTATION.md) | FPV mount/projection, input setup, latency, swept gate scoring, event ties and native performance | CAM, UI/input, race, rendering or QA |
| [05_VALIDATION_AND_IMPLEMENTATION_BACKLOG.md](05_VALIDATION_AND_IMPLEMENTATION_BACKLOG.md) | Reviewable work packages, test IDs, pass/fail rules, physical campaign and evidence formats | Implementation scheduling and verification |
| [06_SOURCE_AUDIT_AND_EVIDENCE.md](06_SOURCE_AUDIT_AND_EVIDENCE.md) | Immutable source links, actual gaps, existing test map, executed results and complete reproducer/reference scripts | Verifying the rationale and reproducing the findings |
| [07_BETAFLIGHT_INAV_SETTINGS_RESEARCH.md](07_BETAFLIGHT_INAV_SETTINGS_RESEARCH.md) | 34 source-backed investigations of common settings, firmware differences, OpenRC dispositions and 81 proposed cases | Controls, filters, motors, input, modes and firmware-style setup |
| [08_SETTINGS_SCHEMA_IMPORT_AND_TESTS.md](08_SETTINGS_SCHEMA_IMPORT_AND_TESTS.md) | Typed configuration, profile scopes, safe partial import, default provenance, atomic apply, UI and P17–21 with 18 integration cases | Settings/data/UI/session implementation |
| [09_SETTINGS_EVIDENCE_AND_REFERENCE_PROBE.md](09_SETTINGS_EVIDENCE_AND_REFERENCE_PROBE.md) | Current source pins, 177 anchored references across 50 files, documentation conflicts and complete 14-evaluation source-fragment probe | Reproducing the settings research and its precise evidence limits |
| [10_FPV_SIMULATOR_APPROACHES.md](10_FPV_SIMULATOR_APPROACHES.md) | 28 distinct approaches with examples, user signals, OpenRC decisions and verification work | Product scope, practice, racing, simulation-core and deployment choices |
| [11_FPV_PRODUCT_DECISIONS_AND_EXPERIMENTS.md](11_FPV_PRODUCT_DECISIONS_AND_EXPERIMENTS.md) | Journeys, result/compatibility identities, 12 experiments, 13 proposed cases and P22–P24 | Turning simulator/user research into bounded engineering work |
| [12_SIMULATOR_EVIDENCE_LEDGER.md](12_SIMULATOR_EVIDENCE_LEDGER.md) | 22-product comparison, separate research frameworks, 23 coded user threads and dated source ledger | Checking product claims, version changes and the limits of user evidence |
| [13_OPEN_SOURCE_FPV_AND_DRONE_APPROACHES.md](13_OPEN_SOURCE_FPV_AND_DRONE_APPROACHES.md) | 25 code-backed approaches across FPV frontends, controllers, dynamics, input, interoperability and analysis | Choosing useful open-source patterns and tools |
| [14_OPEN_SOURCE_REUSE_AND_INTEGRATION_PLAN.md](14_OPEN_SOURCE_REUSE_AND_INTEGRATION_PLAN.md) | Reuse decisions, P25/P26, reference/bridge contracts, causal sensors, exact clocks and 21 proposed cases | Turning open-source research into bounded engineering work |
| [15_OPEN_SOURCE_LICENSE_SOURCE_AND_USER_EVIDENCE.md](15_OPEN_SOURCE_LICENSE_SOURCE_AND_USER_EVIDENCE.md) | Exact code/license pins, asset/dependency exceptions, excluded candidates and 19 coded discussions | Verifying reuse scope and distinguishing observed user needs from hypotheses |

Read 00 → 01 → 02 before implementing. Consult 03/04 for the specialized flight/presentation contracts, 05 for acceptance and 06 for current OpenRC code evidence. For settings, read 07 → 08 and use 09 for source/probe evidence. For broader simulator approaches and user needs, read 10 → 11 and consult 12. For this open-source follow-up, read 13 → 14 and use 15 for exact source/license/user evidence. The pack contains sixteen Markdown documents.

## Work already advanced

1. Read the active plan and traced its dependencies against the frozen current source, including the kernel, multirotor plant, electrical and battery laws, controller profiles, catalog, Home preparation, camera, collision and recording adapters.
2. Re-ran the unmodified existing multirotor test on a byte-identical 73-source dependency closure, using a minimal headless project and the pinned engine: **15 checks, 0 failed**. This isolates the mathematical kernel; it does not qualify the full product or renderer.
3. Executed an isolated malformed-k2 probe. Body, continuous state and sampled aux rolled back; `Plant.duties` remained `[0.1, 0.8, 0.8, 0.1]`. A following reset preparation reported a **0.787007672634271 N·m** yaw moment with that stale cache and **0 N·m** after synchronizing the cache to the same accepted aux. The probe reproduces an integration defect; its successful exit means the defect was observed.
4. Ran **20 synthetic reference cases**, including Actual rates, control-mixing signs, rotor momentum/work, common-bus power, electrical-unit conversions, prop clearance, FOV and sampling phase. All passed and repeated with identical JSON. The full script and report are embedded in 06.
5. Pinned Betaflight **4.5.2 / `024f8e13d4e642eb6a380308685b9ea3aa3ef1a2`** as one supported mathematical rate-curve target. This is a deliberately versioned compatibility baseline, not a claim to support newer firmware dumps or the complete firmware controller.
6. Identified a manufacturer dataset with thrust, RPM, voltage, current and rounded torque; preserved the important distinction that its F5146 propeller is **5.1 inches**, not 5.0 inches. Also pinned an OpenRacer asset-intake candidate and documented its unresolved assembly/licensing/geometry work.

7. Extended the plan with 34 settings investigations against current stable BF 2026.6.2 and INAV 9.1.0 source pins, preserving the older rate-only baseline. Added five work packages, versioned import/default/profile rules and explicit simulator capability boundaries.
8. Compiled and executed an extracted current BF throttle path for 14 selected inputs/configurations, repeated identically. For mid/hover/expo 30/70/0, input 0.30 produces 1663 PWM under the stated host/table assumptions, not the continuous-curve value 1700. This is a source-fragment observation, not a full firmware or OpenRC test pass.
9. Investigated 28 distinct simulator approaches, with a 22-product/edition inventory and separate firmware/robotics examples. Coded 23 deliberately selected community threads, retained disagreement and distinguished historical reports from current product claims. This is desk research, not a representative preference survey or hands-on simulator benchmark.
10. Added practice-journey qualification, local feedback/authoring packages P22–P24, explicit result-comparison rules, and 12 proposed experiments with 13 proposed acceptance cases. Independent review corrected milestone dependencies, hold/reset semantics, learning-study carryover and postcommit recording/result distinctions. These cases have not been executed.
11. Inspected 25 separately identified open-source code projects at exact revisions, with literal license/notice files and concrete implementation paths. Retained eight excluded or scoped examples; distinguished firmware from complete plants, shared lineage from independent references, and code grants from assets/dependencies. No external simulator was built or benchmarked in this follow-up.
12. Coded 19 user/developer discussions and proposed optional P25 source-pinned comparisons and P26 firmware-bridge feasibility, plus 21 future cases. Critical review added explicit RC-plus-sensor inputs, causal specific-force sampling, candidate-state rollback and exact clock conventions. These proposals preserve the existing M0–M4 boundaries.

Detailed executed logs, source identities and reproducible commands are in [06](06_SOURCE_AUDIT_AND_EVIDENCE.md) and the settings-specific [09](09_SETTINGS_EVIDENCE_AND_REFERENCE_PROBE.md). The broader simulator ledger is [12](12_SIMULATOR_EVIDENCE_LEDGER.md); the open-source code/license/user ledger is [15](15_OPEN_SOURCE_LICENSE_SOURCE_AND_USER_EVIDENCE.md). Source inspection, qualitative reports, software verification, numerical calculation, manufacturer data and physical validation remain separate evidence classes.

## Decisions proposed by this handoff

| Decision | Disposition |
| --- | --- |
| Simulation | Retain custom 64-bit NED/FRD kernel; rendering converts at the existing boundary. |
| Control | Simulator-owned Acro and bounded Angle training; 240 Hz is an initial hypothesis with a mandatory higher-rate comparison. |
| Controller transaction | New opt-in generic sampled/stage contract; retain legacy callbacks and behavior for existing models. |
| First energy model | Explicit one-quadrant, four-load, one-pack model based on existing EL equations; richer BAT adaptation has a separate identified state layout. |
| First racer | One sourced 5-inch-class assembly; nominal prop diameter, hub geometry and all estimates explicit. The old laboratory quad is never the catalog product. |
| Race authority | Fixed race state inside a composed `VehicleModel` endpoint transition; accepted path evidence and a canonical event order. |
| First track | Upright rectangular gates on one qualified field; tilted/dive gates require a separate collision capability. |
| View | Rigid onboard FPV, full roll, adjustable tilt and explicitly horizontal FOV; one interpolation owner. |
| First release | Experimental free flight can release independently of local racing and physical-fidelity qualification. |
| Open-source reuse | Use identified existing tools and independent references first; one authoritative plant per session, component-specific licenses and no unqualified external controller state. |

These are concrete review proposals. Where implementation must choose a constant, gain or physical assembly, the owning work package states what evidence closes the choice; absent measurements are not replaced by invented tuning values.

## How to adopt these files in the repository

Use this pack as one reviewable handoff. When adopting it, update the existing `docs/plans/drone-racing.md` as the canonical active plan, preserving DR IDs. Place technical contracts and dated research under the existing drone research/documentation homes and link them from that plan. Register accepted architectural decisions in `docs/DECISIONS.md` and ownership changes in `docs/README.md`. Reconcile valuable older research before superseding it. Do not maintain several independent files claiming to own current implementation status.

Before implementation, compare the current repository with the frozen commit and recheck every changed seam. The absence of a feature in the inspected source is not proof of its status on a later branch. The pinned engine, exact source, config identities and evidence scope must accompany each implementation PR.

## Remaining evidence

No selected physical quad was measured; no native 1080p FPV session, exported drone package, radio/goggles latency, full repository suite or playable race was qualified in this review. The exact product build, commercial-source redistribution decisions, controller gains, native target-host budgets and physical flight envelope remain named work items. These gaps do not prevent the proposed headless transaction/controller work from starting.
