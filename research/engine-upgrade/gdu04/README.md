# GDU-04 frozen numerical comparison

`run.py` compares two native engines using the same copied simulation dependencies,
accepted data, initial session checkpoints and downstream control tapes. It uses
the existing `FlightSession`, `Simulation`, checkpoint codec and independent PCG32
oracle. It does not modify `.orfl` headers or relax replay compatibility checks.

From the repository root, choose a new output directory on a drive with space:

```powershell
python research/engine-upgrade/gdu04/run.py --source-app D:/OpenRCsimulator-experiments/godot-4.8-beta1/app --baseline .tools/Godot_v4.7.2-stable_win64_console.exe --candidate .tools/engine-upgrade/4.8-beta1/Godot_v4.8-beta1_win64_console.exe --out D:/OpenRCsimulator-experiments/gdu04-new-run
python -B -m unittest discover -s research/engine-upgrade/gdu04 -p test_run.py -v
```

The runner creates separate small dependency snapshots, import caches and APPDATA
profiles. Every flyable fixed-wing catalog entry runs in calm air and seeded
turbulence for 960 ticks at 240 Hz. Both engines restore the baseline's lossless
checkpoint and parse the same frozen command JSON. Roll, pitch and yaw doublets
are applied after tick 120; optional gear and flap slots retain their initial values.

The stream includes initial and every accepted tick's body state, previous state,
sampled auxiliary state, continuous state, controls, discrete modes (including RNG
state) and loads. Raw float64/int64 bytes are compared, including signed zero.
Five seeds also produce 4096 raw PCG32 words/states and 4096 OU updates each.
Raw PCG words/states must match the existing independent Python recurrence.

`--compare-only` analyzes existing completed checked outputs without rerunning the
engines. It verifies snapshot hashes, probe identity, completed invocations and
matching control/layout identities first. Engine executable hashes in that mode
are explicitly identified as measured during analysis. Keep the raw streams,
checkpoints, command tapes, manifests and checked-runner logs together.

This is a bounded numerical migration experiment. It does not compare trim-solving
results, all maneuvers or vehicle types, rendering, physical realism, performance
or `.orfl` exact replay across engine versions.

[2026-10-25 evidence](../../../docs/research/engine-upgrade/GDU-03/numerical/README.md).
