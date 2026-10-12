# Coupled shaft dynamics

2026-10-12 · Revision 2 · Step prefix: **G2a / G2b** (main-line ROADMAP).

**Status:** The opt-in P-51 coupled shaft route is software verified. Electric synthetic sessions now use the coupled route through [ELECTRIC-PROPULSION-PLAN](ELECTRIC-PROPULSION-PLAN.md). Production promotion, physical validation and the 500 µs tick target remain open.

## Implemented contract

Coupled RK4 integrates body state and relative propeller RPM together. Each stage evaluates its own RPM, air-relative axial inflow, field density and engine charge. The solver reuses the body/rotor angular-acceleration balance and applies relative-spin reaction once. Propeller aerodynamic reaction is external; engine torque/friction exchange momentum internally. Rotor inertia is estimated model data; this does not validate an engine map or aircraft response.

For the P-51 development route, select `-- --aircraft=p51d-mustang-120 --shaft-integrator=coupled-rk4`. Combustion aircraft keep `split` as the default. Electric propulsion requires coupled RK4 and rejects an explicit split route. A model needs valid propeller shaft/rotor data and positive carrier inertia; this plan adds no shaft data to aircraft and makes no physical electric conversion claim. Turbines still use their separate spool law.

Continuous RPM is carried with the physics state and the accepted endpoint is mirrored to `aux[0]` for existing consumers. Stage evaluation does not change RNG or sampled modes. Body state, continuous RPM, mirror and clock commit or roll back together. Coupled checkpoints carry integration identity; restore requires a destination configured for the matching mode. Golden v1 remains outside this continuous-state experiment.

## Step register

| ID | Delivery and proof | Status |
| --- | --- | --- |
| G2a, experimental slice | Opt-in shaft/body RK4, stage-local propulsion/wake and endpoint RPM. [143-suite gate, 54 focused checks, seven CLI tests and 42 refinements](research/propulsion/G2a-RK4/README.md) | Complete — software |
| G2b, propeller slice | Fixed-axis relative-spin reaction with locked inertia; simultaneous body/rotor balances, signs, steady limit and momentum checks. | Software verified |
| G2a/G2b promotion | Make coupling the production default after aircraft response and per-tick acceptance. | Open |
| G2a-R1 | Reuse one aerodynamic stage evaluation. [Exact eight-case parity, 143-suite gate and paired cost](research/propulsion/G2a-R1/README.md) | Complete — software; 500 µs gate open |
| G2b turbine | Couple signed turbine spool/body acceleration. | Deferred to turbine owner |

G2a-R1 measured 730–765 µs per step in its documented fixtures, 42–46% below the matched coupled baseline. This remains above the 500 µs target and does not close the full-session performance gate. Electric-specific costs and acceptance are tracked in EL2a/Gate P.

The RK derivative uses `I*(Omega_dot + axis·omega_dot) = Q_engine_net − Q_prop`; rotor momentum, gyro precession and `−I*Omega_dot*axis` reaction are accounted for once. Current fixed-axis coupling, constant estimated rotor inertia, source/propeller tables, stopped-prop cutoff and reverse-spin limits bound the claim. [Derivation and assumptions](research/propulsion/G2a-RK4/sources.md); [electric source contract](ELECTRIC-PROPULSION-PLAN.md).
