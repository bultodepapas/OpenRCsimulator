# P51-15…18 audit tools

2026-10-12 · **Status: reusable audit and verification tools.** [Plan](../../../docs/P51-PLAN.md) · [Evidence](../../../docs/research/p51-realism/README.md)

Run from the repository root using the pinned Godot 4.7.2 binary. The JSON is generated; edit P51-05 inputs/generator, never only the output.

```powershell
python research/p51/p51-05/derive_physics.py
python research/p51/p51-05/derive_physics.py --check
python research/p51/p51-15/test_inventory.py
python research/p51/p51-15/run_probe.py --godot .tools/Godot_v4.7.2-stable_win64_console.exe --app app --probe envelope --hz 240 --output C:/Temp/p51-air-240.json
python research/p51/p51-15/run_probe.py --godot .tools/Godot_v4.7.2-stable_win64_console.exe --app app --probe ground --hz 240 --output C:/Temp/p51-ground-240.json
python research/p51/p51-15/verify_native.py --godot .tools/Godot_v4.7.2-stable_win64_console.exe --app app --out C:/Temp/p51-focused
```

Use fresh output paths. Repeat both probes at 480 Hz. Each runner preserves engine output and fails on engine errors even if Godot returns zero. Ground cases must complete, remain finite and pass lifecycle checks; aircraft identity, tick rate and matrix size are checked. `envelope_probe.gd` reuses the existing Extra research reducer/inverted solver by relative path, so retain the repository structure. Since P51-21 the ground fixtures use the product runway start (stiction anchors); earlier reports used a constructed, settled pose.

Freeze separate baseline/candidate source trees before comparing flight or cost. `run_benchmarks.py --godot <binary> --baseline <baseline-app> --candidate <candidate-app> --out <fresh-directory>` alternates baseline/candidate/candidate/baseline. Existing trim/stalled/component timings and the new ten-second idle-ground `Simulation.step()` timings exclude rendering and fixture setup. They measure this host; they are not a 500 µs target-hardware certification.

On Linux, make a fresh LF checkout (`git -c core.autocrlf=false clone --no-hardlinks ...`) and overlay only reviewed files. `python3 research/p51/p51-15/run_suite.py --root <checkout> --out <fresh-directory>` runs `app/test.sh` with isolated user-data paths and records continuation if it fails. The result remains nonzero when any component failed. Reproduce each unrelated failure on baseline; never relabel a continued suite as an uninterrupted pass.

`check_evidence_identity.py` compares baseline, frozen candidate and final aircraft JSON, rejects any non-source final delta, and records hashes of the final authored tools. This bridges provenance-only corrections; it must not be used to excuse an untested numerical change.

Tune one identifiable quantity at a time: establish geometry/mass/CG and units, verify inertia, identify propeller/engine maps, then compare trim and control response before stall or spin tuning. Retain units, evidence kinds, source uncertainty and conditional-module validity under [AIRCRAFT_CONTRACT](../../../docs/AIRCRAFT_CONTRACT.md). Keep the stated 1% steady / 5% smooth comparison bands; report contact events, nonlinear maneuvers and stochastic weather separately. These scripts predict the current model, not the flight envelope of a real RC aircraft.
