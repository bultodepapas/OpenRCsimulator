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

The full three-wheel experiment also exposed slow convergence with redundant, nearly dependent contact rows: the original cyclic method missed its KKT gate after 1,024 sweeps. The [retained acceleration cohort](evidence/traction-acceleration/README.md) fixes that exact captured problem in 8 sweeps without changing its physical optimization or tolerances. Every eighth sweep can propose a rank-revealing interior-face correction, limited to the first feasible cap, and bounded feasible extrapolation. Original-objective and full KKT/work checks remain decisive. The 607-check QP suite includes lossless reproduction, unit changes, reversed sweep order and independent constrained optima. Independent review adds 34 checks.

## One accepted contact step

[AircraftGroundStep](../../../../app/physics/aircraft_ground_step.gd) supplies a bounded `VehicleModel.step_policy` composition. It calls the existing RK4 implementation for free/normal dynamics, then applies one simultaneous contact impulse at each substep endpoint. The complete split is **first order**, even though its smooth subflow uses RK4. It owns 1/2/4/8/16-piece attempts; the model must leave the kernel's other substep selectors unset.

The optional `fixed-hub-half-impulse-rk4-normal-half-impulse-v1` operator now applies half-capacity impulses before and after each free interval. It recomputes the post-kick force sample and k1, then certifies the interval using those changed velocities. Both impulse losses/prescribed work enter the same energy ledger. Its frozen contact optimization is not a self-adjoint exact flow, so the declared contact order remains **one**, despite its two-sided arrangement. Default Lie results stay byte-identical in six compared airborne/loaded/rolling/braking/capture cases. The expanded Step suite passes 167 checks, alongside Accuracy 84 and Electric 196; actual three-wheel drop and rest qualification is still in progress.

`maximum_assembly_resolution_j` is an optional **per-impulse** numerical ceiling, defaulting to strict behavior. A two-sided tick can invoke up to 32 contact solves, so its owner must allocate a whole-tick budget accordingly and check the receipt's accumulated derived uncertainty. It is not a force coefficient, physical dissipation allowance or permission to omit genuine motion. The accepted receipt records the selected operator law and resolution-use totals; abandoned attempts remain unpublished.

The evaluator returns the common rotor stage, fixed mass/CG, explicit state-index/unit mappings, contact rows/capacities, stable contact IDs, normal loads, all recoverable potential energy, normal dissipation and nonconservative power. It rejects source events, moving hubs, changing inertia/axes, prescribed carrier motion and unsupported reverse domains in this initial slice. The step uses final post-impulse omega when reconstructing fixed-datum velocity from CM velocity. Reusing old omega is incorrect.

Work receipts separate integrated normal damping, tangent/brake/rolling dissipation, prescribed work and mechanical-energy residual. They contain only the accepted path. RK internal points supply a named quadrature approximation; they never enter damage maxima. Accepted start/end load samples and their sampled peak/time remain explicitly **samples, not an interval maximum**. An endpoint failure owner cannot combine such a peak with unrelated potential energy at another state.

An optional named accuracy callback compares complete coarse/fine split trajectories from the same initial state. Only a finer path passing the normalized error gate is accepted. It compares raw differences across contact transitions, without a fourth-order Richardson divisor. Failed or mutated callbacks, exhausted budgets and abandoned paths publish no receipt. Current paired mode conservatively requires both paths to satisfy the supplied interval admission; if 16 pieces is the first admissible path, no finer comparison exists and it rejects.

The retained pre-extension step suite passes 127 checks, including the earlier 75-check `Simulation`/`VehicleModel` touchdown, spin-up, rebound, liftoff, braking, work, replay and rollback cases. Optional finite shaft-capture mapping targets a declared nonnegative rotor and its canonical internal friction row. The target rotor stays fixed, while the row ordinal may change as wheels load and unload. Roundoff polishing keeps the original finite cap and resolves all coupled coordinates; genuine reverse motion still refuses. Empty/absent capture preserves default result bytes. Fixture tolerances are explicitly pinned; they are not calibrated aircraft targets.

An actual three-wheel contact experiment revealed a limitation beyond the scalar fixtures: at first touchdown the 8/16-piece Lie paths differ by approximately 55/85 mm/s in wheel rim speed for the two tested sink rates, exceeding that experiment's proposed 1 mm/s gate. A disposable symmetric half-kick experiment reduces this to 3.16/4.86 mm/s with both impulse losses accounted for, but still fails that absolute gate. Its smooth damped/coupled convergence remains empirically first order. No second-order claim or production step replacement follows from its symmetric appearance. Comparison against finer references and the masterplan's physical error scales remains required.

Subsequent disposable 16/128-piece comparisons measured symmetric-path rim errors of approximately 0.054%/0.102% in those same touchdown cases, while Lie remained about 4%. This motivates qualification against a declared absolute-plus-relative physical error contract, rather than silently claiming the stricter absolute fixture passed. Near-rest tests exposed two further numerical refusals: objective bookkeeping rejected already KKT-certified candidates, and tiny point-velocity cancellation made the old relative-only KKT target finer than the resolved input arithmetic. The corrections below address those numerical cases; the retained acceleration cohort above predates them and does not prove their resolution. Actual loaded-trajectory refinement remains required.

## Verified assembly resolution near rest

[ContactAssemblyResolution](../../../../app/physics/contact_assembly_resolution.gd) is an explicit opt-in numerical contract layered on the existing impulse owner. The ordinary strict QP runs first. A strict refusal can accept **zero impulse** only when verified original assembly operands establish objective suboptimality below computed assembly uncertainty and the caller's independent upper energy budget. This reports `converged_at_assembly_resolution`, with the failed strict residual still visible; it is not relabeled strict KKT success.

For supplied binary64 `J,z,b,M` and solved response columns, the helper reassembles original free slip/mobility exactly, bounds dot/solve errors and proves the true symmetric mass matrix positive definite through an inverse-Cholesky congruence bound. Inverse residual witnesses bound the true inverse. Outward positive bound arithmetic includes gradual-underflow allowances and rejects unsupported overflow. Matrix uncertainty must also meet the existing relative numerical contract. For original capacities `D`:

```text
Gamma = sum_i D_i * delta_v_i + 0.5 * sum_ij D_i * delta_A_ij * D_j
```

A compact feasible dual-gap bound for the true PSD Gram objective must fit `Gamma`; `Gamma` must fit the owner's ceiling. The budget cannot enlarge derived uncertainty. Trying zero first avoids circulating impulses in near-null directions. Original capacities, passive work, common-mass and slip checks remain in force. Nonzero publication under this special receipt refuses. Ordinary strict callers retain their path and result bytes.

The exact Sym16 fixture has `Gamma=5.98e-17 J` and a true objective-gap upper bound `1.62e-20 J`; it accepts zero impulse/loss. Genuine motion at 0.001, 0.1 and 1 m/s produces opposing reaction/loss instead. The separate objective-order correction checks an already satisfied original KKT/work certificate before refusing a tiny internal monotonicity uptick. Main checks: assembly 53, strict QP 659, impulse 314, existing Step 127 and electric 196 — **1,349 assertions**, plus the accuracy policy's 84 in the [retained 1,433-check cohort](evidence/rest-resolution/README.md). These are numerical assembly/operator regressions, not a claim that an aircraft now rests correctly for six seconds or that advanced stock contact is enabled.

## Reusable local accuracy policy

[AircraftGroundAccuracy](../../../../app/physics/aircraft_ground_accuracy.gd) prepares a versioned numerical quality resource separately from the model-owned physical layout. Explicit SI absolute/relative scales and provenance cover position, CM velocity at the fixed datum, shortest quaternion angle, body rate, every continuous state coordinate, sampled normal peaks and work partitions. RPM converts to rad/s; wheel rims and wash remain declared m/s. Missing, duplicate or unknown continuous coverage refuses. Numerical quality does not author a second CG or wheel radius.

`compare` returns the exact four-key Step error-gate interface; `diagnose` exposes channel deltas, units and bounds. Complete adjacent coarse/fine paths are compared without Richardson division. Receipt layout, times, peak samples and ledger algebra are checked; an owner-supplied physical binding remains necessary because historical Step receipts do not authenticate their model. Work accuracy uses declared mechanical-throughput scales and remains separate from energy-conservation acceptance. Eighty-four checks include agreement with the existing electric oracle, quaternion sign/CG cases, mutation/refusal and actual Step callback use. This is per-tick accuracy, not a global trajectory guarantee.

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

## Fixed-voltage aircraft stage

[AircraftGroundElectric](../../../../app/physics/aircraft_ground_electric.gd) now assembles the existing fixed-voltage aircraft force and continuous-state owners with the common contact stage. It retains the established `[transported wash..., shaft RPM, wheel rim speeds...]` ordering. One stage-local propeller evaluation feeds the existing aerodynamic/slipstream load path and the local shaft couple. Motor electromagnetic drive enters the internal shaft equation; finite bearing friction is appended to the simultaneous wheel impulse problem. The adapter does not add the old isolated shaft reaction or old ground forces again.

For fixed carriers and constant mass, its nonconservative mechanical power is:

```text
P = F_external · v_O + M_external,O · omega
    + (a_shaft · couple_propeller) * sigma_shaft
    + torque_electromagnetic * sigma_shaft
```

The first wrench already includes the complete propeller wrench once. The additional terms account for relative shaft motion. Conservative energy includes gravity at the fixed reference CM and the normal spring/stop potential; bearing, tire and brake losses belong to the subsequent impulse receipt. Electrical copper loss remains in the existing source ledger. The adapter accepts an explicitly marked negative algebraic RPM extension without authorizing negative accepted RPM.

The stage checks use the repository's synthetic fixed-voltage Stik aircraft with explicitly synthetic compliant contact geometry and aggregate rotor partition. They compare the reused propeller/aerodynamic/wash calls, check the common final-alpha body derivative, independently calculate `z^T M z_dot` for energy closure, and apply simultaneous wheel/bearing impulses. Fixed wheel axes, fixed gear and constant mass are enforced; other aircraft remain with their existing owner until their full integration is qualified.

The expanded electric suite passes **196 checks**, including actual `Simulation` startup/cutoff, finite bearing capture, checkpoint replay and atomic rejection. Its airborne experiment is explicitly zero-gravity, calm air, 20 m above a static plane, with bounded speed/body rate/shaft state. The source fixture has no transported-wash state, so this does not qualify transported-wash runtime dynamics. Duty samples from zero through full throttle pass a versioned complete-path numerical quality profile. This is controlled source integration evidence, not a loaded runway rollout, aircraft calibration, stock activation or performance claim.

That profile retains the original state-error scales and independent Step energy-closure guards. It compares external-work partitions against `1e-6 J + 0.005*max(abs(W_coarse),abs(W_fine))`; bearing loss uses the same mechanical-throughput scale, including both work and loss magnitudes. This bounds absolute partition error relative to energy processed. It does **not** promise 0.5% relative accuracy in tiny bearing heat or qualify a thermal model. The stricter absolute `1e-6 J` work oracle remains an explicit rejection test; its rejection is distinct from energy creation.

An additional 17-check slow diagnostic compares a complete two-tick full-throttle start followed by cutoff against 32 diagnostic pieces per tick. Production remains bounded to 16 pieces. Both paths capture exactly at tick 299 (1.24583 s). Cumulative external-work/bearing-loss differences are about 0.000336 J, within the declared 0.001601 J throughput bound; actual cumulative energy-balance residual is `7.89e-10 J`. Final differences are 10.0 micrometres position, 12.0 micrometres/s CM velocity, 0.1426 mrad attitude and 0.879 microrad/s body rate, with exactly zero shaft-speed difference. A per-tick state gate is not a global trajectory bound: applying its local angular scale over this whole horizon fails. These measured global differences remain explicit diagnostics, not a claimed global microradian guarantee.

## Remaining integration gates

Qualify loaded aircraft trajectories and the optional two-sided contact composition, integrate session state adapters, qualify actual field geometry and supported source events, and bind damage to accepted failure states. Preserve the existing session, event, Workshop and audio owners. The broad suite also identified direct transcendental calls in the new compliance/steering modules; these now route through existing `Math3D` wrappers. Original frozen evidence remains unchanged; subsequent combined-source receipts must include those corrections. No new fleet coefficient calibration, native audio listening or 1080p performance claim is established by these software checks.
