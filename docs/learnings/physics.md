# Physics, data, and performance lessons

**Status:** curated reference.

Lessons from ground handling (E1–E3b3), aircraft data and aero consistency (D1, D11, E0a), simulation state and performance (H1–H15), and propwash (E0b), recorded from 2026-10-06 to 2026-10-08. Reports hold the detailed evidence; owning plans hold current status. Measurements are historical unless explicitly identified as a current contract. See [LEARNINGS](../../LEARNINGS.md) for shared engineering lessons.

## Numerical correctness and state

### A stability limit is not a physical measurement

The explicit integrator limits the spring frequencies it can resolve, but that limit says nothing about the real landing gear's stiffness. A passive contact model can still have inaccurate touchdown forces or trajectories, so check ring-down and switched-contact accuracy with step refinement and independent touchdown cases. Do not reuse an old stiffness number as a physical datum; keep measured gear data separate from a solver's numerical bound. ([H11](../research/simulation-state/H11/README.md), [E1b](../research/ground-contact/E1b/README.md))

### Keep contact-law ramps smooth away from the operating point

Touchdown damping should rise continuously from zero compression and join the full law with a continuous slope (C¹) at an onset below static compression. A ramp that reaches full damping exactly at rest leaves a kink in every small ring-down and degrades smooth-regime convergence; keep the normal resting point beyond the ramp. ([E1b](../research/ground-contact/E1b/README.md))

### Diagnose convergence before widening a tolerance

A refinement ratio near two can come from a wheel bouncing across the ground-contact branch, not from a defect in the smooth tyre law. Inspect the motion and contact state, establish whether the test is in a smooth or switched regime, and compare against the expected integration order before changing a band. Quasi-static limits are useful oracles only when the test approaches the assumptions behind them. ([E2](../research/ground-friction-e2.md), [H11](../research/simulation-state/H11/README.md))

### Every coupled continuous state needs the same integration stages

Updating a continuous wake or other lag once per tick while integrating the body with RK4 creates a split, lower-order system. Put coupled continuous variables in the integrator workspace and evaluate them at each RK stage; use a nonautonomous analytic oracle because ordinary autonomous flight traces will not reveal a solver that freezes stage time. Sampled controls and discrete modes still need explicit update boundaries. ([H8a](../research/simulation-state/H8a/README.md), [E0b5](../research/propwash/E0b5/README.md))

### A checkpoint is the complete physics boundary

Body position and attitude alone do not define a resumable simulation. Include the previous rigid-body state, auxiliary lags, engine mode, sampled inputs, tick and timestep, configuration, mass properties, and stop condition; restore and roll them back together after a failed tick. JSON is useful diagnostic data but is not a bit-exact checkpoint, and recorded tolerance metadata must never loosen code-owned acceptance limits. ([H8](../research/simulation-state/H8/README.md), [H9](../research/simulation-state/H9/README.md), [C7-R2](../research/trace-integrity/C7-R2/README.md))

### Exact equivalence and physical correctness are separate claims

A frozen copy of the old implementation can show that a refactor preserves its behavior, including a bug. Keep an independent physical or analytic oracle for correctness, and a sensitive equivalence check for intentional behavior-preserving changes. If exact replay matters, preserve floating-point operation and accumulation order: even adding zero can change the sign of zero and therefore a bitwise fingerprint. ([H12](../research/simulation-state/H12/README.md), [E0b1](../research/propwash/E0b1/README.md))

## Ground and aerodynamic models

### Model the ground at the contact points and through the real session

Keep aircraft tyre coefficients with the aircraft and let each field's surface scale them, so aircraft data remains usable at different fields. Query the surface under each wheel: a contact near the center of gravity can hide a mistaken center-of-gravity lookup. Unit tests cannot prove the application passed the selected field into simulation; expose the active surface in trace evidence or another session-level check. ([E3a](../research/ground-surfaces-e3a.md))

### Judge wheel support along gravity on the full resting facet

For rigid gear at rest, find the lower facet of the contacts' convex hull, project the center of gravity along that facet's normal, and measure its margin to the whole coplanar facet boundary. A body-axis projection misjudges taildraggers at their nose-up resting attitude, while testing each triangle separately can give a centered square-layout center zero margin along its diagonals. ([D1-R3](../research/aircraft-validation/D1-R3/README.md))

### Stiction needs per-wheel memory and an energy-safe release rule

A velocity-regularized rolling law creeps under a small steady push because it has no memory of a parked tyre. Per-wheel anchors remove that creep, but release must depend on sustained elastic force rather than a transient damper spike; initialize a new anchor unloaded, and distribute spring stiffness by each wheel's static load share. Check breakaway against an independent force and moment balance, since thrust height and propeller torque redistribute normal loads. Current breakaway factors remain estimates pending field measurement. ([E3b1](../research/ground-contact/E3b1/README.md))

### Separate a detected contact from the physical impact event

A tick-end penetration identifies an observed contact, not the first point or time of impact. Preserve that timing in diagnostics and distinguish point speed from CG speed. A landing-gear contact position is an undeformed reference: `v + omega × r` omits compression motion, so it cannot establish the actual wheel-contact velocity. Mark that value unavailable until the model provides the missing rate. ([CR-01a](../research/crash-damage-investigations/CR-01a/README.md))

For a rotating rigid point, interpolating endpoint depths does not locate its crossing along the pose interpolation. Position lerp plus shortest-path quaternion nlerp yields a cubic ground-plane numerator; derivative-root intervals expose enter-and-exit contacts hidden between clear endpoints. Keep this reconstructed pose separate from the observed tick state, and leave tangencies or pre-existing contact explicitly unknown. ([CR-01b](../research/crash-damage-investigations/CR-01b/README.md))

### Solve runway starts as equilibria

Settling a start by simulation can leave a small slip and make the result depend on timestep or engine-start transient. Solve the engine-off rest pose, place the anchors there, then solve the idling pose with anchors fixed; balance vertical force in world coordinates, including the vertical component of tilted thrust. The result verifies the model's equilibrium, not the real airplane's measured resting attitude or breakaway. ([E3b2](../research/ground-contact/E3b2/README.md))

### Verify maneuver joins in one continuous flight

An isolated landing entry does not prove a circuit can reach it. Keep trims and simulation state continuous from the runway start, bound the actual state at each handoff, and independently check the saved route and every tick. A controller tuned to this model establishes a reproducible verification case, not physical fidelity. Count stop/hold durations in integer ticks: summing timestep floats can reject an exact five-second dwell. ([E3c2a](../research/ground-contact/E3c2a/README.md))

### Match the assumptions of an independent ground-roll oracle

A one-dimensional takeoff integral using the simulator's own thrust and aerodynamic forces checks 6-DOF ground coupling, not those forces' fidelity. A fixed-rest-attitude integral diverges as the aircraft pitches and unloads its wheels; driving the same integral with the recorded 6-DOF attitude isolates the coupling error. State which quantities are shared and reserve real takeoff measurements for validation. ([E3b3](../research/ground-contact/E3b3/README.md))

### Preserve shared event errors when reducing video intervals

Adjacent intervals share an endpoint: its frame/position pick errors cancel in the combined span, while a common clock or survey-scale error persists. Keep signed sensitivity contributions so covariance survives; summing interval variances as independent gives the wrong result. A same-frame position estimate can also correlate with the frame pick. VAL-8a verifies these effects analytically and with seeded sampling. Use original capture cadence, surveyed ground positions and a consistent aircraft reference point; the resulting mean ground velocity does not establish airspeed or instantaneous liftoff speed. ([VAL-8a](../research/validation/VAL-8a/README.md))

RPM response crossings similarly reuse steady endpoints and sometimes adjacent samples. Preserve those signed contributions through lag/delay calculations; command-time uncertainty cancels from the 63.2% consistency residual. A threshold knot can change segments under small noise, invalidating a fixed-segment derivative. Screen crossing identity before reporting local uncertainty and keep interpolation bounds separate from standard uncertainties. ([VAL-7c](../research/validation/VAL-7c/README.md))

### Check mass properties before tuning aerodynamic derivatives

Flight response can identify a combination such as roll damping divided by roll inertia, not each term independently. In the dated 2026-10-06 Stik comparison with UMN flight-identified models, steady roll rate was within 2% while the roll time constant was about 2.1× too short; the analysis attributed most of the gap to inventory-derived inertia, not an independently measured Stik inertia. Treat that as a historical diagnosis, and check each input's provenance before changing inertia or tuning damping to fit one pole. ([Aerodynamics at RC scale](../research/roadmap-investigations/02-aerodynamics-rc-scale.md), [D11d](../research/aero-consistency/D11d/README.md))

### Test derivatives across blends and against time-domain motion

A load blend can be continuous while its derivatives change sharply, so linearize and measure derivatives across the entire transition, including approach angles. At RC scale, downwash delay can be a meaningful fraction of the short-period timescale; represent that effect as a lag state shared by nonlinear flight and linearization, then compare the linear model with a forced response through the actual integrator. Do not apply the effective static tail slope to pitch-rate flow or elevator: downwash reduces the free-stream slope, while those terms need their own geometry-derived factors. Check fin damping against `Cnr_fin = -2(l_v/b)·Cnβ_fin` before assigning a whole-aircraft yaw gap to the fin; the cited check found the fin consistent and traced the remaining discrepancy to a borrowed yaw-damping coefficient. ([D11d](../research/aero-consistency/D11d/README.md), [E0a2a](../research/aero-consistency/E0a2a/README.md), [E0a2b](../research/aero-consistency/E0a2b/README.md), [D11f](../research/aero-consistency/D11f/README.md), [D11g](../research/aero-consistency/D11g/README.md))

### Keep rendering and physics coordinate datums explicit

Visual model coordinates may include a datum offset that the physics adapter removes. Copying a rendered shaft location directly into a force application point can invent a thrust moment; document the transform and test the physics location in its own coordinate frame. ([E0b2](../research/propwash/E0b2/README.md))

### Calibrate propellers against power as well as thrust

Static thrust alone can make a propeller model look plausible while requiring more engine power than the installed engine can deliver. Use measured RPM on a known propeller and an engine power anchor to constrain blade-element fits across propeller variants; keep catalogue ratings, observed installation performance, and derived model values distinct. The cited P-51 calibration is an aircraft-specific historical estimate, not a universal engine correction. ([P-51 flight realism](../research/p51-flight-realism.md), [P51-06 evidence](../../research/p51/p51-06/README.md))

### A propwash centroid or exact outline does not establish tail loads

Tail effectiveness depends on the distributed axial and swirl velocity over the actual tail, not just centerline induced speed or total covered area. Compare simplified models against independent distributed integration, preserve the zero-swirl baseline, and name assumptions such as a borrowed swirl factor or angular downwash offset. The E0b reports are research and performance evidence; they do not establish calibration on the Stik or justify production enablement. ([E0b3b](../research/propwash/E0b3b/README.md), [E0b4](../research/propwash/E0b4/README.md), [E0b6](../research/propwash/E0b6/README.md))

### Subtract washed and free loads with the same tail law

When adding propwash to a tail model, evaluate washed and free loads with the same tail law, pressure arm, rate contribution, and sampled wing lift; otherwise the increment subtracts a different baseline. Verify the held downwash state through the real session path, since a helper-only test can miss disconnected state wiring. E0b3a's shared angular downwash is explicitly a quasi-steady approximation, and its manufactured fixtures do not calibrate Stik propwash. ([E0b3a](../research/propwash/E0b3a/README.md))

## Data and performance

### Validate data before conversion and at the session boundary

Casting first can turn numeric strings into accepted numbers and bypass unit or provenance checks; non-finite values also need explicit rejection. Validate types, finite values, units, kind and source before conversion, then test whole-session behavior: invalid initial data must not fly, while a rejected reload must preserve the existing model, trim, auxiliary state and clock. ([D1-R2](../research/aircraft-validation/D1-R2/README.md))

A solver must prove that its residual is finite before testing convergence: both `NaN > tolerance` and `NaN < tolerance` are false. Finite inputs alone are insufficient because intermediate arithmetic can overflow. Refuse the candidate before reconstructing diagnostics through invalid arithmetic, and preserve the failure-result fields that callers consume. ([D4-R2](../research/trim-integrity/D4-R2/README.md))

### Match a companion schema against accepted inputs too

A schema can reject every malformed fixture and still reject valid runtime inputs. Compare both directions through the production file loader: optional absence, null, empty objects and string trimming have different contracts. Godot's ASCII source trimming and Python's Unicode whitespace rules differ, so a generic `\S` can change accepted data. Keep physically inconsistent but structurally valid cases to show which checks remain runtime-only. ([DATA-4a](../research/aircraft-validation/DATA-4a/README.md))

### Keep reference provenance and freshness executable

Modal comparisons need complete source rows, explicit scaling transforms, current engine outputs, and input/source hashes; reject stale or malformed reports before publication. Keep known real-airframe discrepancies separate from tests of the classifier, and treat inherited rounded modal values as provisional when their calculation or tuning history is unverified. ([VAL-3](../research/validation/VAL-3/README.md))

### Run metamorphic checks through actual flight ticks

Symmetry, Froude scaling, and passive-energy checks should exercise real session callbacks and RK ticks, including every relevant length and timescale such as servo slew, lag distance, and timestep. Preserve an unmodified control and use bounded mutations that fail the named property while flight integrity still passes; a runaway trajectory is weak evidence. These are software properties under stated assumptions, not universal similarity claims. ([VAL-4](../research/validation/VAL-4/README.md))

### Give malformed-input probes a valid positive control

Start each malformed-input series from a finite, nonzero call that succeeds, then change one field at a time and assert the expected output shape and backend call count. Without that control, an unrelated invalid field or fallback path can make every mutation appear safely rejected; preserve the distinct contracts for required fields, optional absence, and explicit null. ([E0b6p native evidence](../research/propwash/E0b6p/native/README.md), [decoder](../research/propwash/E0b6p/decoder/README.md))

### Verify every generated artifact in dependency order

A generator's local `--check` protects nothing if CI never runs it. For multi-stage aircraft data, check each link from source to geometry, runtime data, and generated report; otherwise a current runtime file can coexist with stale published derivation. This proves reproducibility and freshness, not that the underlying physical inputs are correct. ([DATA-1](../research/aircraft-validation/DATA-1/README.md))

### Profile complete, evolving ticks before choosing an optimization

Component timings help locate a hot path, but they do not predict an evolving flight's full-tick cost or the gain in every regime. Measure through decoding, adapters, and the language boundary, across aircraft and realistic trajectories; report the target machine, run conditions, spread and percentile definition. For attribution, use exclusive timer buckets, assert that timers and expected calls ran, keep the original batch length, alternate instrumented and control runs, and retain raw samples instead of subtracting noisy observer costs. Shared-host numbers in the H and Gate P reports are historical observations, not a current release guarantee, and a Linux-only native probe does not establish other platforms. ([H4/H5](../research/simulation-state/H4-H5/README.md), [H15](../research/simulation-state/H15/README.md), [Gate P](../research/simulation-state/Gate-P/README.md), [E0b6p attribution](../research/propwash/E0b6p/attribution/README.md))

### Remove calls and allocations before adding a native dependency

Measured GDScript hot paths often spend substantial time on helper calls, temporary arrays and dictionary lookups rather than arithmetic. Scalarize only behind a frozen, sensitive oracle that preserves operation order, and remeasure the complete trajectory: an exact local speedup may still miss the whole-tick budget. A native port also has binding and model-decoding costs, platform-build obligations, and must retain the GDScript oracle until its full path is accepted. ([H12](../research/simulation-state/H12/README.md), [H13](../research/simulation-state/H13/README.md), [E0b6p native evidence](../research/propwash/E0b6p/native/README.md))

### A prepared model needs an explicit ownership boundary

A copied native model stays unchanged when its source dictionary is edited, which protects its memory but can mix stale geometry with freshly computed GDScript propulsion inputs. Dictionary identity detects replacement, not nested edits. Invalidate generations on every preparation attempt, including failure; require explicit rebuild after edits and test backend invalidation through the adapter so stateless fallback cannot hide a stale handle. Moving decoding outside ticks does not remove this ownership obligation. ([E0b6p prepared-model evidence](../research/propwash/E0b6p/prepared-model/README.md))
