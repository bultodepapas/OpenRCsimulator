# Physics audit: attitude mapping and road reuse

The accepted quaternion contract allows lengths within `1e-3` of one, while `math3d.q_rotate` implements the unit-quaternion rotation formula. `Vehicle._derivative_core` previously passed the raw quaternion into the world-position derivative. A unit body velocity `[8, 1, 0]` at 90-degree yaw, with accepted quaternion length `1.0005`, produced `[-1.00900225, 8.00700175, 0]` instead of `[-1, 8, 0]` (0.0114046 m/s error). The reproducible probe is `research/rc-monster-truck/audit-2026-10-15/physics/q_position_rate_probe.gd`; after the change it reports zero error. Telemetry used the same raw mapping for speed, so it now validates and normalizes its attitude too.

The stage-level regression starts from a valid unit quaternion and 12 rad/s body-z spin. The first RK midpoint state has quaternion length `1.004987562`; its position derivative now matches the normalized spatial rotation, while qdot still matches the raw quaternion ODE. This isolates the defect from malformed public input. A 2 s free-flight run at 12 rad/s refines from maximum position errors of `0.049187880 m` at `dt=1/30 s`, to `0.003375948 m` at `dt=1/60 s`, and `0.000218028 m` at `dt=1/120 s`. At the coarse step, the raw-map baseline had maximum-axis error `0.049854743 m` and Euclidean error `0.057470708 m`; the normalized-map result has maximum-axis error `0.049187880 m` and Euclidean error `0.058126636 m`. The overall path error therefore did not improve in this coarse case; RK4 truncation dominates. This is step-refinement evidence, not a claim that normalizing the intermediate attitude removes that truncation. The regression's direct midpoint mapping assertion is the principal proof of the fix. The probe is `research/rc-monster-truck/audit-2026-10-15/physics/unit_spin_position_probe.gd`.

`_evaluate_active` now memoizes deterministic road samples by exact nested float keys for that single evaluation. Each callback-owned dictionary is deep-copied once into the cache; all consumers treat the returned sample as read-only. The cache is discarded on return, with no quantization or reuse across RK stages, states, or times. The wet reference test has 19 logical requests (center, eight water cells, four tire patches, six hull probes); the callback receives 14 calls, each for a distinct exact coordinate, showing five within-evaluation duplicates reused.

Verification used Godot 4.7.2 on Windows:

```text
.tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy --script res://tests/test_rcv_attitude_integration.gd
RCV attitude integration: 6 checks, 0 failures
```

The solver identity is now `openrc-ground-vehicle-dynamics-rk4-v5` because RK-stage integration behavior is corrected. Native identity sources and parity checks are updated; the native binary/build receipt still require the coordinated rebuild.
