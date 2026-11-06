## Wind audit results

**I found three new software correctness issues, two newly quantified continuity problems in the helicopter rotor laws, and two concrete optimization opportunities.** The first fixes I would prioritize are preserving independent weather values during editing and correcting native checkpoint preparation order.

The experiments used commit [`d0b672b`](https://github.com/bultodepapas/OpenRCsimulator/commit/d0b672b09663226ff8b8ac4f43eae8643c77a8c4). While the review was running, `main` advanced to `c5187df`. I checked the intervening changes: **the responsible source files remain unchanged**, and the newly added audit documents do not duplicate these specific findings. Execution results remain tied to the original revision. [Closing source comparison](https://github.com/bultodepapas/OpenRCsimulator/compare/d0b672b09663226ff8b8ac4f43eae8643c77a8c4...c5187df3502926a08c8014d330272160a0e002b8).

I began with `external Audits/CONSOLIDATED-AUDITS.md`, then checked the dedicated wind reference and roadmap. At closing, I also reviewed the expanded A1–A19 audit ledger and relevant new helicopter/UI reports. Previously reported issues are excluded from the new-finding count. [Consolidated audits](https://github.com/bultodepapas/OpenRCsimulator/blob/c5187df3502926a08c8014d330272160a0e002b8/external%20Audits/CONSOLIDATED-AUDITS.md) · [Wind reference](https://github.com/bultodepapas/OpenRCsimulator/blob/d0b672b09663226ff8b8ac4f43eae8643c77a8c4/docs/WIND-ATMOSPHERE-REFERENCE.md) · [Wind roadmap](https://github.com/bultodepapas/OpenRCsimulator/blob/d0b672b09663226ff8b8ac4f43eae8643c77a8c4/docs/WIND-ATMOSPHERE-ROADMAP.md).

### Deliverables

- [OpenRC_Wind_Audit_d0b672b.txt](https://chatgpt.com/library?file_id=libfile_87749680674c81919ed55aae7338991e&account_id=personal) — complete report, equations, code locations, repair proposals, and verification requirements.
- [OpenRC_Wind_Evidence_d0b672b.zip](https://chatgpt.com/library?file_id=libfile_cd6d1b0d17208191b985a7be01dc1a90&account_id=personal) — probes, raw checked logs, source hashes, reproduction instructions, closing comparison, and experimental thermal patches.

This was a read-only review of production code.

### Priorities and evidence

| ID | Priority | Finding | Evidence |
|---|---|---|---|
| **WNEW-01** | P2 | Editing one spatial-weather field changes other independent wind inputs | Production controls and actual field samples |
| **WNEW-02** | P2 | Native checkpoint restoration prepares against the previous OU layout | Real reference sessions and production adapter; native outcome source-derived |
| **WNEW-03** | P2, model continuity | Tail wake changes discontinuously when axial flow crosses induced speed | Rotor components, coupled loads, standalone RK4 |
| **WNEW-04** | P2, model continuity | Main-rotor flap rate jumps near pure crosswind with axial flow | Limit analysis, production components, standalone RK4 |
| **WNEW-05** | P3 | Valid inward-drifting thermals are rejected | Validation/composition probes and isolated candidate |
| **WOPT-01** | P3 | Thermal queries allocate an unused result and evaluate the same sine twice | Exact-result comparisons and paired component timing |
| **WOPT-02** | P3 | Overlay wind/air sampling repeats the same datum query | Provider-call accounting and sampled output equivalence |

P2 here means a correctness or numerical-model issue worth addressing. The evidence does **not** establish a catastrophic flight failure or justify a P0/P1 classification.

---

## 1. Spatial-weather edits silently replace independent wind values

**Affected code:** [`spatial_weather_controls.gd:216–257`](https://github.com/bultodepapas/OpenRCsimulator/blob/d0b672b09663226ff8b8ac4f43eae8643c77a8c4/app/ui/spatial_weather_controls.gd#L216-L257), particularly the `profile_changed` and `gust_edited` branches.

This finding has two related mechanisms.

### A. Changing roughness can rotate the unshown upper wind

The schema admits an independently authored `free_air_wind_ned_mps`. However, editing reference speed, direction, height, or roughness reconstructs that vector using `_free_air_vector()`.

The reconstruction extrapolates the reference profile:

\[
U_\infty
=
U_{\rm ref}
\frac{\ln((z_\infty-d)/z_0)}
{\ln((z_{\rm ref}-d)/z_0)}
\]

and forces its direction to the reference wind direction. That is a reasonable rule for an explicitly linked profile, but the independent upper vector is not exposed by those controls. [Reconstruction code](https://github.com/bultodepapas/OpenRCsimulator/blob/d0b672b09663226ff8b8ac4f43eae8643c77a8c4/app/ui/spatial_weather_controls.gd#L528-L544).

I reproduced this with the unmodified production controls:

| Quantity | Before | After changing only roughness |
|---|---:|---:|
| Reference wind | 3 m/s FROM 090° | Unchanged |
| Roughness length | 0.03 m | 0.02 m |
| Upper wind, NED | `[-4, 0, 0]` m/s | Approximately `[0, -4.1115351394, 0]` m/s |
| Actual wind at 100 m AGL | `[-4, 0, 0]` m/s | Same changed upper vector |

Both configurations validate. **A roughness edit rotates the upper wind by 90°**, changing the previously accepted custom field. An aircraft in that region would encounter the altered wind and shear; the experiment demonstrated provider samples, rather than a flown trajectory.

### B. Changing one gust’s timing can alter its direction or precision

The editor derives a displayed intensity from the first gust vector. It usually rounds that magnitude to two decimals, retaining full precision when rounding would produce zero. Editing **any** of intensity, start time, or duration then reconstructs the vector from the displayed magnitude and the reference direction. [Gust reconstruction](https://github.com/bultodepapas/OpenRCsimulator/blob/d0b672b09663226ff8b8ac4f43eae8643c77a8c4/app/ui/spatial_weather_controls.gd#L236-L257) · [Formatting behavior](https://github.com/bultodepapas/OpenRCsimulator/blob/d0b672b09663226ff8b8ac4f43eae8643c77a8c4/app/ui/spatial_weather_controls.gd#L618-L626).

For a **single** gust:

- Original amplitude: `[-1, 0, 0]` m/s.
- Reference direction: FROM 090°.
- Sole edit: duration from 4 to 5 seconds.
- Returned amplitude: approximately `[0, -1, 0]` m/s.
- Wind at the respective gust peaks changes from `[-1, -3, 0]` to `[0, -4, 0]` m/s.

There is also a case using ordinary component operations from the shipped light-breeze preset: enter intensity `0.123456`, reopen the returned draft, and edit only duration. The displayed `0.12` becomes the new actual magnitude—a **2.80% reduction**.

This is distinct from prior F16, which already reports replacement of a multi-event agenda. These examples contain only one event and lose no event count; they alter its independent vector or precision.

### Concrete repair

Treat the editor as a patch over the original configuration:

- Preserve `free_air_wind_ned_mps` unless an explicit upper-wind control or a visible, represented linkage owns its replacement.
- For a single gust, change only the edited keys. A time-only edit must retain the original NED amplitude exactly.
- Keep authoritative numeric values separate from rounded display text.
- For intensity edits, preserve the existing direction unless the user deliberately changes it; define the zero-magnitude case explicitly.

The dialog reads and validates these drafts before publication, so the altered values can pass through the normal Apply path. That publication/save path was source-traced; a clean full-app click/save/reload run was not performed. [Apply path](https://github.com/bultodepapas/OpenRCsimulator/blob/d0b672b09663226ff8b8ac4f43eae8643c77a8c4/app/ui/weather_dialog.gd#L845-L863).

**Verification:** no-op round trips, numerically equivalent text edits, transverse upper wind, roughness/reference edits, single-gust timing changes, high-precision amplitudes, explicit intensity changes, Apply/Cancel, persisted reload, and provider samples before/after.

---

## 2. Native checkpoint restoration uses the previous turbulence-layout cache

**Affected code:** [`flight_session.gd:6104–6141`](https://github.com/bultodepapas/OpenRCsimulator/blob/d0b672b09663226ff8b8ac4f43eae8643c77a8c4/app/sim/flight_session.gd#L6104-L6141), [`weather_adapter.gd:55–58`](https://github.com/bultodepapas/OpenRCsimulator/blob/d0b672b09663226ff8b8ac4f43eae8643c77a8c4/app/sim/native/weather_adapter.gd#L55-L58), and the native weather guard.

The restore sequence stages the candidate:

1. Auxiliary state.
2. Modes and inputs.
3. Weather.
4. Backend preparation.

But `_turbulence_aux_index` still contains the **destination session’s old value** during preparation. It is assigned the restored value only in the successful restore’s postcommit callback.

That creates two different failures:

| Transition | Preparation problem | Consequence |
|---|---|---|
| Steady wind → OU turbulence | Candidate needs an OU block, but cached index remains `-1` | Adapter refuses the candidate layout |
| OU turbulence → steady wind | Guard captures the old positive index | Postcommit changes it to `-1`, invalidating the newly prepared guard |

The C++ guard captures `turbulence_aux_index` and requires it to remain equal. The session’s native pre-step rejects a configuration that no longer matches. [Guard comparison](https://github.com/bultodepapas/OpenRCsimulator/blob/d0b672b09663226ff8b8ac4f43eae8643c77a8c4/research/native-kernel/src/nk_weather_guard.hpp#L364-L381) · [Pre-step refusal](https://github.com/bultodepapas/OpenRCsimulator/blob/d0b672b09663226ff8b8ac4f43eae8643c77a8c4/app/sim/flight_session.gd#L5037-L5042).

### What was executed

Using real `FlightSession` instances and **v2 flight checkpoints**, one with steady wind and one with OU turbulence:

- Reference restoration succeeded in both directions.
- Reproducing the production pre-backend staging made `NativeWeather.prepare` reject the OU candidate with the old `-1` index.
- Assigning the candidate index made that preparation succeed.
- In reverse, preparation succeeded with old index `14`; the guard matched initially and failed after the postcommit change to `-1`.

**The native extension itself was unavailable.** Therefore, the native restore refusal and subsequent native-tick refusal are source-derived outcomes supported by the executed adapter behavior—not claimed end-to-end native runs.

### Concrete repair

Stage the derived cache with the other candidate fields, before preparing the backend:

```gdscript
_turbulence_aux_index = expected_aux - 7 if turbulent else -1
_prepare_stage_backend(
    float(snapshot.tick) * float(snapshot.dt),
    str(recorded_backend.backend)
)
```

The existing transaction already includes this owner field in its rollback set. Preserve that rollback and the exact backend identity requirement; weakening the guard or silently falling back would conceal the inconsistent preparation. [Owner rollback fields](https://github.com/bultodepapas/OpenRCsimulator/blob/d0b672b09663226ff8b8ac4f43eae8643c77a8c4/app/sim/flight_session.gd#L1076-L1086).

**Verification:** actual native steady↔OU restores at tick zero and later ticks, a following accepted tick, exact continuation/replay, matching RNG/interval/layout/backend identities, and refused-restore rollback. Use self-describing v2 flight checkpoints: legacy calm-v1 has an earlier restriction that can prevent reaching this defect.

---

## 3. Tail wake has a finite discontinuity at \(w=v_i\)

**Affected code:** [`tail_rotor.gd:68–77`](https://github.com/bultodepapas/OpenRCsimulator/blob/d0b672b09663226ff8b8ac4f43eae8643c77a8c4/app/physics/rotorcraft/tail_rotor.gd#L68-L77), propagated to both tail surfaces by [`aerodynamic_stage.gd:115–137`](https://github.com/bultodepapas/OpenRCsimulator/blob/d0b672b09663226ff8b8ac4f43eae8643c77a8c4/app/physics/rotorcraft/aerodynamic_stage.gd#L115-L137).

The current wake factor is:

\[
K =
\begin{cases}
1.5\,\operatorname{clamp}
\left(
\dfrac{u/(v_i-w)-g_i}{g_f-g_i},0,1
\right), & v_i>w,\\[6pt]
0, & v_i\le w.
\end{cases}
\]

The tail flow uses:

\[
w_{\rm tail}=w+lq-Kv_i.
\]

For fixed \(u>0\) and \(v_i>0\):

\[
\lim_{w\to v_i^-}K=1.5,
\qquad
K(v_i)=0.
\]

Consequently, the wake contribution changes by a finite \(1.5v_i\) for an arbitrarily small change in axial airflow.

This affects the tail rotor **and** the fin/horizontal stabilizer receiving the same wake factor.

### Reproduced effect

For the stock X-Cell, with main speed \(167\ \mathrm{rad/s}\), \(u=10\ \mathrm{m/s}\), \(v_i=4\ \mathrm{m/s}\), and \(w=4\pm10^{-12}\ \mathrm{m/s}\):

- \(K\) changes from `1.5` to `0`.
- \(w_{\rm tail}\) changes from approximately `−2` to `+4 m/s`.

In the constructed complete coupled stage with neutral sticks, the total loads changed as follows:

| Quantity | Just below the boundary | Just above | Difference |
|---|---:|---:|---:|
| \(F_z\), N | −168.516095 | −169.618595 | −1.102500 |
| \(M_y\), N·m | +0.223099 | −0.559781 | −0.782879 |
| \(M_z\), N·m | −1.170260 | −1.113380 | +0.056880 |

The \(u=0\) and reverse-flow controls remained continuous around the same boundary.

Both constructed states completed 24 standalone 240-Hz RK4 steps with the supplied wind held fixed. The first-step pitch-rate difference was approximately \(0.00156\ \mathrm{rad/s}\). These were coupled integrator calls, not accepted helicopter-session ticks or a time-evolving gust flight.

### Interpretation and improvement

A smooth vertical gust can cross this boundary while induced velocity evolves. The force law then supplies a finite jump, making the response sensitive to where RK stages fall relative to the boundary.

**The underlying piecewise law is already documented in HELI-06.** The new finding is its one-sided limit and quantified propagation into the combined wrench. It is a numerical limitation of an acknowledged approximation, not a newly discovered transcription error. [Existing model disclosure](https://github.com/bultodepapas/OpenRCsimulator/blob/d0b672b09663226ff8b8ac4f43eae8643c77a8c4/docs/research/helicopter/HELI-06/README.md#L48-L66).

The repair should define a supported wake geometry and continuity policy. A continuous vector/angular wake-direction model with finite overlap is a candidate architecture, but deleting the gate or adding an epsilon to the denominator does not establish physical correctness.

**Verification:** independent one-sided tests in \(u,w,v_i\), signed-flow and body-rate cases, separate tail/fin/stabilizer contributions, forced crossings with timestep refinement, full-session rollback/continuation, and reference/native comparison. Any changed physical law should have an explicit version and compatibility policy.

---

## 4. Main-rotor flap rate jumps near pure crosswind with axial flow

**Affected code:** [`main_rotor.gd:178–190`](https://github.com/bultodepapas/OpenRCsimulator/blob/d0b672b09663226ff8b8ac4f43eae8643c77a8c4/app/physics/rotorcraft/main_rotor.gd#L178-L190).

Define:

\[
\mu_x=\frac{u}{\Omega R},\quad
\mu_y=\frac{v}{\Omega R},\quad
\mu_z=\frac{w}{\Omega R},\quad
\mu=\sqrt{\mu_x^2+\mu_y^2}.
\]

In the **unblended standard rotor law**, the axial contribution to longitudinal flap rate is:

\[
\dot a_{1,\rm axial}
=
\frac{C(\mu)\operatorname{sign}(\mu_x)\mu_z}{\tau},
\]

where

\[
C(\mu)=
\frac{16K_\mu\mu^2}
{(1-\mu^2/2)(8\mu+a\sigma)},
\qquad
\tau=\frac{16}{\gamma_{\rm flybar}\Omega}.
\]

For nonzero lateral and axial flow, \(C(|\mu_y|)\) remains finite as \(\mu_x\to0\). Therefore:

\[
\dot a_1(0^+)-\dot a_1(0^-)
=
\frac{2C(|\mu_y|)\mu_z}{\tau}.
\]

At exactly zero, `signf(0)` removes the contribution altogether.

The startup blend scales this jump by \(1-\texttt{low_weight}\); the fully weighted low-RPM law omits the term. The executed \(167\ \mathrm{rad/s}\) examples are in the unblended standard regime. [Low-RPM branching](https://github.com/bultodepapas/OpenRCsimulator/blob/d0b672b09663226ff8b8ac4f43eae8643c77a8c4/app/physics/rotorcraft/main_rotor.gd#L120-L139) · [Blending](https://github.com/bultodepapas/OpenRCsimulator/blob/d0b672b09663226ff8b8ac4f43eae8643c77a8c4/app/physics/rotorcraft/main_rotor.gd#L304-L314).

### Reproduced effect

For the stock X-Cell, \(\Omega=167\ \mathrm{rad/s}\), \(R=0.775\ \mathrm m\), zero flap angles/rates/cyclic, \(v=5\ \mathrm{m/s}\), and \(w=3\ \mathrm{m/s}\):

| Forward air velocity \(u\) | Longitudinal flap rate |
|---:|---:|
| \(-10^{-12}\ \mathrm{m/s}\) | \(-0.0016197764445\ \mathrm{rad/s}\) |
| \(0\) | \(0\) |
| \(+10^{-12}\ \mathrm{m/s}\) | \(+0.0016197764445\ \mathrm{rad/s}\) |

Here \(\mu\approx0.03863\). Setting either lateral flow or axial flow to zero removes this particular jump.

A constructed high-bound case, \(v=18,\ w=8\ \mathrm{m/s}\), gives:

\[
\mu\approx0.13908,
\qquad
\Delta\dot a_1\approx0.04693253\ \mathrm{rad/s}
=2.689^\circ/\mathrm{s}.
\]

That is below the code’s \(\mu<0.15\) indicator, although the indicator does not physically qualify this combined sideways/axial-flow condition. Valid legacy settings can construct the corresponding instantaneous flow using 15 m/s mean wind, a 3 m/s horizontal gust, and an 8 m/s upward gust.

The complete standalone RK4 experiment produced an \(a_1\) difference of about \(3.14\times10^{-5}\) radians after one step and \(1.23\times10^{-5}\) radians after 24 steps. Both runs remained accepted by the integrator. The short trace does not demonstrate a visible upset or growing instability.

### Interpretation and improvement

HELI-05 already identifies `sign(u)` as an inferred backward-flight convention and explicitly sets pure sideflow to zero. The new result is that the opposite limiting values do not approach that exact-sideflow result. [Existing disclosure](https://github.com/bultodepapas/OpenRCsimulator/blob/d0b672b09663226ff8b8ac4f43eae8643c77a8c4/docs/research/helicopter/HELI-05/README.md#L31-L42).

A possible mathematical direction is to replace the discontinuous sign dependence with a consistently derived flow-direction projection. For example, the **complete product**

\[
C(\mu)\frac{\mu_x}{\mu}\frac{\mu_z}{\tau}
\]

can be defined as zero at \(\mu=0\), because \(C(\mu)=O(\mu^2)\) for fixed positive rotor speed. The ratio \(\mu_x/\mu\) itself has no direction-independent zero-flow limit.

That expression is only a candidate. The longitudinal and lateral corrections, rotor rotation conventions, and forward/backward source anchors need a joint physical derivation.

**Verification:** two-sided \(u\) sweeps with nonzero \(v\), positive/negative \(w\), zero-axis controls, low-RPM transitions, intentional boundary crossings at 240/480/960 Hz, and supported session/checkpoint/native comparisons.

The newer A15 H02 report describes a **different** strong-gust problem: a low-RPM blend-domain gap causing startup refusal. I excluded that already reported defect from this count. [H02](https://github.com/bultodepapas/OpenRCsimulator/blob/c5187df3502926a08c8014d330272160a0e002b8/external%20Audits/helicopter-controls-contact-trim-audit-3e652a8.md#L95-L168).

---

## 5. Thermal containment rejects valid inward drift

**Affected code:** [`wind_thermal_field.gd:319–340`](https://github.com/bultodepapas/OpenRCsimulator/blob/d0b672b09663226ff8b8ac4f43eae8643c77a8c4/app/physics/wind_thermal_field.gd#L319-L340).

The validator uses, independently for north and east:

\[
|c_0|+|v|T+5R\le L.
\]

This is a sufficient triangle-inequality bound, but it treats inward travel as outward expansion.

For the implemented affine center motion,

\[
c(t)=c_0+vt,\qquad 0\le t\le T,
\]

the exact real-arithmetic extremum is:

\[
\max_t|c(t)|=\max(|c_0|,\ |c_0+vT|).
\]

The appropriate containment bound is therefore:

\[
\boxed{\max(|c_0|,\ |c_0+vT|)+5R\le L}.
\]

### Counterexample

Use:

- Half-extent \(L=1000\ \mathrm m\).
- Initial center \(c_0=600\ \mathrm m\).
- Drift \(v=-2\ \mathrm{m/s}\).
- Lifetime \(T=360\ \mathrm s\).
- Radius \(R=35\ \mathrm m\).

The center moves from 600 to −120 m.

The actual support bound is:

\[
\max(600,120)+175=775\ \mathrm m.
\]

The current validator computes:

\[
600+720+175=1495\ \mathrm m
\]

and refuses the cell.

I reproduced rejection through thermal resolution/build, spatial composition, and weather validation. Four inward cardinal tracks and one origin-crossing track fit but are rejected. Three truly outside-domain controls are also rejected.

### Concrete repair

For each horizontal axis:

```gdscript
var c0 := float(center[axis])
var c1 := c0 + float(drift[axis]) * duration
var reach := maxf(absf(c0), absf(c1)) + 5.0 * radius
```

Compare `reach` with the corresponding half-extent.

An isolated two-expression correction admitted all five contained tracks and retained rejection of the invalid controls. For each accepted track, 361 samples through its lifetime matched byte-for-byte between the corrected 1,000 m domain and an otherwise identical 10,000 m domain. The velocity equations were unchanged.

**Impact:** usable authored thermal scenarios are unnecessarily refused. This is a lower-priority admission issue.

**Verification:** both axes, zero/outward/inward drift, origin crossings, exact boundaries and adjacent representable values. The endpoint argument is exact in real arithmetic; binary64 boundary acceptance should be explicitly tested before integration.

---

## 6. Thermal queries can eliminate work without changing the field

**Affected code:** [`wind_thermal_field.gd:250–306`](https://github.com/bultodepapas/OpenRCsimulator/blob/d0b672b09663226ff8b8ac4f43eae8643c77a8c4/app/physics/wind_thermal_field.gd#L250-L306).

Two small costs occur in every contributing cell query:

1. A zero `PackedFloat64Array` is allocated at entry, then discarded when the actual result is allocated.
2. `M.sin_(vertical_wave)` is evaluated twice.

The candidate constructs zero arrays only on early-return paths and uses:

```gdscript
var vertical_sine := M.sin_(vertical_wave)
var vertical_value := peak * vertical_sine * vertical_sine
```

This preserves multiplication order and fresh result ownership. It introduces no persistent cache or approximation.

### Evidence

**22,048 checks passed**, including exact structured-result and packed-array byte comparisons over:

- Zero, one, four, and sixteen configured cells.
- 20,000 seeded random position/time queries.
- Height, lifetime, and radial-support boundaries.
- Zero-flow and invalid-input cases.

The paired benchmark warmed both implementations, alternated order, and used 24 pairs of 8,192-query batches for each workload:

| Active cells | Median baseline | Median candidate | Median paired reduction |
|---:|---:|---:|---:|
| 1 | 5.286 µs/query | 4.847 µs/query | 9.07% |
| 4 | 14.101 µs/query | 12.765 µs/query | 9.74% |

The candidate was faster in 21/24 and 23/24 pairs, respectively. Host variation was substantial, so these are **component measurements, not an FPS prediction**.

The dependable implementation claim is narrower: one discarded packed-array allocation and one duplicate sine evaluation disappear per contributing cell query.

**Verification before integration:** relevant provider/regression and replay gates in the actual app, native/reference law agreement, and complete-session profiling if the change is being justified by user-visible performance. The experimental patch is included in the archive.

---

## 7. The overlay repeats a wind query already available in its air result

**Affected code:** [`overlay_manager.gd:551–565`](https://github.com/bultodepapas/OpenRCsimulator/blob/d0b672b09663226ff8b8ac4f43eae8643c77a8c4/app/render/overlays/overlay_manager.gd#L551-L565), [`flight_session.gd:662–671`](https://github.com/bultodepapas/OpenRCsimulator/blob/d0b672b09663226ff8b8ac4f43eae8643c77a8c4/app/sim/flight_session.gd#L662-L671), and `wind_aircraft_flow.gd`.

The snapshot sequence calls:

```gdscript
session.wind_at(time_s)
session.air_data(s, time_s)
```

For spatial weather, `air_data()` invokes `WindFlow.stage_air()`, whose first query repeats the same accepted datum and time. The successful air receipt already retains a detached reference-wind value in its spatial sampler. [Datum query](https://github.com/bultodepapas/OpenRCsimulator/blob/d0b672b09663226ff8b8ac4f43eae8643c77a8c4/app/physics/wind_aircraft_flow.gd#L270-L295) · [Retained sample](https://github.com/bultodepapas/OpenRCsimulator/blob/d0b672b09663226ff8b8ac4f43eae8643c77a8c4/app/physics/wind_aircraft_flow.gd#L67-L84).

A checked harness using the unmodified flow implementation reduced provider calls from **11 to 10 in this isolated datum-wind plus stage-air sequence**. It used a synthetic station model and the real spatial field across 8/24/64 modes and three times. The compared wind and selected air fields were byte-identical.

This is not the total count for a complete overlay refresh: other accessors can make additional queries. Invalid-datum/station controls tested stage refusal and an explicitly simulated fallback, rather than the actual overlay fallback.

### Concrete repair

Provide an explicit observer/session snapshot accessor that returns both air data and its already sampled datum wind.

Preserve these conditions:

- Reuse only within the same state/time/provider snapshot.
- Keep the separate datum fallback when another aircraft station makes the complete air result invalid.
- Preserve legacy and pending-reset behavior.
- Retain full station validation.
- Avoid exposing mutable internal receipt state.

A datum-only `Air.compute()` replacement would change behavior by skipping station validation. Cross-frame or cross-stage caching would introduce a different correctness problem.

This is a measured operation-count reduction, with no timing or FPS claim. It is distinct from the already reported downwash reuse, flap accessor, and general station-batching opportunities.

---

## What the broader wind trace established

The basic frame convention is coherent in the traced paths:

\[
\mathbf W_{\rm NED}
=
[-U\cos\theta,\,-U\sin\theta,\,0]
\]

for a wind **FROM** angle \(\theta\), and

\[
\mathbf V_{\rm air,body}
=
\mathbf V_{\rm body}
-
R_{\rm body\to NED}^{T}\mathbf W_{\rm NED}.
\]

Upward gusts use negative Down. The state being integrated is ground-relative, while aerodynamic pressure and angles use relative airflow. I did not establish a new universal direction-sign error or duplicate wind force. [Frame and flow contract](https://github.com/bultodepapas/OpenRCsimulator/blob/d0b672b09663226ff8b8ac4f43eae8643c77a8c4/docs/WIND-ATMOSPHERE-REFERENCE.md#L24-L38).

The source trace covered generation/configuration, `WindField`, `Environment`, session sampling, fixed-wing stations and propulsion, helicopter main-hub/tail/airframe integration, and implemented feedback.

Several design properties are worth preserving:

- OU randomness belongs to the simulation owner; ordinary RK/render queries interpolate a committed interval rather than drawing fresh noise.
- Spatial queries use position and simulation time.
- Station-domain failures are propagated.
- Helicopter main and tail rotors receive relative airflow in the supported uniform-weather path.
- Provider, state, RNG, and rollback ownership must remain intact when optimizing. [Session sampling and OU interval](https://github.com/bultodepapas/OpenRCsimulator/blob/d0b672b09663226ff8b8ac4f43eae8643c77a8c4/app/sim/flight_session.gd#L596-L654).

I excluded the earlier findings on cloud following, nonlocal cues, windsock cadence, finite domains/horizons, nominal turbulence calibration, volume-versus-mass-flux continuity, helicopter weather exclusions, experimental multirotor simplifications, terrain-flow absence, and launch initialization. Those remain owned by the existing wind reference and roadmap.

## Verification performed

The six existing focused provider suites completed **33,219 checks**:

| Suite | Checks |
|---|---:|
| Wind field | 66 |
| OU turbulence | 29 |
| Balanced thermal field | 57 |
| Spatial wind field | 155 |
| Spatial gust index | 31,369 |
| Prepared spatial wind | 1,543 |

Additional probes reproduced the new editing, adapter, rotor, thermal-admission, and observer-query cases. The archive preserves **35 checked receipt/log pairs**, separating 28 passing runs from seven rejected exploratory runs. Failed sparse-project imports and incomplete-dependency attempts are not counted as simulator defects or successful validation.

The executed engine was the repository-pinned Godot `4.8.beta2.official.cafc17a19`, Linux x86-64. No matching native extension, clean full rendered-app workflow, physical flight validation, or target-machine FPS campaign was executed. The supplied replay helper was syntax/CLI checked; a complete replay of that helper from a full checkout remains untested.

**Recommended implementation order:** fix scoped weather editing, then native restore staging; add the rotor one-sided regression cases before selecting any new physical law; correct thermal containment; and integrate the two local work reductions after their narrow equivalence checks. This order addresses unintended behavior first while keeping mathematical continuity, implementation equivalence, and physical realism as separately verifiable goals.