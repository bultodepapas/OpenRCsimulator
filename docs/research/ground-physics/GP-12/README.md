# GP-12: wheel contact integration

2026-10-25/26 development record. These modules extend the [GP-11 frozen integration cohort](../GP-11/evidence/README.md). They do not yet enable the advanced law on stock aircraft. The [masterplan](../../../advanced-ground-flight-physics-masterplan.md) owns fleet, source-event, damage and presentation gates.

## Wheel and material assembly

[AircraftGroundTraction](../../../../app/physics/aircraft_ground_traction.gd) binds installed wheel hardware to explicit `openrc-tire-surface-traction v1` records. A record names its material and supplies provenance-bearing longitudinal friction, lateral friction and rolling-resistance coefficients. These are effective installed-tire/material pairs, not universal material constants. The first law explicitly uses the same static and kinetic Coulomb ellipse; it does not implement tire deformation, relaxation, temperature or separate Stribeck friction. Numerical bounds on coefficients are supported computation ranges, not measurement claims.

Each loaded wheel resolves the actual normal-stage **surface footpoint** material. Unknown materials reject; runway usage names, terrain position and legacy rolling multipliers cannot select a guessed material. Roughness remains the geometry provider's responsibility. The adapter constructs:

| Row | Velocity coordinate | Impulse-rate limit |
| --- | --- | --- |
| Longitudinal/lateral tire pair | Actual rim material point relative to stationary ground | `mu_long*N`, `mu_lateral*N` in one ellipse, N |
| External rolling resistance | `a·omega + sigma + a·nu` | `Crr*N*R`, N m |
| Installed internal brake | Relative wheel `sigma` | `demand*hardware_brake_torque`, N m |

The integration owner multiplies these rates by accepted-piece seconds **once**. All groups enter the same mobility problem. Axle/rim geometry and live CG define moment arms; the contact arm already includes the rim arm and is not shifted twice. The longitudinal tangent is `unit(a cross n)`; lateral is `n cross longitudinal` (leftward for the standard flat-ground axle convention). Symmetric friction is unaffected by that sign, but telemetry must retain it.

Brake demand is per installed wheel. No brake hardware means no brake row. Brakes can act airborne and transfer angular momentum to the body; tire and ground-rolling terms disappear with normal load. A small load therefore reduces traction and rolling resistance continuously without switching a takeoff mode. Differential braking produces yaw through the contact forces.

The 86-check assembly suite uses the actual P-51 wheel-profile brake capacities with explicitly synthetic compliant geometry. It covers touchdown spin-up, wheel lock, combined traction, airborne braking, per-wheel material changes, differential yaw, bank/camber, actual rim velocity, live-CG arms and prescribed steering work. Independent review also places a wheel hub and solved footpoint on opposite sides of a material boundary, verifying that the footpoint wins.

## Captured-wheel verification correction

The assembly fixture exposed a false rejection in `AircraftGroundImpulse`: one brake held its wheel mathematically at zero, while individually large `A*p` contributions canceled to float64 roundoff. The original post-slip comparison scaled only by the near-zero result and reported a normalized residual of `0.0036786`, despite closed energy/mass balances and a converged QP. The corrected backward-error scale includes `abs(v_free)+sum(abs(A_ij*p_j))` as well as the independent `b+J*z_after` term magnitudes. This changes neither impulses nor solver tolerances. Ordinary passing cases preserve velocity/impulse bytes. The frozen GP-11 source remains the pre-correction record; its narrower test results are not rewritten.

## One accepted contact step

[AircraftGroundStep](../../../../app/physics/aircraft_ground_step.gd) supplies a bounded `VehicleModel.step_policy` composition. It calls the existing RK4 implementation for free/normal dynamics, then applies one simultaneous contact impulse at each substep endpoint. The complete split is **first order**, even though its smooth subflow uses RK4. It owns 1/2/4/8/16-piece attempts; the model must leave the kernel's other substep selectors unset.

The evaluator returns the common rotor stage, fixed mass/CG, explicit state-index/unit mappings, contact rows/capacities, stable contact IDs, normal loads, all recoverable potential energy, normal dissipation and nonconservative power. It rejects source events, moving hubs, changing inertia/axes, prescribed carrier motion and unsupported reverse domains in this initial slice. The step uses final post-impulse omega when reconstructing fixed-datum velocity from CM velocity. Reusing old omega is incorrect.

Work receipts separate integrated normal damping, tangent/brake/rolling dissipation, prescribed work and mechanical-energy residual. They contain only the accepted path. RK internal points supply a named quadrature approximation; they never enter damage maxima. Accepted start/end load samples and their sampled peak/time remain explicitly **samples, not an interval maximum**. An endpoint failure owner cannot combine such a peak with unrelated potential energy at another state.

An optional named accuracy callback compares complete coarse/fine split trajectories from the same initial state. Only a finer path passing the normalized error gate is accepted. It compares raw differences across contact transitions, without a fourth-order Richardson divisor. Failed or mutated callbacks, exhausted budgets and abandoned paths publish no receipt. Current paired mode conservatively requires both paths to satisfy the supplied interval admission; if 16 pieces is the first admissible path, no finer comparison exists and it rejects.

The 75-check step suite exercises actual `Simulation`/`VehicleModel` touchdown, wheel spin-up, rebound, liftoff, airborne braking, damped work, checkpoint continuation, rollback and paired-path rejection. Its analytic spring/sliding-wheel oracle demonstrates convergence of the complete split. Fixture tolerances are explicitly pinned; they are not calibrated aircraft targets.

## Conditional normal-rate bounds

[NormalContactAdmission](../../../../app/physics/normal_contact_admission.gd) uses all free rotor coordinates. Local normal mobility is `W=J*M^-1*J^T`. Gershgorin bounds on `sqrt(Kbar)*W*sqrt(Kbar)` and `sqrt(Cbar)*W*sqrt(Cbar)` retain multibody coupling and permit singular contact sets. The accuracy guards are `h*omega_bound<=0.1` and `h*damping_rate_bound<=0.25`; exceeding 16 pieces rejects without changing physical coefficients.

For fixed hubs on a plane, eliminating free axial spins gives `A=B+sum K*(Id-aa^T)>=B`, where `B` is the **live** body remainder. A positive lower bound `beta` from its scaled inverse and backward-error residual gives:

```text
d_i = 1/m + (|hub_i-cg|+R_i)^2/beta
omega_material^2 <= sum Kbar_i*d_i
lambda_damping <= sum Cbar_i*d_i
Hgap_i <= |hub_i-cg| + 2*R_i/kappa_min
omega_geometry^2 <= sum Nbar_i*Hgap_i/beta
```

These are conditional bounds over supplied compression, speed, load and protected axle-projection envelopes. They are not a complete nonlinear RHS error proof: damping/geometry transport, gyroscopic terms and envelope coverage remain the integration owner's responsibility. A swept gap guard similarly assumes a true whole-interval gap-speed bound. The 221-check admission suite covers independent dense inverse comparisons, changed axes/CG, curvature near the projection limit, bounds, malformed inputs and a synthetic P-51 partial-fuel example requiring 3/4/6 pieces at 240 Hz. Checked complete-path refinement remains required for the proposed practical aircraft policy.

## Existing-source bridge

[AircraftGroundSource](../../../../app/physics/aircraft_ground_source.gd) reuses the existing fixed-voltage electric motor and propeller laws. It separates electromagnetic drive from the finite bearing-friction capacity derived from the existing motor's no-load current. The latter belongs to one bounded internal shaft row in the joint impulse solve. It does not reuse the old isolated motor rest clamp as an unlimited constraint.

The supplied propeller wrench is already in the aircraft external loads once. Subtracting the propeller hub force moment yields its full local rotor couple, including transverse P-factor. This avoids counting propeller drag twice through an old net shaft torque. An explicitly requested negative algebraic RPM extension evaluates source maps at zero and is marked trial-only; accepted reverse RPM remains unsupported. Finite batteries, fuel consumption, glow lifecycle and open-system turbine momentum need their existing source owners integrated separately.

The source suite passes 162 checks; existing electric-motor checks (1,057) and 25,001 propulsion scalar comparisons pass. This bridge supplies terms; it does not itself activate a source policy or authorize launch.

## Remaining integration gates

Complete the finite static-shaft capture policy, assemble aircraft force/source/state adapters, qualify actual field geometry and supported source events, and bind damage to accepted failure states. Preserve the existing session, event, Workshop and audio owners. The broad suite also identified direct transcendental calls in the new compliance/steering modules; these now route through the existing `Math3D` wrappers. The original frozen evidence remains unchanged; subsequent combined-source receipts must include those corrections. No new fleet coefficient calibration, native audio listening or 1080p performance claim is established by these software checks.
