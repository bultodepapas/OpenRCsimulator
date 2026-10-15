# R09 standard-column boundary sweep

**Run date:** 2026-10-14 local (Bogota). **Scope:** read-only boundary behavior of the standard-column atmosphere in the retained final-native app snapshot. No runtime, aircraft data, tests, or goldens were edited.

## Method

The reproducible probe is [`probe.gd`](probe.gd); its complete stdout is [`boundary-sweep-field-minus500-edge-025mps-ground-context.log`](boundary-sweep-field-minus500-edge-025mps-ground-context.log). It ran at 240 Hz (dt = 1/240 s) against `tmp/physics-audit-final-native-2026-10-14/app` using Godot 4.7.2 stable, official build `ed1daf0bf`. The exact command was:

```powershell
$godot = 'C:\DEVELOPMENT\OpenRCsimulator\.tools\Godot_v4.7.2-stable_win64_console.exe'
$probe = (Resolve-Path -LiteralPath 'docs/research/physics-audit-2026-10-14/remediation/R09/boundary-sweep-20261014/probe.gd').Path
& $godot --headless --path 'tmp/physics-audit-final-native-2026-10-14/app' --audio-driver Dummy --script $probe
# Native process exit code: 0
```

The test selected the v4 `standard_column` weather mode with `field_elevation_m = -500 m`. This datum puts the lower atmosphere limit at `down = 0`; the one-metre interior control is at `down = -1 m`. Each family was tested at both geometric limits, −500 m and 11000 m. Exact-edge reset and one-step cases used outward NED down speed of 0.25 m/s; the expected first RK midpoint is only 0.520833 mm outside the closed interval. Each case also tried a reset 0.1 m beyond the interval and a one-step control starting 1 m inside while moving outward at 0.25 m/s. Velocity was assigned in NED and rotated into body axes while preserving horizontal NED velocity.

Five initialized and flyable family sessions were included: Jensen prescribed-RPM Stik, Avanti turbine, Turbo Lumber electric, P-51 coupled shaft (`coupled-rk4`), and glow Stik. Per-case contact context is in the raw log. Every session had an empty `ground_surfaces` array, which the existing code defines as flat dry pavement; the stage ground-load path remained active (three wheels for the first four aircraft; the glow case has three anchors and no continuous wheel state). No scenery collision world was installed, so the separate post-step collision filter was absent. The 0.25 m/s edge state is a boundary stress state, not a tested runway equilibrium. This probe did not validate runway placement or the terrain/collision-world path.

## Results

All **10 of 10** family/edge cases showed the same boundary contract:

- At the exact limit, the atmospheric query and simulation reset succeeded.
- At ±0.1 m outside, the atmospheric query failed and reset returned false; the accepted state, last loads, and tick were unchanged.
- At the exact limit with outward motion, `Simulation.step()` rejected the RK joint stage, left tick at 0, and preserved the exact accepted body state.
- The probe independently queried the computed first RK midpoint: −500.000520833333 m for the lower edge and 11000.0005208333 m for the upper edge. Both were outside and returned `ok=false`.
- At 1 m inside, reset and one outward control step succeeded without a fault for all 10 cases. Final altitudes remained in range: lower controls were −499.001017981574 to −499.001031094626 m; upper controls were 10999.0009748100 to 10999.0009779466 m.

The step fault text is the generic `step rejected: RK joint stage evaluation is nonfinite or malformed`; the public API does not label it “atmosphere out of range.” The paired midpoint query, the unchanged-state fault result, and the code path support the interpretation: the next RK stage samples an altitude outside the column and is rejected before the step commits. This is the documented fail-closed behavior, not a defect found by this sweep.

## Source and run identity

[`identity.json`](identity.json) records the snapshot-manifest SHA-256, Godot binary hash, probe/log hashes, and hashes of the atmosphere, wind, simulation, family adapter, and five aircraft files. The snapshot manifest has 2319 entries and SHA-256 `21fa890a76d5b4935861bae884734cba31b34582b5e5fe4542dc012acc229146`; all 16 selected files match its entries. The probe ran against the isolated snapshot, not the shared working `app/`. At identity capture, the live worktree differed among those selected files only for `app/data/aircraft/p51d_mustang_120.json`; the complete hashes are preserved in `identity.json`.

Relevant snapshot source: `app/physics/atmosphere.gd:23-24,100-105,140-150` defines the inclusive altitude limits and rejects out-of-range values; `app/physics/wind_field.gd:149-158` maps `field_elevation_m - down_m` to that sampler; `app/sim/flight_session.gd:250-263` exposes the body-state atmosphere query; `app/sim/flight_session.gd:519-520,553-560,809-811,2443-2464` documents flat-pavement defaults, installs the optional post-step collision filter, and evaluates landing-gear loads; and `app/sim/simulation.gd:94-127,132-136,168-208,238-255,285-293` validates resets and RK stages before publishing the next state. The probe uses its own exact RK midpoint calculation and records all per-family outcomes without instrumenting or changing those sources.

This verifies software boundary and rollback behavior only. It is not a validation that ISA conditions, propulsion, aerodynamics, or landing gear are physically accurate at either extreme altitude.

The `ground-context` 0.25 m/s output and `identity.json` are the canonical evidence. Other run logs and `identity-attempt-01-manifest-key-mismatch.json` in this new directory are earlier drafting diagnostics; they are superseded and are not used for the results above.
