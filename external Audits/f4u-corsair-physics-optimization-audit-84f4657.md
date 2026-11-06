## Results

**I found one material Corsair flight-model inconsistency, one smaller numerical bug, and two concrete optimization opportunities.** The highest-priority issue is the reference point used by the Corsair’s aerodynamic rate derivatives: the generator supplies some moments about the center of gravity where the runtime expects moments about the aerodynamic reference point.

I read the complete [`external Audits/CONSOLIDATED-AUDITS.md`](https://github.com/bultodepapas/OpenRCsimulator/blob/84f4657814c157f1556f965861c0ab8623f48d8e/external%20Audits/CONSOLIDATED-AUDITS.md) before reviewing the code, then checked the findings against it and the Corsair’s development evidence. Previously reported issues and documented modeling limitations are excluded from the findings below.

The experiments use commit **`84f4657814c157f1556f965861c0ab8623f48d8e`** on `codex/m1-native-validation-20261106`. I also checked the subsequent head, `e72d878`: its changes concern flight statistics and do not alter the files responsible for these findings. [Checked comparison](https://github.com/bultodepapas/OpenRCsimulator/compare/84f4657814c157f1556f965861c0ab8623f48d8e...e72d878b6b4a89209dfe1a992ba119921dcdd34c).

### Deliverables

- [F4U_Corsair_Audit_84f4657.txt](https://chatgpt.com/library?file_id=libfile_e4c3faf362448191908e402b9b86067d&account_id=personal) — complete report, derivations, source locations, priorities, and repair recommendations.
- [F4U_Corsair_Evidence_84f4657.zip](https://chatgpt.com/library?file_id=libfile_16b0cbd23bd88191b1dcc3d53f409652&account_id=personal) — reproducible probes, isolated prototypes, raw measurements, checked-runner receipts, source hashes, and a replay helper.

| ID | Finding | Assessment | Evidence |
|---|---|---|---|
| **CF-01** | Corsair rate moments mix CG and aerodynamic-reference-point conventions | **Fix before further handling calibration** | Attached-flow pitch-rate moment is **7.74% weaker in magnitude** than the generator’s stated CG coefficient at the zero-angle diagnostic condition |
| **CF-02** | Propeller thrust coefficient jumps at the last table row | **Confirmed, smaller numerical defect** | Approximately **1.019 N** thrust step in a valid windmilling region; an accepted simulation tick crosses it |
| **CF-03** | Imported model construction validates the retract data twice | **Promising construction optimization** | Isolated validate-and-bind component: **15.98 → 8.37 ms/build**; production ownership conditions still need qualification |
| **CF-04** | Offline VLM recomputes a complete velocity vector for each component | **Small, well-supported cleanup** | **179,200 fewer function evaluations**, with identical complete generated output bytes |

The percentages here describe specific coefficients or measured components. They do not establish equivalent changes in whole-aircraft damping, loading time, or FPS.

---

## 1. CF-01 — The Corsair’s damping data use the wrong moment reference

### What the code does

The aircraft contract defines aerodynamic moment coefficients **about the aerodynamic reference point**, or ARP. The runtime then transfers the resulting forces and moments to the CG:

\[
\mathbf M_{\mathrm{CG}}
=
\mathbf M_{\mathrm{ARP}}
+
(\mathbf r_{\mathrm{ARP}}-\mathbf r_{\mathrm{CG}})
\times \mathbf F.
\]

That is exactly what `aero.gd` implements. The transfer itself is necessary and consistent with the declared contract. [Aircraft convention](https://github.com/bultodepapas/OpenRCsimulator/blob/84f4657814c157f1556f965861c0ab8623f48d8e/docs/AIRCRAFT_CONTRACT.md#L61-L72), [runtime force and moment calculation](https://github.com/bultodepapas/OpenRCsimulator/blob/84f4657814c157f1556f965861c0ab8623f48d8e/app/physics/aero.gd#L216-L246).

The Corsair generator, however, calculates pitch damping using the horizontal-tail arm **to the CG**:

```python
Cmq = -2 * tail_q * (xh_ac - cg[0]) ** 2 / c_ref ** 2 * 1.1
```

It also explicitly describes this coefficient as “tail damping about the CG x1.1.” The lateral rate derivatives use CG-referred fin arms as well:

```python
l_v = xv_ac - cg[0]
z_v = fin_cz - cg[2]

Cnr = -0.25 * 0.03 + 2 * (l_v / b) ** 2 * CYb_v - 0.02
CYr = -2 * CYb_v * l_v / b
```

These values are subsequently emitted into fields that the consumer interprets as ARP-referred moments. [Corsair rate-derivative generation](https://github.com/bultodepapas/OpenRCsimulator/blob/84f4657814c157f1556f965861c0ab8623f48d8e/research/f4u-corsair/F4U-07/derive_physics.py#L547-L580), [coefficient metadata](https://github.com/bultodepapas/OpenRCsimulator/blob/84f4657814c157f1556f965861c0ab8623f48d8e/research/f4u-corsair/F4U-07/derive_physics.py#L820-L846).

The result is an additional force-arm contribution applied to a moment that already incorporates the CG arm.

### The mathematical proof

At zero angle of attack and sideslip, let

\[
r_x=x_{\mathrm{CG}}-x_{\mathrm{ARP}},
\]

using the repository’s authored aft-positive \(x\) coordinate. The runtime’s transfer gives

\[
C_{m_q,\mathrm{realized}}
=
C_{m_q,\mathrm{stored}}
+
\frac{r_x}{c}C_{L_q},
\]

and

\[
C_{n_r,\mathrm{realized}}
=
C_{n_r,\mathrm{stored}}
+
\frac{r_x}{b}C_{Y_r}.
\]

For the loaded reference-inventory Corsair:

\[
r_x=0.0742843807412\ \mathrm m,\qquad
c=0.518605\ \mathrm m,\qquad
b=2.777778\ \mathrm m.
\]

Here \(c\) is the coefficient chord \(S/b\), as required by this project’s convention.

The production aerodynamic code produces:

| Quantity | Generated field | Additional reference transfer | Realized derivative about CG |
|---|---:|---:|---:|
| Pitch-rate moment \(C_{m_q}\) | −10.193066 | +0.789336415 | **−9.403729585** |
| Yaw-rate moment \(C_{n_r}\) | −0.093768 | +0.004090166 | **−0.089677834** |

Both added terms move the negative damping coefficients toward zero. Relative to the generator’s CG-derived values, the reductions in magnitude are:

\[
\frac{0.789336415}{10.193066}=7.7439\%,
\]

\[
\frac{0.004090166}{0.093768}=4.3620\%.
\]

There is also an independent mechanical check for the fin. Its body-frame vector from the reference CG is \((-l_v,0,-z_v)\). A yaw rate produces lateral point velocity \(-r l_v\). The resulting side-force derivative is

\[
C_{Y_r}=-2C_{Y_\beta,v}\frac{l_v}{b},
\]

and its moment about the CG is

\[
-\frac{l_v}{b}C_{Y_r}
=
2C_{Y_\beta,v}\left(\frac{l_v}{b}\right)^2.
\]

That is the fin term already present in the generator’s `Cnr`. Its moment reference is therefore established by the formula, independently of the explanatory comment.

### How I verified it

The probes call the actual `Aero.loads` implementation at 23 m/s. Central differences using rate perturbations of ±0.02, ±0.002, and ±0.0002 rad/s all recover the predicted derivatives. Both sides of each perturbation remain entirely in the empirical aerodynamic branch.

Two controls isolate the cause:

- Making the longitudinal CG and ARP coordinates coincide removes the additional terms.
- Subtracting the reference-transfer terms from the stored moments in an in-memory diagnostic recovers the original CG target values.

I also checked a production level trim. `Trim.solve` converged at approximately \(3.54535^\circ\) angle of attack and \(0.51218^\circ\) sideslip. At that state, the angle-corrected pitch transfer is

\[
\Delta C_{m_q}
=
C_{L_q}
\frac{r_x\cos\alpha+r_z\sin\alpha}{c}
=
0.809636836.
\]

At a pitch rate of 0.2 rad/s, the stock aerodynamic pitch moment differs from the reference-shift diagnostic by **0.441908 N·m**. At a yaw rate of 0.2 rad/s, the corresponding yaw difference is **0.0640453 N·m**. Both differences vanish at zero rate.

This matters because a static trim check can pass while the rate response remains inconsistent. The numerical results establish a model-convention error; they do not establish how much a real Corsair’s handling differs.

### Why a simple coefficient adjustment is incomplete

The same generator mixes references inside the force/moment pair:

```python
# Tail contribution uses the tail-to-ARP arm:
CLq = 2 * tail_q * l_h / c_ref + ...

# Tail moment uses the tail-to-CG arm:
Cmq = -2 * tail_q * (xh_ac - cg[0]) ** 2 / c_ref ** 2 * 1.1
```

Therefore, simply making `Cmq` more negative by the measured offset would leave the underlying derivation inconsistent. The rate-force reference needs to be settled along with the moment reference.

**Recommended repair:** derive each complete force/moment rate pair about a declared body datum \(O\), at a declared reference angle and wake condition. Then transform its moment to ARP once:

\[
\frac{\partial \mathbf M_{\mathrm{ARP}}}{\partial \omega_j}
=
\frac{\partial \mathbf M_O}{\partial \omega_j}
-
(\mathbf r_{\mathrm{ARP}}-\mathbf r_O)
\times
\frac{\partial \mathbf F}{\partial \omega_j}.
\]

Apply this separately to each rate component, then normalize with the correct reference lengths. Working in dimensional form during the transfer reduces opportunities to mix span, coefficient chord, and moment axes.

The repair belongs in the owning generator or a shared generation helper. The generic runtime should retain its correct ARP-to-CG operation.

For finite fuel, keep the distinction between the reference-inventory datum \(O\) and the live CG. The live mass-property transfer is a separate runtime operation; the empty-tank plan CG is not a substitute for the reference datum.

### Why this escaped existing coverage

The existing damping-regime and yaw-damping tests explicitly handle the ARP transfer for the **Stik**. They do not prevent a different aircraft generator from producing CG-referred values in ARP fields. [Existing damping tests](https://github.com/bultodepapas/OpenRCsimulator/blob/84f4657814c157f1556f965861c0ab8623f48d8e/app/tests/test_damping_regimes.gd#L62-L115).

This is a **Corsair recurrence** of a convention previously corrected under D6e-R1/D11g. I am not presenting the old Stik issue as a new discovery.

The useful regression is an independent generator-to-runtime check of the Corsair’s force/moment pairs, including zero angles, trim angles, mixed rates, fuel-dependent mass properties, and the empirical/local transition. The in-memory shifts used in this audit are diagnostics, not validated replacement physics.

---

## 2. CF-02 — The thrust curve jumps at its final table row

The stock Corsair thrust table ends at

\[
J_{\max}=1.35,\qquad C_{T,\mathrm{last}}=-0.1029.
\]

The shared propulsion implementation defines

```gdscript
const CT_FLOOR := -0.1
```

and extrapolates beyond the final row using:

```gdscript
return maxf(
    floor_value,
    last_value + slope * (J - last_J)
)
```

Inside the table, interpolation preserves the authored final value. Immediately outside it, the higher floor takes over. [Corsair thrust data](https://github.com/bultodepapas/OpenRCsimulator/blob/84f4657814c157f1556f965861c0ab8623f48d8e/app/data/aircraft/f4u_corsair_250.json#L2110-L2128), [lookup and floor implementation](https://github.com/bultodepapas/OpenRCsimulator/blob/84f4657814c157f1556f965861c0ab8623f48d8e/app/physics/propulsion.gd#L29-L57).

Consequently,

\[
C_T(J_{\max})=-0.1029,
\qquad
C_T(J_{\max}^{+})=-0.1.
\]

The jump is

\[
\Delta C_T=0.0029.
\]

This is a discontinuity in the value of the force coefficient, beyond the ordinary slope changes expected from linear interpolation.

### Numerical witness

| Advance ratio | Returned \(C_T\) |
|---|---:|
| \(1.35-10^{-9}\) | −0.102899999772 |
| \(1.35\) | −0.1029 |
| \(1.35+10^{-9}\) | −0.1 |

With

\[
T=C_T\rho n^2D^4,
\]

the stock \(D=0.762\) m propeller at 1,750 rpm and \(\rho=1.225\ \mathrm{kg/m^3}\) gives a thrust jump of approximately **1.01889 N**. The corresponding axial speed is about **30.00375 m/s**.

The power coefficient remains continuous at this boundary. A nearby in-table control at \(J=1.30\), using the same perturbation size, changes \(C_T\) by only about \(5.14\times10^{-10}\).

I also exercised the production finite-fuel session. Its paired stage evaluations showed approximately **1.012 N** difference in the forward force component and **0.04625 m/s²** in forward acceleration, with the session’s own atmosphere and coupled mass response.

For reachability, a valid constructed engine-off state started at \(J=1.35001\) and 1,750 rpm. One accepted 240 Hz tick crossed to

\[
J=1.3469053786,
\qquad
\mathrm{rpm}=1753.2005673,
\]

without a simulation fault.

**Severity remains modest.** This establishes a reachable numerical discontinuity, not a visible jerk, sustained trajectory error, or major handling failure.

### Recommended correction

For the current extrapolation form, continuity requires

\[
C_{\mathrm{floor}}\le C_{\mathrm{last}}.
\]

A declared per-propeller floor or a documented table-aware extrapolation rule can satisfy that condition while preserving the authored values inside the table.

The regression should cover final values above, equal to, and below the floor; neighboring binary64 inputs; unchanged in-table interpolation; and the engine-off crossing. Keep any physical recalibration of the propeller separate from this lookup correction.

The same shared interaction occurs in other data, including the P-51. A generic table/extrapolation contract is preferable to a Corsair-specific runtime branch.

---

## 3. CF-03 — The retract rig is validated twice during one model build

The duplicated work occurs in the shared imported-aircraft builder:

| Step | Operation |
|---|---|
| `imported_model.gd:58` | Calls `Construction.validate_geometry(...)` |
| `imported_model_contract.gd:197–200` | Validates the complete retract rig |
| `imported_model.gd:110` | Calls `Retraction.bind(...)` |
| `retractable_model.gd:72–75` | Immediately validates the complete rig again |

The Corsair’s generated rig contains **101 samples × 17 carrier nodes = 1,717 pose records**, plus **606 wheel-path vectors**. The second invocation repeats the scan of those records. [Builder](https://github.com/bultodepapas/OpenRCsimulator/blob/84f4657814c157f1556f965861c0ab8623f48d8e/app/aircraft/imported_model.gd#L50-L113), [construction validator](https://github.com/bultodepapas/OpenRCsimulator/blob/84f4657814c157f1556f965861c0ab8623f48d8e/app/aircraft/imported_model_contract.gd#L188-L200), [retract validator and binder](https://github.com/bultodepapas/OpenRCsimulator/blob/84f4657814c157f1556f965861c0ab8623f48d8e/app/aircraft/retractable_model.gd#L24-L113).

### What the prototype changed

The isolated prototype preserves the public `bind()` validation behavior and splits the remaining binding implementation into a private operation that consumes immediately validated data.

It retains the checks that depend on the actual scene:

- Unique node bindings and correct parents.
- Rest-transform agreement.
- Wheel-helper validity.
- Agreement with the declared stowed pose.

The proposed saving is the repeated data scan within one construction call.

### Measured result

Eight alternating baseline/candidate pairs, with four builds per batch, gave:

| Metric | Result |
|---|---:|
| Baseline median batch mean | **15.9835 ms/build** |
| Candidate median batch mean | **8.3696 ms/build** |
| Median paired reduction | **49.69%** |
| Paired reduction range | **25.46–67.93%** |
| Pairs favoring candidate | **8/8** |

The wide range shows host noise. These are medians of batch means, not individual-load latency percentiles.

The candidate also passed **21 bind-level assertions** and **8 synthetic complete-build assertions**, including malformed poses, wheel paths, and node bindings. The complete-build comparison checks node transforms and the public rig/articulation structure.

### Production conditions

This is worth qualifying, but the ownership boundary must be explicit: **the rig contents must remain unchanged between validation and binding**.

Keep validation for standalone callers. Use a private synchronous handoff within construction, with no stale validation receipt or cross-build identity cache. Any new copying or guard overhead must be measured as part of the candidate.

The fixtures use real generated Corsair geometry in synthetic node hierarchies. They do not load the actual GLB, textures, or materials. Consequently, this result does **not** establish a 49.69% reduction in aircraft loading time or any FPS gain.

The next useful measurement is the real aircraft-selection and flight-start path after the change passes actual Corsair and Avanti construction checks.

---

## 4. CF-04 — The offline VLM computes the same vector three times

The Corsair ground-effect generator builds an influence-matrix entry with:

```python
sum(
    horseshoe(pi["cp"], pj, ground)[k] * pi["n"][k]
    for k in range(3)
)
```

`horseshoe()` returns the complete three-component induced-velocity vector. The expression invokes it once for each component of the dot product.

That function performs segment geometry, cross products, square roots, and—when ground is present—image-vortex calculations. Its inputs and output are identical across those three calls. [VLM implementation](https://github.com/bultodepapas/OpenRCsimulator/blob/84f4657814c157f1556f965861c0ab8623f48d8e/research/f4u-corsair/F4U-07/ground_effect_vlm.py#L93-L148).

The duplication can be removed with a small helper:

```python
def normal_influence(pi, pj, ground):
    velocity = horseshoe(pi["cp"], pj, ground)
    return sum(
        velocity[k] * pi["n"][k]
        for k in range(3)
    )

A = [
    [normal_influence(pi, pj, ground) for pj in panels]
    for pi in panels
]
```

This preserves the original multiplication and summation order.

### Exact work reduction

There are 80 panels and 14 solves: free air plus 13 ground heights.

For matrix construction alone:

\[
N_{\mathrm{before}}=14\cdot80^2\cdot3=268{,}800,
\]

\[
N_{\mathrm{after}}=14\cdot80^2=89{,}600.
\]

Including the unchanged Trefftz-plane and tail-point work, instrumented totals were:

| Version | `horseshoe()` evaluations |
|---|---:|
| Original | 371,840 |
| Candidate | 192,640 |
| Removed | **179,200** |

That is **48.19% fewer evaluations** across the complete generator.

The complete original and candidate JSON outputs were **byte-identical**, including all heights and both fitted outputs. The baseline output also passed the existing repository tolerance check against the retained data file.

This is an offline regeneration improvement. I did not measure an elapsed-time speedup, and this code does not run during flight. It is nevertheless a useful small cleanup: less computational work, a clearer expression of the intended dot product, and unchanged generated results.

---

## 5. Two optimization ideas did not earn a recommendation

I retained the negative results because they prevent attractive-looking changes from becoming regressions.

### Stationary gear-pose caching was slower

A guarded cache matched **24,850 sampled transform/rest comparisons**, but its source-data checks cost more than the interpolation it replaced.

| Workload | Original | Guarded cache |
|---|---:|---:|
| Stowed | 37.08 µs/call | 45.74 µs/call |
| Deployed | 35.19 µs/call | 44.74 µs/call |
| Moving | 41.75 µs/call | 86.28 µs/call |

Every measured pair favored the original.

Simply skipping `apply()` when extension is unchanged would also be incorrect: the sampled pose must be restored before suspension compression is added. The current frame’s node transforms are not necessarily the original sampled transforms. [Pose application and compression-rest refresh](https://github.com/bultodepapas/OpenRCsimulator/blob/84f4657814c157f1556f965861c0ab8623f48d8e/app/aircraft/retractable_model.gd#L116-L130).

**Reject this cache prototype.** A cheaper design based on explicitly immutable data remains unmeasured.

### Reusing the gasoline propeller result had inconclusive timings

The legacy Corsair path can evaluate thrust and torque in `Propulsion.loads`, then evaluate them again for `Slipstream.stage_loads`. A narrowly guarded handoff matched **291 sampled load/refusal checks**. [Dynamics handoff](https://github.com/bultodepapas/OpenRCsimulator/blob/84f4657814c157f1556f965861c0ab8623f48d8e/app/physics/dynamics.gd#L109-L135), [slipstream evaluation](https://github.com/bultodepapas/OpenRCsimulator/blob/84f4657814c157f1556f965861c0ab8623f48d8e/app/physics/slipstream.gd#L59-L89).

However, ten alternating timing pairs split **five in favor of each version**, with changes ranging from **−9.91% to +22.53%**. That does not establish a reliable speedup.

This also requires care around different inflow conventions: an electric propeller’s hub velocity is not automatically interchangeable with the legacy gasoline datum velocity. The shaft’s torque expression has a different floating-point operation order, so substituting that result requires separate justification.

I would defer this change until session-level profiling demonstrates a worthwhile cost.

---

## 6. What I would change first

The strongest organizational improvement is to make reference conventions explicit where physical data are generated. The Corsair generator currently mixes geometry, empirical estimates, force derivatives, and moment references closely enough that a plausible formula can be written into a field with the wrong meaning.

I would separate the work into four small changes:

1. **Repair the Corsair rate-derivative derivation.** Introduce one well-defined transformation for complete force/moment rate pairs, preserve the reference-inventory/live-CG distinction, regenerate the aircraft data, and qualify the changed handling.
2. **Define a continuous propeller extrapolation contract.** Preserve authored in-table values and test the endpoint/floor interaction independently of physical calibration.
3. **Apply the VLM vector reuse.** Keep it generator-only and require complete output-byte equivalence.
4. **Qualify the single-build retract-validation handoff.** Preserve public validation and scene checks, then measure real aircraft-selection and flight-start behavior.

These changes have different acceptance criteria. The physics corrections intentionally change behavior and require new expected results and flight qualification. The work-elimination changes should preserve outputs and refusal behavior.

### Cross-check against earlier work

| New finding | Related earlier work | Why this remains a new finding |
|---|---|---|
| CF-01 | Stik D6e-R1/D11g datum work | This identifies the recurrence in the **Corsair generator** |
| CF-02 | Documented uncertainty in inferred propeller data | The newly demonstrated problem is the **lookup discontinuity**, independent of coefficient accuracy |
| CF-03 | Kernel validation reuse and F4U model/Home work | This isolates the **second sampled-gear scan within one build** |
| CF-04 | M09/M10 runtime reuse proposals | This concerns the **offline Corsair VLM generator** |

### Verification boundary

I replayed the packaged diagnostics in fresh isolated projects. The eight diagnostic runs and two imports completed with their required markers, `ok=true`, `complete=true`, and zero engine errors or warnings. The portable VLM replay also reproduced the exact output comparison.

The audit establishes software and mathematical consistency findings. Full flight-tape comparisons, native-backend qualification, real imported-scene timing, rendered behavior, and independent aircraft measurements remain outside these experiments.

**The production repository remains unchanged.**