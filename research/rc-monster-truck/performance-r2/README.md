# RCV Track Sampler Allocation Pass

This study removes short-lived smoothstep arrays from the airfield obstacle-track sampler while keeping its equations and returned values unchanged. The reference path in `verify_track_parity.gd` preserves the previous sampler implementation for exact comparison.

Run the parity check from the repository root with the pinned Windows Godot 4.7.2 console build:

```powershell
$Godot = '.tools/Godot_v4.7.2-stable_win64_console.exe'
& $Godot --headless --path app --script "$PWD/research/rc-monster-truck/performance-r2/verify_track_parity.gd"
```

The check covers the default dirt-loop centerline, both loop edges and shoulders, the technical and access strips, every ramp and roller approach/deck/descent boundary, an empty track, non-finite coordinates and distant finite coordinates. It reports exact field equality, treating matching NaN values as equal for invalid-input parity.

After the braking baseline finishes, a bounded same-process Track-only comparison can be recorded with `-- --bench`. It alternates the preserved old sampler and current sampler across seven 16,000-call trials and reports per-call means and medians; it does not tick the vehicle session.

```powershell
& $Godot --headless --path app --script "$PWD/research/rc-monster-truck/performance-r2/verify_track_parity.gd" -- --bench
```

The pre-change timing baseline and the candidate result will be recorded in `docs/research/rc-monster-truck/RCV-handling/performance-track-scalar-r2.md`. `candidate-paired-03` and `candidate-paired-04` in `RCV-performance` are the same-machine context for the earlier sampler cache; they do not measure this allocation change.
