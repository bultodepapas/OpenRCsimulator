# All-axis D11g data replay

This run closes the axis-coverage gap in `flights/verification.json`: it compares the Stik rate-derivative data change on independent roll, pitch, and yaw tapes, in both directions and under both rate profiles. It also records neutral cases and uses the unchanged Avanti as a zero-difference data control.

The new recorder follows the earlier `session_probe.gd` conditioning and timing: each case is independently trimmed at the aircraft start speed and 300 m altitude, stepped at 240 Hz for 1,440 ticks, and receives neutral raw controls except for one signed unit-axis pulse during `[0.5, 1.0)` seconds. There are 14 cases per aircraft: normal and full profile, each with neutral plus negative and positive roll, pitch, and yaw. The original probe and runner remain unchanged.

The Stik tapes load the archived prior aircraft bytes from `d11g-root-integration/previous/data/aircraft/jensen_ugly_stik_60.json` (`5fe8ece9…`). Same-tape candidate replays load the isolated app's current Stik JSON (`bdcf4d64…`). Jet tapes and their candidate control both use the unchanged isolated-app Avanti JSON (`68d3fd42…`); this is a negative control, not a historical Avanti data comparison. All recordings and replays use solver identity `85d0b19b…`.

All 28 recordings completed 1,440 ticks without faults or crashes. Each tape passed a complete exact replay and a complete candidate replay, then compared as 1,441 aligned CSV rows. The 14 Jet negative-control comparisons are exactly zero in position, velocity, angular rate, and quaternion angle. Stik neutral residuals are at most about `3e-16` in velocity/rate/orientation; the signed controls expose data-dependent changes. Across both signs, the largest observed candidate differences were:

| Profile / axis | Position (m) | Velocity (m/s) | Angular rate (rad/s) | Quaternion angle (rad) |
|---|---:|---:|---:|---:|
| Normal / roll | 0.1884 | 0.04897 | 0.002786 | 0.006432 |
| Full / roll | 0.3031 | 0.06075 | 0.004861 | 0.005238 |
| Normal / pitch | 0.1123 | 0.02700 | 0.005461 | 0.003539 |
| Full / pitch | 0.4977 | 0.08340 | 0.05495 | 0.009926 |
| Normal / yaw | 0.1197 | 0.01346 | 0.006099 | 0.002648 |
| Full / yaw | 0.3070 | 0.04048 | 0.01091 | 0.01264 |

These are open-loop software/data sensitivity measurements, not flight validation or a claim that the coefficients are physically validated. The comparison reuses the exact same recorded, post-conditioning input tape for both runs; it does not retune trim or pilot input for the candidate.

Run from the repository root on Windows with:

```powershell
python research/physics-audit-2026-10-14/remediation/run_rate_data_flights.py `
  --app tmp/physics-audit-keyboard-fixture/app `
  --godot .tools/Godot_v4.7.2-stable_win64_console.exe `
  --stik-baseline docs/research/physics-audit-2026-10-14/remediation/R11/d11g-root-integration/previous/data/aircraft/jensen_ugly_stik_60.json `
  --out docs/research/physics-audit-2026-10-14/remediation/R11/d11g-root-integration/all-axis-flights
```

`verification.json` retains all 28 tape hashes, per-case replay identities and comparison maxima, all 85 process commands and logs, plus before/after hashes for 934 app GDScript/data JSON files, `project.godot`, the archived and candidate aircraft inputs, the probe/runner/comparer/helper, and the Godot executable. Every process passed within its 240 s capture, 180 s replay, or 30 s CSV-comparison limit; app source/data, project settings, watched tools, and aircraft inputs had no hash drift. Raw recordings, CSVs, reports, and logs are under `records/` and `runs/`; the case summaries and integrity receipt are in [`verification.json`](verification.json).
