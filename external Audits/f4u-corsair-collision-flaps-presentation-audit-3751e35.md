Completed the Corsair-focused review and the detailed senior-developer handoff. **The report establishes two new correctness defects and one measured performance opportunity**, with code references, mathematical derivations, reproducible probes, proposed corrections and acceptance criteria.

## Deliverables

- **Detailed Markdown report — approximately 5,000 words:**  
  [F4U-CORSAIR-NEW-FINDINGS-3751e35-2026-11-06.md](https://chatgpt.com/library?file_id=libfile_1fa996d4f1bc8191a00e8e0a345e9e84&account_id=personal)

- **Evidence archive — report, probes, raw measurements, checked logs, hashes and replay instructions:**  
  [F4U-CORSAIR-EVIDENCE-3751e35-2026-11-06.zip](https://chatgpt.com/library?file_id=libfile_07398ec70af88191ab7f23e40eec9399&account_id=personal)

I read `external Audits/CONSOLIDATED-AUDITS.md` before the investigation and checked the expanded **A1–A11** ledger again before finalizing. The previous Corsair CF-01–04 findings are excluded from the new-finding count.

The experiments are pinned to commit `3751e35e1cccf574c4446d21273a4d5ecaf80ddf`. A closing comparison against `842339369a58e7320177a6caecf22a7dc012ec0f` confirmed that the responsible files were unchanged. The report distinguishes that later source check from the revision actually executed. Production source was not modified.

## 1. CF-05 — raised-circuit collision detection can miss contact within a tick

**This is the highest correctness priority identified in this pass.**

The track collision routine examines a hull point only when its final position has positive penetration depth. Its depth helper also returns zero when the point ends at or below the flat-ground datum. That combination can discard a point that crossed raised dirt earlier in the tick. The relevant logic is in [`flight_session.gd`](https://github.com/bultodepapas/OpenRCsimulator/blob/3751e35e1cccf574c4446d21273a4d5ecaf80ddf/app/sim/flight_session.gd#L3372).

The fundamental problem is this gate:

```gdscript
if _rc_point_depth(candidate, hull, index) <= 0.0:
    continue
```

A clear endpoint does not prove that the trajectory between endpoints was clear. A point can enter and leave a raised feature during the same tick.

### What the probes reproduced

Both cases retain the **stock 23-point Corsair crash hull** and use the right-wingtip point.

| Case | Demonstrated behavior |
|---|---|
| **Tabletop crossing, endpoint below datum** | The wingtip crosses the composed field-and-track surface at interpolated tick fraction **0.124858**. The track detector reports no hit, and the session publishes a flat-ground collision at **0.966441** instead. Those fractions differ by **3.5066 ms** at 240 Hz. |
| **Roller crossing, both endpoints clear** | Every hull point is clear of the composed surface at both endpoints. Between them, the selected wingtip penetrates that surface by **0.932 mm** at the sampled fraction 0.503. The soft-contact tick is accepted with no track impact and an empty crash record. |

The roller control is particularly useful: supplying the same interior pose as the endpoint makes the detector find a collision. The geometry and track can produce a hit; the whole-interval query misses it because of endpoint admission.

These are deliberately constructed valid resets followed by real accepted simulation ticks. The reported crossings use the resolver’s position/shortest-nlerp interpolation, not a dense reconstruction of the RK trajectory. The submillimetre roller result establishes a counterexample, not how frequently players encounter it.

### Recommended correction

Separate:

1. The continuous signed clearance from the terrain.
2. The policy determining which raised-dirt contacts belong to the track.
3. The search and arbitration for the first collision.

The search must consider potentially intersecting interior intervals, including cases with two clear endpoints. **Increasing the bisection count cannot fix a candidate that is skipped before bisection starts.**

The report describes a conservative interval-search approach, a possible mathematical clearance bound, and regressions covering both witnesses, rotating poses, the existing 5 cm relief threshold, competing contacts and rollback.

## 2. CF-06 — flap lift-reference translation omits the force-direction projection

The Corsair’s flap model specifies that incremental camber lift acts **0.075281 m aft** of the strip force point. However, the runtime transfers the full lift magnitude through that distance without accounting for the lift vector’s direction. The force calculation and displacement term appear together in [`aero.gd`](https://github.com/bultodepapas/OpenRCsimulator/blob/3751e35e1cccf574c4446d21273a4d5ecaf80ddf/app/physics/aero.gd#L580).

For an aft displacement expressed in body axes,

\[
\Delta\mathbf r=(-dx,0,0),
\]

and incremental lift

\[
\Delta\mathbf F_L
=
\Delta L\left(\frac{f_2}{V_p},0,-\frac{f_0}{V_p}\right),
\]

the pitch transfer must be

\[
\Delta M_y
=
(\Delta\mathbf r\times\Delta\mathbf F_L)_y
=
-dx\,\Delta L\,\frac{f_0}{V_p}.
\]

The implementation currently uses:

\[
\Delta M_y=-dx\,\Delta L.
\]

For uniform flow with zero angular rates, the omitted factor is \(\cos\alpha\). In the general case, it must come from **each station’s actual local flow**.

### Measured discrepancy

The diagnostic used production `Aero.loads`, stock Corsair data, 23 m/s, density 1.225 kg/m³, full 30° flaps, zero body rates and neutral other controls.

| Angle of attack | Current offset contribution | Geometric transfer | Current minus geometric |
|---|---:|---:|---:|
| 0° | −14.616299 N·m | −14.616299 N·m | Approximately zero |
| +12° | −13.403083 N·m | −13.110194 N·m | **−0.292890 N·m** |
| +20° | −18.482263 N·m | −17.367646 N·m | **−1.114617 N·m** |
| +30° | −14.342156 N·m | −12.420671 N·m | **−1.921485 N·m** |

The witness isolates the parameter by changing only the offset to zero in a copied model. An independent oracle derives the lift increment from strip-force differences and applies the cross product. The other five wrench components remain numerically unchanged; clean-flap outputs are byte-identical between the original and zero-offset models.

This establishes an internal force-location inconsistency. It does not establish a particular handling change or quantify error against a real Corsair.

### Recommended correction

The narrow repair should retain the optional-field guard and use the actual station-flow projection:

```gdscript
# Inside the existing active-flap/nonzero-plane-speed branch.
if flap_model.has("lift_reference_offset_m"):
    var offset: float = float(flap_model.lift_reference_offset_m)
    flap_couple -= lift_q_area * flap_delta_cl * offset * (f0 / plane_speed)
```

The separate thin-airfoil section couple and profile-drag moment should remain intact. The report includes controls for absent/zero offsets, clean flaps, zero/reverse flow, angular rates, spatial wind and finite-fuel configurations.

This should be an independently reviewed physics correction before further flap-pitch tuning.

## 3. CF-07 — rendering calculates a flap overspeed advisory it discards

The flap presentation path calls `session.flap_state()` but consumes only `angle_deg`. The status function also computes airspeed and density for an overspeed advisory. In spatial weather, obtaining that airspeed prepares the entire Corsair station-airflow structure. See the [render consumer](https://github.com/bultodepapas/OpenRCsimulator/blob/3751e35e1cccf574c4446d21273a4d5ecaf80ddf/app/main.gd#L3176) and [full status calculation](https://github.com/bultodepapas/OpenRCsimulator/blob/3751e35e1cccf574c4446d21273a4d5ecaf80ddf/app/sim/flight_session.gd#L4056).

For one successful status read:

| Weather mode | Existing wind queries | Existing density queries | Angle-only candidate |
|---|---:|---:|---:|
| Legacy | 1 | 2 | 0 / 0 |
| Spatial | **10** | **2** | **0 / 0** |

The ten spatial queries cover the datum, six wing stations, two tails and the propeller. This work also occurs with stowed flaps.

### Prototype result

A narrow reader obtains the accepted actual flap fraction and live maximum angle without computing the advisory or introducing a persistent cache.

It passed **268 parity checks**, including invalid auxiliary values, enabled/disabled input, both weather modes, maximum-angle changes and folded-wing hinge transforms. A separate check covers the short-input fallback.

In the isolated presentation-component benchmark:

| Weather, input enabled | Baseline median | Candidate median | Median paired reduction |
|---|---:|---:|---:|
| Legacy | 62.13 µs | 46.66 µs | **22.39%** |
| Spatial | 581.47 µs | 46.92 µs | **92.11%** |

Each workload used eight alternating baseline/candidate pairs, with 128 calls per batch. The candidate was faster in all eight pairs. The report also includes the disabled-input cases and every raw batch measurement.

**These are component savings, not FPS gains.** The timed sequence includes control-surface, flap and fold updates in a synthetic imported hierarchy. It excludes the rest of rendering, GPU work and physics integration.

The recommended implementation is a small shared presentation accessor. HUD and control consumers that need the full status should retain it. Real Corsair GLB integration, lifecycle behavior and matched full-scene profiling remain the next qualification steps.

## What the senior developer receives

The report connects each finding to a focused implementation task and explains the relevant structural improvements:

- **Collision:** separate geometric clearance, contact ownership and first-event search.
- **Aerodynamics:** test force-location changes using dimensional cross-product invariants.
- **Presentation:** expose the accepted-state quantity the consumer actually needs, avoiding unnecessary environment queries.

The evidence archive includes **10 original successful checked-run receipts and seven fresh reconstruction receipts**, all complete with zero engine errors and warnings. The fresh reconstruction includes the import and six diagnostics; it does not count another benchmark campaign.

The report also retains bounded negative results—such as the sampled flap-lift sweep and aerodynamic power screens—and explains why other observations were not promoted. That keeps the implementation queue focused on findings supported by new evidence.