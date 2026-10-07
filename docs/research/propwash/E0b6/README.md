# E0b6 — Distributed swirl and torque audit

2026-10-07 · **Status: numerical verification complete; calibration and enabled-path cost open.** Experimental smooth-profile route only. Production Stik remains unconfigured; legacy P-51 behavior is preserved.

## What changed

The E0b3b single-centroid approximation produced up to 206% moment error with nonzero swirl. Swirl varies strongly across the tail and changes sign across the shaft; evaluating it at one centroid cannot recover that distribution.

E0b6 retains the existing axial-wash centroid load and adds a span-integrated correction:

```text
L = L_axial_centroid + integral[ L_local(axial + swirl) - L_local(axial) ]
```

The integral uses five-point Gauss–Legendre quadrature, splitting each chord interval at the inner/outer occupancy radii and vortex core. It uses the neutral chord profiles, local rotational velocity, existing tail law and aerodynamic load arms. Horizontal loads retain their established pressure plane, 5 mm below the neutral coverage plane. Radial occupancy weights force increments, not air velocity. The correction vanishes continuously as swirl strength goes to zero. It does not remove the separate axial-centroid approximation. E0b5's schema still excludes simultaneous swirl and continuous axial transport; this step does not invent a transported swirl state.

## Torque and source audit

Let `s = swirl_factor`, `k = wash_factor`, `w` be disc induced speed, `R` propeller radius, `a = 0.3R` core radius, and `b` the ideal contracted radius. Above the numerical speed floor, the implemented strength is:

```text
Gamma = s (k/2) Q / [rho pi R² (u+w)]
v_theta(r) = Gamma r / max(r²,a²)
```

Here `Gamma` denotes `r v_theta` outside the core; circulation would be `2 pi Gamma`. The solid core makes speed finite and continuous at the axis and core boundary, but its radial derivative has a kink. For an assumed uniform cylinder of radius `b > a`, annular integration gives:

```text
Q_cylinder / Q = s (k/2) [U / (u+2w)] [1 - a²/(2b²)]
```

Use `U=u+2w` for the nominal ideal far wake, or `U=u+kw` for the locally attenuated axial speed. This is a **diagnostic cylinder**, not a global conservation claim: the implementation does not track expanded mass flow, fuselage/wing recovery, or reaction from removed angular momentum. The smooth load occupancy is not a complete wake velocity field. The 1 m/s divisor floor further changes this interpretation at small disc flow speeds.

[Selig 2010](https://m-selig.ae.illinois.edu/pubs/Selig-2010-AIAA-2010-7638-PropAeroSim.pdf), printed pp. 5–6, equations 17–20 and figure 5, supports an empirical axial-speed factor. It does **not** derive `k/2` as swirl attenuation. Page 9 obtains swirl from PROPID and describes right roll and left yaw for a clockwise propeller viewed from behind. Its roughly 40% resultant roll is a configuration-specific example, not a retained-torque fraction or radial calibration. The PDF filename says 7638; its cover identifies AIAA 2010-7938.

[Khan 2016](https://mcgill.scholaris.ca/server/api/core/bitstreams/dcf4ec23-fc4d-457b-b4af-7e0fe29ce67c/content), printed p. 104, omits explicit tangential/radial wake velocity and reduces reaction roll to 40%, citing Selig. It is not independent confirmation. [Khan and Nahon 2015](https://doi.org/10.2514/1.C033118) validates an axial acceleration/diffusion model, not this swirl field. [Deters, Ananda and Selig 2015](https://m-selig.ae.illinois.edu/pubs/DetersAnandaSelig-2015-AIAA-2015-2265-LRN-PropSlipstream.pdf), pp. 10–14, measures downstream evolution and propeller-dependent swirl profiles. Those observations justify uncertainty; they do not calibrate a fixed `0.3R` core for this Stik.

The implementation therefore retains its estimated strength law, with corrected comments. No coefficient is fitted to a universal fraction of rudder authority or to the cited 40% result.

## Evidence

- [41 accuracy checks](accuracy-checks.log) compare swirl deltas for factors 0.4 and 1.0 across six synthetic states: static controls, forward flight with rates, high angle of attack, displaced core, displaced edge and reverse fade. Acceptance is `max(0.1% of reference norm, 1e-4 N or N·m)`. The midpoint reference uses 128 samples per chord interval; the forward case also checks 256. The original three cases retain axial-centroid residuals below 0.25% (largest moment residual 0.1962%). This is a sampled envelope, not a uniform error bound over every possible state.
- [Independent dense probe](quadrature-development.log): 8,192 midpoint samples per interval, four factor-0.4 cases; peak normalized correction errors **1.035e-6 force / 1.024e-6 moment**. That experiment verifies the distributed correction, not physical wake realism or the whole axial-plus-swirl approximation.
- [23 torque checks](torque-checks.log): signed linear strength, density similarity, mass-flow consistency of the nominal cylinder, analytic core deficit, attenuated-speed flux and finite speed-floor join. Direction tests cover the currently supported clockwise-from-behind propeller; handedness is not configurable.
- [Four mutations](mutations.log) caught by assertions: missing correction, reversed swirl, retained axial load in the correction, and wrong torque strength. Disposable copies only.
- [16 production flight fingerprints](fleet-comparison.json) unchanged across four aircraft and trim/stall/spin/ground regimes; [12 zero-swirl load cases](zero-swirl-comparison.json) exactly match the pre-step smooth-profile baseline. No production aircraft data or golden file was changed.
- [Full regression](suite-summary.log): `app/test.sh` exits 0 in a fresh isolated clone with the E0b3b/E0b4/E0b5 prerequisites and final E0b6 code: 114 sections, 89 GDScript test programs, production and continuous-wash 30/60/144 fps hashes identical. Concurrent landscape/input/desktop work is excluded; [manifest](verification-manifest.json) identifies the verified runtime files.
- [Resource and scene checks](integration.json): zero errors, no new-script diagnostics, three scene smokes pass. The broader validator retains 184 existing warnings.

## Uncertainty and observations still needed

[60 fixed-rpm cases](sensitivity.json) sweep speeds 0/5/15/25 m/s, wash endpoint pairs `[0.8,1.8]`, `[1,1.4]`, `[1.4,1.8]` and swirl factors 0/0.2/0.4/0.7/1.0. These are **estimated exploratory ranges**, not statistical confidence bounds, measured Stik parameters or limits on model-form error. Controls and body attitude are zero; wing CL is held at 0.3. Geometry, core size and the borrowed propeller torque table are held fixed and remain uncertain.

| Airspeed, m/s | Incremental yaw range, N·m | Incremental tail roll / shaft torque |
| --- | ---: | ---: |
| 0 | −3.020 to 0 | 0 to 0.745 |
| 5 | −3.974 to 0 | 0 to 0.962 |
| 15 | −4.902 to 0 | 0 to 1.187 |
| 25 | −4.364 to 0 | 0 to 1.200 |

The tail-moment ratio is neither a conserved torque fraction nor whole-airframe net roll. Values above one are retained as model output, not capped or validated; the downstream angular-momentum balance is unresolved. Published donor-aircraft observations do not provide matched Stik data. E0b7 still needs configuration, raw throttle/rpm, nose-wheel unloading, taxi-blip and takeoff-swing observations, their uncertainties and held-out cases. Production enablement remains a separate decision.

## Cost and next step

The [first 12-point implementation](initial-quadrature-cost.json) performed two washed-minus-free evaluations per point even though the free terms cancel, costing roughly 60 ms per active tick. Direct washed-load evaluations and five quadrature points preserve the declared accuracy while reducing cost. [Paired cost evidence](cost-comparison.json) uses five batches after warm-up, 24 whole ticks per batch, on the shared i5-10500 host.

| Fixture, swirl factor 0.4 | Prior centroid, µs/tick | Distributed correction, µs/tick |
| --- | ---: | ---: |
| Forward | 733.4 | 20,912.2 |
| Stall | 884.0 | 20,657.4 |
| Static | 755.7 | 17,882.4 |
| Spin | 782.3 | 23,913.4 |
| Reverse fade | 751.0 | 16,141.9 |
| Reverse off | 351.5 | 358.4 |

**The active path fails the 500 µs/tick budget.** Timing noise and concurrent checks do not explain that order of magnitude. This is an accuracy reference for an unconfigured experimental path, not a playable Stik enablement. E0b6p must profile and reduce the enabled workload while preserving the dense-reference, continuity and fleet evidence; any native implementation remains subject to Gate P. No claim of budget acceptance is made.

## Reproduce

```sh
$(app/get-godot.sh) --headless --path app --script res://tests/test_swirl_accuracy.gd
$(app/get-godot.sh) --headless --path app --script res://tests/test_swirl_torque.gd
$(app/get-godot.sh) --headless --path app --script "$PWD/research/propwash/e0b6/sweep_swirl.gd" -- /tmp/e0b6-sweep.json
$(app/get-godot.sh) --headless --path app --script "$PWD/research/propwash/e0b6/bench_swirl.gd" -- /tmp/e0b6-cost.json
app/test.sh
```

Commit message: `E0b6: integrate swirl along the tail; prove 64 checks, four mutations and 16 exact fleet hashes; record cost gate`
