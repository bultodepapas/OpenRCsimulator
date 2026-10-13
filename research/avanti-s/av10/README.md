# AV-10b independent variable-mass reference

**Date:** 2026-10-13. **Status:** independent mechanics reference and analytic fixtures; production integration and physical acceptance remain pending. **Step:** AV-10b in the [turbine realism plan](../../../docs/plans/turbine-realism.md#13-incremental-implementation-sequence), especially [§4.5](../../../docs/plans/turbine-realism.md#45-changing-mass-cg-inertia-and-datum).

This directory contains a stdlib-only Python reference for a rigid dry body plus a prescribed body-fixed liquid inventory. It derives the open-system equations at a fixed dry-body datum, implements the equivalent instantaneous-CG equations, and compares them on independent fixtures. It does not change `app/` or establish an aircraft-specific fuel schedule.

Run the fixtures from the repository root:

```powershell
python -m unittest discover -s research/avanti-s/av10 -p 'test_*.py'
```

## Model and signs

Let `O` be fixed in the dry structure and let `R` map body-axis vectors to inertial axes. The velocity of `O`, resolved in body axes, is `v = Rᵀ x_O_dot`; body angular velocity is `omega`. For any body-resolved vector `a`, its inertial derivative is `R (a_dot + omega × a)`, where `a_dot` is its body-coordinate derivative.

For the remaining body and liquid, let `m` be total mass, `h` the first mass moment about `O`, and `J_O` the inertia tensor about `O`:

```text
h   = integral(r dm) = m c
J_O = integral(S(r) dm)
S(r) = |r|² I - r rᵀ
```

`S(r)` is the physical parallel-axis tensor; its off-diagonal entries are negative products of inertia. For each point-outflow element `i`, `mu_i >= 0` is outward mass flow, `r_i` is its body-fixed location, and `u_i` is its velocity relative to the local rigid-body velocity. Its absolute body-axis velocity is `v_e,i = v + omega × r_i + u_i`.

For point-outflow elements, the model requires matching inventory rates:

```text
m_dot   = -sum_i(mu_i)
h_dot   = -sum_i(mu_i r_i)
J_O_dot = -sum_i(mu_i S(r_i))
```

These are conservation constraints, not a consequence of specifying only a scalar fuel rate. A distributed sink can be represented by quadrature points whose rates reproduce its mass, first-moment, and second-moment fluxes. A single pickup with rate `mu` specifies only the point-flux moments at that pickup. In particular, neither a tank fill profile nor a pickup location alone specifies the internal liquid velocity or the spatial distribution of mass flow into the pickup.

## Fixed-datum open-system balance

The remaining matter has linear momentum and angular momentum about `O`, formed with absolute particle velocities:

```text
P_b   = m v + omega × h
L_O,b = h × v + J_O omega
```

For external resultant force `F` and external moment `tau_O` about `O`, the control-volume balances are

```text
F     = inertial_rate(P_b) + sum_i(mu_i v_e,i)
tau_O = inertial_rate(L_O,b) + v × P_b
        + sum_i(mu_i r_i × v_e,i)
```

The `v × P_b` term is present because `O` moves with the body while angular momentum is formed using absolute velocities. Expanding the balances and substituting the inventory rates above cancels the co-moving outlet momentum against the corresponding changing mass properties. The resulting equations are

```text
F = m (v_dot + omega × v)
    + omega_dot × h + omega × (omega × h)
    + sum_i(mu_i u_i)

tau_O = h × v_dot + J_O omega_dot
         + omega × L_O,b + v × P_b
         + sum_i(mu_i r_i × u_i)
```

The six acceleration components follow from one spatial-inertia solve:

```text
[ m I       -[h]x ] [ v_dot     ]   [ F - m omega×v - omega×(omega×h) - sum(mu_i u_i) ]
[[h]x        J_O  ] [ omega_dot ] = [ tau_O - omega×L_O,b - v×P_b - sum(mu_i r_i×u_i) ]
```

Here `[h]x a = h × a`. A co-moving outlet has `u_i = 0`; it creates no rocket acceleration by itself. Its changing mass, center, and inertia are already balanced by the momentum it carries away. Adding a `-J_dot omega` term without the matching angular-momentum flux breaks that balance.

## Net turbine thrust is applied once

In the aircraft-level reduced model, put installed **net engine thrust** into `F` once and use its nozzle arm once when forming the moment. NASA's [general thrust equation](https://www1.grc.nasa.gov/beginners-guide-to-aeronautics/thrust-force/) includes exit momentum, inlet momentum, and the pressure-area term; its gas-turbine simplification gives gross thrust less ram drag as net thrust. Do not add a second exhaust-momentum term when that net thrust is already the applied engine force. If gas flow is modeled directly with a separate engine control volume, derive the engine force from that balance and remove the net-thrust surrogate.

The constant-thrust fixture has no rotation, centered inventory loss `m(t) = m0 - k t`, and constant net thrust `F`. The fixed-datum equation gives `v_dot = F/m`, so

```text
v(t) - v(0) = (F/k) ln(m0 / (m0 - k t))
```

The test integrates the reference acceleration with RK4 and compares it to this closed form. It sets relative outlet speed to zero, so a duplicated rocket term would fail the fixture. Deleting fuel at a tank pickup is an aircraft-mass boundary approximation: in a real aircraft, fuel remains aboard while it travels through the pump, lines, and engine. Include that inventory when material to the mass-property error budget.

## Exact current-CG transform

Let `c = h/m`, `q_i = r_i - c`, and `I_C = J_O - m S(c)`. For the same point-outflow model,

```text
c_dot   = -(1/m) sum_i(mu_i q_i)
I_C_dot = -sum_i(mu_i S(q_i))
```

The momentum velocity of the current inventory center is `v_m = P_b/m = v + omega × c`. The geometric center position is `x_C = x_O + R c`, giving the exact rate

```text
x_C_dot = R (v + omega × c + c_dot)
        = R (v_m + c_dot)
v_m_dot = v_dot + omega_dot × c + omega × c_dot
```

Thus `v_m` is generally not the derivative of geometric CG position. A solver that stores momentum velocity must integrate geometric position with `R (v_m + c_dot)`. A solver that stores the geometric position derivative must reconstruct momentum velocity as `Rᵀ x_C_dot - c_dot` before applying the dynamics.

Taking moments about the moving CG, with `tau_C = tau_O - c × F`, gives the equivalent current-CG equations for point-outflow elements:

```text
F = m (v_m_dot + omega × v_m)
    + sum_i(mu_i (omega × q_i + u_i))

tau_C = I_C omega_dot + omega × (I_C omega) + I_C_dot omega
         + sum_i(mu_i q_i × (omega × q_i + u_i))
```

For co-moving outlets, `I_C_dot omega` cancels the outlet angular-momentum term because `S(q) omega = q × (omega × q)`. In the moving-origin balance, `x_C_dot × P_b` also cancels the common-translation part of the outlet flux: `m c_dot × v_m = -sum_i(mu_i q_i) × v_m`. This is why no extra translation term appears in the displayed current-CG equation. A finite distributed outflow must use the same spatial quadrature in the changing inertia and angular-momentum flux; a point-outflow formula does not carry an omitted finite box inertia automatically. The off-axis fixture compares fixed-datum and current-CG accelerations using the exact derivative transform and reconstructs the original open-system force and moment balances.

## Quasi-static liquid and distributed-inventory limits

The equations are exact for their declared rigid-body mass distribution and outlet velocities. They do not supply the distribution or velocities. In particular:

- A body-fixed liquid approximation requires internal liquid velocity and slosh forces to be negligible over the simulated maneuvers and integration step. A quasi-static free-surface approximation also requires settling to be fast relative to changes in body acceleration, orientation, and fuel depletion.
- A measured fill profile can establish the inventory's current mass, centroid, and inertia if the measurement resolves density and occupied geometry. It does not determine the internal velocity field, mass-flux distribution into a pickup, or momentum transport through a hose and engine. Those require a separate flow model, measurements, or a validated approximation.
- If liquid redistributes inside the tank, `mu` and a single pickup position do not determine `h_dot`, `J_O_dot`, or internal fluid momentum. The current inventory profile and its time derivative are distinct from the boundary mass-flux moments.
- A homothetically shrinking annulus requires distributed outlet fluxes whose first and second moments match the shrinking inventory. The annulus fixture represents that flux with four symmetric point elements. A single point pickup does not produce the same inertia rate for a finite annulus.
- Recompute stage-local mass properties and flux moments at every integration stage for a stage-coupled method. Holding them fixed for an outer tick is acceptable only after time-step refinement bounds the acceleration, trim, contact, and force-arm errors.

Fuel transfer from tank to pump, lines, and engine remains part of aircraft mass until it crosses the chosen aircraft control-volume boundary. The reference can delete fuel at a selected pickup only as an explicit reduced boundary convention. To model the whole aircraft more closely, retain fuel in its evolving line/engine locations and remove exhaust at the aircraft boundary, with a consistent engine thrust control volume.

NASA-CR-190838 §2.3, printed p. 14, writes the control-volume moment-of-momentum balance with stored angular momentum, inlet/outlet angular-momentum flow, and applied moment; see the [NASA report PDF](https://ntrs.nasa.gov/api/citations/19920024954/downloads/19920024954.pdf) or [NTRS record](https://ntrs.nasa.gov/citations/19920024954). This supports the angular-flux term in the derivation. It does not provide this aircraft's pickup flow, fuel schedule, or tank fill law.

## Conditions for a moving-CG fixed-box reduction

A moving-CG production reduction can use a fixed estimated fuel centroid and box only when the approximation and its flux are internally consistent. One precise model is:

- Treat the dry structure, tank shell, and any fixed line hardware as a constant dry component with mass `m_d`, centroid `c_d`, and centroidal inertia `J_d`.
- Treat fuel as a homothetically scaled box with mass `m_f(t)`, fixed body-axis centroid `c_f`, and fixed centroidal inertia per unit fuel mass `B`. `B` is symmetric positive semidefinite and must describe the declared box approximation; it is not inferred from a pickup.
- At every integration stage compute

  ```text
  m   = m_d + m_f
  h   = m_d c_d + m_f c_f
  J_O = J_d + m_d S(c_d) + m_f (B + S(c_f))
  c   = h/m
  I_C = J_O - m S(c)
  c_dot = -mu (c_f - c)/m,  where mu = -m_f_dot >= 0
  ```

- Make the modeled outflow moments match those property rates. For a distributed co-moving drain (`u_j = 0`), choose point-quadrature rates and positions satisfying `sum(mu_j) = mu`, `sum(mu_j r_j) = mu c_f`, and `sum(mu_j S(r_j)) = mu (B + S(c_f))`. Then the same quadrature in the current-CG angular flux cancels `I_C_dot omega` exactly. This is a mathematical proportional-drain convention; it is not a claim that a single physical pickup drains the whole box uniformly.
- If only a single pickup at `r_p` and scalar `mu` are available, the exact point model instead requires mass-property rates from that point: `h_dot = -mu r_p` and `J_O_dot = -mu S(r_p)`. It cannot at the same time retain a finite box tensor that scales with fuel mass. For the fixed-box properties above, a single point flux matches all three moments only in the point-mass limit `B = 0` with `r_p = c_f`. Otherwise use a distributed flux model or explicitly treat the mismatch as an approximation and bound its effects over the intended envelope.
- Store either momentum velocity `v_m = P/m` and integrate geometric CG position with `x_C_dot = R(v_m + c_dot)`, or store geometric position rate and reconstruct `v_m = Rᵀ x_C_dot - c_dot`. Use that same convention in force evaluation, interpolation, contact, replay, and rendering. Compute all moments and force arms about the current CG consistently.
- Apply the installed net turbine force and its moment once. Do not add explicit exhaust momentum on top of net thrust. If the aircraft fuel-mass boundary is placed at the pickup, bound the omitted pump/line/engine inventory and transfer effects; otherwise model that fuel until the exhaust boundary.
- Validate the estimated centroid and box tensor against fill-dependent evidence or documented bounds across the intended attitude and acceleration range. Check tensor symmetry and positive definiteness at every stage, mass positivity through unusable volume, off-axis force-arm behavior, and sensitivity of acceleration, trim, contact, and flight response to plausible centroid/box/flux variations. A single tank profile measurement does not establish the momentum-flow assumption.

If these conditions cannot be supported, use a fixed dry-body datum with an explicit fill-dependent inventory and outflow model, or retain the existing constant-mass route. The current rigid-body derivative accepts one mass and CG inertia; replacing those values each tick does not implement either variable-mass formulation.

## Fixtures and results

`test_variable_mass_reference.py` checks:

1. Constant net thrust and linear mass loss against the logarithmic solution.
2. Co-moving outflow with no applied wrench produces no translational acceleration or spin.
3. Uniform rotating annulus drainage carries away the declining angular momentum and produces no spurious spin-up.
4. An off-axis dry body, tank shell, and liquid pickup with full symmetric tensors give matching fixed-datum/current-CG results; the solved state also satisfies the original open-system flux balances.
5. The geometric CG position rate includes `c_dot` and agrees with a finite-difference position transform.

These are software/mechanics fixtures, not physical validation of the Ventage Jet installation. No aircraft-specific pickup, fuel transit, slosh, nozzle flux, or tank fill map was available for this reference.

## Integration recommendation and remaining unknowns

AV-10b in the plan prefers a fixed dry-structure datum for the optional variable-mass route. It keeps hull placement and dry-body geometry continuous and requires one six-by-six spatial-inertia solve per stage. Recompute stage-local `m`, `h`, `J_O`, and flux moments from a validated inventory model; express gravity, aerodynamic, gear/contact, and net-thrust wrenches about the same datum. Convert to current-CG position and telemetry only at a documented boundary. Preserve the constant-mass path until the variable route passes integration, replay, and refinement gates.

The moving-CG route is also mathematically valid under the explicit state and flux conditions above. Before AV-10c, resolve the authored tank geometry and fill-dependent centroid/tensor; actual pickup and unusable volume; pump/hopper/line fuel inventory; whether tank depletion is an acceptable aircraft-boundary mass-loss convention; installed net-thrust control-volume conventions; and measured slosh/settling behavior under representative acceleration. The conservation law is determined, but the aircraft-specific inventory and flux schedules are not.
