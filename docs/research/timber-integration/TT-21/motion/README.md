# TT-21 — Turbo Lumber motion observer cost

This evidence records a render-only optimization in app/aircraft/timber_visual_motion.gd. The native engine is Godot 4.7.2-stable. All timing is headless method-level CPU measurement, not an FPS or GPU claim.

## Runtime change

Contact dust now returns before GroundWheels.frame() when the visual session is paused or no contact compression is positive. It turns the configured emitters off in both cases and preserves the paused particle clock behavior. For loaded wheels, slip reads the existing continuous-state array directly instead of allocating a wheel-speed slice. No physical state, controls, forces, collision data, suspension pose, contact thresholds, materials, or timing constants change.

Cable and coil surfaces continue to use clear_surfaces() / add_surface_from_arrays() so CPU-side arrays and AABBs stay current for Wreck preparation. A shallow-copy variant of the surface-array update was tested and removed because it did not reduce cable-update time in the paired run. ArrayMesh.surface_update_vertex_region() was also rejected: on the pinned engine the native probe left surface_get_arrays(), duplicates, and get_aabb() at their original vertices. The method is documented in [Godot 4.7 ArrayMesh](https://docs.godotengine.org/en/4.7/classes/class_arraymesh.html); the measured behavior is retained in [the probe report](region-api-probe.json).

## Same-process paired profile

The harness loads the frozen baseline and candidate GDScript resources into two independently built private Turbo Lumber fixtures, matches state, continuous telemetry, auxiliary inputs, field surfaces, and contacts, then alternates call order for each matched input pair. Each case uses 60 batches of 20 pairs (1,200 calls per source). The run shared the host with other work, so treat these values as scoped microbenchmark evidence rather than a general runtime guarantee. Baseline SHA-256: abc055855e5b15e5602131fd7df8a18cdebd7814a95f4b62b04ba19beeea09f3. Final candidate SHA-256: cab8d170d89c474c0ba586ad7f4078a172482ba1a88a8801538e97253d433938.

| Case | Baseline median (µs/call) | Candidate median (µs/call) | Paired candidate/baseline median |
| --- | ---: | ---: | ---: |
| Settled rest _process | 112.70 | 112.22 | 1.000 |
| Variable-compression taxi _process | 275.15 | 277.82 | 1.008 |
| Airborne _process | 98.80 | 59.30 | 0.602 |
| Focus-style paused _process | 60.67 | 58.90 | 0.968 |
| Cable + two coil deformation | 110.10 | 109.90 | 1.000 |
| Contact dust, paved/no slip | 48.33 | 48.17 | 0.997 |
| Contact dust, synthetic rough/slip | 46.98 | 46.80 | 0.996 |
| Contact dust, no positive compression | 46.98 | 9.25 | 0.197 |

The airborne case has no positively compressed wheel. Its paired median observer time was 39.8% lower, consistent with skipping the dust contact-frame evaluations. The direct no-compression dust call was 80.3% lower. Taxi, rest, pause, cable, and loaded dust cases show no meaningful improvement in this run; no acceleration claim is made for them. The rough/slip case injects a controlled synthetic wheel-speed difference into a private fixture and is not a measured tire test.

The report records exact baseline/candidate parity at rest, taxi, airborne, pause, reset, and Wreck-stopped poses, including vertex/attribute arrays, materials, mesh AABBs, wheel/hinge/axle transforms, and telemetry hashes. All six snapshot pairs and both input-immutability checks passed. The native motion verifier passes 41/41 checks, including unchanged simulation/continuous/aux arrays, Wreck bounds, wheel contact heights, rough-ground dust gating, pause/reset behavior, and inert Wreck copies.

The previous separate-process measurements are preserved in [profile-comparison.json](profile-comparison.json) as exploratory only. Their medians are confounded by host and process drift and are not performance acceptance evidence.

## Files and reproduction

- [Final same-process paired profile](paired-profile.json)
- [Final native paired-profile engine log](paired-engine.log)
- [Final paired-profile runner report](paired-engine-check.json)
- [Motion verifier result](runtime-checks.json)
- [Motion verifier engine log](runtime-engine.log)
- [Motion verifier runner report](runtime-engine-check.json)
- [Confounded separate-run exploratory comparison](profile-comparison.json)
- [ArrayMesh region API result](region-api-probe.json)
- [Same-process paired profiler](../../../../../research/timber/optimization/motion_paired_profile.gd)
- [Original separate-run profiler](../../../../../research/timber/optimization/motion_profile.gd)
- [Comparison script for exploratory profiles](../../../../../research/timber/optimization/compare_motion_profiles.py)
- [Region API probe](../../../../../research/timber/optimization/motion_region_probe.gd)
- [Frozen baseline source](../../../../../research/timber/optimization/motion_baseline.gd)

Run with the pinned engine and a new output directory:

    .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --script res://../research/timber/optimization/motion_paired_profile.gd -- --out=C:/new/timber-motion-paired-profile
