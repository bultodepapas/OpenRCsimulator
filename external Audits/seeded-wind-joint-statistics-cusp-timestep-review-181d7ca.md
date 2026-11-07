I continued into the **actual seeded wind field**, tracing it through station sampling and aerodynamic loads, and testing the fastest supported turbulence settings.

The strongest new result is that **the statistical reference can matter more than the aerodynamic discrepancy being investigated**. In one controlled case, the exact covariance of the sampled wind predicts vertical-force variance within about **0.012%** of the production aerodynamic result. An independent-phase ensemble predicts **3.83 times the same linear predictor’s finite-record variance**. Both statistics are valid, but they describe different experiments.

I also confirmed that the previously identified aerodynamic cusp occurs with real seeded wind, and found encouraging—but deliberately bounded—results from timestep refinement at the supported wind-setting extremes.

### Deliverables

- **Full review:** OpenRC_Seeded_Wind_Review_181d7ca.txt[OpenRC_Seeded_Wind_Review_181d7ca.txt](sandbox:/workspace/scratch/d136c947101b/deliverables/OpenRC_Seeded_Wind_Review_181d7ca.txt)
- **Runnable code, raw results, manifests, and checked logs:** OpenRC_Seeded_Wind_Lab_181d7ca.zip[OpenRC_Seeded_Wind_Lab_181d7ca.zip](sandbox:/workspace/scratch/d136c947101b/deliverables/OpenRC_Seeded_Wind_Lab_181d7ca.zip)
- **Results figure:** OpenRC_Seeded_Wind_Results_181d7ca.png[OpenRC_Seeded_Wind_Results_181d7ca.png](sandbox:/workspace/scratch/d136c947101b/deliverables/OpenRC_Seeded_Wind_Results_181d7ca.png)

I rechecked the [consolidated audit ledger](https://github.com/bultodepapas/OpenRCsimulator/blob/181d7ca638285f24c1ec9e5089ed07b35b7ea418/external%20Audits/CONSOLIDATED-AUDITS.md) before investigating. These results extend **A10, A23, and the documented F12 wind-statistics limitations**. They do **not** add a new independent serious-bug count.

The experiments ran against `181d7ca638285f24c1ec9e5089ed07b35b7ea418`. GitHub advanced to `420c259` during the review; I inspected that comparison. The wind, aerodynamic, simulation, and tested aircraft data remained unchanged. The production checkout was not modified.

---

## 1. The most useful new improvement: qualify the complete joint wind-to-load calculation

### Why the distinction matters

The implemented spatial turbulence is a finite collection of deterministic modes. Once the configuration, seed, and epoch are fixed, wind at every point and time is determined.

Two different statistical questions arise:

1. **What variance occurs in this particular record**, at these positions and sample times?
2. **What variance would occur across independently randomized modal phases**, keeping the modal geometry and amplitudes fixed?

A short time record need not reproduce the second statistic. Its modes can reinforce or cancel one another over the selected window, and its sample mean need not vanish.

That distinction follows directly from the phase evolution in [`wind_spatial_field.gd`](https://github.com/bultodepapas/OpenRCsimulator/blob/181d7ca638285f24c1ec9e5089ed07b35b7ea418/app/physics/wind_spatial_field.gd#L316). The repository already documents the qualitative limitation; this pass adds an exact numerical reference and tests its consequences for actual aircraft loads.

### What I executed

I built an independent Python implementation of:

- The seeded mode preparation.
- The height-dependent potential and its derivative.
- The resulting three-component wind.
- Exact mean and covariance over a finite, regularly sampled record.
- The full joint covariance of the wind inputs used by the aerodynamic model.

The independent reconstruction was compared with **11,776 production wind samples** across 11 prescribed paths and time windows.

The largest wind-vector component discrepancy was approximately:

\[
1.335\times10^{-13}\ \mathrm{m/s}.
\]

The largest entrywise discrepancy between the exact finite-record covariance and covariance calculated directly from production samples was approximately:

\[
1.292\times10^{-15}\ (\mathrm{m/s})^2.
\]

These are numerical agreement results on the pinned Linux/Godot runtime, not atmospheric validation.

### The same wind field gives substantially different short-record statistics

For the field matching the aerodynamic experiment:

| Parameter | Value |
|---|---|
| Seed | `20261025` |
| Mode count | 24 |
| Nominal wavelengths | 5–50 m |
| Coherence parameter | 4 s |
| Nominal turbulence RMS parameter | 0.05 m/s |
| Mean wind, layers, gusts, thermals | Zero/absent |
| Sampling position | `[0, 0, -100]` m NED |
| Sample rate | 8 Hz |

The observed centered vector RMS was:

| Record | Centered vector RMS | Fraction of the independent-phase RMS |
|---|---:|---:|
| 256 samples, starting at 0 s | 0.037956 m/s | 81.05% |
| 256 samples, starting at 128 s | 0.033744 m/s | 72.05% |
| 2,048 samples, starting at 0 s | 0.044285 m/s | 94.56% |
| Independent-phase ensemble at that point | 0.046832 m/s | 100% |

Here, a “32 s record” means 256 samples at \(0,0.125,\ldots,31.875\) seconds. The independent-phase RMS is also distinct from the authored nominal parameter of \(0.05\ \mathrm{m/s}\).

The closest pair of absolute mode frequencies in this fixture corresponds to a beat period of about **2,762 seconds**. That pair’s spacing alone does not explain the entire variance difference—its amplitudes and all the other cross terms matter—but it illustrates why a 4 s coherence parameter cannot guarantee that a short record behaves like an independent-phase ensemble.

**Practical consequence:** a developer could mistakenly increase turbulence strength to compensate for a low variance in one short recording, then produce excessive loads in another window. The correct first step is to establish which statistic the benchmark is supposed to reproduce.

### The aircraft needs the full joint covariance

The aerodynamic input is not just wind at the aircraft datum. In this experiment it comprises:

\[
\mathbf x=
\begin{bmatrix}
\mathbf W_0\\
\Delta\mathbf u_1\\
\vdots\\
\Delta\mathbf u_8
\end{bmatrix},
\qquad
\Delta\mathbf u_i
=
R^\mathsf T(\mathbf W_0-\mathbf W_i).
\]

That gives **27 scalar coordinates**: three datum-wind components and three ambient increments at each of eight aerodynamic surface stations. The sampling and subtraction are implemented in [`wind_aircraft_flow.gd`](https://github.com/bultodepapas/OpenRCsimulator/blob/181d7ca638285f24c1ec9e5089ed07b35b7ea418/app/physics/wind_aircraft_flow.gd#L280).

For a qualified linear load map \(J\),

\[
\operatorname{Cov}(\Delta\mathbf L)
=
J\,\operatorname{Cov}(\mathbf x)\,J^\mathsf T,
\]

where \(\mathbf L=[F_x,F_y,F_z,M_x,M_y,M_z]^\mathsf T\).

The covariance must retain the relationships between the datum and stations, and between different stations. Independent sampling of each location would describe a different field.

I reconstructed all 27 coordinates from the actual retained station positions and the independently prepared modes. The maximum input disagreement was \(1.562\times10^{-16}\ \mathrm{m/s}\). The joint-input covariance agreed within \(3.172\times10^{-18}\ (\mathrm{m/s})^2\) per entry.

For the control state with a unique fastest wing station, the results were:

| Calculation | Vertical-force variance, \(N^2\) | Rolling-moment variance, \((N\,m)^2\) |
|---|---:|---:|
| Actual nonlinear aerodynamic samples | 0.06987249 | 0.000905953 |
| Linear predictor, exact same finite record | 0.06988105 | 0.000905799 |
| Linear predictor, independent modal phases | 0.26772383 | 0.000746596 |
| Finite predictor with all cross-block covariances removed | 0.07395087 | 0.000503587 |

Three conclusions follow:

- The actual and same-record linear **vertical-force variances differ by about 0.01225%** in this case.
- The independent-phase linear variance is **3.83114 times** the finite-record linear variance.
- Removing covariance between the nine three-component blocks **underestimates rolling-moment variance by 44.4%** in this fixture.

The last row is a deliberately incomplete diagnostic calculation. I did not find production code using that approximation.

These are comparisons of specific marginal variances. Their close agreement does not establish a bound on every instantaneous load error, mean, cross-covariance, or aircraft state.

### Concrete improvement

Extend A23’s offline qualification with the reference included in the package:

- Preserve configuration, seed, epoch, exact sample times, and station positions.
- Calculate the finite-record mean instead of assuming it is zero.
- Retain the entire joint covariance matrix.
- Compare actual samples with the exact conditional reference.
- Treat independent-phase and independent-seed ensembles as separately defined experiments.

This creates a reliable basis for later turbulence tuning and physical-data comparisons.

---

## 2. The known aerodynamic cusp also appears with actual seeded wind

This is a stronger reproduction of the existing A10 issue.

### The code mechanism

In [`Aero._wing_flow`](https://github.com/bultodepapas/OpenRCsimulator/blob/181d7ca638285f24c1ec9e5089ed07b35b7ea418/app/physics/aero.gd#L293), the model normalizes station source strengths using the maximum three-dimensional station speed:

\[
U_{\max}=\max_i\|\mathbf u_i\|.
\]

The normalized strengths contribute to induced coupling. At a symmetric state, several stations can tie for the maximum. A small spatial gust then selects different winners in different perturbation directions.

The maximum function is continuous, but generally lacks a unique derivative at a tie. Consequently, individually stable centered sensitivity columns do not necessarily form a Jacobian that predicts arbitrary combined wind perturbations correctly.

The spatial load calculation uses matched local/reference evaluations with a common held wake; that ownership is preserved in these experiments. See [`ambient_spatial_continuation_loads`](https://github.com/bultodepapas/OpenRCsimulator/blob/181d7ca638285f24c1ec9e5089ed07b35b7ea418/app/physics/aero.gd#L1073).

### What changed from the earlier experiment

The positive wind samples now come through the actual production pipeline:

`WindSpatialField → WindField → Environment → WindAircraftFlow → Aero`

Wind at the datum and all stations changes together. The input is no longer a manufactured spanwise standing-wave pattern.

I evaluated the stock wheel-profiled Stik at a prescribed state with:

- 20 m/s datum-relative airspeed and approximately 3° angle of attack.
- Identity attitude and zero angular rate.
- Neutral controls.
- Density \(1.225\ \mathrm{kg/m^3}\).
- Baseline aerodynamic \(F_z=-39.6572\ \mathrm N\).
- A fixed, matched baseline wake within each comparison.

This is a frozen-state load-map test, not a trimmed or freely evolving flight.

### Separating smooth nonlinear effects from the cusp

For each production wind sample, I also evaluated a diagnostic reflected field:

\[
\mathbf W_- = 2\mathbf W_0-\mathbf W_+.
\]

The reflection is a controlled counterfactual, not a claim that another production seed generates exactly that field.

Define:

\[
\mathbf L_{\mathrm{odd}}
=
\frac{\mathbf L_+-\mathbf L_-}{2},
\]

\[
\mathbf L_{\mathrm{even}}
=
\frac{\mathbf L_++\mathbf L_-}{2}-\mathbf L_0.
\]

For a sufficiently smooth load map, the even response begins at second order in perturbation amplitude. A maximum tie can produce a first-order absolute-value contribution.

The actual seeded-field results show that distinction:

| Nominal wind RMS parameter | Tied-state even \(F_z\) RMS | Unique-maximum control | Coupling-ablation diagnostic |
|---|---:|---:|---:|
| 0.0500 m/s | 0.00208578 N | 0.00028946 N | 0.00029103 N |
| 0.0250 m/s | 0.00105660 N | 0.00007236 N | 0.00007276 N |
| 0.0125 m/s | 0.00053266 N | 0.00001809 N | 0.00001819 N |

Halving the input approximately halves the tied-state response. The control responses approximately quarter.

The tied odd-minus-linear residual also scales approximately linearly over these amplitudes. Thus, the discrepancy is not confined to the paired-even statistic.

For the unique-maximum control, I used a deliberately constructed roll-rate state, \(p=1\ \mathrm{rad/s}\). Its fastest station remained the same throughout all sampled amplitudes and reflections. This is a mathematical control on the load map, not a claim about a steady real flight at that rate.

The coupling ablation used a separate in-memory model with the off-diagonal induced-map entries set to zero. It retained the stock wake and recalculated its own baseline and sensitivity columns. That alteration changes the aerodynamic model and its baseline loads. It supports the existing mechanism; **it does not justify removing induced coupling as a fix**.

### Measured impact

At the largest tested nominal wind parameter, the tied-state positive-field results were:

| Load component | Actual wind-induced response RMS | Centered-prediction error RMS | Error relative to response |
|---|---:|---:|---:|
| \(F_x\) | 0.031612 N | 0.000264 N | 0.834% |
| \(F_y\) | 0.092958 N | 0.000086 N | 0.093% |
| \(F_z\) | 0.264717 N | 0.002425 N | 0.916% |
| \(M_x\) | 0.030236 N·m | 0.000032 N·m | 0.106% |
| \(M_y\) | 0.021332 N·m | 0.000079 N·m | 0.371% |
| \(M_z\) | 0.016831 N·m | 0.000018 N·m | 0.106% |

The vertical-force prediction error is approximately **0.0061% of baseline \(|F_z|\)**. It is detectable and relevant to sensitivity analysis, but this fixture does not establish a noticeable handling problem.

One subtlety matters: the production-only record’s mean \(\Delta F_z\) was negative, while the separately defined paired-even mean was positive. They are different quantities. The input itself has a nonzero finite-window mean, so its entire mean load change cannot be attributed to cusp rectification.

### Concrete improvement

Add the following to the offline aerodynamic diagnostic:

- Fastest station index and runner-up speed margin.
- Full-field one-sided responses.
- Amplitude-halving comparisons.
- Absolute force/moment errors alongside percentages of perturbation loads.

For a unique baseline winner with margin \(\Delta\), and a bound \(\epsilon\) on every station’s body-relative velocity perturbation, the reverse triangle inequality gives the sufficient condition

\[
\Delta>2\epsilon
\]

for preserving that winner.

This condition does not cover other aerodynamic branches, such as stall or angle wrapping, and the nominal turbulence RMS parameter is not itself a bound on \(\epsilon\).

Near ties, use directional or nonlinear sampling of the complete wind pattern. Any eventual normalization change should be evaluated as a physics-law candidate with the repository’s replay and affected-aircraft gates.

---

## 3. The supported rapid-wind settings did not expose a solver defect in the bounded tests

I separately examined admitted settings at the rapid end of the spatial wind configuration:

- Minimum and maximum wavelength both **2 m**.
- Coherence parameter down to **0.1 s**.
- Nominal turbulence RMS **1 m/s**.
- Mode counts of **8, 24, and 64**.
- Reference wind **3 m/s FROM 30°** at 10 m height.

These limits are enforced in [`wind_spatial_config.gd`](https://github.com/bultodepapas/OpenRCsimulator/blob/181d7ca638285f24c1ec9e5089ed07b35b7ea418/app/physics/wind_spatial_config.gd#L305).

This configuration is distinct from the 5–50 m, zero-mean field used for the load-statistics experiment.

### Actual encounter frequencies

For constant horizontal velocity at fixed height,

\[
\nu_m
=
\omega_m+\mathbf k_{h,m}\cdot\mathbf V_g.
\]

The prepared \(\omega_m\) already includes reference-wind advection. Subtracting that wind again would be an error in the analysis.

The maximum absolute frequencies from the actual prepared modes were:

| Modes / coherence parameter | Stationary observer | Moving with reference wind | Ground velocity 20 m/s north |
|---|---:|---:|---:|
| 8 / 0.1 s | 13.116 Hz | 14.048 Hz | 13.981 Hz |
| 24 / 4 s | 1.432 Hz | 0.351 Hz | 9.870 Hz |
| 24 / 0.1 s | 13.857 Hz | 14.048 Hz | 17.946 Hz |
| 64 / 0.1 s | 15.367 Hz | 14.328 Hz | 20.431 Hz |
| 64 / 600 s | 1.256 Hz | 0.00239 Hz | 9.691 Hz |

These are prescribed-path frequencies. They are not exact spectra of the evolving aircraft trajectory.

### Actual simulation refinement

I ran the actual `Simulation`, `WindAircraftFlow`, and `Aero` components using identical initial conditions and weather, with **1, 2, 4, 8, and 16 substeps per 240 Hz tick**.

The test used fixed Stik mass/inertia and evolving state, with gravity, propulsion, and contact absent. The runs were intentionally short: 0.10 s for eight modes and 0.05 s for 64 modes.

The maximum endpoint component differences between one and 16 substeps were:

| Quantity | 8 modes, 0.10 s | 64 modes, 0.05 s |
|---|---:|---:|
| Position | \(5.28\times10^{-8}\) m | \(3.40\times10^{-9}\) m |
| Body velocity | \(4.47\times10^{-7}\) m/s | \(1.75\times10^{-7}\) m/s |
| Quaternion component | \(3.60\times10^{-8}\) | \(1.83\times10^{-8}\) |
| Body angular rate | \(3.20\times10^{-6}\) rad/s | \(1.97\times10^{-6}\) rad/s |

Every requested stage was evaluated and accepted without a simulation fault.

The 16-substep trajectory is a finer comparator, not exact ground truth. Individual component differences were not monotone at every refinement, so I am not assigning a universal convergence order or claiming long-flight stability.

**These results provide no reason to increase the physics rate across the board.** They support retaining targeted extreme-setting refinement checks and investigating a specific longer-flight problem if one appears.

### Slow diagnostics can still misrepresent the same wind

One actual prepared mode has an encountered frequency of approximately **18.83994 Hz** on the selected path.

Its analytically reconstructed sequence aliases to:

- Approximately **−11.16006 Hz** under exactly uniform 30 Hz sampling.
- Approximately **−1.16006 Hz** under exactly uniform 10 Hz sampling.

That is a single-mode calculation from extracted coefficients, not a reproduced UI failure.

A separate direct sampling experiment used the complete eight-mode provider. Its downward-wind series had centered RMS \(0.560708\ \mathrm{m/s}\). Piecewise-linear reconstruction from subsets of the same samples produced:

| Retained sample rate | Reconstruction RMS error |
|---|---:|
| 240 Hz | 0.004991 m/s |
| 30 Hz | 0.279522 m/s |
| 10 Hz | 0.691064 m/s |

The complete eight-mode signal’s highest modal frequency was below 15 Hz. Therefore, its substantial 30 Hz reconstruction error demonstrates that **being below Nyquist does not make linear interpolation accurate**; it is not evidence of above-Nyquist aliasing in that complete signal.

The normal overlay text gate uses accumulated process-delta time, nominally around 10 Hz under ordinary conditions, and reads instantaneous wind. Forced refreshes and time scaling complicate that cadence. The physics trace is separately recorded per tick. See [`overlay_manager.gd`](https://github.com/bultodepapas/OpenRCsimulator/blob/181d7ca638285f24c1ec9e5089ed07b35b7ea418/app/render/overlays/overlay_manager.gd#L416).

**Concrete improvement:** use high-rate wind/load records with simulation timestamps for spectral and peak analysis. If a lower-rate display presents a filtered or interval statistic, define it explicitly and filter before decimation. A changing number on the HUD should not be used as a spectrum measurement.

---

## 4. A useful mathematical optimization is now implemented in the research code

The exact finite-record reference can calculate moments without generating every sample in a long regular record.

For sample times

\[
t_j=t_0+j\Delta t,
\]

define the finite-record characteristic factor

\[
K_N(\nu)
=
\frac1N\sum_{j=0}^{N-1}e^{i\nu t_j}.
\]

It has the closed form

\[
K_N(\nu)
=
e^{i\nu t_0}
e^{i(N-1)x/2}
\frac{\operatorname{sinc}(Nx/2)}
     {\operatorname{sinc}(x/2)},
\]

where \(x=\nu\Delta t\) reduced modulo \(2\pi\), and \(\operatorname{sinc}(z)=\sin(z)/z\).

Expanding the real wind modes into positive and negative complex-frequency terms lets the same expression calculate:

- Finite-record means.
- Every modal sum/difference cross term.
- Joint station covariance.
- Linearized force/moment covariance.

The stable kernel in the supplied implementation is essentially:

```python
import numpy as np

def finite_record_kernel(omega, start, dt, count):
    phase_step = (omega * dt + np.pi) % (2 * np.pi) - np.pi

    ratio = (
        np.sinc(count * phase_step / (2 * np.pi))
        / np.sinc(phase_step / (2 * np.pi))
    )

    return np.exp(
        1j * omega * start
        + 0.5j * (count - 1) * phase_step
    ) * ratio
```

The package includes direct-sum controls at zero and near-zero frequencies, aliases, nonzero start times, and an equal-frequency pair that cancels exactly.

Its computational work depends on the number of modes and coordinates rather than the duration of the sampled record. That makes it useful for repeated offline comparisons of window length, start time, and prescribed velocity.

This is an **analysis optimization**, with no measured FPS claim. Changing height, attitude, gust envelopes, or aircraft feedback breaks the simple fixed-coefficient harmonic assumption and requires further treatment or direct sampling.

---

## 5. What the external research adds—and the development priority

The TurbSim guide explicitly distinguishes statistics over its full analysis interval from statistics over a shorter output interval, and treats rescaling as an explicit option. That is a useful precedent for OpenRC’s diagnostic design: record the exact statistical definition and treat normalization changes as changes to the declared model. Its turbine-scale settings are not RC calibration. [openfast.readthedocs.io](https://openfast.readthedocs.io/en/v4.0.5/_downloads/cb14d3e2d3533d76e405d730fea19846/TurbSim_v2.00.pdf?utm_source=chatgpt.com)

NASA’s Dryden and gust-gradient verification work similarly emphasizes checking implementation assumptions and aircraft-relative gust gradients. It supports the layered verification approach here; it does not establish that OpenRC’s finite harmonic field is a Dryden process or justify adding another angular-gust force. [NASA Technical Reports Server (NTRS)](https://ntrs.nasa.gov/citations/20190000875?utm_source=chatgpt.com)

My recommended order is:

1. **Integrate the exact joint finite-record reference into A23’s qualification work.** This addresses the largest demonstrated analysis mismatch in this pass.
2. **Add the actual seeded-input cusp case and unique-maximum control to A10’s diagnostics.** Keep absolute effects visible when evaluating any normalization candidate.
3. **Retain the extreme-setting timing fixtures and timestamped high-rate diagnostics.** Extend them when a concrete stability or handling question warrants it.

The existing A22 weather-editing, checkpoint-layout, and rotor-continuity findings retain their repair priority. This continuation gives you more reliable ways to evaluate wind changes without mistaking a statistical mismatch for a force-model defect.

The final focused runs passed **283 assertions**, with zero detected engine errors or warnings. The independent mathematics adds 25 kernel controls and six joint-load conditions. Those counts include repeated controls; they are software verification evidence, not independent flight trials or physical validation.