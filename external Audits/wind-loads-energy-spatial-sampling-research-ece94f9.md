I extended the investigation into primary research, other open-source simulators, and independent mathematical experiments.

**The strongest next improvement is to qualify how the wind field becomes aircraft loads and energy changes.** A field can have a plausible RMS wind speed while producing the wrong rolling moments, gust timing, or rotor inflow. The research gives us several precise ways to test those effects.

I also quantified one tempting target—the existing OU interpolation—and found a small, bounded statistical effect at the supported time scales. That helps put engineering effort where it is more likely to improve flight behavior.

### Deliverables

- [OpenRC_Wind_Research_Extension_ece94f9.txt](https://chatgpt.com/library?file_id=libfile_c4bdbcff7c8881918d238bbf24a1383b&account_id=personal) — complete report, equations, affected code, proposed experiments, and source register.
- [OpenRC_Wind_Research_Lab_ece94f9.zip](https://chatgpt.com/library?file_id=libfile_447db7314fe481918dd58108f95f9e7c&account_id=personal) — runnable Python lab, numerical results, research notes, figures, and file hashes.
- [OpenRC_Wind_Math_References.png](https://chatgpt.com/library?file_id=libfile_16d6059735e4819183b82c5e3dcd7b09&account_id=personal) — full-size reference figure.

I rechecked the [consolidated audit ledger](https://github.com/bultodepapas/OpenRCsimulator/blob/ece94f9ede8c90c92652ebce68196f81eded6c70/external%20Audits/CONSOLIDATED-AUDITS.md), the completed-work register, and the existing wind reference and roadmap. Several broad research needs were already documented; the new contribution here is the mathematics, quantified examples, and concrete experiments that make those tasks actionable.

The code references below use the inspected `d0b672b…` snapshot. The [closing GitHub comparison through `ece94f9…`](https://github.com/bultodepapas/OpenRCsimulator/compare/d0b672b09663226ff8b8ac4f43eae8643c77a8c4...ece94f9ede8c90c92652ebce68196f81eded6c70) contains five later commits; the cited physics files are unchanged.

**The independent lab passed 55 named checks.** These are mathematical reference checks, not new aircraft flight tests. This extension adds research results and implementation recommendations without adding to the previously reported confirmed-bug count.

---

## 1. Test the wind’s rolling-moment effect separately from its average

**Priority: high. This is the most useful next qualification of the existing fixed-wing implementation.**

Relevant code:

- [Wing station geometry — `aircraft_data.gd:830–857`](https://github.com/bultodepapas/OpenRCsimulator/blob/d0b672b09663226ff8b8ac4f43eae8643c77a8c4/app/physics/aircraft_data.gd#L830-L857)
- [Station wind sampling — `wind_aircraft_flow.gd:263–358`](https://github.com/bultodepapas/OpenRCsimulator/blob/d0b672b09663226ff8b8ac4f43eae8643c77a8c4/app/physics/wind_aircraft_flow.gd#L263-L358)
- [Spatial aerodynamic continuation — `aero.gd:1068–1187`](https://github.com/bultodepapas/OpenRCsimulator/blob/d0b672b09663226ff8b8ac4f43eae8643c77a8c4/app/physics/aero.gd#L1068-L1187)

OpenRC already samples wind at distinct aerodynamic locations. NASA’s finite-element turbulence work provides a useful precedent for this approach: aircraft rotational response can arise from correlated disturbances at separated force locations. [NASA Technical Reports Server (NTRS)](https://ntrs.nasa.gov/citations/19970012097?utm_source=chatgpt.com)

The next question is **which spatial variations those samples reproduce accurately**.

### An exact reference for a rectangular wing

Consider one scalar wind component:

\[
w(y)=A\sin(ky+\phi),
\qquad q=\frac{kb}{2},
\]

where \(b\) is wingspan and \(k\) is spanwise wavenumber.

Under deliberately simplified **uniform linear sensitivity**, the exact span-average response is

\[
H_0(q)=\frac{\sin q}{q}.
\]

For six equally spaced strip centroids, it becomes

\[
H_6(q)=\frac{\sin q}{6\sin(q/6)}.
\]

These are useful sampling references, but the rolling effect depends on the **first spatial moment**:

\[
\frac1b\int_{-b/2}^{b/2}y\,w(y)\,dy.
\]

Normalized against the continuous, small-gradient result, its transfer is

\[
H_1(q)=\frac{3(\sin q-q\cos q)}{q^3}.
\]

The corresponding six-centroid result is

\[
H_{1,6}(q)=-\frac{3}{q}H_6'(q).
\]

A revealing limit follows:

\[
\lim_{q\to0}H_1(q)=1,
\qquad
\lim_{q\to0}H_{1,6}(q)=\frac{35}{36}.
\]

That is an exact quadrature property. **It is not evidence that OpenRC’s rolling moment is 2.78% wrong.** The real aerodynamic sensitivities depend on the induced map, polar, controls, moment arms, wake, and the matched spatial correction.

It does show why checking only average wind is insufficient:

- An even gust can produce a nonzero average with zero first moment.
- An odd gust can have zero average while producing a nonzero rolling excitation.

### Numbers tied to your aircraft geometry

The [Jensen Ugly Stik configuration](https://github.com/bultodepapas/OpenRCsimulator/blob/d0b672b09663226ff8b8ac4f43eae8643c77a8c4/app/data/aircraft/jensen_ugly_stik_60.json#L17-L27) uses a 1.524 m span. The current mode generator limits horizontal wavenumber to

\[
k_h\le\frac{\sqrt3}{2}\frac{2\pi}{\lambda},
\]

because the vertical share of the three-dimensional wavenumber is at least one half. Using that envelope and aligning the horizontal wave with a level wing gives these calculated references:

| Nominal 3-D wavelength | Continuous mean | Six-centroid mean | Continuous first moment | Six-centroid first moment |
|---|---:|---:|---:|---:|
| 5 m | 0.889263 | 0.892100 | 0.932899 | 0.911063 |
| 2 m | 0.422753 | 0.431284 | 0.631168 | 0.631828 |

These are limiting single-mode examples, not measured seeded fields or aircraft force errors.

### Concrete implementation experiment

At a fixed, symmetric, attached-flow state:

1. Apply a very small even sinusoidal wind perturbation, then an odd one.
2. Verify the actual station positions and sampled values against the analytical sums.
3. Estimate each station’s real load sensitivity through the existing wind-to-load path:

\[
J_i=
\frac{\partial(F_x,F_y,F_z,M_x,M_y,M_z)}
{\partial\mathbf W_i}.
\]

4. Predict the small-perturbation load from those sensitivities and compare it with the actual stage result.
5. Repeat at half amplitude, with mirrored wind, and with clearly separated wing, tail, propulsion, and wake contributions.

This would reveal whether a discrepancy originates in sampling, sign conventions, moment arms, force ownership, or the aerodynamic approximation.

### A useful computational shortcut for research

Once those sensitivities exist, a frozen-state covariance can be calculated analytically.

Write a mode’s station velocity as

\[
\mathbf w_{im}
=\mathbf p_{im}\cos\phi_m+\mathbf q_{im}\sin\phi_m,
\]

with spatial phase offsets absorbed into \(\mathbf p_{im}\) and \(\mathbf q_{im}\). For independent uniformly distributed phases, define

\[
\mathbf P_m=\sum_iJ_i\mathbf p_{im},
\qquad
\mathbf Q_m=\sum_iJ_i\mathbf q_{im}.
\]

Then

\[
\operatorname{Cov}(\text{load})
=
\frac12\sum_m
\left(\mathbf P_m\mathbf P_m^\mathsf T+
\mathbf Q_m\mathbf Q_m^\mathsf T\right).
\]

That provides an efficient way to investigate which modes contribute to force and moment variance before running long flights. It is a linearized analysis tool; actual nonlinear response still needs flight evaluation.

---

## 2. A seven-point disk rule offers a precise starting point for rotor wind research

**Priority: medium for the research program; potentially important before admitting spatial weather to helicopters.**

Owners include the [rotorcraft aerodynamic stage](https://github.com/bultodepapas/OpenRCsimulator/blob/d0b672b09663226ff8b8ac4f43eae8643c77a8c4/app/physics/rotorcraft/aerodynamic_stage.gd), main and tail rotor models, and their weather admission boundary.

Current helicopter support does not admit the spatial field considered here. This is a concrete extension of the already planned rotor-weather work.

### A hub sample and a disk average are different inputs

For a scalar sinusoidal wind component across a flat, uniformly weighted disk,

\[
H_{\rm disk}(q)=\frac{2J_1(q)}q,
\qquad q=k_hR,
\]

with \(H_{\rm disk}(0)=1\).

The small-wavenumber expansion is

\[
H_{\rm disk}(q)
=1-\frac{q^2}{8}+\frac{q^4}{192}+O(q^6).
\]

Uniform disk averaging also appears in rotor-effective-wind research, where alternative radial weighting is explicitly distinguished. That wind-turbine literature does not establish a complete helicopter rotor force model. [an experimental comparison](https://wes.copernicus.org/articles/4/421/2019/?utm_source=chatgpt.com)

For the [configured X-Cell radius of 0.775 m](https://github.com/bultodepapas/OpenRCsimulator/blob/d0b672b09663226ff8b8ac4f43eae8643c77a8c4/app/data/aircraft/xcell_60_research.json#L21-L25):

| Nominal 3-D wavelength | Single hub sample | Exact uniform disk average |
|---|---:|---:|
| 5 m | 1.000000 | 0.913678 |
| 2 m | 1.000000 | 0.538182 |

These compare normalized scalar wind amplitudes. They do **not** predict equivalent changes in rotor thrust.

### The seven-point construction

Use:

- One center point with weight \(1/4\).
- Six equally spaced ring points, each with weight \(1/8\).
- Ring radius \(\sqrt{2/3}\,R\).

The weights sum to one. Their radial moments satisfy

\[
\langle r^2\rangle=\frac{R^2}{2},
\qquad
\langle r^4\rangle=\frac{R^4}{3},
\]

while the angular arrangement cancels harmonics one through five.

Therefore, **this rule integrates every Cartesian polynomial wind pattern through total degree five exactly over a uniform disk**.

I verified all 21 monomials through that degree and checked the sinusoidal disk integral against an independent numerical area integral.

The orientation check matters. For the 2 m example:

- Exact disk response: **0.538181904**
- Seven-point response with an aligned wave: **0.538349824**
- Largest absolute error among **721 tested orientations**: **0.001691785**

The last number is the useful one to retain. The aligned case alone would make the rule appear more accurate than the orientation sweep supports.

### What this can and cannot improve

This is a compact, independently checkable **sampling diagnostic**. It could help evaluate disk input resolution without immediately building a large blade-element model.

Actual rotor loads still require radial and azimuthal weighting, blade motion, induction, flapping, and main-to-tail wake interaction. Even a simple quadratic load demonstrates the distinction:

\[
\left\langle(U-W)^2\right\rangle
=
(U-\langle W\rangle)^2+\operatorname{Var}(W).
\]

Evaluating a nonlinear force at mean wind loses information.

NASA’s SORBET work provides inspiration for distributed blade-station turbulence, but its published record concerns a full-size UH-60 and cannot supply RC rotor calibration directly. [NASA Technical Reports Server (NTRS)](https://ntrs.nasa.gov/citations/19970000605?utm_source=chatgpt.com)

---

## 3. The aircraft’s encountered gust frequency deserves explicit testing

**Priority: high as a diagnostic; conditional priority for adding new aerodynamic dynamics.**

The relevant implementation is [the mode construction and evaluation in `wind_spatial_field.gd:316–415`](https://github.com/bultodepapas/OpenRCsimulator/blob/d0b672b09663226ff8b8ac4f43eae8643c77a8c4/app/physics/wind_spatial_field.gd#L316-L415).

A mode has horizontal phase

\[
\phi=
\mathbf k_h\cdot\mathbf x_h
+
\left(\omega_{\rm intrinsic}
-\mathbf k_h\cdot\mathbf W_{\rm ref}\right)(t+t_{\rm epoch})
+\phi_0.
\]

For a straight path at constant height and ground velocity:

\[
\boxed{
\omega_{\rm encounter}
=
\omega_{\rm intrinsic}
+
\mathbf k_h\cdot
(\mathbf V_{\rm ground}-\mathbf W_{\rm ref})
}
\]

This gives several useful controls:

- A stationary aircraft encounters modes carried by the reference wind.
- An aircraft moving with that reference wind still encounters intrinsic evolution.
- A particular trajectory can cancel one mode’s frequency.

For example,

\[
\mathbf V_{\rm ground}-\mathbf W_{\rm ref}
=
-\frac{\omega_{\rm intrinsic}}{|\mathbf k_h|^2}\mathbf k_h
\]

makes that mode constant along the trajectory. The lab verified this with synthetic mode parameters inside the geometric envelope.

Consequently, the configured “coherence time” is not a guarantee that every aircraft trajectory sees that decorrelation time.

### How large can the encountered frequencies be?

For a horizontal path/reference-relative speed of 20 m/s and coherence parameter \(T_c=4\) s:

| Minimum nominal wavelength | Conservative individual-mode frequency bound |
|---|---:|
| 5 m | 3.839 Hz |
| 2 m | 9.035 Hz |

These are bounds for the stated straight, level motion. Particular seeds need not attain them, and attitude or altitude changes add further variation.

The aerodynamic reduced gust frequency is

\[
k_g=\frac{\omega_{\rm encounter}c}{2U_{\rm air}}
=\frac{\pi f_{\rm encounter}c}{U_{\rm air}}.
\]

The denominator must be **air-relative section speed**.

With the Stik chord \(c=0.3048\) m and \(U_{\rm air}=20\) m/s, those bounds give approximately \(k_g=0.184\) and \(0.433\). That makes an isolated unsteady-response comparison worthwhile.

Wei and colleagues studied periodic gust response at Reynolds numbers 200,000 and 260,000 and reduced frequencies 0.09–0.42. Their results show that incident gust composition and normalization matter when choosing between Sears and Atassi descriptions. They do not justify applying one generic filter to every RC airfoil. [arxiv.org](https://arxiv.org/abs/1811.10485?utm_source=chatgpt.com)

### A particularly useful moving-gust test

Use an isolated laboratory provider with

\[
\xi=\mathbf e\cdot(\mathbf x-\mathbf c_g t)-\xi_0
\]

and

\[
\mathbf W_{\rm gust}=
\begin{cases}
\displaystyle
\mathbf d\,\frac A2
\left[1-\cos\left(\frac{2\pi\xi}{L}\right)\right],
&0\le\xi\le L,\\[6pt]
0,&\text{otherwise},
\end{cases}
\]

where \(\mathbf d\perp\mathbf e\). That perpendicularity makes this idealized one-dimensional perturbation divergence-free.

For two fixed aircraft offsets, their crossing-time difference is

\[
t_2-t_1
=
-\frac{\mathbf e\cdot(\mathbf r_2-\mathbf r_1)}
{\mathbf e\cdot(\mathbf V_{\rm ground}-\mathbf c_g)}.
\]

A tail 0.6 m aft of the wing, entering an aligned gust at 10 m/s relative encounter speed, should see the same phase **0.06 s later**.

First verify that sampling delay. Then investigate the force delay. This separates:

1. Travel through the ambient gust.
2. Section aerodynamic response.
3. Wing-to-tail wake transport.
4. Aircraft motion.

The FAA’s gust-load guidance is useful for its one-minus-cosine test shape and its reminder that peak response can occur after the input gust ends. Its transport-aircraft dimensions and amplitudes are not RC requirements. [Dynamic Gust Loads](https://www.faa.gov/documentLibrary/media/Advisory_Circular/AC_25_341-1.pdf?utm_source=chatgpt.com)

A section-response study should measure **amplitude and phase**, preserve the current wake state separately, and demonstrate a consequential discrepancy before adding aerodynamic memory.

---

## 4. Add an energy diagnostic that distinguishes thermals, shear, and gusts

**Priority: high for wind qualification and potentially valuable for training feedback.**

Relevant owners are [air data](https://github.com/bultodepapas/OpenRCsimulator/blob/d0b672b09663226ff8b8ac4f43eae8643c77a8c4/app/physics/air_data.gd), [rigid-body translation](https://github.com/bultodepapas/OpenRCsimulator/blob/d0b672b09663226ff8b8ac4f43eae8643c77a8c4/app/physics/rigid_body.gd#L78-L129), the spatial/thermal providers, and the existing trace tools.

For a constant-mass aircraft, define:

- \(\mathbf v_g\): center-of-mass ground velocity in inertial NED.
- \(\mathbf W(\mathbf x,t)\): wind at that point.
- \(\mathbf v_a=\mathbf v_g-\mathbf W\): air-relative velocity.
- \(h=-D\): height.
- \(\mathbf F\): all nongravitational force in the same inertial frame.

Define *energy height*:

\[
H=h+\frac{|\mathbf v_a|^2}{2g}.
\]

Differentiation gives

\[
\boxed{
\dot H
=
\frac{\mathbf v_a\cdot\mathbf F}{mg}
-\frac{\mathbf v_a\cdot\partial_t\mathbf W}{g}
-\frac{\mathbf v_a\cdot[(\nabla\mathbf W)\mathbf v_g]}{g}
-W_D
}
\]

Every term has units of m/s.

| Term | What it measures |
|---|---|
| \(\mathbf v_a\cdot\mathbf F/(mg)\) | Nongravitational work |
| \(-\mathbf v_a\cdot\partial_t\mathbf W/g\) | Explicitly changing wind |
| \(-\mathbf v_a\cdot[(\nabla\mathbf W)\mathbf v_g]/g\) | Spatial shear encountered along the aircraft path |
| \(-W_D\) | Vertical air motion |

Published soaring energy analyses use this separation between updraft energy and energy obtained from spatial or temporal wind changes. ArduSoar also provides a practical reference for total-energy and sink-corrected variometry. [research-information.bris.ac.uk](https://research-information.bris.ac.uk/ws/portalfiles/portal/348328696/rsif.2022.0671.pdf?utm_source=chatgpt.com)

**This is a diagnostic identity. It does not call for adding another wind acceleration to the simulator.**

Its simplest controls are informative:

- Constant horizontal wind: the explicit wind-derivative and vertical terms vanish.
- Constant updraft: \(-W_D>0\).
- Steady vertical shear: energy change depends on the aircraft’s movement through that shear.
- A changing gust: the explicit time derivative contributes even at a fixed position.

### What I checked

The lab uses a manufactured trajectory and differentiable wind field. I differentiated \(H\) independently and compared it with the assembled right-hand side.

With central-difference intervals successively halved, maximum residuals were:

| Differencing interval | Maximum residual |
|---|---:|
| 0.040 s | \(1.31873\times10^{-4}\) m/s |
| 0.020 s | \(3.29699\times10^{-5}\) m/s |
| 0.010 s | \(8.24257\times10^{-6}\) m/s |
| 0.005 s | \(2.06065\times10^{-6}\) m/s |

The approximately fourfold reduction matches second-order differencing.

Deliberately omitting the spatial-gradient term produced a maximum 0.11829 m/s discrepancy in that manufactured case. This illustrates the diagnostic; it is not an observed OpenRC error.

### A source-specific integration precaution

OpenRC’s [finite-fuel dynamics use a fixed datum while the live center of mass moves](https://github.com/bultodepapas/OpenRCsimulator/blob/d0b672b09663226ff8b8ac4f43eae8643c77a8c4/app/physics/fixed_datum_body.gd#L1-L28).

Therefore, the first implementation should use a **constant-mass aircraft whose datum coincides with its center of mass**. A datum airspeed cannot automatically be substituted for CM airspeed during fuel depletion.

An extension to finite fuel must follow the existing CM and co-moving-efflux conventions. The diagnostic also excludes rotational and stored energy.

Once qualified, this could support clearer feedback: actual climb rate, local updraft, and energy-height rate answer different questions. That would help distinguish a genuine thermal encounter from trading airspeed for altitude.

---

## 5. The existing OU interpolation has a small, measurable statistical effect

**Priority: low compared with the load and energy work above.**

Relevant code:

- [OU endpoint update](https://github.com/bultodepapas/OpenRCsimulator/blob/d0b672b09663226ff8b8ac4f43eae8643c77a8c4/app/physics/wind_turbulence.gd#L65-L76)
- [Committed-interval interpolation](https://github.com/bultodepapas/OpenRCsimulator/blob/d0b672b09663226ff8b8ac4f43eae8643c77a8c4/app/sim/flight_session.gd#L617-L625)
- [Allowed correlation-time range](https://github.com/bultodepapas/OpenRCsimulator/blob/d0b672b09663226ff8b8ac4f43eae8643c77a8c4/app/physics/wind_config.gd#L121-L130)

The endpoints follow the exact stationary OU transition. Between endpoints, queries use linear interpolation.

Let

\[
a=e^{-\Delta/\tau},
\qquad
X(s)=(1-s)X_n+sX_{n+1}.
\]

With endpoint variance \(\sigma^2\),

\[
\frac{\operatorname{Var}X(s)}{\sigma^2}
=
1-2(1-a)s(1-s).
\]

Thus:

\[
\text{midpoint variance ratio}=\frac{1+a}{2},
\]

\[
\text{variance averaged over interval phase}=\frac{2+a}{3}.
\]

At 240 Hz:

| Correlation time | Midpoint RMS reduction | RMS reduction calculated from phase-averaged variance |
|---|---:|---:|
| 0.2 s | 0.5168% | 0.3442% |
| 2 s | 0.0520% | 0.0347% |
| 3 s | 0.0347% | 0.0231% |
| 30 s | 0.00347% | 0.00231% |

Because the allowed minimum is 0.2 s, monotonicity makes the first row the largest effect within the supported range at this timestep.

That is a useful bound. It does not suggest an urgent turbulence rewrite.

The reconstructed spectrum also differs from continuous OU: it contains the sampled-process spectrum multiplied by the first-order-hold \(\operatorname{sinc}^4\) envelope. Moreover, not every statistic moves downward. At \(\tau=0.2\) s, the one-interval integrated-wind variance is slightly lower than continuous OU, while its long-horizon variance rate is slightly higher.

**I would preserve the declared interpolation law and test its actual force-response bandwidth before changing it.** Blanket RMS renormalization would change other statistics and replay behavior.

NASA’s turbulence-verification work is useful here because it evaluates statistics, spectra, and aircraft response as separate layers. [NASA Technical Reports Server (NTRS)](https://ntrs.nasa.gov/citations/20190000875?utm_source=chatgpt.com)

---

## 6. Three external resources are worth using—with distinct jobs

### TurbSim/InflowWind: an independent synthetic spatial reference

The inspected [TurbSim source documentation](https://github.com/OpenFAST/openfast/blob/2895884d2be01862173c88d70f86b358d2f1a50a/modules/turbsim/README.md) describes stationary three-component wind series on a vertical grid, with specified spectra and spatial coherence. InflowWind reconstructs a queryable field using frozen-field advection. [openfast.readthedocs.io](https://openfast.readthedocs.io/en/main/_downloads/a231262e7763b4d61759ebe4e0fc30b2/InflowWind_Manual.pdf?utm_source=chatgpt.com)

A useful first experiment would:

- Generate one small, nonperiodic `.bts` fixture.
- Compare an independent reader with the matching InflowWind driver at grid nodes, half-cells, interior points, and boundaries.
- Compare spectra and complex cross-spectra at 0.5, 1, and 2 m station separations.
- Record the generator, inputs, axes, mean profile, advection speed, epoch, finite bounds, and hashes.

The mean is already part of the imported field. Adding OpenRC’s mean and OU again would change the intended atmosphere.

This reference can qualify an implementation against a chosen statistical model. Physical measurements are still needed to establish appropriate RC conditions.

### NEON CPER: real pointwise wind statistics

NEON’s original-frequency eddy-covariance data include 20 Hz three-component sonic wind. The usual one- and thirty-minute summaries cannot supply that spectrum. [Bundled data products - eddy covariance](https://data.neonscience.org/data-products/DP4.00200.001?utm_source=chatgpt.com)

CPER is a useful candidate because it is a shortgrass site with a low tower. However, its official page is internally inconsistent: the narrative states **8 m**, while the structured tower-height field states **9 m**. The selected deployment’s instrument metadata must resolve the actual measurement height. [Open Data to Understand our Ecosystems](https://www.neonscience.org/field-sites/cper?utm_source=chatgpt.com)

I would compare valid, contiguous windows, reserve entire days for assessment, and initially examine component variance and energy in explicitly selected frequency bands. Keep instrument orientation, quality flags, gaps, and sensor response in the record.

A single sonic does not establish wing-scale spatial coherence or thermal radius and lifetime. The dataset would qualify pointwise statistics under documented conditions.

No individual data file was downloaded here. NEON’s current instructions describe a token requirement for downloads, and its data policy provides CC BY 4.0 terms. [Open Data to Understand our Ecosystems](https://www.neonscience.org/resources/learning-hub/tutorials/get-started-neon-data-series-data-tutorials?utm_source=chatgpt.com)

### WindNinja: terrain mean-flow comparison

WindNinja could provide an offline reference for mean wind around terrain. Its documented typical resolution is around 100 m, and its mass-only solver cannot reproduce reversed-flow eddies; a separate mass-and-momentum solver has different capabilities. [US Forest Service Research and Development](https://research.fs.usda.gov/firelab/products/dataandtools/windninja?utm_source=chatgpt.com)

The useful first test is a withheld-station comparison:

1. Initialize from upstream observations.
2. Withhold another station.
3. Compare the predicted mean vector with that measurement and with a uniform-wind baseline.
4. Reverse inflow and vary terrain-buffer size.

Preserve the coordinate system, true versus grid north, output height, vegetation/roughness assumptions, and missing-data mask.

A horizontal raster does not provide a validated vertical velocity field. Its value here is independent terrain comparison while the simulator’s physical terrain and three-dimensional boundary behavior are qualified.

---

## 7. Borrow external methods while preserving one coherent world

The pinned [JSBSim `FGWinds` implementation](https://github.com/JSBSim-Team/jsbsim/blob/911b2d48ce934da183556983ec60b2069faa46fb/src/models/atmosphere/FGWinds.cpp#L260-L330) uses aircraft airspeed in its Dryden/Tustin time scales, including \(L/V\), and explicitly zeros those turbulence outputs at \(V=0\).

That makes it useful as a **path-conditioned reference**. It does not make it an arbitrary-position shared atmosphere.

Two independent equal-mean wind processes, each with component variance \(\sigma^2\), disagree even at coincident points:

\[
E[(W_1-W_2)^2]=2\sigma^2.
\]

Using the same spatially uniform wind time series for both instead produces perfect correlation at every separation.

For OpenRC’s shared-world work, the useful requirements are:

- Equal wind at equal world position and time.
- Query-order independence.
- Explicit separation covariance.
- One weather identity and epoch.
- Resetting one aircraft does not reset the world.

Force ownership needs the same care. Consider the synthetic rotational field

\[
\mathbf W(\mathbf r)=\boldsymbol\Omega_g\times\mathbf r.
\]

A station already sees

\[
(\boldsymbol\Omega_{\rm body}-\boldsymbol\Omega_g)\times\mathbf r
\]

in its relative flow. Additional angular-gust corrections can duplicate that contribution unless their ownership is derived explicitly.

OpenRC’s global empirical derivatives and local sectional contributions are not necessarily identical, so this should be tested with a per-source force and moment ledger rather than resolved by removing every rate term.

---

## Recommended implementation sequence

The previously confirmed configuration, restoration, and rotor-seam issues retain their corrective priority. For this new research work, I would proceed in this order:

| Order | Concrete change | Evidence required |
|---|---|---|
| **1** | Extend station-load tests with even/odd harmonic wind | Correct samples, mirrored moments, converged load sensitivities |
| **2** | Add the moving-pulse fixture | Predicted station-arrival times; separate input and force phase |
| **3** | Add constant-mass energy accounting to offline traces | Calm, updraft, shear, gust, and thermal controls; refinement |
| **4** | Qualify field statistics against synthetic and measured references | Explicit height, bandwidth, ensemble, covariance, and held-out cases |
| **5** | Add the disk quadrature to rotor research | Scalar sampling first, then actual blade sensitivity and wake behavior |
| **6** | Evaluate section-level unsteady aerodynamics | Demonstrated amplitude/phase discrepancy within a declared regime |







**The first implementation I would make is the station-load experiment together with the moving gust.** It directly exercises the wind field, sampling locations, coordinate transforms, aerodynamic forces, and moment arms already present in your simulator. It would tell us which additional wind physics would improve the flying experience—and which would merely add computation.