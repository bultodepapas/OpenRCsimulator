# Baseline, coverage and interpretation

## Audited identity

Production source: `8d4169f8febfd7d78a028eaa817414217a54f24b`, the current `main` when this investigation started on 28 November 2026. Dedicated documentation/evidence branch: `audit/native-physics-10-specialists-2026-11-28`. [GitHub tracking issue #24](https://github.com/bultodepapas/OpenRCsimulator/issues/24) records the scope and publication.

Before publication, the audit branch fast-forwarded to `c84c2f8b987617a619f7e77397f025daee28a262`. The intervening commits update the native roadmap, a render-preference check and publication-fixture identities. A direct Git comparison confirms that `app/physics`, `app/sim`, `app/data`, `research/native-kernel/src` and `research/rc-monster-truck/native/src` are unchanged from the audited commit. The baseline receipts remain pinned to the actual `8d4169f8` runs; this publication update does not imply a new qualified native or full CI run. The implementation plan complements the existing [native kernel and optimization roadmap](../../plans/native-kernel-roadmap.md), whose historical target timings retain their own evidence and owners.

The 272-file, 106,404-line [source inventory](../../../research/native-physics-audit-2026-11-28/evidence/source-inventory.json) covers materialized physics, simulation and aircraft-native source. It records SHA-256 identities. Ground native source, data, tests, session consumers and calibration pipelines were inspected where the domain reports cite them. Inventory coverage is not an assertion that every source line or possible vehicle state was exhaustively reviewed.

The previous swarm investigation at `c4eca1ab`, based on `71306784`, was treated as leads. The current `app/physics` and `app/sim` trees are unchanged since that baseline, but the current native configuration/weather guard builders differ. In particular the old unbounded fast-plan expansion claim is superseded by the per-root budget and watch fallback. Findings and measured results in this investigation are tied to the new source identity.

## Checked software baseline

The lead ran official Godot `4.8.beta2.official.cafc17a19` through the repository's checked runner, one engine process at a time. All **27 selected suites passed, reporting 6,527 assertions**. The runner recorded identical simulation/physics/data/native source fingerprints before and after. The compact [baseline receipt](../../../research/native-physics-audit-2026-11-28/evidence/baseline.json) retains each case, completion result, count and log hash. The [runner and reproduction instructions](../../../research/native-physics-audit-2026-11-28/README.md) reconstruct the raw logs in a new output directory.

| Area | Selected existing suites | Reported assertions |
| --- | --- | ---: |
| Core mathematics and integration | math3d, rigid body, integrator, law properties, event refinement, simulation | 384 |
| Atmosphere and air data | atmosphere, atmospheric-column session, air data | 350 |
| Fixed-wing loads and contact | aero, ground effect, ground friction, mass inventory, rotor coupling | 182 |
| Helicopter | main rotor, inflow, drive, aerodynamic stage | 4,085 |
| Electric and multirotor | electric bus, sample rate, electric motor, battery ECM | 1,184 |
| Turbine and glow | continuous turbine, glow flight physics | 156 |
| Airship and ground vehicle | airship dynamics, suspension, vehicle dynamics | 186 |
| **Total** | **27 suites** | **6,527** |

One ground-vehicle native comparison explicitly skipped because the required backend was absent. It is not a native pass. The suite totals include many numerical-law assertions; they are not 6,527 independently measured physical conditions. Passing current tests demonstrates retained baseline behavior and makes the new counterexamples more useful: the existing assertions do not cover those mechanisms.

The first new resource import exhausted disposable cache capacity. It is recorded as a setup failure, not a physics result. A subsequent independent-cache import completed through the checked runner without engine errors before the selected suites ran.

## Evidence boundaries

| Evidence | Established here | Not established here |
| --- | --- | --- |
| Production source inspection | Call paths, input ownership, algebra, explicit omissions, static duplicated work | Frequency in normal play; actual optimizer behavior |
| Actual C++ header witnesses | The reported component outputs and operation/allocation counts on this host | Admitted native package, full-session coverage, target latency |
| Independent equation/data reducers | Discriminating analytical results, calibration residuals and proposed control fixtures | Production execution unless a separate production witness is cited |
| Checked engine suites and contact witness | Reference-runtime regressions; actual stock FPV contact-function counterexample | Native implementation, physical flight accuracy or pilot experience |
| Manufacturer and experimental sources | Measurements in each identified hardware/environment domain | Uncertainty-free fleet constants or transfer to a different propeller/airframe |

This Linux x86-64 container exposes nine logical CPUs and no `/dev/dri`. It has no configured test pool or admitted native aircraft/ground sidecar. Available GCC is 14.2.0; the qualified Linux package pins 13.3.0. Standalone probes use strict floating-point options, but do not substitute for the qualified package. We did not relax compiler, architecture, model admission or backend checks.

Incidental reference timings in the selected ground-vehicle suite are preserved in its receipt. They are averages from a shared container, not per-tick p95/p99 or evidence of native performance. No FPS improvement or production CPU reduction is claimed by this audit.

## Physical and numerical conventions

The common checks use SI units, NED world coordinates and forward/right/down body coordinates, with scalar-first body-to-NED quaternions. Angles in force/rotation laws are radians. RPM conversions are explicit at the shaft boundary. Forces are N, moments N·m, energies J, powers W, inertia kg·m², temperature K inside the laws. A six-entry inertia tensor contains actual off-diagonal matrix entries; traditional products of inertia use the opposite sign. Each source dataset needs its own documented frame conversion.

Use the full modeled inventory in conservation tests: translating and rotating body, rotor relative and absolute motion, fuel and gas mass, springs, battery/polarization storage, dissipative heat and external work. Wind or a commanded powered actuator can add energy; an isolated passive frame impact cannot. Quaternion normalization and exact replay are useful checks but do not by themselves establish physical conservation or convergence.

The production outer tick is 1/240 s. Compare smooth integration convergence separately from event timing, piecewise laws and controller sample/hold behavior. When refining an internal plant integration, retain the same controller sample clock; otherwise the experiment changes the closed-loop system as well as the numerical solver. Preserve atomic commit/refusal/restore behavior, accepted-tick ordering and recording identities.

## Coverage obligations and remaining qualification

The ten roles cover fixed-wing aerodynamics; main/tail rotors and drive; multirotor propulsion and contacts; gas/glow/turbine propulsion; electric/battery/EDF; rigid bodies, collision, ground and buoyancy; numerical methods; control/actuator response; native architecture/performance; and independent verification. Atmosphere, mass/inertia and units cross these ownership boundaries. Their reports identify exact inspections and tests rather than assigning every system a blanket pass.

For implementation, every changed law needs a manufactured invariant or discriminating regression, compatible reference/native evidence, converged event/state checks and the owning release/platform gate. Realism claims additionally need matched geometry, mass/CG/inertia, atmospheric conditions, controls and held-out measured data. Target performance requires the actual admitted backend, warmed paired tapes, instrument-off controls and reported per-tick tail latency. The absence of those measurements is retained as an open acceptance gate, not converted into a hypothesis about their outcome.
