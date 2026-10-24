# GP-02 analytic wheel and terrain checks

Status: synthetic software verification complete; no physical calibration. Recorded 2026-10-11 with Godot `4.7.2.stable.official.ed1daf0bf` on Windows 10.

Follow-up: [GP-02-R1 smooth-surface rolling resistance](rolling-2026-10-23/README.md), 2026-10-23, repairs a negative-coefficient defect with failing/passing regressions and a preserved same-tape taxi comparison.

The focused fixture isolates the new per-wheel evaluator from aerodynamic and propulsion loads. It verifies the analytic spring load at 0/25/50/100 N, airborne force and derivative zero, terrain gradient finite differences and normal direction, per-wheel runway/rough coefficients and yaw moment, separate tire spin-up and rolling drag, reverse-motion dissipation, declared brake torque and the no-hardware path. A coupled body/wheel RK4 fixture checks 240/480/960 Hz refinement and compares braked with unbraked stopping distance.

The pinned native runner passed import and the focused test (2/2 commands); the test reported 28 checks and 0 failures. Core measurements are in [measurements.json](measurements.json), the full engine output is in [test log](test_ground_physics.gd.log), and the runner command plus source hashes are in [report.json](report.json).

Selected values: a 0.2 m radius, 0.1 kg·m² wheel at 0.5 m/s with zero initial rim speed produces −40 N tire force, −4 N separate rolling force and +16 m/s² rim acceleration. Body plus wheel power is −22 W at the initial instant. The synthetic 2 N·m brake produces −4 m/s² rim acceleration and −28 W total power. The runway/rough pair produces −5.036/−14.728 N wheel drag and −2.752 N·m yaw moment. The 240/480/960 body-speed results differ by less than `2e-15` relative.

Reproduction command used for this capture (the app copy contains the in-progress GP implementation and test):

```powershell
$Gp02OutputDirectory = Join-Path .tools ("gp-work\gp02-verify-" + [guid]::NewGuid().ToString("N"))
python research\ground-physics\verify.py --app .tools\gp-work\app --godot .tools\Godot_v4.7.2-stable_win64_console.exe --out $Gp02OutputDirectory
```

These fixtures verify signs, bounds and numerical consistency only. They do not establish real tire inertia, grass resistance, braking, rollout distance, suspension behavior, or pilot acceptance. The parameters remain estimated or source-derived as labeled in `app/data/ground/wheel_profiles.json`.
