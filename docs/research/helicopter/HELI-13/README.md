# HELI-13: pure swash kernel

**Date:** 2026-10-13. **Scope:** a standalone, parameterized swashplate kernel for the [helicopter plan](../../../plans/helicopter.md#heli-13). It contains no session, input, or aircraft-data integration.

## Contract

[`swash.gd`](../../../../app/physics/rotorcraft/swash.gd) exposes five operations:

- `validate_curves` and `sample_mode_curve` accept a dictionary of named flight modes. Every mode has exactly five `pitch` points in [-1, 1] and five `throttle` points in [0, 1]. The shared stick knots are [-1, -0.5, 0, 0.5, 1], with linear interpolation. There are no built-in mode curves or aircraft presets.
- `mix_120` and `unmix_120` use normalized axis and servo-rise values. Looking down the rotor shaft, +x is forward and +y is right. Servo order is front, rear-right, rear-left. Positive servo rise moves the local swash point toward the rotor head. The mixer is:

      front       = collective + longitudinal
      rear-right  = collective − 0.5·longitudinal + √3/2·lateral
      rear-left   = collective − 0.5·longitudinal − √3/2·lateral

  Thus positive longitudinal raises the front swash side; positive lateral raises the right side. In the kernel’s blade-pitch convention, `θ(ψ) = θ0 + A_long·cos(ψ) + B_lat·sin(ψ)`, with ψ = 0 forward and increasing toward the right. This defines the linkage and harmonic signs; a future rotor integration must align its azimuth and flapping signs explicitly.
- `step_servos` clamps each requested servo independently to its declared normalized travel, then applies an exact first-order lag step, capped by that servo’s rate limit. Travel, rate, lag, and timestep are explicit inputs. Omitting `lag_seconds` selects zero lag. The kernel assigns no hardware endpoints or response values.
- `linkage_output` analytically decodes achieved servo positions, multiplies by caller-declared positive radians-per-unit ratios, and applies caller-declared collective and cyclic limits. It returns `theta0_rad`, `longitudinal_rad`, and `lateral_rad`.

Public functions return `{"ok": false, "error": ...}` for malformed shapes, non-finite values, or out-of-domain commands. Dynamic positions use packed float64 arrays; table/configuration inputs may use arrays or packed float64 arrays. Each servo travel interval is independently declared within normalized [-1, 1].

## Software evidence

[`test_heli_swash.gd`](../../../../app/tests/test_heli_swash.gd) checks curve interpolation and mode selection, analytic mixer round-trip, common-mode collective, zero-sum cyclic, independent per-servo saturation, rate and exact-lag response, linkage conversion and limits, and invalid inputs.

Run the focused check with the repository-pinned Godot binary:

```powershell
.tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --check-only --script res://physics/rotorcraft/swash.gd
.tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --check-only --script res://tests/test_heli_swash.gd
.tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --script res://tests/test_heli_swash.gd
```

Godot 4.7.2: both scripts parse; the focused suite passes **46 checks, 0 failed**. This establishes software behavior only. No identified aircraft’s swash direction, servo travel, response, or linkage has been qualified, and the kernel does not claim physical validation.
