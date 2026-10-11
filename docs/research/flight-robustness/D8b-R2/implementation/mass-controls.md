# D8b-R2c — Mass, inertia, and control contracts

2026-10-11 · **Status: mathematical and provenance contracts pass; aircraft-specific flight bounds remain unsupported.**

[Owning plan](../../../../UGLY-STIK-PULLUP-PLAN.md) · [D8b-R2 evidence](../README.md) · [contract test](../../../../../app/tests/test_pullup_invariants.gd)

## Current source audit

The contract loads [`jensen_ugly_stik_60.json`](../../../../../app/data/aircraft/jensen_ugly_stik_60.json) through the production loader. Its 20-item reference inventory totals **2.885058291 kg**, with CG `[0.1209, 0, 0] m` in the leading-edge frame `[x aft, y right, z up]`. The derived full tensor about that CG is `[0.1154067801, 0.3870856140, 0.4841075904, -0.0095400, 0.0072395, 0.0004552569] kg·m²` in body FRD order `[Jxx, Jyy, Jzz, Jxy, Jxz, Jyz]`.

The inventory is a **virtual reference build**, not a measured owner aircraft. Two masses use manual product references; 17 masses are estimated, and the 284.1 g balance item is derived. Its position and most installation coordinates and dimensions remain estimated. The balance item is explicitly not a ballast recommendation. The inventory's off-axis items produce nonzero products of inertia; the test independently recomputes those products from the source positions and checks that the loaded tensor retains them.

The full tensor passes positive-definiteness checks and its inverse recovers all three body axes. Analytic fixtures also verify every point-mass tensor entry and sign, a box's intrinsic inertia, mirrored-product cancellation, and the coupled angular acceleration under a pure pitch moment. These are mathematical checks, not calibration of the reference build. The existing loader warning that `Jyy` is 2.11× a scaled UltraStick25e comparison is a donor-data plausibility note, not a measured bound.

No numerical bounds are assigned to flight angle of attack, body rates, loop-plane error, recovery time, or altitude loss. The repository has no matched high-load flight data or measured installation to support those limits. The checks enforce mathematical validity and preserve source provenance; they do not convert estimated inputs into measurements.

## Control source and behavior

Current maximum throws are 20° aileron, 20° elevator, and 25° rudder. The source labels them **estimated** and says they are typical low-rate sport throws absent from the Jensen plan. The 0.14 s full-throw time is also estimated from a generic standard analog servo and linkage travel. The loader derives the servo slew from that time. The contract reads these values and their recognized provenance dynamically, then checks degree/radian conversion and that each command axis maps to its own configured surfaces; it does not pin exact throw values or evidence kinds for future aircraft-data revisions.

Godot synthetic physical-key events exercise all eight keyboard keys through `Keyboard.read_raw()`, command slew, and the aircraft throw map. Each key changes only its assigned raw axis: left/right roll, up/down pitch (down is positive nose-up command), A/D yaw, and S/W throttle. This checks the Godot key-state adapter in headless mode, not a physical keyboard, OS delivery, ghosting, or radio hardware. The separate [`test_servo.gd`](../../../../../app/tests/test_servo.gd) contract checks simulated servo lag and its full-throw endpoint; neither is a physical servo measurement.

## Reproduction and limits

Run on Windows with the repository-pinned official Godot 4.7.2 executable:

```powershell
.\.tools\Godot_v4.7.2-stable_win64_console.exe --headless --path app --script res://tests/test_pullup_invariants.gd
```

The promoted contract reports **41 checks, 0 failures**. Focused existing contracts also passed on the same native executable: rigid body (15), aircraft data (87), controls (17), and servo (6), for 166 checks total. The aircraft-data run prints the existing donor-inertia warning described above. No full `app/test.sh` run or physical flight was part of this scoped verification.
