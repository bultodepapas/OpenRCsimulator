# P51-26 slipstream quadrature and sidewash tools

2026-10-16 · **Status: research tools; the law is implemented in the runtime (`propeller_sidewash`, `app/physics/slipstream.gd`). The patches below are the 2026-10-15 candidates it was built from.** [Plan](../../../docs/P51-REALISM-PLAN.md) · [Evidence](../../../docs/research/p51-realism/P51-26/README.md)

| File | Purpose |
| --- | --- |
| `strip_swirl_probe.gd` | Re-evaluates the legacy slipstream tail law at the level trim over N uniform strips, Gauss-Legendre with core cuts, span-mean swirl, or piecewise mean swirl. Prints its roll and yaw derivatives per β and per rudder. With one strip it equals `Slipstream.loads` exactly. |
| `trim_power_probe.gd` | Level (powered) and glide trim at 22–45 m/s; prints the power-on minus glide elevator. |
| `slipstream_bench.gd` | Best-of-7 time per `Slipstream.loads` call at a powered sideslipping state. |
| `convergence_probe.gd` | Runtime law: relative error of the slipstream yaw per sideslip for 1, 2, 4 and 64 subdivisions per swirl segment against 256. |
| `cost_breakdown.gd` | Runtime law: `Slipstream.loads` segmented against the legacy centroid, the tail law, thrust/normal force and the wing wake. |
| `candidate-piecewise-ribner.patch` | Candidate for `app/physics/slipstream.gd`: piecewise swirl quadrature on the legacy path plus Ribner's far-wake sidewash. Unconditional, for evaluation only; not applied. |
| `candidate-mean-swirl-on-top.patch` | Applied on top of the first patch: one evaluation per piece with the span-mean swirl. |

Evaluate a candidate in a disposable copy only:

```bash
mkdir -p tmp/p51-26/appB && cp app/project.godot tmp/p51-26/appB/ && cp -r app/physics app/data app/sim tmp/p51-26/appB/
(cd tmp/p51-26/appB && patch -p1 < ../../../research/p51/p51-26/candidate-piecewise-ribner.patch)
.tools/Godot_v4.7.2-stable_win64_console.exe --headless --path tmp/p51-26/appB --audio-driver Dummy \
  --script "$PWD/research/p51/p51-24/sideslip_probe.gd" -- --speeds=20,25.7,28.6,35,45
```
