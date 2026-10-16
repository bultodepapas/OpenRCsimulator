# P51-22 research tools: wing in the propeller jet

2026-10-16 · **Status: research candidate, not runtime.** [Evidence](../../../docs/research/p51-realism/P51-22/README.md#resolution--2026-10-16)

| File | Purpose |
| --- | --- |
| `candidate-wing-jet.patch` | Opt-in `propulsion.propeller.slipstream.wing_vortex_core`: `app/physics/wing_jet.gd`, the slipstream hook, loader/schema/contract gates, the P51-05 generator field and regenerated P-51 data, and `app/tests/test_wing_jet.gd` (16 checks). |
| `loop_sweep.gd` | Full-throttle pull-up steps of 0.3–0.7 stick from 27 and 32 m/s; prints turned pitch, α, β, pitch and minimum speed. |

The candidate's law:
- The planar wing at the aerodynamic reference point is cut by the same jet circle, drift, axial increment and swirl as the tail pieces. Eight midpoint strips cover the immersed span.
- Each strip keeps its converged Weissinger induced velocity, so its angle scales with Vp/Vp_jet. The circulation increment is a band as wide as the immersed span, with Helmbold's low-aspect slope.
- The increment's horseshoe system adds downwash to the immersed stabilizer in the washed evaluation. Legacy slipstream only, with no new state.

Its cost is +47 % per P-51 tick. It adds about 20 N of blown lift at 18 m/s, but almost no circulation, so it does not restore the tail downwash. The evidence report has the numbers.

Evaluate it in a disposable copy only, from the repository root:

```bash
rm -rf tmp/p51-22 && mkdir -p tmp/p51-22 && cp -r app tmp/p51-22/app
git apply --directory=tmp/p51-22 --include='tmp/p51-22/app/*' research/p51/p51-22/candidate-wing-jet.patch
.tools/Godot_v4.7.2-stable_win64_console.exe --headless --path tmp/p51-22/app --audio-driver Dummy --script res://tests/test_wing_jet.gd
.tools/Godot_v4.7.2-stable_win64_console.exe --headless --path tmp/p51-22/app --audio-driver Dummy --script "$PWD/research/p51/p51-22/loop_sweep.gd"
```

The patch also changes `research/p51/p51-05/derive_physics.py`. Apply that hunk in a full disposable clone if you want to check the generator.
