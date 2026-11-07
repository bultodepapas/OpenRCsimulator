I continued into **executable experiments against OpenRC’s actual wind, station-flow, aerodynamic, and rigid-body code** at commit [`347905ca`](https://github.com/bultodepapas/OpenRCsimulator/commit/347905cafed505cad758107f2790fab2b018e4c6).

The most consequential result concerns **how to analyze and optimize the wind response**: at a symmetric aircraft state, a matrix of converged, centered station derivatives can still give the wrong response to a combined gust. I reproduced that behavior, traced it to the existing maximum-station-speed calculation, and measured its effect on a controlled gust ensemble.

**This pass establishes no additional serious production defect.** It adds wind-specific evidence to an already documented modeling observation, corrects an assumption in the previous analytical proposal, and supplies reproducible tests for gust arrival, coordinate transformations, clocks, and energy accounting. Production files remain unchanged.

## Deliverables

- OpenRC_Wind_Production_Experiments_347905c.txt[OpenRC_Wind_Production_Experiments_347905c.txt](sandbox:/workspace/scratch/d136c947101b/deliverables/OpenRC_Wind_Production_Experiments_347905c.txt) — complete report, equations, source locations, priorities, and verification boundaries.
- OpenRC_Wind_Production_Lab_347905c.zip[OpenRC_Wind_Production_Lab_347905c.zip](sandbox:/workspace/scratch/d136c947101b/deliverables/OpenRC_Wind_Production_Lab_347905c.zip) — custom probes, raw results, checked execution logs, source hashes, reproduction instructions, and independent critical review.
- OpenRC_Wind_Production_Results_347905c.png[OpenRC_Wind_Production_Results_347905c.png](sandbox:/workspace/scratch/d136c947101b/deliverables/OpenRC_Wind_Production_Results_347905c.png) — figure generated from the measured component outputs.

I checked the current consolidated and completed audit records before investigating. The earlier wind findings now belong to **A22**. The latest wind-preset/atmosphere scope repair is recorded as completed under **A11 R01**. The maximum-speed cusp discussed below already belongs to **A10**, so I have kept that attribution rather than counting it again. [Pending ledger](https://github.com/bultodepapas/OpenRCsimulator/blob/347905cafed505cad758107f2790fab2b018e4c6/external%20Audits/CONSOLIDATED-AUDITS.md) · [Completed work](https://github.com/bultodepapas/OpenRCsimulator/blob/347905cafed505cad758107f2790fab2b018e4c6/external%20Audits/COMPLETED-AUDIT-WORK.md)

---

## 1. A symmetric gust exposes a limitation of centered linearization

**Classification:** new wind-specific evidence extending A10.  
**Priority:** correct the analysis method before using it for turbulence-response prediction or optimization.

### The relevant calculation

In [`app/physics/aero.gd:297–370`](https://github.com/bultodepapas/OpenRCsimulator/blob/347905cafed505cad758107f2790fab2b018e4c6/app/physics/aero.gd#L297-L370), `_wing_flow()` calculates a reference speed from the maximum **three-dimensional** relative speed across the wing stations:

\[
U_{\max}=\max_i\|\mathbf u_i\|.
\]

The attached-flow source weight contains the ratio

\[
s_i=\frac{V_{p,i}}{U_{\max}},
\]

where \(V_{p,i}\) is the station’s section-plane speed. The off-diagonal induced-map calculation then uses those weights. [Induced-map consumption](https://github.com/bultodepapas/OpenRCsimulator/blob/347905cafed505cad758107f2790fab2b018e4c6/app/physics/aero.gd#L490-L507)

A maximum is continuous, but its derivative can change when two stations exchange which one is fastest. A10 already demonstrated this mechanism for a roll-rate perturbation. The new experiments show what it does to **spatial-wind sensitivities and statistical load predictions**. [Original A10 observation](https://github.com/bultodepapas/OpenRCsimulator/blob/347905cafed505cad758107f2790fab2b018e4c6/external%20Audits/extra-300-round2-trim-reload-audit-8e5f2f0.md#L210-L231)

### The wind-specific reproduction

I used the production-normalized stock Ugly Stik model in a constructed component state:

- Datum airspeed: **20 m/s**.
- Datum angle of attack: **3°**.
- Neutral controls and zero angular rates.
- Identity attitude, at 100 m altitude.
- Density: **1.225 kg/m³**.
- A fixed reference wake for the compared load evaluations.

This is a fixed-state evaluation; it is not claimed to be trimmed flight.

All six wing stations have exactly the same initial three-dimensional speed. Their spanwise coordinates are

\[
y_i=[-0.635,-0.381,-0.127,0.127,0.381,0.635]\ \mathrm m.
\]

Through the real `wind_world()` provider interface, the probe supplies

\[
W_N=W_E=0,\qquad
W_D(y)=a\sin(1.08827961854\,y).
\]

Here \(W_D>0\) means air moving downward. The actual spanwise wavelength is **5.7735 m**.

Reversing \(a\) swaps the fastest station between the two outer wing stations. The measured one-sided derivatives of the body-down force are:

| Gust parameter \(h\), m/s | Positive-side derivative, N/(m/s) | Negative-side derivative, N/(m/s) |
|---:|---:|---:|
| 0.05 | +0.016377051 | −0.016377051 |
| 0.025 | +0.016635654 | −0.016635654 |
| 0.0125 | +0.016764950 | −0.016764950 |
| 0.00625 | +0.016829597 | −0.016829597 |
| 0.00001 | +0.016894139 | −0.016894139 |
| 0.000001 | +0.016894234 | −0.016894234 |

The local response therefore contains approximately

\[
F_z(a)-F_z(0)
=
0.0168942\,|a|+O(a^2)\quad\mathrm N.
\]

A centered derivative,

\[
\frac{F_z(h)-F_z(-h)}{2h},
\]

returns approximately zero for that term. Reducing \(h\) does not recover the missing \(|a|\) response.

This is a **continuous force with a corner in its derivative**. It is distinct from the finite rotor-load jumps quantified in the earlier wind audit.

### Controls that distinguish the mechanism

Two controls were particularly useful.

First, a disposable in-memory model clone removed the off-diagonal induced-map entries while retaining the same stock held wake. The first-order even term disappeared. This supports the known normalization/coupling mechanism, but the altered model is a diagnostic, not a proposed aerodynamic fix.

Second, setting body roll rate to \(p=0.25\ \mathrm{rad/s}\) created a unique fastest station. The initial gap between the fastest and second-fastest three-dimensional speeds was

\[
\Delta U=0.003725239\ \mathrm{m/s}.
\]

At that state, both one-sided force derivatives converge to approximately

\[
-0.0119080\ \frac{\mathrm N}{\mathrm{m/s}},
\]

and the smooth-response checks passed. The minimum speed gap **among the sampled signed perturbations** was \(0.002970327\ \mathrm{m/s}\).

### A more subtle consequence: individually converged columns can still be wrong together

For the even field

\[
W_D(y)=a\cos(2.72069904635\,y),
\]

I compared two calculations:

1. Perturb the complete spatial pattern and measure its centered response.
2. Perturb datum and station inputs individually, assemble centered derivative columns, and combine them.

At the tied-speed state:

| Calculation | \(dF_z/da\), N/(m/s) |
|---|---:|
| Direct pattern, \(|a|=0.0001\) m/s | 15.50054419 |
| Direct pattern, \(|a|=0.00005\) m/s | 15.50054483 |
| Combined centered datum/station columns | 15.52966327 |

The discrepancy is approximately **0.188%** of the direct slope. Meanwhile, halving the individual derivative step changes the largest force-column derivative by only \(4.44\times10^{-8}\ \mathrm{N/(m/s)}\).

That is the important numerical lesson: **convergence of coordinate-wise centered differences does not prove that the resulting matrix is a derivative of the complete map.**

This directly corrects the smooth-Jacobian assumption in my earlier proposal for predicting load covariance from station wind covariance.

### Concrete improvement

The analysis tool should distinguish a smooth local state from a tied maximum before choosing its sensitivity representation.

For a requested gust pattern, evaluate both one-sided responses while keeping state, controls, density, time, model, and wake consistent:

```python
Fp = evaluate_pattern(+h)
Fm = evaluate_pattern(-h)

D_plus  = (Fp - F0) / h
D_minus = (F0 - Fm) / h

d = 0.5 * (D_plus + D_minus)
c = 0.5 * (D_plus - D_minus)
```

Then the local directional approximation is

\[
\mathbf F(a)\approx\mathbf F_0+\mathbf d\,a+\mathbf c\,|a|.
\]

There is also a useful conservative guard. If every station’s full body-relative velocity changes by at most \(\epsilon\), the reverse triangle inequality gives

\[
\text{new winning-speed gap}\geq\Delta U-2\epsilon.
\]

Thus

\[
\Delta U>2\epsilon
\]

with an appropriate floating-point margin is sufficient to keep the same station fastest. With unequal bounds \(b_i\), use

\[
U_w-b_w>\max_{j\ne w}(U_j+b_j).
\]

This guards the maximum selector only. Zero speed, stall/polar joins, wrapping, and other branches still need their own checks.

For a few requested gust patterns, direct directional evaluation is also economical: one vertical pattern requires two signed evaluations at one amplitude, while building all nine vertical datum/station columns requires eighteen. This is an **offline evaluation-count opportunity**, not a measured simulator speedup.

---

## 2. A controlled gust ensemble confirms the missing mean and variance terms

**Classification:** new measured consequence of the existing A10 mechanism.

A zero-mean gust does not generally imply zero mean aerodynamic-force change. Ordinary quadratic aerodynamics can already produce a mean shift. What distinguishes this case is the **first-order amplitude scaling** associated with the \(|a|\) term.

I ran **768 actual stage/load evaluations**: 256 equally spaced phases for each of three amplitudes, using

\[
W_D(y,\phi)
=
A\sin\phi\,\sin(1.08827961854\,y).
\]

The aircraft state and held wake were unchanged.

| \(A\), m/s | Actual mean \(\Delta F_z\), N | Actual \(\operatorname{Var}(F_z)\), N² | Leading piecewise variance, N² |
|---:|---:|---:|---:|
| 0.05 | 0.000524803764 | \(6.3059505\times10^{-8}\) | \(6.7611201\times10^{-8}\) |
| 0.025 | 0.000265634378 | \(1.6328733\times10^{-8}\) | \(1.6902800\times10^{-8}\) |
| 0.0125 | 0.000133625285 | \(4.1536420\times10^{-9}\) | \(4.2257001\times10^{-9}\) |

For continuously uniform phase and

\[
\mathbf F(a)=\mathbf F_0+\mathbf d a+\mathbf c|a|+O(a^2),
\]

the leading moments are

\[
\mathbb E[\mathbf F]-\mathbf F_0
=
\frac{2}{\pi}\mathbf c A+O(A^2),
\]

and

\[
\operatorname{Cov}(\mathbf F)
=
A^2\left[
\frac12\mathbf d\mathbf d^\mathsf T+
\left(\frac12-\frac{4}{\pi^2}\right)
\mathbf c\mathbf c^\mathsf T
\right]
+O(A^3).
\]

The numerical predictions used the actual finite phase-grid moments, including

\[
\frac1{256}\sum_j|\sin\phi_j|
=
0.6365878141,
\]

rather than substituting \(2/\pi\) silently.

For \(F_z\), the predicted limiting ratio is

\[
\frac{\mathbb E[\Delta F_z]}{A}
\longrightarrow
0.0107546031\ \frac{\mathrm N}{\mathrm{m/s}}.
\]

The observed ratios approach it:

\[
0.0104960753,\quad
0.0106253751,\quad
0.0106900228.
\]

The piecewise approximation remains approximate at finite amplitude. At \(A=0.05\ \mathrm{m/s}\), its predicted mean is \(0.000537730\ \mathrm N\), about **2.46% above** the measured \(0.000524804\ \mathrm N\).

### How much does this matter physically?

The largest mean change is only **0.00132% of the magnitude of the baseline \(F_z\)** in this fixture.

Also, \(F_z\) is positive downward. The positive increment moves the initially negative body-z force toward zero; it does not mean added upward lift. No pilot-visible effect was demonstrated.

The practical significance is for **derivative-based analysis, fitting, and optimization**, where a very small but systematically omitted term can invalidate the mathematical model being fitted.

There is another essential boundary: this is a manufactured **standing spatial pattern**. A traveling mode,

\[
A\sin(ky+\phi)
=
A\sin(ky)\cos\phi+
A\cos(ky)\sin\phi,
\]

also changes the datum wind and carries correlated odd/even components. The measured statistics above cannot be assigned to a production traveling mode without preserving those components and correlations.



OpenRC_Wind_Production_Results_347905c.pngPNG



---

## 3. The actual aircraft response differs from the ideal wing-filter calculation

The earlier analytical work used ideal spatial averaging as a reference. This pass measured the implemented aerodynamic component directly.

At the same 20 m/s, 3° fixture, direct centered perturbations of \(\pm0.00005\ \mathrm{m/s}\) produced:

| Actual spanwise wavelength, m | Cosine \(dF_z/da\), N/(m/s) | Cosine \(dM_y/da\), N·m/(m/s) | Sine \(dM_x/da\), N·m/(m/s) | Sine \(dM_z/da\), N·m/(m/s) |
|---:|---:|---:|---:|---:|
| 2.3094 | +15.50054 | +2.28744 | +5.76438 | +0.78998 |
| 5.7735 | +25.72537 | +2.11303 | +3.26153 | +0.44924 |
| 11.5470 | +27.49096 | +2.08294 | +1.70863 | +0.23548 |

These evaluations include the datum air data, six wing strips, both tails, matched baseline/correction, and the held wake.

The uniform vertical-wind sensitivity is approximately

\[
\frac{dF_z}{dW_D}=28.09803\ \frac{\mathrm N}{\mathrm{m/s}}.
\]

The three cosine-response ratios relative to that uniform response are approximately

\[
0.55165,\qquad0.91556,\qquad0.97840.
\]

These are useful **identified software-response baselines**. They are not bare sinc-filter coefficients or percentages of discretization error. OpenRC’s actual model contains induced coupling, tail contributions, and the matched global/local continuation. [Spatial continuation implementation](https://github.com/bultodepapas/OpenRCsimulator/blob/347905cafed505cad758107f2790fab2b018e4c6/app/physics/aero.gd#L1073-L1189)

**Concrete use:** retain these observables when changing station resolution or wind sampling. A candidate can then be checked for changes in vertical force, pitch, roll, and yaw separately. Physical validation still needs an independent target; agreement with the existing code is a regression result.

---

## 4. Coordinate transformations, epoch handling, and station arrival passed focused checks

**Classification:** positive verification within the tested cases; no new defect established.

The production station-flow construction uses the expected relationship

\[
\mathbf u_i
=
R^\mathsf T(\mathbf v_g-\mathbf W_i)
+
\boldsymbol\omega\times\mathbf r_i.
\]

Equivalently, relative to datum air velocity, the station correction is

\[
\Delta\mathbf u_i
=
R^\mathsf T(\mathbf W_{\mathrm{datum}}-\mathbf W_i).
\]

The probe independently reconstructed station arms and a quaternion rotation matrix before comparing against actual `WindAircraftFlow` outputs. [Station sampling and transformations](https://github.com/bultodepapas/OpenRCsimulator/blob/347905cafed505cad758107f2790fab2b018e4c6/app/physics/wind_aircraft_flow.gd#L264-L355)

### Production composite field

A nonzero field combined an independently directed upper wind, a shear layer, active/inactive gust times, and an advected thermal.

Twelve point/time comparisons tested:

- Horizontal translation of the relevant positions and thermal center.
- A **73° yaw rotation** of physical vectors and positions.
- A consistent simulation-time/epoch-offset rebase in both spatial and thermal identities.

Maximum wind-component differences were:

| Transformation | Maximum difference |
|---|---:|
| Horizontal translation | 0 m/s |
| Yaw rotation | \(8.89\times10^{-16}\) m/s |
| Consistent epoch rebase | 0 m/s |

At a separately transformed aircraft stage, station-delta components agreed within \(2\times10^{-10}\ \mathrm{m/s}\), force components within \(10^{-8}\ \mathrm N\), and moment components within \(10^{-8}\ \mathrm{N\,m}\).

The rotation experiment disabled stochastic modes. It therefore makes no claim that rotating the mean wind also rotates a fixed seed’s prepared modal geometry. Changed configuration hashes also remain distinct: matching sampled values does not mean matching checkpoint identity.

### Actual seeded modal phase

A separate test retained **24 real prepared modes**, nonzero turbulence, and a nonzero epoch offset.

The implementation uses

\[
\phi=\mathbf k_h\cdot\mathbf x_h+
\left(\omega_{\mathrm{intrinsic}}-\mathbf k_h\cdot\mathbf W_{\mathrm{ref}}\right)
(t+t_{\mathrm{epoch}}).
\]

At exactly the profile’s 10 m reference height, changing the reference wind by \(\mathbf b\) and querying the paired field at

\[
\mathbf x+\mathbf b(t+t_{\mathrm{epoch}})
\]

reproduced the corresponding wind shift to \(2.22\times10^{-15}\ \mathrm{m/s}\). The deliberately incorrect unshifted control differed by **0.660 m/s**, so the test was sensitive to the phase error it was designed to catch. [Mode phase and preparation](https://github.com/bultodepapas/OpenRCsimulator/blob/347905cafed505cad758107f2790fab2b018e4c6/app/physics/wind_spatial_field.gd#L316-L415)

This equivalence is restricted to the tested construction. Changing reference wind is not a uniform boost at every height of the ground-referenced profile.

### Moving front through real aircraft stations

A separate synthetic provider supplied an upward one-minus-cosine packet with:

- Horizontal propagation direction \([1,-1,0]/\sqrt2\).
- Front speed **2 m/s**.
- Duration **0.5 s**.
- Peak upward wind **2 m/s**.

For a prescribed fixed-attitude trajectory \(\mathbf x(t)=\mathbf x_0+\mathbf Vt\), the continuous peak time at station arm \(\mathbf r\) is

\[
t_{\mathrm{peak}}
=
\frac{
t_0+\mathbf n\cdot(\mathbf x_0+R\mathbf r)/c+T/2
}{
1-\mathbf n\cdot\mathbf V/c
}.
\]

Actual station queries matched the independently calculated peaks:

| Station | Peak time, s |
|---|---:|
| Left outer wing | 20.048266 |
| Right outer wing | 18.877801 |
| Horizontal tail | 19.381886 |
| Vertical tail | 19.401837 |
| Propeller | 19.480729 |

These are continuous times solved for the prescribed trajectory, then queried. They are not claimed as peaks observed on a simulated flight’s output ticks.

A separate bare production `Simulation` tick exercised actual Flow/Aero with one and two substeps. The expected RK stage times were used, and the independently computed station winds and relative flows matched at every evaluated stage.

The built-in spatial gust remains an epoch/height-dependent global event. The moving-front provider is a **regression fixture for a possible future propagation feature**. [Built-in gust implementation](https://github.com/bultodepapas/OpenRCsimulator/blob/347905cafed505cad758107f2790fab2b018e4c6/app/physics/wind_spatial_field.gd#L274-L299)

---

## 5. A complete wind-energy budget closes against the actual dynamics

**Classification:** completed component verification and a concrete offline diagnostic opportunity.

This part was informed by atmospheric-energy accounting research, then independently derived for OpenRC’s NED coordinates and body-frame velocity state. The external work distinguishes energy associated with updrafts, time-varying wind, and spatial wind gradients. [research-information.bris.ac.uk](https://research-information.bris.ac.uk/ws/portalfiles/portal/348328696/rsif.2022.0671.pdf?utm_source=chatgpt.com)

For constant mass, with the state datum at the center of mass, define

\[
\mathbf v_a=\mathbf v_g-\mathbf W,
\qquad
H=-D+\frac{\|\mathbf v_a\|^2}{2g}.
\]

Here \(H\) is **energy height**, measured in metres.

For non-gravity force \(\mathbf F\) expressed in NED,

\[
\boxed{
\dot H=
\frac{\mathbf v_a\cdot\mathbf F}{mg}
-\frac{\mathbf v_a\cdot\partial_t\mathbf W}{g}
-\frac{\mathbf v_a\cdot[(\nabla\mathbf W)\mathbf v_g]}{g}
-W_D
}
\]

The four contributions are force work, temporal wind change, movement through wind gradients, and vertical wind.

### Two implementation details matter

First, the spatial derivative follows the **aircraft trajectory**, so it uses ground velocity \(\mathbf v_g\).

Second, OpenRC stores translational velocity in body FRD. At a unit quaternion,

\[
\frac{d\mathbf v_g}{dt}
=
R\left(
\dot{\mathbf v}_{\mathrm{body}}
+
\boldsymbol\omega\times\mathbf v_{\mathrm{body}}
\right).
\]

Dropping the rotation-rate term would manufacture an apparent energy discrepancy. The production rigid-body state and derivative make this convention explicit. [State layout and dynamics](https://github.com/bultodepapas/OpenRCsimulator/blob/347905cafed505cad758107f2790fab2b018e4c6/app/physics/rigid_body.gd#L1-L15)

The wind-gradient terms are accounting terms. **The test adds no extra \(-d\mathbf W/dt\) force to the aircraft.**

### Actual production-component results

The experiment connected the real:

`WindSpatialField → WindAircraftFlow → Aero → RigidBody → Integrator`

It used constant Stik mass/inertia, no thrust or contact, and a quasi-steady reference wake recalculated at each RHS evaluation. Energy was sampled at normalized standalone RK endpoints; intermediate RK quaternions retained the production behavior.

Each case ran for **0.5 seconds** at 240, 480, and 960 Hz.

| Wind case | Energy-height residual at 240 Hz, m | At 480 Hz, m | At 960 Hz, m |
|---|---:|---:|---:|
| Uniform upper air | \(7.7562\times10^{-6}\) | \(1.9391\times10^{-6}\) | \(4.8478\times10^{-7}\) |
| Smooth shear layer | \(1.0147\times10^{-5}\) | \(2.5343\times10^{-6}\) | \(6.3111\times10^{-7}\) |
| Rising authored gust | \(1.0683\times10^{-5}\) | \(2.6714\times10^{-6}\) | \(6.6836\times10^{-7}\) |
| Mature advected thermal | \(8.9587\times10^{-6}\) | \(2.2398\times10^{-6}\) | \(5.5994\times10^{-7}\) |
| Seeded modes plus gust | \(7.5545\times10^{-6}\) | \(1.8883\times10^{-6}\) | \(4.7163\times10^{-7}\) |

The residual is the measured change in \(H\) minus the trapezoidal integral of the complete budget.

The approximately fourfold reduction when halving timestep is a **second-order diagnostic quadrature trend**. It is not a claim of fourth-order full-flight convergence.

The final run passed **96 checks**, with **21,034 actual aerodynamic load calls and zero load refusals**.

At the five initial states, a separate directional finite difference of \(H\) along the actual state/time derivative agreed with the independently sampled wind-partial budget within

\[
3.576\times10^{-8}\ \mathrm{m/s}.
\]

That independent directional check was not swept across every trajectory endpoint.

### Why the complete budget is useful

Along the same simulated trajectories:

- Omitting the total spatial term in the shear-case diagnostic produces an energy-height residual of approximately **−0.35155 m**.
- Omitting the temporal term in the gust-case diagnostic produces approximately **+0.52983 m**.

Those are errors in deliberately incomplete diagnostics. They are not production energy bugs or changes to the simulated trajectory.

The concrete improvement is an offline/debug ledger that records the four terms with the exact state, time, and provider identity. Numerical field derivatives require eight neighboring field queries per diagnostic point, so this should begin at a selected diagnostic cadence.

Finite-fuel aircraft need the existing fixed-datum and live-CG bookkeeping before reusing the constant-mass formula.

---

## What I would prioritize next

| Priority | Concrete action | Reason |
|---|---|---|
| **1** | Add tied-maximum detection and whole-pattern one-sided sensitivity analysis | Prevents an invalid centered Jacobian from becoming the basis of tuning or covariance predictions. |
| **2** | Promote the uniform, unique-maximum, moving-front, and RK-stage-time fixtures into focused regressions | Protects the wind-to-load path with discriminating tests. |
| **3** | Integrate the four-term energy ledger into offline flight analysis | Separates wind energy exchange from force-model or frame-accounting errors. |
| **4** | Evaluate any future induced-flow or unsteady-gust redesign against these baselines and independent physical data | Keeps numerical consistency and aerodynamic validity as separate acceptance questions. |

The verification strategy also follows NASA’s emphasis on examining turbulence-model assumptions alongside implementation checks. Its gust-gradient formulation was used as methodological inspiration; no additional gust torque was added on top of OpenRC’s station flow. [NASA Technical Reports Server (NTRS)](https://ntrs.nasa.gov/citations/20190000875?utm_source=chatgpt.com)

### Verification record

The six final focused runs completed:

| Probe | Checks | Failures |
|---|---:|---:|
| Unique-maximum load response | 351 | 0 |
| Direct directional versus coordinate response | 351 | 0 |
| Matched-wake cusp study | 177 | 0 |
| Explicit phase ensemble | 23 | 0 |
| Coordinate, epoch, gust-arrival, and stage-time checks | 71 | 0 |
| Energy accounting | 96 | 0 |

All final checked receipts contain zero engine errors and warnings. The counts include repeated controls, not statistically independent samples.

The initial tied-state probe’s **15 failed assertions** are retained: they exposed the incorrect smoothness assumption in the test design. The package also preserves the rejected gust-harness attempts and the earlier ablation whose wake was not matched.

The immediate engineering gain is a stronger, reproducible wind-analysis toolkit: **it detects when a linear approximation is invalid, verifies where and when the air reaches each station, and accounts for wind energy without adding spurious forces.**