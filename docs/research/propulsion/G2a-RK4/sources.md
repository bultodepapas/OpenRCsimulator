# G2a / G2b — Rotor momentum, shaft dynamics, and RK4 sources

2026-10-09 · **Status: primary-source research notes; equations inform G2a/G2b experiments, not physical validation.**

## Governing equations and limits

For a rigid aircraft with body-frame angular rate `ω`, constant locked inertia `J_locked`, and relative rotor momentum `h`, angular-momentum balance gives

```text
M_ext = J_locked·ω̇ + ω×(J_locked·ω + h) + ḣ_body
ω̇ = J_locked⁻¹·[M_ext − ω×(J_locked·ω + h) − ḣ_body]
```

For a rotor fixed to a body shaft, `h = I_s Ω s`; with constant axial inertia and fixed body axis `s`, `ḣ_body = I_s Ω̇ s`. Simmons, Buning, and Murphy use this form in aircraft body axes: their Eqs. 29–31 include the propulsor angular-momentum derivative and the body-rate cross terms; they define each propulsor momentum as `I_p Ω_p`, rotate it into body axes, and sum the rotors. See [NASA NTRS 20210017459, §VIII.D, Eqs. 29–31, pp. 20–21](https://ntrs.nasa.gov/citations/20210017459).

The simple shaft law `I_s Ω̇ = Q_engine − Q_prop` is a useful lumped actuator model, but it treats `Ω` as if body rotation did not contribute to the rotor's absolute spin. If `Ω` is relative to a fuselage-fixed shaft, an axisymmetric rotor's absolute axial rate is `Ω + s·ω`; projecting its rotor-only angular-momentum balance onto `s` gives

```text
I_s (Ω̇ + s·ω̇) = Q_engine − Q_prop
```

under an ideal coaxial bearing and consistent torque signs. Thus exact shaft/body coupling includes the aircraft angular acceleration along the shaft and is implicit when combined with the aircraft equation. Dropping `s·ω̇` is an approximation whose size depends on `I_s / J_locked` and the maneuver; it should be identified as such. For a shaft that changes direction in body axes or a non-axisymmetric rotor, further terms are needed.

Richard's general-aviation engine/propeller model is a direct precedent for the lumped speed law: it derives engine speed from a torque balance on a short crankshaft with the propeller mounted on it, and explicitly neglects the crankshaft's own inertia relative to the propeller. The model is low-order and intended for engine/propeller dynamics, not full aircraft/rotor coupling. See [NASA-TM-107006, §“Engine Speed,” Eq. 8, p. 7, and state form Eq. 22](https://ntrs.nasa.gov/citations/19950026495).

The locked-inertia convention matters. `J_locked` must include the rotor's mass distribution as if locked to the airframe; `h` then adds only its relative spin momentum. If rotor mass or transverse inertia is omitted from `J_locked`, `J_locked·ω` is incomplete. In this repository, [aircraft_data.gd](../../../../app/physics/aircraft_data.gd) builds inertia from inventory component boxes; the P-51 propeller and engine are coarse inventory shapes, while [the P-51 data](../../../../app/data/aircraft/p51d_mustang_120.json) separately estimates axial rotating inertia. These inputs support a structurally useful experiment, not an exact rotor/airframe inertia split. The current [rigid-body equation](../../../../app/physics/rigid_body.gd) adds `h` inside `ω×(...)` but has no `ḣ`; [simulation.gd](../../../../app/sim/simulation.gd) holds `h` through RK4 stages and advances auxiliary shaft RPM before the body step. G2a should keep the body-stage `ḣ` synchronized with stage RPM and avoid counting engine torque as an external aircraft moment: propeller aerodynamic reaction is external; engine torque is internal to the aircraft-plus-rotor system.

NASA TP-2511 independently derives coupled rotational equations for a body with rotating appendages, including terms dependent on both body and appendage rates. It supports the need to account for relative-motion coupling in a complete model, while its articulated solar-panel geometry is not a propeller-specific shaft model. See [NASA-TP-2511, Eqs. 15–18 and 25–27, pp. 12–15](https://ntrs.nasa.gov/citations/19850025835).

## RK4 and piecewise tables

The classical RK4 formula has fourth-order global convergence only when its right-hand side has enough smoothness. This matters for the simulator's piecewise-linear propulsion tables: the table value is continuous, but its slope changes at each knot. Nordam and Duran give a directly relevant published experiment. For a continuous right-hand side with a derivative kink, their RK4 error scales approximately as `h²` when steps cross the kink, but returns to `h⁴` when the integration stops and restarts at the known kink; in their linear-interpolation data, RK4 likewise failed to achieve fourth-order convergence. See [Nordam and Duran, “Numerical integrators for Lagrangian oceanography,” §3.1–3.2, §5.1, Appendix A, Fig. 2, GMD 13, 5935–5957 (2020)](https://gmd.copernicus.org/articles/13/5935/2020/).

For RK4 convergence evidence, halve the step over a fixed smooth interval and check that error ratios approach 16 (`h⁴`). Separately include trajectories that cross propulsion-table knots and report the measured order; do not infer fourth order from the integrator formula alone. If a knot can be located reliably, split/restart at the crossing. Otherwise preserve the current interpolation and quantify the observed error/order, including the existing floors and extrapolation branches.

## Source list

- Simmons, B. M., Buning, P. G., and Murphy, P. C. (2021). “Full-Envelope Aero-Propulsive Model Identification for Lift+Cruise Aircraft Using Computational Experiments.” NASA Langley / AIAA AVIATION Forum. [NTRS record and PDF](https://ntrs.nasa.gov/citations/20210017459).
- Richard, J. C. (1995). “Low-order nonlinear dynamic model of IC engine-variable pitch propeller system for general aviation aircraft.” NASA-TM-107006. [NTRS record and PDF](https://ntrs.nasa.gov/citations/19950026495).
- Rheinfurth, M. H., and Carroll, S. N. (1985). “Space Station Rotational Equations of Motion.” NASA-TP-2511. [NTRS record and PDF](https://ntrs.nasa.gov/citations/19850025835).
- Nordam, T., and Duran, R. (2020). “Numerical integrators for Lagrangian oceanography.” *Geoscientific Model Development*, 13, 5935–5957. [Publisher article](https://doi.org/10.5194/gmd-13-5935-2020).
