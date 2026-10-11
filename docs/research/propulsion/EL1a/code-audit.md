# Electric integration seams

2026-10-10 · **Status: read-only runtime audit; future integration work, not implemented behavior.**

The [plan](../../../ELECTRIC-PROPULSION-PLAN.md) defines the rollout. EL1a adds only a stateless electric source; the following paths still assume glow or turbine. This audit was checked against the current G2a/G2b/H8 implementation, superseding the older propulsion research's pre-coupling snapshot.

| Location | Existing behavior | Electric consequence |
| --- | --- | --- |
| `app/physics/aircraft_data.gd`, `_propulsion` | Missing kind defaults to glow; explicit supported kinds are glow/turbine. Glow requires idle/max RPM and lag; optional shaft requires combustion fields. | Add `electric_prop` to loader and JSON schema together; never derive a fake combustion block. |
| `app/physics/propulsion.gd`, `has_shaft`, `engine_torque`, `shaft_rate`, `steady_rpm` | Non-turbine without `shaft` uses a throttle/RPM lag; torque/root bracket/off-state friction dereference the glow shaft block. | Introduce explicit source dispatch/capability and electric equilibrium bounds. Supplying only `kind` is insufficient. |
| `app/physics/trim.gd`, `_rpm` | Uses propulsion equilibrium and supplies engine charge ratio. | Use identical electric source and propeller law for trim/flight; do not apply combustion dry-air scaling to electrical torque. |
| `app/physics/dynamics.gd`, `loads`, `rotor_momentum` | Prop loads and rotor momentum are already separate; non-turbine is a propeller. | Reuse propeller aero and its stage-local density/air velocity, but validate electric inertia/axis. |
| `app/sim/flight_session.gd`, `_supports_coupled_shaft`, `_coupled_response` | Coupled support requires `has_shaft`; stage response calls the glow-oriented `shaft_rate`. The response uses shared `rotor_coupling.gd`. | Accept the electric capability, evaluate electric net source torque at each stage and retain the existing internal momentum exchange once. |
| `flight_session.gd`, `_pre_step` | Selects turbine spool, glow shaft or lag. | Electric must not fall through any branch or pre-advance RPM while coupled RK also advances it. |
| `app/sim/simulation.gd` continuous callbacks | Stages, accepted aux projection and transactional rollback already exist. | Reuse this ownership for shaft and future SOC/polarization states; every new state belongs in reset/checkpoint/rollback. |
| `flight_session.gd`, `trace_meta`, checkpoint/restore | Propulsion labels distinguish turbine, lag and coupled/uncoupled shaft; v4 wrapper carries coupled mode/configuration identity. | Explicit electric model identity and source settings must survive fresh-owner restore; audit version semantics before adding battery state. |
| `app/sim/trace.gd`, coupled metadata reader | Recognizes the current coupled model identity. | New identity requires coordinated reader changes. |
| `app/tests/check_trimmed_flight.py`, `test_trace_acceptance.py` | Propulsion-model allowlist, semantics checks and exact feature-key checks. | Add electric accepted cases and wrong-kind/version negative controls; update the trace contract evidence. |
| `app/main.gd`, engine sound creation/status | Supplies `propulsion.max_rpm` to combustion sound; generic engine RPM label. | The electric data shape cannot silently omit a consumed field; define a justified presentation reference and TT-12 audio behavior. |
| `app/input/rc_input.gd`; session disconnect path | Radio low-throttle arming exists; disconnect zeros throttle and pauses, leaving `engine_running` set. | Shared input arming is useful but does not implement EL3 signal-loss timing or ESC arming/recovery. Test these contracts separately. |

## Boundaries to retain

- The composite EL1a motor/ideal-ESC source deliberately refuses negative electrical current. A signed motor-only law may become a separate seam when a supported brake/regenerative ESC needs it. The current approximation must remain explicit; do not infer it describes all BLDC controller topologies.
- Body plus rotor use locked inertia; an added stator reaction on top of the existing relative-spin reaction would double-count torque. Motor/prop losses must each have one owner.
- The old research names `source.kind` and G-E steps are proposals, not current schema/step identities. Use `propulsion.kind` and EL in new work.
- Coupled P-51 measurements in [G2a-R1](../G2a-R1/README.md) were above the 500 µs/tick target. They do not predict an electric fixture's cost; measure the real integrated path before promotion.
- Timber's static/current tests need its own stock three-blade map. The generic 800 Kv fixture verifies equations and reuse only.

No tests were needed for the audit itself. The adjacent [EL1a report](README.md) owns the source-kernel verification and source hashes.
