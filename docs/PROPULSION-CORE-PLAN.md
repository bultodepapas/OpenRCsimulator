# Coupled shaft dynamics

This guide covers the fixed-axis G2a/G2b propeller solver. The [project roadmap](../ROADMAP.md) owns promotion priorities and the physics timing gate.

## Implemented contract

Coupled RK4 integrates body state and relative propeller RPM together. Each stage evaluates its own RPM, air-relative axial inflow, field density and engine charge. The solver reuses the body/rotor angular-acceleration balance and applies relative-spin reaction once. Propeller aerodynamic reaction is external; engine torque/friction exchange momentum internally. Rotor inertia is estimated model data; this does not validate an engine map or aircraft response.

The P-51's finite-gasoline configuration now selects coupled RK4 by default. Other prescribed-fuel combustion aircraft keep `split` as the default. Electric, explicit finite-glow and finite-gasoline propeller propulsion require coupled RK4 and reject an explicit split route. `FlightSession.setup_shaft_integrator()` validates the request and `FlightSession._commit_aircraft()` chooses the default ([session source](../app/sim/flight_session.gd)). A model needs valid propeller shaft/rotor data and positive carrier inertia. Turbines use a separate continuous spool law; coupling their signed spool/body acceleration remains deferred to the turbine owner.

Fuel depletion and shaft coupling are separate concerns. `FlightSession.mass_properties()` publishes live mass/CG/inertia for accepted finite-fuel states; `GlowFlight.properties()` and `LiquidFuelFlight.properties()` feed the shared fixed-datum law. The [fuel plan](plans/fuel-mass-balance.md) owns balance, fleet integration and remaining qualification gates.

Continuous RPM is carried with the physics state and the accepted endpoint is mirrored to `aux[0]` for existing consumers. Stage evaluation does not change RNG or sampled modes. Body state, continuous RPM, mirror and clock commit or roll back together. Coupled checkpoints carry integration identity; restore requires a destination configured for the matching mode. Golden v1 remains outside this continuous-state experiment.

## Qualification and remaining work

| Question | Evidence or next action |
| --- | --- |
| Does the solver conserve angular momentum? | The shaft balance is `I*(Omega_dot + axis·omega_dot) = Q_engine_net − Q_prop`. Check the body/rotor reaction, sign and steady limit against the [derivation](research/propulsion/G2a-RK4/sources.md) and [coupled shaft test](../app/tests/test_shaft_coupled.gd). |
| Does a smooth throttle transient converge? | The [P-51 refinement test](../app/tests/test_shaft_refinement.gd) compares 60, 120 and 240 Hz against 1920 Hz. It checks fourth-order behavior with the held downwash lag removed, second-order behavior with that lag present, and an older prescribed-fuel split fixture. These are distinct model configurations. |
| Can another prescribed-fuel aircraft switch to coupled RK4? | Check its flight response and rotor/airframe parameters, then measure per-tick cost in its supported regimes. Fixed-axis geometry, estimated rotor inertia, propeller tables, stopped-prop cutoff and reverse-spin limits bound the claim. Turbine spool/body coupling remains a separate turbine task. |

The [original coupled solver campaign](research/propulsion/G2a-RK4/README.md) and [stage-reuse comparison](research/propulsion/G2a-R1/README.md) retain the software evidence. G2a-R1 measured 730–765 µs per step on those fixtures. For current performance, identify the actual selected backend and report whole-session per-tick p50/p95 on the idle target host. Include ground, active wake and applicable electric event ticks.
