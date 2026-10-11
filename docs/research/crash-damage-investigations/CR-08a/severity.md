# CR-08a — Deterministic crash-severity estimate

**Status:** implemented prototype; uncalibrated. **Serves:** [CRASH-DAMAGE-PLAN](../../../CRASH-DAMAGE-PLAN.md), CR-08a. This is a bounded presentation estimate, not a structural resolver.

## Inputs and outputs

CrashSeverity.estimate() takes a supplied mass, normal and tangential point speeds, incidence angle, surface ID and component ID. The angle is measured from the surface plane: 0° is grazing and 90° is normal. The angle must agree with atan2(v_normal, v_tangent) within 1°; the decomposed speeds already determine the energy, so angle is not counted a second time.

energy_j is 0.5 × mass × (v_normal² + v_tangent²) for the supplied mass. estimated_energy_j is a provisional surface-weighted estimate:

surface_factor × 0.5 × mass × (v_normal² + tangential_factor × v_tangent²)

severity is estimated_energy_j / 2000 J, clamped to 0…1. component_damage is that normalized score times a dimensionless component exposure factor, clamped to 0…1. It is not a physical fraction of a broken part. The estimate also returns the C0…C4 class, surface and component IDs, grouped component, speed, angle, validity, and data-provenance flags.

estimate_from_speed_angle() decomposes scalar speed with v_normal = speed × sin(angle) and v_tangent = speed × cos(angle). estimate_snapshot() reads the recorded hull-point velocity and flat-ground normal from the CR-01 snapshot. If gear point velocity is unavailable, a caller may supply CG velocity as a marked proxy. Unlabelled hull contacts use fuselage_estimate. The helper does not change simulation state or run during healthy flight.

## Provisional class bins

The bins below are heuristic separations, in estimated joules after the surface factor. Their evidence kind is **illustrative scenario separation**, not material testing. They were chosen to place the report 05 examples in plausible review bands: a sub-0.5 J tip touch, a 9–23 J hard landing, a roughly 325 J Stik nose-in, and an approximately 9.4 kJ Avanti nose-in. See [report 05](../05-architecture-impact-model.md#outcome-classes) and the [CR-00 effective-mass results](../../../../research/crash-damage/cr-00/results.txt). Those examples do not validate a threshold.

| Class | Estimated-energy interval | Proposed label |
| --- | ---: | --- |
| C0 | ≤ 1 J | contact |
| C1 | > 1 to 8 J | scrape |
| C2 | > 8 to 100 J | damaged |
| C3 | > 100 to 2,000 J | structural crash |
| C4 | > 2,000 J | destroyed |

The surface and component coefficients are also uncalibrated:

| Surface | Energy factor | Tangential factor |
| --- | ---: | ---: |
| grass | 0.78 | 0.15 |
| mown | 0.82 | 0.18 |
| rough | 0.88 | 0.24 |
| runway | 0.95 | 0.28 |
| asphalt | 0.96 | 0.30 |
| concrete | 1.00 | 0.35 |
| water | 0.60 | 0.05 |
| unknown | 0.90 | 0.20 |

| Component group | Exposure factor |
| --- | ---: |
| wingtip | 1.20 |
| wing | 1.00 |
| tail | 1.15 |
| gear | 1.25 |
| propeller | 1.35 |
| engine | 1.30 |
| canopy | 1.25 |
| fuselage | 0.85 |
| unknown | 1.00 |

The mown_grass and dirt aliases use the mown and rough profiles for both surface and tangential factors. Other surface IDs use the unknown profile. Coefficients affect only this estimate; they are not accepted surface compliance or component strength data.

## Progressive accumulation

accumulate_damage(state, event) returns a new state. Per-component exposure composes as 1 − (1 − previous) × (1 − event), so it cannot decrease or exceed 1. The summary class is monotonic; estimated event energies sum into a cumulative exposure index capped at 1e12 J. That sum is not the remaining energy of a physical crash.

## Limits and proof

The supplied mass is not converted to effective mass from inertia or contact location. Passing total aircraft mass can overstate a local tip or tail hit. The snapshot has no mass or surface field; gear-limit snapshots have no point kinematics, and hull crossing-time velocity remains unavailable. A detected-tick point speed or CG proxy must not be presented as crossing-time kinematics.

Thresholds, component exposure factors, and surface response have no RC material calibration or public-video validation in this step. They do not establish breakage, failure limits, durability, fire, or physical damage. CR-07 report 03 remains required before structural thresholds or a physical resolver are accepted.

The final script and test were parsed and run in a disposable Godot 4.7.2 project with the same resource paths. **44 focused checks passed**, covering class bins, mass/speed/angle/surface monotonicity, component mapping and bounds, finite-input guards, snapshot proxies, and cumulative damage. These checks validate software behavior only.

