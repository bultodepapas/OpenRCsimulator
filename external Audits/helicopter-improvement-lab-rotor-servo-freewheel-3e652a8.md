I continued the work by building and running **four reproducible helicopter experiments**. The strongest additional result is that the low-RPM transition problem extends beyond rejected states: **the rotor evaluator can return `ok=true` while producing an extremely large flap-rate derivative near its mathematical boundary.**

I also built an independently checked servo-response model, an event-aware freewheel/drivetrain experiment, and a benchmark against published NASA rotor measurements.

**The complete package is here:**

[OpenRC_Helicopter_Improvement_Lab_2026-11-06.zip](https://chatgpt.com/library?file_id=libfile_6befa7ef61248191b95d7e697600919b&account_id=personal)

It contains the runnable Python and GDScript experiments, input data, plots, numerical results, verification records, and implementation notes.

I cross-checked this work against the [consolidated audit ledger](https://github.com/bultodepapas/OpenRCsimulator/blob/d0b672b09663226ff8b8ac4f43eae8643c77a8c4/external%20Audits/CONSOLIDATED-AUDITS.md). The executable baseline is `3e652a8`; the [GitHub comparison through `d0b672b`](https://github.com/bultodepapas/OpenRCsimulator/compare/3e652a879ab8e928fc7d0b23d8303ac5724c3be6...d0b672b09663226ff8b8ac4f43eae8643c77a8c4) confirms that the relevant helicopter physics and configuration files remained unchanged. The low-RPM work strengthens the earlier **H02** finding. The actuator and freewheel work develops already-recognized model boundaries into tested implementation candidates.

These are **component experiments and research prototypes**. Production flight behavior and the HX-700’s qualification status remain unchanged.

## 1. The low-RPM blend can admit an enormous flap derivative

**Relevant code:** [`main_rotor.gd`, transition and normal-law evaluation](https://github.com/bultodepapas/OpenRCsimulator/blob/d0b672b09663226ff8b8ac4f43eae8643c77a8c4/app/physics/rotorcraft/main_rotor.gd#L125-L185), and [`low_rpm_transition`](https://github.com/bultodepapas/OpenRCsimulator/blob/d0b672b09663226ff8b8ac4f43eae8643c77a8c4/app/physics/rotorcraft/main_rotor.gd#L216-L224).

The current model transitions from an estimated startup law into the normal mean-rotor law using:

\[
\Omega_{\mathrm{hi}}
=
\min\!\left(
0.20\Omega_n,\,
\max\!\left(0.08\Omega_n,\frac{U}{0.15R}\right)
\right),
\qquad
\Omega_{\mathrm{lo}}=\frac{\Omega_{\mathrm{hi}}}{2}.
\]

Here:

- \(U\) is the rotor-plane component of **hub air-relative velocity**.
- \(R\) is rotor radius.
- \(\Omega_n\) is nominal rotor speed.
- \(\Omega\) is current rotor speed.

Above the lower transition endpoint, the evaluator starts calling the normal law. That law requires:

\[
\mu^2<2,
\qquad
\mu=\frac{U}{\Omega R}.
\]

Once the transition cap is active, a disconnected refusal interval exists whenever:

\[
U>\sqrt{2}\,(0.1\Omega_n)R.
\]

The interval is, in ideal arithmetic,

\[
\boxed{
0.1\Omega_n<\Omega\leq\frac{U}{\sqrt{2}R}
}
\]

The new scan confirms the following boundaries for both implemented configurations:

| Derived quantity | X-Cell | HX-700 laboratory configuration |
|---|---:|---:|
| Crossflow where the 20% transition cap begins | 3.882750 m/s | 4.618141 m/s |
| Crossflow above which the refusal interval exists | **18.303459 m/s** | **21.770126 m/s** |
| Crossflow corresponding to \(\mu=0.15\) at nominal RPM | 19.413750 m/s | 23.090706 m/s |

These are limits of the current mathematical implementation. They are not validated aircraft speed limits.

### The additional problem is on the accepted side

The longitudinal flapping equation contains a term proportional to:

\[
\frac{\mu^2\mu_z\,\operatorname{sign}(\mu_x)}
     {(1-\mu^2/2)(8\mu+a\sigma)}.
\]

For the probe’s nonzero longitudinal crossflow, axial flow, and flapback coefficient, the denominator approaches zero as \(\mu^2\to2^{-}\).

If that pole lies inside the blend band, the normal-law blend weight is already positive there. Multiplying by the smooth blend therefore **does not remove the singularity**.

I called the actual GDScript evaluator with fixed diagnostic inputs: collective \(0.1\) rad, induced velocity \(4\) m/s, axial hub air velocity \(+1\) m/s, and zero body rates, cyclic, and flap angles.

| Configuration | Rotor-plane airspeed | Rotor speed just above the pole | Returned longitudinal flap rate |
|---|---:|---:|---:|
| X-Cell | 20 m/s | 18.247935 rad/s | **431.280315 rad/s** |
| HX-700 laboratory | 25 m/s | 25.253839 rad/s | **3692.061616 rad/s** |

Both calls return `ok=true`, with the blended-startup label and an advance-ratio flag outside the identified range. The complete inputs and neighboring samples are retained in the package.

For scale, the X-Cell derivative multiplied by one \(1/240\)-second timestep is approximately **1.8 radians**. That is a local derivative estimate, not the result of an accepted RK4 flight step.







The scan executed **58,322 actual rotor evaluations**. Its independently written domain inequalities matched the evaluator’s acceptance and advance-ratio flags across the grid. The pole-neighborhood samples are additional recorded observations.

### What should change

The immediate improvement is an explicit domain diagnostic carrying the actual hub airspeed, head speed, transition endpoints, and applicable model limits. That would make a refused transaction explainable and give regression tests a precise contract.

The aerodynamic correction needs a supported overlap between the participating models. A small blend weight cannot make an unsupported or singular submodel suitable for evaluation.

A stronger low-speed model should explicitly address:

- Large crossflow and reverse-flow blade sections.
- Reynolds-number dependence.
- Slowly rotating or stopped blades.
- Correctly signed rotor torque and energy exchange.

This matters for gusting startup, moving coastdown, and future power-off flight. The experiment establishes the mathematical problem; the earlier H02 session reproduction remains the evidence that a startup refusal is reachable in a complete session.

## 2. Achieved servo motion needs its own state

**Relevant code:** [`electronics.gd`](https://github.com/bultodepapas/OpenRCsimulator/blob/d0b672b09663226ff8b8ac4f43eae8643c77a8c4/app/physics/rotorcraft/electronics.gd), especially the mixed-command clamp followed by `linkage_output`; and [`swash.gd`](https://github.com/bultodepapas/OpenRCsimulator/blob/d0b672b09663226ff8b8ac4f43eae8643c77a8c4/app/physics/rotorcraft/swash.gd), including `mix_120`, `unmix_120`, and `step_servos`.

The flight electronics currently passes the clipped mixed servo commands directly into the linkage calculation. The separate servo helper implements a documented discrete operation: apply a first-order lag step, then cap the resulting displacement.

I implemented and checked a specific continuous alternative:

\[
\dot x
=
\operatorname{clip}
\left(
\frac{u-x}{\tau},
-r,r
\right),
\qquad
u=\operatorname{clamp}(u_{\rm command},x_{\min},x_{\max}).
\]

Here \(x\) is achieved normalized swash rise, \(r\) is its rate limit, and \(\tau\) is the lag time constant.

### The exact held-command solution

For a command held constant over an interval, define:

\[
d=|u-x|,
\qquad
d_*=r\tau.
\]

If \(d\leq d_*\), the actuator follows the exponential response immediately. Otherwise it moves at the rate limit until:

\[
t_s=\frac{d-d_*}{r},
\]

then follows the exponential response.

The core calculation is small:

```python
# Assumes validated positive rate/tau and an already clamped target.
def held_servo_step(x, target, dt, rate, tau):
    error = target - x
    distance = abs(error)
    knee = rate * tau

    if distance <= knee:
        remaining = distance * math.exp(-dt / tau)
    else:
        switch_time = (distance - knee) / rate
        if dt <= switch_time:
            remaining = distance - rate * dt
        else:
            remaining = knee * math.exp(-(dt - switch_time) / tau)

    return target - math.copysign(remaining, error)
```

The complete implementation in the package also validates inputs and defines zero-rate, zero-lag, and travel-limit behavior.

An independent SciPy DOP853 integration of the differential equation agreed with this solution to a maximum of:

\[
\boxed{9.1821\times10^{-13}}
\]

normalized position units across **720 comparisons** on the specified three-servo command sequence.

### What the comparison actually shows

For a deliberately coarse, held \(0.5\)-second command, with synthetic \(r=2\,\mathrm{s}^{-1}\), \(\tau=0.2\) s, targets \([1,0.8,0.2]\), and zero initial position:

| Calculation | Front servo | Rear-right servo | Rear-left servo |
|---|---:|---:|---:|
| Exact continuous law | 0.852848 | 0.710748 | 0.183583 |
| Existing helper, one 0.5 s call | 0.917915 | 0.734332 | 0.183583 |
| Existing helper, 120 calls at 240 Hz | 0.852848 | 0.710748 | 0.183583 |

This distinguishes two update semantics. It is not a new production defect: the existing helper documents its operation, and the flight path does not currently use it.

On the separate changing-command sequence at 240 Hz, the differences between the helper and continuous candidate map to only a few millionths of a radian of blade pitch. The larger modeling decision is whether aerodynamic loads respond to instantaneous commands or to achieved actuator positions.

### Why filtering collective and cyclic separately is insufficient

There is a useful algebraic result here.

For the existing 120-degree swash, let the commanded axes be:

\[
q=
\begin{bmatrix}
q_{\rm collective}\\
q_{\rm longitudinal}\\
q_{\rm lateral}
\end{bmatrix},
\]

with mixing matrix:

\[
B=
\begin{bmatrix}
1&1&0\\
1&-\frac12&\frac{\sqrt3}{2}\\
1&-\frac12&-\frac{\sqrt3}{2}
\end{bmatrix}.
\]

In an unsaturated small-signal model, let the individual servo responses be \(G_1(s),G_2(s),G_3(s)\). The achieved-axis response is then:

\[
\boxed{
H(s)=B^{-1}
\operatorname{diag}(G_1,G_2,G_3)
B
}
\]

When the three servo responses are equal, this reduces to a common scalar response on all axes. When they differ, off-diagonal terms generally appear.

**Unequal servo dynamics can therefore create collective/cyclic coupling before rotor aerodynamics enters the calculation.** Rate and travel saturation add further nonlinear coupling.

The direct-controller probe illustrates this using deliberately asymmetric synthetic servos: positive lateral command initially produces a very small negative achieved lateral pitch mapping. That is a consequence of unequal swash motion in this constructed setup; it does not establish a real helicopter’s roll response.

### How to integrate this correctly

I would add named float64 states for the three achieved swash positions, then derive blade pitch and visual motion from those states. Commanded and achieved values should remain distinct in telemetry.

The timing decision is essential. The current controller evaluates feedback at RK stages. The exact formula above assumes a held target. There are two coherent approaches:

1. Keep continuously evaluated controller feedback and integrate the actuator differential equation consistently at each RK stage.
2. Define a sampled controller with an explicit command hold, then evaluate the closed-form actuator state at the required stage times.

Either approach needs initialization, reset, rejected-step rollback, checkpoint, and native/reference behavior defined together. Hidden mutable actuator updates inside a stage callback would break that contract.

The synthetic rates and time constants are test inputs, not proposed aircraft defaults. Hardware measurements under appropriate voltage and load are needed before calibration.

## 3. A freewheel cannot be controlled by throttle state alone

**Relevant code:** [`drive.gd`](https://github.com/bultodepapas/OpenRCsimulator/blob/d0b672b09663226ff8b8ac4f43eae8643c77a8c4/app/physics/rotorcraft/drive.gd), which explicitly describes the current one-speed proxy; and [`geared_coupling.gd`](https://github.com/bultodepapas/OpenRCsimulator/blob/d0b672b09663226ff8b8ac4f43eae8643c77a8c4/app/physics/rotorcraft/geared_coupling.gd), which handles reflected inertia and body momentum coupling.

I built a small two-inertia, event-aware freewheel experiment with an independently specified rational solution.

Let:

\[
x=\frac{\omega_m}{n},
\qquad
y=\Omega,
\qquad
J_s=n^2J_m,
\]

where \(x\) is motor speed referred to the rotor side and \(y\) is rotor speed.

For an ideal one-way clutch:

\[
g=y-x\geq0,
\qquad
\lambda\geq0,
\qquad
\lambda g=0.
\]

Define \(Q_s=nQ_m\) as applied source torque. Let \(Q_r\) be signed torque applied to the rotor: negative resists rotation, positive supplies shaft energy.

Then:

\[
J_s\dot x=Q_s-\lambda,
\qquad
J_r\dot y=Q_r+\lambda.
\]

In the locked state:

\[
\boxed{
\lambda_{\rm locked}
=
\frac{J_rQ_s-J_sQ_r}{J_s+J_r}
}
\]

The clutch releases when maintaining equal speed would require negative clutch torque. Project Chrono’s asymmetric shaft-clutch interface provides a useful external reference for this one-direction torque concept. Chrono itself was not incorporated into this experiment. [api.projectchrono.org](https://api.projectchrono.org/10.0.0/classchrono_1_1_ch_shafts_clutch.html?utm_source=chatgpt.com)

### A concrete counterexample

Use synthetic inertias:

\[
J_s=1,\qquad J_r=4\ \mathrm{kg\,m^2},
\]

with both speeds initially \(1.6\) rad/s, zero motor torque, and resisting rotor torque:

\[
Q_s=0,\qquad Q_r=-2\ \mathrm{N\,m}.
\]

The required clutch torque is:

\[
\lambda_{\rm locked}
=
\frac{4(0)-1(-2)}{5}
=
+0.4\ \mathrm{N\,m}.
\]

The clutch therefore remains engaged in this ideal model. The motor-side inertia continues supplying torque while the coupled system slows.

After one second:

| Rule | Source-referred speed | Rotor speed | One-way gap |
|---|---:|---:|---:|
| Mechanical constraint | 1.2 rad/s | 1.2 rad/s | 0 |
| Force open whenever motor torque is zero | 1.6 rad/s | 1.1 rad/s | **−0.5 rad/s** |

The second result violates the one-way constraint.

A subtle point is that the naive open trajectory can still satisfy its own external-work balance. **Energy accounting alone would not detect that it represents the wrong clutch mechanics.**

### What passed

The complete synthetic program includes spin-up, locked coastdown, release, motor catch-up, equal-speed engagement, stopping, and a specifically defined resting case.

| Event | Analytical time |
|---|---:|
| Release | 2 s |
| Equal-speed engagement | \(28/9\) s |
| Stop | 7 s |

All **76 checks passed** across outer timesteps of:

\[
1/240,\quad1/239,\quad1/480,\quad0.113,\quad0.37\ \mathrm{s}.
\]

At 240 Hz, the maximum checked residuals were approximately:

- Energy: \(1.25\times10^{-13}\) J.
- Generalized momentum: \(2.67\times10^{-13}\) N·m·s.
- Shaft speed versus the rational reference: \(1.82\times10^{-14}\) rad/s.

These results validate the specified mathematical experiment. Its fixed gear carrier, prescribed torques, and synthetic inertias keep it separate from a full helicopter model.

### What this means for OpenRC

A realistic implementation needs a declared motor/freewheel/main-rotor/tail-rotor topology. The tail’s mechanical drive arrangement determines what authority remains during power-off flight.

The coupled implementation should then:

- Carry separate motor and rotor speed states.
- Preserve each shaft group’s reflected inertia and signed body momentum coupling.
- Locate release and engagement events inside the accepted-tick transaction.
- Include clutch reactions exactly once.
- Define stopped-speed and invalid-initial-state policies.
- Preserve reset, rollback, checkpoint, and native/reference agreement.

Autorotation also requires correctly signed aerodynamic shaft power. The freewheel provides the mechanical connection law; the rotor model must supply the corresponding aerodynamic energy exchange.

## 4. The rotor model now has a reproducible external-data benchmark

I extracted a narrow dataset from Harris’s NASA report: Knight and Hefner’s untwisted NACA 0015 rotor, with 60-inch diameter and 2-inch chord, tested at a tip speed of 251.3 ft/s, Reynolds number 267,825, and Mach 0.22511. The source table and geometry were inspected, and the downloaded PDF is hash-pinned. [ntrs.nasa.gov](https://ntrs.nasa.gov/api/citations/20205001147/downloads/Harris%20CR-20205001147_Final_7_1_2020.pdf?utm_source=chatgpt.com)

The benchmark keeps two questions separate:

1. Can a simple model predict **power from measured thrust**?
2. Can the existing rotor reference, with explicitly stated wake assumptions, predict **thrust from blade pitch**?

That distinction prevents a good power fit from being mistaken for validation of the complete rotor model.

### Power conditional on measured thrust

Using conventional rotor coefficients:

\[
C_T=\frac{T}{\rho A(\Omega R)^2},
\qquad
C_P=\frac{P}{\rho A(\Omega R)^3},
\]

I fitted:

\[
C_P
=
\frac{\sigma C_{D0,\mathrm{eff}}}{8}
+
K_{\mathrm{eff}}\frac{C_T^{3/2}}{\sqrt2}.
\]

The fitting set contains five two-blade points at 2°, 4°, 6°, 8°, and 10°. The three-blade points at the same pitches form a separate configuration holdout from the same historic experiment.

The fitted parameters are:

\[
C_{D0,\mathrm{eff}}=0.00940631,
\qquad
K_{\mathrm{eff}}=1.509075.
\]

| Comparison | Dimensionless \(C_P\) RMSE |
|---|---:|
| Two-blade fitting points | \(1.9702\times10^{-6}\) |
| Withheld three-blade points | \(1.0575\times10^{-5}\) |

The holdout errors are:

| Collective | Relative power-coefficient error |
|---|---:|
| 2° | −15.40% |
| 4° | −9.18% |
| 6° | −3.84% |
| 8° | −1.58% |
| 10° | +0.20% |

This is useful disagreement. It gives future model changes a test they can fail.

The holdout remains from the same experimental family, and its highest-thrust point also exceeds the fitting set’s maximum \(C_T\). Low-torque measurement limitations further constrain interpretation.

The fitted coefficients are **effective regression parameters**. They can absorb multiple loss mechanisms and measurement effects; they should not replace the X-Cell or HX-700 aircraft coefficients.

### A separate pitch-to-thrust calculation

The second comparison calls OpenRC’s existing [`research/helicopter/reference/main_rotor.py`](https://github.com/bultodepapas/OpenRCsimulator/blob/d0b672b09663226ff8b8ac4f43eae8643c77a8c4/research/helicopter/reference/main_rotor.py) using the source rotor geometry, an assumed lift slope, and the explicit ideal-hover closure:

\[
\lambda_i=\sqrt{\frac{C_T}{2}}.
\]

It does not use measured thrust as an input.

| Static reference comparison | Dimensionless \(C_T\) RMSE |
|---|---:|
| Two blades | \(3.3915\times10^{-5}\) |
| Three-blade mathematical extension | \(1.2066\times10^{-4}\) |

The three-blade calculation is labeled as a **Python-reference-only extension**: production `main_rotor.gd::prepare` admits two blades. This comparison also uses an imposed static wake, rather than exercising the session’s dynamic-inflow model.



benchmark.pngPNG



### A sensitivity result that helps prioritize work

The NASA document lists root cutout as \(0.167R\) in its geometry table and \(0.150R\) in Appendix A. I preserved that discrepancy rather than choosing one silently. [ntrs.nasa.gov](https://ntrs.nasa.gov/api/citations/20205001147/downloads/Harris%20CR-20205001147_Final_7_1_2020.pdf?utm_source=chatgpt.com)

For the restricted constant-chord, constant-section-drag profile-power term:

\[
C_{P0}
=
\frac{\sigma C_{D0}}8
\left[
1-\left(\frac{r_c}{R}\right)^4
\right].
\]

Changing the cutout from \(0.150R\) to \(0.167R\) changes that term by only **0.02717%**. The fourth-power dependence follows from the radial profile-power integral. [ntrs.nasa.gov](https://ntrs.nasa.gov/api/citations/20205001147/downloads/Harris%20CR-20205001147_Final_7_1_2020.pdf?utm_source=chatgpt.com)

That calculation does not quantify the associated thrust or wake change. It does show that this particular profile-power correction cannot explain a 15% conditional power discrepancy. This is the kind of sensitivity analysis that helps avoid spending development effort on the wrong parameter.

## How I would advance the implementation

The experiments support four separable increments:

| Priority | Concrete increment | Evidence required before accepting it |
|---|---|---|
| **1** | Rotor-domain diagnostics and boundary regressions | Clear classification around the refusal interval and pole; preserved valid baseline replay |
| **2** | Achieved actuator states with a defined control clock | Independent actuator reference, combined-axis behavior, reset/checkpoint/rollback, native/reference agreement |
| **3** | Separate motor speed and event-aware freewheel mechanics | Complementarity plus energy checks, full-body momentum accounting, tail-drive behavior, restart and stop cases |
| **4** | Supported low-speed and signed rotor-load models | External source curves, withheld conditions, continuity and energy checks, appropriate power-off flight traces |

There are also concrete efficiency opportunities in these designs. A held-command servo response can use a fixed amount of work instead of a finely stepped inner solver. Constant-torque shaft segments admit analytic event times. For a coupled flight implementation, those shortcuts need to remain consistent with the chosen control clock and state-dependent loads; this work does not establish an end-to-end frame-time improvement.

**Verification is complete for this package:** I independently reran all four experiments, reran the six external-benchmark tests, inspected the checked Godot results, and compared the retained numerical outputs. They reproduced in the recorded environment, and the production checkout remained clean.

The next changes now have mathematical specifications, discriminating test cases, and external comparison data. That gives us a firmer basis for improving helicopter behavior than tuning gains around an uncertain actuator, rotor, or drivetrain model.