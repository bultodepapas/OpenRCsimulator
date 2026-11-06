I continued the Extra 300 review and found **two additional actionable issues**:

1. **The trim solver repeats expensive steady-RPM searches after it already has the correct answer.** A small candidate patch removes that work and preserves every tested result byte.
2. **F5 reload can update the physical propeller and collision radius while leaving the visible propeller and blur at the previous diameter.** I reproduced this through the real application in both directions.

I reviewed development commit [`8e5f2f0`](https://github.com/bultodepapas/OpenRCsimulator/commit/8e5f2f0ba6aacd44efa1c4ac48c4023f181c47bd), checked the required [consolidated audit ledger](https://github.com/bultodepapas/OpenRCsimulator/blob/8e5f2f0ba6aacd44efa1c4ac48c4023f181c47bd/external%20Audits/CONSOLIDATED-AUDITS.md), and excluded the six findings from the first pass. The ledger is unchanged, and the newly implemented downwash-air reuse was already covered.

**Complete report, candidate patch, reproduction code, raw timings, fixtures, and logs:**

Extra300_Audit_Round2_8e5f2f0_2026-11-06.zip[Extra300_Audit_Round2_8e5f2f0_2026-11-06.zip](sandbox:/workspace/scratch/b3c27b2e84ee/extra300_audit/round2/Extra300_Audit_Round2_8e5f2f0_2026-11-06.zip)

## E300-07 — The final trim result unnecessarily solves the engine equilibrium twice

**Classification: demonstrated performance opportunity, with a tested candidate patch.**

The solver already retains the steady RPM corresponding to its current accepted Newton iterate. When a trial step succeeds, it updates the unknowns, RPM, and residual together. However, the result-building function discards that available RPM and recomputes it twice:

```gdscript
var e := _evaluate(x, mode, V, model, g, rho, engine_charge_ratio)
var rpm: float = ... _rpm(throttle, e.state, mode, model, rho, engine_charge_ratio)
```

The first line solves the steady RPM internally because none was supplied. The second solves it again to populate the returned result. Both searches repeat the equilibrium calculation already associated with the accepted iterate. See the [accepted-iterate updates](https://github.com/bultodepapas/OpenRCsimulator/blob/8e5f2f0ba6aacd44efa1c4ac48c4023f181c47bd/app/physics/trim.gd#L142) and [result construction](https://github.com/bultodepapas/OpenRCsimulator/blob/8e5f2f0ba6aacd44efa1c4ac48c4023f181c47bd/app/physics/trim.gd#L352).

### Why this is expensive

For the Extra’s glow installation, steady RPM comes from a torque-balance calculation:

\[
Q_{\text{engine}}(\omega,\tau,\rho_{\mathrm{dry}})
-
Q_{\text{propeller}}(\omega,u,\rho)=0,
\]

where \(\omega\) is shaft speed, \(\tau\) is throttle, and \(u\) is axial inflow.

The implementation searches an RPM mesh containing **128 intervals plus engine-table knots**, identifies restoring roots, and refines them by bisection. Repeating that search entails many engine and propeller evaluations. It is substantially more work than retrieving a scalar. [Operating-point implementation](https://github.com/bultodepapas/OpenRCsimulator/blob/8e5f2f0ba6aacd44efa1c4ac48c4023f181c47bd/app/physics/glow/operating_point.gd#L36)

### The exact-reuse solution

The candidate adds an optional RPM argument to `_result()`. On the bounded glow level-trim path, it passes the existing `x_rpm` through to the final evaluation and returned result.

The invariant that makes this safe is:

\[
\texttt{x\_rpm}
=
\operatorname{steadyRPM}(\texttt{x}).
\]

This association survives a failed line search. Rejected trial candidates keep their RPM in a local variable; the retained `x_rpm` still belongs to the last accepted `x`. That matters because unsuccessful trims also construct diagnostic results.

The patch preserves the existing root-selection rule, numerical tolerances, and equations. Its reuse is confined to the bounded glow level path. The existing fallback remains in place for glide, legacy propulsion, and electric trim.

An independent source review checked all five affected result exits, including failed bounded steps.

### Exact reduction in work

The instrumented probe counted calls from the trim solver to the finite-glow steady-RPM calculation:

| Extra 300 case | Original searches | Candidate searches | Searches eliminated |
|---|---:|---:|---:|
| Level trim at 22 m/s | 19 | 17 | 2 |
| Half-power cruise search | 202 | 174 | **28** |
| Excessive-idle refusal | 30 | 24 | 6 |
| Stopped-engine glide | 0 | 0 | 0 |

The half-power search performs 14 trim finalizations, so removing two searches from each eliminates:

\[
14\times2=28,
\qquad
\frac{28}{202}\approx13.86\%
\]

of its steady-RPM searches.

The final full-fuel, reference-atmosphere cruise result remained exactly the same, including the approximately **32.45912 m/s** airspeed and **10,784.934 RPM** equilibrium.

This is separate from the existing reuse of RPM during some Jacobian probes. The unnecessary work occurs during final result construction.

### Measured timing

I measured uninstrumented baseline and candidate code using the pinned Godot engine on Linux, with other audit CPU work paused. Each case used two warmup pairs followed by 24 measured pairs, alternating execution order.

| Calculation | Original median | Candidate median | Median reduction across paired runs |
|---|---:|---:|---:|
| Extra level trim, 22 m/s | 148.67 ms | 134.18 ms | **10.1%** |
| Extra half-power cruise search | 1,518.48 ms | 1,332.00 ms | **12.0%** |

The fixed-speed candidate was faster in **24 of 24 pairs**. The longer cruise search was faster in **17 of 24 pairs**, with substantial host variability: its paired reduction interquartile range ran from approximately **−5.2% to +13.2%**.

Consequently, **the exact elimination of 28 searches is stronger evidence than a promise of a fixed 12% speedup**.

These measurements cover warm, uncached solver calls. The application already has a launch-trim cache, so a cache hit bypasses this work. The benefit applies when the operating point must actually be recomputed—for example, after relevant model, fuel, or atmosphere changes. Full startup time, frame rate, GPU cost, and native-backend performance were outside this measurement. [Launch-cache implementation](https://github.com/bultodepapas/OpenRCsimulator/blob/8e5f2f0ba6aacd44efa1c4ac48c4023f181c47bd/app/sim/launch_trim_cache.gd#L41)

### Verification

The candidate passed:

- **87 audit checks**, including **34 byte-identical complete-result comparisons** and checks that the input model remained unchanged.
- **731 checks** in the repository’s trim-integrity test.
- **22 checks** in the repository’s cruise-trim test.
- Exact result comparison on all **48 measured timing pairs**.

The audit cases include full and 10% fuel, reference and hot-high atmospheres, several speeds, half-power searches, warm starts, failed trims, invalid requests, and glide. Legacy, electric, and four-stroke glow fixtures provide additional controls.

The archive includes the small patch, variant builder, probes, raw timing pairs, checked-runner receipts, and the independent invariant review. The patch also passes `git apply --check` against the reviewed revision.

## E300-08 — F5 reload leaves the Extra’s propeller visuals at the old diameter

**Classification: reproducible developer-workflow correctness bug.**

At startup, `main.gd` applies the validated glow installation’s propeller diameter to the visual model. The adjacent comment explicitly mentions handling installation-profile reloads that retain the same aircraft ID.

The actual F5 handler does this:

```gdscript
_note = session.reload() ...
_update_cg_model()
print(_note)
```

It updates the session and model CG, but never reapplies the accepted diameter to the visual propeller. The session meanwhile rebuilds the physical propeller collision disc. [Startup geometry handling](https://github.com/bultodepapas/OpenRCsimulator/blob/8e5f2f0ba6aacd44efa1c4ac48c4023f181c47bd/app/main.gd#L880) · [F5 handler](https://github.com/bultodepapas/OpenRCsimulator/blob/8e5f2f0ba6aacd44efa1c4ac48c4023f181c47bd/app/main.gd#L2137)

### Reproduction through the real application

I used the actual Extra flight scene and real F5 key events through the repository’s debug bridge.

The counterexample changes the diameter in both the disposable aircraft JSON and its existing glow-installation JSON:

\[
12\text{ in}=0.3048\text{ m},
\qquad
13\text{ in}=0.3302\text{ m}.
\]

This is a **synthetic, accepted same-ID developer edit**. It does not imply that a 13-inch alternative is shipped in the Extra catalog or physically calibrated.

| Operation | Accepted physical diameter | Physical strike radius | Visual propeller scale |
|---|---:|---:|---:|
| Stock launch and no-op F5 | 0.3048 m | 0.1524 m | 1.000000 |
| Change only aircraft diameter, then F5 | Previous value retained | Previous value retained | 1.000000 |
| Change both files coherently to 13 inches, then F5 | **0.3302 m** | **0.1651 m** | **1.000000 — stale** |
| Fresh launch with those same 13-inch files | 0.3302 m | 0.1651 m | 1.083333 |
| Restore stock files in that fresh flight, then F5 | **0.3048 m** | **0.1524 m** | **1.083333 — stale** |

The inconsistent one-file edit was correctly refused. Both coherent edits were accepted, with the application reporting that the aircraft had reloaded and trimmed successfully.

Those controls establish a specific lifecycle defect:

- The loader distinguishes valid and inconsistent installation data.
- Fresh initialization applies the accepted diameter.
- Successful F5 reload changes the physical configuration but misses the visual update.

### The geometric consequence

The required scale is already straightforward:

\[
s_x=s_y=
\frac{D_{\text{accepted}}}{D_{\text{authored}}}.
\]

For the test edit:

\[
s=\frac{13}{12}\approx1.083333.
\]

After the accepted 12-to-13-inch reload, the physical strike radius becomes **0.1651 m**, while the effective blur radius remains approximately **0.152428 m**. That creates a radial disagreement of about **12.67 mm**.

The reverse-direction test leaves approximately **0.165131 m** of visible radius against a physical radius of **0.1524 m**.

The mesh’s original measured tip is about 28 micrometres beyond its nominal radius, which is far smaller than the reload mismatch. These observations establish a geometry discrepancy; I did not fly a boundary-strike trajectory to demonstrate a resulting collision.

### The repair can reuse existing code

`AirplaneBuilder.apply_propeller_diameter()` already calculates scale from the authored diameter, making repeated applications idempotent. [Existing absolute-diameter setter](https://github.com/bultodepapas/OpenRCsimulator/blob/8e5f2f0ba6aacd44efa1c4ac48c4023f181c47bd/app/render/airplane.gd#L228)

After reproducing the stale state, I invoked that existing setter diagnostically. It returned success and updated both the propeller and blur transforms to the expected scale.

The blur does not inherently need to be rebuilt for a diameter-only change: its update function copies the propeller’s global transform **before** its early-return check. Its stored profile radius is local to the propeller. [Blur transform handling](https://github.com/bultodepapas/OpenRCsimulator/blob/8e5f2f0ba6aacd44efa1c4ac48c4023f181c47bd/app/render/propeller_blur.gd#L466)

The useful structural improvement is to extract one helper that applies the accepted installation geometry, then call it from startup and successful reload. It should also refresh dependent extents consistently and handle any presentation failure after physical commit explicitly.

The regression test needs to exercise the **actual F5 route**, covering:

- No-op and repeated reloads.
- Accepted diameter changes in both directions.
- Rejected aircraft/installation disagreement.
- The physical disc, solid propeller transform, and blur transform.

A test of the setter alone would miss this wiring error. The existing nominal Extra installation test passed **17 checks**, but it does not cover F5.

The archive contains the fixtures and full transcript. The diagnostic setter call is clearly identified; it is not presented as a production fix. The successful headless app runs had landscape resource UID fallback warnings, so they establish the observed state and transform behavior rather than rendered-pixel or target-GPU qualification.

## Additional mathematical findings that need validation

The aerodynamic pass produced useful questions, but the evidence does not yet justify changing the flight model.

### The polar and induced-source retention use different attachment measures

At a constructed **−20° angle of attack and 20 m/s**, the induced-source weights were all zero while the active polar retained attachment fractions of approximately **0.566–0.619**.

A disposable diagnostic that substituted the polar’s attachment fraction into the source weighting changed \(F_z\) by approximately **22.37 N**. This is substantial model sensitivity. However, there is no established contract requiring those two quantities to be equal, and the negative-angle branch lacks the independent evidence needed to identify the physically correct choice. [Source weighting](https://github.com/bultodepapas/OpenRCsimulator/blob/8e5f2f0ba6aacd44efa1c4ac48c4023f181c47bd/app/physics/aero.gd#L354)

The appropriate next step is to clarify the intended relationship and validate it against independent data. Adopting the diagnostic substitution as a fix would be premature.

### A maximum over station speeds introduces a small roll-rate cusp

The same normalization uses the maximum station speed. In a symmetric configuration, switching which wing supplies that maximum can introduce behavior of the form

\[
s(p)\approx s_0+c|p|.
\]

That expression is continuous, but its derivative changes abruptly at \(p=0\).

At **14° angle of attack and 20 m/s**, the probe found one-sided \(F_z\) derivatives approaching approximately

\[
-0.264606
\quad\text{and}\quad
+0.264606
\ \frac{\mathrm N}{\mathrm{rad/s}}.
\]

A fixture-specific diagnostic confirmed the maximum-speed normalization as the cause. A central finite difference at the symmetric point can therefore return zero even though the response contains a first-order \(|p|\) term.

This is relevant when interpreting a local linearization, but its force scale is small—about **0.026 N at 0.1 rad/s** in that fixture—and no material handling or integration failure was established. The archive labels it as a numerical modeling observation, not a serious bug or proposed generic wake correction.

## Areas that held up under the additional checks

The finite-fuel pass passed **23 checks** covering the four offered fill levels, live mass/CG/inertia, starter prime and momentum, cut/restart replay, and reset refueling.

An independent fixed-datum calculation reproduced the tested mass properties, with a maximum inertia discrepancy of approximately \(5.56\times10^{-17}\ \mathrm{kg\,m^2}\). A short **16-tick** recording containing an engine cut and restart replayed the sampled arrays exactly. That is useful bounded control evidence; it does not establish long-flight or physical tank validation.

I also excluded the rotating-shaft scenery result from the new findings after tracing it to an explicitly documented contact convention. The apparent Workshop scaling issue was unreachable because the current finite-glow Extra refuses that operation.

**The most useful next code changes are the isolated trim-reuse patch and a separate F5 synchronization repair with the public reload sequence as its regression test.** Both have clear boundaries, and neither requires changing the Extra’s aerodynamic calibration.