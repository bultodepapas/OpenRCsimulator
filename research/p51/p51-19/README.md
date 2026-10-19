# P51-19 trim calibration tools

2026-10-14 · **Status: reusable tools.** [Plan](../../../docs/P51-PLAN.md) · [Evidence](../../../docs/research/p51-realism/P51-19/README.md)

| File | Purpose |
| --- | --- |
| `naca_xp51_fig10.json` | Elevator-for-trim points read from NACA MR L-566 Figure 10 (XP-51, glide and cruise, CG 24.5 and 29.2 % MAC, tab 0), with the reading method and uncertainty. Input to the P51-05 generator. |
| `trim_probe.gd` | Runtime trim solver at nominal CL 0.25…1.1 for CG 24.5, 27 and 29.2 % MAC, level (powered) and glide (engine stopped). Moves only the CG and the CG-relative thrust arm. |
| `compare_probes.py` | Baseline/candidate summary of the [P51-15 probe](../p51-15/README.md) reports. |

The calibration itself runs inside [`derive_physics.py`](../p51-05/derive_physics.py), so the generated data and [derivation](../p51-05/derivation.md) stay reproducible from one command. Run from the repository root:

```powershell
python research/p51/p51-05/derive_physics.py --check
& .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy --script "$PWD/research/p51/p51-19/trim_probe.gd"
python research/p51/p51-15/run_probe.py --godot .tools/Godot_v4.7.2-stable_win64_console.exe --app app --probe envelope --hz 240 --output C:/Temp/p51-air-240.json
python research/p51/p51-19/compare_probes.py <base-air.json> <cand-air.json> <base-ground.json> <cand-ground.json>
```

Add `-- --data=<path>` to the probe to evaluate a saved data file. Compare glide rows with the NACA glide series: they exclude propulsion. Level rows include the RC propeller, thrust line and slipstream, which do not match the full-size installation.
