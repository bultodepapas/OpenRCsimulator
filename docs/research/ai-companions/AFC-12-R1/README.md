# AFC-12 R1: bounded traffic broad phase

2026-10-20, Godot 4.7.2, Windows. The production tree now contains
[`traffic_index.gd`](../../../../app/ai/companions/traffic_index.gd), a reusable
float64 swept-bounds index. The manager does not use it yet; this report makes no
flight-separation or performance claim.

Each observation contains the existing 13-value rigid-body state, a stable ID,
and optional hull radius, position uncertainty and per-world-axis acceleration
bound. The caller must qualify that bound for the entire prediction horizon.
The index rotates body velocity into NED, expands the entire linear sweep by
`radius + uncertainty + acceleration * horizon² / 2 + 1e-6 m`, and queries 50 m
cells. Results retain the original observation order for deterministic threat
selection. A returned candidate still needs trajectory and collision refinement.

Storage is bounded to 256 observations, 4,096 cells per box and 65,536 bucket
references total. Oversized boxes enter an all-query overflow list; an oversized
query scans all boxes. Bounds outside ±10,000 km and nonfinite intermediate
arithmetic refuse the rebuild. Failed rebuilds preserve previous storage but
invalidate queries until the next successful rebuild. Callers must fall back to
the complete current traffic set on either rebuild or query failure.

The integrated test passes **102 checks**, with zero engine errors or warnings:

```powershell
python tools/godot/run_checked.py --warnings-as-errors --timeout 60 --require-text "traffic index: 102 checks, 0 failed" -- .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy --script res://tests/test_companions_traffic_index.gd
```

The independent analytic closest-approach oracle covers 80 seeded 32-aircraft
sets. It finds 1,088 linear conflicts and the broad phase omits none, returning
18,228 candidates from 79,360 possible ordered pairs. These counts describe a
synthetic workload, not timing or a supported fleet size. Explicit fixtures cover
a 400 m/s crossing from 1 km away, negative cell boundaries, rotated body
velocity, a bounded-acceleration crossing through local cells, per-box and global
overflow, hull/uncertainty inflation, detached storage and empty-roster reset.

Independent review identified finite-input arithmetic overflow and missing
non-overflow acceleration coverage. Both are fixed and tested. The earlier
single failed assertion expected a 1,000-cell box to exceed the 4,096-cell limit;
the fixture was corrected to actually exercise overflow. All original reports
are retained in `checks/`; `verification.json` binds the integrated result to
the current source hashes.

Open AFC-12 work includes qualified acceleration/error envelopes, actual coupled
trajectory avoidance, terrain/pits/obstacle containment, scheduler integration,
and measured callback costs. This broad phase alone closes none of those gates.
