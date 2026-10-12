# Ground physics probes

Status: GP-04/05 verification tools, 2026-10-11. No physical calibration.

Use the pinned Godot 4.7.2. Run scripts against an imported app with absolute script/output paths; `res://` points to that app. Drivers never tune or rewrite aircraft data.

```powershell
$godot = (Resolve-Path .tools/Godot_v4.7.2-stable_win64_console.exe).Path
python research/ground-physics/verify.py --app app --godot $godot --out <new-evidence-directory> --full
& $godot --headless --path app --script (Resolve-Path research/ground-physics/airborne_parity.gd).Path -- --out=<absolute-json-path>
& $godot --headless --path app --script (Resolve-Path research/ground-physics/aircraft_ground_scenarios.gd).Path -- --out=<absolute-json-path>
& $godot --headless --path app --script (Resolve-Path research/ground-physics/benchmark.gd).Path -- --support=<absolute-GP04-scenario-json-path> --out=<absolute-json-path>
```

`verify.py --full` imports, checks every GDScript and runs every `test_*.gd`, with timeouts and engine-error rejection. It does not replace the Python, generated-asset, release or rendered checks in `app/test.sh`. `--tests` selects named tests when `--full` is omitted.

Airborne parity hashes all body, existing auxiliary, loads and inputs over 1200 ticks for four aircraft with calm/crosswind conditions; wheel slots are checked separately by `test_wheel_session.gd`. Benchmark after a warmup, alone on the host; report median and p95, never infer slow-machine acceptance. For a pre-GP baseline, replace the benchmark contact call with the old `Ground.loads` signature in a disposable copy; keep session workloads identical.

See [evidence](../../docs/research/ground-physics/README.md) and [plan](../../docs/research/ground-physics/GP-05/README.md).

`profile_inventory.gd` exports resolved catalog parameters with `--out`. `session_acceleration.gd` takes `--support=<GP04-json>` and `--out`, runs full-session thrust/aero/crash behavior with neutral controls, and records terminal outcomes without asserting pilot acceptance. The visual gear probe checks the existing model pivots against the integrated wheel state.
