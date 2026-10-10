# Coupled shaft dynamics

2026-10-09 · Step prefix: **G2a / G2b** (main-line ROADMAP) · **Status: experimental P-51 implementation software verified; physical and performance acceptance remain open.**

The first slice integrates relative propeller shaft RPM with body state in RK4. Each stage uses its own RPM, air-relative axial inflow, field density and dry-air engine charge. It also solves the body/rotor angular-acceleration coupling and applies relative-spin reaction exactly once. Aircraft coefficients and generated model data are unchanged.

| Step | Delivery | Proof/status |
| --- | --- | --- |
| G2a, experimental slice | Opt-in shaft/body RK4; stage-local propulsion, wake and rotor momentum; exact endpoint RPM telemetry | [Evidence](research/propulsion/G2a-RK4/README.md): 143-suite gate, 54 focused checks, seven CLI tests, 42 refinement runs and isolated mutations |
| G2b, propeller slice | Fixed-axis relative-spin reaction with locked inertia and body axial acceleration | Simultaneous body/rotor balances, signs, steady limit and angular-momentum checks |
| G2a/G2b promotion | Adopt coupling as the production default; validate actual aircraft response and per-tick cost | Open; experimental route remains explicit |
| G2a stage cost | Reuse one aerodynamic evaluation across the coupled stage's loads and shaft derivative | Pending; [observed cost](research/propulsion/G2a-RK4/cost.md) is 1263–1325 µs/step on this host; 500 µs target remains open |
| G2b turbine | Signed spool/body acceleration coupling | Deferred to the turbine owner; no new turbine torque law |

Use `-- --aircraft=p51d-mustang-120 --shaft-integrator=coupled-rk4`. `split` remains the default. Aircraft without shaft data and positive carrier inertia refuse the experiment. This does not create shaft data for glow or electric aircraft.

Continuous layout is axial wake increments first, then one relative shaft RPM; `aux[0]` mirrors the accepted endpoint for existing renderer/audio/CSV consumers. Sampled servos and turbulence retain their tick policy. The RK derivative never changes RNG/modes. Body, continuous RPM, aux mirror and clock commit together; faults roll back together. Coupled flight checkpoints use v4 with explicit integration identity and weather. Restoring requires a destination already configured for the same integration mode. Golden v1 excludes this continuous-state experiment.

Propeller aerodynamic reaction is an external moment. Engine torque and bearing friction exchange momentum internally. The solver retains locked aircraft inertia and relative rotor momentum, includes gyroscopic precession once, and applies `−I*Omega_dot*axis` once. It also accounts for body angular acceleration along the shaft in `I*(Omega_dot + axis·omega_dot) = Q_engine_net − Q_prop`. [Primary-source notes](research/propulsion/G2a-RK4/sources.md) record the assumptions and derivation.

The rotor is axisymmetric with a fixed shaft axis and constant estimated inertia. Current Ct/Cp and engine power tables retain their measured/derived/estimated provenance. Their slope changes, stopped-prop cutoff, reverse-spin omission and other sampled physics limit global convergence; numerical evidence does not validate an engine map or full dead-stick handling.
