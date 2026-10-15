# HELI-33 impact-detector performance evidence

This is a warm native CPU microprofile of the helicopter impact detector. It measures the direct `ImpactDetector.evaluate(...)` call with the production field, prepared contact geometry, and (where enabled) the field collision world. Each case ran 100 warm-up ticks followed by 500 measured ticks; all four cases returned `ok=true` and no impact. Times are microseconds per call, using the harness's sorted-sample p50 and p95 indices.

The baseline source is `impact_detector_before.gd`, whose Git blob (`499acb81134a8519fc6d08f7b16a8808b9ed912a`) matches `HEAD:app/physics/rotorcraft/impact_detector.gd` at commit `5e9dae16eefae345f116cad613fd612a398d970c`. The final evidence copy and current app source have Git blob `10f2466e8a7152f87a356af6635b5c1e806b9356`. The baseline and final runs used the same `profile_harness.gd`; the corresponding source was in the app module path before Godot loaded the project. Engine: Godot 4.7.2 stable (`ed1daf0bf`).

| Case | Baseline p50/p95 | Final p50/p95 | p50 / p95 change |
|---|---:|---:|---:|
| Ground, empty collision world | 1169 / 1354 | 661 / 774 | -43.5% / -42.8% |
| Ground, field collision world | 1918 / 2460 | 897 / 991 | -53.2% / -59.7% |
| Airborne, empty collision world | 134 / 194 | 313 / 350 | +133.6% / +80.4% |
| Airborne, field collision world | 1532 / 2644 | 410 / 465 | -73.2% / -82.4% |

The empty-world airborne case is slower in the final profile and is retained as a regression. These are single-run warm measurements, not release acceptance or physical validation. The harness also records `s.sim.step()` separately before calling the detector. Its p50/p95 values, baseline → final, were ground/empty 2511/2912 → 2725/3162 µs, ground/field 3293/4294 → 2993/3379 µs, airborne/empty 986/1304 → 1713/2025 µs, and airborne/field 3200/5922 → 1799/2117 µs. These are integrator diagnostics, not a comparison of detector-call cost; the direct detector timings above are the relevant measurements.

A separate comparison using the same scenarios and sampling method evaluated the added conservative rotor vertical-support early-out. It uses rotor radius plus chord half-width and the validated terrain height bound to skip rotor support sampling when the full bound remains clear of terrain. Against the immediately preceding detector source, the measured p50/p95 changed as follows:

| Case | Before early-out | With early-out | p50 / p95 change |
|---|---:|---:|---:|
| Ground, empty collision world | 801 / 1014 | 400 / 642 | -50.1% / -36.7% |
| Ground, field collision world | 714 / 1192 | 503 / 756 | -29.6% / -36.6% |
| Airborne, empty collision world | 176 / 309 | 165 / 222 | -6.3% / -28.2% |
| Airborne, field collision world | 368 / 507 | 225 / 305 | -38.9% / -39.8% |

The early-out comparison is summarized here; its temporary source and harness copies were removed after recording the results. The immediately preceding source had SHA-256 `131BB64149038DF54DA4A2C41D61B7C69B60CECED73DE365BE50ECA7563DC8D3`; the measured candidate matches the retained final source (SHA-256 `9F2BDA0BEA24955765251B04A6E5F98D48B4321596D9C18BDAC66A70B48FB5F6`). The optimized source passed the focused detector suite: 26 checks, 0 failed. Parse checks for the detector and test script also passed. The raw canonical before/after profiles and logs, source copies, harness, and focused verification logs are retained alongside this report. `SHA256SUMS.txt` records their SHA-256 fingerprints and excludes itself.