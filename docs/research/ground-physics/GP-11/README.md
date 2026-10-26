# GP-11: compliant support and coupled ground implementation

2026-10-25/26 development record. Owner: GP, with SF and AS contracts retained. This record covers the common integration cohort after GP-10a/b. **These are executable foundations, not a completed stock-fleet rollout or measured RC calibration.** The [masterplan](../../../advanced-ground-flight-physics-masterplan.md) retains the open gates.

## Effective suspension law

[NormalCompliance](../../../../app/physics/normal_compliance.gd) implements `openrc-normal-compliance v1`. Its coordinate `x` is positive support compression; `v=dx/dt` is positive while closing. An exact wheel/surface gap Jacobian must supply both the force direction and compression rate. The scalar model represents effective leg plus tire compliance; it does not separately resolve tire strain, moving unsprung mass or strut shortening.

```text
e = max(0, x - stroke); y = e / stop_scale
F_elastic = k*x + k_stop*stop_scale*y^p
U = 1/2*k*x^2 + k_stop*stop_scale^2*y^(p+1)/(p+1)
c = c_compression_or_rebound*ramp(x/onset) + c_stop*ramp(e/stop_scale)
N = max(0, F_elastic + c*v)
P_dissipation = (N - F_elastic)*v
ramp(z) = 0 for z<=0; z*(2-z) for 0<z<1; 1 for z>=1
```

For `x<=0`, force, potential and dissipation are zero. The supported progressive exponents are 1, 2 and 3. Spring rates stay in N/m because the stop scale carries the nonlinear length factors. Damping is in N s/m; lengths are metres and energy joules. Every input is a strict `{value,unit,kind,source}` quantity. Numeric input limits are supported computation ranges, not aircraft hardware limits.

The unilateral rebound clamp matters to the energy ledger. If the unclipped damper would pull the wheel into the ground, actual contact force is zero. Counting `c*v^2` then overstates dissipated energy; the implemented work expression remains consistent with the applied force. One test distinguishes actual 2 W loss from an incorrect 32 W estimate. No restitution velocity kick, bounce multiplier or touchdown speed threshold is used.

`prepare` validates and pins the resource. `evaluate` returns the load, exact potential, dissipation, elastic tangent, force derivatives, stop contribution and clipping state. `bounds` supplies conservative position/rate derivative bounds. `scalar_substeps` admits a declared scalar mode only when frequency-step and damping-step accuracy ratios fit the bounded budget; it refuses rather than softens an overly stiff model. A zero-onset nonzero damper needs event-aware integration and is refused by that scalar admission helper. Multibody mobility and geometric stiffness remain the assembled solver's responsibility.

[The 88-check compliance test](../../../../app/tests/test_normal_compliance.gd) covers independent potential derivatives, work/passivity, onset/stop continuity, asymmetric damping, clipped rebound, malformed provenance, derivative bounds and admission limits. Actual `Simulation`/`VehicleModel` drop fixtures use 2 kg and 4 kg bodies at 120/240/480 Hz, elastic rebound, progressive stops, integrated damper heat, touchdown phase offsets, gravity/static sag and exact checkpoint continuation. A heavier body on the same spring produces the expected greater compression. Those synthetic masses and stiffnesses are verification fixtures, not calibrated fleet settings.

## Geometry and rotation dependencies

[GP-10](../GP-10/README.md#gp-10c-round-wheel-geometry) owns the zero-width ring envelope and local terrain support certificate. [GP-09](../GP-09/README.md#gp-09b-c-prescribed-carriers-and-a-common-rotor-system) owns the simultaneous body/wheel/shaft equations. The common system uses relative angular speeds in rad/s; rim-speed and RPM conversion belong only at existing aircraft interfaces.

The new fixed-datum composition in [FixedDatumBody](../../../../app/physics/fixed_datum_body.gd) receives the **final** coupled angular acceleration before applying `alpha x c + omega x (omega x c)`. It does not correct translation with the old single-shaft acceleration and patch rotation afterward. External moments transfer from the authored datum to live CG once, outside that helper. Fuel efflux remains co-moving; no unowned `I_dot` torque is introduced.

RK intermediate quaternions are not necessarily unit length. New geometry and position/gravity transforms use one normalized local attitude, while the quaternion ODE remains `q_dot = 0.5*q_raw*omega`. The combined integrator state is not modified during evaluation; endpoint normalization stays in the kernel. A strict unit-length test inside a stage evaluator was rejected because ordinary rotating RK stages exceed it. This smooth off-manifold extension must be shared by contact geometry and body kinematics.

## Authored ground module

[AircraftGroundProfile](../../../../app/physics/aircraft_ground_profile.gd) and the generated v2 schema admit an optional closed `ground` module. Absence or explicit `legacy_wheels_v1` retains existing behavior. `coupled_thin_ring_compliance_v1` authors capabilities, a pinned existing wheel-profile reference, separately identified compliance resources, and stable contact-ID bindings to hub/axle geometry. Hubs are authored in the LE frame and converted once about the inventory CG. Wheel radius, axial inertia, brake capacity and spin relaxation retain their existing wheel-profile owner.

An optional `openrc-aircraft-rotor-partition v1` record declares an **estimated aggregate** locked-tensor reservation. It names the reference pose, source and fixed-hub assumption, and supplies provenance-bearing transverse inertia for every installed rotor. Shaft and wheel axial inertias and axes are not duplicated. The common order is closed propeller shaft first, then hardware contact order; authoring record order cannot change state binding. The existing locked tensor, mass and CG are preserved. Both the remainder and rotor tensors must be physically realizable; merely obtaining an invertible matrix is insufficient.

This is necessary because the coarse stock inventory cannot support a defensible per-component split. For example, the Stik's estimated wheel-hub orbital inertia can exceed the relevant inertia in its coarse main-gear inventory box. The module therefore never claims that a named gear component was physically partitioned. Translating hubs, moving fork/gear mass and open-system turbine momentum require their own qualified adapters.

Authoring validity currently remains distinct from launch admission. Coupled modules return normalized data but cannot silently fly using the legacy contact law. The Workshop classifier replaces the old point-contact law assertion and disables unqualified similarity transformations. Full Workshop editing, compiler source-aware versions and launch admission remain subsequent implementation gates.

Optional `steering_profiles` author provenance-bearing `openrc-prescribed-angle-actuator v1` resources. A steered support must supply both `steering_profile_id` and a unit `steering_axis_le`; its hinge passes through the fixed authored hub. Resource and actuator IDs must match. Unused/dangling resources, missing paired fields and a response outside its declared limits reject. Absence means a fixed axle; old steering throws do not silently synthesize new response parameters. The authoring suite passes 123 checks and the generated offline schema passes 13 additional structural cases; cross-field response bounds remain runtime checks.

## Prescribed steering and assembled stage

[ControlActuators](../../../../app/physics/control_actuators.gd) adds the explicit law `bounded-critical-prescribed-angle-v1`. The existing sampled servo functions retain their arithmetic. New linkage state is angle `theta` and angular rate `v`; actual upstream rudder servo output selects the signed target `u`:

```text
theta_dot = v
v_dot = (u - theta - 2*tau*v)/tau^2
z = theta + tau*v
theta_dot = (z-theta)/tau; z_dot = (u-z)/tau
```

For `theta,z,u` within travel `[-A,A]`, the state rectangle is invariant. Hence `|v|<=2A/tau` and `|v_dot|<=4A/tau^2`; authored maximum rate/acceleration must cover these bounds. RK4 stage and endpoint invariance requires `h/tau<=1`. A target change preserves angle and rate; acceleration can jump finitely. No per-tick angle reset, rate reset or velocity impulse is introduced. Full carrier velocity and acceleration remain `hinge_axis*v` and `hinge_axis*v_dot`, including a hinge parallel to the wheel axle. This ideal prescribed mechanism has no separately modeled servo inertia, power limit or backlash; the common rotor solve reports its signed actuator work.

The steering suite passes 273 checks, including analytic response, invariant limits, reversals, independent work derivatives and actual-kernel 120/240/480 Hz runs. Energy/work errors are respectively `1.85e-8`, `1.15e-9`, `7.15e-11 J`; these are synthetic conservation checks, not hardware response measurements.

[AircraftGroundStage](../../../../app/physics/aircraft_ground_stage.gd) binds the normal supports, explicit aggregate rotor partition and optional linkage state once. `motion` maps continuous angle/rate pairs to the existing five-field motion rows in hardware contact order. Shared response resources retain independent installed-contact states. `motion_state_valid` and `motion_substeps` provide the linkage part of model validation/admission; contact and source bounds still belong to the single step owner.

`evaluate` sums external and normal datum wrenches once, shifts the total moment to live CG once, solves all wheel/shaft angular accelerations together and passes final alpha to the fixed-datum derivative. The complete external shaft couple must already be in the external aircraft wrench and is also supplied to the shaft local row; internal drive torque goes only into that local row. Passing an old net shaft torque would count propeller drag twice. Its 145 checks include installed P-51/fuel properties, independent tensor/work assembly, raw RK quaternions, authored steering and actual-kernel drops. It does not install a second integrator, choose contact timesteps or authorize stock launch.

## Damage and transaction dependencies

[GearDamage](../../../../app/physics/gear_damage.gd) supplies an explicit experimental attached-component normal-capacity law. [VehicleModel](../../../../app/sim/vehicle_model.gd) supplies a fixed-layout accepted-endpoint transaction and clock-aware state validation. Failure state, released support potential and events must commit together; a later rejected projection must publish none of them. Unknown strength remains an inspection requirement, not an invented fracture threshold. The physical failed support law and its geometry still belong to the aircraft adapter.

## Normal stage and traction composition

[AircraftGroundDynamics](../../../../app/physics/aircraft_ground_dynamics.gd) binds authored support geometry to selected wheel hardware once, then evaluates all normal loads about the fixed datum. Its 146-check suite covers force/potential virtual work, full rotor couples, local RK attitude, footpoint materials, certified airborne culling and actual three-wheel/shaft kernel drops. The airborne cull proves positive separation from the bounded terrain; it reports a clearance bound without inventing a closest point or contact normal. Kinematic rows are keyed by contact ID and returned in hardware order. Moving hubs are explicitly unsupported.

[GroundTraction](../../../../app/physics/ground_traction.gd) solves the compact convex problem `min(0.5*p^T*A*p + v_free^T*p)` for `A=J*M^-1*J^T`. Each 2D group is a traction ellipse after `p=D*y`; 1D groups are bounded angular or linear impulses. Limits are distinct physical capacities, not speed multipliers. Exact block minimization uses the full mobility metric, with global stationarity/feasibility/duality checks before publication. PSD singular contact mobility is allowed; an indefinite matrix, exceeded iteration budget or unrepresentable scale rejects without a partial impulse. No diagonal regularization is added. The bounded row count is 128; tests include a 65-row case needed by 16 braked/rolling wheels plus a shaft row.

[AircraftGroundImpulse](../../../../app/physics/aircraft_ground_impulse.gd) composes that QP with one CM translation mass and the common angular rotor mass matrix. It verifies the stage and rebuilds its factor. Point-tangent rows use the actual CM contact arm, full wheel rim arm and relative spin; internal brakes use only a relative-spin row, while external rolling moments include both body axle and spin rows. Its work receipt separates dissipation from prescribed ground/carrier work. Thus it does not mislabel actuator-driven kinetic-energy gain as a negative friction loss. Zero rows preserve velocity bytes; static-hold stages are refused until the joint constraint policy is qualified. The QP and adapter suites pass 370 and 94 checks respectively.

These modules do not themselves choose a timestep, advance a second aircraft state or switch stock laws. The aircraft policy must compose normal integration, tangential impulses, source events and accepted damage evidence, including speed-domain constraints. Its convergence order and performance must be measured for that composed policy; a fourth-order RK normal integrator does not make an impulse split fourth order.

## Verification boundaries

The integration baseline consists of four preserved Stik/P-51 air/ground tapes captured after GP-10. Exact baseline replays were complete with unchanged solver fingerprints. Candidate comparisons hold aircraft bytes and command tapes fixed; changed solver fingerprints are reported as candidate experiments. No golden flight is rewritten.

The [retained initial integration cohort](evidence/README.md) pins 36 changed source snapshots, the original baseline tapes and all selected checked-runner receipts. It passed **3,469 checks across 21 suites**, plus four native comparisons: all numerical fields are byte-identical across **1,484 samples** on the legacy paths, with changed candidate solver identity reported explicitly. A fresh Git clone with `autocrlf=true` preserved every retained artifact's bytes. This is a frozen cohort: later normal-admission, complete-step and wheel/material-row changes need their own receipts and are not covered by that replay claim.

The [broader frozen-cohort regression](broad-suite/README.md) is **FAILED overall**: all 1,374 scripts parsed, and all 751 unit scripts ran with 734 passed and 17 failed. Failure attributions and original stopped attempts are retained. The original offline/integration gates completed as a disclosed composite after isolated checkout/import metadata repairs; this is not an uninterrupted full-suite pass. Later GP-12 and current-main changes are excluded from that runtime cohort.

Each new module is parsed before promotion and checked with the pinned Godot 4.8-beta1 console runner, including engine diagnostics that can accompany process exit zero. Tests exercise the real float64 kernel, independent energy/momentum calculations and explicit negative cases. Full fleet landing/taxi comparisons, measured suspension and strength data, rendered wheel/gear behavior, audio listening and 1080p target-host performance remain open. Command wall times are not physics budgets.

## Engineering references

NASA's [lumped landing-gear impact methodology](https://ntrs.nasa.gov/citations/20000112939) and [nonlinear gear parameter-identification study](https://ntrs.nasa.gov/citations/19960049759) support using component force/energy laws and separate static/dynamic measurements. Their full-scale helicopter/A-6 parameters are not RC values and were not copied into these resources. The [masterplan source ledger](../GP-08/sources.md) owns the broader research and applicability limits.
