# AV-09: active brake-law characterization, review R2

2026-11-10 · Windows x86-64 · headless Godot 4.8-beta2 official
(`cafc17a192acf67903910a68aeb3c076c0907a4b`), GDScript reference backend.
This is a numerical characterization of the existing wheel law, not brake
calibration or a measured landing distance. The [review](../../../avanti-realism/review-2026-11-10.md#42-the-active-brake-law-can-be-dominated-by-numerical-regularization)
identified a cap that can dominate the assumed hardware torque. The grid below
reproduces that branch; two coupled sessions show one consequence under the
specified initial conditions. The [GP-12 candidate](../../../ground-physics/GP-12/README.md)
was not enabled or compared.

## Identity and evidence

The aircraft bytes are SHA-256
`77674df18312f6235352a28a797c497013ef18451a41eb0141e3f16dffd220b9`,
the working-tree candidate containing the [review R1 / AV-17-R4 Cmq correction](../../../avanti-realism/AV-17-R4/README.md).
The recorded solver identity is `source-tree-v1` SHA-256
`6e8951de37d288138e43c07bb9e348ec31e7f920f4b9d74d6f0227827b95cdef`.
The wheel profile input and selected canonical profile hashes are
`58a2526829a3e9e529ac16f79a7d135614618c3d70350c2187d804a476e40665` and
`d0a5dea3a0392c875c403802cc4978588cf850f822307f20a40c0d58e45d70f2`.
The R4 baseline was commit `3699b237a417413f3942736bbfa2bb229a2d6125`, with
concurrent uncommitted work; the solver and aircraft hashes identify this run
more precisely than that commit alone. No complete frozen worktree was retained.

The current [grid script](../../../../../research/avanti-s/av09-brake-audit/wheel_grid.gd)
and [rollout script](../../../../../research/avanti-s/av09-brake-audit/record_rollouts.gd)
hash to `ef872116a287be74c953db312776b4c619a81ba6f6cbcbe3dbbbcd377bf7894c`
and `c17d3fd605cb3729c90f6016f905816ac48bb935d9d0dcd4b3d4dbf7a867bea8`,
respectively. The checked-runner reports did not capture script hashes at run
time, so these identify the reviewed copies, not an independent byte check of
the executed scripts. The [artifact manifest](artifact-sha256.json) records
hashes and lengths for all 24 retained artifacts, including compressed and
uncompressed CSV bytes. All 24 entries and four gzip payloads were verified.

## Fixed-axle grid

The script calls the active `ground_wheels.gd` evaluator with the loaded
`main_left` profile: radius 0.04338 m, inertia 0.000055552 kg·m², relaxation
0.03 s, stock friction coefficient 0.8 and rolling coefficient 0.03. It replaces
support geometry to prescribe constant normal load and integrates wheel rim
speed with RK4 while holding the axle velocity fixed. It tests 384 combinations
of axle speed 1/3/10/20 m/s, normal load 1/10/40/80 N, brake demand
0/0.25/0.5/1, assumed capacity 0.1/1/10 N·m and friction factor 1/0.2;
two additional cases add 1 m/s lateral speed at 3 m/s, 40 N, full demand and
1 N·m. The friction factor scales grip alone, leaving rolling coefficient fixed;
it is not a complete wet-surface model. These are laboratory inputs, not
aircraft operating limits.

Each run lasts at least 1 s and ends when absolute rim acceleration falls below
`1e-7 m/s²` or after 5 s. The [240 Hz](grid/summary-240.json) and
[480 Hz](grid/summary-480.json) runs each completed 386 cases and eight
aggregate checks with zero failures. Both had 385 cases below the settling
threshold. Case 329 had 20 m/s axle speed, 40 N load, factor 0.2, 0.25 demand
and 1 N·m capacity; friction-circle and torque caps were active and its
acceleration was still approximately −0.001074 m/s² at 5 s in both runs. The check allows
that finite residual; it does not declare this case settled.

At 3 m/s, 40 N, factor 1 and full demand, capacities 0.1, 1 and 10 N·m all
give the same 1 s result at both rates: rim speed 1.5 m/s, tire slip force
−1.4760 N, rolling force −1.2 N and actual brake torque 0.06403 N·m. Both
relaxation slope caps are active while the friction-circle and torque clamps
are inactive. For the assumed 1 N·m capacity, 1/0.04338 = 23.05 N is a
nominal torque-over-radius capacity, not the observed tire force. This reproduces
the review's branch-specific prediction; it does not show that changing capacity
has no effect in other conditions.

The scripts reconstructed branch forces at the recorded sample points with
maximum absolute error `8.89e-15` in either run. Passive tire-slip, rolling,
lateral and brake powers were nonpositive at every evaluated RK stage, within
the `1e-10 W` check. The sampled force-work/wheel-energy closure error peaked at
`2.20e-4 J` at 240 Hz and `1.26e-5 J` at 480 Hz. Fixed axle motion is an
external constraint; this is not a closed vehicle energy balance. The retained
[240 Hz traces](grid/wheel-traces-240.csv.gz) and
[480 Hz traces](grid/wheel-traces-480.csv.gz) include force, torque, slip,
power, integrated work and limiter flags at selected ticks and each case endpoint.
Flags report which slope or saturation branch was active at that sample; they
are not a continuous trace of every RK stage.

## Coupled coast and brake recordings

The [manifest](rollouts/manifest.json) describes a converged default-field
runway pose with gear down and 50% fuel (initial mass 11.438578 kg). The script
then seeds 3 m/s body-forward velocity and matching wheel rim speeds, clears
contact anchors, and records two six-second, 240 Hz `FlightSession` runs from
the same restored checkpoint. Initial recorded numeric rows match and the
checked boundary covers body state, previous state, auxiliary and continuous
state, modes, inputs and tick. Initial wind is zero. Engine throttle command is
zero, but the turbine is running at 44,000 rpm: initial net thrust is 1.660 N.
The first accepted tick uses brake demand 0 for coast and 1 for brake; all
other commands start equal. Thus these are deliberately different input tapes,
not a same-tape comparison of two solver laws. The manifest's `gear_state` is
the final brake-run state; initial gear is down and its brake input is zero.

| First endpoint with `abs(u_mps) < 0.1` | Tick | Time | Horizontal displacement from start |
| --- | ---: | ---: | ---: |
| Coast | 1169 | 4.8708 s | 7.4870 m |
| Full brake | 967 | 4.0292 s | 5.8666 m |

Here `u_mps` is body-forward velocity; displacement is the straight-line NED
horizontal distance between the initial and threshold endpoints, not integrated
path length. These are first sampled threshold crossings, not zero-speed stops.
For example, at 0.5 s the brake run's left main-wheel slip force is −1.259 N,
rolling force −3.518 N and torque 0.0552 N·m; the wheel endpoint diagnostics
evaluate the accepted endpoint and are not the flight log's prior-step k1 loads.
See [wheel endpoints](rollouts/wheel-endpoints.csv), sampled every 24 ticks,
and the full [coast](rollouts/coast-replay.csv.gz) and
[brake](rollouts/brake-replay.csv.gz) replay CSVs.

Both [coast](rollouts/coast-replay.json) and [brake](rollouts/brake-replay.json)
self-replays report `status: ok`, `mode: exact`, `complete: true`,
`solver_changed: false` and 1,441 verified rows (initial sample plus 1,440
ticks). Their [recordings](rollouts/) and checked-runner reports retain the
input snapshots, markers, exact commands and engine logs. The rollout completed
13 checks with zero failures; the checked reports show no classified engine
errors. The logs also print an aircraft-data warning that the experimental
tabulated wing polar's provenance and aircraft-specific post-stall validation
need review.

This synthetic pose was not produced by an approach or touchdown, and no
independent real-aircraft measurements were used. It establishes neither
landing distance nor physical realism. It also does not establish rest/hold,
release and restart, touchdown spin-up, unloading, steering, native-backend
parity, or a GP-12 comparison. Those remain separate gates for a ground-law
change; the [AV-09 evidence](../README.md) and GP owners retain their scope.

## Reproduction

From the repository root in PowerShell, first match the aircraft, wheel profile,
solver and engine identities above and import the project if needed. These
commands use fresh output paths; they do not reproduce the original bytes if
inputs or recording metadata differ. Each checked report contains the exact
original argument list and verdict. Consult the [checked-runner guide](../../../../../tools/godot/README.md)
and [flight-log workflow](../../../../FLIGHT-LOGGING.md) for their contracts.

```powershell
$GodotWindows = (Resolve-Path '.tools/Godot_v4.8-beta2_win64_console.exe').Path
$Root = (Get-Location).Path.Replace('\', '/')
$Run = "$Root/tmp/av09-r2-$([guid]::NewGuid().ToString('N'))"
$Grid = "$Root/research/avanti-s/av09-brake-audit/wheel_grid.gd"
$Rollout = "$Root/research/avanti-s/av09-brake-audit/record_rollouts.gd"
foreach ($Hz in 240, 480) {
  python tools/godot/run_checked.py --out-dir "$Run/checks" --label "grid-$Hz" --timeout 300 --require-text 'AV09_WHEEL_GRID 386 cases, 8 checks, 0 failures' -- $GodotWindows --headless --path app --audio-driver Dummy --script $Grid -- "--out=$Run/grid-$Hz" "--hz=$Hz"
  if ($LASTEXITCODE -ne 0) { throw "Grid $Hz failed; inspect its report and log" }
}
python tools/godot/run_checked.py --out-dir "$Run/checks" --label rollout --timeout 300 --require-text 'AV09_ROLLOUT 13 checks, 0 failures' -- $GodotWindows --headless --path app --audio-driver Dummy --script $Rollout -- "--out=$Run/rollouts"
if ($LASTEXITCODE -ne 0) { throw 'Rollout failed; inspect its report and log' }
foreach ($Name in 'coast', 'brake') {
  python tools/godot/run_checked.py --out-dir "$Run/checks" --label "replay-$Name" --timeout 300 --require-text 'Flight log exact: 1441 rows verified.' -- $GodotWindows --headless --path app --audio-driver Dummy --script res://tools/flight_log_cli.gd -- "--log=$Run/rollouts/$Name.orfl" "--csv=$Run/rollouts/$Name-replay.csv" "--report=$Run/rollouts/$Name-replay.json" --replay
  if ($LASTEXITCODE -ne 0) { throw "Replay $Name failed; inspect its report and log" }
}
```

Check the two replay JSON reports for completion, exact mode and unchanged
solver as well as the runner verdicts. The grid summary's zero failures alone
does not mean every case settled. Required CI and physical validation were not
run as part of this characterization.
