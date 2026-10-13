# AV-10b independent variable-mass reference

**Date:** 2026-10-13. **Status:** independent mechanics reference and analytic fixtures; production integration and physical acceptance remain pending. **Step:** AV-10b in the [turbine realism plan](../../../docs/plans/turbine-realism.md#13-incremental-implementation-sequence), especially [§4.5](../../../docs/plans/turbine-realism.md#45-changing-mass-cg-inertia-and-datum).

This directory contains a stdlib-only Python reference for a rigid dry body plus body-fixed liquid mass. It derives the open-system equations at a fixed dry-body datum, implements a second formulation at the instantaneous center of mass, and compares both on independent fixtures. It does not change `app/` or decide a production architecture.

Run the fixtures from the repository root:

```powershell
python -m unittest discover -s research/avanti-s/av10 -p 'test_*.py'
```

## Model and signs

Let (O) be a datum rigidly attached to the dry structure, (R) map body vectors to inertial axes, (mathbf v) be the inertial velocity of (O) expressed in body axes, and (oldsymbolomega) be body angular velocity. A dot on a body-resolved vector below is its derivative in body coordinates; its inertial derivative is (R(dot{mathbf a}+oldsymbolomega\timesmathbf a)).

For the remaining body and liquid, define total mass (m), first moment (mathbf h=intmathbf r,dm=mmathbf c), and inertia about (O), (mathbf J_O=int S(mathbf r),dm), with

\[
S(\mathbf r)=\lVert\mathbf r\rVert^2\mathbf 1-\mathbf r\mathbf r^T.
\]

The tensor uses the usual physical inertia matrix, including negative products of inertia off diagonal. For each outlet (i), (mu_i\ge0) is outward mass flow, (mathbf r_i) is its body-fixed location, and (mathbf u_i) is flow velocity relative to the local rigid-body velocity. Thus the outlet's absolute velocity, resolved in body axes, is

\[
\mathbf v_{e,i}=\mathbf v+\boldsymbol\omega\times\mathbf r_i+\mathbf u_i.
\]

For material leaving at those outlets, the inventory moments change at rates

\[
\dot m=-\sum_i\mu_i,\qquad
\dot{\mathbf h}=-\sum_i\mu_i\mathbf r_i,\qquad
\dot{\mathbf J}_O=-\sum_i\mu_i S(\mathbf r_i).
\]

These rates are part of the model contract. A single pickup point does not, by itself, determine how a distributed reservoir's centroid and tensor change if the remaining liquid is also being redistributed.

## Fixed-datum open-system balance

The remaining matter has linear momentum and angular momentum about (O), using **absolute** particle velocities:

\[
\mathbf P_b=m\mathbf v+\boldsymbol\omega\times\mathbf h,\qquad
\mathbf L_{O,b}=\mathbf h\times\mathbf v+\mathbf J_O\boldsymbol\omega.
\]

For external resultant force \(\mathbf F\) and external moment \(\boldsymbol\tau_O\) about (O), Reynolds transport gives

\[
\mathbf F=\left(\frac{d\mathbf P}{dt}\right)_I+\sum_i\mu_i\mathbf v_{e,i},
\]

\[
\boldsymbol\tau_O=\left(\frac{d\mathbf L_O}{dt}\right)_I
 +\mathbf v_O\times\mathbf P+\sum_i\mu_i\mathbf r_i\times\mathbf v_{e,i}.
\]

The \(\mathbf v_O\times\mathbf P\) term appears because the angular-momentum reference point moves with the body. Substituting the momentum definitions and the three inventory rates above cancels every co-moving part of the outlet flux against the corresponding changing inventory moment. The result is

\[
\mathbf F=m(\dot{\mathbf v}+\boldsymbol\omega\times\mathbf v)
 +\dot{\boldsymbol\omega}\times\mathbf h
 +\boldsymbol\omega\times(\boldsymbol\omega\times\mathbf h)
 +\sum_i\mu_i\mathbf u_i,
\]

\[
\boldsymbol\tau_O=\mathbf h\times\dot{\mathbf v}
 +\mathbf J_O\dot{\boldsymbol\omega}
 +\boldsymbol\omega\times\mathbf L_{O,b}
 +\mathbf v\times\mathbf P_b
 +\sum_i\mu_i\mathbf r_i\times\mathbf u_i.
\]

Equivalently, the six unknown derivatives follow from one spatial-inertia solve:

\[
\begin{bmatrix}
m\mathbf 1 & -[\mathbf h]_\times\\
[\mathbf h]_\times & \mathbf J_O
\end{bmatrix}
\begin{bmatrix}\dot{\mathbf v}\\\dot{\boldsymbol\omega}\end{bmatrix}
=
\begin{bmatrix}
\mathbf F-m\boldsymbol\omega\times\mathbf v
 -\boldsymbol\omega\times(\boldsymbol\omega\times\mathbf h)-\sum_i\mu_i\mathbf u_i\\
\boldsymbol\tau_O-\boldsymbol\omega\times\mathbf L_{O,b}
 -\mathbf v\times\mathbf P_b-\sum_i\mu_i\mathbf r_i\times\mathbf u_i
\end{bmatrix}.
\]

Here \([\mathbf h]_\times\mathbf a=\mathbf h\times\mathbf a\). In particular, a co-moving outlet has \(\mathbf u_i=0\). It creates no rocket acceleration by itself; its changing mass, center and inertia are already balanced by the momentum it carries away. An added \(-\dot{\mathbf J}\boldsymbol\omega\) term without the matching angular-momentum flux breaks that balance.

### Net turbine thrust is applied once

For the aircraft-level reduced model, put measured/modelled **net engine thrust** into \(\mathbf F\) once, at its nozzle arm when forming \(\boldsymbol\tau_O\). If fuel inventory is removed with the body-co-moving outlet convention (\(\mathbf u=0\)), do not add a second \(\dot m\,\mathbf v_{exhaust}\) term. NASA's general thrust equation already includes exit momentum, inlet momentum and the pressure-area term; its gas-turbine simplification identifies gross thrust less ram drag as the net force. See NASA Glenn's [Thrust Equation](https://www1.grc.nasa.gov/beginners-guide-to-aeronautics/thrust-force/) and the NASA Kennedy Center [Expendable Launch Vehicles Briefing and Basic Rocketry Physics](https://ntrs.nasa.gov/citations/20100036816), slides 2-14 and 2-15.

The constant-thrust fixture has no rotation, a centered inventory loss \(m(t)=m_0-kt\), and constant net thrust (F). The fixed-datum equation reduces to \(\dot v=F/m\), hence

\[
v(t)-v(0)=\frac{F}{k}\ln\!\left(\frac{m_0}{m_0-kt}\right).
\]

The test integrates the reference acceleration with RK4 and compares it to this closed form. It deliberately assigns zero relative outlet speed, so it can detect a duplicated rocket term. This fixture is a reduced aircraft model; it is not a claim that the tank pickup is the physical aircraft boundary where burned fuel exits.

## Exact current-CG transform

Let \(\mathbf c=\mathbf h/m\), \(\mathbf q_i=\mathbf r_i-\mathbf c\), and \(\mathbf I_C=\mathbf J_O-mS(\mathbf c)\). From the same outlet moments,

\[
\dot{\mathbf c}=-\frac{1}{m}\sum_i\mu_i\mathbf q_i,\qquad
\dot{\mathbf I}_C=-\sum_i\mu_iS(\mathbf q_i).
\]

The instantaneous momentum velocity of the current inventory center is

\[
\mathbf v_m=\frac{\mathbf P}{m}=\mathbf v+\boldsymbol\omega\times\mathbf c.
\]

The geometric center position is \(\mathbf x_C=\mathbf x_O+R\mathbf c\), so its exact kinematic rate is

\[
\dot{\mathbf x}_C=R(\mathbf v+\boldsymbol\omega\times\mathbf c+\dot{\mathbf c})
 =R(\mathbf v_m+\dot{\mathbf c}).
\]

Thus \(\mathbf v_m\) is generally **not** \(\dot{\mathbf x}_C\). If a solver stores position at the moving CG and velocity as \(\mathbf P/m\), it must integrate position with the extra \(R\dot{\mathbf c}\). If it stores the geometric position derivative instead, reconstruct momentum using \(\mathbf P=mR(\dot{\mathbf x}_C^b-\dot{\mathbf c})\). The fixed-datum to momentum-velocity derivative is also exact:

\[
\dot{\mathbf v}_m=\dot{\mathbf v}+\dot{\boldsymbol\omega}\times\mathbf c
 +\boldsymbol\omega\times\dot{\mathbf c}.
\]

Taking moments about the moving CG, with \(\boldsymbol\tau_C=\boldsymbol\tau_O-\mathbf c\times\mathbf F\), gives the independently coded equivalent equations

\[
\mathbf F=m(\dot{\mathbf v}_m+\boldsymbol\omega\times\mathbf v_m)
 +\sum_i\mu_i(\boldsymbol\omega\times\mathbf q_i+\mathbf u_i),
\]

\[
\boldsymbol\tau_C=\mathbf I_C\dot{\boldsymbol\omega}
 +\boldsymbol\omega\times(\mathbf I_C\boldsymbol\omega)
 +\dot{\mathbf I}_C\boldsymbol\omega
 +\sum_i\mu_i\mathbf q_i\times(\boldsymbol\omega\times\mathbf q_i+\mathbf u_i).
\]

For co-moving outlets, \(\dot{\mathbf I}_C\boldsymbol\omega\) cancels the outlet angular-momentum term because \(S(\mathbf q)\boldsymbol\omega=\mathbf q\times(\boldsymbol\omega\times\mathbf q)\). The off-axis fixture compares angular acceleration directly and compares the two translational derivatives using the exact transform above. It also reconstructs the original open-system force and moment balances from the solved accelerations.

## When quasi-static tank mass properties are valid

The reference equations are exact for their declared rigid-body control volume and outlet kinematics. The tank model used to supply (m,\mathbf h,\mathbf J_O) is a separate physical assumption.

- A body-fixed liquid approximation is reasonable only while internal liquid velocity and slosh loads are negligible for the maneuver and step size of interest. A quasi-static free-surface model additionally needs liquid settling to be fast compared with the changes in body acceleration/orientation and the depletion time.
- A fixed liquid centroid and shape scaled by fill is valid only if measured or geometric fill-dependent first/second moments stay within the flight-model error budget. A box with mass scaled but geometry frozen is an estimate; it does not follow automatically from the pickup location.
- Exact single-port moment rates require the removed material's current location to be that port. A homothetically shrinking annulus instead needs the outlet's *distributed* mass-flux moments to match its changing first/second moments. The annulus fixture uses four symmetric outlets whose first and second moments exactly reproduce uniform ring drainage.
- If the actual fluid distribution changes independently of the outlet location, \(\mu\) and \(\mathbf r_{pickup}\) alone do not determine \(\dot{\mathbf h}\), \(\dot{\mathbf J}_O\), or internal momentum transfer. Measure a fill-dependent distribution or model tank geometry, free surface/slosh, and internal flow. Do not infer those rates from a generic tank label.
- Recompute the mass properties from the actual fuel state at every integration stage for a stage-coupled method. Holding them fixed for one outer tick is only acceptable after time-step refinement bounds the resulting acceleration, trim, contact and force-arm errors.
- Fuel leaves the tank for the pump/lines/engine before its combustion products leave the aircraft. The simple reference deletes inventory at a selected pickup and does not model that internal transit or line inventory. For exact whole-aircraft mass accounting, retain fuel in its changing line/engine location and remove exhaust at the aircraft boundary, or quantify the approximation. Keep the engine net-thrust control volume consistent with whichever boundary is chosen.

NASA's [Dynamic Modeling of Solar Dynamic Components and Systems](https://ntrs.nasa.gov/citations/19920024954), §2.3, writes the control-volume moment-of-momentum balance with stored angular momentum and inlet/outlet angular-momentum flow. It supports carrying the angular flux term; it does not supply an RC tank's pickup flow or fill law.

## Fixtures and results

`test_variable_mass_reference.py` checks:

1. Constant net thrust and linear mass loss against the logarithmic solution.
2. Co-moving outflow with no applied wrench produces no translational acceleration or spin.
3. Uniform rotating annulus drainage carries away exactly the decreasing angular momentum and produces no spurious spin-up.
4. An off-axis dry body, tank shell and liquid pickup with full symmetric tensors give matching fixed-datum/current-CG results; the solved state also satisfies the original open-system flux balances.
5. The geometric CG position rate includes \(\dot{\mathbf c}\) and agrees with a finite-difference position transform.

These are software/mechanics fixtures, not physical validation of the Ventage Jet installation. No aircraft-specific pickup, fuel transit, slosh, nozzle flux or tank fill map was available for this reference.

## Integration recommendation and remaining unknowns

Use a fixed dry-structure datum for the optional variable-mass route. It keeps hull placement and dry-body geometry continuous, and the reference provides a single six-by-six spatial inertia solve per stage. Recompute stage-local (m,\mathbf h,\mathbf J_O) from a validated fill-distribution model; express gravity, aerodynamic, gear/contact and net thrust wrenches about the same datum. Convert to current-CG position/telemetry only at a documented boundary. Preserve the current constant-mass path until the variable route passes the plan's integration, replay and refinement gates.

The current constant-mass rigid-body derivative accepts one mass and CG inertia and integrates position/velocity on its established CG reference. It cannot become a variable-CG solver by changing only those two values each tick. A moving-CG route is mathematically possible, but it must state whether the stored velocity is momentum velocity (\mathbf P/m) or geometric position derivative and use the exact transform above throughout force evaluation, interpolation, contact and rendering.

Before AV-10c, resolve: the authored tank geometry and fill-dependent centroid/tensor; actual pickup and unusable volume; pump/hopper/line fuel inventory; whether the delivery rate can be treated as aircraft-boundary mass loss at the tank; installed net-thrust control-volume conventions; and measured slosh/settling behavior under representative acceleration. Without those, the conservation law is determined but the aircraft-specific mass-property schedule is not.
