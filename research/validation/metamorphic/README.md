# VAL-4 — Metamorphic flight checks

**Status:** implemented; software verification, not independent aircraft validation. [Evidence and limitations](../../../docs/research/validation/VAL-4/README.md).

From the repository root:

```sh
python3 research/validation/metamorphic/run.py
```

Add `--output /tmp/val4-proof.json` to preserve the full baseline, source hashes and mutation results. Python uses only the standard library and invokes the pinned Godot. It runs the current code, repeats the baseline in a disposable app copy, then applies three source mutations only to that copy. A mismatch, incomplete report, engine error, timeout, surviving mutation or concurrent source change fails without publishing evidence. Existing output is replaced atomically only after success.

The fixture connects the actual `FlightSession` load, servo, downwash and rotor callbacks to `Simulation`. It runs off-tree so window focus, physical radios and menu callbacks cannot affect it. The engine is stopped, wind is zero and contact is disabled. All numerical state uses float64 arrays. No files in `app/` are edited; this is a separate research command, not a new shared CI job.

| Property | Scope and tolerance | Deliberate defect |
| --- | --- | --- |
| Mirror symmetry | Four 240-tick flights; reflect lateral position/velocity, roll/yaw rates and quaternion x/z; mirror roll/yaw commands. Compare every body and auxiliary entry within 1e-12 absolute. Set Jxy/Jyz to zero in the fixture; retain Jxz. Additional one-sided surface probes exercise attached and local aerodynamics. | Reverse only the left aileron's global yaw derivative. Differential ailerons alone can hide this error, so one-sided controls are essential. |
| Froude scaling | The same four flights at length factors 0.25, 2.25, 4 and 9. Scale areas by N², mass N³, inertia N⁵; speed/time by √N and rates by 1/√N. Scale servo time and downwash length too. Compare every tick after undoing units, with error / max(1, absolute baseline) ≤ 1e-9. | Add a fixed 3 cm offset to the local wing stations on both sides. |
| Energy non-increase | 32 seeded, neutral-control, dead-stick flights with the original asymmetric inertia. At each of 240 steps, total kinetic plus gravitational potential energy may rise by at most 1e-9 J. | Reverse the local wing drag sign at one tenth magnitude, exposing positive work without numerical runaway. |

Four Froude time scales correspond to 480/160/120/80 Hz versus the 240 Hz reference. The number of ticks and dimensionless command timing stay identical; the engine's tick rate is set before each isolated flight reset. Auxiliaries contain zero rpm, three servo positions and the dimensionless lagged wing CL. Geometry and the induced-flow map come from the loaded Stik model; the map and aerodynamic coefficients are dimensionless and remain unchanged.

`E = m(v·v)/2 + omega·(J omega)/2 - m g down` uses NED position and the complete inertia tensor. Attitude, alpha, beta and body rates vary across the fixed seed; one case starts at zero translation. The checks exercise gravity, load evaluation, sampled downwash and RK4 through the real simulation step. They do not claim monotonic energy for powered flight, wind, ground impacts, arbitrary control work or every possible timestep/state.

Similarity here assumes unchanged density, gravity and dimensionless polars. It does not match Reynolds number or establish similarity between two real aircraft. Powered propulsion, contact, input-device timing, fuel, different aircraft models and ground/crash handling are outside VAL-4.
