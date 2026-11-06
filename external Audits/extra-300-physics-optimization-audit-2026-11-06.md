## Extra 300 audit: two physics defects and three concrete optimization opportunities

I found **two reproducible Extra-specific physics consistency defects**, **three optimization opportunities**, and **one visual defect**. The strongest findings are in the aerodynamic-data generator: it mixes moment reference points and derives propeller crossflow coefficients without the installed blade’s camber.

I read the complete [`external Audits/CONSOLIDATED-AUDITS.md`](https://github.com/bultodepapas/OpenRCsimulator/blob/e72d878b6b4a89209dfe1a992ba119921dcdd34c/external%20Audits/CONSOLIDATED-AUDITS.md) before reviewing the code, then checked these findings against the previous audits and Extra research notes. I also used the GitHub tools to verify the branch, commits, related PRs, and source.

**Reviewed:** `codex/m1-native-validation-20261106` at [`e72d878`](https://github.com/bultodepapas/OpenRCsimulator/commit/e72d878b6b4a89209dfe1a992ba119921dcdd34c). The branch still pointed to that commit at the closing check. Production source remains unchanged.

**Complete report, reproduction scripts, experimental patches, raw results, and checked-run receipts:**  
Extra300_Audit_e72d878_2026-11-06.zip[Extra300_Audit_e72d878_2026-11-06.zip](sandbox:/workspace/scratch/b3c27b2e84ee/extra300_audit/Extra300_Audit_e72d878_2026-11-06.zip)

### Findings at a glance

| ID | Finding | Demonstrated consequence | Priority |
|---|---|---|---|
| **E300-01** | Aerodynamic generator mixes CG and aerodynamic-reference-point moments | A **0.1036 N·m roll-moment discrepancy** in the tested sideslip case; smaller pitch/yaw damping discrepancies | Fix before aerodynamic retuning |
| **E300-02** | Propeller crossflow tables omit installed blade camber | At \(J=0.5\), P-factor coefficient is **55.6% below** the result from the same method using the installed section | Fix before propulsion/handling retuning |
| **E300-03** | Repeated mass, CG, inertia, and inverse calculations within one physics stage | A guarded prototype removes **960 duplicate evaluations per simulated second** on the ordinary four-stage, 240 Hz path | Complete parity qualification, then benchmark |
| **E300-04** | Loft meshes duplicate vertex attributes | Indexed candidate reduces measured stock mesh buffers by **71.68%**, but construction was slower in the benchmark | Memory tradeoff |
| **E300-05** | Custom paint recreates identical shader resources | **14 distinct shaders with identical code** during preparation; another 14 in the representative paint test | Focused resource-reuse opportunity |
| **E300-06** | Visual propeller blade handedness opposes its rotation | The modeled trailing edge travels first | Presentation correction |

The numerical differences below are **software consistency results from production-code probes**. They do not establish how closely a corrected aircraft matches a real Extra 300S.

---

## 1. The aerodynamic generator uses the wrong reference point for some moments

**This is the most important structural physics finding.**

Your aircraft contract is explicit: aerodynamic moment coefficients are supplied about the **aerodynamic reference point**, or ARP. The runtime then transfers the associated forces to the center of gravity:

\[
\mathbf M_{\mathrm{CG}}
=
\mathbf M_{\mathrm{ARP}}
+
(\mathbf r_{\mathrm{ARP}}-\mathbf r_{\mathrm{CG}})
\times\mathbf F.
\]

The shared runtime implements that contract. However, the Extra generator derives the fin contribution to the sideslip rolling-moment coefficient using the fin’s height above the **loaded CG**:

```python
z_v = fin_cy - cg_model_y
Clb = Clb_wing + dihedral_low + CYb_v * z_v / b
```

That CG-based contribution is then consumed as an ARP-based coefficient, and the runtime applies another force-arm transfer. Nearby coefficients already use ARP arms correctly, so the generator contains a mixture of conventions. Sources: [aircraft frame contract](https://github.com/bultodepapas/OpenRCsimulator/blob/e72d878b6b4a89209dfe1a992ba119921dcdd34c/docs/AIRCRAFT_CONTRACT.md#L61-L70), [Extra lateral derivatives](https://github.com/bultodepapas/OpenRCsimulator/blob/e72d878b6b4a89209dfe1a992ba119921dcdd34c/research/extra-300/ex05/derive_physics.py#L346-L391), and [runtime moment transfer](https://github.com/bultodepapas/OpenRCsimulator/blob/e72d878b6b4a89209dfe1a992ba119921dcdd34c/app/physics/aero.gd#L216-L246).

### The mathematical discrepancy

Using the authored structural coordinates, where \(z\) is positive upward, the fin contribution required by the consumer is:

\[
C_{\ell_\beta,\mathrm{fin}}^{\mathrm{ARP}}
=
C_{Y_\beta,\mathrm{fin}}
\frac{z_{\mathrm{fin}}-z_{\mathrm{ARP}}}{b}.
\]

The generator supplies:

\[
C_{\ell_\beta,\mathrm{fin}}^{\mathrm{generated}}
=
C_{Y_\beta,\mathrm{fin}}
\frac{z_{\mathrm{fin}}-z_{\mathrm{CG}}}{b}.
\]

Therefore its excess relative to the ARP convention is:

\[
\Delta C_{\ell_\beta}
=
-C_{Y_\beta,\mathrm{fin}}
\frac{z_{\mathrm{CG}}-z_{\mathrm{ARP}}}{b}.
\]

For the stock full-tank Extra, the probe obtains:

- \(C_{Y_\beta,\mathrm{fin}}=-0.35510923\ \mathrm{rad}^{-1}\)
- \(z_{\mathrm{CG}}-z_{\mathrm{ARP}}=0.02842429\ \mathrm m\)
- \(b=1.6256\ \mathrm m\)

This gives:

\[
\boxed{\Delta C_{\ell_\beta}=+0.00620923\ \mathrm{rad}^{-1}}
\]

The sign shifts the tested sideslip roll response toward a less stabilizing value.

### What changes in the actual load calculation

I tested the production functions at:

- \(V=20\ \mathrm{m/s}\), \(\rho=1.225\ \mathrm{kg/m^3}\)
- \(\alpha=0^\circ,\ \beta=+5^\circ\)
- Zero body rates and neutral controls
- Settled wake, no ground effect, 12,000 rpm

A diagnostic model copy changed **only the fin-reference contribution to `Clb`**.

| Roll moment | Stock | Reference-point diagnostic |
|---|---:|---:|
| Aerodynamic component | −0.328074 N·m | −0.431661 N·m |
| Combined aerodynamic, propeller, and slipstream loads | −0.919021 N·m | −1.022608 N·m |
| Difference | | **−0.103587 N·m** |

That is **24.0% of the diagnostic aerodynamic roll component**, or approximately **10.1% of the diagnostic combined roll moment** in this positive-sideslip case. The distinction matters: 24% is not a measured error in the aircraft’s complete roll response.

At negative sideslip, the correction changes sign. The other five load components and the propeller/slipstream contributions remain unchanged. The local-flow selector is exactly zero, so the result does not depend on a stall-transition ambiguity.

### The same convention problem affects damping

The generator explicitly labels `Cmq` as a coefficient about the CG. The fin part of `Cnr` also uses a CG-based arm. The runtime nevertheless treats their moments as ARP moments and transfers the accompanying rate forces. See [the generator’s coefficient definitions](https://github.com/bultodepapas/OpenRCsimulator/blob/e72d878b6b4a89209dfe1a992ba119921dcdd34c/research/extra-300/ex05/derive_physics.py#L593-L610).

Small, symmetric rate probes produced:

| Derivative | Generated value | Effective CG derivative |
|---|---:|---:|
| Pitch damping \(C_{m_q}\) | −9.360761 | −9.157953 |
| Yaw damping \(C_{n_r}\) | −0.180871 | −0.178734 |

These match the extra transfer terms:

\[
C_{m_q,\mathrm{effective}}
=
C_{m_q}
+
C_{L_q}\frac{x_{\mathrm{CG}}-x_{\mathrm{ARP}}}{c},
\]

\[
C_{n_r,\mathrm{effective}}
=
C_{n_r}
+
C_{Y_r}\frac{x_{\mathrm{CG}}-x_{\mathrm{ARP}}}{b}.
\]

The effects are smaller—about 2.17% and 1.18% less negative—but reinforce the reference-convention diagnosis.

### Recommended repair

For the static fin contribution, the narrow correction belongs in the Extra generator:

```python
fin_clb_arp = CYb_v * (fin_cy - arp_y) / b
Clb = Clb_wing + dihedral_low + fin_clb_arp
```

Do not globally replace every CG arm with an ARP arm. The arm that determines rotational inflow and the arm that determines a moment can have different roles.

Also, do not apply the correction using total `CYb`: your fuselage side force is already defined at the ARP. Moving it as though it were fin force would introduce another inconsistency.

The existing loader has an optional fin/wing `Clb` relation, but enabling `wing_body_cl_beta` also changes the local-regime roll model. It is **not merely a validation switch**. A generator-level force-and-arm invariant is the narrower first safeguard. Sources: [loader relation](https://github.com/bultodepapas/OpenRCsimulator/blob/e72d878b6b4a89209dfe1a992ba119921dcdd34c/app/physics/aircraft_data.gd#L2641-L2649) and [local-regime use](https://github.com/bultodepapas/OpenRCsimulator/blob/e72d878b6b4a89209dfe1a992ba119921dcdd34c/app/physics/aero.gd#L666-L671).

**Validation:** the final production-code witness passed **29 checks**, including both sideslip signs, rate symmetry, unchanged unrelated loads, and algebraic moment-datum translations.

---

## 2. The propeller crossflow tables omit the installed blade’s camber

The Extra installation specifies:

```text
zero_lift_angle_rad = -0.10223236266152576
```

That is approximately \(-5.8575^\circ\). The runtime annular model correctly includes this value:

\[
\alpha_{\mathrm{section}}=\beta-\phi-\alpha_0.
\]

However, the generator constructs the section dictionary used for `normal_force` and `pfactor_moment` without `zero_lift_angle_rad`. The Python mirror defaults the omitted parameter to zero. Consequently, the flight model combines **cambered-section thrust and torque** with crossflow tables derived from a **symmetric section**. Sources: [installation](https://github.com/bultodepapas/OpenRCsimulator/blob/e72d878b6b4a89209dfe1a992ba119921dcdd34c/app/data/glow/extra_61fx_2t.json#L203-L207), [generator mapping](https://github.com/bultodepapas/OpenRCsimulator/blob/e72d878b6b4a89209dfe1a992ba119921dcdd34c/research/extra-300/ex05/derive_physics.py#L493-L527), and [Python default](https://github.com/bultodepapas/OpenRCsimulator/blob/e72d878b6b4a89209dfe1a992ba119921dcdd34c/research/glow-engines/calibration_report.py#L470-L500).

This conflicts with the generator’s own stated method: deriving those coefficients from the same installed glow propeller.

### The discrepancy is substantial

I reproduced **all 44 shipped coefficient entries exactly** using the unmodified generator block. Adding only the omitted camber parameter produces:

| Advance ratio \(J\) | Stock \(C_N\) | Consistent \(C_N\) | Stock \(C_M\) | Consistent \(C_M\) |
|---:|---:|---:|---:|---:|
| 0.30 | 0.001884 | 0.002474 | 0.002999 | 0.005058 |
| 0.50 | 0.004456 | 0.006239 | 0.002978 | 0.006713 |
| 0.70 | 0.006712 | 0.010410 | 0.000957 | 0.006488 |
| 0.80 | 0.007221 | 0.012175 | 0.000000 | 0.005572 |

“Consistent” here means **the existing derivation using the installed section parameters**. It does not mean independently calibrated against an actual Extra propeller.

At \(J=0.5\):

- The stock normal-force coefficient is **28.6% below** the consistent result.
- The stock P-factor coefficient is **55.6% below** the consistent result.

At \(J=0.8\), the current generator clips the P-factor coefficient to zero while the same method with installed camber still produces a positive coefficient.

### An independent algebraic check

Substituting the generator’s expression for mean blade lift into its crossflow equations makes the coefficient differences simplify to:

\[
\Delta C_N
=
\frac{3J^2}{2\pi^2}\Delta C_T,
\]

\[
\Delta C_M
=
\frac{J}{2\pi}\Delta C_T.
\]

These identities apply before the nonnegative clamp and six-decimal rounding. The probe checks them independently of the table comparison, and includes a zero-camber control.

### What this means in dimensional loads

For \(12{,}000\) rpm, \(D=0.3048\ \mathrm m\), and \(J=0.5\):

\[
V_{\mathrm{axial}}=JnD=30.48\ \mathrm{m/s}.
\]

At a \(10^\circ\) disc-flow angle, the production load functions give:

| Quantity | Stock tables | Consistent-table diagnostic |
|---|---:|---:|
| Normal-force magnitude | 0.327244 N | 0.458185 N |
| P-factor moment magnitude | 0.066660 N·m | 0.150265 N·m |

For the vertical-crossflow case, the complete propulsion wrench changes by approximately **−0.08360 N·m in yaw** and **+0.04753 N·m in pitch**, including the normal-force arm.

**Shaft thrust and shaft torque remain byte-identical between these two table variants.** The runtime’s installed thrust model is already using camber correctly; the inconsistency is in the auxiliary coefficient generation. The production consumer is [the crossflow calculation in `propulsion.gd`](https://github.com/bultodepapas/OpenRCsimulator/blob/e72d878b6b4a89209dfe1a992ba119921dcdd34c/app/physics/propulsion.gd#L619-L651).

### Recommended repair

The immediate source correction is small:

```python
section = {
    "lift_slope_per_rad": gp["lift_slope"],
    "cd0": gp["cd0"],
    "induced_drag": gp["induced_drag"],
    "blades": gp["blades"],
    "zero_lift_angle_rad": gp.get("zero_lift_angle_rad", 0.0),
}
```

The durable cleanup is to use **one installation-to-section adapter**. The calibration reader already carries the optional camber field correctly; maintaining another hand-written parameter mapping allowed the two consumers to diverge. See [the existing reader](https://github.com/bultodepapas/OpenRCsimulator/blob/e72d878b6b4a89209dfe1a992ba119921dcdd34c/research/glow-engines/calibration_report.py#L77-L82).

Regenerate the owning aircraft data and dependent identities through the established pipeline.

The current installation test passed **17/17 checks**, but its crossflow expectations read the same shipped tables. That checks load assembly correctly; it cannot detect this particular generator-to-installation disagreement. Add a separate invariant connecting the generated tables to the installed section.

**Validation:** the new production-load witness passed **46 checks**, including both crossflow directions, shaft-aligned flow, zero RPM, and Python/runtime thrust agreement.

---

## 3. The Extra recomputes identical mass properties within each physics stage

This is the most promising new CPU optimization found in the bounded review.

The call sequence is:

1. `point()` calls `_stage_mass_context()` and computes mass properties.
2. Stock Extra has no optional `fuel_feed` block, so that result is not returned as `evaluation.mass`.
3. `evaluate()` finds no mass result and calls `properties()` again.

The repeated work includes CG, six inertia components, and the inverse inertia tensor, plus associated arrays and dictionaries. Sources: [first evaluation](https://github.com/bultodepapas/OpenRCsimulator/blob/e72d878b6b4a89209dfe1a992ba119921dcdd34c/app/physics/glow/flight.gd#L445-L462), [conditional return](https://github.com/bultodepapas/OpenRCsimulator/blob/e72d878b6b4a89209dfe1a992ba119921dcdd34c/app/physics/glow/flight.gd#L569-L583), [recomputation](https://github.com/bultodepapas/OpenRCsimulator/blob/e72d878b6b4a89209dfe1a992ba119921dcdd34c/app/physics/glow/flight.gd#L666-L682), and [mass/inertia calculation](https://github.com/bultodepapas/OpenRCsimulator/blob/e72d878b6b4a89209dfe1a992ba119921dcdd34c/app/physics/mass_inventory.gd#L228-L276).

On the ordinary four-stage RK path:

\[
4 \times 240 = \boxed{960}
\]

That is **960 duplicated mass-property evaluations per simulated second**, excluding event trials, observers, endpoints, and extra contact substeps. It is an operation count, not a measured speedup.

A qualifying soft-hull evaluation near the flat-ground reference can calculate the properties a third time. The ground function already accepts a properties argument, but this call path does not supply it. See [`_ground_evaluation()`](https://github.com/bultodepapas/OpenRCsimulator/blob/e72d878b6b4a89209dfe1a992ba119921dcdd34c/app/sim/flight_session.gd#L4373-L4393).

### What the prototype establishes

The included experimental patch reuses the result only when:

- There is no fuel-feed or feed-line block.
- Line fuel is exactly zero.
- Fuel is finite and strictly between zero and capacity, inclusive of capacity.

Other paths retain the existing recomputation. The default public `point()` result remains unchanged.

The patch reduces:

- Ordinary airborne stages: **two calculations to one**.
- Qualifying soft-hull stages: **three calculations to two**.

The further ground reuse is a separate, unimplemented opportunity.

The baseline and candidate matched for:

- 90 direct stages: 72 successful and 18 refused.
- Default public `point()` results for those cases.
- 48 accepted airborne/engine-cut ticks.
- 16 runway ticks.
- Four near-exhaustion ticks, including two event records.
- The existing glow-flight physics program: **110 checks passed on both versions**.

### How I would integrate it

Use one private, validated **stage-local context** and pass it to the consumers that need those properties. Preserve the existing refusal and callback ordering. Do not retain this result across RK stages or fuel events.

The prototype still needs qualification for explicit `point(..., true)` callers, supported callback/mutation behavior, native/reference parity, recordings, checkpoints, replay, and other aircraft configurations. A controlled full-session benchmark should follow those checks.

This opportunity is distinct from the previously audited airflow, station-geometry, and stage-validation reuse.

---

## 4. Loft indexing cuts mesh storage substantially, but did not speed up construction

The Extra’s `_loft()` emits repeated triangle corners and commits them directly. The experimental change is:

```gdscript
st.index()
return st.commit()
```

The insertion is immediately before the existing commit in [`extra_300s_model.gd`](https://github.com/bultodepapas/OpenRCsimulator/blob/e72d878b6b4a89209dfe1a992ba119921dcdd34c/app/aircraft/extra_300s_model.gd#L71-L105).

### Measured storage

| Quantity | Stock | Indexed candidate |
|---|---:|---:|
| Stored vertices across distinct mesh resources | 53,204 | 10,878 |
| Serialized ArrayMesh vertex/attribute/index buffers | 1,317,552 bytes | 373,176 bytes |
| Same buffers after custom-paint preparation | 1,825,800 bytes | 1,475,672 bytes |
| Instance triangles | 19,502 | 19,502 |

The stock buffer reduction is **944,376 bytes, or 71.68%**—about **0.901 MiB per model** for the measured buffers.

These are inspected engine buffer lengths. They are not measurements of total process RAM or actual GPU allocation.

The correctness probe re-expanded the indices and compared every present vertex attribute, triangle order, mesh path, and local transform. It repeated the comparison after custom-paint preparation. Those comparisons passed with exact Godot value equality.

The paint adapter expands its target triangles, which explains why the saving falls to **19.18%** after custom preparation. That behavior is visible in [the adapter’s mesh preparation](https://github.com/bultodepapas/OpenRCsimulator/blob/e72d878b6b4a892ba119921dcdd34c/app/aircraft/procedural_skin.gd#L120-L150).

### The timing result changes the recommendation

In the headless Linux experiment, after warmup and 16 alternating baseline/candidate pairs:

- Baseline median `build()`: **96.19 ms**
- Indexed median `build()`: **103.24 ms**
- Median paired change: **+8.5%**

The samples were noisy, but they do **not** support a faster-construction claim.

I would treat this as a memory optimization. If adopted, indexing once in an owned preparation lifecycle—or sharing verified immutable mesh resources—could avoid paying the work on every fresh construction. Per-instance nodes, hinges, and paint overrides still need separate ownership.

I also rejected a tempting alternative: indexing after committing and reading the mesh back through `SurfaceTool.create_from()`. That introduced another encode/decode pass and changed decoded normals and tangents. The supplied candidate indexes before commit.

---

## 5. Custom paint loses the stock shader sharing

The stock Extra finish already correctly shares **one shader among five material variants**. The duplication is in the custom-paint path.

`_prepare_material()` creates a fresh `Shader` for each painted surface. Then `paint()` creates another shader for each distinct prepared material. The real adapter calls in the probe produced:

- **14 prepared shader objects with one identical source string**
- **14 final shader objects with one identical source string** for the representative opaque, untextured paint record

Sources: [shader preparation and painting](https://github.com/bultodepapas/OpenRCsimulator/blob/e72d878b6b4a89209dfe1a992ba119921dcdd34c/app/aircraft/procedural_skin.gd#L302-L364) and [custom-skin material-copy selection](https://github.com/bultodepapas/OpenRCsimulator/blob/e72d878b6b4a89209dfe1a992ba119921dcdd34c/app/aircraft/custom_skin.gd#L181-L215).

The focused improvement is to share immutable `Shader` resources by exact generated source and relevant texture/alpha variant, while keeping separate `ShaderMaterial` uniforms and instance ownership.

This is a demonstrated resource-allocation opportunity. It does not prove 28 GPU compilations or a particular frame-time saving. The actual `.orskin` import lifecycle and graphical performance were not measured.

---

## 6. The rendered propeller’s trailing edge travels first

The blade builder places the +X blade’s leading edge toward +Y. The finite-glow render path rotates the propeller about local **−Z** for positive RPM.

For a point on +X:

\[
\mathbf v=\boldsymbol\omega\times\mathbf r
\]

therefore points toward −Y. The authored leading-edge direction and the motion oppose one another. Sources: [blade geometry](https://github.com/bultodepapas/OpenRCsimulator/blob/e72d878b6b4a89209dfe1a992ba119921dcdd34c/app/aircraft/extra_300s_model.gd#L661-L685), [glow spin sign](https://github.com/bultodepapas/OpenRCsimulator/blob/e72d878b6b4a89209dfe1a992ba119921dcdd34c/app/render/airplane.gd#L143-L149), and [rendered propeller rotation](https://github.com/bultodepapas/OpenRCsimulator/blob/e72d878b6b4a89209dfe1a992ba119921dcdd34c/app/main.gd#L3170-L3175).

The witness located the leading and trailing points in the actual generated mesh and evaluated:

\[
(\mathbf p_{\mathrm{LE}}-\mathbf p_{\mathrm{TE}})
\cdot
(\boldsymbol\omega\times\mathbf p_{\mathrm{mid}}).
\]

It was negative under the production spin direction and positive under the reversed-spin control.

Correct the blade’s leading-edge, camber, and pitch geometry together, keeping the physical rotation convention consistent. Then inspect stopped appearance, rotation, blur, and strike visuals.

This is a presentation defect. It does not establish an error in the simulated shaft or thrust signs.

---

## Validation, exclusions, and implementation order

The package contains **13 successful checked-run receipts**, including the 46-check propeller witness, 29-check aerodynamic witness, mesh comparisons, blade-direction check, stage-parity pair, and relevant existing tests. Every selected receipt reports completion without engine diagnostics.

The tests were headless and used the pinned Linux Godot build. I did not run the complete application suite, a rendered flight, target-device GPU measurements, native-backend qualification, or a full recording/replay campaign.

I excluded findings already covered by the ledger or project notes, including the earlier reverse-flow discontinuity, trim/failsafe issues, existing airflow/cache opportunities, missing wing propwash, and known knife-edge/hammerhead limitations. A coasting-propeller strike omission was reproduced, but **GP-17 already plans that coverage**, so it is not counted as a new discovery.

**I would implement E300-01 and E300-02 first.** They are generator/consumer contract errors that can distort later tuning. Then complete the mass-reuse parity work and measure the actual session cost. Treat mesh indexing as a deliberate memory tradeoff, and handle shader sharing and blade handedness as separate, focused changes.